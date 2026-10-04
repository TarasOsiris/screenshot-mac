import Foundation

nonisolated enum GooglePlayAPIOrigin: StoreAPIOrigin {
    static func httpErrorDescription(status: Int, message: String) -> String {
        String(localized: "Google Play returned \(status): \(message)")
    }
}

typealias GooglePlayAPIError = StoreAPIError<GooglePlayAPIOrigin>

/// Thin wrapper over the Google Play Android Publisher API v3 (raw URLSession, no SDK).
/// Mirrors `AppStoreConnectAPIService`: bearer auth, JSON error extraction, and a demo
/// mode that short-circuits every call so App Review / dev can walk the flow offline.
final class GooglePlayAPIService: StoreDemoPacing {
    static let shared = GooglePlayAPIService()

    private static let baseURL = "https://androidpublisher.googleapis.com"
    private static let decoder = JSONDecoder()

    private let auth: GooglePlayAuthService
    private let session: URLSession
    private let credentials: GooglePlayCredentialsStore
    private let http: StoreHTTPClient
    private let demoData: GooglePlayDemoData

    init(auth: GooglePlayAuthService = .shared,
         session: URLSession = StoreHTTPClient.sharedSession,
         credentials: GooglePlayCredentialsStore = .shared,
         demoData: GooglePlayDemoData = .shared) {
        self.auth = auth
        self.session = session
        self.credentials = credentials
        self.demoData = demoData
        self.http = StoreHTTPClient(
            baseURL: Self.baseURL,
            session: session,
            bearerToken: { [auth] in try await auth.token() },
            errorMessage: Self.extractErrorMessage
        )
    }

    private var isDemoMode: Bool { credentials.isDemoMode }

    /// Validates the credential by exchanging the JWT for an access token (no package needed).
    func testConnection() async throws -> String {
        if isDemoMode {
            await demoDelay()
            return String(localized: "Connected (Demo Mode). No traffic is sent to Google.")
        }
        _ = try await auth.token()
        let email = credentials.clientEmail ?? "service account"
        return String(localized: "Connected. Authorized as \(email).")
    }

    // MARK: - Edits

    func insertEdit(packageName: String) async throws -> GPEdit {
        if isDemoMode {
            await demoDelay()
            return demoData.insertEdit()
        }
        return try await request(method: "POST", path: "/androidpublisher/v3/applications/\(packageName)/edits")
    }

    /// Commits the edit. Returns whether the changes were sent for review (`true`) or held as an
    /// un-reviewed draft (`false`).
    ///
    /// `sendForReview == true` omits the flag (Google sends all changes for review on commit).
    /// `sendForReview == false` adds `changesNotSentForReview=true` to hold them as a draft. Some
    /// app states reject that flag with a 400 ("must not be set") — we let that error propagate
    /// rather than retrying without the flag: committing without it sends the changes to review,
    /// which for a published app can push the live listing live, so it must be an explicit choice.
    @discardableResult
    func commitEdit(packageName: String, editId: String, sendForReview: Bool) async throws -> Bool {
        if isDemoMode { await demoDelay(); return sendForReview }
        let base = "/androidpublisher/v3/applications/\(packageName)/edits/\(editId):commit"
        let path = sendForReview ? base : "\(base)?changesNotSentForReview=true"
        _ = try await rawRequest(method: "POST", path: path, body: nil, contentType: nil)
        return sendForReview
    }

    /// Checks that this service account can actually edit this package, before the wizard commits
    /// the user to a plan built against it.
    ///
    /// The Play Developer API has no "does this app exist" call and no way to list the apps a
    /// service account can reach — everything is keyed by package name — so opening a draft edit
    /// and discarding it is the check. That writes server state, so it belongs on an explicit
    /// action, never on a keystroke.
    func verifyPackage(packageName: String) async throws {
        if isDemoMode {
            await demoDelay()
            return
        }
        let edit = try await insertEdit(packageName: packageName)
        // A failure to clean up doesn't invalidate the answer: Play expires abandoned edits.
        try? await deleteEdit(packageName: packageName, editId: edit.id)
    }

    /// The read shares the upload's per-hour API quota, so it trickles rather than bursting.
    static let screenshotCountConcurrency = 4

    /// Listing screenshots per language and image type, via a throwaway edit; failed languages are left out.
    func screenshotCounts(packageName: String, languages: [String]) async throws -> [String: [String: Int]] {
        if isDemoMode {
            await demoDelay()
            return demoData.screenshotCounts(languages: languages)
        }
        let edit = try await insertEdit(packageName: packageName)
        let requests = languages.flatMap { language in GPImageType.userSelectableCases.map { (language, $0.apiValue) } }
        var counts: [String: [String: Int]] = [:]
        var failedLanguages = Set<String>()
        await withTaskGroup(of: (String, String, Int?).self) { group in
            var queue = requests.makeIterator()
            func startNext() {
                guard let (language, imageType) = queue.next() else { return }
                group.addTask {
                    let count = try? await self.imageCount(packageName: packageName, editId: edit.id, language: language, imageType: imageType)
                    return (language, imageType, count)
                }
            }
            for _ in 0..<Self.screenshotCountConcurrency { startNext() }
            for await (language, imageType, count) in group {
                if let count { counts[language, default: [:]][imageType] = count } else { failedLanguages.insert(language) }
                startNext()
            }
        }
        try? await deleteEdit(packageName: packageName, editId: edit.id)
        for language in failedLanguages { counts[language] = nil }
        return counts
    }

    /// A language with no listing answers 404, which means it has no screenshots.
    private func imageCount(packageName: String, editId: String, language: String, imageType: String) async throws -> Int {
        let path = "/androidpublisher/v3/applications/\(packageName)/edits/\(editId)/listings/\(language)/\(imageType)"
        do {
            let response: GPImagesListResponse = try await request(method: "GET", path: path)
            return response.images?.count ?? 0
        } catch let error as GooglePlayAPIError where error.httpStatus == 404 {
            return 0
        }
    }

    /// Only ever cleanup, so it runs unstructured: inside a cancelled caller the retry policy
    /// would throw before the DELETE is sent and leave the edit open in the Play Console.
    func deleteEdit(packageName: String, editId: String) async throws {
        if isDemoMode { await demoDelay(); return }
        let path = "/androidpublisher/v3/applications/\(packageName)/edits/\(editId)"
        _ = try await Task { try await rawRequest(method: "DELETE", path: path, body: nil, contentType: nil) }.value
    }

    // MARK: - Images

    func deleteAllImages(packageName: String, editId: String, language: String, imageType: String) async throws {
        if isDemoMode {
            await demoDelay()
            demoData.deleteAllImages(language: language, imageType: imageType)
            return
        }
        let path = "/androidpublisher/v3/applications/\(packageName)/edits/\(editId)/listings/\(language)/\(imageType)"
        _ = try await rawRequest(method: "DELETE", path: path, body: nil, contentType: nil)
    }

    @discardableResult
    func uploadImage(packageName: String, editId: String, language: String, imageType: String, fileName: String, png: Data) async throws -> GPImage {
        if isDemoMode {
            await demoDelay()
            return demoData.uploadImage(language: language, imageType: imageType)
        }
        let path = "/upload/androidpublisher/v3/applications/\(packageName)/edits/\(editId)/listings/\(language)/\(imageType)?uploadType=media"
        let data = try await rawRequest(method: "POST", path: path, body: png, contentType: "image/png", fileName: fileName)
        return try GooglePlayAPIError.decode(GPImageUploadResponse.self, from: data, using: Self.decoder).image
    }

    // MARK: - HTTP

    private func request<T: Decodable>(method: String, path: String) async throws -> T {
        let data = try await rawRequest(method: method, path: path, body: nil, contentType: nil)
        return try GooglePlayAPIError.decode(T.self, from: data, using: Self.decoder)
    }

    private func rawRequest(method: String, path: String, body: Data?, contentType: String?, fileName: String? = nil) async throws -> Data {
        // Google's upload backend reads the display name from Content-Disposition; without it
        // every uploaded image shows as "image".
        let headers = fileName.map { ["Content-Disposition": "attachment; filename=\"\($0)\""] } ?? [:]
        do {
            return try await http.data(
                method: method,
                path: path,
                body: body,
                contentType: contentType,
                extraHeaders: headers
            )
        } catch let error as StoreHTTPError {
            throw GooglePlayAPIError(error)
        }
    }

    nonisolated private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }
        if let message = error["message"] as? String, !message.isEmpty { return message }
        if let status = error["status"] as? String, !status.isEmpty { return status }
        return nil
    }
}

// MARK: - DTOs

struct GPEdit: Decodable {
    let id: String
    let expiryTimeSeconds: String?
}

struct GPImage: Decodable {
    let id: String?
    let url: String?
    let sha256: String?
    let sha1: String?
}

private struct GPImagesListResponse: Decodable {
    let images: [GPImage]?
}

private struct GPImageUploadResponse: Decodable {
    let image: GPImage
}

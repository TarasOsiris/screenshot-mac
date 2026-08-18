import Foundation

enum GooglePlayAPIError: Error, LocalizedError {
    case invalidURL
    case httpError(status: Int, message: String)
    case decodingFailed(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid request URL.")
        case .httpError(let status, let message):
            return String(localized: "Google Play returned \(status): \(message)")
        case .decodingFailed(let error):
            return String(localized: "Response decoding failed: \(error.localizedDescription)")
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

/// Thin wrapper over the Google Play Android Publisher API v3 (raw URLSession, no SDK).
/// Mirrors `AppStoreConnectAPIService`: bearer auth, JSON error extraction, and a demo
/// mode that short-circuits every call so App Review / dev can walk the flow offline.
final class GooglePlayAPIService {
    static let shared = GooglePlayAPIService()

    private static let baseURL = "https://androidpublisher.googleapis.com"
    private static let decoder = JSONDecoder()

    private let auth: GooglePlayAuthService
    private let session: URLSession
    private let credentials: GooglePlayCredentialsStore
    private let demoData: GooglePlayDemoData

    init(auth: GooglePlayAuthService = .shared,
         session: URLSession = .shared,
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

    private var http: StoreHTTPClient!

    /// Maps transport failures onto this service's own error type, so every localized string
    /// stays exactly where it is.
    private static func mapped(_ error: StoreHTTPError) -> GooglePlayAPIError {
        switch error {
        case .invalidURL: .invalidURL
        case .nonHTTPResponse: .httpError(status: -1, message: "Non-HTTP response")
        case .status(let status, let message): .httpError(status: status, message: message ?? "HTTP \(status)")
        case .transport(let underlying): .transport(underlying)
        }
    }

    private var isDemoMode: Bool { credentials.isDemoMode }

    private func demoDelay() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

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

    func deleteEdit(packageName: String, editId: String) async throws {
        if isDemoMode { await demoDelay(); return }
        let path = "/androidpublisher/v3/applications/\(packageName)/edits/\(editId)"
        _ = try await rawRequest(method: "DELETE", path: path, body: nil, contentType: nil)
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
        do {
            return try Self.decoder.decode(GPImageUploadResponse.self, from: data).image
        } catch {
            throw GooglePlayAPIError.decodingFailed(error)
        }
    }

    // MARK: - HTTP

    private func request<T: Decodable>(method: String, path: String) async throws -> T {
        let data = try await rawRequest(method: method, path: path, body: nil, contentType: nil)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw GooglePlayAPIError.decodingFailed(error)
        }
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
            throw Self.mapped(error)
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

private struct GPImageUploadResponse: Decodable {
    let image: GPImage
}

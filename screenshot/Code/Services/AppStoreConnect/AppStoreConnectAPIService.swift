import Foundation

enum AppStoreConnectAPIError: Error, LocalizedError {
    case invalidURL
    case httpError(status: Int, message: String)
    case decodingFailed(Error)
    case transport(Error)

    var httpStatus: Int? {
        if case let .httpError(status, _) = self { return status }
        return nil
    }

    var isDecodingFailure: Bool {
        if case .decodingFailed = self { return true }
        return false
    }

    var transportError: Error? {
        if case let .transport(underlying) = self { return underlying }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid request URL.")
        case .httpError(let status, let message):
            return String(localized: "App Store Connect returned \(status): \(message)")
        case .decodingFailed(let error):
            return String(localized: "Response decoding failed: \(error.localizedDescription)")
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

final class AppStoreConnectAPIService {
    static let shared = AppStoreConnectAPIService()

    private static let baseURL = "https://api.appstoreconnect.apple.com"
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private let auth: AppStoreConnectAuthService
    private let session: URLSession
    private let credentials: AppStoreConnectCredentialsStore
    private let http: StoreHTTPClient
    private let demoData: AppStoreConnectDemoData

    let retryPolicy: StoreRetryPolicy

    init(auth: AppStoreConnectAuthService = .shared,
         session: URLSession = StoreHTTPClient.sharedSession,
         credentials: AppStoreConnectCredentialsStore = .shared,
         demoData: AppStoreConnectDemoData = .shared,
         retryPolicy: StoreRetryPolicy = StoreRetryPolicy()) {
        self.retryPolicy = retryPolicy
        self.auth = auth
        self.session = session
        self.credentials = credentials
        self.demoData = demoData
        self.http = StoreHTTPClient(
            baseURL: Self.baseURL,
            session: session,
            bearerToken: { [auth] in try auth.token() },
            errorMessage: Self.extractErrorMessage,
            retryPolicy: retryPolicy
        )
    }

    /// Maps transport failures onto this service's own error type, so every localized string
    /// stays exactly where it is.
    private static func mapped(_ error: StoreHTTPError) -> AppStoreConnectAPIError {
        switch error {
        case .invalidURL: .invalidURL
        case .nonHTTPResponse: .httpError(status: -1, message: "Non-HTTP response")
        case .status(let status, let message): .httpError(status: status, message: message ?? "HTTP \(status)")
        case .transport(let underlying): .transport(underlying)
        }
    }

    private var isDemoMode: Bool { credentials.isDemoMode }

    /// Short pause so the upload wizard's progress UI animates believably in demo mode.
    /// Kept small because real upload flows make ~6 sequential calls per (template × locale).
    private func demoDelay() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    func testConnection() async throws -> String {
        if isDemoMode {
            await demoDelay()
            let name = demoData.apps.first?.attributes.name ?? "Demo App"
            return String(localized: "Connected (Demo Mode). Sample app: \(name).")
        }
        let response: ASCListResponse<ASCApp> = try await get("/v1/apps?limit=1")
        if let first = response.data.first {
            return String(localized: "Connected. First app: \(first.attributes.name)")
        }
        return String(localized: "Connected. No apps found on this account yet.")
    }

    // MARK: - Apps / versions / localizations

    func listApps(limit: Int = 200) async throws -> [ASCApp] {
        if isDemoMode {
            await demoDelay()
            return demoData.apps
        }
        let response: ASCListResponse<ASCApp> = try await get("/v1/apps?limit=\(limit)&sort=name")
        return response.data
    }

    /// Lists apps with their App Store versions inlined via JSON:API `?include`.
    /// One round-trip instead of N+1 — used by the upload wizard to pre-compute
    /// which apps have a version that can accept screenshot uploads (so the picker can hide locked ones).
    func listAppsWithVersions(limit: Int = 200) async throws -> [ASCAppWithVersions] {
        if isDemoMode {
            await demoDelay()
            return demoData.apps.map { app in
                ASCAppWithVersions(app: app, versions: demoData.versions(forApp: app.id))
            }
        }
        let path = "/v1/apps?limit=\(limit)&sort=name"
            + "&include=appStoreVersions"
            + "&fields%5BappStoreVersions%5D=appStoreState,versionString,platform"
        let response: ASCAppListWithVersionsResponse = try await get(path)
        let versionsById: [String: ASCAppStoreVersion] = Dictionary(
            uniqueKeysWithValues: (response.included ?? []).compactMap { item in
                guard item.type == "appStoreVersions",
                      let attributes = item.attributes else { return nil }
                return (item.id, ASCAppStoreVersion(id: item.id, attributes: attributes))
            }
        )
        return response.data.map { row in
            let versionIds = row.relationships?.appStoreVersions?.data?.map(\.id) ?? []
            let versions = versionIds.compactMap { versionsById[$0] }
            return ASCAppWithVersions(
                app: ASCApp(id: row.id, attributes: row.attributes),
                versions: versions
            )
        }
    }

    func listAppStoreVersions(appId: String, limit: Int = 20) async throws -> [ASCAppStoreVersion] {
        if isDemoMode {
            await demoDelay()
            return demoData.versions(forApp: appId)
        }
        let path = "/v1/apps/\(appId)/appStoreVersions?limit=\(limit)"
        let response: ASCListResponse<ASCAppStoreVersion> = try await get(path)
        return response.data
    }

    func listLocalizations(versionId: String, limit: Int = 200) async throws -> [ASCAppStoreVersionLocalization] {
        if isDemoMode {
            await demoDelay()
            return demoData.versionLocalizations(forVersion: versionId)
        }
        let path = "/v1/appStoreVersions/\(versionId)/appStoreVersionLocalizations?limit=\(limit)"
        let response: ASCListResponse<ASCAppStoreVersionLocalization> = try await get(path)
        return response.data
    }

    // MARK: - Metadata (editing)

    func listAppInfos(appId: String) async throws -> [ASCAppInfo] {
        if isDemoMode {
            await demoDelay()
            return demoData.appInfos(forApp: appId)
        }
        let path = "/v1/apps/\(appId)/appInfos"
        let response: ASCListResponse<ASCAppInfo> = try await get(path)
        return response.data
    }

    func listAppInfoLocalizations(appInfoId: String, limit: Int = 200) async throws -> [ASCAppInfoLocalization] {
        if isDemoMode {
            await demoDelay()
            return demoData.appInfoLocalizations(forAppInfo: appInfoId)
        }
        let path = "/v1/appInfos/\(appInfoId)/appInfoLocalizations?limit=\(limit)"
        let response: ASCListResponse<ASCAppInfoLocalization> = try await get(path)
        return response.data
    }

    func updateVersionLocalization(id: String, attributes: [String: AnyEncodable]) async throws {
        if isDemoMode { await demoDelay(); return }
        try await updateResource(type: "appStoreVersionLocalizations", id: id, attributes: attributes)
    }

    func updateAppInfoLocalization(id: String, attributes: [String: AnyEncodable]) async throws {
        if isDemoMode { await demoDelay(); return }
        try await updateResource(type: "appInfoLocalizations", id: id, attributes: attributes)
    }

    func updateAppStoreVersion(id: String, attributes: [String: AnyEncodable]) async throws {
        if isDemoMode { await demoDelay(); return }
        try await updateResource(type: "appStoreVersions", id: id, attributes: attributes)
    }

    private func updateResource(type: String, id: String, attributes: [String: AnyEncodable]) async throws {
        guard !attributes.isEmpty else { return }
        let body = ASCResourceUpdate(
            data: ASCResourceUpdate.Payload(type: type, id: id, attributes: attributes)
        )
        _ = try await rawRequest(method: "PATCH", path: "/v1/\(type)/\(id)", body: body)
    }

    // MARK: - Screenshot sets

    func listScreenshotSets(localizationId: String, limit: Int = 50) async throws -> [ASCAppScreenshotSet] {
        if isDemoMode {
            await demoDelay()
            return demoData.screenshotSets(localizationId: localizationId)
        }
        let path = "/v1/appStoreVersionLocalizations/\(localizationId)/appScreenshotSets?limit=\(limit)"
        let response: ASCListResponse<ASCAppScreenshotSet> = try await get(path)
        return response.data
    }

    func createScreenshotSet(localizationId: String, displayType: String) async throws -> ASCAppScreenshotSet {
        if isDemoMode {
            await demoDelay()
            return demoData.createScreenshotSet(localizationId: localizationId, displayType: displayType)
        }
        let body = ASCResourceCreate(
            data: ASCResourceCreate.Payload(
                type: "appScreenshotSets",
                attributes: ["screenshotDisplayType": AnyEncodable(displayType)],
                relationships: [
                    "appStoreVersionLocalization": AnyEncodable(
                        ASCRelationship.single(type: "appStoreVersionLocalizations", id: localizationId)
                    )
                ]
            )
        )
        let response: ASCSingleResponse<ASCAppScreenshotSet> = try await post("/v1/appScreenshotSets", body: body)
        return response.data
    }

    func deleteScreenshotSet(id: String) async throws {
        if isDemoMode {
            await demoDelay()
            demoData.deleteScreenshotSet(id: id)
            return
        }
        try await delete("/v1/appScreenshotSets/\(id)")
    }

    // MARK: - Screenshots (reserve / upload / commit)

    func listScreenshots(
        setId: String,
        limit: Int = 50,
        retryPolicy: StoreRetryPolicy? = nil
    ) async throws -> [ASCAppScreenshot] {
        if isDemoMode { await demoDelay(); return [] }
        let fields = "fileSize,fileName,sourceFileChecksum,imageAsset,assetToken,assetType,assetDeliveryState"
        let path = "/v1/appScreenshotSets/\(setId)/appScreenshots?limit=\(limit)&fields%5BappScreenshots%5D=\(fields)"
        let response: ASCListResponse<ASCAppScreenshot> = try await get(path, retryPolicy: retryPolicy)
        return response.data
    }

    /// `retryPolicy` is `.singleAttempt` at the delivery/verify poll loops, which retry already.
    func screenshot(id: String, retryPolicy: StoreRetryPolicy? = nil) async throws -> ASCAppScreenshot {
        if isDemoMode {
            await demoDelay()
            throw AppStoreConnectAPIError.httpError(status: 404, message: "Demo screenshot not found")
        }
        let fields = "fileSize,fileName,sourceFileChecksum,imageAsset,assetToken,assetType,assetDeliveryState"
        let response: ASCSingleResponse<ASCAppScreenshot> = try await get(
            "/v1/appScreenshots/\(id)?fields%5BappScreenshots%5D=\(fields)",
            retryPolicy: retryPolicy
        )
        return response.data
    }

    func listScreenshotOrder(setId: String) async throws -> [String] {
        if isDemoMode { await demoDelay(); return [] }
        let response: ASCRelationshipListResponse = try await get(
            "/v1/appScreenshotSets/\(setId)/relationships/appScreenshots?limit=50"
        )
        return response.data.map(\.id)
    }

    func setScreenshotOrder(setId: String, screenshotIds: [String]) async throws {
        if isDemoMode { await demoDelay(); return }
        let body = ASCRelationshipListRequest(
            data: screenshotIds.map { ASCResourceReference(type: "appScreenshots", id: $0) }
        )
        _ = try await rawRequest(
            method: "PATCH",
            path: "/v1/appScreenshotSets/\(setId)/relationships/appScreenshots",
            body: body
        )
    }

    func downloadScreenshotData(_ screenshot: ASCAppScreenshot, maxDimension: Int? = nil) async throws -> Data {
        let resolvedScreenshot: ASCAppScreenshot
        if screenshot.attributes.imageAsset == nil {
            resolvedScreenshot = try await self.screenshot(id: screenshot.id)
        } else {
            resolvedScreenshot = screenshot
        }
        guard let imageAsset = resolvedScreenshot.attributes.imageAsset,
              let url = Self.resolvedImageAssetURL(
                imageAsset,
                fileName: resolvedScreenshot.attributes.fileName,
                maxDimension: maxDimension
              ) else {
            throw AppStoreConnectAPIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw AppStoreConnectAPIError.httpError(status: -1, message: "Non-HTTP image response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AppStoreConnectAPIError.httpError(
                    status: http.statusCode,
                    message: "Screenshot download failed"
                )
            }
            return data
        } catch let error as AppStoreConnectAPIError {
            throw error
        } catch {
            throw AppStoreConnectAPIError.transport(error)
        }
    }

    nonisolated static func resolvedImageAssetURL(
        _ asset: ASCImageAsset,
        fileName: String?,
        maxDimension: Int? = nil
    ) -> URL? {
        guard asset.width > 0, asset.height > 0 else { return nil }
        var width = asset.width
        var height = asset.height
        // The template host renders whatever {w}x{h} we ask for, so requesting a thumbnail
        // here avoids pulling multi-MB source renditions just to draw a preview.
        if let maxDimension, maxDimension > 0, max(width, height) > maxDimension {
            let scale = Double(maxDimension) / Double(max(width, height))
            width = max(1, Int((Double(width) * scale).rounded()))
            height = max(1, Int((Double(height) * scale).rounded()))
        }
        let trimmedFileName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ext = URL(fileURLWithPath: trimmedFileName).pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "png"
        let resolved = asset.templateUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("{w}", with: String(width))
            .replacing("{h}", with: String(height))
            .replacing("{f}", with: ext)
        guard !resolved.contains("{"), !resolved.contains("}") else { return nil }
        guard let url = URL(string: resolved), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    func deleteScreenshot(id: String) async throws {
        if isDemoMode { await demoDelay(); return }
        try await delete("/v1/appScreenshots/\(id)")
    }

    func reserveScreenshot(setId: String, fileName: String, fileSize: Int) async throws -> ASCAppScreenshot {
        if isDemoMode {
            await demoDelay()
            return demoData.reserveScreenshot(setId: setId, fileName: fileName, fileSize: fileSize)
        }
        let attributes: [String: AnyEncodable] = [
            "fileName": AnyEncodable(fileName),
            "fileSize": AnyEncodable(fileSize)
        ]
        let body = ASCResourceCreate(
            data: ASCResourceCreate.Payload(
                type: "appScreenshots",
                attributes: attributes,
                relationships: [
                    "appScreenshotSet": AnyEncodable(
                        ASCRelationship.single(type: "appScreenshotSets", id: setId)
                    )
                ]
            )
        )
        let response: ASCSingleResponse<ASCAppScreenshot> = try await post("/v1/appScreenshots", body: body)
        return response.data
    }

    /// Chunk PUTs go straight to Apple's upload host rather than through `StoreHTTPClient`,
    /// which exists for bearer-authenticated JSON against a store's base URL and shares none of
    /// this. `repeatable` regardless of the verb Apple names: the operation pins the byte range,
    /// so a repeat overwrites the same bytes with the same content.
    func uploadChunk(operation: ASCUploadOperation, from fileData: Data) async throws {
        guard let url = URL(string: operation.url) else {
            throw AppStoreConnectAPIError.invalidURL
        }

        let lower = operation.offset
        let upper = min(operation.offset + operation.length, fileData.count)
        var request = URLRequest(url: url)
        request.httpMethod = operation.method
        for header in operation.requestHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        // Slicing a multi-MB buffer is pure CPU — run it off the main actor.
        request.httpBody = await Self.slice(of: fileData, from: lower, to: upper)

        try await retryPolicy.attempting {
            let http: HTTPURLResponse
            do {
                let (_, response) = try await session.data(for: request)
                guard let received = response as? HTTPURLResponse else {
                    throw AppStoreConnectAPIError.httpError(status: -1, message: "Non-HTTP response")
                }
                http = received
            } catch let error as AppStoreConnectAPIError {
                throw error
            } catch {
                guard retryPolicy.allowsRetry(transportError: error, repeatable: true) else {
                    throw AppStoreConnectAPIError.transport(error)
                }
                throw StoreRetryPolicy.Retryable(underlying: AppStoreConnectAPIError.transport(error))
            }

            if (200..<300).contains(http.statusCode) { return }
            let failure = AppStoreConnectAPIError.httpError(
                status: http.statusCode, message: "Upload chunk failed"
            )
            guard retryPolicy.allowsRetry(status: http.statusCode, repeatable: true) else { throw failure }
            throw StoreRetryPolicy.Retryable(
                underlying: failure,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
    }

    /// `@concurrent` is load-bearing — see the concurrency note in CLAUDE.md.
    @concurrent nonisolated private static func slice(of data: Data, from lower: Int, to upper: Int) async -> Data {
        data.subdata(in: lower..<upper)
    }

    func commitScreenshot(id: String, md5Checksum: String) async throws {
        if isDemoMode { await demoDelay(); return }
        let attributes: [String: AnyEncodable] = [
            "uploaded": AnyEncodable(true),
            "sourceFileChecksum": AnyEncodable(md5Checksum)
        ]
        let body = ASCResourceUpdate(
            data: ASCResourceUpdate.Payload(
                type: "appScreenshots",
                id: id,
                attributes: attributes
            )
        )
        let _: ASCSingleResponse<ASCAppScreenshot> = try await patch("/v1/appScreenshots/\(id)", body: body)
    }

    // MARK: - HTTP helpers

    func get<T: Decodable>(_ path: String, retryPolicy: StoreRetryPolicy? = nil) async throws -> T {
        try await request(method: "GET", path: path, body: Optional<Data>.none, retryPolicy: retryPolicy)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await request(method: "POST", path: path, body: body)
    }

    func patch<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await request(method: "PATCH", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        _ = try await rawRequest(method: "DELETE", path: path, body: Optional<Data>.none)
    }

    private func request<Body: Encodable, T: Decodable>(
        method: String,
        path: String,
        body: Body?,
        retryPolicy: StoreRetryPolicy? = nil
    ) async throws -> T {
        let data = try await rawRequest(method: method, path: path, body: body, retryPolicy: retryPolicy)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw AppStoreConnectAPIError.decodingFailed(error)
        }
    }

    private func rawRequest<Body: Encodable>(
        method: String,
        path: String,
        body: Body?,
        retryPolicy: StoreRetryPolicy? = nil
    ) async throws -> Data {
        do {
            return try await http.data(
                method: method,
                path: path,
                body: try body.map { try Self.encoder.encode($0) },
                // Screenshot relationship reads verify writes made moments earlier; a cached
                // pre-mutation response would look like a failed order update.
                bypassCache: method == "GET",
                retryPolicy: retryPolicy
            )
        } catch let error as StoreHTTPError {
            throw Self.mapped(error)
        }
    }

    nonisolated private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]] else {
            return nil
        }
        let messages: [String] = errors.compactMap { error in
            let title = error["title"] as? String
            let detail = error["detail"] as? String
            return [title, detail].compactMap { $0 }.joined(separator: ": ").nonEmpty
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
}

private nonisolated extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Request bodies

// MARK: - ASC request bodies

private nonisolated struct ASCResourceCreate: Encodable {
    let data: Payload

    struct Payload: Encodable {
        let type: String
        let attributes: [String: AnyEncodable]?
        let relationships: [String: AnyEncodable]?
    }
}

private nonisolated struct ASCResourceUpdate: Encodable {
    let data: Payload

    struct Payload: Encodable {
        let type: String
        let id: String
        let attributes: [String: AnyEncodable]?
    }
}

private nonisolated struct ASCRelationship: Encodable {
    let data: Ref

    struct Ref: Encodable {
        let type: String
        let id: String
    }

    static func single(type: String, id: String) -> ASCRelationship {
        ASCRelationship(data: Ref(type: type, id: id))
    }
}

nonisolated struct ASCResourceReference: Codable, Sendable {
    let type: String
    let id: String
}

nonisolated struct ASCRelationshipListResponse: Decodable, Sendable {
    let data: [ASCResourceReference]
}

private nonisolated struct ASCRelationshipListRequest: Encodable {
    let data: [ASCResourceReference]
}

/// Tiny type-erasing wrapper so we can build heterogeneous JSON:API attribute dictionaries.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

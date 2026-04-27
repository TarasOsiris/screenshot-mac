import Foundation

enum AppStoreConnectAPIError: Error, LocalizedError {
    case invalidURL
    case httpError(status: Int, message: String)
    case decodingFailed(Error)
    case transport(Error)

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
    private let demoData: AppStoreConnectDemoData

    init(auth: AppStoreConnectAuthService = .shared,
         session: URLSession = .shared,
         credentials: AppStoreConnectCredentialsStore = .shared,
         demoData: AppStoreConnectDemoData = .shared) {
        self.auth = auth
        self.session = session
        self.credentials = credentials
        self.demoData = demoData
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

    func listScreenshots(setId: String, limit: Int = 50) async throws -> [ASCAppScreenshot] {
        let path = "/v1/appScreenshotSets/\(setId)/appScreenshots?limit=\(limit)"
        let response: ASCListResponse<ASCAppScreenshot> = try await get(path)
        return response.data
    }

    func deleteScreenshot(id: String) async throws {
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

    func uploadChunk(operation: ASCUploadOperation, from fileData: Data) async throws {
        guard let url = URL(string: operation.url) else {
            throw AppStoreConnectAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = operation.method
        for header in operation.requestHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let lower = operation.offset
        let upper = min(operation.offset + operation.length, fileData.count)
        let slice = fileData.subdata(in: lower..<upper)
        request.httpBody = slice

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AppStoreConnectAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectAPIError.httpError(status: -1, message: "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppStoreConnectAPIError.httpError(status: http.statusCode, message: "Upload chunk failed")
        }
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

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(method: "GET", path: path, body: Optional<Data>.none)
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
        body: Body?
    ) async throws -> T {
        let data = try await rawRequest(method: method, path: path, body: body)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw AppStoreConnectAPIError.decodingFailed(error)
        }
    }

    private func rawRequest<Body: Encodable>(
        method: String,
        path: String,
        body: Body?
    ) async throws -> Data {
        guard let url = URL(string: Self.baseURL + path) else {
            throw AppStoreConnectAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try auth.token()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppStoreConnectAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectAPIError.httpError(status: -1, message: "Non-HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw AppStoreConnectAPIError.httpError(
                status: http.statusCode,
                message: Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            )
        }

        return data
    }

    private static func extractErrorMessage(from data: Data) -> String? {
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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - ASC DTOs

struct ASCListResponse<T: Decodable>: Decodable {
    let data: [T]
}

struct ASCSingleResponse<T: Decodable>: Decodable {
    let data: T
}

struct ASCApp: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let bundleId: String
        let sku: String?
        let primaryLocale: String?
    }
}

enum ASCPlatform: String, CaseIterable {
    case ios = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"

    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        case .visionOS: return "visionOS"
        }
    }
}

struct ASCAppStoreVersion: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let versionString: String
        let appStoreState: String?
        let platform: String?
        let copyright: String?

        init(
            versionString: String,
            appStoreState: String?,
            platform: String?,
            copyright: String? = nil
        ) {
            self.versionString = versionString
            self.appStoreState = appStoreState
            self.platform = platform
            self.copyright = copyright
        }

        var displayState: String {
            guard let raw = appStoreState, !raw.isEmpty else { return String(localized: "not editable") }
            return raw.replacingOccurrences(of: "_", with: " ").lowercased()
        }

        var ascPlatform: ASCPlatform? {
            guard let platform, !platform.isEmpty else { return nil }
            return ASCPlatform(rawValue: platform)
        }

        var displayPlatform: String? {
            if let ascPlatform { return ascPlatform.displayName }
            guard let platform, !platform.isEmpty else { return nil }
            return platform.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var isEditable: Bool {
        switch attributes.appStoreState {
        case "PREPARE_FOR_SUBMISSION",
             "DEVELOPER_REJECTED",
             "REJECTED",
             "METADATA_REJECTED",
             "INVALID_BINARY",
             "WAITING_FOR_REVIEW",
             "IN_REVIEW":
            return true
        default:
            return false
        }
    }
}

struct ASCAppStoreVersionLocalization: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let locale: String
        let description: String?
        let keywords: String?
        let promotionalText: String?
        let whatsNew: String?
        let marketingUrl: String?
        let supportUrl: String?

        init(
            locale: String,
            description: String? = nil,
            keywords: String? = nil,
            promotionalText: String? = nil,
            whatsNew: String? = nil,
            marketingUrl: String? = nil,
            supportUrl: String? = nil
        ) {
            self.locale = locale
            self.description = description
            self.keywords = keywords
            self.promotionalText = promotionalText
            self.whatsNew = whatsNew
            self.marketingUrl = marketingUrl
            self.supportUrl = supportUrl
        }
    }
}

struct ASCAppInfo: Decodable, Identifiable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        let state: String?
        let appStoreState: String?

        init(state: String? = nil, appStoreState: String? = nil) {
            self.state = state
            self.appStoreState = appStoreState
        }
    }

    var effectiveState: String? {
        attributes?.state ?? attributes?.appStoreState
    }

    var isEditable: Bool {
        guard let state = effectiveState else { return false }
        return Self.editableStates.contains(state)
    }

    private static let editableStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW"
    ]
}

struct ASCAppInfoLocalization: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let locale: String
        let name: String?
        let subtitle: String?
        let privacyPolicyUrl: String?
        let privacyPolicyText: String?
        let privacyChoicesUrl: String?

        init(
            locale: String,
            name: String? = nil,
            subtitle: String? = nil,
            privacyPolicyUrl: String? = nil,
            privacyPolicyText: String? = nil,
            privacyChoicesUrl: String? = nil
        ) {
            self.locale = locale
            self.name = name
            self.subtitle = subtitle
            self.privacyPolicyUrl = privacyPolicyUrl
            self.privacyPolicyText = privacyPolicyText
            self.privacyChoicesUrl = privacyChoicesUrl
        }
    }
}

struct ASCAppScreenshotSet: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let screenshotDisplayType: String?
    }
}

struct ASCAppScreenshot: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let fileName: String?
        let fileSize: Int?
        let uploaded: Bool?
        let sourceFileChecksum: String?
        let uploadOperations: [ASCUploadOperation]?
    }
}

struct ASCUploadOperation: Decodable {
    let method: String
    let url: String
    let length: Int
    let offset: Int
    let requestHeaders: [ASCUploadHeader]
}

struct ASCUploadHeader: Decodable {
    let name: String
    let value: String
}

// MARK: - ASC request bodies

private struct ASCResourceCreate: Encodable {
    let data: Payload

    struct Payload: Encodable {
        let type: String
        let attributes: [String: AnyEncodable]?
        let relationships: [String: AnyEncodable]?
    }
}

private struct ASCResourceUpdate: Encodable {
    let data: Payload

    struct Payload: Encodable {
        let type: String
        let id: String
        let attributes: [String: AnyEncodable]?
    }
}

private struct ASCRelationship: Encodable {
    let data: Ref

    struct Ref: Encodable {
        let type: String
        let id: String
    }

    static func single(type: String, id: String) -> ASCRelationship {
        ASCRelationship(data: Ref(type: type, id: id))
    }
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

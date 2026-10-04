import Foundation
@testable import Screenshot_Bro
import Security
import Testing

/// One request the service sent to the Android Publisher API (token exchanges excluded).
nonisolated private struct PlayCall: Sendable, Equatable {
    let method: String
    let path: String
    let query: String?
    let fileName: String?

    var route: String { "\(method) \(path)" }
}

/// Answers every request with a plausible Play response unless `responder` returns one.
nonisolated private final class PlayStubServer: @unchecked Sendable {
    typealias Responder = @Sendable (_ call: PlayCall, _ earlier: [PlayCall]) -> (Int, String)?

    static let tokenHost = "oauth2.test"

    private let lock = NSLock()
    private var recorded: [PlayCall] = []
    private let responder: Responder?

    init(responder: Responder?) { self.responder = responder }

    var calls: [PlayCall] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func respond(to request: URLRequest) -> (Int, String) {
        guard let url = request.url else { return (400, "{}") }
        if url.host() == Self.tokenHost {
            return (200, #"{"access_token":"test-token","expires_in":3600}"#)
        }
        let disposition = request.value(forHTTPHeaderField: "Content-Disposition")
        let call = PlayCall(
            method: request.httpMethod ?? "GET",
            path: url.path(percentEncoded: false),
            query: url.query(percentEncoded: false),
            fileName: disposition?.split(separator: "\"").dropFirst().first.map(String.init)
        )
        lock.lock()
        let earlier = recorded
        recorded.append(call)
        lock.unlock()

        if let answer = responder?(call, earlier) { return answer }
        if call.method == "POST", call.path.hasSuffix("/edits") { return (200, #"{"id":"edit-1"}"#) }
        if call.path.hasPrefix("/upload/") { return (200, #"{"image":{"id":"img"}}"#) }
        return (200, "{}")
    }
}

nonisolated private final class PlayStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var server: PlayStubServer?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = Self.server, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, body) = server.respond(to: request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private final class ProgressLog {
    var entries: [UploadProgress] = []
}

@MainActor
private final class TaskHolder {
    var task: Task<Bool, Error>?
}

// The real `GooglePlayAPIService` over a stubbed URLSession, so the service's request order,
// retry and rollback are pinned at the wire rather than against a hand-written fake.
@Suite(.serialized)
@MainActor
struct GooglePlayUploadServiceTests {

    private final class Harness {
        let service: GooglePlayUploadService
        let server: PlayStubServer

        init(responder: PlayStubServer.Responder? = nil) throws {
            server = PlayStubServer(responder: responder)
            PlayStubProtocol.server = server

            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [PlayStubProtocol.self]
            let session = URLSession(configuration: config)

            let credentials = GooglePlayCredentialsStore.isolatedForTesting()
            try credentials.saveServiceAccount(json: try GooglePlayUploadServiceTests.serviceAccountJSON())
            let api = GooglePlayAPIService(
                auth: GooglePlayAuthService(credentials: credentials, session: session),
                session: session,
                credentials: credentials,
                demoData: GooglePlayDemoData()
            )
            service = GooglePlayUploadService(
                api: api,
                retryPolicy: StoreRetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .milliseconds(2))
            )
        }
    }

    private static var cachedServiceAccountJSON: String?

    /// Token minting really signs, so the credential needs a real RSA key.
    private static func serviceAccountJSON() throws -> String {
        if let cached = cachedServiceAccountJSON { return cached }
        var error: Unmanaged<CFError>?
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(try makeTestRSAPrivateKey(), &error) as Data?)
        let pem = pemEncoded(pkcs1, label: "RSA PRIVATE KEY")
        let object = [
            "client_email": "uploader@example.iam.gserviceaccount.com",
            "private_key": pem,
            "token_uri": "https://\(PlayStubServer.tokenHost)/token"
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        cachedServiceAccountJSON = json
        return json
    }

    // MARK: - Fixtures

    private let packageName = "com.example.app"
    private let english = GPUploadLanguage(projectCode: "en", playCode: "en-US", label: "English")
    private let german = GPUploadLanguage(projectCode: "de", playCode: "de-DE", label: "German")

    private var editsPath: String { "/androidpublisher/v3/applications/\(packageName)/edits" }
    private var openEdit: String { "POST \(editsPath)" }
    private var abandonEdit: String { "DELETE \(editsPath)/edit-1" }
    private var commitEdit: String { "POST \(editsPath)/edit-1:commit" }
    private func clearListing(_ language: GPUploadLanguage) -> String {
        "DELETE \(editsPath)/edit-1/listings/\(language.playCode)/phoneScreenshots"
    }
    private func uploadImage(_ language: GPUploadLanguage) -> String {
        "POST /upload\(editsPath)/edit-1/listings/\(language.playCode)/phoneScreenshots"
    }

    private func makeRow(templates: Int) -> ScreenshotRow {
        makeTestRow(label: "Hero", width: 90, height: 160, templateCount: templates)
    }

    private func makeTarget(_ row: ScreenshotRow, _ languages: [GPUploadLanguage]) -> GPUploadTarget {
        GPUploadTarget(
            rowId: row.id,
            rowLabel: row.label,
            rowSize: CGSize(width: row.templateWidth, height: row.templateHeight),
            imageType: .phoneScreenshots,
            languages: languages,
            templateCount: row.templates.count
        )
    }

    @discardableResult
    private func upload(
        _ h: Harness,
        row: ScreenshotRow,
        languages: [GPUploadLanguage],
        sendForReview: Bool = true,
        source: (any RowRenderSource)? = nil,
        log: ProgressLog = ProgressLog()
    ) async throws -> Bool {
        try await h.service.upload(
            packageName: packageName,
            targets: [makeTarget(row, languages)],
            sendForReview: sendForReview,
            rows: [row],
            source: source ?? StubGPDocument(rows: [row])
        ) { log.entries.append($0) }
    }

    private func missingImageDocument(_ row: ScreenshotRow) -> StubGPDocument {
        let document = StubGPDocument(rows: [row])
        document.referencedFileNames = ["gone.png"]
        return document
    }

    private func failureContext(_ error: Error?) -> GPUploadFailureContext? {
        guard case .requestFailed(let context)? = error as? GooglePlayUploadError else { return nil }
        return context
    }

    // MARK: - Success

    @Test func publishesEachLanguageClearThenUploadThenCommitsOnce() async throws {
        let h = try Harness()
        let row = makeRow(templates: 2)
        let log = ProgressLog()

        let sentForReview = try await upload(h, row: row, languages: [english, german], log: log)

        #expect(sentForReview)
        #expect(h.server.calls.map(\.route) == [
            openEdit,
            clearListing(english), uploadImage(english), uploadImage(english),
            clearListing(german), uploadImage(german), uploadImage(german),
            commitEdit,
        ])
        #expect(h.server.calls.last?.query == nil)
        #expect(h.server.calls.filter { $0.path.hasPrefix("/upload/") }.allSatisfy { $0.query == "uploadType=media" })

        let suffix = ExportFileNaming.preferredCustomSuffix
        let expectedNames = ["en", "de"].flatMap { code in
            (0..<2).map { ExportFileNaming.screenshotFileName(row: row, localeCode: code, index: $0, customSuffix: suffix) }
        }
        #expect(h.server.calls.compactMap(\.fileName) == expectedNames)

        let steps = log.entries.map(\.completedSteps)
        #expect(log.entries.allSatisfy { $0.totalSteps == 4 })
        #expect(steps == steps.sorted(), "progress must not rewind when nothing is retried")
        #expect(steps.last == 4)
    }

    @Test func holdingAsDraftCommitsWithTheNotSentForReviewFlag() async throws {
        let h = try Harness()

        let sentForReview = try await upload(h, row: makeRow(templates: 1), languages: [english], sendForReview: false)

        #expect(sentForReview == false)
        let commit = try #require(h.server.calls.last)
        #expect(commit.route == commitEdit)
        #expect(commit.query == "changesNotSentForReview=true")
    }

    // MARK: - Failure and rollback

    @Test func noTargetsFailsBeforeOpeningAnEdit() async throws {
        let h = try Harness()

        let error = await #expect(throws: (any Error).self) {
            try await h.service.upload(
                packageName: packageName, targets: [], sendForReview: true,
                rows: [], source: StubGPDocument()
            ) { _ in }
        }

        guard case .noRowsSelected? = error as? GooglePlayUploadError else {
            Issue.record("expected noRowsSelected, got \(String(describing: error))")
            return
        }
        #expect(h.server.calls.isEmpty)
    }

    /// No edit exists yet, so there is nothing to abandon.
    @Test func failingToOpenTheEditSendsNothingElse() async throws {
        let h = try Harness { call, _ in
            call.method == "POST" && call.path.hasSuffix("/edits") ? (403, #"{"error":{"message":"denied"}}"#) : nil
        }

        let error = await #expect(throws: (any Error).self) { try await upload(h, row: makeRow(templates: 1), languages: [english]) }

        let context = try #require(failureContext(error))
        #expect(context.operation == .openEdit)
        #expect(context.httpStatus == 403)
        #expect(h.server.calls.map(\.route) == [openEdit])
    }

    @Test func nonRetryableUploadFailureAbandonsTheEditWithoutCommitting() async throws {
        let h = try Harness { call, earlier in
            let priorUploads = earlier.filter { $0.path.hasPrefix("/upload/") }.count
            return call.path.hasPrefix("/upload/") && priorUploads == 1 ? (400, #"{"error":{"message":"bad image"}}"#) : nil
        }

        let error = await #expect(throws: (any Error).self) { try await upload(h, row: makeRow(templates: 2), languages: [english, german]) }

        let context = try #require(failureContext(error))
        #expect(context.operation == .uploadScreenshot(number: 2))
        #expect(context.httpStatus == 400)
        #expect(context.languageCode == "en-US")
        #expect(h.server.calls.map(\.route) == [
            openEdit, clearListing(english), uploadImage(english), uploadImage(english), abandonEdit,
        ])
    }

    @Test func unreadableImagesAbandonTheEditBeforeTouchingAnyListing() async throws {
        let h = try Harness()
        let row = makeRow(templates: 1)

        let error = await #expect(throws: (any Error).self) {
            try await upload(h, row: row, languages: [english], source: missingImageDocument(row))
        }

        guard case .unreadableImages(_, let languageLabel, let fileNames)? = error as? GooglePlayUploadError else {
            Issue.record("expected unreadableImages, got \(String(describing: error))")
            return
        }
        #expect(languageLabel == "English")
        #expect(fileNames == ["gone.png"])
        #expect(h.server.calls.map(\.route) == [openEdit, abandonEdit])
    }

    // MARK: - Retry

    /// A retry redoes the whole language from its clear, and progress rewinds to the language start.
    @Test func transientUploadFailureRepublishesTheLanguageFromItsClear() async throws {
        let h = try Harness { call, earlier in
            let priorUploads = earlier.filter { $0.path.hasPrefix("/upload/") }.count
            return call.path.hasPrefix("/upload/") && priorUploads == 1 ? (503, #"{"error":{"message":"backend"}}"#) : nil
        }
        let log = ProgressLog()

        try await upload(h, row: makeRow(templates: 2), languages: [english], log: log)

        #expect(h.server.calls.map(\.route) == [
            openEdit,
            clearListing(english), uploadImage(english), uploadImage(english),
            clearListing(english), uploadImage(english), uploadImage(english),
            commitEdit,
        ])
        let steps = log.entries.map(\.completedSteps)
        #expect(steps != steps.sorted(), "the retry should rewind progress to the language's first step")
        #expect(steps.last == 2)
    }

    @Test func exhaustedRetriesSurfaceTheFailureAndAbandonTheEdit() async throws {
        let h = try Harness { call, _ in
            call.path.hasPrefix("/upload/") ? (503, #"{"error":{"message":"backend"}}"#) : nil
        }

        let error = await #expect(throws: (any Error).self) { try await upload(h, row: makeRow(templates: 1), languages: [english]) }

        let context = try #require(failureContext(error))
        #expect(context.operation == .uploadScreenshot(number: 1))
        #expect(context.httpStatus == 503)
        let routes = h.server.calls.map(\.route)
        #expect(routes.filter { $0 == clearListing(english) }.count == 3)
        #expect(routes.filter { $0 == uploadImage(english) }.count == 3)
        #expect(routes.last == abandonEdit)
        #expect(!routes.contains(commitEdit))
    }

    // MARK: - Cancellation

    @Test func cancellingAfterTheEditOpensAbandonsIt() async throws {
        let h = try Harness()
        let row = makeRow(templates: 1)
        let document = StubGPDocument(rows: [row])
        let holder = TaskHolder()
        let server = h.server
        let openEditPath = self.editsPath
        let uploadTarget = makeTarget(row, [english])
        let package = self.packageName

        let task = Task {
            try await h.service.upload(
                packageName: package, targets: [uploadTarget], sendForReview: true,
                rows: [row], source: document
            ) { _ in
                if server.calls.contains(where: { $0.method == "POST" && $0.path == openEditPath }) {
                    holder.task?.cancel()
                }
            }
        }
        holder.task = task

        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!h.server.calls.map(\.route).contains(commitEdit))
        #expect(h.server.calls.map(\.route).last == abandonEdit)
    }
}

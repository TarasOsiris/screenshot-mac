import Foundation
@testable import Screenshot_Bro
import Testing

/// Intercepts every request so the transport can be exercised without a network.
nonisolated private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse?, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.requestCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
            } else {
                // Simulate a non-HTTP response.
                let url = request.url ?? URL(string: "about:blank")!
                let nonHTTP = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
                client?.urlProtocol(self, didReceive: nonHTTP, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct StoreHTTPClientTests {

    private func makeSession() -> URLSession {
        StubURLProtocol.requestCount = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient(
        token: @escaping () async throws -> String = { "tok" },
        errorMessage: @escaping @Sendable (Data) -> String? = { _ in nil },
        retryPolicy: StoreRetryPolicy = StoreRetryPolicy(
            maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .milliseconds(2)
        )
    ) -> StoreHTTPClient {
        StoreHTTPClient(
            baseURL: "https://example.test",
            session: makeSession(),
            bearerToken: token,
            errorMessage: errorMessage,
            retryPolicy: retryPolicy
        )
    }

    /// Fails the first `failures` attempts with `status`, then succeeds.
    private func flaky(
        status: Int,
        failures: Int,
        headers: [String: String]? = nil
    ) -> @Sendable (URLRequest) throws -> (HTTPURLResponse?, Data) {
        { request in
            let isFailure = StubURLProtocol.requestCount <= failures
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: isFailure ? status : 200,
                httpVersion: nil,
                headerFields: isFailure ? headers : nil
            )!
            return (response, Data((isFailure ? "{\"errors\":[]}" : "{\"ok\":true}").utf8))
        }
    }

    private func ok(_ body: String) -> @Sendable (URLRequest) throws -> (HTTPURLResponse?, Data) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    @Test func successReturnsBodyAndSendsBearerToken() async throws {
        StubURLProtocol.handler = ok("{\"ok\":true}")
        defer { StubURLProtocol.handler = nil }

        let data = try await makeClient().data(method: "GET", path: "/v1/things")
        #expect(String(decoding: data, as: UTF8.self) == "{\"ok\":true}")

        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(sent.url?.absoluteString == "https://example.test/v1/things")
        #expect(sent.httpMethod == "GET")
    }

    @Test func bodySetsDefaultJSONContentType() async throws {
        StubURLProtocol.handler = ok("{}")
        defer { StubURLProtocol.handler = nil }

        _ = try await makeClient().data(method: "POST", path: "/p", body: Data("{}".utf8))
        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func explicitContentTypeAndExtraHeadersAreSent() async throws {
        StubURLProtocol.handler = ok("{}")
        defer { StubURLProtocol.handler = nil }

        _ = try await makeClient().data(
            method: "POST",
            path: "/upload",
            body: Data([0x1]),
            contentType: "image/png",
            extraHeaders: ["Content-Disposition": "attachment; filename=\"01.png\""]
        )
        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(sent.value(forHTTPHeaderField: "Content-Disposition") == "attachment; filename=\"01.png\"")
    }

    /// Reads that verify a just-made write must not be served from cache.
    @Test func bypassCacheSetsNoCacheHeaderAndPolicy() async throws {
        StubURLProtocol.handler = ok("{}")
        defer { StubURLProtocol.handler = nil }

        _ = try await makeClient().data(method: "GET", path: "/verify", bypassCache: true)
        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
        #expect(sent.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func errorStatusCarriesTheParsedMessage() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{\"error\":\"boom\"}".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let client = makeClient(errorMessage: { data in
            (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        })
        await #expect(throws: StoreHTTPError.self) {
            _ = try await client.data(method: "GET", path: "/x")
        }
        do {
            _ = try await client.data(method: "GET", path: "/x")
        } catch let StoreHTTPError.status(code, message) {
            #expect(code == 409)
            #expect(message == "boom")
        } catch {
            Issue.record("expected .status, got \(error)")
        }
    }

    /// An unparseable error body must still surface the status, not swallow the failure.
    @Test func unparseableErrorBodyStillThrowsWithNilMessage() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("<html>nope</html>".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().data(method: "GET", path: "/x")
            Issue.record("expected a throw")
        } catch let StoreHTTPError.status(code, message) {
            #expect(code == 500)
            #expect(message == nil)
        } catch {
            Issue.record("expected .status, got \(error)")
        }
    }

    @Test func nonHTTPResponseIsReported() async {
        StubURLProtocol.handler = { _ in (nil, Data()) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().data(method: "GET", path: "/x")
            Issue.record("expected a throw")
        } catch StoreHTTPError.nonHTTPResponse {
            // expected
        } catch {
            Issue.record("expected .nonHTTPResponse, got \(error)")
        }
    }

    @Test func transportFailureIsWrapped() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().data(method: "GET", path: "/x")
            Issue.record("expected a throw")
        } catch StoreHTTPError.transport {
            // expected
        } catch {
            Issue.record("expected .transport, got \(error)")
        }
    }

    @Test func malformedPathIsRejectedBeforeAnyRequest() async {
        StubURLProtocol.lastRequest = nil
        let client = StoreHTTPClient(
            baseURL: "ht tp://bad url",
            session: makeSession(),
            bearerToken: { "tok" },
            errorMessage: { _ in nil }
        )
        do {
            _ = try await client.data(method: "GET", path: "/x")
            Issue.record("expected a throw")
        } catch StoreHTTPError.invalidURL {
            // expected
        } catch {
            Issue.record("expected .invalidURL, got \(error)")
        }
    }

    /// A token that can't be minted must fail the call, not send an unauthenticated request.
    @Test func tokenFailurePropagates() async {
        struct TokenError: Error {}
        StubURLProtocol.handler = ok("{}")
        defer { StubURLProtocol.handler = nil }

        let client = makeClient(token: { throw TokenError() })
        await #expect(throws: TokenError.self) {
            _ = try await client.data(method: "GET", path: "/x")
        }
    }

    // MARK: - Retry

    /// The failure this exists for: a single Apple 500 used to abort a whole upload.
    @Test func transientServerErrorOnIdempotentRequestIsRetriedUntilItSucceeds() async throws {
        StubURLProtocol.handler = flaky(status: 500, failures: 2)
        defer { StubURLProtocol.handler = nil }

        let data = try await makeClient().data(method: "GET", path: "/x")
        #expect(String(decoding: data, as: UTF8.self) == "{\"ok\":true}")
        #expect(StubURLProtocol.requestCount == 3)
    }

    /// A POST may already have taken effect server-side, so a 500 must not be repeated blindly —
    /// `AppStoreConnectScreenshotSyncService.reserve` retries it only after sweeping the orphan.
    @Test func serverErrorOnNonIdempotentRequestIsNotRetried() async {
        StubURLProtocol.handler = flaky(status: 500, failures: 2)
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: StoreHTTPError.self) {
            _ = try await makeClient().data(method: "POST", path: "/x", body: Data("{}".utf8))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    /// A 429 is refused before the server acts, so repeating a POST is safe.
    /// A rate limit is refused before the server acts, but a proxy can return one for a request
    /// the origin already processed — so a plain write still must not repeat itself.
    @Test func rateLimitIsRetriedOnlyWhereRepeatingIsSafe() async throws {
        StubURLProtocol.handler = flaky(status: 429, failures: 1)
        defer { StubURLProtocol.handler = nil }

        _ = try await makeClient().data(method: "GET", path: "/x")
        #expect(StubURLProtocol.requestCount == 2)

        await #expect(throws: StoreHTTPError.self) {
            _ = try await makeClient().data(method: "POST", path: "/x", body: Data("{}".utf8))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    /// The server's own pacing hint must win over the computed backoff.
    @Test func retryAfterHeaderIsHonoured() async throws {
        StubURLProtocol.handler = flaky(status: 503, failures: 1, headers: ["Retry-After": "1"])
        defer { StubURLProtocol.handler = nil }

        let policy = StoreRetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .seconds(8))
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await makeClient(retryPolicy: policy).data(method: "GET", path: "/x")
        }
        #expect(elapsed > .milliseconds(900))
        #expect(StubURLProtocol.requestCount == 2)
    }

    /// A caller that owns its own retry loop must not have a second budget applied underneath.
    @Test func singleAttemptPolicyOverridesTheClientPolicy() async {
        StubURLProtocol.handler = flaky(status: 503, failures: 99)
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: StoreHTTPError.self) {
            _ = try await makeClient().data(method: "GET", path: "/x", retryPolicy: .singleAttempt)
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func exhaustingRetriesSurfacesTheLastStatus() async {
        StubURLProtocol.handler = flaky(status: 503, failures: 99)
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().data(method: "GET", path: "/x")
            Issue.record("expected a throw")
        } catch let StoreHTTPError.status(code, _) {
            #expect(code == 503)
        } catch {
            Issue.record("expected .status, got \(error)")
        }
        #expect(StubURLProtocol.requestCount == 3)
    }

    /// A client error is the caller's bug — repeating it just wastes the rate-limit budget.
    @Test func clientErrorIsNotRetried() async {
        StubURLProtocol.handler = flaky(status: 404, failures: 99)
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: StoreHTTPError.self) {
            _ = try await makeClient().data(method: "GET", path: "/x")
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test(arguments: [("DELETE", 3), ("POST", 1)])
    func ambiguousTransportFailureIsRetriedOnlyWhenRepeatingIsHarmless(
        method: String, expectedRequests: Int
    ) async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: StoreHTTPError.self) {
            _ = try await makeClient().data(method: method, path: "/x", body: Data("{}".utf8))
        }
        #expect(StubURLProtocol.requestCount == expectedRequests)
    }

    /// The request never left the device, so the method's side effects don't matter.
    @Test func undeliveredRequestIsRetriedForAnyMethod() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotFindHost) }
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: StoreHTTPError.self) {
            _ = try await makeClient().data(method: "POST", path: "/x", body: Data("{}".utf8))
        }
        #expect(StubURLProtocol.requestCount == 3)
    }

    /// Each attempt re-mints the bearer so a retry straddling an expiry doesn't resend a stale one.
    @Test func eachRetryMintsAFreshToken() async throws {
        StubURLProtocol.handler = flaky(status: 500, failures: 1)
        defer { StubURLProtocol.handler = nil }

        let minted = Counter()
        let client = makeClient(token: { minted.increment(); return "tok-\(minted.value)" })
        _ = try await client.data(method: "GET", path: "/x")

        #expect(minted.value == 2)
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
    }
}

nonisolated private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}

struct StoreRetryPolicyTests {
    private let policy = StoreRetryPolicy()

    @Test(arguments: ["GET", "delete", "PUT", "HEAD"])
    func idempotentMethodsRetryOnServerErrors(method: String) {
        #expect(policy.allowsRetry(status: 503, method: method))
    }

    @Test(arguments: ["POST", "PATCH"])
    func writesDoNotRetryOnServerErrors(method: String) {
        #expect(!policy.allowsRetry(status: 500, method: method))
    }

    /// The reserve POST is retryable only because its caller sweeps the orphan first — which it
    /// states with `repeatable:`, not by pretending the verb is safe.
    @Test func repeatableOverridesTheVerb() {
        #expect(policy.allowsRetry(status: 500, repeatable: true))
        #expect(!policy.allowsRetry(status: 500, repeatable: false))
        #expect(policy.allowsRetry(status: 429, repeatable: true))
        #expect(!policy.allowsRetry(status: 429, repeatable: false))
    }

    /// A request that never left the device leaves no server state to clean up.
    @Test func reachedServerIsFalseOnlyForUndeliveredRequests() {
        #expect(!StoreRetryPolicy.reachedServer(URLError(.cannotFindHost)))
        #expect(StoreRetryPolicy.reachedServer(URLError(.timedOut)))
        #expect(StoreRetryPolicy.reachedServer(StoreHTTPError.status(500, message: nil)))
    }

    @Test(arguments: [400, 401, 403, 404, 409, 422])
    func clientErrorsNeverRetry(status: Int) {
        #expect(!policy.allowsRetry(status: status, method: "GET"))
    }

    @Test func nonURLErrorsAreNotRetried() {
        struct Boom: Error {}
        #expect(!policy.allowsRetry(transportError: Boom(), method: "GET"))
    }

    @Test func backoffGrowsAndIsCapped() {
        let policy = StoreRetryPolicy(maxAttempts: 6, baseDelay: .seconds(1), maxDelay: .seconds(4))
        #expect(policy.delay(forAttempt: 0, retryAfter: nil) == .seconds(1))
        #expect(policy.delay(forAttempt: 1, retryAfter: nil) == .seconds(2))
        #expect(policy.delay(forAttempt: 2, retryAfter: nil) == .seconds(4))
        #expect(policy.delay(forAttempt: 5, retryAfter: nil) == .seconds(4))
    }

    @Test func retryAfterOverridesBackoffButStaysCapped() {
        #expect(policy.delay(forAttempt: 0, retryAfter: "3") == .seconds(3))
        #expect(policy.delay(forAttempt: 0, retryAfter: " 2 ") == .seconds(2))
        #expect(policy.delay(forAttempt: 0, retryAfter: "9999") == policy.maxDelay)
    }

    /// An HTTP-date `Retry-After` is not parsed; it must fall back, not resolve to zero.
    @Test func unparseableRetryAfterFallsBackToBackoff() {
        #expect(policy.delay(forAttempt: 1, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT")
                == policy.delay(forAttempt: 1, retryAfter: nil))
        #expect(policy.delay(forAttempt: 0, retryAfter: "0") == policy.delay(forAttempt: 0, retryAfter: nil))
    }
}

struct JWTTests {
    /// Sorted keys keep the encoded payload deterministic — a signature is only reproducible
    /// if the bytes that were signed are.
    @Test func signingInputIsDeterministicRegardlessOfKeyOrder() throws {
        let a = try JWT.signingInput(
            header: ["alg": "ES256", "kid": "K1", "typ": "JWT"],
            claims: ["iss": "I", "iat": 1, "exp": 2, "aud": "x"]
        )
        let b = try JWT.signingInput(
            header: ["typ": "JWT", "kid": "K1", "alg": "ES256"],
            claims: ["aud": "x", "exp": 2, "iat": 1, "iss": "I"]
        )
        #expect(a == b)
    }

    @Test func signingInputIsTwoBase64URLSegments() throws {
        let input = try JWT.signingInput(header: ["alg": "RS256"], claims: ["iss": "a@b.com"])
        let parts = input.split(separator: ".")
        #expect(parts.count == 2)
        // base64url uses -/_ and drops padding.
        #expect(!input.contains("+") && !input.contains("/") && !input.contains("="))
    }

    @Test func tokenAppendsTheSignatureAsAThirdSegment() throws {
        let input = try JWT.signingInput(header: ["alg": "ES256"], claims: ["iss": "I"])
        let token = JWT.token(signingInput: input, signature: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(token.hasPrefix(input + "."))
        #expect(token.split(separator: ".").count == 3)
    }
}

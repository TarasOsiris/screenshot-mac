import Foundation
import Testing
@testable import Screenshot_Bro

/// Intercepts every request so the transport can be exercised without a network.
nonisolated private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse?, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
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
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient(
        token: @escaping () async throws -> String = { "tok" },
        errorMessage: @escaping @Sendable (Data) -> String? = { _ in nil }
    ) -> StoreHTTPClient {
        StoreHTTPClient(
            baseURL: "https://example.test",
            session: makeSession(),
            bearerToken: token,
            errorMessage: errorMessage
        )
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
}

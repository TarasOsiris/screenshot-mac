import Foundation
import Testing
@testable import Screenshot_Bro

/// The bearer-token gate that MCPHTTPListener applies before forwarding a request to the SDK
/// transport. Exercises the real header parser so case handling and the `Bearer ` prefix match
/// what a client actually sends.
@Suite
struct MCPListenerAuthTests {

    private func head(_ headerLines: String...) throws -> MCPHTTPRequestHead {
        var raw = "POST /mcp HTTP/1.1"
        for line in headerLines { raw += "\r\n" + line }
        return try MCPHTTPRequestParser.parseHead(Data(raw.utf8))
    }

    @Test func noTokenConfiguredAllowsEverything() throws {
        let request = try head("Content-Type: application/json")
        #expect(MCPHTTPListener.authorize(request, expectedToken: nil))
        #expect(MCPHTTPListener.authorize(request, expectedToken: ""))
    }

    @Test func missingHeaderRejected() throws {
        let request = try head("Content-Type: application/json")
        #expect(!MCPHTTPListener.authorize(request, expectedToken: "s3cret"))
    }

    @Test func wrongTokenRejected() throws {
        let request = try head("Authorization: Bearer nope")
        #expect(!MCPHTTPListener.authorize(request, expectedToken: "s3cret"))
    }

    @Test func nonBearerSchemeRejected() throws {
        let request = try head("Authorization: Basic s3cret")
        #expect(!MCPHTTPListener.authorize(request, expectedToken: "s3cret"))
    }

    @Test func correctBearerAccepted() throws {
        let request = try head("Authorization: Bearer s3cret")
        #expect(MCPHTTPListener.authorize(request, expectedToken: "s3cret"))
    }

    @Test func headerNameAndSchemeAreCaseInsensitive() throws {
        let request = try head("authorization: bearer s3cret")
        #expect(MCPHTTPListener.authorize(request, expectedToken: "s3cret"))
    }
}

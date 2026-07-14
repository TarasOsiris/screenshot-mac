import Foundation
import Testing
@testable import Screenshot_Bro

struct MCPHTTPRequestParserTests {

    private func head(_ raw: String) throws -> MCPHTTPRequestHead {
        try MCPHTTPRequestParser.parseHead(Data(raw.utf8))
    }

    @Test func parsesRequestLineAndHeaders() throws {
        let parsed = try head("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:8722\r\nContent-Type: application/json\r\nContent-Length: 42")
        #expect(parsed.method == "POST")
        #expect(parsed.target == "/mcp")
        #expect(parsed.path == "/mcp")
        #expect(parsed.httpVersion == "HTTP/1.1")
        #expect(parsed.contentLength == 42)
        #expect(parsed.header("content-type") == "application/json")
    }

    @Test func headerLookupIsCaseInsensitive() throws {
        let parsed = try head("GET /mcp HTTP/1.1\r\nACCEPT: application/json")
        #expect(parsed.header("Accept") == "application/json")
        #expect(parsed.header("accept") == "application/json")
    }

    @Test func stripsQueryStringFromPath() throws {
        let parsed = try head("POST /mcp?session=abc HTTP/1.1\r\nContent-Length: 0")
        #expect(parsed.path == "/mcp")
        #expect(parsed.target == "/mcp?session=abc")
    }

    @Test func duplicateHeadersAreJoined() throws {
        let parsed = try head("POST /mcp HTTP/1.1\r\nX-Thing: a\r\nX-Thing: b")
        #expect(parsed.header("x-thing") == "a, b")
    }

    @Test func detectsConnectionClose() throws {
        let parsed = try head("POST /mcp HTTP/1.1\r\nConnection: close")
        #expect(parsed.wantsClose)
        let keepAlive = try head("POST /mcp HTTP/1.1\r\nConnection: keep-alive")
        #expect(!keepAlive.wantsClose)
    }

    @Test func detectsTransferEncoding() throws {
        let parsed = try head("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked")
        #expect(parsed.hasTransferEncoding)
    }

    @Test func rejectsMalformedRequestLine() {
        #expect(throws: MCPHTTPParseError.self) {
            try MCPHTTPRequestParser.parseHead(Data("NOT A REQUEST\r\nFoo: bar".utf8))
        }
    }

    @Test func rejectsMalformedHeader() {
        #expect(throws: MCPHTTPParseError.self) {
            try MCPHTTPRequestParser.parseHead(Data("POST /mcp HTTP/1.1\r\nno-colon-here".utf8))
        }
    }

    @Test func findsHeaderTerminator() {
        var buffer = Data("POST /mcp HTTP/1.1\r\nContent-Length: 4\r\n".utf8)
        #expect(MCPHTTPRequestParser.headerEndRange(in: buffer) == nil)
        buffer.append(Data("\r\nbody".utf8))
        let range = MCPHTTPRequestParser.headerEndRange(in: buffer)
        #expect(range != nil)
        if let range {
            let body = buffer[range.upperBound...]
            #expect(String(decoding: body, as: UTF8.self) == "body")
        }
    }
}

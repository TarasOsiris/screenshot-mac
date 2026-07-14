import Foundation
import MCP
import Testing
@testable import Screenshot_Bro

/// Drives the SDK server through the stateless HTTP transport exactly as MCPServerService wires
/// it — validation pipeline, JSON-RPC decode, handler bridging — everything except the socket.
@Suite(.serialized)
@MainActor
struct MCPServerRoundTripTests {

    private func makeTransport(state: AppState) async throws -> (Server, StatelessHTTPServerTransport) {
        let executor = MCPToolExecutor(state: state)
        let transport = StatelessHTTPServerTransport()
        let server = try await MCPServerService.makeStartedServer(executor: executor, transport: transport)
        return (server, transport)
    }

    private func post(_ transport: StatelessHTTPServerTransport, _ body: [String: Any]) async throws -> [String: Any] {
        let request = HTTPRequest(
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: try JSONSerialization.data(withJSONObject: body),
            path: "/mcp"
        )
        let response = await transport.handleRequest(request)
        #expect(response.statusCode == 200, "unexpected status \(response.statusCode)")
        let data = try #require(response.bodyData)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func initializeListToolsAndCallTool() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let (server, transport) = try await makeTransport(state: state)
        defer { Task { await server.stop() } }

        let initialize = try await post(transport, [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": ["name": "tests", "version": "1.0"],
            ],
        ])
        let initResult = try #require(initialize["result"] as? [String: Any])
        let serverInfo = try #require(initResult["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "screenshot-bro")

        let list = try await post(transport, [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
        ])
        let listResult = try #require(list["result"] as? [String: Any])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(tools.count == MCPToolName.allCases.count)
        #expect(tools.allSatisfy { $0["inputSchema"] != nil })

        let call = try await post(transport, [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": [
                "name": "get_project",
                "arguments": [:],
            ],
        ])
        let callResult = try #require(call["result"] as? [String: Any])
        #expect(callResult["isError"] == nil || callResult["isError"] as? Bool == false)
        let content = try #require(callResult["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        #expect(text.contains(state.rows[0].id.uuidString))
    }

    @Test func initializeIsIdempotentAcrossReconnects() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let (server, transport) = try await makeTransport(state: state)
        defer { Task { await server.stop() } }

        for id in 1...2 {
            let initialize = try await post(transport, [
                "jsonrpc": "2.0",
                "id": id,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-06-18",
                    "capabilities": [:],
                    "clientInfo": ["name": "client-\(id)", "version": "1.0"],
                ],
            ])
            #expect(initialize["error"] == nil, "initialize #\(id) failed: \(initialize)")
            let result = try #require(initialize["result"] as? [String: Any])
            #expect(result["protocolVersion"] as? String == "2025-06-18")
            let serverInfo = try #require(result["serverInfo"] as? [String: Any])
            #expect(serverInfo["name"] as? String == "screenshot-bro")
        }
    }

    @Test func rejectsWrongContentType() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let (server, transport) = try await makeTransport(state: state)
        defer { Task { await server.stop() } }

        let request = HTTPRequest(
            method: "POST",
            headers: ["Content-Type": "text/plain", "Accept": "application/json"],
            body: Data("hello".utf8),
            path: "/mcp"
        )
        let response = await transport.handleRequest(request)
        #expect(response.statusCode >= 400)
    }

    @Test func getIsMethodNotAllowed() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let (server, transport) = try await makeTransport(state: state)
        defer { Task { await server.stop() } }

        let response = await transport.handleRequest(HTTPRequest(method: "GET", headers: [:], body: nil, path: "/mcp"))
        #expect(response.statusCode == 405)
    }
}

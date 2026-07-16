#if os(macOS)
import Foundation
import MCP
import OSLog
import SwiftUI

/// Hosts the in-app MCP server (Debug builds only): SDK `Server` + stateless HTTP transport
/// behind a loopback NWListener, so agents like Claude Code can drive the app at
/// http://127.0.0.1:8722/mcp while it runs.
@MainActor
@Observable
final class MCPServerService {
    enum Status: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    static let enabledDefaultsKey = "mcpServerEnabled"
    static let portDefaultsKey = "mcpServerPort"
    static let defaultPort: UInt16 = 8722
    private static let tokenAccount = "mcpAuthToken"

    private(set) var status: Status = .stopped

    /// Bearer token required to call the server. Enforced in Release builds so an arbitrary local
    /// process can't drive the app; nil in DEBUG so the repo's `.mcp.json` / agent harness keep
    /// working without a header. Loaded (not created) at launch so users who never enable the
    /// server get no Keychain item; `start` mints one on first enable.
    private(set) var authToken: String? = {
        #if DEBUG
        nil
        #else
        KeychainService.load(account: MCPServerService.tokenAccount)
        #endif
    }()

    private var server: Server?
    private var listener: MCPHTTPListener?

    var port: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
        return UInt16(exactly: stored).flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultPort
    }

    var claudeRegistrationCommand: String {
        var command = "claude mcp add --transport http screenshot-bro http://127.0.0.1:\(port)/mcp"
        if let authToken, !authToken.isEmpty {
            command += " --header \"Authorization: Bearer \(authToken)\""
        }
        return command
    }

    /// Discards the current token, issues a fresh one, and restarts the listener if running so the
    /// new token takes effect. No-op in DEBUG (no token is enforced there).
    func regenerateToken(state: AppState) {
        #if !DEBUG
        KeychainService.delete(account: Self.tokenAccount)
        authToken = Self.loadOrCreateToken()
        if case .running = status {
            Task {
                await stop(keepStatus: true)
                await start(state: state)
            }
        }
        #endif
    }

    private static func loadOrCreateToken() -> String {
        if let existing = KeychainService.load(account: tokenAccount) { return existing }
        let token = makeToken()
        try? KeychainService.save(token, account: tokenAccount)
        return token
    }

    private static func makeToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    func autostartIfEnabled(state: AppState) {
        guard !PersistenceService.isRunningUnderXCTest else { return }
        guard isEnabled else { return }
        Task { await start(state: state) }
    }

    func setEnabled(_ enabled: Bool, state: AppState) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        Task {
            if enabled {
                await start(state: state)
            } else {
                await stop()
            }
        }
    }

    func start(state: AppState) async {
        if case .running = status { return }
        status = .starting
        await stop(keepStatus: true)

        #if !DEBUG
        if authToken == nil { authToken = Self.loadOrCreateToken() }
        #endif

        let executor = MCPToolExecutor(state: state)
        let transport = StatelessHTTPServerTransport()
        let listener = MCPHTTPListener(port: port, expectedToken: authToken) { @Sendable [transport] request in
            await transport.handleRequest(request)
        }

        do {
            let server = try await Self.makeStartedServer(executor: executor, transport: transport)
            do {
                try await listener.start()
            } catch {
                await server.stop()
                throw error
            }
            self.server = server
        } catch {
            await listener.stop()
            status = .failed("Could not start on port \(port): \(error.localizedDescription). If the port is taken, run `defaults write xyz.tleskiv.screenshot \(Self.portDefaultsKey) -int <port>` and update .mcp.json.")
            return
        }

        self.listener = listener
        status = .running(port: port)
        AppLogger.mcp.info("MCP server running on 127.0.0.1:\(self.port)")
    }

    func stop(keepStatus: Bool = false) async {
        if let listener {
            await listener.stop()
        }
        if let server {
            await server.stop()
        }
        listener = nil
        server = nil
        if !keepStatus {
            status = .stopped
        }
    }

    static func makeStartedServer(executor: MCPToolExecutor, transport: StatelessHTTPServerTransport) async throws -> Server {
        let name = "screenshot-bro"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let instructions = "Controls the Screenshot Bro app: create App Store / Google Play screenshot projects, edit rows and shapes, import screenshots into device frames, translate texts, render previews, and export final images. Call get_project first to discover ids."
        let capabilities = Server.Capabilities(tools: .init(listChanged: false))
        let server = Server(name: name, version: version, instructions: instructions, capabilities: capabilities)
        await server.withMethodHandler(ListTools.self) { @Sendable _ in
            ListTools.Result(tools: MCPToolCatalog.tools)
        }
        await server.withMethodHandler(CallTool.self) { @Sendable [executor] params in
            await executor.call(name: params.name, arguments: params.arguments)
        }
        try await server.start(transport: transport)
        // The SDK's default initialize handler (registered inside start()) accepts only one
        // handshake per Server instance, but every client of the stateless transport re-sends
        // initialize — replace it post-start with an idempotent one so reconnects succeed.
        await server.withMethodHandler(Initialize.self) { @Sendable params in
            Initialize.Result(
                protocolVersion: Version.supported.contains(params.protocolVersion) ? params.protocolVersion : Version.latest,
                capabilities: capabilities,
                serverInfo: .init(name: name, version: version),
                instructions: instructions
            )
        }
        return server
    }
}
#endif

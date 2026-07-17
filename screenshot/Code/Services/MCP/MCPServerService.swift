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
    /// Serializes start/stop: a quick off→on toggle must not interleave a stale stop with the
    /// fresh start (which leaked a still-bound listener and blocked the port until relaunch).
    private var lifecycleTask: Task<Void, Never>?

    /// The in-flight lifecycle operation, if any, so the UI can show an accurate spinner label
    /// (a token regeneration is a restart, not a plain start) and block spam re-toggles.
    enum Transition { case starting, stopping, restarting }
    private(set) var transition: Transition?
    var isTransitioning: Bool { transition != nil }
    private var pendingLifecycleOps = 0

    var port: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
        return UInt16(exactly: stored).flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultPort
    }

    var serverURL: String {
        "http://127.0.0.1:\(port)/mcp"
    }

    /// Standard MCP `mcpServers` config (streamable HTTP). Client-agnostic — works with any MCP
    /// client, not just Claude — and includes the bearer header only when a token is enforced.
    var configurationJSON: String {
        var entry = "      \"type\": \"http\",\n      \"url\": \"\(serverURL)\""
        if let authToken, !authToken.isEmpty {
            entry += ",\n      \"headers\": {\n        \"Authorization\": \"Bearer \(authToken)\"\n      }"
        }
        return "{\n  \"mcpServers\": {\n    \"screenshot-bro\": {\n\(entry)\n    }\n  }\n}"
    }

    /// A plain-English instruction a user can paste into any AI agent (Claude Code, Cursor, …) to
    /// have it register this server itself — friendlier than editing config files by hand.
    var agentPrompt: String {
        var lines = [
            "Add an MCP server named \"screenshot-bro\" to your configuration so you can control the Screenshot Bro app.",
            "",
            "It uses streamable HTTP transport:",
            "- URL: \(serverURL)"
        ]
        if let authToken, !authToken.isEmpty {
            lines.append("- HTTP header: Authorization: Bearer \(authToken)")
        }
        lines.append("")
        lines.append("Use whatever method your MCP client supports (a config-file entry or an \"mcp add\" command). After adding it, reconnect so the screenshot-bro tools load, then list them to confirm.")
        return lines.joined(separator: "\n")
    }

    /// Discards the current token, issues a fresh one, and restarts the listener if running so the
    /// new token takes effect. No-op in DEBUG (no token is enforced there).
    func regenerateToken(state: AppState) {
        #if !DEBUG
        AppLogger.mcp.log("Regenerating auth token")
        KeychainService.delete(account: Self.tokenAccount)
        authToken = Self.loadOrCreateToken()
        if case .running = status {
            // Full stop (not keepStatus) — start() early-returns while status is still .running.
            enqueue(.restarting) {
                await self.stop()
                await self.start(state: state)
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

    /// Stored (not computed from UserDefaults) so @Observable tracks it — the Settings toggle
    /// reverts visually if flipping it mutates nothing observable.
    private(set) var isEnabled: Bool = UserDefaults.standard.bool(forKey: MCPServerService.enabledDefaultsKey)

    func autostartIfEnabled(state: AppState) {
        guard !PersistenceService.isRunningUnderXCTest else { return }
        guard isEnabled else { return }
        AppLogger.mcp.log("Autostart: server enabled, starting")
        enqueue(.starting) { await self.start(state: state) }
    }

    func setEnabled(_ enabled: Bool, state: AppState) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        AppLogger.mcp.log("Toggled \(enabled ? "on" : "off", privacy: .public)")
        enqueue(enabled ? .starting : .stopping) {
            if enabled {
                await self.start(state: state)
            } else {
                await self.stop()
            }
        }
    }

    private func enqueue(_ kind: Transition, _ operation: @escaping @MainActor () async -> Void) {
        let previous = lifecycleTask
        pendingLifecycleOps += 1
        transition = kind
        lifecycleTask = Task {
            await previous?.value
            await operation()
            self.pendingLifecycleOps -= 1
            if self.pendingLifecycleOps == 0 {
                self.transition = nil
            }
        }
    }

    func start(state: AppState) async {
        if case .running = status {
            AppLogger.mcp.log("Start requested but already running")
            return
        }
        AppLogger.mcp.log("Starting on port \(self.port)")
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
            AppLogger.mcp.error("Start failed on port \(self.port): \(String(describing: error), privacy: .public)")
            status = .failed("Could not start on port \(port): \(error.localizedDescription). If the port is taken, run `defaults write xyz.tleskiv.screenshot \(Self.portDefaultsKey) -int <port>` and update .mcp.json.")
            // Clear the persisted intent so autostart doesn't re-attempt this doomed start on every
            // launch; isEnabled stays true in memory so the failure remains visible this session.
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
            return
        }

        self.listener = listener
        status = .running(port: port)
        AppLogger.mcp.log("MCP server running on 127.0.0.1:\(self.port)")
    }

    func stop(keepStatus: Bool = false) async {
        let hadServer = listener != nil || server != nil
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
        if hadServer {
            AppLogger.mcp.log("Stopped (port released)")
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

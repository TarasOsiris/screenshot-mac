import SwiftUI

#if os(macOS)
struct AutomationSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Environment(MCPServerService.self) private var mcpServer

    var body: some View {
        Form {
            Section {
                if mcpServer.isTransitioning {
                    LabeledContent("Enable MCP server") {
                        HStack(spacing: 8) {
                            Text(mcpTransitionLabel)
                                .foregroundStyle(.secondary)
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    Toggle("Enable MCP server", isOn: Binding(
                        get: { mcpServer.isEnabled },
                        set: { mcpServer.setEnabled($0, state: appState) }
                    ))
                }
            } footer: {
                Text("Runs a local server on 127.0.0.1 so AI agents and MCP clients (like Claude Code) can create and edit projects, translate text, and export screenshots on your behalf.")
                    .foregroundStyle(.secondary)
            }

            if mcpServer.isEnabled && !mcpServer.isTransitioning {
                Section("Status") {
                    mcpStatusRow
                }

                Section {
                    LabeledContent("Server URL") {
                        copyableValue(mcpServer.serverURL, monospaced: true, tooltip: "Copy server URL")
                    }
                    if let token = mcpServer.authToken {
                        LabeledContent("Access Token") {
                            copyableValue(token, masked: true, tooltip: "Copy access token")
                        }
                    }
                    agentPromptPreview
                    Button {
                        PlatformPasteboard.copyString(mcpServer.agentPrompt)
                    } label: {
                        Label("Copy Agent Prompt", systemImage: "sparkles")
                    }
                    Button("Copy Configuration (JSON)") {
                        PlatformPasteboard.copyString(mcpServer.configurationJSON)
                    }
                    if mcpServer.authToken != nil {
                        Button("Regenerate Access Token") {
                            mcpServer.regenerateToken(state: appState)
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if mcpServer.authToken != nil {
                        Text("Easiest: paste the agent prompt into your AI assistant and let it connect. Or add the server by hand with the URL and access token, or the JSON configuration. Keep the token private — anyone with it can control the app while the server is running.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Easiest: paste the agent prompt into your AI assistant and let it connect. Or add the server by hand with the URL or the JSON configuration, then restart the client.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var agentPromptPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: mcpServer.agentPromptPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: .rect(cornerRadius: UIMetrics.CornerRadius.card))
            if mcpServer.authToken != nil {
                Text("The dots stand in for your access token — the copied text carries the real one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var mcpStatusRow: some View {
        switch mcpServer.status {
        case .stopped:
            Label("Not running", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .running(let port):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Running")
                Spacer()
                Text(verbatim: "127.0.0.1:\(port)")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }

    private var mcpTransitionLabel: LocalizedStringKey {
        switch mcpServer.transition {
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .restarting: "Restarting…"
        case nil: "Working…"
        }
    }

    private func copyableValue(_ value: String, monospaced: Bool = false, masked: Bool = false, tooltip: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: masked ? MCPServerService.maskedToken : value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            ActionButton(icon: "doc.on.doc", tooltip: tooltip) {
                PlatformPasteboard.copyString(value)
            }
        }
    }
}
#endif

import SwiftUI

// Shared upload chrome. Both store wizards render the same [UploadIssue], and before these
// were shared they rendered it differently — App Store Connect in a tinted callout with
// "scope · message", Google Play in a grey box with "scope: message" and a different symbol.

struct UploadIssuesPanel: View {
    let issues: [UploadIssue]
    /// Supplied by the store that knows how to apply a fix; without it the Fix buttons stay hidden.
    var onFix: ((UploadIssueFix) -> Void)?

    var body: some View {
        if !issues.isEmpty {
            CalloutBox(tint: issues.hasErrors ? .red : .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        UploadIssueRow(issue: issue, onFix: onFix)
                    }
                    #if os(macOS)
                    if let agentPrompt {
                        CopyAgentPromptButton(prompt: agentPrompt)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    #endif
                }
            }
        }
    }

    /// One button for the panel: issues that share a prompt share it, distinct ones are joined.
    private var agentPrompt: String? {
        var seen = Set<String>()
        let prompts = issues.compactMap(\.agentPrompt).filter { seen.insert($0).inserted }
        return prompts.isEmpty ? nil : prompts.joined(separator: "\n\n---\n\n")
    }
}

private struct UploadIssueRow: View {
    let issue: UploadIssue
    let onFix: ((UploadIssueFix) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity.tint)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                message
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = issue.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let fix = issue.fix, let onFix {
                Spacer(minLength: 8)
                Button("Fix") { onFix(fix) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption)
            }
        }
    }

    private var message: Text {
        if let scope = issue.scope {
            let scopeText = Text(scope).fontWeight(.semibold)
            return Text("\(scopeText) · \(issue.message)")
        }
        return Text(issue.message)
    }
}

#if os(macOS)
/// The MCP server that would act on the prompt only exists on macOS.
private struct CopyAgentPromptButton: View {
    let prompt: String
    @State private var copied = false

    var body: some View {
        Button {
            PlatformPasteboard.copyString(prompt)
            copied = true
        } label: {
            Label(copied ? "Copied" : "Copy Agent Prompt", systemImage: copied ? "checkmark" : "sparkles")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
#endif

struct CalloutBox<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            }
    }
}

struct DisclosureChevronButton<Label: View>: View {
    let expanded: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    init(
        expanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label = { EmptyView() }
    ) {
        self.expanded = expanded
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                label()
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

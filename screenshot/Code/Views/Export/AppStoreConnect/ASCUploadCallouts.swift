import SwiftUI

struct ASCIssuesPanel: View {
    let issues: [UploadIssue]

    var body: some View {
        if !issues.isEmpty {
            ASCCalloutBox(tint: issues.hasErrors ? .red : .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        ASCIssueRow(issue: issue)
                    }
                }
            }
        }
    }
}

private struct ASCIssueRow: View {
    let issue: UploadIssue

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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

struct ASCCalloutBox<Content: View>: View {
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

struct ASCDisclosureChevronButton<Label: View>: View {
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

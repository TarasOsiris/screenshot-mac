import SwiftUI

/// One inspector value row: a label, the value column, and the unit column after it. Every numeric
/// row in the inspector is built from this, so alignment, the shared column and the unit slot are
/// owned in one place instead of being re-spelled per row.
///
/// `Form(.grouped)` aligns a row's label to its content's *first text baseline*, so a row whose
/// content happens to begin with a small `Text` — the geometry fields' 9pt axis letters — pulls its
/// label up above the centre of its own fields. Laying the row out here replaces that rule with an
/// explicit centre alignment, and makes this the only place `unitWidth` is spent, so the reserved
/// column and the occupied one can no longer drift apart.
struct InspectorValueRow<Content: View>: View {
    let label: LocalizedStringKey
    /// "°", "%", or nothing — the column is reserved either way, so fields end on the same x
    /// whether or not their row carries a suffix.
    var unit: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        LabeledContent {
            HStack(spacing: 0) {
                content()

                Text(unit ?? "")
                    .scaledFont(UIMetrics.FontSize.numericBadge)
                    .foregroundStyle(.secondary)
                    .frame(width: UIMetrics.InspectorRow.unitWidth, alignment: .leading)
            }
        } label: {
            Text(label)
        }
        .labeledContentStyle(InspectorValueRowStyle())
    }
}

private struct InspectorValueRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: UIMetrics.InspectorRow.columnGap) {
            configuration.label
            Spacer(minLength: 0)
            configuration.content
        }
    }
}

import SwiftUI

/// The inspector's collapsible section: a header that toggles, the rows it hides, and the expansion
/// persisted under `id`'s key.
///
/// The three inspectors spelled that triple out by hand, which is how single- and multi-selection
/// came to share five sections by copied string rather than by type. Holding the `@AppStorage` here
/// rather than on the panel also means collapsing one section invalidates one section, not the
/// whole inspector.
///
/// The disclosure control is ours, not `Section(isExpanded:)`'s. The platform draws that chevron and
/// owns the space around it, handing app code only the label — so the strip between the two belongs
/// to nobody and swallows clicks, and no padding on our side can reach it. Owning the row is what
/// makes all of it clickable; `ASCScreenshotReviewLocaleRow` and `EditorRowHeader` do the same.
struct InspectorSection<Content: View, Accessory: View>: View {
    private let id: InspectorSectionID
    private let title: LocalizedStringKey
    private let accessory: Accessory
    private let content: Content
    @AppStorage private var isExpanded: Bool

    init(
        _ id: InspectorSectionID,
        _ title: LocalizedStringKey,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.title = title
        self.accessory = accessory()
        self.content = content()
        _isExpanded = AppStorage(wrappedValue: id.startsExpanded, id.rawValue)
    }

    var body: some View {
        Section {
            if isExpanded {
                content
            }
        } header: {
            header
        }
    }

    /// Carries the rule separating it from the section above. The rule belongs to the header rather
    /// than sitting between the `Form`'s children because half the inspector's sections are
    /// conditional — a star shape drops the type, fill and outline sections — so interleaved
    /// dividers would double up or trail. A header exists exactly when its section does.
    private var header: some View {
        headerButton
            // Outdents the row so our chevron lands in the margin the platform used to draw its own
            // in, which keeps every title on the x it has today. The frame's leading edge doesn't
            // move, so the rule below is measured against the same box as before.
            .padding(.leading, -UIMetrics.InspectorSection.chevronOutdent)
            .overlay(alignment: .top) {
                // The grouped form insets every row, header included, so a plain Divider stops short
                // of the panel edges. Negative padding is what reaches them.
                Divider()
                    .padding(.horizontal, -UIMetrics.InspectorSection.rowInset)
                    .offset(y: -UIMetrics.InspectorSection.ruleGap)
                    // The rule must not take a click meant for collapsing the section.
                    .allowsHitTesting(false)
            }
    }

    private var headerButton: some View {
        Button(action: toggle) {
            HStack(spacing: UIMetrics.InspectorSection.titleGap) {
                chevron
                Text(title)
                accessory
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: UIMetrics.ActionButton.minTouchTarget)
            // After the frames, not before: applied earlier it would only cover the title's own run.
            .contentShape(Rectangle())
        }
        .buttonStyle(InspectorSectionHeaderStyle())
        #if os(macOS)
        // 17 headers would otherwise be 17 new stops between the inspector's real controls.
        .focusable(false)
        #endif
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
    }

    /// Swapped, not rotated, and in a fixed box — the width has to hold steady or the wider
    /// `chevron.down` nudges the title every time a section opens.
    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: UIMetrics.InspectorSection.chevronFont, weight: .medium))
            .frame(width: UIMetrics.InspectorSection.chevronSize)
            .foregroundStyle(.secondary)
    }

    private func toggle() {
        InspectorSectionExpansion.apply(!isExpanded, to: id, includingAll: PlatformModifiers.optionDown)
    }
}

extension InspectorSection where Accessory == EmptyView {
    init(
        _ id: InspectorSectionID,
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.init(id, title, accessory: { EmptyView() }, content: content)
    }
}

/// No press feedback: a native disclosure row doesn't dim, and today's header didn't either, so
/// `EditorIconButtonStyle`'s fade would read as a flash across the whole row. Not `.plain` — the
/// primitive styles each bring a real `NSControl` with them (see `EditorIconButtonStyle`), and this
/// panel holds one per section.
private struct InspectorSectionHeaderStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// The one writer of section expansion, so "⌥ means all of them" is a single named decision rather
/// than an implicit property of some binding. Writing the keys — rather than a view's own state — is
/// what lets one click reach the sections the panel isn't currently showing; `@AppStorage` observes
/// `UserDefaults`, so the visible ones update themselves.
enum InspectorSectionExpansion {
    static func apply(_ expanded: Bool, to id: InspectorSectionID, includingAll: Bool) {
        for target in includingAll ? InspectorSectionID.allCases : [id] {
            UserDefaults.standard.set(expanded, forKey: target.rawValue)
        }
    }
}

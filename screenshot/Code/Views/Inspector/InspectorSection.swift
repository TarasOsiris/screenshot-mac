import SwiftUI

/// The inspector's collapsible section: the platform's `Section(isExpanded:)`, its header, and the
/// expansion persisted under `id`'s key.
///
/// The three inspectors spelled that triple out by hand, which is how single- and multi-selection
/// came to share five sections by copied string rather than by type. Holding the `@AppStorage` here
/// rather than on the panel also means collapsing one section invalidates one section, not the
/// whole inspector.
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
        Section(isExpanded: expansion) {
            content
        } header: {
            header
        }
    }

    /// Carries the rule separating it from the section above. The rule belongs to the header rather
    /// than sitting between the `Form`'s children because half the inspector's sections are
    /// conditional — a star shape drops the type, fill and outline sections — so interleaved
    /// dividers would double up or trail. A header exists exactly when its section does.
    private var header: some View {
        HStack(spacing: UIMetrics.InspectorSection.titleGap) {
            Text(title)
            accessory
        }
        // The header is the toggle's label, so the whole band should take the click — without this
        // the gap between the title and its badge is dead.
        .contentShape(Rectangle())
        // An overlay, not a stacked child: in the layout the rule made the header two rows tall, and
        // the grouped form centres its disclosure chevron on the whole header — which is what put
        // the chevron above the title it labels. Outside the layout, the header is exactly as tall
        // as its title and the chevron centres by construction.
        .overlay(alignment: .top) {
            // The grouped form insets every row, header included, so a plain Divider stops short of
            // the panel edges. Negative padding is what reaches them; the title keeps the form's own
            // inset, so it stays aligned with the rows below no matter what this value is.
            Divider()
                .padding(.horizontal, -UIMetrics.InspectorSection.rowInset)
                .offset(y: -UIMetrics.InspectorSection.ruleGap)
                // The rule must not take a click meant for collapsing the section.
                .allowsHitTesting(false)
        }
        #if os(macOS)
        // `.pointerStyle` rather than an `onHover` that pushes `NSCursor`: a push has to be balanced
        // by a pop, and the header is torn down mid-hover whenever the selection changes panels.
        .pointerStyle(.link)
        #endif
    }

    /// Widens the write the form's own toggle already makes, rather than adding a gesture — a second
    /// one would toggle the section again and cancel the click out.
    private var expansion: Binding<Bool> {
        Binding(get: { isExpanded }) { newValue in
            InspectorSectionExpansion.apply(newValue, to: id, includingAll: PlatformModifiers.optionDown)
        }
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

/// The one writer of section expansion, so "⌥ means all of them" is a single named decision rather
/// than an implicit property of one binding. Writing the keys — rather than a view's own state — is
/// what lets one click reach the sections the panel isn't currently showing; `@AppStorage` observes
/// `UserDefaults`, so the visible ones update themselves.
enum InspectorSectionExpansion {
    static func apply(_ expanded: Bool, to id: InspectorSectionID, includingAll: Bool) {
        for target in includingAll ? InspectorSectionID.allCases : [id] {
            UserDefaults.standard.set(expanded, forKey: target.rawValue)
        }
    }
}

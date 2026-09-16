import SwiftUI

/// A section header that carries the rule separating it from the section above.
///
/// The rule belongs to the header rather than sitting between the `Form`'s children because half
/// the inspector's sections are conditional — a star shape drops the type, fill and outline
/// sections — so interleaved dividers would double up or trail. A header exists exactly when its
/// section does.
struct InspectorSectionHeader<Accessory: View>: View {
    private let title: LocalizedStringKey
    @ViewBuilder private let accessory: () -> Accessory

    init(_ title: LocalizedStringKey, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIMetrics.InspectorSection.ruleGap) {
            // The grouped form insets every row, header included, so a plain Divider stops short of
            // the panel edges. Negative padding is what reaches them; the title keeps the form's own
            // inset, so it stays aligned with the rows below no matter what this value is.
            Divider()
                .padding(.horizontal, -UIMetrics.InspectorSection.rowInset)
                // The header doubles as the disclosure toggle's label, so the rule must not take
                // a click meant for collapsing the section.
                .allowsHitTesting(false)
            HStack(spacing: UIMetrics.InspectorSection.titleGap) {
                Text(title)
                accessory()
            }
        }
    }
}

extension InspectorSectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

import SwiftUI

#if os(macOS)
struct HelpHeading: View {
    let text: LocalizedStringKey
    let topPadding: CGFloat

    init(_ text: LocalizedStringKey, topPadding: CGFloat = 12) {
        self.text = text
        self.topPadding = topPadding
    }

    var body: some View {
        Text(text)
            .scaledFont(UIMetrics.FontSize.sectionHeading, weight: .semibold)
            .padding(.top, topPadding)
    }
}
#endif

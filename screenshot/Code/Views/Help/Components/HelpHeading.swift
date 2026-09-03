import SwiftUI

#if os(macOS)
struct HelpHeading: View {
    let text: LocalizedStringResource
    let topPadding: CGFloat

    init(_ text: LocalizedStringResource, topPadding: CGFloat = 12) {
        self.text = text
        self.topPadding = topPadding
    }

    var body: some View {
        HelpText(text)
            .scaledFont(UIMetrics.FontSize.sectionHeading, weight: .semibold)
            .padding(.top, topPadding)
    }
}
#endif

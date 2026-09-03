import SwiftUI

#if os(macOS)
struct HelpHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?

    init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HelpText(title)
                .scaledFont(UIMetrics.FontSize.displayTitle, weight: .bold)
            if let subtitle {
                HelpText(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}
#endif

import SwiftUI

#if os(macOS)
struct HelpHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .scaledFont(UIMetrics.FontSize.displayTitle, weight: .bold)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}
#endif

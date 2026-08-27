import SwiftUI

#if os(macOS)
struct HelpTip: View {
    private static let fillOpacity: Double = 0.08
    private static let borderOpacity: Double = 0.25

    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.yellow.opacity(Self.fillOpacity),
            in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .stroke(Color.yellow.opacity(Self.borderOpacity), lineWidth: UIMetrics.BorderWidth.hairline)
        }
    }
}
#endif

import SwiftUI

struct ShapePropertiesSection<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.horizontal, ShapePropertiesSectionLayout.horizontalPadding)
        .padding(.vertical, ShapePropertiesSectionLayout.verticalPadding)
        .frame(minHeight: ShapePropertiesSectionLayout.minHeight)
        .background(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
        )
        .overlay {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .strokeBorder(.separator.opacity(UIMetrics.Opacity.sectionBorder), lineWidth: UIMetrics.BorderWidth.hairline)
        }
    }
}

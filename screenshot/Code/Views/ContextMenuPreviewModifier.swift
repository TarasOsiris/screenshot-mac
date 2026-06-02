import SwiftUI

extension View {
    @ViewBuilder
    func contextMenuWithPreview<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        #if os(iOS)
        contextMenu(menuItems: menuItems, preview: preview)
        #else
        contextMenu(menuItems: menuItems)
        #endif
    }

    /// Shared rounded-card chrome for context-menu preview content (single source of truth for
    /// the preview corner radius / material / hairline so the three preview views stay consistent).
    func contextMenuPreviewCard(padding: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.preview, style: .continuous)
        return self
            .padding(padding)
            .background(.regularMaterial, in: shape)
            .overlay { shape.strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.standard) }
            .contentShape(shape)
    }
}

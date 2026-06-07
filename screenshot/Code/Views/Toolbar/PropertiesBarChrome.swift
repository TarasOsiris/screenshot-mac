import SwiftUI

/// Chrome for the bottom shape-properties bar: docked `.bar` material on macOS,
/// a floating Liquid Glass slab on iPad (rounded material fallback below iOS 26).
struct PropertiesBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(.bar)
        #else
        if #available(iOS 26.0, *) {
            content
                .clipShape(.rect(cornerRadius: UIMetrics.CornerRadius.floating))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: UIMetrics.CornerRadius.floating))
        } else {
            content
                .clipShape(.rect(cornerRadius: UIMetrics.CornerRadius.floating))
                .background {
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating)
                        .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.standard)
                }
        }
        #endif
    }
}

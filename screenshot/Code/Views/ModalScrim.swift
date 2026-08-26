import SwiftUI

/// The dimming layer behind a centered modal panel. Two overlays had the same
/// `Color.black.opacity(0.3).ignoresSafeArea()` written out by hand.
struct ModalScrim: View {
    var body: some View {
        Color.black.opacity(UIMetrics.Opacity.scrim)
            .ignoresSafeArea()
    }
}

/// The material card a centered modal panel sits on. Shared by the export-progress and
/// project-loading overlays so both pick up Liquid Glass on iOS 26.
struct OverlayCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: UIMetrics.CornerRadius.floating))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating))
        }
        #else
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating))
        #endif
    }
}

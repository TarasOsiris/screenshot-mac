import SwiftUI

/// The dimming layer behind a centered modal panel. Two overlays had the same
/// `Color.black.opacity(0.3).ignoresSafeArea()` written out by hand.
struct ModalScrim: View {
    var body: some View {
        Color.black.opacity(UIMetrics.Opacity.scrim)
            .ignoresSafeArea()
    }
}

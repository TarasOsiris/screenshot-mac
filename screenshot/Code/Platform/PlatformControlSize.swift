import SwiftUI

extension View {
    /// Desktop-dense `.small` controls on macOS; the standard size on iPad so
    /// switches, sliders, and buttons keep their native touch dimensions.
    @ViewBuilder
    func compactControlSize() -> some View {
        #if os(macOS)
        controlSize(.small)
        #else
        self
        #endif
    }
}

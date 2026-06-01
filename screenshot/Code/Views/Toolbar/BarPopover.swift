import SwiftUI

extension View {
    /// A popover anchored to a control in the bottom properties bar.
    ///
    /// macOS shows a real popover above the anchor (`arrowEdge: .top`). On iPad a popover
    /// anchored to a control sitting at the very bottom of the screen renders partly
    /// off-screen, so present a content-sized sheet instead (`.presentationSizing(.fitted)`):
    /// a compact, centered dialog that's always fully on-screen, matching the rest of the
    /// app's iPad sheets (ProjectNameSheet, showcase).
    @ViewBuilder
    func barPopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .top, content: content)
        #else
        sheet(isPresented: isPresented) {
            content()
                .presentationSizing(.fitted)
                .presentationDragIndicator(.visible)
        }
        #endif
    }
}

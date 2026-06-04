import SwiftUI

/// Dashed "add" placeholder (new row / new screenshot). Emphasis is driven by
/// `isPressed` so touch gets real press feedback (iPad has no hover), with hover
/// kept as a pointer-only enhancement on macOS / trackpad.
struct DashedPlaceholderButtonStyle: ButtonStyle {
    var width: CGFloat? = nil
    var height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Placeholder(width: width, height: height, isPressed: configuration.isPressed)
    }

    private struct Placeholder: View {
        let width: CGFloat?
        let height: CGFloat
        let isPressed: Bool
        @State private var isHovered = false

        var body: some View {
            let emphasized = isHovered || isPressed
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(emphasized ? .primary : .secondary)
                .frame(width: width, height: height)
                .background(Rectangle().fill(.primary.opacity(emphasized ? 0.04 : 0)))
                .contentShape(Rectangle())
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundStyle(emphasized ? .primary : .secondary)
                }
                #if os(iOS)
                .hoverEffect(.automatic)
                #endif
                .onHover { isHovered = $0 }
                .animation(.easeInOut(duration: 0.15), value: emphasized)
        }
    }
}

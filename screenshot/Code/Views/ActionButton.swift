import SwiftUI

/// Press feedback for the editor's icon buttons, without an `NSButton` behind it.
///
/// The built-in `.borderless` / `.plain` styles bridge to a real AppKit `NSControl`, which brings a
/// cursor rect, a tracking area, key-view-loop membership and Auto Layout participation *each* — and
/// the editor's scroll content holds hundreds of them, so every display cycle during a scroll paid to
/// revalidate the lot. A custom `ButtonStyle` renders through SwiftUI primitives and creates none of
/// that. Prefer it over a primitive style for anything inside the row list.
struct EditorIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.4 : 1)
    }
}

/// The editor's icon-button label: glyph, tap target and hit shape. Its own view so a `Menu` that
/// should look like an `ActionButton` inherits the iPad touch-target floor too, rather than
/// re-spelling the frame and landing below it.
struct IconButtonLabel: View {
    let tooltip: LocalizedStringKey
    let icon: String
    var iconSize: CGFloat = UIMetrics.ActionButton.iconSize
    var frameSize: CGFloat = UIMetrics.ActionButton.frameSize

    private var tapTarget: CGFloat { max(frameSize, UIMetrics.ActionButton.minTouchTarget) }

    var body: some View {
        Label(tooltip, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.system(size: iconSize))
            .frame(width: tapTarget, height: tapTarget)
            .contentShape(Rectangle())
    }
}

struct ActionButton: View {
    let icon: String
    let tooltip: LocalizedStringKey
    var iconSize: CGFloat = UIMetrics.ActionButton.iconSize
    var frameSize: CGFloat = UIMetrics.ActionButton.frameSize
    var isDestructive: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonLabel(tooltip: tooltip, icon: icon, iconSize: iconSize, frameSize: frameSize)
        }
        .buttonStyle(EditorIconButtonStyle())
        // Kept even though there is no NSButton left: this is SwiftUI focus, not AppKit's key-view
        // loop, and ActionButton is used well beyond the editor's row list.
        .focusable(false)
        .foregroundStyle(
            disabled
            ? AnyShapeStyle(.tertiary)
            : (isDestructive ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.secondary))
        )
        .disabled(disabled)
        .help(tooltip)
    }
}

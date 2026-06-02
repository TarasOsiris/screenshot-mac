import SwiftUI

struct ActionButton: View {
    let icon: String
    let tooltip: LocalizedStringKey
    var iconSize: CGFloat = UIMetrics.ActionButton.iconSize
    var frameSize: CGFloat = UIMetrics.ActionButton.frameSize
    var isDestructive: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    private var tapTarget: CGFloat { max(frameSize, UIMetrics.ActionButton.minTouchTarget) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .frame(width: tapTarget, height: tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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

import SwiftUI

struct LocaleOverrideIndicator: View {
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            OverrideDot()
            Text("Overridden")
                .font(.system(size: UIMetrics.FontSize.inlineLabel))
                .foregroundStyle(Color.accentColor)

            ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset language override", frameSize: UIMetrics.IconButton.frameSize, action: onReset)
        }
    }
}

struct OverrideDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
    }
}

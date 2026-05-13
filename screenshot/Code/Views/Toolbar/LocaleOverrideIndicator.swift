import SwiftUI

struct LocaleOverrideIndicator: View {
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            OverrideDot()
            Text("Overridden")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)

            ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset language override", frameSize: 24, action: onReset)
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

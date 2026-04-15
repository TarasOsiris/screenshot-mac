import SwiftUI

struct LocaleOverrideIndicator: View {
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
            Text("Overridden")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)

            ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset locale override", frameSize: 24, action: onReset)
        }
    }
}

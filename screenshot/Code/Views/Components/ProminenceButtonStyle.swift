import SwiftUI

/// Bordered, or bordered-prominent: `.buttonStyle` can't take a conditional of two different style types.
struct ProminenceButtonStyle: PrimitiveButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

import SwiftUI

struct AddTemplateButton: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) { }
            .buttonStyle(DashedPlaceholderButtonStyle(width: width, height: height))
            .help("Add screenshot")
            .accessibilityLabel("Add screenshot")
    }
}

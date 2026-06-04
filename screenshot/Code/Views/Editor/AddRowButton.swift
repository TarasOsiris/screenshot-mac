import SwiftUI

struct AddRowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { }
            .buttonStyle(DashedPlaceholderButtonStyle(height: 48))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .help("Add new row")
            .accessibilityLabel("Add new row")
    }
}

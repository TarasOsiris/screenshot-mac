import SwiftUI

struct AddRowButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(height: 48)
                .background(
                    Rectangle()
                        .fill(.primary.opacity(isHovered ? 0.04 : 0))
                )
                .contentShape(Rectangle())
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .help("Add row")
        .accessibilityLabel("Add row")
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

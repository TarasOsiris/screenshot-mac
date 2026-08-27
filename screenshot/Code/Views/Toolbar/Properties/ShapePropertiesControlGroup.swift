import SwiftUI

struct ShapePropertiesControlGroup<Content: View>: View {
    let label: LocalizedStringKey
    private let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            content
        }
    }
}

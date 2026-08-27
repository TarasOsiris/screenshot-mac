import SwiftUI

struct ShapePropertiesBadge: View {
    let type: ShapeType

    var body: some View {
        Image(systemName: type.icon)
            .scaledFont(UIMetrics.FontSize.numericBadge, weight: .medium)
            .propertiesBadgeCapsule()
    }
}

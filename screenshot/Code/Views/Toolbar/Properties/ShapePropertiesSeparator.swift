import SwiftUI

struct ShapePropertiesSeparator: View {
    #if os(macOS)
    private static let height: CGFloat = 18
    #else
    private static let height: CGFloat = 24
    #endif

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: UIMetrics.BorderWidth.standard, height: Self.height)
            .padding(.horizontal, 4)
    }
}

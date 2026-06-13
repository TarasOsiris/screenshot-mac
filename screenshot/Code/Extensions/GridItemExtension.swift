import SwiftUI

extension Array where Element == GridItem {
    /// Card-grid columns: two even columns on a compact-width layout (iPhone portrait),
    /// otherwise an adaptive grid sized between `minimum` and `maximum`.
    static func adaptiveCards(minimum: CGFloat, maximum: CGFloat, spacing: CGFloat, compact: Bool) -> [GridItem] {
        if compact {
            return [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
        }
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: spacing)]
    }
}

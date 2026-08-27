import SwiftUI

extension View {
    /// The properties bars are fixed-height horizontal strips of label+control chips; past the
    /// first accessibility size the chips stop fitting. Every control here is also reachable from
    /// the inspector, which scrolls vertically and takes the full Dynamic Type range.
    @ViewBuilder
    func denseBarTypography() -> some View {
        #if os(macOS)
        self
        #else
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
        #endif
    }
}

/// Layout constants shared by `ShapePropertiesSection` and the bars that host it.
/// Use `.horizontalPadding` on the row container so sections align flush with the bar edges.
enum ShapePropertiesSectionLayout {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4
    static let badgeHorizontalPadding: CGFloat = 8
    static let badgeVerticalPadding: CGFloat = 4
    // Taller sections on iPad give the bottom bar's controls touch-friendly breathing room.
    // 52 = the 44pt ActionButton touch target + vertical padding, so every section in the
    // row renders at the same height regardless of which controls it holds.
    // Floor tall enough that every section's natural height (the tallest control is the ~24pt
    // fill/color swatch + vertical padding ≈ 32) is clamped to a single value, so all pills match.
    #if os(macOS)
    static let minHeight: CGFloat = 34
    #else
    static let minHeight: CGFloat = 52
    #endif
}

extension View {
    /// Accent capsule shared by the single-selection type badge and the multi-selection
    /// count badge so both read identically.
    func propertiesBadgeCapsule() -> some View {
        padding(.horizontal, ShapePropertiesSectionLayout.badgeHorizontalPadding)
            .padding(.vertical, ShapePropertiesSectionLayout.badgeVerticalPadding)
            .frame(minHeight: ShapePropertiesSectionLayout.minHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge))
            )
    }

    /// Secondary "replace"-style affordance in the properties bar: dense borderless-secondary on
    /// macOS, tappable bordered on iPad. Keeps the three replace buttons identical per platform.
    @ViewBuilder
    func propertiesBarSecondaryButton() -> some View {
        #if os(macOS)
        buttonStyle(.borderless).foregroundStyle(.secondary)
        #else
        buttonStyle(.bordered)
        #endif
    }
}

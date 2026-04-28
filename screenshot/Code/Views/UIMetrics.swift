import SwiftUI

/// Centralized UI constants used across editor, inspector, properties bar, and toolbar views.
/// New views should reach for these values instead of hardcoding sizes/colors so the app stays visually coherent.
enum UIMetrics {
    enum FontSize {
        /// Default body text for properties bar, popover content, and inspector sub-labels.
        /// Use for any small label that isn't a hint or a numeric badge.
        static let body: CGFloat = 11
        /// Compact label inside grouped controls (e.g. tile-fill labels, drop-zone hint).
        static let inlineLabel: CGFloat = 10
        /// Tiny hint text and axis labels ("X"/"Y", percent suffixes).
        static let hint: CGFloat = 9
        /// Numeric badge / value display next to sliders.
        static let numericBadge: CGFloat = 10
    }

    enum SliderWidth {
        /// Default width for sliders inside compact rows.
        static let standard: CGFloat = 80
        /// Wider sliders for fine-grained tuning (letter spacing).
        static let wide: CGFloat = 120
    }

    enum ColorSwatch {
        /// Inline ColorPicker in toolbars and outline controls.
        static let inline: CGFloat = 30
        /// Fill swatch button preview.
        static let preview: CGFloat = 24
    }

    enum CornerRadius {
        /// Small chip / preset / preview tile corner radius.
        static let chip: CGFloat = 4
        /// Card / drop area / image preview corner radius.
        static let card: CGFloat = 6
        /// Standard section / control surface corner radius.
        static let section: CGFloat = 8
        /// Floating bar / popover corner radius.
        static let floating: CGFloat = 12
    }

    enum BorderWidth {
        /// Hairline border on light surfaces.
        static let hairline: CGFloat = 0.5
        /// Standard 1pt border.
        static let standard: CGFloat = 1
        /// Emphasized border (focus, drop target).
        static let emphasis: CGFloat = 1.5
    }

    /// Dark-mode-safe overlay opacities. Apply on top of `Color.primary` / `Color.secondary` rather than `.white` / `.black`
    /// so the visual weight stays consistent across light and dark appearances.
    enum Opacity {
        /// Background fill of a properties section (use on `Color.primary`).
        static let sectionFill: Double = 0.05
        /// Border of a properties section (use on `.separator`).
        static let sectionBorder: Double = 0.35
        /// Subtle hairline overlay above arbitrary content (use on `Color.primary`).
        static let hairlineOverlay: Double = 0.15
        /// Dimming applied to disabled rows.
        static let disabled: Double = 0.45
        /// Filled background of an active accent badge.
        static let accentBadge: Double = 0.14
        /// Pressed state for accent buttons.
        static let accentPressed: Double = 0.22
        /// Highlight ring on the active item in a discrete picker.
        static let accentSelection: Double = 0.3
        /// Border of an active accent surface.
        static let accentBorder: Double = 0.38
        /// Strong accent emphasis for drop-target highlights and similar hover affordances.
        static let accentEmphasis: Double = 0.75
    }

    enum Stroke {
        /// Subtle strokeBorder used to outline image previews / swatches against any background.
        static var subtle: Color { Color.primary.opacity(Opacity.hairlineOverlay) }
    }
}

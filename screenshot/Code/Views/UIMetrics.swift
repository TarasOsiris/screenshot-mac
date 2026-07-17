import SwiftUI

/// Centralized UI constants used across editor, inspector, properties bar, and toolbar views.
/// New views should reach for these values instead of hardcoding sizes/colors so the app stays visually coherent.
enum UIMetrics {
    enum FontSize {
        // macOS keeps the desktop-dense pointer-precision sizes; iPad bumps the small
        // tiers toward standard iOS text styles so labels stay legible at arm's length.
        #if os(macOS)
        /// Default body text for properties bar, popover content, and inspector sub-labels.
        /// Use for any small label that isn't a hint or a numeric badge.
        static let body: CGFloat = 11
        /// Compact label inside grouped controls (e.g. tile-fill labels, drop-zone hint).
        static let inlineLabel: CGFloat = 10
        /// Tiny hint text and axis labels ("X"/"Y", percent suffixes).
        static let hint: CGFloat = 9
        /// Numeric badge / value display next to sliders.
        static let numericBadge: CGFloat = 10
        /// Rows in compact menus/popovers (device picker, zoom presets, showcase toggles).
        static let menuRow: CGFloat = 12
        #else
        static let body: CGFloat = 14
        static let inlineLabel: CGFloat = 13
        static let hint: CGFloat = 11
        static let numericBadge: CGFloat = 12
        static let menuRow: CGFloat = 14
        #endif
        /// Section heading inside long-form copy (Help, settings descriptions).
        static let sectionHeading: CGFloat = 17
        /// Display title for help / about headers.
        static let displayTitle: CGFloat = 26
    }

    enum SliderWidth {
        #if os(macOS)
        /// Default width for sliders inside compact rows.
        static let standard: CGFloat = 80
        /// Wider sliders for fine-grained tuning (letter spacing).
        static let wide: CGFloat = 120
        #else
        // Longer tracks on iPad: finger dragging needs more travel for the same precision.
        static let standard: CGFloat = 120
        static let wide: CGFloat = 160
        #endif
    }

    enum ColorSwatch {
        #if os(macOS)
        /// Inline ColorPicker in toolbars and outline controls.
        static let inline: CGFloat = 30
        /// Fill swatch button preview.
        static let preview: CGFloat = 24
        /// Background-override indicator in the template control bar.
        static let overrideIndicator: CGFloat = 12
        static let overrideIndicatorIcon: CGFloat = 10
        #else
        // iPad gets larger swatches so the fill/color taps clear the touch-target floor.
        static let inline: CGFloat = 40
        static let preview: CGFloat = 40
        static let overrideIndicator: CGFloat = 24
        static let overrideIndicatorIcon: CGFloat = 16
        #endif
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
        /// Context-menu preview card corner radius.
        static let preview: CGFloat = 16
    }

    enum BorderWidth {
        /// Hairline border on light surfaces.
        static let hairline: CGFloat = 0.5
        /// Standard 1pt border.
        static let standard: CGFloat = 1
        /// Emphasized border (focus, drop target).
        static let emphasis: CGFloat = 1.5
        /// Bold rule (selected-row top/bottom accent lines).
        static let prominent: CGFloat = 2.5
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
        /// Light body tint behind the selected editor row (use on `Color.accentColor`).
        static let accentRowSelection: Double = 0.10
        /// Stronger tint behind the selected row's header strip. Layers over
        /// `accentRowSelection`, so the header reads ≈ 0.21 effective vs the ~0.10 body.
        static let accentRowHeader: Double = 0.12
    }

    enum Stroke {
        /// Subtle strokeBorder used to outline image previews / swatches against any background.
        static var subtle: Color { Color.primary.opacity(Opacity.hairlineOverlay) }
    }

    /// Read-only row preview ("App Store" tiles).
    enum Preview {
        /// Gap between template tiles at zoom 1.0; render sites scale it by zoom.
        /// Shared by `RowPreviewView`, its loading placeholder, and `RowContextMenuPreview`
        /// so their layouts stay in sync.
        static let tileGap: CGFloat = 12
    }

    /// Onboarding coach-mark popover card. Desktop-dense on macOS; iPad gets a
    /// wider card with larger type and touch-sized controls.
    enum Coach {
        #if os(macOS)
        static let width: CGFloat = 300
        static let titleSize: CGFloat = 15
        static let iconBadgeSize: CGFloat = 28
        static let iconSize: CGFloat = 14
        static let stackSpacing: CGFloat = 14
        static let padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 14)
        static let dotHeight: CGFloat = 6
        static let dotActiveWidth: CGFloat = 16
        static let closeIconSize: CGFloat = 9
        static let closeButtonSize: CGFloat = 18
        #else
        static let width: CGFloat = 400
        static let titleSize: CGFloat = 19
        static let iconBadgeSize: CGFloat = 38
        static let iconSize: CGFloat = 18
        static let stackSpacing: CGFloat = 16
        static let padding = EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 20)
        static let dotHeight: CGFloat = 8
        static let dotActiveWidth: CGFloat = 22
        static let closeIconSize: CGFloat = 13
        static let closeButtonSize: CGFloat = 30
        #endif
    }

    /// Dimensions for secondary windows (Settings, debug pickers, etc.). `settings` is the
    /// ideal open size; the window is resizable down to `settingsMinSize`.
    enum Window {
        static let settings = CGSize(width: 740, height: 560)
        static let settingsMinSize = CGSize(width: 600, height: 460)
        static let settingsSidebarWidth: CGFloat = 210
        static let debug = CGSize(width: 420, height: 400)
    }

    enum Spacing {
        /// Outer padding for centered modal panels (export progress, drop overlays).
        static let modal: CGFloat = 24
    }

    /// Tap-target dimensions for the small chevron menu placed next to a numeric text field
    /// (e.g. font-size / line-height presets in the properties bar).
    enum ChevronMenu {
        #if os(macOS)
        static let width: CGFloat = 14
        static let height: CGFloat = 20
        #else
        // iPad: widen to a comfortable tap target (44pt floor, matching ActionButton).
        static let width: CGFloat = 32
        static let height: CGFloat = 44
        #endif
    }

    /// Square tap target for icon-only buttons used in toolbars and bars (matches the explicit
    /// `frameSize: 24` passed to `ActionButton` across properties bars).
    enum IconButton {
        static let frameSize: CGFloat = 24
    }

    /// Default geometry for `ActionButton` and the manual icon buttons that mimic it.
    /// iPad gets larger glyphs and a 44pt touch-target floor (Apple HIG); macOS keeps the
    /// dense pointer-precision sizing unchanged.
    enum ActionButton {
        #if os(macOS)
        static let iconSize: CGFloat = 11
        static let frameSize: CGFloat = 22
        /// Minimum tap target enforced even when a smaller `frameSize` is passed. 0 = no floor on macOS.
        static let minTouchTarget: CGFloat = 0
        #else
        static let iconSize: CGFloat = 16
        static let frameSize: CGFloat = 44
        static let minTouchTarget: CGFloat = 44
        #endif
    }

    /// Capsule status badges in locale lists (Base tag, translation progress).
    enum StatusBadge {
        #if os(macOS)
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 2
        #else
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 3
        #endif
    }

    /// Bordered capsule action buttons inside list rows (e.g. per-language Translate).
    enum CapsuleButton {
        static let minContentHeight: CGFloat = 28
    }

    /// Prominent glass capsule built by hand where ButtonStyle can't apply
    /// (e.g. the principal toolbar slot strips button styles).
    enum ProminentCapsule {
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 8
    }

    enum GradientEditor {
        #if os(macOS)
        static let stopHandleSize: CGFloat = 14
        static let stopHandleHitTarget: CGFloat = 14
        static let stopBarHeight: CGFloat = 24
        static let controlsRowHeight: CGFloat = 24
        static let iconTapTarget: CGFloat = 22
        static let angleWheelSize: CGFloat = 36
        static let anglePresetButtonWidth: CGFloat = 14
        static let anglePresetButtonHeight: CGFloat = 14
        static let anglePresetGlyphSize: CGFloat = 7
        static let centerPickerSize: CGFloat = 48
        static let centerHandleSize: CGFloat = 8
        #else
        static let stopHandleSize: CGFloat = 24
        static let stopHandleHitTarget: CGFloat = 44
        static let stopBarHeight: CGFloat = 44
        static let controlsRowHeight: CGFloat = 44
        static let iconTapTarget: CGFloat = 28
        static let angleWheelSize: CGFloat = 56
        static let anglePresetButtonWidth: CGFloat = 40
        static let anglePresetButtonHeight: CGFloat = 40
        static let anglePresetGlyphSize: CGFloat = 14
        static let centerPickerSize: CGFloat = 56
        static let centerHandleSize: CGFloat = 14
        #endif
    }
}

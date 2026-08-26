import SwiftUI

// Shared platform-adaptive view modifiers. macOS-first call sites read as no-ops or dense
// controls; on iPad they expand to touch-target-friendly sizing. Centralized here so the same
// helper isn't re-declared per feature file (iPadColorSwatchFrame had been duplicated verbatim).
extension View {
    /// Enlarges the inline ColorPicker to the iPad touch target; macOS keeps the native well size.
    @ViewBuilder
    func iPadColorSwatchFrame() -> some View {
        #if os(macOS)
        self
        #else
        frame(width: UIMetrics.ColorSwatch.inline, height: UIMetrics.ColorSwatch.inline)
        #endif
    }

    /// Segmented pickers use the dense `.mini` size on macOS but a tappable `.regular` on iPad.
    @ViewBuilder
    func iPadTappableSegmentedControl() -> some View {
        #if os(macOS)
        controlSize(.mini)
        #else
        controlSize(.regular)
            .frame(minHeight: UIMetrics.GradientEditor.iconTapTarget)
            .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section))
            .contentShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section))
        #endif
    }

    /// Pads a text-only button up to the 40pt touch-target floor on iPad; no-op on macOS.
    @ViewBuilder
    func iPadResetTapTarget() -> some View {
        #if os(macOS)
        self
        #else
        padding(.horizontal, 10)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        #endif
    }

    /// Prominent toolbar button styling on iPad (glass on iOS 26+); no-op on macOS.
    @ViewBuilder
    func iPadToolbarProminentStyle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        self
        #endif
    }

    /// Presents `content` as a fitted sheet on macOS and a full-screen cover on iPad. Desktop-grade
    /// multi-step flows (the upload wizards) want a Mac sheet but a native full-screen screen on iPad.
    @ViewBuilder
    func platformAdaptiveSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

/// Scales a `UIMetrics.FontSize` point value with the user's text size on iPad, relative to
/// `.body`, so the tuned tier relationships survive. macOS deliberately keeps the exact point
/// value: the desktop bars are pointer-dense by design and AppKit has no Dynamic Type.
#if os(iOS)
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}
#endif

extension View {
    @ViewBuilder
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        #if os(macOS)
        font(.system(size: size, weight: weight))
        #else
        modifier(ScaledSystemFont(size: size, weight: weight))
        #endif
    }
}

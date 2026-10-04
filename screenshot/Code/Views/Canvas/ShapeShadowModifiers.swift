import SwiftUI

/// Applies a shape's configurable drop shadow.
///
/// `.compositingGroup()` flattens the shape's sub-layers (e.g. a device frame's screenshot +
/// bezel, or an image's clipped content) into one image first, so exactly one drop shadow is
/// cast from the unified silhouette — strictly behind the whole shape. Without it, SwiftUI casts
/// a shadow per sub-layer and an inner layer's offset shadow can bleed *inside* the shape.
///
/// Offscreen flip: SwiftUI's `.shadow` lowers to a CALayer `shadowOffset` that the
/// offscreen `NSHostingView.cacheDisplay` path (export / Preview) renders with its
/// **global** Y mirrored versus live on-screen compositing (editor) — so the shadow sits
/// below the device live but above it in export. (We use `.shadow` rather than a
/// `.blur`-based silhouette because `.blur` under-renders offscreen, which would make the
/// editor and export blur differ; `.shadow`'s blur is identical in both paths.)
///
/// The shadow's offset is applied in the shape's local (pre-rotation) space, but the
/// flip is global, so for a rotated shape a plain Y-negation points the shadow the wrong
/// way. We instead feed the export path the local offset `L = R(-θ)·F·R(θ)·(ox, oy)`
/// (F = vertical mirror), which after the global flip lands exactly where the editor
/// draws it, at any rotation. For θ = 0 this reduces to `(ox, -oy)`.
///
/// Shadow geometry is stored in model space and scaled by `displayScale` so the editor
/// (display scale) and export (scale 1.0) stay in parity — same precedent as
/// `displayOutlineWidth`.
struct ShadowModifier: ViewModifier {
    let shadow: ShadowConfig?
    let displayScale: CGFloat
    /// The shape's rotation in degrees — needed to compensate the offscreen flip when rotated.
    let rotationDegrees: Double
    @Environment(\.isExportRendering) private var isExportRendering

    func body(content: Content) -> some View {
        if let shadow, shadow.isActive {
            let offset = Self.compensatedOffset(
                ox: shadow.resolvedOffsetX * displayScale,
                oy: shadow.resolvedOffsetY * displayScale,
                rotationDegrees: rotationDegrees,
                isExportRendering: isExportRendering
            )
            content
                .compositingGroup()
                .shadow(
                    color: shadow.resolvedColor.opacity(shadow.resolvedOpacity),
                    radius: shadow.resolvedRadius * displayScale,
                    x: offset.x,
                    y: offset.y
                )
        } else {
            content
        }
    }

    /// Live: the offset as-authored. Export: `R(-θ)·F·R(θ)·(ox,oy)`, which after the
    /// offscreen global vertical flip reproduces the live offset at any rotation.
    /// macOS-only: the flip is an `NSHostingView.cacheDisplay` artifact — iOS exports render
    /// through `ImageRenderer`, which does not flip (verified by pixel probe on the simulator),
    /// so compensating there would point every shadow the wrong way.
    nonisolated static func compensatedOffset(
        ox: CGFloat,
        oy: CGFloat,
        rotationDegrees: Double,
        isExportRendering: Bool
    ) -> (x: CGFloat, y: CGFloat) {
        #if os(macOS)
        guard isExportRendering else { return (ox, oy) }
        let t = 2 * rotationDegrees * .pi / 180
        let c = cos(t), s = sin(t)
        return (x: ox * c - oy * s, y: -(ox * s + oy * c))
        #else
        return (ox, oy)
        #endif
    }
}

/// A fixed non-rotated `.shadow(y:)` with the same offscreen-flip compensation as
/// `ShadowModifier` — for the built-in ambient shadows (showcase tiles, abstract device
/// bodies), which would otherwise point up in exports and down in the editor.
/// macOS-only for the same reason as `ShadowModifier.compensatedOffset`.
private struct FlipCompensatedShadow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
    @Environment(\.isExportRendering) private var isExportRendering

    private var compensatedY: CGFloat {
        ShadowModifier.compensatedOffset(ox: 0, oy: y, rotationDegrees: 0, isExportRendering: isExportRendering).y
    }

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, x: 0, y: compensatedY)
    }
}

extension View {
    func flipCompensatedShadow(color: Color, radius: CGFloat, y: CGFloat) -> some View {
        modifier(FlipCompensatedShadow(color: color, radius: radius, y: y))
    }
}

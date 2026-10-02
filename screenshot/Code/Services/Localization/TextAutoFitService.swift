import CoreGraphics
import Foundation

/// What fitting one text shape's translation into its box changed.
struct TextAutoFitResult: Equatable {
    enum Action: String {
        case none
        case shrink
        case grow
        case growAndShrink = "grow_and_shrink"
    }

    /// Written into this locale's override only, so the base layout and other locales never move.
    var contribution: TextAutoFitContribution
    var fontScale: CGFloat
    var stillOverflows: Bool

    var action: Action {
        switch (contribution.addedHeight > 0, fontScale < 1) {
        case (true, true): .growAndShrink
        case (true, false): .grow
        case (false, true): .shrink
        case (false, false): .none
        }
    }

    static let unchanged = TextAutoFitResult(contribution: TextAutoFitContribution(), fontScale: 1, stillOverflows: false)
}

/// Fits an overflowing translation with the least visible change: a mild shrink, then a taller box
/// for that locale into free space, then the full shrink range.
enum TextAutoFitService {
    /// Below this, a shrunk headline reads visibly smaller than its siblings in other locales.
    static let preferredMinimumScale: CGFloat = 0.8

    private enum ShrinkMethod {
        case localeFontSize
        /// Already on for the shape; auto-fit never turns the shared flag on, since no fit could take it back.
        case shrinkToFit
    }

    /// `localeState` must not already carry this shape's auto-fit contribution for `localeCode`.
    static func fit(
        shape: CanvasShapeModel,
        localeCode: String,
        row: ScreenshotRow,
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> TextAutoFitResult {
        guard shape.type == .text else { return .unchanged }
        let resolved = LocaleService.resolveShape(shape, localeCode: localeCode, localeState: localeState)
        guard !(resolved.text ?? "").isEmpty else { return .unchanged }

        let input = TextFitInput(shape: resolved, availableFontFamilies: availableFontFamilies)
        let layout = TextFitLayout(input)
        let height = input.size.height
        if layout.fits(fontScale: 1, height: height) { return .unchanged }

        let shrink = shrinkMethod(for: shape, resolved: resolved, localeCode: localeCode, localeState: localeState)
        if shrink != nil {
            let mild = layout.largestFittingScale(height: height)
            if mild.fits, mild.scale >= preferredMinimumScale {
                return finish(resolved, growth: 0, offsetY: 0, fit: mild, shrink: shrink, families: availableFontFamilies)
            }
        }

        var growth: CGFloat = 0
        var offsetY: CGFloat = 0
        var fitsAtPreferredScale = false
        // Obstacle checks use axis-aligned frames, which a rotated box doesn't have.
        if resolved.rotation == 0 {
            let obstacles = row.activeShapes
                .filter { $0.id != shape.id }
                .map { LocaleService.resolveShape($0, localeCode: localeCode, localeState: localeState) }
            let room = verticalRoom(for: resolved, obstacles: obstacles, canvasHeight: row.templateHeight)
            let maxGrowth = room.above + room.below
            if maxGrowth >= 1 {
                let needed = layout.minimumFittingHeight(
                    fontScale: shrink == nil ? 1 : preferredMinimumScale, minHeight: height, maxHeight: height + maxGrowth
                )
                growth = min(maxGrowth, needed.map { ($0 - height).rounded(.up) } ?? maxGrowth)
                fitsAtPreferredScale = needed != nil
                offsetY = -upwardShare(of: growth, align: resolved.textVerticalAlign ?? .center, room: room)
            }
        }

        let grownHeight = height + growth
        let fit = shrink == nil
            ? (scale: 1, fits: layout.fits(fontScale: 1, height: grownHeight))
            : layout.largestFittingScale(
                height: grownHeight,
                atLeast: fitsAtPreferredScale ? preferredMinimumScale : TextFitMeasurer.minimumShrinkScale
            )
        return finish(resolved, growth: growth, offsetY: offsetY, fit: fit, shrink: shrink, families: availableFontFamilies)
    }

    private static func finish(
        _ resolved: CanvasShapeModel,
        growth: CGFloat,
        offsetY: CGFloat,
        fit: (scale: CGFloat, fits: Bool),
        shrink: ShrinkMethod?,
        families: Set<String>
    ) -> TextAutoFitResult {
        var contribution = TextAutoFitContribution(offsetY: offsetY, addedHeight: growth)
        guard fit.scale < 1, let shrink else {
            return TextAutoFitResult(contribution: contribution, fontScale: 1, stillOverflows: !fit.fits)
        }
        switch shrink {
        case .shrinkToFit:
            return TextAutoFitResult(contribution: contribution, fontScale: fit.scale, stillOverflows: !fit.fits)
        case .localeFontSize:
            // A smaller point size isn't exactly a scaled raster (tracking stays put), so search real sizes.
            let baseSize = resolved.fontSize ?? CanvasShapeModel.defaultFontSize
            var candidate = resolved
            candidate.height += growth
            func fits(_ size: CGFloat) -> Bool {
                candidate.fontSize = size
                return TextFitMeasurer.fits(TextFitInput(shape: candidate, availableFontFamilies: families))
            }
            var low = (baseSize * TextFitMeasurer.minimumShrinkScale).rounded(.up)
            var high = max(low, (baseSize * fit.scale).rounded(.down))
            let lowFits = fits(low)
            if lowFits {
                while low < high {
                    let mid = ((low + high + 1) / 2).rounded(.down)
                    if fits(mid) { low = mid } else { high = mid - 1 }
                }
            }
            contribution.fontSize = low
            return TextAutoFitResult(contribution: contribution, fontScale: low / baseSize, stillOverflows: !lowFits)
        }
    }

    /// A per-locale font size where the text is plain and the locale has no size of its own;
    /// otherwise only a Shrink to Fit the user already turned on.
    private static func shrinkMethod(
        for shape: CanvasShapeModel,
        resolved: CanvasShapeModel,
        localeCode: String,
        localeState: LocaleState
    ) -> ShrinkMethod? {
        if shape.shrinkToFit == true { return .shrinkToFit }
        if resolved.richText == nil, localeState.override(forCode: localeCode, shapeId: shape.id)?.fontSize == nil {
            return .localeFontSize
        }
        return nil
    }

    /// Free space above and below `box` before it leaves the canvas or covers a shape it doesn't already overlap.
    static func verticalRoom(
        for box: CanvasShapeModel,
        obstacles: [CanvasShapeModel],
        canvasHeight: CGFloat
    ) -> (above: CGFloat, below: CGFloat) {
        let top = box.y
        let bottom = box.y + box.height
        var above = max(0, top)
        var below = max(0, canvasHeight - bottom)
        for obstacle in obstacles {
            let bounds = obstacle.aabb
            guard bounds.maxX > box.x, bounds.minX < box.x + box.width else { continue }
            if bounds.minY >= bottom {
                below = min(below, bounds.minY - bottom)
            } else if bounds.maxY <= top {
                above = min(above, top - bounds.maxY)
            }
        }
        return (above, below)
    }

    /// How much of `growth` goes above the box, keeping the text's anchored edge fixed while there is room.
    private static func upwardShare(
        of growth: CGFloat,
        align: TextVerticalAlign,
        room: (above: CGFloat, below: CGFloat)
    ) -> CGFloat {
        switch align {
        case .top:
            return growth - min(growth, room.below)
        case .bottom:
            return min(growth, room.above)
        case .center:
            let up = min(growth / 2, room.above)
            let down = min(growth - up, room.below)
            return growth - down
        }
    }
}

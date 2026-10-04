import Foundation

extension CanvasShapeModel {
    /// Re-applies only the caller's changes relative to `oldBase` onto `newBase`.
    /// This is used when a discrete edit was prepared from a stale snapshot while a
    /// continuous edit was still in flight for the same shape.
    func rebased(from oldBase: CanvasShapeModel, onto newBase: CanvasShapeModel) -> CanvasShapeModel {
        var result = newBase

        if type != oldBase.type { result.type = type }
        if x != oldBase.x { result.x = x }
        if y != oldBase.y { result.y = y }
        if width != oldBase.width { result.width = width }
        if height != oldBase.height { result.height = height }
        if rotation != oldBase.rotation { result.rotation = rotation }
        if borderRadius != oldBase.borderRadius { result.borderRadius = borderRadius }
        if colorData != oldBase.colorData { result.colorData = colorData }
        if opacity != oldBase.opacity { result.opacity = opacity }

        if text != oldBase.text { result.text = text }
        if richText != oldBase.richText { result.richText = richText }
        if fontName != oldBase.fontName { result.fontName = fontName }
        if fontSize != oldBase.fontSize { result.fontSize = fontSize }
        if fontWeight != oldBase.fontWeight { result.fontWeight = fontWeight }
        if textAlign != oldBase.textAlign { result.textAlign = textAlign }
        if textVerticalAlign != oldBase.textVerticalAlign { result.textVerticalAlign = textVerticalAlign }
        if italic != oldBase.italic { result.italic = italic }
        if uppercase != oldBase.uppercase { result.uppercase = uppercase }
        if letterSpacing != oldBase.letterSpacing { result.letterSpacing = letterSpacing }
        if lineSpacing != oldBase.lineSpacing { result.lineSpacing = lineSpacing }
        if lineHeightMultiple != oldBase.lineHeightMultiple { result.lineHeightMultiple = lineHeightMultiple }
        if translationKey != oldBase.translationKey { result.translationKey = translationKey }

        if shrinkToFit != oldBase.shrinkToFit { result.shrinkToFit = shrinkToFit }

        if imageFileName != oldBase.imageFileName { result.imageFileName = imageFileName }
        if imageCrop != oldBase.imageCrop { result.imageCrop = imageCrop }
        if deviceCategory != oldBase.deviceCategory { result.deviceCategory = deviceCategory }
        if deviceBodyColorData != oldBase.deviceBodyColorData { result.deviceBodyColorData = deviceBodyColorData }
        if deviceFrameId != oldBase.deviceFrameId { result.deviceFrameId = deviceFrameId }
        if screenshotFileName != oldBase.screenshotFileName { result.screenshotFileName = screenshotFileName }
        if devicePitch != oldBase.devicePitch { result.devicePitch = devicePitch }
        if deviceYaw != oldBase.deviceYaw { result.deviceYaw = deviceYaw }
        if deviceBodyMaterial != oldBase.deviceBodyMaterial { result.deviceBodyMaterial = deviceBodyMaterial }
        if deviceLighting != oldBase.deviceLighting { result.deviceLighting = deviceLighting }
        if hideCameraCutout != oldBase.hideCameraCutout { result.hideCameraCutout = hideCameraCutout }
        if shadow != oldBase.shadow { result.shadow = shadow }

        if svgContent != oldBase.svgContent { result.svgContent = svgContent }
        if svgUseColor != oldBase.svgUseColor { result.svgUseColor = svgUseColor }

        if outlineColorData != oldBase.outlineColorData { result.outlineColorData = outlineColorData }
        if outlineWidth != oldBase.outlineWidth { result.outlineWidth = outlineWidth }
        if textBackgroundColorData != oldBase.textBackgroundColorData { result.textBackgroundColorData = textBackgroundColorData }
        if textBackgroundCornerRadius != oldBase.textBackgroundCornerRadius { result.textBackgroundCornerRadius = textBackgroundCornerRadius }
        if textBackgroundPadding != oldBase.textBackgroundPadding { result.textBackgroundPadding = textBackgroundPadding }
        if textBackgroundOutlineColorData != oldBase.textBackgroundOutlineColorData { result.textBackgroundOutlineColorData = textBackgroundOutlineColorData }
        if textBackgroundOutlineWidth != oldBase.textBackgroundOutlineWidth { result.textBackgroundOutlineWidth = textBackgroundOutlineWidth }
        if textBackgroundOpacity != oldBase.textBackgroundOpacity { result.textBackgroundOpacity = textBackgroundOpacity }
        if starPointCount != oldBase.starPointCount { result.starPointCount = starPointCount }

        if fillStyle != oldBase.fillStyle { result.fillStyle = fillStyle }
        if fillGradientConfig != oldBase.fillGradientConfig { result.fillGradientConfig = fillGradientConfig }
        if fillImageConfig != oldBase.fillImageConfig { result.fillImageConfig = fillImageConfig }

        if clipToTemplate != oldBase.clipToTemplate { result.clipToTemplate = clipToTemplate }
        if isLocked != oldBase.isLocked { result.isLocked = isLocked }

        return result
    }
}

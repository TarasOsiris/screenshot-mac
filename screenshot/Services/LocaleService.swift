import Foundation

enum LocaleService {

    /// Apply the active locale's overrides to a shape. Returns the shape unchanged if base locale.
    static func resolveShape(_ shape: CanvasShapeModel, localeState: LocaleState) -> CanvasShapeModel {
        resolveShape(shape, localeCode: localeState.activeLocaleCode, localeState: localeState)
    }

    /// Resolve an array of shapes for the active locale.
    static func resolveShapes(_ shapes: [CanvasShapeModel], localeState: LocaleState) -> [CanvasShapeModel] {
        guard !localeState.isBaseLocale else { return shapes }
        return shapes.map { resolveShape($0, localeState: localeState) }
    }

    /// Resolve a single shape for a specific locale code.
    static func resolveShape(_ shape: CanvasShapeModel, localeCode: String, localeState: LocaleState) -> CanvasShapeModel {
        guard localeCode != localeState.baseLocaleCode else { return shape }
        guard let override = localeState.override(forCode: localeCode, shapeId: shape.id) else { return shape }
        return applyOverride(override, to: shape)
    }

    /// Given the base shape and an updated (resolved) shape, split changes into base shape mutations
    /// and locale overrides. Updates localeState overrides directly. Returns the base shape to store.
    static func splitUpdate(base: CanvasShapeModel, updated: CanvasShapeModel, localeState: inout LocaleState) -> CanvasShapeModel {
        guard !localeState.isBaseLocale else {
            return updated
        }

        // Start from updated, restore overridable properties to base values
        var baseResult = updated
        baseResult.x = base.x
        baseResult.y = base.y
        baseResult.width = base.width
        baseResult.height = base.height

        // Build override from position/size deltas vs base
        var override = ShapeLocaleOverride()
        let dx = updated.x - base.x
        let dy = updated.y - base.y
        let dw = updated.width - base.width
        let dh = updated.height - base.height
        if dx != 0 { override.offsetX = dx }
        if dy != 0 { override.offsetY = dy }
        if dw != 0 { override.offsetWidth = dw }
        if dh != 0 { override.offsetHeight = dh }

        // Text shapes also have text property overrides
        if updated.type == .text {
            baseResult.text = base.text
            baseResult.fontName = base.fontName
            baseResult.fontSize = base.fontSize
            baseResult.fontWeight = base.fontWeight
            baseResult.textAlign = base.textAlign
            baseResult.italic = base.italic
            baseResult.letterSpacing = base.letterSpacing
            baseResult.lineSpacing = base.lineSpacing

            if updated.text != base.text { override.text = updated.text }
            if updated.fontName != base.fontName { override.fontName = updated.fontName }
            if updated.fontSize != base.fontSize { override.fontSize = updated.fontSize }
            if updated.fontWeight != base.fontWeight { override.fontWeight = updated.fontWeight }
            if updated.textAlign != base.textAlign { override.textAlign = updated.textAlign }
            if updated.italic != base.italic { override.italic = updated.italic }
            if updated.letterSpacing != base.letterSpacing { override.letterSpacing = updated.letterSpacing }
            if updated.lineSpacing != base.lineSpacing { override.lineSpacing = updated.lineSpacing }
        }

        // Device/image shapes have display image overrides
        if updated.type == .device || updated.type == .image {
            if updated.displayImageFileName != base.displayImageFileName {
                override.overrideImageFileName = updated.displayImageFileName
            }
            baseResult.displayImageFileName = base.displayImageFileName
        }

        setShapeOverride(&localeState, shapeId: base.id, override: override.isEmpty ? nil : override)
        return baseResult
    }

    /// Set or remove a shape's override for the active locale.
    static func setShapeOverride(_ state: inout LocaleState, shapeId: UUID, override: ShapeLocaleOverride?) {
        setShapeOverride(&state, localeCode: state.activeLocaleCode, shapeId: shapeId, override: override)
    }

    /// Set or remove a shape's override for a specific locale.
    static func setShapeOverride(_ state: inout LocaleState, localeCode code: String, shapeId: UUID, override: ShapeLocaleOverride?) {
        let key = shapeId.uuidString
        if let override {
            state.overrides[code, default: [:]][key] = override
        } else {
            state.overrides[code]?.removeValue(forKey: key)
            cleanupEmptyOverrides(&state, forCode: code)
        }
    }

    /// Remove all locale overrides for a deleted shape.
    static func removeShapeOverrides(_ state: inout LocaleState, shapeId: UUID) {
        let key = shapeId.uuidString
        for localeCode in state.overrides.keys {
            state.overrides[localeCode]?.removeValue(forKey: key)
            cleanupEmptyOverrides(&state, forCode: localeCode)
        }
    }

    private static func cleanupEmptyOverrides(_ state: inout LocaleState, forCode code: String) {
        if state.overrides[code]?.isEmpty == true {
            state.overrides.removeValue(forKey: code)
        }
    }

    /// Copy overrides from one shape ID to another (for duplication).
    static func copyShapeOverrides(_ state: inout LocaleState, fromId: UUID, toId: UUID) {
        let fromKey = fromId.uuidString
        let toKey = toId.uuidString
        for localeCode in state.overrides.keys {
            if let override = state.overrides[localeCode]?[fromKey] {
                state.overrides[localeCode]?[toKey] = override
            }
        }
    }

    /// Add a new locale.
    static func addLocale(_ state: inout LocaleState, locale: LocaleDefinition) {
        guard !state.locales.contains(where: { $0.code == locale.code }) else { return }
        state.locales.append(locale)
    }

    /// Remove a locale and its overrides.
    static func removeLocale(_ state: inout LocaleState, code: String) {
        guard code != state.baseLocaleCode else { return }
        state.locales.removeAll { $0.code == code }
        state.overrides.removeValue(forKey: code)
        if state.activeLocaleCode == code {
            state.activeLocaleCode = state.baseLocaleCode
        }
    }

    // MARK: - Private

    private static func applyOverride(_ override: ShapeLocaleOverride, to shape: CanvasShapeModel) -> CanvasShapeModel {
        var result = shape
        if let dx = override.offsetX { result.x = shape.x + dx }
        if let dy = override.offsetY { result.y = shape.y + dy }
        if let dw = override.offsetWidth { result.width = shape.width + dw }
        if let dh = override.offsetHeight { result.height = shape.height + dh }
        if let text = override.text { result.text = text }
        if let fontName = override.fontName { result.fontName = fontName }
        if let fontSize = override.fontSize { result.fontSize = fontSize }
        if let fontWeight = override.fontWeight { result.fontWeight = fontWeight }
        if let textAlign = override.textAlign { result.textAlign = textAlign }
        if let italic = override.italic { result.italic = italic }
        if let letterSpacing = override.letterSpacing { result.letterSpacing = letterSpacing }
        if let lineSpacing = override.lineSpacing { result.lineSpacing = lineSpacing }
        if let fileName = override.overrideImageFileName {
            result.displayImageFileName = fileName
        }
        return result
    }
}

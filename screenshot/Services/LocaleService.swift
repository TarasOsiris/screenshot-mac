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
        guard let overrides = localeState.overrides[localeCode],
              let override = overrides[shape.id.uuidString] else { return shape }
        return applyOverride(override, to: shape)
    }

    /// Given the base shape and an updated (resolved) shape, split changes into base shape mutations
    /// and locale overrides. Updates localeState overrides directly. Returns the base shape to store.
    static func splitUpdate(base: CanvasShapeModel, updated: CanvasShapeModel, localeState: inout LocaleState) -> CanvasShapeModel {
        guard !localeState.isBaseLocale else {
            return updated
        }

        // Only text shapes have overridable properties
        guard updated.type == .text else {
            return updated
        }

        // Start from updated, restore base's text properties (overridable props stay on base)
        var baseResult = updated
        baseResult.text = base.text
        baseResult.fontName = base.fontName
        baseResult.fontSize = base.fontSize
        baseResult.fontWeight = base.fontWeight
        baseResult.textAlign = base.textAlign
        baseResult.italic = base.italic
        baseResult.letterSpacing = base.letterSpacing
        baseResult.lineSpacing = base.lineSpacing

        // Build override from text property differences vs base
        var override = ShapeLocaleOverride()
        if updated.text != base.text { override.text = updated.text }
        if updated.fontName != base.fontName { override.fontName = updated.fontName }
        if updated.fontSize != base.fontSize { override.fontSize = updated.fontSize }
        if updated.fontWeight != base.fontWeight { override.fontWeight = updated.fontWeight }
        if updated.textAlign != base.textAlign { override.textAlign = updated.textAlign }
        if updated.italic != base.italic { override.italic = updated.italic }
        if updated.letterSpacing != base.letterSpacing { override.letterSpacing = updated.letterSpacing }
        if updated.lineSpacing != base.lineSpacing { override.lineSpacing = updated.lineSpacing }

        setShapeOverride(&localeState, shapeId: base.id, override: override.isEmpty ? nil : override)
        return baseResult
    }

    /// Set or remove a shape's override for the active locale.
    static func setShapeOverride(_ state: inout LocaleState, shapeId: UUID, override: ShapeLocaleOverride?) {
        let code = state.activeLocaleCode
        let key = shapeId.uuidString
        if let override {
            state.overrides[code, default: [:]][key] = override
        } else {
            state.overrides[code]?.removeValue(forKey: key)
            if state.overrides[code]?.isEmpty == true {
                state.overrides.removeValue(forKey: code)
            }
        }
    }

    /// Remove all locale overrides for a deleted shape.
    static func removeShapeOverrides(_ state: inout LocaleState, shapeId: UUID) {
        let key = shapeId.uuidString
        for localeCode in state.overrides.keys {
            state.overrides[localeCode]?.removeValue(forKey: key)
            if state.overrides[localeCode]?.isEmpty == true {
                state.overrides.removeValue(forKey: localeCode)
            }
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
        if let text = override.text { result.text = text }
        if let fontName = override.fontName { result.fontName = fontName }
        if let fontSize = override.fontSize { result.fontSize = fontSize }
        if let fontWeight = override.fontWeight { result.fontWeight = fontWeight }
        if let textAlign = override.textAlign { result.textAlign = textAlign }
        if let italic = override.italic { result.italic = italic }
        if let letterSpacing = override.letterSpacing { result.letterSpacing = letterSpacing }
        if let lineSpacing = override.lineSpacing { result.lineSpacing = lineSpacing }
        return result
    }
}

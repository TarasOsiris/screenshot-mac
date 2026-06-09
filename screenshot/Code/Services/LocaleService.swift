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

        setShapeOverride(&localeState, shapeId: base.id, override: makeOverride(base: base, resolved: updated))
        var baseResult = updated
        restoreOverridableFields(&baseResult, from: base)
        return baseResult
    }

    /// Reset the fields `makeOverride` treats as locale-overridable back to their base values.
    /// Keep this field set in lockstep with `makeOverride`.
    private static func restoreOverridableFields(_ result: inout CanvasShapeModel, from base: CanvasShapeModel) {
        result.x = base.x
        result.y = base.y
        result.width = base.width
        result.height = base.height
        if base.type == .text {
            result.text = base.text
            result.richText = base.richText
            result.fontName = base.fontName
            result.fontSize = base.fontSize
            result.fontWeight = base.fontWeight
            result.textAlign = base.textAlign
            result.italic = base.italic
            result.uppercase = base.uppercase
            result.letterSpacing = base.letterSpacing
            result.lineSpacing = base.lineSpacing
            result.lineHeightMultiple = base.lineHeightMultiple
        }
        if base.type == .device || base.type == .image {
            result.displayImageFileName = base.displayImageFileName
        }
    }

    /// Build the override that expresses `resolved` as a delta from `base`. nil if identical.
    static func makeOverride(base: CanvasShapeModel, resolved: CanvasShapeModel) -> ShapeLocaleOverride? {
        var override = ShapeLocaleOverride()
        let dx = resolved.x - base.x
        let dy = resolved.y - base.y
        let dw = resolved.width - base.width
        let dh = resolved.height - base.height
        if dx != 0 { override.offsetX = dx }
        if dy != 0 { override.offsetY = dy }
        if dw != 0 { override.offsetWidth = dw }
        if dh != 0 { override.offsetHeight = dh }

        if resolved.type == .text {
            if resolved.text != base.text { override.text = resolved.text }
            if resolved.richText != base.richText {
                override.richText = resolved.richText
                override.clearsRichText = resolved.richText == nil && base.richText != nil ? true : nil
            }
            if resolved.fontName != base.fontName { override.fontName = resolved.fontName }
            if resolved.fontSize != base.fontSize { override.fontSize = resolved.fontSize }
            if resolved.fontWeight != base.fontWeight { override.fontWeight = resolved.fontWeight }
            if resolved.textAlign != base.textAlign { override.textAlign = resolved.textAlign }
            if resolved.italic != base.italic { override.italic = resolved.italic }
            if resolved.uppercase != base.uppercase { override.uppercase = resolved.uppercase }
            if resolved.letterSpacing != base.letterSpacing { override.letterSpacing = resolved.letterSpacing }
            if resolved.lineSpacing != base.lineSpacing { override.lineSpacing = resolved.lineSpacing }
            if resolved.lineHeightMultiple != base.lineHeightMultiple { override.lineHeightMultiple = resolved.lineHeightMultiple }
        }

        if resolved.type == .device || resolved.type == .image {
            if resolved.displayImageFileName != base.displayImageFileName {
                override.overrideImageFileName = resolved.displayImageFileName
            }
        }

        return override.isEmpty ? nil : override
    }

    /// Promote `newBaseCode` to be the base locale: bake its resolved appearance into every
    /// shape's base content, re-anchor all other locales as overrides relative to it, and move
    /// it to the front of `state.locales`. Owns both the shape rebase and the reorder so callers
    /// can't get the ordering wrong.
    static func setBaseLocale(_ newBaseCode: String, rows: inout [ScreenshotRow], state: inout LocaleState) {
        guard state.hasLocale(newBaseCode), newBaseCode != state.baseLocaleCode else { return }
        for r in rows.indices {
            for s in rows[r].shapes.indices {
                rows[r].shapes[s] = rebaseShape(rows[r].shapes[s], to: newBaseCode, state: &state)
            }
        }
        if let idx = state.locales.firstIndex(where: { $0.code == newBaseCode }) {
            state.locales.insert(state.locales.remove(at: idx), at: 0)
        }
    }

    /// Re-express one shape so `newBaseCode` becomes the base locale: returns the new base shape
    /// and rewrites the shape's overrides across all locales (relative to the new base). The
    /// caller reorders `state.locales` after rebasing every shape (see `setBaseLocale`).
    private static func rebaseShape(_ shape: CanvasShapeModel, to newBaseCode: String, state: inout LocaleState) -> CanvasShapeModel {
        // Snapshot every locale's resolved appearance before mutating any override.
        let resolvedByCode = Dictionary(
            state.locales.map { ($0.code, resolveShape(shape, localeCode: $0.code, localeState: state)) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let newBaseShape = resolvedByCode[newBaseCode] else { return shape }

        for (code, resolved) in resolvedByCode {
            if code == newBaseCode {
                setShapeOverride(&state, localeCode: code, shapeId: shape.id, override: nil)
            } else {
                setShapeOverride(&state, localeCode: code, shapeId: shape.id, override: makeOverride(base: newBaseShape, resolved: resolved))
            }
        }
        return newBaseShape
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
        guard !state.hasLocale(locale.code) else { return }
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
        if let text = override.text {
            result.text = text
            if override.richText == nil {
                result.richText = nil
            }
        }
        if override.clearsRichText == true {
            result.richText = nil
        } else if let richText = override.richText {
            result.richText = richText
        }
        if let fontName = override.fontName { result.fontName = fontName }
        if let fontSize = override.fontSize { result.fontSize = fontSize }
        if let fontWeight = override.fontWeight { result.fontWeight = fontWeight }
        if let textAlign = override.textAlign { result.textAlign = textAlign }
        if let italic = override.italic { result.italic = italic }
        if let uppercase = override.uppercase { result.uppercase = uppercase }
        if let letterSpacing = override.letterSpacing { result.letterSpacing = letterSpacing }
        if let lineSpacing = override.lineSpacing { result.lineSpacing = lineSpacing }
        if let lineHeightMultiple = override.lineHeightMultiple { result.lineHeightMultiple = lineHeightMultiple }
        if let fileName = override.overrideImageFileName {
            result.displayImageFileName = fileName
        }
        return result
    }
}

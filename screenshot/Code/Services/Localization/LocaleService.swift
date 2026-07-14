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
    ///
    /// Translated *text* (`text`/`richText`) is keyed by the shape's `textTranslationKey` so reused
    /// strings share one entry; per-shape styling/geometry (offsets, font, image) stays keyed by the
    /// shape's own `id`. For an unlinked shape both keys coincide, matching the historical behavior.
    static func resolveShape(_ shape: CanvasShapeModel, localeCode: String, localeState: LocaleState) -> CanvasShapeModel {
        guard localeCode != localeState.baseLocaleCode else { return shape }
        let (styleOverride, textOverride) = shapeOverrides(for: shape, localeCode: localeCode, localeState: localeState)
        guard styleOverride != nil || textOverride != nil else { return shape }
        return applyOverride(style: styleOverride, text: textOverride, to: shape)
    }

    /// The two override sources a shape resolves against: style/geometry keyed by the
    /// shape's `id`, translated text keyed by its `textTranslationKey`. Single source of
    /// truth shared by `resolveShape` and `rowIsLocaleNeutral` so the neutrality check can
    /// never drift from what resolution actually reads.
    private static func shapeOverrides(
        for shape: CanvasShapeModel,
        localeCode: String,
        localeState: LocaleState
    ) -> (style: ShapeLocaleOverride?, text: ShapeLocaleOverride?) {
        (localeState.override(forCode: localeCode, shapeId: shape.id),
         localeState.overrides[localeCode]?[shape.textTranslationKey])
    }

    /// True when `localeCode` resolves every shape in the row unchanged, so a neutral row
    /// renders pixel-identical to the base locale and export can reuse one render for all
    /// such locales. Backgrounds are not locale-overridable, so shapes are the only inputs
    /// that matter.
    static func rowIsLocaleNeutral(row: ScreenshotRow, localeCode: String, localeState: LocaleState) -> Bool {
        guard localeCode != localeState.baseLocaleCode else { return true }
        return !row.activeShapes.contains { shape in
            let (style, text) = shapeOverrides(for: shape, localeCode: localeCode, localeState: localeState)
            return style != nil || text != nil
        }
    }

    /// Given the base shape and an updated (resolved) shape, split changes into base shape mutations
    /// and locale overrides. Updates localeState overrides directly. Returns the base shape to store.
    static func splitUpdate(base: CanvasShapeModel, updated: CanvasShapeModel, localeState: inout LocaleState) -> CanvasShapeModel {
        splitUpdate(base: base, updated: updated, localeState: &localeState, forLocaleCode: localeState.activeLocaleCode)
    }

    /// Split an update against an explicit locale code rather than the active locale, so a
    /// deferred commit (e.g. inline text flushed after the active locale already changed)
    /// always lands in the locale it was edited in.
    static func splitUpdate(base: CanvasShapeModel, updated: CanvasShapeModel, localeState: inout LocaleState, forLocaleCode code: String) -> CanvasShapeModel {
        guard code != localeState.baseLocaleCode else {
            return updated
        }

        writeSplitOverride(&localeState, localeCode: code, shapeId: base.id, textKey: base.textTranslationKey,
                           override: makeOverride(base: base, resolved: updated))
        var baseResult = updated
        restoreOverridableFields(&baseResult, from: base)
        return baseResult
    }

    /// Persist a full override split across the two key spaces: translated-text fields under the
    /// shape's `textTranslationKey` (shared by reused strings), all other fields under its `id`.
    /// For an unlinked shape the keys coincide, so the whole override lands under `id`. Pass
    /// `writeText: false` to leave an already-written shared-text entry untouched (when rebasing
    /// several members of one reused string in a single pass).
    static func writeSplitOverride(_ state: inout LocaleState, localeCode code: String, shapeId: UUID, textKey: String, override: ShapeLocaleOverride?, writeText: Bool = true) {
        if textKey == shapeId.uuidString {
            setShapeOverride(&state, localeCode: code, shapeId: shapeId, override: override)
            return
        }
        if writeText {
            setTextFieldsOverride(&state, localeCode: code, key: textKey, text: override?.text, richText: override?.richText, clearsRichText: override?.clearsRichText)
        }
        var style = override ?? ShapeLocaleOverride()
        style.clearTranslatedText()
        setShapeOverride(&state, localeCode: code, shapeId: shapeId, override: style.isEmpty ? nil : style)
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

        // Snapshot every shape's resolved appearance per locale BEFORE mutating any override, so a
        // text key shared by multiple shapes isn't read back after an earlier shape rewrote it.
        var resolvedByShape: [UUID: [String: CanvasShapeModel]] = [:]
        for row in rows {
            for shape in row.shapes {
                resolvedByShape[shape.id] = Dictionary(
                    state.locales.map { ($0.code, resolveShape(shape, localeCode: $0.code, localeState: state)) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }

        var rewrittenTextKeys = Set<String>()
        for r in rows.indices {
            for s in rows[r].shapes.indices {
                let shape = rows[r].shapes[s]
                guard let resolved = resolvedByShape[shape.id], let newBaseShape = resolved[newBaseCode] else { continue }
                let textKey = shape.textTranslationKey
                let isLinked = textKey != shape.id.uuidString
                // A shared text key is rewritten only once (the first member that reaches it).
                let writeText = !isLinked || rewrittenTextKeys.insert(textKey).inserted

                for (code, res) in resolved {
                    let full = code == newBaseCode ? nil : makeOverride(base: newBaseShape, resolved: res)
                    writeSplitOverride(&state, localeCode: code, shapeId: shape.id, textKey: textKey, override: full, writeText: writeText)
                }
                rows[r].shapes[s] = newBaseShape
            }
        }

        if let idx = state.locales.firstIndex(where: { $0.code == newBaseCode }) {
            state.locales.insert(state.locales.remove(at: idx), at: 0)
        }
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

    // MARK: - Shared translation text (reuse)

    /// Set or clear just the translated-text fields under an explicit catalog `key` for one locale,
    /// preserving any per-shape style/geometry already stored under that key. Used by translation
    /// editing and reuse, where text and styling live under different keys for linked shapes.
    static func setTextOverride(_ state: inout LocaleState, localeCode code: String, key: String, text: String?) {
        setTextFieldsOverride(&state, localeCode: code, key: key, text: (text?.isEmpty == true) ? nil : text, richText: nil, clearsRichText: nil)
    }

    /// Set or clear the full translated-text triple (plain / rich / clears-rich) under a key for one
    /// locale, preserving any per-shape style fields already stored there. Drops the override if it
    /// becomes empty.
    static func setTextFieldsOverride(_ state: inout LocaleState, localeCode code: String, key: String, text: String?, richText: String?, clearsRichText: Bool?) {
        var override = state.overrides[code]?[key] ?? ShapeLocaleOverride()
        override.text = text
        override.richText = richText
        override.clearsRichText = clearsRichText
        if override.isEmpty {
            state.overrides[code]?.removeValue(forKey: key)
            cleanupEmptyOverrides(&state, forCode: code)
        } else {
            state.overrides[code, default: [:]][key] = override
        }
    }

    /// Copy translated-text fields from one key to another for every locale. With `removeSource`,
    /// also strips them from the source — i.e. a move. Used by reuse link (move) and unlink (copy).
    static func copyTextOverrides(_ state: inout LocaleState, fromKey: String, toKey: String, removeSource: Bool = false) {
        for code in Array(state.overrides.keys) {
            guard let from = state.overrides[code]?[fromKey], from.hasTranslatedTextField else { continue }
            var to = state.overrides[code]?[toKey] ?? ShapeLocaleOverride()
            to.copyTranslatedText(from: from)
            state.overrides[code, default: [:]][toKey] = to
            if removeSource {
                var src = from
                src.clearTranslatedText()
                if src.isEmpty { state.overrides[code]?.removeValue(forKey: fromKey) } else { state.overrides[code]?[fromKey] = src }
                cleanupEmptyOverrides(&state, forCode: code)
            }
        }
    }

    static func moveTextOverrides(_ state: inout LocaleState, fromKey: String, toKey: String) {
        copyTextOverrides(&state, fromKey: fromKey, toKey: toKey, removeSource: true)
    }

    /// Remove translated-text fields under a key for every locale, preserving any style fields and
    /// dropping fully-empty overrides. Used to clear a shape's own text when it adopts a shared key.
    static func stripTextOverrides(_ state: inout LocaleState, key: String) {
        for code in Array(state.overrides.keys) {
            guard var ov = state.overrides[code]?[key] else { continue }
            ov.clearTranslatedText()
            if ov.isEmpty { state.overrides[code]?.removeValue(forKey: key) } else { state.overrides[code]?[key] = ov }
            cleanupEmptyOverrides(&state, forCode: code)
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

    private static func applyOverride(style: ShapeLocaleOverride?, text textOverride: ShapeLocaleOverride?, to shape: CanvasShapeModel) -> CanvasShapeModel {
        var result = shape
        if let style {
            if let dx = style.offsetX { result.x = shape.x + dx }
            if let dy = style.offsetY { result.y = shape.y + dy }
            if let dw = style.offsetWidth { result.width = shape.width + dw }
            if let dh = style.offsetHeight { result.height = shape.height + dh }
            if let fontName = style.fontName { result.fontName = fontName }
            if let fontSize = style.fontSize { result.fontSize = fontSize }
            if let fontWeight = style.fontWeight { result.fontWeight = fontWeight }
            if let textAlign = style.textAlign { result.textAlign = textAlign }
            if let italic = style.italic { result.italic = italic }
            if let uppercase = style.uppercase { result.uppercase = uppercase }
            if let letterSpacing = style.letterSpacing { result.letterSpacing = letterSpacing }
            if let lineSpacing = style.lineSpacing { result.lineSpacing = lineSpacing }
            if let lineHeightMultiple = style.lineHeightMultiple { result.lineHeightMultiple = lineHeightMultiple }
            if let fileName = style.overrideImageFileName { result.displayImageFileName = fileName }
        }
        if let textOverride {
            if let text = textOverride.text {
                result.text = text
                if textOverride.richText == nil { result.richText = nil }
            }
            if textOverride.clearsRichText == true {
                result.richText = nil
            } else if let richText = textOverride.richText {
                result.richText = richText
            }
        }
        return result
    }
}

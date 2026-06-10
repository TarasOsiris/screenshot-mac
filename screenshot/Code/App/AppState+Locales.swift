import SwiftUI

extension AppState {

    // MARK: - Locales

    func setActiveLocale(_ code: String) {
        guard code != localeState.activeLocaleCode else { return }
        guard localeState.hasLocale(code) else { return }
        commitAllPendingEdits() // flush any in-progress edit to the old locale before switching
        localeState.activeLocaleCode = code
        loadScreenshotImages() // evict old locale images, load new ones
        scheduleSave()
    }

    func cycleLocaleForward() { cycleLocale(forward: true) }
    func cycleLocaleBackward() { cycleLocale(forward: false) }

    private func cycleLocale(forward: Bool) {
        let locales = localeState.locales
        guard locales.count > 1 else { return }
        guard let idx = locales.firstIndex(where: { $0.code == localeState.activeLocaleCode }) else { return }
        let offset = forward ? 1 : locales.count - 1
        let target = locales[(idx + offset) % locales.count]
        setActiveLocale(target.code)
    }

    func moveLocale(from source: IndexSet, to destination: Int) {
        guard let fromIdx = source.first, fromIdx != 0, destination != 0 else { return }
        withUndo("Reorder Language") {
            localeState.locales.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Promote a language to base: bake its translations into every shape's base content,
    /// re-anchor all other locales (including the old base) as overrides, then move it first.
    func setBaseLocale(_ code: String) {
        guard localeState.hasLocale(code), code != localeState.baseLocaleCode else { return }
        withUndo("Set Base Language") {
            LocaleService.setBaseLocale(code, rows: &rows, state: &localeState)
        }
        loadScreenshotImages()
    }

    /// All text shapes across all rows with their base text and override for the requested locale.
    func textShapesForTranslation(localeCode: String? = nil) -> [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, isTranslated: Bool)] {
        var results: [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, isTranslated: Bool)] = []
        let code = localeCode ?? localeState.activeLocaleCode
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                let isTranslated = localeState.overrides[code]?[shape.textTranslationKey]?.hasTextContent == true
                results.append((shape: shape, rowId: row.id, rowLabel: row.label, isTranslated: isTranslated))
            }
        }
        return results
    }

    /// One entry per *unique* translatable string — text shapes that share a translation key
    /// collapse into a single entry. `rowLabel` aggregates the distinct rows that use the string.
    /// Drives the Edit Translations table, which lists unique terms; reuse is assigned on the canvas.
    func textShapesForTranslationMatrix() -> [(shape: CanvasShapeModel, rowLabel: String)] {
        var byKey: [String: (shape: CanvasShapeModel, rows: [String])] = [:]
        var order: [String] = []
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                let key = shape.textTranslationKey
                if byKey[key] == nil {
                    byKey[key] = (shape, [row.label])
                    order.append(key)
                } else if !byKey[key]!.rows.contains(row.label) {
                    byKey[key]?.rows.append(row.label)
                }
            }
        }
        return order.map { key in
            let entry = byKey[key]!
            return (shape: entry.shape, rowLabel: entry.rows.joined(separator: ", "))
        }
    }

    /// Translation progress for a locale (defaults to active locale).
    func translationProgress(for localeCode: String? = nil) -> (translated: Int, total: Int) {
        let code = localeCode ?? localeState.activeLocaleCode
        let textShapes = allTextShapes()
        let total = textShapes.count
        guard total > 0 else { return (0, 0) }

        if code == localeState.baseLocaleCode {
            return (total, total)
        }

        let translated = textShapes.reduce(into: 0) { count, shape in
            if localeState.overrides[code]?[shape.textTranslationKey]?.hasTextContent == true {
                count += 1
            }
        }
        return (translated, total)
    }

    func updateBaseText(shapeId: UUID, text: String) {
        guard let loc = shapeLocation(for: shapeId) else { return }
        let editedShape = rows[loc.rowIndex].shapes[loc.shapeIndex]
        let editedKey = editedShape.textTranslationKey
        // A shared (reused) string can span rows, so its base edit needs a whole-document undo.
        let isShared = editedShape.translationKey != nil

        // Capture undo state only at the start of a base text editing sequence
        if baseTextBaseRow == nil && baseTextBaseRows == nil {
            commitAllPendingEdits()
            if isShared { baseTextBaseRows = rows } else { baseTextBaseRow = rows[loc.rowIndex] }
        }

        if isShared {
            setSharedBaseText(key: editedKey, text: text)
        } else {
            rows[loc.rowIndex].shapes[loc.shapeIndex].text = text
        }
        scheduleSave()

        // Debounce undo registration so rapid keystrokes collapse into one entry
        baseTextUndoTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.finishBaseTextEditIfNeeded()
        }
        baseTextUndoTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    /// Commits a pending base-text editing burst as one undo step. No-op when none is captured.
    func finishBaseTextEditIfNeeded() {
        baseTextUndoTask?.cancel()
        baseTextUndoTask = nil
        if let baseRows = baseTextBaseRows {
            baseTextBaseRows = nil
            baseTextBaseRow = nil
            registerUndoWithBase("Edit Base Text", base: baseRows, baseLocaleState: localeState)
        } else if let baseRow = baseTextBaseRow {
            baseTextBaseRow = nil
            registerUndoForRowWithBase("Edit Base Text", baseRow: baseRow, baseLocaleState: localeState)
        }
    }

    func updateTranslationText(shapeId: UUID, text: String) {
        updateTranslationText(shapeId: shapeId, localeCode: localeState.activeLocaleCode, text: text)
    }

    func updateTranslationText(shapeId: UUID, localeCode code: String, text: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard localeState.hasLocale(code) else { return }
        guard let loc = shapeLocation(for: shapeId) else { return }
        let textKey = rows[loc.rowIndex].shapes[loc.shapeIndex].textTranslationKey

        // Capture undo state only at the start of a translation editing sequence
        if translationBaseLocaleState == nil {
            commitAllPendingEdits()
            translationBaseLocaleState = localeState
        }

        // Text is keyed by the (possibly shared) translation key, so editing one member of a reused
        // string updates them all. Per-shape style fields under the shape's own id are untouched.
        LocaleService.setTextOverride(&localeState, localeCode: code, key: textKey, text: text.isEmpty ? nil : text)
        scheduleSave()

        // Debounce undo registration so rapid keystrokes collapse into one entry
        translationUndoTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.finishTranslationEditIfNeeded()
        }
        translationUndoTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    /// Commits a pending translation editing burst as one undo step. No-op when none is captured.
    func finishTranslationEditIfNeeded() {
        translationUndoTask?.cancel()
        translationUndoTask = nil
        guard let savedBase = translationBaseLocaleState else { return }
        translationBaseLocaleState = nil
        registerUndoWithBase("Edit Translation", base: rows, baseLocaleState: savedBase)
    }

    func resetLocaleOverride(shapeId: UUID) {
        withUndo("Reset Override") {
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: nil)
        }
    }

    func resetTranslationText(shapeId: UUID) {
        resetTranslationText(shapeId: shapeId, localeCode: localeState.activeLocaleCode)
    }

    func resetTranslationText(shapeId: UUID, localeCode code: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard let loc = shapeLocation(for: shapeId) else { return }
        let textKey = rows[loc.rowIndex].shapes[loc.shapeIndex].textTranslationKey
        guard localeState.overrides[code]?[textKey]?.hasTranslatedTextField == true else { return }

        withUndo("Reset Translation") {
            // Clears plain + formatted text, so a rich-text-only translation reverts to base too.
            LocaleService.setTextOverride(&localeState, localeCode: code, key: textKey, text: nil)
        }
    }

    func resetLocaleImageOverride(shapeId: UUID) {
        let code = localeState.activeLocaleCode
        guard var override = localeState.override(forCode: code, shapeId: shapeId),
              let oldFile = override.overrideImageFileName else { return }
        withUndo("Reset Image Override") {
            override.overrideImageFileName = nil
            if override.isEmpty {
                LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: nil)
            } else {
                LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override)
            }
            cleanupUnreferencedImage(oldFile)
        }
    }

    func resetAllTranslations(shapeIds: Set<UUID>) {
        guard anyTranslationOrOverride(shapeIds: shapeIds) else { return }

        withUndo("Reset All Translations") {
            var removedImages: [String] = []
            for shapeId in shapeIds {
                for overrides in localeState.overrides.values {
                    if let image = overrides[shapeId.uuidString]?.overrideImageFileName { removedImages.append(image) }
                }
                LocaleService.removeShapeOverrides(&localeState, shapeId: shapeId)
                // A reused string lives under a shared key; clear it too (resets the whole group).
                if let sharedKey = textShape(for: shapeId)?.translationKey {
                    LocaleService.stripTextOverrides(&localeState, key: sharedKey)
                }
            }
            cleanupUnreferencedImages(removedImages)
        }
    }

    /// Whether a shape carries any override for the active locale — a per-shape style/geometry
    /// override (under its id) or a shared translation (under its translation key). Drives the
    /// per-shape "reset to base" affordance.
    func shapeHasActiveLocaleOverride(_ shapeId: UUID) -> Bool {
        guard !localeState.isBaseLocale else { return false }
        let code = localeState.activeLocaleCode
        if localeState.overrides[code]?[shapeId.uuidString]?.isEmpty == false { return true }
        if let key = textShape(for: shapeId)?.translationKey {
            return localeState.overrides[code]?[key]?.hasTextContent == true
        }
        return false
    }

    /// Whether any of these shapes has a non-empty override in any locale, accounting for reused
    /// strings whose translations live under a shared key.
    func anyTranslationOrOverride(shapeIds: Set<UUID>) -> Bool {
        if localeState.hasAnyOverride(shapeIds: shapeIds) { return true }
        return shapeIds.contains { id in
            guard let key = textShape(for: id)?.translationKey else { return false }
            return localeState.overrides.values.contains { $0[key]?.hasTextContent == true }
        }
    }

    /// Drop any override entry whose key is no longer a live shape id or a live text shape's
    /// translation key — e.g. after deleting every member of a reused string.
    func cleanupOrphanedTranslationOverrides() {
        var live = Set<String>()
        for row in rows {
            for shape in row.shapes {
                live.insert(shape.id.uuidString)
                if shape.type == .text { live.insert(shape.textTranslationKey) }
            }
        }
        for code in Array(localeState.overrides.keys) {
            guard let keys = localeState.overrides[code]?.keys else { continue }
            for key in Array(keys) where !live.contains(key) {
                localeState.overrides[code]?.removeValue(forKey: key)
            }
            if localeState.overrides[code]?.isEmpty == true {
                localeState.overrides.removeValue(forKey: code)
            }
        }
    }

    func resetActiveLocaleToBase() {
        let code = localeState.activeLocaleCode
        guard code != localeState.baseLocaleCode else { return }
        guard let localeOverrides = localeState.overrides[code], !localeOverrides.isEmpty else { return }

        withUndo("Reset Language to Base") {
            let overrideImages = localeOverrides.values.compactMap(\.overrideImageFileName)
            localeState.overrides.removeValue(forKey: code)
            cleanupUnreferencedImages(overrideImages)
        }
    }

    func addLocale(_ locale: LocaleDefinition) {
        guard !localeState.hasLocale(locale.code) else { return }
        withUndo("Add Language") {
            LocaleService.addLocale(&localeState, locale: locale)
            localeState.activeLocaleCode = locale.code
        }
    }

    func removeLocale(_ code: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard localeState.hasLocale(code) else { return }
        withUndo("Remove Language") {
            let overrideImages = localeState.overrides[code]?.values.compactMap(\.overrideImageFileName) ?? []
            LocaleService.removeLocale(&localeState, code: code)
            cleanupUnreferencedImages(overrideImages)
        }
    }

    // MARK: - Translation reuse (shared strings)

    private func textShape(for id: UUID) -> CanvasShapeModel? {
        guard let loc = shapeLocation(for: id) else { return nil }
        let shape = rows[loc.rowIndex].shapes[loc.shapeIndex]
        return shape.type == .text ? shape : nil
    }

    /// The override holding a text shape's translation for a locale, resolved through its (possibly
    /// shared) translation key. Use this for display/read — not `override(forCode:shapeId:)`, which
    /// would miss a reused string stored under another key.
    func translationOverrideForDisplay(shape: CanvasShapeModel, localeCode: String) -> ShapeLocaleOverride? {
        localeState.overrides[localeCode]?[shape.textTranslationKey]
    }

    /// Set `text` as the base text of every text shape sharing `key` — the members of a reused
    /// string. Owns the cross-row fan-out for both the table and inline canvas base edits.
    func setSharedBaseText(key: String, text: String) {
        for r in rows.indices {
            for s in rows[r].shapes.indices where rows[r].shapes[s].type == .text && rows[r].shapes[s].textTranslationKey == key {
                rows[r].shapes[s].text = text
            }
        }
    }

    /// Distinct other strings in the project a shape could reuse, keyed by translation key, with a
    /// representative base text and the row labels that use them.
    func reusableTranslationTargets(excludingShapeId id: UUID) -> [(key: String, baseText: String, rowLabels: [String])] {
        let excludeKey = textShape(for: id)?.textTranslationKey
        var byKey: [String: (baseText: String, rows: [String])] = [:]
        var order: [String] = []
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                let key = shape.textTranslationKey
                if key == excludeKey { continue }
                let base = (shape.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !base.isEmpty else { continue }
                if byKey[key] == nil { byKey[key] = (base, [row.label]); order.append(key) }
                else { byKey[key]?.rows.append(row.label) }
            }
        }
        return order.map { (key: $0, baseText: byKey[$0]!.baseText, rowLabels: byKey[$0]!.rows) }
    }

    /// Make `shapeId` reuse the string identified by `targetKey`: it adopts that string's base text
    /// and all its translations, and edits to either now affect both.
    func linkTranslation(shapeId: UUID, toTargetKey targetKey: String) {
        guard let myLoc = shapeLocation(for: shapeId) else { return }
        let shape = rows[myLoc.rowIndex].shapes[myLoc.shapeIndex]
        guard shape.type == .text, shape.textTranslationKey != targetKey else { return }
        let previousKey = shape.textTranslationKey

        // Resolve the target's base text up front; bail before mutating anything if it has none, so
        // a no-op link can't leave a half-converted shared key behind.
        guard let baseText = allTextShapes().first(where: { $0.textTranslationKey == targetKey })?.text,
              !baseText.isEmpty else { return }

        withUndo("Reuse Translation") {
            let sharedKey = ensureSharedKey(forTargetKey: targetKey)
            guard let loc = shapeLocation(for: shapeId) else { return }
            // This shape's own independent text (under its id) is no longer used.
            LocaleService.stripTextOverrides(&localeState, key: shapeId.uuidString)
            rows[loc.rowIndex].shapes[loc.shapeIndex].translationKey = sharedKey
            rows[loc.rowIndex].shapes[loc.shapeIndex].text = baseText
            cleanupSharedKeyIfOrphaned(previousKey)
        }
    }

    /// Stop reusing: the shape keeps its current base text and a private copy of the shared
    /// translations, and future edits no longer affect the other shapes.
    func unlinkTranslation(shapeId: UUID) {
        guard let loc = shapeLocation(for: shapeId) else { return }
        guard let sharedKey = rows[loc.rowIndex].shapes[loc.shapeIndex].translationKey else { return }

        withUndo("Stop Reusing Translation") {
            LocaleService.copyTextOverrides(&localeState, fromKey: sharedKey, toKey: shapeId.uuidString)
            rows[loc.rowIndex].shapes[loc.shapeIndex].translationKey = nil
            cleanupSharedKeyIfOrphaned(sharedKey)
        }
    }

    /// Resolve the shared key for a reuse target. If the target group is already shared (synthetic
    /// key), return it; otherwise mint a fresh key and migrate the previously-standalone target's
    /// text onto it so deleting any single member never destroys the string.
    private func ensureSharedKey(forTargetKey targetKey: String) -> String {
        if let member = allTextShapes().first(where: { $0.textTranslationKey == targetKey }),
           member.translationKey != nil {
            return targetKey // already a synthetic shared key
        }
        let sharedKey = UUID().uuidString
        LocaleService.moveTextOverrides(&localeState, fromKey: targetKey, toKey: sharedKey)
        for r in rows.indices {
            for s in rows[r].shapes.indices where rows[r].shapes[s].textTranslationKey == targetKey {
                rows[r].shapes[s].translationKey = sharedKey
            }
        }
        return sharedKey
    }

    /// Drop a synthetic shared-text entry once no shape references it anymore.
    private func cleanupSharedKeyIfOrphaned(_ key: String) {
        // Keep the entry while any live text shape still references the key (as its shared key or,
        // for an unlinked shape, its own id).
        let referenced = allTextShapes().contains { $0.textTranslationKey == key || $0.id.uuidString == key }
        if !referenced { LocaleService.stripTextOverrides(&localeState, key: key) }
    }
}

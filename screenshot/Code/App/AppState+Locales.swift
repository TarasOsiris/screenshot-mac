import SwiftUI

extension AppState {

    // MARK: - Locales

    func setActiveLocale(_ code: String) {
        guard code != localeState.activeLocaleCode else { return }
        guard localeState.hasLocale(code) else { return }
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
        registerUndo("Reorder Language")
        localeState.locales.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// All text shapes across all rows with their base text and override for the requested locale.
    func textShapesForTranslation(localeCode: String? = nil) -> [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, overrideText: String?)] {
        var results: [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, overrideText: String?)] = []
        let code = localeCode ?? localeState.activeLocaleCode
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                let overrideText = localeState.override(forCode: code, shapeId: shape.id)?.text
                results.append((shape: shape, rowId: row.id, rowLabel: row.label, overrideText: overrideText))
            }
        }
        return results
    }

    func textShapesForTranslationMatrix() -> [(shape: CanvasShapeModel, rowLabel: String)] {
        textShapesForTranslation().map { (shape: $0.shape, rowLabel: $0.rowLabel) }
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
            if let text = localeState.override(forCode: code, shapeId: shape.id)?.text,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                count += 1
            }
        }
        return (translated, total)
    }

    func updateBaseText(shapeId: UUID, text: String) {
        guard let loc = shapeLocation(for: shapeId) else { return }

        // Capture undo state only at the start of a base text editing sequence
        if baseTextBaseRow == nil {
            baseTextBaseRow = rows[loc.rowIndex]
        }

        rows[loc.rowIndex].shapes[loc.shapeIndex].text = text
        scheduleSave()

        // Debounce undo registration so rapid keystrokes collapse into one entry
        baseTextUndoTask?.cancel()
        guard let savedBaseRow = baseTextBaseRow else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerUndoForRowWithBase("Edit Base Text", baseRow: savedBaseRow, baseLocaleState: self.localeState)
            self.baseTextBaseRow = nil
        }
        baseTextUndoTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func updateTranslationText(shapeId: UUID, text: String) {
        updateTranslationText(shapeId: shapeId, localeCode: localeState.activeLocaleCode, text: text)
    }

    func updateTranslationText(shapeId: UUID, localeCode code: String, text: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard localeState.hasLocale(code) else { return }
        guard shapeLocation(for: shapeId) != nil else { return }

        // Capture undo state only at the start of a translation editing sequence
        if translationBaseLocaleState == nil {
            translationBaseLocaleState = localeState
        }

        let key = shapeId.uuidString
        var override = localeState.overrides[code]?[key] ?? ShapeLocaleOverride()
        override.text = text.isEmpty ? nil : text
        LocaleService.setShapeOverride(&localeState, localeCode: code, shapeId: shapeId, override: override.isEmpty ? nil : override)
        scheduleSave()

        // Debounce undo registration so rapid keystrokes collapse into one entry
        translationUndoTask?.cancel()
        guard let savedBase = translationBaseLocaleState else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerUndoWithBase("Edit Translation", base: self.rows, baseLocaleState: savedBase)
            self.translationBaseLocaleState = nil
        }
        translationUndoTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func resetLocaleOverride(shapeId: UUID) {
        registerUndo("Reset Override")
        LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: nil)
        scheduleSave()
    }

    func resetTranslationText(shapeId: UUID) {
        resetTranslationText(shapeId: shapeId, localeCode: localeState.activeLocaleCode)
    }

    func resetTranslationText(shapeId: UUID, localeCode code: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard var override = localeState.override(forCode: code, shapeId: shapeId) else { return }

        registerUndo("Reset Translation")
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil
        override.text = nil
        LocaleService.setShapeOverride(&localeState, localeCode: code, shapeId: shapeId, override: override.isEmpty ? nil : override)
        scheduleSave()
    }

    func resetLocaleImageOverride(shapeId: UUID) {
        let code = localeState.activeLocaleCode
        guard var override = localeState.override(forCode: code, shapeId: shapeId),
              let oldFile = override.overrideImageFileName else { return }
        registerUndo("Reset Image Override")
        override.overrideImageFileName = nil
        if override.isEmpty {
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: nil)
        } else {
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override)
        }
        cleanupUnreferencedImage(oldFile)
        scheduleSave()
    }

    func resetActiveLocaleToBase() {
        let code = localeState.activeLocaleCode
        guard code != localeState.baseLocaleCode else { return }
        guard let localeOverrides = localeState.overrides[code], !localeOverrides.isEmpty else { return }

        registerUndo("Reset Language to Base")
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil

        let overrideImages = localeOverrides.values.compactMap(\.overrideImageFileName)
        localeState.overrides.removeValue(forKey: code)
        cleanupUnreferencedImages(overrideImages)
        scheduleSave()
    }

    func addLocale(_ locale: LocaleDefinition) {
        guard !localeState.hasLocale(locale.code) else { return }
        registerUndo("Add Language")
        LocaleService.addLocale(&localeState, locale: locale)
        localeState.activeLocaleCode = locale.code
        scheduleSave()
    }

    func removeLocale(_ code: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard localeState.hasLocale(code) else { return }
        registerUndo("Remove Language")
        // Collect override image filenames before removing the locale
        let overrideImages = localeState.overrides[code]?.values.compactMap(\.overrideImageFileName) ?? []
        LocaleService.removeLocale(&localeState, code: code)
        cleanupUnreferencedImages(overrideImages)
        scheduleSave()
    }
}

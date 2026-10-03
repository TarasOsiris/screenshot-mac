import SwiftUI

/// Translation reuse: text shapes that share one string key, so a translation is written once.
extension AppState {
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

    /// Cheap existence check for `reusableTranslationTargets` — early-exits on the first match and
    /// allocates nothing, so it's safe to call from a view body to gate the reuse menu's presence.
    func hasReusableTranslationTargets(excludingShapeId id: UUID) -> Bool {
        let excludeKey = textShape(for: id)?.textTranslationKey
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                if shape.textTranslationKey == excludeKey { continue }
                if !(shape.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            }
        }
        return false
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
        return order.compactMap { key in
            guard let entry = byKey[key] else { return nil }
            return (key: key, baseText: entry.baseText, rowLabels: entry.rows)
        }
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

import SwiftUI

// A/B variants: rows tagged with `ScreenshotRow.variantId`; untagged rows are the Original (the control).
extension AppState {

    func variant(for row: ScreenshotRow) -> ScreenshotVariant? {
        variants.variant(withId: row.variantId)
    }

    /// What the UI, export and uploads see; `variants` itself is persisted regardless of the flag.
    var activeVariants: [ScreenshotVariant] { BetaFeatures.shared.isABTestingEnabled ? variants : [] }

    var effectiveVariantFilter: EditorVariantFilter {
        viewMode.variantFilter.resolved(in: activeVariants)
    }

    func setVariantFilter(_ filter: EditorVariantFilter) {
        viewMode.variantFilter = filter
        keepSelectionVisible()
    }

    /// Moves the selection off a row the filter hides, so the inspector never edits an invisible row.
    func keepSelectionVisible() {
        let filter = effectiveVariantFilter
        guard let id = selectedRowId, let idx = rowIndex(for: id), !filter.includes(rows[idx]) else { return }
        selectRow(nearestVisibleRow(from: idx)?.id)
    }

    /// The first row at or after `index` the filter shows, else the last one before it.
    func nearestVisibleRow(from index: Int) -> ScreenshotRow? {
        let filter = effectiveVariantFilter
        return rows[index...].first(where: filter.includes) ?? rows[..<index].last(where: filter.includes)
    }

    // MARK: - Screenshot slots

    /// A variant holds one App Store row per screenshot size; this is the one already in `row`'s slot.
    func rowOccupyingSlot(of row: ScreenshotRow, in variantId: UUID?) -> ScreenshotRow? {
        DocumentEditing.rowOccupyingSlot(of: row, in: variantId, rows: rows)
    }

    /// Per row: the variants whose slot for its size is taken, by which row's label; plus clashing variant rows.
    func variantSlotOccupancy() -> (occupants: [UUID: [UUID: String]], clashing: Set<UUID>) {
        var holders: [String: [ScreenshotRow]] = [:]
        var slots: [UUID: String] = [:]
        for row in rows where !row.excludeFromAppStoreConnect {
            let slot = DocumentEditing.screenshotSlot(of: row)
            slots[row.id] = slot
            if let variantId = row.variantId { holders["\(variantId)|\(slot)", default: []].append(row) }
        }
        let clashing = Set(holders.values.filter { $0.count > 1 }.joined().map(\.id))
        var occupants: [UUID: [UUID: String]] = [:]
        let variants = activeVariants
        for (rowId, slot) in slots {
            for variant in variants {
                if let holder = holders["\(variant.id)|\(slot)"]?.first(where: { $0.id != rowId }) {
                    occupants[rowId, default: [:]][variant.id] = holder.displayLabel
                }
            }
        }
        return (occupants, clashing)
    }

    // MARK: - Labels

    /// The row a variant copy takes its name from: its source, while that row exists and is named by
    /// hand. An automatic size label describes one row's size, so it is never shared.
    func labelSource(of row: ScreenshotRow) -> ScreenshotRow? {
        DocumentEditing.labelSource(of: row, in: rows)
    }

    /// Call inside an undo transaction, after renaming `rowId`.
    func propagateLabel(from rowId: UUID) {
        DocumentEditing.propagateLabel(from: rowId, in: &rows)
    }

    // MARK: - Verbs

    /// Starts a new variant seeded with a copy of `rowId`, inserted right after it.
    @discardableResult
    func createVariant(fromRow rowId: UUID, name: String? = nil) -> UUID? {
        guard let idx = rowIndex(for: rowId) else { return nil }
        return withUndo("Create Variant") {
            let created = DocumentEditing.createVariant(
                fromRowAt: idx, name: name, variants: &variants, rows: &rows,
                localeState: &localeState, resources: self
            )
            if let copy = created.copy { selectRow(copy.id) }
            return created.variantId
        }
    }

    /// Copies `rowId` into `variantId` (nil copies it into the Original), right after the source.
    func duplicateRow(_ rowId: UUID, into variantId: UUID?) {
        guard let idx = rowIndex(for: rowId) else { return }
        withUndo("Duplicate into Variant") {
            let copy = DocumentEditing.duplicateRow(
                at: idx, into: variantId, variants: variants, rows: &rows,
                localeState: &localeState, resources: self
            )
            if let copy { selectRow(copy.id) }
        }
    }

    func setRowVariant(_ rowId: UUID, to variantId: UUID?) {
        guard let idx = rowIndex(for: rowId), rows[idx].variantId != variantId,
              variantId == nil || variants.variant(withId: variantId) != nil,
              rowOccupyingSlot(of: rows[idx], in: variantId) == nil else { return }
        withRowUndo("Move to Variant", rowId: rowId) {
            DocumentEditing.setVariant(variantId, ofRowAt: idx, rows: &rows)
        }
        keepSelectionVisible()
    }

    /// Unique ignoring case and never "Original": export folders and experiment treatments match by name.
    func renameVariant(_ id: UUID, to name: String) {
        guard let idx = variants.firstIndex(where: { $0.id == id }),
              let unique = DocumentEditing.variantName(name, among: variants, excluding: id),
              variants[idx].name != unique else { return }
        withUndo("Rename Variant") {
            variants[idx].name = unique
        }
    }

    /// Removes the variant and its rows; if that would empty the project, its rows move to the Original.
    func deleteVariant(_ id: UUID) {
        guard variants.contains(where: { $0.id == id }) else { return }
        withUndo("Delete Variant") {
            let deleted = DocumentEditing.deleteVariant(id, variants: &variants, rows: &rows, localeState: &localeState)
            for rowId in deleted.deletedRowIds { viewMode.exitPreview(for: rowId) }
            normalizeSelection()
            keepSelectionVisible()
            cleanupUnreferencedImages(deleted.imageCandidates)
        }
    }
}

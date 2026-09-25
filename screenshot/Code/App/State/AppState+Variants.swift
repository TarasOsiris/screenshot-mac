import SwiftUI

// A/B variants: rows tagged with `ScreenshotRow.variantId`; untagged rows are the Original (the control).
extension AppState {

    func variant(for row: ScreenshotRow) -> ScreenshotVariant? {
        variants.variant(withId: row.variantId)
    }

    /// What the UI, export and uploads see; `variants` itself is persisted regardless of the flag.
    var activeVariants: [ScreenshotVariant] { variants.active }

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
        let nearest = rows[idx...].first(where: filter.includes) ?? rows[..<idx].last(where: filter.includes)
        selectRow(nearest?.id)
    }

    // MARK: - Screenshot slots

    /// A variant holds one App Store row per screenshot size; this is the one already in `row`'s slot.
    func rowOccupyingSlot(of row: ScreenshotRow, in variantId: UUID?) -> ScreenshotRow? {
        guard let variantId, !row.excludeFromAppStoreConnect else { return nil }
        let slot = Self.screenshotSlot(of: row)
        return rows.first {
            $0.id != row.id && $0.uploadsToAppStore(from: variantId) && Self.screenshotSlot(of: $0) == slot
        }
    }

    /// Per row: the variants whose slot for its size is taken, by which row's label; plus clashing variant rows.
    func variantSlotOccupancy() -> (occupants: [UUID: [UUID: String]], clashing: Set<UUID>) {
        var holders: [String: [ScreenshotRow]] = [:]
        var slots: [UUID: String] = [:]
        for row in rows where !row.excludeFromAppStoreConnect {
            let slot = Self.screenshotSlot(of: row)
            slots[row.id] = slot
            if let variantId = row.variantId { holders["\(variantId)|\(slot)", default: []].append(row) }
        }
        let clashing = Set(holders.values.filter { $0.count > 1 }.joined().map(\.id))
        var occupants: [UUID: [UUID: String]] = [:]
        for (rowId, slot) in slots {
            for variant in activeVariants {
                if let holder = holders["\(variant.id)|\(slot)"]?.first(where: { $0.id != rowId }) {
                    occupants[rowId, default: [:]][variant.id] = holder.displayLabel
                }
            }
        }
        return (occupants, clashing)
    }

    private static func screenshotSlot(of row: ScreenshotRow) -> String {
        ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)?.appStoreConnectValue
            ?? "\(Int(row.templateWidth))x\(Int(row.templateHeight))"
    }

    // MARK: - Labels

    /// The row a variant copy takes its name from: its source, while that row exists and is named by
    /// hand. An automatic size label describes one row's size, so it is never shared.
    func labelSource(of row: ScreenshotRow) -> ScreenshotRow? {
        guard FeatureFlags.abTesting, row.variantId != nil, let originId = row.originRowId, originId != row.id,
              let idx = rowIndex(for: originId), rows[idx].isLabelManuallySet else { return nil }
        return rows[idx]
    }

    /// Call inside an undo transaction, after renaming `rowId`.
    func propagateLabel(from rowId: UUID) {
        guard FeatureFlags.abTesting, let idx = rowIndex(for: rowId) else { return }
        let source = rows[idx]
        for i in rows.indices where rows[i].originRowId == rowId && rows[i].variantId != nil {
            if source.isLabelManuallySet {
                rows[i].label = source.label
            } else {
                rows[i].label = presetLabel(forWidth: rows[i].templateWidth, height: rows[i].templateHeight)
            }
            rows[i].isLabelManuallySet = source.isLabelManuallySet
        }
    }

    // MARK: - Verbs

    /// Starts a new variant seeded with a copy of `rowId`, inserted right after it.
    @discardableResult
    func createVariant(fromRow rowId: UUID, name: String? = nil) -> UUID? {
        guard rowIndex(for: rowId) != nil else { return nil }
        return withUndo("Create Variant") {
            let variant = ScreenshotVariant(
                name: variants.uniqueName(variants.nextDefaultName()),
                colorIndex: variants.nextColorIndex(among: ScreenshotVariant.colorSlots)
            )
            variants.append(variant)
            if let name { renameVariant(variant.id, to: name) }
            duplicateRow(rowId, into: variant.id)
            return variant.id
        }
    }

    /// Copies `rowId` into `variantId` (nil copies it into the Original), right after the source.
    func duplicateRow(_ rowId: UUID, into variantId: UUID?) {
        guard let idx = rowIndex(for: rowId),
              variantId == nil || variants.variant(withId: variantId) != nil,
              rowOccupyingSlot(of: rows[idx], in: variantId) == nil else { return }
        withUndo("Duplicate into Variant") {
            let source = rows[idx]
            insertDuplicate(
                of: source,
                at: idx + 1,
                label: source.label,
                isLabelManuallySet: source.isLabelManuallySet,
                variantId: variantId,
                // A copy of a copy follows the same row, so a rename reaches the whole family.
                originRowId: variantId == nil ? nil : (source.originRowId.flatMap { rowIndex(for: $0) != nil ? $0 : nil } ?? source.id)
            )
        }
    }

    func setRowVariant(_ rowId: UUID, to variantId: UUID?) {
        guard let idx = rowIndex(for: rowId), rows[idx].variantId != variantId,
              variantId == nil || variants.variant(withId: variantId) != nil,
              rowOccupyingSlot(of: rows[idx], in: variantId) == nil else { return }
        withRowUndo("Move to Variant", rowId: rowId) {
            rows[idx].variantId = variantId
            if variantId == nil { rows[idx].originRowId = nil }
        }
        keepSelectionVisible()
    }

    /// Unique ignoring case and never "Original": export folders and experiment treatments match by name.
    func renameVariant(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ScreenshotVariant.maxNameLength))
        guard !trimmed.isEmpty, let idx = variants.firstIndex(where: { $0.id == id }) else { return }
        let unique = variants.uniqueName(trimmed, excluding: id)
        guard variants[idx].name != unique else { return }
        withUndo("Rename Variant") {
            variants[idx].name = unique
        }
    }

    /// Removes the variant and its rows; if that would empty the project, its rows move to the Original.
    func deleteVariant(_ id: UUID) {
        guard variants.contains(where: { $0.id == id }) else { return }
        withUndo("Delete Variant") {
            let variantRowIds = Set(rows.inVariant(id).map(\.id))
            // Removed first, so a filter on this variant has already widened when the selection moves.
            variants.removeAll { $0.id == id }
            if variantRowIds.count < rows.count {
                deleteRows(variantRowIds)
            } else {
                for i in rows.indices {
                    rows[i].variantId = nil
                    rows[i].originRowId = nil
                }
            }
        }
    }
}

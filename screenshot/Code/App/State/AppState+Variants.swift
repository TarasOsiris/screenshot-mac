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

    /// Starts a new variant seeded with a copy of `rowId`, inserted right after it.
    @discardableResult
    func createVariant(fromRow rowId: UUID, name: String? = nil) -> UUID? {
        guard rowIndex(for: rowId) != nil else { return nil }
        return withUndo("Create Variant") {
            let variant = ScreenshotVariant(name: variants.nextDefaultName())
            variants.append(variant)
            if let name { renameVariant(variant.id, to: name) }
            duplicateRow(rowId, into: variant.id)
            return variant.id
        }
    }

    /// Copies `rowId` into `variantId` (nil copies it into the Original), right after the source.
    func duplicateRow(_ rowId: UUID, into variantId: UUID?) {
        guard let idx = rowIndex(for: rowId),
              variantId == nil || variants.variant(withId: variantId) != nil else { return }
        withUndo("Duplicate into Variant") {
            let source = rows[idx]
            insertDuplicate(
                of: source,
                at: idx + 1,
                label: source.label,
                isLabelManuallySet: source.isLabelManuallySet,
                variantId: variantId
            )
        }
    }

    func setRowVariant(_ rowId: UUID, to variantId: UUID?) {
        guard let idx = rowIndex(for: rowId), rows[idx].variantId != variantId,
              variantId == nil || variants.variant(withId: variantId) != nil else { return }
        withRowUndo("Move to Variant", rowId: rowId) {
            rows[idx].variantId = variantId
        }
    }

    func renameVariant(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ScreenshotVariant.maxNameLength))
        guard !trimmed.isEmpty,
              let idx = variants.firstIndex(where: { $0.id == id }),
              variants[idx].name != trimmed else { return }
        withUndo("Rename Variant") {
            variants[idx].name = trimmed
        }
    }

    /// Removes the variant and its rows; if that would empty the project, its rows move to the Original.
    func deleteVariant(_ id: UUID) {
        guard variants.contains(where: { $0.id == id }) else { return }
        withUndo("Delete Variant") {
            let variantRowIds = Set(rows.inVariant(id).map(\.id))
            if variantRowIds.count < rows.count {
                deleteRows(variantRowIds)
            } else {
                for i in rows.indices { rows[i].variantId = nil }
            }
            variants.removeAll { $0.id == id }
        }
    }
}

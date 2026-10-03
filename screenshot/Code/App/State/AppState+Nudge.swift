import SwiftUI
import UniformTypeIdentifiers

extension AppState {
    func nudgeSelectedShapes(dx: CGFloat, dy: CGFloat) {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        if let cropId = imageCrop.shapeId {
            nudgeImageCrop(cropId, rowIdx: rowIdx, dx: dx, dy: dy)
            return
        }

        let ids = selectedShapeIds
        let hasMovable = rows[rowIdx].shapes.contains { ids.contains($0.id) && !$0.resolvedIsLocked }
        guard hasMovable else { return }

        // Only once something will actually move, so a fully-locked nudge doesn't poison the
        // baseline for a later, unrelated nudge.
        beginNudgeIfNeeded(rowIdx: rowIdx, target: rows[rowIdx].id)
        edits.nudgeActionName = ids.count > 1 ? "Move Shapes" : "Move Shape"

        for i in rows[rowIdx].shapes.indices {
            if ids.contains(rows[rowIdx].shapes[i].id) && !rows[rowIdx].shapes[i].resolvedIsLocked {
                rows[rowIdx].shapes[i].x += dx
                rows[rowIdx].shapes[i].y += dy
            }
        }
        scheduleSave()
        edits.nudge.arm()
    }

    /// In crop mode the arrows pan the picture inside the frame, in canvas directions.
    private func nudgeImageCrop(_ shapeId: UUID, rowIdx: Int, dx: CGFloat, dy: CGFloat) {
        guard let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shapeId }) else { return }
        let shape = rows[rowIdx].shapes[shapeIdx]
        // The frame a locale sees can differ from the base one; clamp against what's on screen,
        // as the drag does.
        let resolved = LocaleService.resolveShape(shape, localeState: localeState)
        guard !resolved.resolvedIsLocked, resolved.width > 0, resolved.height > 0,
              let imageSize = displayImageSize(of: resolved) else { return }

        let frameSize = resolved.frameRect.size
        let local = ResizeGeometry.localTranslation(CGSize(width: dx, height: dy), rotation: resolved.rotation)
        var updated = resolved
        updated.imageCrop = (resolved.imageCrop ?? ImageCrop())
            .panned(by: local, frameSize: frameSize, imageSize: imageSize)
            .clamped(imageSize: imageSize, frameSize: frameSize)
            .storedValue
        guard updated.imageCrop != resolved.imageCrop else { return }

        beginNudgeIfNeeded(rowIdx: rowIdx, target: shapeId)
        edits.nudgeActionName = "Crop Image"
        if localeState.isBaseLocale {
            // Skips `localeState`'s mutation notice, which would re-render every row per key repeat.
            rows[rowIdx].shapes[shapeIdx].imageCrop = updated.imageCrop
        } else {
            rows[rowIdx].shapes[shapeIdx] = LocaleService.splitUpdate(base: shape, updated: updated, localeState: &localeState)
        }
        scheduleSave()
        edits.nudge.arm()
    }

    /// Captures the undo base at the start of a nudge burst; the burst commits as one step.
    /// `target` is the row for a move and the shape for a crop pan, so switching between the two
    /// — however crop mode was entered or left — splits the burst into separate undo steps.
    private func beginNudgeIfNeeded(rowIdx: Int, target: UUID) {
        if edits.nudge.isActive, edits.nudge.activeId != target { edits.nudge.finish() }
        guard !edits.nudge.isActive else { return }
        commitAllPendingEdits()
        let baseRow = rows[rowIdx]
        // A crop pan in a non-base locale writes its override, so the base locale state is part of the step.
        let baseLocaleState = localeState
        edits.nudge.begin(id: target) { [weak self] in
            guard let self else { return }
            self.registerUndoForRowWithBase(self.edits.nudgeActionName, baseRow: baseRow, baseLocaleState: baseLocaleState)
        }
    }

    /// Commits a pending arrow-key nudge as one undo step. No-op when no nudge is captured.
    func finishNudgeIfNeeded() {
        edits.nudge.finish()
    }
}

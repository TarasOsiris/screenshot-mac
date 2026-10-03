import SwiftUI
import UniformTypeIdentifiers

extension AppState {
    func copySelectedShapes() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        clipboard.copy(rows[rowIdx].shapes.filter { ids.contains($0.id) })
    }

    #if os(macOS)
    /// Reading pasteboard data blocks on the app that copied it (SCREENSHOT-BRO-1Z), so it happens off-main.
    private func pasteSystemPasteboardImage(intoRow rowId: UUID) {
        let changeCount = NSPasteboard.general.changeCount
        let projectId = activeProjectId
        let pointer = canvasHints.mouseModelPosition
        Task {
            guard let image = await Self.readPasteboardImage(),
                  NSPasteboard.general.changeCount == changeCount,
                  activeProjectId == projectId,
                  let rowIdx = selectedRowIndex, rows[rowIdx].id == rowId else { return }
            let row = rows[rowIdx]
            let center = pointer ?? CGPoint(x: row.templateWidth / 2, y: row.templateHeight / 2)
            addImageShape(image: image, centerX: center.x, centerY: center.y, source: .paste)
        }
    }

    @concurrent private nonisolated static func readPasteboardImage() async -> NSImage? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) else { return nil }
        // NSImage reads file URLs too; don't pull a copied video or archive into memory to find out it isn't one.
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if let fileURL = fileURLs.first,
           UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .image) != true {
            return nil
        }
        guard let image = NSImage(pasteboard: pasteboard), image.isValid else { return nil }
        return image
    }
    #endif

    func pasteShapes() {
        guard let rowIdx = selectedRowIndex else { return }

        #if os(macOS)
        // A newer outside copy wins even when it isn't an image — the shapes copied before it are stale.
        if clipboard.systemPasteboardIsNewer {
            pasteSystemPasteboardImage(intoRow: rows[rowIdx].id)
            return
        }
        #endif

        // Otherwise paste from internal shape clipboard
        let copied = clipboard.shapes
        guard !copied.isEmpty else { return }
        withRowUndo(copied.count == 1 ? "Paste Shape" : "Paste Shapes", rowId: rows[rowIdx].id) {
            var newIds: Set<UUID> = []
            let groupMinX = copied.map(\.x).min() ?? 0
            let groupMinY = copied.map(\.y).min() ?? 0
            let groupMaxX = copied.map { $0.x + $0.width }.max() ?? 0
            let groupMaxY = copied.map { $0.y + $0.height }.max() ?? 0
            let groupCenterX = (groupMinX + groupMaxX) / 2
            let groupCenterY = (groupMinY + groupMaxY) / 2

            for source in copied {
                var pasted: CanvasShapeModel
                if let mousePos = canvasHints.mouseModelPosition, copied.count == 1 {
                    pasted = source.duplicated()
                    pasted.x = mousePos.x - pasted.width / 2
                    pasted.y = mousePos.y - pasted.height / 2
                } else if let mousePos = canvasHints.mouseModelPosition {
                    pasted = source.duplicated()
                    pasted.x = mousePos.x + (source.x - groupCenterX)
                    pasted.y = mousePos.y + (source.y - groupCenterY)
                } else {
                    pasted = source.duplicated(offsetX: 20, offsetY: 20)
                }
                LocaleService.copyShapeOverrides(&localeState, fromId: source.id, toId: pasted.id)
                copyImageFiles(for: &pasted, originalId: source.id)
                rows[rowIdx].shapes.append(pasted)
                newIds.insert(pasted.id)
            }
            selectedShapeIds = newIds
        }
    }
}

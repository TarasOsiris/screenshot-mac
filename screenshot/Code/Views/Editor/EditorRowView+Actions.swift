#if os(macOS)
import AppKit
#endif
import SwiftUI

extension EditorRowView {
    func tapSelectRow() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
        state.selectRow(row.id)
    }

    /// Only the first row's canvas reports to the deferred-tour logic, since the
    /// `.canvas` coach mark anchors here.
    func startDeferredCoachIfNeeded() {
        guard isFirst, !isPreviewMode else { return }
        #if os(iOS)
        state.coach.startDeferredIfEligible(isCompactWidth: horizontalSizeClass != .regular)
        #else
        state.coach.startDeferredIfEligible(isCompactWidth: false)
        #endif
    }

    func startLabelEdit() {
        editingLabelText = row.label
        isEditingLabel = true
        isLabelFieldFocused = true
    }

    func commitLabelEdit() {
        guard isEditingLabel else { return }
        isEditingLabel = false
        state.updateRowLabel(row.id, text: editingLabelText)
    }

    func cancelLabelEdit() {
        isEditingLabel = false
    }

    func createImageShape(image: NSImage, modelX: CGFloat, modelY: CGFloat) {
        state.selectRow(row.id)
        state.addImageShape(image: image, centerX: modelX, centerY: modelY)
    }

    // MARK: - Add Element helpers

    func addShapeFromMenu(_ type: ShapeType) {
        let center = contextMenuPointStore.value ?? state.shapeCenter(for: row)
        state.selectRow(row.id)
        guard let shape = CanvasShapeModel.defaultShape(for: type, row: row, centerX: center.x, centerY: center.y) else { return }
        state.addShape(shape)
    }

    // MARK: - Shared row menu

    @ViewBuilder
    var rowMenuContent: some View {
        EditorRowMenuContent(
            state: state,
            row: row,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            canDelete: canDelete,
            confirmBeforeDeleting: confirmBeforeDeleting,
            isSvgDialogPresented: $isSvgDialogPresented,
            isResettingRow: $isResettingRow,
            isDeletingRow: $isDeletingRow,
            addShapeFromMenu: addShapeFromMenu,
            exportRowScreenshots: exportRowScreenshots,
            exportRowImage: { exportRowImage(showcase: $0) }
        )
    }

    func exportRowScreenshots() {
        // macOS picks a destination folder; iPad stages a temp folder and shares it (no Finder).
        #if os(iOS)
        let folder: URL
        do {
            folder = try ExportService.makeTempExportFolder()
        } catch {
            exportError = error.localizedDescription
            return
        }
        #else
        guard let folder = ExportFolderService.chooseFolder() else { return }
        let didAccess = folder.startAccessingSecurityScopedResource()
        #endif

        Task { @MainActor in
            #if os(macOS)
            defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
            #endif

            do {
                var cache: [String: NSImage] = [:]
                let context = RowRenderContext.load(
                    row: row,
                    localeCode: state.localeState.activeLocaleCode,
                    from: state,
                    label: "row export",
                    cache: &cache
                )

                try await withThrowingTaskGroup(of: Void.self) { group in
                    try await context.forEachTemplate { index, image in
                        let padded = String(format: "%02d", index + 1)
                        let fileURL = folder.appendingPathComponent("\(padded)_screenshot.png")
                        group.addTask {
                            guard let data = ExportService.encodeImage(image, format: .png) else {
                                throw ExportError.renderFailed
                            }
                            try data.write(to: fileURL)
                        }
                    }
                    try await group.waitForAll()
                }
                #if os(iOS)
                PlatformShare.present(urls: [folder]) { _ in
                    try? FileManager.default.removeItem(at: folder)
                }
                #else
                NSWorkspace.shared.activateFileViewerSelecting([folder])
                #endif
            } catch {
                exportError = String(localized: "Could not export row screenshots: \(error.localizedDescription)")
            }
        }
    }

    func exportRowImage(showcase: Bool) {
        if showcase {
            requestShowcaseExport(row)
            return
        }
        let localeCode = state.localeState.activeLocaleCode
        Task {
            if let message = await ExportService.saveRowImageViaPanel(defaultName: row.label, render: {
                let images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
                return RowRenderer.renderRowImage(
                    row: row, screenshotImages: images,
                    localeCode: localeCode, localeState: state.localeState,
                    availableFontFamilies: state.availableFontFamilySet
                )
            }) {
                exportError = String(localized: "Could not export row image: \(message)")
            }
        }
    }
}

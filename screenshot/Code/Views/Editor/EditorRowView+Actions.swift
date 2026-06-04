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

    /// Starts an onboarding tour deferred from when the welcome sheet closed (no project was
    /// open then). Only the first row's canvas drives this, since the `.canvas` coach mark
    /// anchors here. Yields a runloop turn so the anchor is laid out before the popover shows.
    func startDeferredCoachIfNeeded() {
        guard state.rows.first?.id == row.id, !isPreviewMode else { return }
        guard let persist = state.pendingCoachPersistOnEnd, !state.isOpeningProject else { return }
        state.pendingCoachPersistOnEnd = nil
        Task { @MainActor in
            await Task.yield()
            state.startCoach(persistOnEnd: persist)
        }
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

    static let placeholderTemplate = ScreenshotTemplate()

    func safeTemplateBinding(rowId: UUID, templateIndex: Int) -> Binding<ScreenshotTemplate> {
        Binding(
            get: {
                guard let ri = state.rows.firstIndex(where: { $0.id == rowId }),
                      templateIndex < state.rows[ri].templates.count else {
                    return Self.placeholderTemplate
                }
                return state.rows[ri].templates[templateIndex]
            },
            set: { newValue in
                guard let ri = state.rows.firstIndex(where: { $0.id == rowId }),
                      templateIndex < state.rows[ri].templates.count else { return }
                state.registerUndoForRow(at: ri, "Edit Template")
                state.rows[ri].templates[templateIndex] = newValue
                state.scheduleSave()
            }
        )
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
                let localeCode = state.localeState.activeLocaleCode
                let images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
                let rowBackground = ExportService.precomposedRowBackgroundIfNeeded(
                    row: row,
                    screenshotImages: images,
                    displayScale: 1.0,
                    labelPrefix: "row export"
                )

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in row.templates.indices {
                        let image = ExportService.renderSingleTemplateImage(
                            index: index, row: row, screenshotImages: images,
                            localeCode: localeCode, localeState: state.localeState,
                            preRenderedRowBackground: rowBackground
                        )
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
        if let message = ExportService.saveRowImageViaPanel(defaultName: row.label, render: {
            let images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
            return ExportService.renderRowImage(
                row: row, screenshotImages: images,
                localeCode: localeCode, localeState: state.localeState
            )
        }) {
            exportError = String(localized: "Could not export row image: \(message)")
        }
    }
}

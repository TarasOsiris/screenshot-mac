#if os(macOS)
import AppKit
#endif
import SwiftUI

extension EditorRowView {
    func tapSelectRow() {
        resignFieldEditor()
        state.selectRow(row.id)
    }

    /// Hands focus back from any SwiftUI `TextField`'s field editor so canvas key commands
    /// (Delete, arrow-key nudge) reach the canvas. Called by the empty-canvas click and by the
    /// marquee; clicking a shape does not currently reset the responder.
    func resignFieldEditor() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
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

    // MARK: - Row mutations

    /// Shared by the row header and the row context menu.
    static let rowAnimation: Animation = .easeInOut(duration: 0.2)

    func toggleCollapsed() {
        withAnimation(Self.rowAnimation) { state.toggleRowCollapsed(for: row.id) }
    }

    func moveRowUp() {
        withAnimation(Self.rowAnimation) { state.moveRowUp(row.id) }
    }

    func moveRowDown() {
        withAnimation(Self.rowAnimation) { state.moveRowDown(row.id) }
    }

    func duplicateRow() {
        store.requirePro(
            allowed: store.canAddRow(currentCount: state.rows.count),
            context: .rowLimit
        ) {
            withAnimation(Self.rowAnimation) { state.duplicateRow(row.id) }
        }
    }

    func resetRow() {
        if confirmBeforeDeleting {
            activeAlert = .resetRow
        } else {
            withAnimation(Self.rowAnimation) { state.resetRow(row.id) }
        }
    }

    func deleteRow() {
        if confirmBeforeDeleting {
            activeAlert = .deleteRow
        } else {
            withAnimation(Self.rowAnimation) { state.deleteRow(row.id) }
        }
    }

    func togglePreviewMode() {
        modeReady = false
        let wasPreview = isPreviewMode
        state.viewMode.togglePreview(for: row.id)
        if !wasPreview {
            textEditingShapeId = nil
            dragSession.reset()
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
            isSvgDialogPresented: $isSvgDialogPresented,
            addShapeFromMenu: addShapeFromMenu,
            exportRowScreenshots: exportRowScreenshots,
            exportRowImage: { exportRowImage(showcase: $0) },
            duplicateRow: duplicateRow,
            moveRowUp: moveRowUp,
            moveRowDown: moveRowDown,
            resetRow: resetRow,
            deleteRow: deleteRow
        )
    }

    func exportRowScreenshots() {
        // macOS picks a destination folder; iPad stages a temp folder and shares it (no Finder).
        #if os(iOS)
        let folder: URL
        do {
            folder = try ExportService.makeTempExportFolder()
        } catch {
            activeAlert = .exportFailed(error.localizedDescription)
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
                activeAlert = .exportFailed(String(localized: "Could not export row screenshots: \(error.localizedDescription)"))
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
                activeAlert = .exportFailed(String(localized: "Could not export row image: \(message)"))
            }
        }
    }
}

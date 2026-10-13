import ImageIO
import SwiftUI
import UniformTypeIdentifiers


extension AppState {

    // MARK: - Screenshot Images

    /// `source` is required, not defaulted: a default is exactly how this event came to miss nine
    /// of eleven import paths — a new one would compile clean and report a lie.
    func saveImage(_ image: NSImage, for shapeId: UUID, source: ImageImportOrigin) {
        guard let activeId = activeProjectId,
              let location = shapeLocation(for: shapeId) else { return }
        let shape = rows[location.rowIndex].shapes[location.shapeIndex]
        guard !shape.resolvedIsLocked else { return }
        let saved = withUndo("Assign Screenshot") {
            performSaveImage(image, for: shapeId, activeId: activeId, location: location)
        }
        guard saved else { return }
        captureImport(count: 1, source: source, device: shape.deviceCategory)
    }

    /// Clears the screenshot image from every (unlocked) device shape in the row, including locale overrides.
    func clearAllDeviceImages(in rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        let deviceIndices = rows[idx].shapes.indices.filter {
            rows[idx].shapes[$0].type == .device && !rows[idx].shapes[$0].resolvedIsLocked
        }
        guard !deviceIndices.isEmpty else { return }

        let hasImagesToClear = deviceIndices.contains { shapeIndex in
            let shape = rows[idx].shapes[shapeIndex]
            return shape.displayImageFileName != nil
                || !localeOverrideImageFileNames(for: shape.id).isEmpty
        }
        guard hasImagesToClear else { return }

        withUndo("Reset All Images") {
            // Snapshot locale codes — setShapeOverride can remove codes via cleanupEmptyOverrides.
            let localeCodes = Array(localeState.overrides.keys)
            var orphanCandidates: [String?] = []

            for shapeIndex in deviceIndices {
                let shapeId = rows[idx].shapes[shapeIndex].id

                for localeCode in localeCodes {
                    guard var override = localeState.override(forCode: localeCode, shapeId: shapeId),
                          let oldFile = override.overrideImageFileName else { continue }
                    orphanCandidates.append(oldFile)
                    override.overrideImageFileName = nil
                    LocaleService.setShapeOverride(
                        &localeState,
                        localeCode: localeCode,
                        shapeId: shapeId,
                        override: override.isEmpty ? nil : override
                    )
                }

                if let baseFile = rows[idx].shapes[shapeIndex].displayImageFileName {
                    orphanCandidates.append(baseFile)
                    rows[idx].shapes[shapeIndex].displayImageFileName = nil
                }
            }

            cleanupUnreferencedImages(orphanCandidates)
        }
    }

    /// Loads the full-resolution image referenced by `shapeId`, runs Vision's foreground
    /// subject mask off the main actor, and replaces the shape's image with the cropped
    /// transparent-background result. The shape's width is adjusted to match the new
    /// (tighter) aspect ratio in the same undo step.
    @MainActor
    func removeImageBackground(for shapeId: UUID, onError: @escaping @MainActor (String) -> Void) {
        guard let location = shapeLocation(for: shapeId) else { return }
        let shape = rows[location.rowIndex].shapes[location.shapeIndex]
        guard !shape.resolvedIsLocked else { return }
        guard let fileName = shape.displayImageFileName,
              let activeId = activeProjectId else { return }
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        Task { @MainActor [weak self] in
            do {
                let result = try await Self.backgroundRemovedImage(at: url)
                guard let self, let location = self.shapeLocation(for: shapeId) else { return }
                self.withUndo("Remove Background") {
                    if self.performSaveImage(result, for: shapeId, activeId: activeId, location: location),
                       self.rows[location.rowIndex].shapes[location.shapeIndex].flexesToImageAspect {
                        self.rows[location.rowIndex].shapes[location.shapeIndex].adaptToImageAspectRatio(result.size)
                    }
                }
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    // swiftlint:disable:next inherited_executor_async - the body is a Task.detached, which offloads.
    private nonisolated static func backgroundRemovedImage(at url: URL) async throws -> NSImage {
        try await Task.detached(priority: .userInitiated) {
            try BackgroundRemovalService.removeBackground(at: url)
        }.value
    }

    func clearImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        guard !rows[location.rowIndex].shapes[location.shapeIndex].resolvedIsLocked else { return }

        withUndo("Clear Screenshot") {
            // On a non-base locale with no per-locale image, the shape shows the inherited base
            // image — fall through and clear that, so Reset matches what the user sees.
            if !localeState.isBaseLocale,
               var override = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId),
               let oldFile = override.overrideImageFileName {
                override.overrideImageFileName = nil
                LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override.isEmpty ? nil : override)
                cleanupUnreferencedImage(oldFile)
            } else {
                guard let oldFile = rows[location.rowIndex].shapes[location.shapeIndex].displayImageFileName else { return }
                rows[location.rowIndex].shapes[location.shapeIndex].displayImageFileName = nil
                cleanupUnreferencedImage(oldFile)
            }
        }
    }

    /// Saves image file and updates state without registering undo or scheduling save.
    /// Used by compound operations that manage their own undo (addImageShape, batchImportImages).
    @discardableResult
    /// Deliberately emits no analytics: `removeImageBackground` re-saves an already-imported
    /// image through here. Every *public* verb above must emit `screenshots_imported` itself
    /// (via `captureImport`) or deliberately not.
    private func performSaveImage(_ image: NSImage, for shapeId: UUID,
                                  activeId: UUID? = nil, location: (rowIndex: Int, shapeIndex: Int)? = nil) -> Bool {
        guard let activeId = activeId ?? activeProjectId else { return false }
        guard let location = location ?? shapeLocation(for: shapeId) else { return false }

        // Every caller of this synchronous path is an editor action, so it writes wherever the
        // locale switcher is pointing — same as before the locale became explicit.
        let localeCode = resolveImportLocale(.active)
        let fileName = DocumentEditing.screenshotImageFileName(for: shapeId, localeCode: localeCode)
        guard let thumbnail = persistImageResource(
            image,
            named: fileName,
            activeId: activeId,
            action: .saveScreenshot
        ) else {
            return false
        }
        screenshotImages[fileName] = thumbnail
        cleanupUnreferencedImage(DocumentEditing.pointShape(
            &rows[location.rowIndex].shapes[location.shapeIndex], at: fileName,
            imageSize: image.size, localeCode: localeCode, localeState: &localeState
        ))
        return true
    }

    /// The locale a write should land in, given what the caller asked for. `nil` means the base
    /// image. `.active` collapses to `nil` when the switcher is on the base locale, which is what
    /// makes the editor's own imports keep writing base images.
    private func resolveImportLocale(_ target: ImageImportLocale) -> String? {
        switch target {
        case .active: return localeState.isBaseLocale ? nil : localeState.activeLocaleCode
        case .base: return nil
        case .locale(let code): return code == localeState.baseLocaleCode ? nil : code
        }
    }

    func addImageShape(image: NSImage, centerX: CGFloat, centerY: CGFloat, source: ImageImportOrigin) {
        guard let rowIdx = selectedRowIndex,
              let activeId = activeProjectId else { return }
        let shape = makeImageShape(image: image, row: rows[rowIdx], centerX: centerX, centerY: centerY)
        let saved = withUndo("Add Image") {
            let shapeIndex = rows[rowIdx].shapes.count
            rows[rowIdx].shapes.append(shape)
            selectShape(shape.id, in: rows[rowIdx].id)
            canvasHints.justAddedShapeId = shape.id
            let saved = performSaveImage(
                image,
                for: shape.id,
                activeId: activeId,
                location: (rowIndex: rowIdx, shapeIndex: shapeIndex)
            )
            if !saved {
                rows[rowIdx].shapes.removeAll { $0.id == shape.id }
                selectedShapeIds = []
                canvasHints.justAddedShapeId = nil
            }
            return saved
        }
        guard saved else { return }
        // `makeImageShape` already ran the detector; this is what it decided to build.
        captureImport(count: 1, source: source, device: shape.deviceCategory)
    }

    /// The one place that shapes the `screenshots_imported` payload, so the three import verbs
    /// cannot drift on it.
    func captureImport(count: Int, source: ImageImportOrigin, device: DeviceCategory?) {
        AnalyticsService.capture(.screenshotsImported, [
            .count: count,
            .source: source.rawValue,
            .detectedDevice: device?.rawValue ?? "none",
        ])
    }

    /// Creates an image or device shape sized for the given row, without side effects.
    func makeImageShape(image: NSImage, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        DocumentEditing.makeImageShape(image: image, row: row, centerX: centerX, centerY: centerY)
    }

    /// Import multiple images into a row. If the row already has device shapes, fills those
    /// in template order and skips templates without a device. Overflow images (beyond the
    /// number of existing devices) are placed into freshly appended templates. Rows with no
    /// existing devices fall back to the legacy one-image-per-template behavior.
    /// Registers a single undo operation for the entire batch.
    /// `maxTemplatesPerRow` caps the row's resulting template count (free-tier limit) by
    /// importing only as many images as fit; pass `nil` for unlimited (Pro). Returns the
    /// number of images imported, so the caller can surface a paywall when some were dropped.
    ///
    /// The document mutation runs synchronously in one undo step; the image encode, disk write and
    /// thumbnail decode are staged and flushed off the main actor afterwards, so the row appears
    /// immediately and the screenshots fill in as they land (SCREENSHOT-BRO-W).
    @discardableResult
    func batchImportImages(
        _ sources: [ImageImportSource],
        into rowId: UUID,
        maxTemplatesPerRow: Int? = nil,
        source: ImageImportOrigin,
        targetLocale: ImageImportLocale = .active
    ) async -> Int {
        guard let idx = rowIndex(for: rowId),
              let activeId = activeProjectId,
              !sources.isEmpty else { return 0 }

        let span = PerfSignpost.begin("AppState.batchImportImages", "images=\(sources.count)")
        defer { PerfSignpost.end("AppState.batchImportImages", span) }

        let batch = stageBatchImport(
            sources, intoRowAt: idx, rowId: rowId,
            localeCode: resolveImportLocale(targetLocale), maxTemplatesPerRow: maxTemplatesPerRow
        )
        return await finishImport(batch, source: source, rowIndex: idx, activeId: activeId)
    }

    /// Imports one batch per locale into a row as a single undo step. Base-locale batches should
    /// come first, so a later locale never seeds the base image a base batch is about to set.
    @discardableResult
    func importLocalizedScreenshots(
        _ batches: [(localeCode: String, sources: [ImageImportSource])],
        into rowId: UUID,
        addingLocales: [LocaleDefinition] = [],
        maxTemplatesPerRow: Int? = nil
    ) async -> Int {
        guard let idx = rowIndex(for: rowId), let activeId = activeProjectId else { return 0 }
        var combined = StagedImport()
        withUndo("Import Localized Screenshots") {
            for locale in addingLocales where !localeState.hasLocale(locale.code) {
                LocaleService.addLocale(&localeState, locale: locale)
            }
            for batch in batches {
                combined += stageBatchImport(
                    batch.sources, intoRowAt: idx, rowId: rowId,
                    localeCode: resolveImportLocale(.locale(batch.localeCode)),
                    maxTemplatesPerRow: maxTemplatesPerRow
                )
            }
        }
        return await finishImport(combined, source: .folder, rowIndex: idx, activeId: activeId)
    }

    /// Screenshots already set for a language that `importLocalizedScreenshots` would overwrite.
    /// A language still showing the base image isn't counted — importing there adds, not replaces.
    func screenshotsReplaced(by plan: LocaleFolderImportPlan, inRow rowId: UUID) -> Int {
        guard let idx = rowIndex(for: rowId) else { return 0 }
        let row = rows[idx]
        let targets = DocumentEditing.templatesContainingDevices(in: rows[idx])
        return plan.batches.reduce(0) { total, batch in
            let localeCode = resolveImportLocale(.locale(batch.localeCode))
            let replaced = targets.prefix(batch.files.count).filter { templateIndex in
                guard let shapeIndex = DocumentEditing.existingDeviceShapeIndex(in: row, templateIndex: templateIndex) else { return false }
                let shape = row.shapes[shapeIndex]
                guard let localeCode else { return shape.displayImageFileName != nil }
                return localeState.override(forCode: localeCode, shapeId: shape.id)?.overrideImageFileName != nil
            }
            return total + replaced.count
        }
    }

    /// Reports, writes and cleans up after the document mutation has landed.
    private func finishImport(_ batch: StagedImport, source: ImageImportOrigin, rowIndex idx: Int, activeId: UUID) async -> Int {
        guard batch.imported > 0 else { return 0 }
        captureImport(count: batch.imported, source: source, device: rows[idx].defaultDeviceCategory)
        await flushStagedImageWrites(batch.staged, activeId: activeId)
        // One document walk for the whole batch instead of one per replaced image.
        cleanupUnreferencedImages(batch.replaced)
        return batch.imported
    }

    /// The synchronous half of an import: the document mutation, in its own undo step unless an
    /// outer transaction is open. File writes are returned for the caller to flush.
    private func stageBatchImport(
        _ sources: [ImageImportSource],
        intoRowAt idx: Int,
        rowId: UUID,
        localeCode: String?,
        maxTemplatesPerRow: Int?
    ) -> StagedImport {
        withUndo("Import Screenshots") {
            let batch = DocumentEditing.stageImport(
                sources, into: &rows[idx], localeCode: localeCode,
                maxTemplatesPerRow: maxTemplatesPerRow, localeState: &localeState
            )
            if batch.imported > 0 { selectRow(rowId) }
            return batch
        }
    }

    /// Writes every staged resource, publishing each editor thumbnail as it lands so the row fills
    /// in progressively.
    private func flushStagedImageWrites(_ staged: [StagedImageWrite], activeId: UUID) async {
        let failures = await DocumentEditing.flush(staged, to: PersistenceService.resourcesDir(activeId)) { fileName, thumbnail in
            screenshotImages[fileName] = thumbnail
        }
        if let failure = failures.last { saveError = failure }
    }
}

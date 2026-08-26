import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ImageResourceIO {
    static let defaultWriteData: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
    static var writeData: (Data, URL) throws -> Void = defaultWriteData
}

/// One image handed to a batch import. `sourceURL` is present only when the caller read the image
/// off disk (the MCP `import_screenshots` tool), which is what lets the writer copy an
/// already-PNG file verbatim; drag-and-drop yields an `NSImage` with no durable originating file.
struct ImageImportSource {
    let image: NSImage
    var sourceURL: URL?
}

/// A resource the batch import has already pointed the document at but not yet written to disk.
/// The write happens after the undo step commits, off the main actor — a 20-image import used to
/// block the main thread for 1.5-3.1 s and trip the app-hang watchdog (SCREENSHOT-BRO-W).
private struct StagedImageWrite {
    let fileName: String
    let source: StagedImageSource
}

extension AppState {

    // MARK: - Screenshot Images

    func saveImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId,
              let location = shapeLocation(for: shapeId) else { return }
        guard !rows[location.rowIndex].shapes[location.shapeIndex].resolvedIsLocked else { return }
        withUndo("Assign Screenshot") {
            _ = performSaveImage(image, for: shapeId, activeId: activeId, location: location)
        }
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
            if !localeState.isBaseLocale {
                let existingOverride = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId)
                guard var override = existingOverride, override.overrideImageFileName != nil else { return }
                let oldFile = override.overrideImageFileName
                override.overrideImageFileName = nil
                LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override.isEmpty ? nil : override)
                if let oldFile { cleanupUnreferencedImage(oldFile) }
            } else {
                let shape = rows[location.rowIndex].shapes[location.shapeIndex]
                guard shape.displayImageFileName != nil else { return }
                rows[location.rowIndex].shapes[location.shapeIndex].displayImageFileName = nil
                if let oldFile = shape.displayImageFileName { cleanupUnreferencedImage(oldFile) }
            }
        }
    }

    /// Saves image file and updates state without registering undo or scheduling save.
    /// Used by compound operations that manage their own undo (addImageShape, batchImportImages).
    @discardableResult
    private func performSaveImage(_ image: NSImage, for shapeId: UUID,
                                  activeId: UUID? = nil, location: (rowIndex: Int, shapeIndex: Int)? = nil) -> Bool {
        guard let activeId = activeId ?? activeProjectId else { return false }
        guard let location = location ?? shapeLocation(for: shapeId) else { return false }

        let fileName = screenshotImageFileName(for: shapeId)
        guard let thumbnail = persistImageResource(
            image,
            named: fileName,
            activeId: activeId,
            action: Self.saveScreenshotAction
        ) else {
            return false
        }
        screenshotImages[fileName] = thumbnail
        cleanupUnreferencedImage(pointShape(at: location, shapeId: shapeId, at: fileName, imageSize: image.size))
        return true
    }

    /// Batch sibling of `performSaveImage`: points the document at the new file now and returns the
    /// bytes still owed to disk, so the whole undo step commits without touching the filesystem.
    private func stageSaveImage(_ source: ImageImportSource, for shapeId: UUID,
                                location: (rowIndex: Int, shapeIndex: Int)) -> (StagedImageWrite, replaced: String?) {
        let fileName = screenshotImageFileName(for: shapeId)
        let replaced = pointShape(at: location, shapeId: shapeId, at: fileName, imageSize: source.image.size)
        let staged = StagedImageWrite(
            fileName: fileName,
            source: source.sourceURL.map { .file($0) } ?? .image(source.image)
        )
        return (staged, replaced)
    }

    /// Repoints one shape (or its active-locale override) at `fileName`, returning the file it
    /// replaced. The half `performSaveImage` and `stageSaveImage` share.
    private func pointShape(at location: (rowIndex: Int, shapeIndex: Int), shapeId: UUID,
                            at fileName: String, imageSize: CGSize) -> String? {
        let previous: String?
        if !localeState.isBaseLocale {
            let shape = rows[location.rowIndex].shapes[location.shapeIndex]
            var override = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId) ?? ShapeLocaleOverride()
            previous = override.overrideImageFileName
            override.overrideImageFileName = fileName
            LocaleService.setShapeOverride(&localeState, shapeId: shape.id, override: override)
        } else {
            var shape = rows[location.rowIndex].shapes[location.shapeIndex]
            previous = shape.displayImageFileName
            shape.displayImageFileName = fileName
            if shape.flexesToImageAspect {
                shape.adaptToImageAspectRatio(imageSize)
            }
            rows[location.rowIndex].shapes[location.shapeIndex] = shape
        }
        return previous == fileName ? nil : previous
    }

    /// Interpolated into the shared "Failed to %@: ..." messages, so the staged path reports the
    /// same wording as the synchronous `persistImageResource` one. Deliberately not localized —
    /// the surrounding format string is, and that is the pre-existing convention here.
    static let saveScreenshotAction = "save screenshot"

    private func screenshotImageFileName(for shapeId: UUID) -> String {
        let localePart = localeState.isBaseLocale ? "" : "-\(localeState.activeLocaleCode)"
        return "\(shapeId.uuidString)\(localePart)-\(UUID().uuidString).png"
    }

    /// How many decoded images to publish at a time. Every merge invalidates each canvas view
    /// that reads `screenshotImages`, so this is not per-image; it's small enough that a large
    /// project fills in visibly from the top instead of appearing all at once at the end.
    private static let imagePublishBatchSize = 4

    func loadScreenshotImages() {
        guard let activeId = activeProjectId else {
            projectOpen.finishImages()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)

        imageLoadTask?.cancel()
        imageLoadTask = nil

        let needed = editorReferencedImageFileNames()

        // Evict images that are no longer needed (e.g. after locale switch)
        let stale = Set(screenshotImages.keys).subtracting(needed)
        for key in stale {
            screenshotImages.removeValue(forKey: key)
        }

        let toLoad = needed.filter { screenshotImages[$0] == nil }
        guard !toLoad.isEmpty else {
            projectOpen.finishImages()
            return
        }
        projectOpen.beginImages(total: toLoad.count)

        // Load downsampled images on a background thread, then publish in batches on main.
        // Full-resolution images are loaded from disk on-demand in export paths.
        let maxDim = ImageDownsampler.editorImageMaxDimension
        let batchSize = Self.imagePublishBatchSize
        imageLoadTask = Task.detached { [weak self] in
            var batch: [String: NSImage] = [:]
            var completed = 0

            for fileName in toLoad {
                if Task.isCancelled { return }
                let url = resourcesURL.appendingPathComponent(fileName)
                autoreleasepool {
                    if let image = ImageDownsampler.downsampledImage(at: url, maxDimension: maxDim)
                        ?? NSImage(contentsOf: url) {
                        batch[fileName] = image
                    }
                }
                completed += 1
                if batch.count >= batchSize || completed == toLoad.count {
                    let published = batch
                    batch = [:]
                    await self?.publishLoadedImages(published, completed: completed, for: activeId)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.finishImageLoading(for: activeId)
        }
    }

    /// Both main-actor tails of the decode loop guard on the same thing: a switch may have landed
    /// while we were decoding, and the incoming project must not inherit these images.
    private func publishLoadedImages(_ images: [String: NSImage], completed: Int, for projectId: UUID) {
        guard activeProjectId == projectId else { return }
        screenshotImages.merge(images) { _, new in new }
        projectOpen.advanceImages(to: completed)
    }

    private func finishImageLoading(for projectId: UUID) {
        guard activeProjectId == projectId else { return }
        projectOpen.finishImages()
    }

    func addImageShape(image: NSImage, centerX: CGFloat, centerY: CGFloat) {
        guard let rowIdx = selectedRowIndex,
              let activeId = activeProjectId else { return }
        let shape = makeImageShape(image: image, row: rows[rowIdx], centerX: centerX, centerY: centerY)
        withUndo("Add Image") {
            let shapeIndex = rows[rowIdx].shapes.count
            rows[rowIdx].shapes.append(shape)
            selectShape(shape.id, in: rows[rowIdx].id)
            justAddedShapeId = shape.id
            if !performSaveImage(
                image,
                for: shape.id,
                activeId: activeId,
                location: (rowIndex: rowIdx, shapeIndex: shapeIndex)
            ) {
                rows[rowIdx].shapes.removeAll { $0.id == shape.id }
                selectedShapeIds = []
                justAddedShapeId = nil
            }
        }
    }

    /// Creates an image or device shape sized for the given row, without side effects.
    func makeImageShape(image: NSImage, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        if let rawCategory = ScreenshotDeviceDetector.detectScreenshotDevice(image) {
            // Phone/tablet pixel sizes overlap between Apple and Android, so when the row's
            // default is an Android category we honor it instead of the Apple-leaning fallback.
            let detectedCategory: DeviceCategory
            switch (row.defaultDeviceCategory, rawCategory) {
            case (.androidPhone, .iphone):
                detectedCategory = .androidPhone
            case (.androidTablet, .ipadPro11), (.androidTablet, .ipadPro13):
                detectedCategory = .androidTablet
            default:
                detectedCategory = rawCategory
            }
            var shape = CanvasShapeModel.defaultDeviceFromRow(
                row,
                centerX: centerX,
                centerY: centerY,
                detectedCategory: detectedCategory
            )
            if let preferredFrame = ScreenshotDeviceDetector.preferredImportFrame(for: image, in: row, detectedCategory: detectedCategory) {
                shape.selectRealFrame(preferredFrame)
                shape.adjustToDeviceAspectRatio(centerX: centerX)
                // A landscape flip preserves the long side, which overflows a portrait template.
                shape.scaleToFitWidth(row.templateWidth * 0.9)
            }
            return shape
        }
        let imgW = image.size.width
        let imgH = image.size.height
        let maxW = row.templateWidth * 0.8
        let maxH = row.templateHeight * 0.8
        let scale = min(maxW / imgW, maxH / imgH, 1.0)
        let w = imgW * scale
        let h = imgH * scale
        return CanvasShapeModel(
            type: .image,
            x: centerX - w / 2,
            y: centerY - h / 2,
            width: w,
            height: h,
            color: .clear
        )
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
    func batchImportImages(_ sources: [ImageImportSource], into rowId: UUID, maxTemplatesPerRow: Int? = nil) async -> Int {
        guard let idx = rowIndex(for: rowId),
              let activeId = activeProjectId,
              !sources.isEmpty else { return 0 }

        let templatesWithDevices = templatesContainingDevices(inRowAt: idx)
        // Templates an image can fill without creating a new one.
        let reusableCount = templatesWithDevices.isEmpty ? rows[idx].templates.count : templatesWithDevices.count
        var sources = sources
        if let cap = maxTemplatesPerRow {
            let maxImages = reusableCount + max(0, cap - rows[idx].templates.count)
            if sources.count > maxImages {
                sources = Array(sources.prefix(maxImages))
            }
        }
        guard !sources.isEmpty else { return 0 }

        var staged: [StagedImageWrite] = []
        var replacedFiles: [String?] = []
        withUndo("Import Screenshots") {
            selectRow(rowId)

            var targetTemplateIndices: [Int]
            if templatesWithDevices.isEmpty {
                while rows[idx].templates.count < sources.count {
                    appendTemplate(to: idx)
                }
                targetTemplateIndices = Array(0..<sources.count)
            } else {
                targetTemplateIndices = Array(templatesWithDevices.prefix(sources.count))
                while targetTemplateIndices.count < sources.count {
                    appendTemplate(to: idx)
                    targetTemplateIndices.append(rows[idx].templates.count - 1)
                }
            }

            for (source, templateIndex) in zip(sources, targetTemplateIndices) {
                guard let (write, replaced) = importImage(source, intoTemplateAt: templateIndex, rowIndex: idx) else { continue }
                staged.append(write)
                replacedFiles.append(replaced)
            }
        }
        AnalyticsService.capture(.screenshotsImported, [
            .count: sources.count,
            .detectedDevice: rows[idx].defaultDeviceCategory?.rawValue ?? "none",
        ])

        await flushStagedImageWrites(staged, activeId: activeId)
        // One document walk for the whole batch instead of one per replaced image.
        cleanupUnreferencedImages(replacedFiles)
        return sources.count
    }

    /// Writes every staged resource, publishing each editor thumbnail as it lands so the row fills
    /// in progressively. Every step that costs real time — the source read or copy, the PNG encode,
    /// the disk write, the thumbnail decode — happens inside a `@concurrent` call, so this loop
    /// suspends at least once per image and the main actor keeps drawing throughout.
    private func flushStagedImageWrites(_ staged: [StagedImageWrite], activeId: UUID) async {
        let resourcesDir = PersistenceService.resourcesDir(activeId)
        for write in staged {
            let destination = resourcesDir.appendingPathComponent(write.fileName)
            do {
                switch write.source {
                case .file(let url):
                    try await StagedImageWriter.persist(copying: url, to: destination)
                case .image(let image):
                    // Pulled here, one at a time: `NSImage` can't cross actors, and decoding all of
                    // them up front would hold every full-resolution bitmap for the whole flush.
                    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw StagedImageWriteError.noImageData
                    }
                    try await StagedImageWriter.persist(encoding: cgImage, to: destination)
                }
            } catch StagedImageWriteError.writeFailed(let reason) {
                // The model already references this name. Leaving the reference is the least
                // destructive outcome: a missing resource loads as an empty device, whereas
                // retracting it would edit the document after the undo step has closed.
                saveError = String(localized: "Failed to \(Self.saveScreenshotAction): \(reason)")
                continue
            } catch {
                saveError = String(localized: "Failed to \(Self.saveScreenshotAction): could not encode image.")
                continue
            }

            if let thumbnail = await ImageDownsampler.downsampledCGImageOffMain(
                at: destination,
                maxDimension: ImageDownsampler.editorImageMaxDimension
            ) {
                screenshotImages[write.fileName] = NSImage(
                    cgImage: thumbnail,
                    size: NSSize(width: thumbnail.width, height: thumbnail.height)
                )
            }
        }
    }

    private func templatesContainingDevices(inRowAt rowIndex: Int) -> [Int] {
        let row = rows[rowIndex]
        return (0..<row.templates.count).filter { templateIndex in
            existingDeviceShapeIndex(in: row, templateIndex: templateIndex) != nil
        }
    }

    private func importImage(_ source: ImageImportSource, intoTemplateAt templateIndex: Int,
                             rowIndex: Int) -> (StagedImageWrite, replaced: String?)? {
        let row = rows[rowIndex]
        if let shapeIndex = existingDeviceShapeIndex(in: row, templateIndex: templateIndex) {
            return stageSaveImage(source, for: row.shapes[shapeIndex].id,
                                  location: (rowIndex: rowIndex, shapeIndex: shapeIndex))
        }

        let centerX = row.templateCenterX(at: templateIndex)
        let centerY = row.templateHeight / 2
        let shape = makeImageShape(image: source.image, row: row, centerX: centerX, centerY: centerY)
        let shapeIndex = rows[rowIndex].shapes.count
        rows[rowIndex].shapes.append(shape)
        return stageSaveImage(source, for: shape.id, location: (rowIndex: rowIndex, shapeIndex: shapeIndex))
    }

    private func existingDeviceShapeIndex(in row: ScreenshotRow, templateIndex: Int) -> Int? {
        let templateCenterX = row.templateCenterX(at: templateIndex)
        let templateCenterY = row.templateHeight / 2

        var best: (index: Int, hasRealFrame: Bool, distance: CGFloat)?

        for (index, shape) in row.shapes.enumerated() {
            guard shape.type == .device,
                  row.owningTemplateIndex(for: shape) == templateIndex else { continue }

            let hasRealFrame = shape.deviceFrameId != nil
            let shapeCenterX = shape.x + shape.width / 2
            let shapeCenterY = shape.y + shape.height / 2
            let distance = abs(shapeCenterX - templateCenterX) + abs(shapeCenterY - templateCenterY)

            guard let current = best else {
                best = (index, hasRealFrame, distance)
                continue
            }

            if hasRealFrame != current.hasRealFrame {
                if hasRealFrame { best = (index, hasRealFrame, distance) }
            } else if distance < current.distance {
                best = (index, hasRealFrame, distance)
            } else if distance == current.distance && index < current.index {
                best = (index, hasRealFrame, distance)
            }
        }

        return best?.index
    }

}

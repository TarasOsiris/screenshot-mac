import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ImageResourceIO {
    static let defaultWriteData: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
    static var writeData: (Data, URL) throws -> Void = defaultWriteData
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

        let isNonBaseLocale = !localeState.isBaseLocale
        let fileName = screenshotImageFileName(for: shapeId, localeCode: isNonBaseLocale ? localeState.activeLocaleCode : nil)
        guard let thumbnail = persistImageResource(
            image,
            named: fileName,
            activeId: activeId,
            action: "save screenshot"
        ) else {
            return false
        }

        screenshotImages[fileName] = thumbnail

        if isNonBaseLocale {
            let shape = rows[location.rowIndex].shapes[location.shapeIndex]
            let existingOverride = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId)
            var override = existingOverride ?? ShapeLocaleOverride()
            let previousOverrideFile = override.overrideImageFileName
            override.overrideImageFileName = fileName
            LocaleService.setShapeOverride(&localeState, shapeId: shape.id, override: override)
            if let oldFile = previousOverrideFile, oldFile != fileName {
                cleanupUnreferencedImage(oldFile)
            }
        } else {
            var shape = rows[location.rowIndex].shapes[location.shapeIndex]
            let previousFile = shape.displayImageFileName
            shape.displayImageFileName = fileName

            if shape.flexesToImageAspect {
                shape.adaptToImageAspectRatio(image.size)
            }

            rows[location.rowIndex].shapes[location.shapeIndex] = shape

            if let oldFile = previousFile, oldFile != fileName {
                cleanupUnreferencedImage(oldFile)
            }
        }
        return true
    }

    private func screenshotImageFileName(for shapeId: UUID, localeCode: String?) -> String {
        let localePart = localeCode.map { "-\($0)" } ?? ""
        return "\(shapeId.uuidString)\(localePart)-\(UUID().uuidString).png"
    }

    func loadScreenshotImages() {
        guard let activeId = activeProjectId else {
            finishProjectOpening()
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
            finishProjectOpening()
            return
        }

        // Load downsampled images on a background thread, then update on main.
        // Full-resolution images are loaded from disk on-demand in export paths.
        let maxDim = ImageDownsampler.editorImageMaxDimension
        imageLoadTask = Task.detached { [weak self] in
            var loaded: [String: NSImage] = [:]
            for fileName in toLoad {
                if Task.isCancelled { return }
                let url = resourcesURL.appendingPathComponent(fileName)
                autoreleasepool {
                    if let image = ImageDownsampler.downsampledImage(at: url, maxDimension: maxDim)
                        ?? NSImage(contentsOf: url) {
                        loaded[fileName] = image
                    }
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.activeProjectId == activeId else { return }
                self.screenshotImages.merge(loaded) { _, new in new }
                self.finishProjectOpening()
            }
        }
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
    @discardableResult
    func batchImportImages(_ images: [NSImage], into rowId: UUID, maxTemplatesPerRow: Int? = nil) -> Int {
        guard let idx = rowIndex(for: rowId),
              let activeId = activeProjectId,
              !images.isEmpty else { return 0 }

        let templatesWithDevices = templatesContainingDevices(inRowAt: idx)
        // Templates an image can fill without creating a new one.
        let reusableCount = templatesWithDevices.isEmpty ? rows[idx].templates.count : templatesWithDevices.count
        var images = images
        if let cap = maxTemplatesPerRow {
            let maxImages = reusableCount + max(0, cap - rows[idx].templates.count)
            if images.count > maxImages {
                images = Array(images.prefix(maxImages))
            }
        }
        guard !images.isEmpty else { return 0 }

        withUndo("Import Screenshots") {
            selectRow(rowId)

            var targetTemplateIndices: [Int]
            if templatesWithDevices.isEmpty {
                while rows[idx].templates.count < images.count {
                    appendTemplate(to: idx)
                }
                targetTemplateIndices = Array(0..<images.count)
            } else {
                targetTemplateIndices = Array(templatesWithDevices.prefix(images.count))
                while targetTemplateIndices.count < images.count {
                    appendTemplate(to: idx)
                    targetTemplateIndices.append(rows[idx].templates.count - 1)
                }
            }

            for (image, templateIndex) in zip(images, targetTemplateIndices) {
                importImage(image, intoTemplateAt: templateIndex, rowIndex: idx, activeId: activeId)
            }
        }
        return images.count
    }

    private func templatesContainingDevices(inRowAt rowIndex: Int) -> [Int] {
        let row = rows[rowIndex]
        return (0..<row.templates.count).filter { templateIndex in
            existingDeviceShapeIndex(in: row, templateIndex: templateIndex) != nil
        }
    }

    private func importImage(_ image: NSImage, intoTemplateAt templateIndex: Int, rowIndex: Int, activeId: UUID) {
        let row = rows[rowIndex]
        if let shapeIndex = existingDeviceShapeIndex(in: row, templateIndex: templateIndex) {
            let shapeId = row.shapes[shapeIndex].id
            _ = performSaveImage(
                image,
                for: shapeId,
                activeId: activeId,
                location: (rowIndex: rowIndex, shapeIndex: shapeIndex)
            )
            return
        }

        let centerX = row.templateCenterX(at: templateIndex)
        let centerY = row.templateHeight / 2
        let shape = makeImageShape(image: image, row: row, centerX: centerX, centerY: centerY)
        let shapeIndex = rows[rowIndex].shapes.count
        rows[rowIndex].shapes.append(shape)
        if !performSaveImage(
            image,
            for: shape.id,
            activeId: activeId,
            location: (rowIndex: rowIndex, shapeIndex: shapeIndex)
        ) {
            rows[rowIndex].shapes.removeAll { $0.id == shape.id }
        }
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

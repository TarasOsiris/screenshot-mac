import SwiftUI
import UniformTypeIdentifiers
import ImageIO

enum ImageResourceIO {
    static let defaultWriteData: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
    static var writeData: (Data, URL) throws -> Void = defaultWriteData
}

extension AppState {

    /// Maximum pixel dimension for images stored in `screenshotImages` (editor display).
    /// Full-resolution images are loaded from disk on-demand for export.
    /// 1200px is enough for editor display at 2x zoom on retina, while
    /// reducing memory ~10x vs full App Store screenshot resolution.
    static let editorImageMaxDimension: CGFloat = 1200

    // MARK: - Screenshot Images

    func saveImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId,
              let location = shapeLocation(for: shapeId) else { return }
        registerUndoForRow(at: location.rowIndex, "Assign Screenshot")
        if performSaveImage(image, for: shapeId, activeId: activeId, location: location) {
            scheduleSave()
        }
    }

    func clearImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }

        if !localeState.isBaseLocale {
            let existingOverride = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId)
            guard var override = existingOverride, override.overrideImageFileName != nil else { return }
            registerUndoForRow(at: location.rowIndex, "Clear Screenshot")
            let oldFile = override.overrideImageFileName
            override.overrideImageFileName = nil
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override.isEmpty ? nil : override)
            if let oldFile { cleanupUnreferencedImage(oldFile) }
        } else {
            let shape = rows[location.rowIndex].shapes[location.shapeIndex]
            guard shape.displayImageFileName != nil else { return }
            registerUndoForRow(at: location.rowIndex, "Clear Screenshot")
            rows[location.rowIndex].shapes[location.shapeIndex].displayImageFileName = nil
            if let oldFile = shape.displayImageFileName { cleanupUnreferencedImage(oldFile) }
        }
        scheduleSave()
    }

    /// Saves image file and updates state without registering undo or scheduling save.
    /// Used by compound operations that manage their own undo (addImageShape, batchImportImages).
    @discardableResult
    private func performSaveImage(_ image: NSImage, for shapeId: UUID,
                                  activeId: UUID? = nil, location: (rowIndex: Int, shapeIndex: Int)? = nil) -> Bool {
        guard let activeId = activeId ?? activeProjectId else { return false }
        guard let location = location ?? shapeLocation(for: shapeId) else { return false }

        let isNonBaseLocale = !localeState.isBaseLocale
        let suffix = isNonBaseLocale ? "-\(localeState.activeLocaleCode)" : ""
        let fileName = "\(shapeId.uuidString)\(suffix).png"
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

            if shape.deviceCategory == .invisible {
                shape.adaptToImageAspectRatio(image.size)
            }

            rows[location.rowIndex].shapes[location.shapeIndex] = shape

            if let oldFile = previousFile, oldFile != fileName {
                cleanupUnreferencedImage(oldFile)
            }
        }
        return true
    }

    func loadScreenshotImages() {
        guard let activeId = activeProjectId else {
            isLoadingImages = false
            finishProjectOpening()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)

        // Cancel any in-flight load from a previous call
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
            isLoadingImages = false
            finishProjectOpening()
            return
        }

        isLoadingImages = true

        // Load downsampled images on a background thread, then update on main.
        // Full-resolution images are loaded from disk on-demand in export paths.
        let maxDim = Self.editorImageMaxDimension
        imageLoadTask = Task.detached { [weak self] in
            var loaded: [String: NSImage] = [:]
            for fileName in toLoad {
                if Task.isCancelled { return }
                let url = resourcesURL.appendingPathComponent(fileName)
                autoreleasepool {
                    if let image = Self.downsampledImage(at: url, maxDimension: maxDim)
                        ?? NSImage(contentsOf: url) {
                        loaded[fileName] = image
                    }
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.activeProjectId == activeId else { return }
                for (key, image) in loaded {
                    self.screenshotImages[key] = image
                }
                self.isLoadingImages = false
                self.finishProjectOpening()
            }
        }
    }

    func addImageShape(image: NSImage, centerX: CGFloat, centerY: CGFloat) {
        guard let rowIdx = selectedRowIndex,
              let activeId = activeProjectId else { return }
        let shape = makeImageShape(image: image, row: rows[rowIdx], centerX: centerX, centerY: centerY)
        registerUndoForRow(at: rowIdx, "Add Image")
        let shapeIndex = rows[rowIdx].shapes.count
        rows[rowIdx].shapes.append(shape)
        selectShape(shape.id, in: rows[rowIdx].id)
        justAddedShapeId = shape.id
        if performSaveImage(
            image,
            for: shape.id,
            activeId: activeId,
            location: (rowIndex: rowIdx, shapeIndex: shapeIndex)
        ) {
            scheduleSave()
        } else {
            rows[rowIdx].shapes.removeAll { $0.id == shape.id }
            selectedShapeIds = []
            justAddedShapeId = nil
        }
    }

    /// Creates an image or device shape sized for the given row, without side effects.
    func makeImageShape(image: NSImage, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        if let detectedCategory = Self.detectScreenshotDevice(image) {
            var shape = CanvasShapeModel.defaultDeviceFromRow(
                row,
                centerX: centerX,
                centerY: centerY,
                detectedCategory: detectedCategory
            )
            if let preferredFrame = preferredImportFrame(for: image, in: row, detectedCategory: detectedCategory) {
                shape.selectRealFrame(preferredFrame)
                shape.adjustToDeviceAspectRatio(centerX: centerX)
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

    /// Import multiple images into a row, one per template. Creates new templates if needed.
    /// Registers a single undo operation for the entire batch.
    func batchImportImages(_ images: [NSImage], into rowId: UUID) {
        guard let idx = rowIndex(for: rowId),
              let activeId = activeProjectId,
              !images.isEmpty else { return }
        registerUndoForRow(at: idx, "Import Screenshots")
        selectRow(rowId)

        // Create additional templates if needed
        let needed = images.count - rows[idx].templates.count
        for _ in 0..<max(0, needed) {
            appendTemplate(to: idx)
        }

        // Place one image per template
        for (i, image) in images.enumerated() {
            importImage(image, intoTemplateAt: i, rowIndex: idx, activeId: activeId)
        }

        scheduleSave()
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

    private func preferredImportFrame(for image: NSImage, in row: ScreenshotRow, detectedCategory: DeviceCategory) -> DeviceFrame? {
        let isLandscape = Self.imageIsLandscape(image)

        if let frameId = mostCommonDeviceFrameId(in: row, matching: detectedCategory),
           let frame = DeviceFrameCatalog.frame(for: frameId) {
            return landscapeVariant(of: frame, isLandscape: isLandscape)
        }

        if let defaultFrameId = row.defaultDeviceFrameId,
           let defaultFrame = DeviceFrameCatalog.frame(for: defaultFrameId),
           defaultFrame.fallbackCategory == detectedCategory {
            return landscapeVariant(of: defaultFrame, isLandscape: isLandscape)
        }

        return nil
    }

    private func landscapeVariant(of frame: DeviceFrame, isLandscape: Bool?) -> DeviceFrame {
        guard let isLandscape, isLandscape != frame.isLandscape else { return frame }
        return DeviceFrameCatalog.variant(forFrameId: frame.id, isLandscape: isLandscape) ?? frame
    }

    private func mostCommonDeviceFrameId(in row: ScreenshotRow, matching category: DeviceCategory) -> String? {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]

        for (index, shape) in row.shapes.enumerated() where shape.type == .device {
            guard let frameId = shape.deviceFrameId,
                  let frame = DeviceFrameCatalog.frame(for: frameId),
                  frame.fallbackCategory == category else { continue }
            counts[frameId, default: 0] += 1
            firstSeen[frameId] = firstSeen[frameId] ?? index
        }

        return counts.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return (firstSeen[lhs.key] ?? .max) > (firstSeen[rhs.key] ?? .max)
        }?.key
    }

    private static func imageIsLandscape(_ image: NSImage) -> Bool? {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return rep.pixelsWide > rep.pixelsHigh
        }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image.size.width > image.size.height
    }

    // Known screenshot pixel sizes (portrait "WxH") → device category
    private static let knownScreenshotSizes: [String: DeviceCategory] = {
        var map = [String: DeviceCategory]()
        // iPhone
        for size in [
            "750x1334",   // iPhone SE / 8
            "828x1792",   // iPhone XR / 11
            "1080x1920",  // iPhone 6/7/8 Plus
            "1125x2436",  // iPhone X / XS / 11 Pro
            "1080x2340",  // iPhone 12 mini / 13 mini
            "1170x2532",  // iPhone 12 / 13 / 14
            "1179x2556",  // iPhone 14 Pro / 15 / 16
            "1206x2622",  // iPhone 16 Pro / 17 / 17 Pro
            "1260x2736",  // iPhone Air
            "1242x2688",  // iPhone XS Max / 11 Pro Max
            "1284x2778",  // iPhone 12/13 Pro Max
            "1290x2796",  // iPhone 14 Pro Max / 15 Pro Max / 16 Plus
            "1320x2868",  // iPhone 16 Pro Max / 17 Pro Max
        ] { map[size] = .iphone }
        // iPad Pro 11"
        for size in [
            "1668x2388",  // iPad Pro 11" (3rd/4th gen)
            "1668x2420",  // iPad Pro 11" (M4)
        ] { map[size] = .ipadPro11 }
        // iPad Pro 13"
        for size in [
            "2048x2732",  // iPad Pro 12.9" (3rd-6th gen)
            "2064x2752",  // iPad Pro 13" (M4)
        ] { map[size] = .ipadPro13 }
        return map
    }()

    /// Detect if an image looks like a device screenshot. Returns the matching category or nil.
    static func detectScreenshotDevice(_ image: NSImage) -> DeviceCategory? {
        guard let rep = image.representations.first else { return nil }
        let pw = rep.pixelsWide
        let ph = rep.pixelsHigh
        guard pw > 0, ph > 0 else { return nil }
        // Normalize to portrait for lookup
        let (w, h) = pw > ph ? (ph, pw) : (pw, ph)
        if let category = knownScreenshotSizes["\(w)x\(h)"] { return category }
        // Heuristic fallback for phones
        let ratio = CGFloat(h) / CGFloat(w)
        if w >= 640 && w <= 1600 && ratio >= 1.7 && ratio <= 2.4 { return .iphone }
        // Heuristic fallback for iPads
        if w >= 1600 && w <= 2200 && ratio >= 1.2 && ratio <= 1.5 { return w >= 2000 ? .ipadPro13 : .ipadPro11 }
        return nil
    }

}

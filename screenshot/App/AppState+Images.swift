import SwiftUI
import UniformTypeIdentifiers
import ImageIO

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
        registerUndo("Assign Screenshot")
        performSaveImage(image, for: shapeId, activeId: activeId, location: location)
        scheduleSave()
    }

    func clearImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }

        if !localeState.isBaseLocale {
            let existingOverride = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId)
            guard var override = existingOverride, override.overrideImageFileName != nil else { return }
            registerUndo("Clear Screenshot")
            let oldFile = override.overrideImageFileName
            override.overrideImageFileName = nil
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override.isEmpty ? nil : override)
            if let oldFile { cleanupUnreferencedImage(oldFile) }
        } else {
            let shape = rows[location.rowIndex].shapes[location.shapeIndex]
            guard shape.displayImageFileName != nil else { return }
            registerUndo("Clear Screenshot")
            rows[location.rowIndex].shapes[location.shapeIndex].displayImageFileName = nil
            if let oldFile = shape.displayImageFileName { cleanupUnreferencedImage(oldFile) }
        }
        scheduleSave()
    }

    /// Saves image file and updates state without registering undo or scheduling save.
    /// Used by compound operations that manage their own undo (addImageShape, batchImportImages).
    private func performSaveImage(_ image: NSImage, for shapeId: UUID,
                                  activeId: UUID? = nil, location: (rowIndex: Int, shapeIndex: Int)? = nil) {
        guard let activeId = activeId ?? activeProjectId else { return }
        guard let location = location ?? shapeLocation(for: shapeId) else { return }

        let isNonBaseLocale = !localeState.isBaseLocale
        let suffix = isNonBaseLocale ? "-\(localeState.activeLocaleCode)" : ""
        let fileName = "\(shapeId.uuidString)\(suffix).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }

        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = Self.editorThumbnail(for: image)

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
            rows[location.rowIndex].shapes[location.shapeIndex] = shape

            if let oldFile = previousFile, oldFile != fileName {
                cleanupUnreferencedImage(oldFile)
            }
        }
    }

    func loadScreenshotImages() {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)

        // Cancel any in-flight load from a previous call
        imageLoadTask?.cancel()

        let needed = editorReferencedImageFileNames()

        // Evict images that are no longer needed (e.g. after locale switch)
        let stale = Set(screenshotImages.keys).subtracting(needed)
        for key in stale {
            screenshotImages.removeValue(forKey: key)
        }

        let toLoad = needed.filter { screenshotImages[$0] == nil }
        guard !toLoad.isEmpty else { return }

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
            }
        }
    }

    func addImageShape(image: NSImage, centerX: CGFloat, centerY: CGFloat) {
        guard let rowIdx = selectedRowIndex else { return }
        let shape = makeImageShape(image: image, row: rows[rowIdx], centerX: centerX, centerY: centerY)
        registerUndo("Add Image")
        rows[rowIdx].shapes.append(shape)
        selectShape(shape.id, in: rows[rowIdx].id)
        justAddedShapeId = shape.id
        performSaveImage(image, for: shape.id)
        scheduleSave()
    }

    /// Creates an image or device shape sized for the given row, without side effects.
    func makeImageShape(image: NSImage, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        if let detectedCategory = Self.detectScreenshotDevice(image) {
            return CanvasShapeModel.defaultDeviceFromRow(row, centerX: centerX, centerY: centerY, detectedCategory: detectedCategory)
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
        guard let idx = rowIndex(for: rowId), !images.isEmpty else { return }
        registerUndo("Import Screenshots")
        selectRow(rowId)

        // Create additional templates if needed
        let needed = images.count - rows[idx].templates.count
        for _ in 0..<max(0, needed) {
            appendTemplate(to: idx)
        }

        // Place one image per template
        for (i, image) in images.enumerated() {
            let row = rows[idx]
            let centerX = row.templateCenterX(at: i)
            let centerY = row.templateHeight / 2
            let shape = makeImageShape(image: image, row: row, centerX: centerX, centerY: centerY)
            rows[idx].shapes.append(shape)
            performSaveImage(image, for: shape.id)
        }

        scheduleSave()
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

    // MARK: - Shape Fill Images

    func saveShapeFillImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId,
              let location = shapeLocation(for: shapeId) else { return }

        registerUndo("Set Fill Image")

        let fileId = UUID().uuidString
        let fileName = "fill-\(fileId).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }
        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = Self.editorThumbnail(for: image)

        var shape = rows[location.rowIndex].shapes[location.shapeIndex]
        let oldFile = shape.fillImageConfig?.fileName
        if shape.fillImageConfig == nil {
            shape.fillImageConfig = BackgroundImageConfig()
        }
        shape.fillImageConfig?.fileName = fileName
        if shape.fillStyle == nil {
            shape.fillStyle = .image
        }
        rows[location.rowIndex].shapes[location.shapeIndex] = shape
        if let oldFile { cleanupUnreferencedImage(oldFile) }
        scheduleSave()
    }

    func removeShapeFillImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        registerUndo("Remove Fill Image")
        let oldFile = rows[location.rowIndex].shapes[location.shapeIndex].fillImageConfig?.fileName
        rows[location.rowIndex].shapes[location.shapeIndex].fillImageConfig?.fileName = nil
        if let oldFile { cleanupUnreferencedImage(oldFile) }
        scheduleSave()
    }

    // MARK: - Background Images

    func saveBackgroundImage(_ image: NSImage, for rowId: UUID, templateIndex: Int? = nil) {
        guard let activeId = activeProjectId,
              let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }

        registerUndo("Set Background Image")

        let fileId = UUID().uuidString
        let fileName = "bg-\(fileId).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }
        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = Self.editorThumbnail(for: image)

        setBackgroundImageFileName(fileName, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    func removeBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndo("Remove Background Image")
        setBackgroundImageFileName(nil, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    func pickAndSaveBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage.fromSecurityScopedURL(url) else { return }
        saveBackgroundImage(image, for: rowId, templateIndex: templateIndex)
    }

    private func setBackgroundImageFileName(_ newFile: String?, rowIndex: Int, templateIndex: Int?) {
        let oldFile: String?
        if let templateIndex, templateIndex < rows[rowIndex].templates.count {
            oldFile = rows[rowIndex].templates[templateIndex].backgroundImageConfig.fileName
            rows[rowIndex].templates[templateIndex].backgroundImageConfig.fileName = newFile
        } else {
            oldFile = rows[rowIndex].backgroundImageConfig.fileName
            rows[rowIndex].backgroundImageConfig.fileName = newFile
        }
        cleanupUnreferencedImage(oldFile)
    }

    // MARK: - Custom Fonts

    func loadCustomFonts() {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil) else { return }

        var changed = false
        for file in files where Self.fontExtensions.contains(file.pathExtension.lowercased()) {
            let fileName = file.lastPathComponent
            guard customFonts[fileName] == nil else { continue }
            if let familyName = registerFont(at: file) {
                customFonts[fileName] = familyName
                changed = true
            }
        }
        if changed { refreshAvailableFontFamilies() }
    }

    func unregisterCustomFonts() {
        guard let activeId = activeProjectId else {
            customFonts.removeAll()
            refreshAvailableFontFamilies()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        for fileName in customFonts.keys {
            let url = resourcesURL.appendingPathComponent(fileName) as CFURL
            CTFontManagerUnregisterFontsForURL(url, .process, nil)
        }
        customFonts.removeAll()
        refreshAvailableFontFamilies()
    }

    @discardableResult
    func importCustomFont(from url: URL) -> String? {
        guard let activeId = activeProjectId else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let destURL = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            // Already imported — just make sure it's registered
            if customFonts[fileName] == nil, let familyName = registerFont(at: destURL) {
                customFonts[fileName] = familyName
            }
            return customFonts[fileName]
        }

        guard (try? fm.copyItem(at: url, to: destURL)) != nil else { return nil }
        if let familyName = registerFont(at: destURL) {
            customFonts[fileName] = familyName
            refreshAvailableFontFamilies()
            return familyName
        }
        return nil
    }

    func removeCustomFont(_ fileName: String) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let url = resourcesURL.appendingPathComponent(fileName)

        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
        customFonts.removeValue(forKey: fileName)
        refreshAvailableFontFamilies()
    }

    private func registerFont(at url: URL) -> String? {
        // May fail if already registered — that's OK
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String else {
            return nil
        }
        return familyName
    }

    // MARK: - Image Helpers

    /// Collects all image filenames (base + locale overrides) for a set of shapes.
    func imageFileNames(for shapes: [CanvasShapeModel]) -> [String] {
        shapes.flatMap { $0.allImageFileNames } + shapes.flatMap { localeOverrideImageFileNames(for: $0.id) }
    }

    // MARK: - Image Cleanup

    func cleanupOrphanedResourceFiles(for projectId: UUID) {
        let resourcesURL = PersistenceService.resourcesDir(projectId)
        guard let files = try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil) else { return }
        let referenced = allReferencedImageFileNames()
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard !Self.fontExtensions.contains(ext) else { continue }
            let fileName = fileURL.lastPathComponent
            if !referenced.contains(fileName) {
                removeImageFile(fileName)
            }
        }
    }

    func cleanupUnreferencedImage(_ fileName: String?) {
        guard let fileName, !isImageFileReferenced(fileName) else { return }
        removeImageFile(fileName)
    }

    /// Batch cleanup: collects all referenced filenames once, then removes any candidate that is unreferenced.
    func cleanupUnreferencedImages(_ fileNames: [String?]) {
        let candidates = Set(fileNames.compactMap { $0 })
        guard !candidates.isEmpty else { return }
        let referenced = allReferencedImageFileNames()
        for fileName in candidates where !referenced.contains(fileName) {
            removeImageFile(fileName)
        }
    }

    private func removeImageFile(_ fileName: String) {
        screenshotImages.removeValue(forKey: fileName)
        if let projectId = activeProjectId {
            let fileURL = PersistenceService.resourcesDir(projectId).appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Copy image files for a duplicated shape so it has its own independent files.
    /// Updates the shape's image references in-place and copies locale override image files.
    func copyImageFiles(for newShape: inout CanvasShapeModel, originalId: UUID) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let fm = FileManager.default

        // Copy base image file (imageFileName or screenshotFileName)
        if let originalFile = newShape.displayImageFileName {
            let srcURL = resourcesURL.appendingPathComponent(originalFile)
            let newFile = "\(newShape.id.uuidString).png"
            let dstURL = resourcesURL.appendingPathComponent(newFile)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.copyItem(at: srcURL, to: dstURL)
                newShape.displayImageFileName = newFile
                screenshotImages[newFile] = screenshotImages[originalFile]
            }
        }

        // Copy fill image file
        if let originalFillFile = newShape.fillImageConfig?.fileName {
            let srcURL = resourcesURL.appendingPathComponent(originalFillFile)
            let newFillFile = "fill-\(newShape.id.uuidString).png"
            let dstURL = resourcesURL.appendingPathComponent(newFillFile)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.copyItem(at: srcURL, to: dstURL)
                newShape.fillImageConfig?.fileName = newFillFile
                screenshotImages[newFillFile] = screenshotImages[originalFillFile]
            }
        }

        // Copy locale override image files
        let originalKey = originalId.uuidString
        let newKey = newShape.id.uuidString
        for localeCode in localeState.overrides.keys {
            guard var override = localeState.overrides[localeCode]?[originalKey],
                  let originalFile = override.overrideImageFileName else { continue }
            let srcURL = resourcesURL.appendingPathComponent(originalFile)
            let newFile = "\(newShape.id.uuidString)-\(localeCode).png"
            let dstURL = resourcesURL.appendingPathComponent(newFile)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.copyItem(at: srcURL, to: dstURL)
                override.overrideImageFileName = newFile
                localeState.overrides[localeCode]?[newKey] = override
                screenshotImages[newFile] = screenshotImages[originalFile]
            }
        }
    }

    /// Collect all screenshot filenames from locale overrides for a shape.
    func localeOverrideImageFileNames(for shapeId: UUID) -> [String] {
        let key = shapeId.uuidString
        return localeState.overrides.values.compactMap { $0[key]?.overrideImageFileName }
    }

    func isImageFileReferenced(_ fileName: String) -> Bool {
        // Check base shape and background references
        let referencedInRows = rows.contains { row in
            row.backgroundImageConfig.fileName == fileName ||
            row.templates.contains { $0.backgroundImageConfig.fileName == fileName } ||
            row.shapes.contains { shape in
                shape.allImageFileNames.contains(fileName)
            }
        }
        if referencedInRows { return true }

        // Check locale override image references
        return localeState.overrides.values.contains { shapeOverrides in
            shapeOverrides.values.contains { $0.overrideImageFileName == fileName }
        }
    }

    // MARK: - Downsampled Image Loading

    /// Returns a downsampled thumbnail for editor display, falling back to the original image.
    static func editorThumbnail(for image: NSImage) -> NSImage {
        guard let tiffData = image.tiffRepresentation else { return image }
        return downsampledImage(from: tiffData, maxDimension: editorImageMaxDimension) ?? image
    }

    /// Efficiently loads a downsampled image from a file URL using CGImageSource.
    static func downsampledImage(at url: URL, maxDimension: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return downsampledImage(from: source, maxDimension: maxDimension)
    }

    /// Downsamples from in-memory image data using CGImageSource (avoids disk round-trip).
    static func downsampledImage(from data: Data, maxDimension: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return downsampledImage(from: source, maxDimension: maxDimension)
    }

    private static func downsampledImage(from source: CGImageSource, maxDimension: CGFloat) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Loads full-resolution images for the given filenames from disk.
    /// Pass `cache` to avoid redundant disk reads across multiple calls (e.g. during export).
    func loadFullResolutionImages(
        fileNames: Set<String>,
        cache: inout [String: NSImage]
    ) -> [String: NSImage] {
        guard let activeId = activeProjectId else { return [:] }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        var images: [String: NSImage] = [:]
        for fileName in fileNames {
            if let cached = cache[fileName] {
                images[fileName] = cached
            } else {
                autoreleasepool {
                    let url = resourcesURL.appendingPathComponent(fileName)
                    if let image = NSImage(contentsOf: url) {
                        images[fileName] = image
                        cache[fileName] = image
                    }
                }
            }
        }
        return images
    }

    // MARK: - Referenced Image Filenames

    /// Collect referenced image filenames for the given rows and locale overrides.
    private func referencedImageFileNames(
        rows targetRows: [ScreenshotRow],
        localeOverrides: [String: [String: ShapeLocaleOverride]]
    ) -> Set<String> {
        var result = Set<String>()
        for row in targetRows {
            if let f = row.backgroundImageConfig.fileName { result.insert(f) }
            for template in row.templates {
                if let f = template.backgroundImageConfig.fileName { result.insert(f) }
            }
            for shape in row.shapes {
                for f in shape.allImageFileNames { result.insert(f) }
            }
        }
        for shapeOverrides in localeOverrides.values {
            for override in shapeOverrides.values {
                if let f = override.overrideImageFileName { result.insert(f) }
            }
        }
        return result
    }

    /// Image filenames needed for the editor (base shapes + active locale overrides only).
    func editorReferencedImageFileNames() -> Set<String> {
        let activeCode = localeState.activeLocaleCode
        let activeOverrides = localeState.overrides[activeCode].map { [activeCode: $0] } ?? [:]
        return referencedImageFileNames(rows: rows, localeOverrides: activeOverrides)
    }

    /// Collect all referenced image filenames in a single pass (for batch cleanup).
    func allReferencedImageFileNames() -> Set<String> {
        referencedImageFileNames(rows: rows, localeOverrides: localeState.overrides)
    }

    /// Image filenames for a specific row and locale (for per-row export).
    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        let localeOverrides = localeState.overrides[localeCode].map { [localeCode: $0] } ?? [:]
        return referencedImageFileNames(rows: [row], localeOverrides: localeOverrides)
    }
}

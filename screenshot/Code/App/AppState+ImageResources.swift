import SwiftUI
import ImageIO

extension AppState {
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
                        // Create a new NSImage with point size equal to pixel
                        // dimensions so SwiftUI uses full resolution at 1x export
                        // rendering (not limited by DPI metadata). A new NSImage
                        // avoids mutating the shared NSImageRep.
                        if let rep = image.representations.first,
                           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                            let normalized = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
                            normalized.addRepresentation(rep)
                            images[fileName] = normalized
                            cache[fileName] = normalized
                        } else {
                            images[fileName] = image
                            cache[fileName] = image
                        }
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

    /// Loads full-resolution images for a single row and locale from disk.
    func loadFullResolutionImages(forRow row: ScreenshotRow, localeCode: String) -> [String: NSImage] {
        let fileNames = referencedImageFileNames(forRow: row, localeCode: localeCode)
        var cache: [String: NSImage] = [:]
        return loadFullResolutionImages(fileNames: fileNames, cache: &cache)
    }
}

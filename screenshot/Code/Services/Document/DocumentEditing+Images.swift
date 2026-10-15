#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import SwiftUI

/// A resource the document already points at, written off the main actor after the edit lands (SCREENSHOT-BRO-W).
struct StagedImageWrite {
    let fileName: String
    let source: StagedImageSource
}

/// The document half of an import, waiting for its files to be written.
struct StagedImport {
    var staged: [StagedImageWrite] = []
    var replaced: [String?] = []
    var imported = 0

    static func += (lhs: inout StagedImport, rhs: StagedImport) {
        lhs.staged += rhs.staged
        lhs.replaced += rhs.replaced
        lhs.imported += rhs.imported
    }
}

/// Copies an image resource inside one project's resources folder, under a new name.
@MainActor
protocol ImageResourceCopying {
    /// False when the source is missing or the copy failed; the duplicate then keeps the original's reference.
    func copyImageResource(_ fileName: String, to newFileName: String) -> Bool
}

extension DocumentEditing {

    // MARK: - Images

    /// Repoints one shape (or one locale's override) at `fileName`, returning the file it replaced.
    /// `localeCode` is the locale to write, `nil` for the base image.
    static func pointShape(
        _ shape: inout CanvasShapeModel,
        at fileName: String,
        imageSize: CGSize,
        localeCode: String?,
        localeState: inout LocaleState
    ) -> String? {
        guard let localeCode else {
            let previous = setBaseImage(&shape, fileName: fileName, imageSize: imageSize)
            return previous == fileName ? nil : previous
        }

        // A shape with no base image renders an empty frame in every locale that has no override
        // of its own — and in the export — so the first image to arrive becomes the fallback too.
        // Otherwise a locale-targeted import into a fresh row reports success and ships blanks.
        if shape.displayImageFileName == nil {
            _ = setBaseImage(&shape, fileName: fileName, imageSize: imageSize)
        }
        var override = localeState.override(forCode: localeCode, shapeId: shape.id) ?? ShapeLocaleOverride()
        let previous = override.overrideImageFileName
        override.overrideImageFileName = fileName
        if shape.flexesToImageAspect {
            // An abstract frame takes its aspect from the image, and this locale's image need not
            // match the base one — so the resize has to be an override, not a base edit.
            var flexed = shape
            flexed.adaptToImageAspectRatio(imageSize)
            override.offsetX = flexed.x == shape.x ? nil : flexed.x - shape.x
            override.offsetWidth = flexed.width == shape.width ? nil : flexed.width - shape.width
        }
        LocaleService.setShapeOverride(&localeState, localeCode: localeCode, shapeId: shape.id, override: override)
        return previous == fileName ? nil : previous
    }

    private static func setBaseImage(_ shape: inout CanvasShapeModel, fileName: String, imageSize: CGSize) -> String? {
        let previous = shape.displayImageFileName
        shape.displayImageFileName = fileName
        if shape.flexesToImageAspect {
            shape.adaptToImageAspectRatio(imageSize)
        }
        return previous
    }

    static func screenshotImageFileName(for shapeId: UUID, localeCode: String?) -> String {
        let localePart = localeCode.map { "-\($0)" } ?? ""
        return "\(shapeId.uuidString)\(localePart)-\(UUID().uuidString).png"
    }

    /// Creates an image or device shape sized for the given row, without side effects.
    static func makeImageShape(image: NSImage, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
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

    /// Fills the row's device columns in order (or one column per image when it has no devices),
    /// appending columns for the overflow. `maxTemplatesPerRow` caps the resulting column count.
    /// Returns the files still owed to disk and the ones the import replaced.
    static func stageImport(
        _ sources: [ImageImportSource],
        into row: inout ScreenshotRow,
        localeCode: String?,
        maxTemplatesPerRow: Int?,
        localeState: inout LocaleState
    ) -> StagedImport {
        let templatesWithDevices = templatesContainingDevices(in: row)
        // Templates an image can fill without creating a new one.
        let reusableCount = templatesWithDevices.isEmpty ? row.templates.count : templatesWithDevices.count
        var sources = sources
        if let cap = maxTemplatesPerRow {
            let maxImages = reusableCount + max(0, cap - row.templates.count)
            if sources.count > maxImages {
                sources = Array(sources.prefix(maxImages))
            }
        }
        guard !sources.isEmpty else { return StagedImport() }

        var targetTemplateIndices: [Int]
        if templatesWithDevices.isEmpty {
            while row.templates.count < sources.count {
                insertTemplate(in: &row, at: row.templates.count)
            }
            targetTemplateIndices = Array(0..<sources.count)
        } else {
            targetTemplateIndices = Array(templatesWithDevices.prefix(sources.count))
            while targetTemplateIndices.count < sources.count {
                insertTemplate(in: &row, at: row.templates.count)
                targetTemplateIndices.append(row.templates.count - 1)
            }
        }

        var batch = StagedImport(imported: sources.count)
        for (source, templateIndex) in zip(sources, targetTemplateIndices) {
            let shapeIndex: Int
            if let existing = existingDeviceShapeIndex(in: row, templateIndex: templateIndex) {
                shapeIndex = existing
            } else {
                let shape = makeImageShape(
                    image: source.image, row: row,
                    centerX: row.templateCenterX(at: templateIndex), centerY: row.templateHeight / 2
                )
                shapeIndex = row.shapes.count
                row.shapes.append(shape)
            }
            let fileName = screenshotImageFileName(for: row.shapes[shapeIndex].id, localeCode: localeCode)
            let replaced = pointShape(
                &row.shapes[shapeIndex], at: fileName, imageSize: source.image.size,
                localeCode: localeCode, localeState: &localeState
            )
            batch.staged.append(StagedImageWrite(
                fileName: fileName,
                source: source.sourceURL.map { .file($0) } ?? .image(source.image)
            ))
            batch.replaced.append(replaced)
        }
        return batch
    }

    static func templatesContainingDevices(in row: ScreenshotRow) -> [Int] {
        (0..<row.templates.count).filter { existingDeviceShapeIndex(in: row, templateIndex: $0) != nil }
    }

    /// The device a screenshot dropped on `templateIndex` belongs in: real frames first, then the
    /// one nearest the column's center.
    static func existingDeviceShapeIndex(in row: ScreenshotRow, templateIndex: Int) -> Int? {
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

    /// Writes staged resources off the main actor, publishing each thumbnail; returns a message per failed write.
    static func flush(
        _ staged: [StagedImageWrite],
        to resourcesDir: URL,
        publish: (String, NSImage) -> Void
    ) async -> [String] {
        var failures: [String] = []
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
                failures.append(ImageResourceSaveAction.saveScreenshot.writeFailedMessage(reason))
                continue
            } catch {
                failures.append(ImageResourceSaveAction.saveScreenshot.encodeFailedMessage)
                continue
            }

            if let thumbnail = await ImageDownsampler.downsampledCGImageOffMain(
                at: destination,
                maxDimension: ImageDownsampler.editorImageMaxDimension
            ) {
                publish(write.fileName, NSImage(
                    cgImage: thumbnail,
                    size: NSSize(width: thumbnail.width, height: thumbnail.height)
                ))
            }
        }
        return failures
    }

    // MARK: - Backgrounds

    /// A language's first image also seeds the base, as a shape's first localized screenshot does.
    /// Returns the file it replaced.
    static func setBackgroundImage(_ source: BackgroundImageSource, on config: inout BackgroundImageConfig, localeCode: String?) -> String? {
        if let localeCode, source.hasImage {
            if !config.hasImage { config.source = source }
            return config.localeImages.updateValue(source, forKey: localeCode)?.fileName
        }
        let freed = config.fileName
        config.source = source
        return freed
    }

    /// Every image file `shapes` reference, base and per-locale.
    static func imageFileNames(for shapes: [CanvasShapeModel], localeState: LocaleState) -> [String] {
        shapes.flatMap(\.allImageFileNames) + shapes.flatMap { shape in
            localeState.overrides.values.compactMap { $0[shape.id.uuidString]?.overrideImageFileName }
        }
    }
}

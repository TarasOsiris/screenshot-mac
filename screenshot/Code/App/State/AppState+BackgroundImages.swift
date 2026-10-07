import SwiftUI
import UniformTypeIdentifiers

extension AppState {
    /// Which image write failed, spelled as whole sentences so each reads naturally once translated.
    enum ImageResourceSaveAction {
        case saveScreenshot
        case saveFillImage
        case saveBackgroundImage

        var encodeFailedMessage: String {
            switch self {
            case .saveScreenshot: String(localized: "Failed to save screenshot: could not encode image.")
            case .saveFillImage: String(localized: "Failed to save fill image: could not encode image.")
            case .saveBackgroundImage: String(localized: "Failed to save background image: could not encode image.")
            }
        }

        func writeFailedMessage(_ reason: String) -> String {
            switch self {
            case .saveScreenshot:
                String(localized: "Failed to save screenshot: \(reason)", comment: "The placeholder is the system's error description.")
            case .saveFillImage:
                String(localized: "Failed to save fill image: \(reason)", comment: "The placeholder is the system's error description.")
            case .saveBackgroundImage:
                String(localized: "Failed to save background image: \(reason)", comment: "The placeholder is the system's error description.")
            }
        }
    }

    // MARK: - Shape Fill Images

    func saveShapeFillImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId,
              let location = shapeLocation(for: shapeId) else { return }

        withUndo("Set Fill Image") {
            let fileId = UUID().uuidString
            let fileName = "fill-\(fileId).png"
            guard let thumbnail = persistImageResource(
                image,
                named: fileName,
                activeId: activeId,
                action: .saveFillImage
            ) else {
                return
            }

            screenshotImages[fileName] = thumbnail

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
        }
    }

    func removeShapeFillImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        withUndo("Remove Fill Image") {
            let oldFile = rows[location.rowIndex].shapes[location.shapeIndex].fillImageConfig?.fileName
            rows[location.rowIndex].shapes[location.shapeIndex].fillImageConfig?.fileName = nil
            if let oldFile { cleanupUnreferencedImage(oldFile) }
        }
    }

    // MARK: - Background Images

    func saveBackgroundImage(_ image: NSImage, for rowId: UUID, templateIndex: Int? = nil) {
        guard let activeId = activeProjectId,
              let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }

        withUndo("Set Background Image") {
            let fileId = UUID().uuidString
            let fileName = "bg-\(fileId).png"
            guard let thumbnail = persistImageResource(
                image,
                named: fileName,
                activeId: activeId,
                action: .saveBackgroundImage
            ) else {
                return
            }

            screenshotImages[fileName] = thumbnail

            setBackgroundImage(fileName: fileName, svgContent: nil, rowIndex: rowIndex, templateIndex: templateIndex)
        }
    }

    func saveBackgroundSvg(_ svgContent: String, for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        withUndo("Set Background SVG") {
            setBackgroundImage(fileName: nil, svgContent: svgContent, rowIndex: rowIndex, templateIndex: templateIndex)
        }
    }

    /// In a language with its own image, removes only that image — the same rule as `clearImage(for:)`.
    func removeBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rowIndex(for: rowId) else { return }
        if backgroundImageIsOverridden(forRowAt: rowIndex, templateIndex: templateIndex) == true {
            resetBackgroundImageOverride(for: rowId, templateIndex: templateIndex)
            return
        }
        withUndo("Remove Background Image") {
            setBackgroundImage(fileName: nil, svgContent: nil, rowIndex: rowIndex, templateIndex: templateIndex)
        }
    }

    /// Drops the active language's own background image, so it shows the base language's again.
    func resetBackgroundImageOverride(for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rowIndex(for: rowId),
              let path = backgroundImageConfigPath(rowIndex: rowIndex, templateIndex: templateIndex) else { return }
        let localeCode = localeState.activeLocaleCode
        withUndo("Use Base Background Image") {
            cleanupUnreferencedImage(self[keyPath: path].localeImages.removeValue(forKey: localeCode)?.fileName)
        }
    }

    /// Whether the active language has its own image here; nil in the base language.
    func backgroundImageIsOverridden(forRowAt rowIndex: Int, templateIndex: Int?) -> Bool? {
        guard !localeState.isBaseLocale,
              let path = backgroundImageConfigPath(rowIndex: rowIndex, templateIndex: templateIndex) else { return nil }
        return self[keyPath: path].localeImages[localeState.activeLocaleCode] != nil
    }

    @MainActor
    func pickAndSaveBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        Task { @MainActor in
            switch await SvgHelper.pickImageOrSvg() {
            case .svg(let sanitized):
                saveBackgroundSvg(sanitized, for: rowId, templateIndex: templateIndex)
            case .image(let image):
                saveBackgroundImage(image, for: rowId, templateIndex: templateIndex)
            case .none:
                break
            }
        }
    }

    /// A language's first image also seeds the base, as a shape's first localized screenshot does.
    private func setBackgroundImage(fileName: String?, svgContent: String?, rowIndex: Int, templateIndex: Int?) {
        let source = BackgroundImageSource(fileName: fileName, svgContent: svgContent)
        let localeCode = localeState.isBaseLocale || !source.hasImage ? nil : localeState.activeLocaleCode
        guard let path = backgroundImageConfigPath(rowIndex: rowIndex, templateIndex: templateIndex) else { return }
        let freed: String?
        if let localeCode {
            if !self[keyPath: path].hasImage { self[keyPath: path].source = source }
            freed = self[keyPath: path].localeImages.updateValue(source, forKey: localeCode)?.fileName
        } else {
            freed = self[keyPath: path].fileName
            self[keyPath: path].source = source
        }
        cleanupUnreferencedImage(freed)
    }

    private func backgroundImageConfigPath(rowIndex: Int, templateIndex: Int?) -> ReferenceWritableKeyPath<AppState, BackgroundImageConfig>? {
        guard rows.indices.contains(rowIndex) else { return nil }
        guard let templateIndex else { return \.rows[rowIndex].backgroundImageConfig }
        guard rows[rowIndex].templates.indices.contains(templateIndex) else { return nil }
        return \.rows[rowIndex].templates[templateIndex].backgroundImageConfig
    }

    func persistImageResource(
        _ image: NSImage,
        named fileName: String,
        activeId: UUID,
        action: ImageResourceSaveAction
    ) -> NSImage? {
        guard let pngData = ExportService.pngData(from: image) else {
            saveError = action.encodeFailedMessage
            return nil
        }

        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        do {
            try ImageResourceIO.writeData(pngData, url)
        } catch {
            saveError = action.writeFailedMessage(error.localizedDescription)
            return nil
        }

        // Downsample from the PNG bytes already in hand — `editorThumbnail(for:)` would
        // re-serialize the image through an uncompressed TIFF on the main actor.
        return ImageDownsampler.downsampledImage(from: pngData, maxDimension: ImageDownsampler.editorImageMaxDimension) ?? image
    }

}

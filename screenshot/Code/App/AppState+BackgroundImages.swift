import SwiftUI
import UniformTypeIdentifiers

extension AppState {
    // MARK: - Shape Fill Images

    func saveShapeFillImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId,
              let location = shapeLocation(for: shapeId) else { return }

        registerUndoForRow(at: location.rowIndex, "Set Fill Image")

        let fileId = UUID().uuidString
        let fileName = "fill-\(fileId).png"
        guard let thumbnail = persistImageResource(
            image,
            named: fileName,
            activeId: activeId,
            action: "save fill image"
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
        scheduleSave()
    }

    func removeShapeFillImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        registerUndoForRow(at: location.rowIndex, "Remove Fill Image")
        let oldFile = rows[location.rowIndex].shapes[location.shapeIndex].fillImageConfig?.fileName
        rows[location.rowIndex].shapes[location.shapeIndex].fillImageConfig?.fileName = nil
        if let oldFile { cleanupUnreferencedImage(oldFile) }
        scheduleSave()
    }

    // MARK: - Background Images

    func saveBackgroundImage(_ image: NSImage, for rowId: UUID, templateIndex: Int? = nil) {
        guard let activeId = activeProjectId,
              let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }

        registerUndoForRow(at: rowIndex, "Set Background Image")

        let fileId = UUID().uuidString
        let fileName = "bg-\(fileId).png"
        guard let thumbnail = persistImageResource(
            image,
            named: fileName,
            activeId: activeId,
            action: "save background image"
        ) else {
            return
        }

        screenshotImages[fileName] = thumbnail

        setBackgroundImage(fileName: fileName, svgContent: nil, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    func saveBackgroundSvg(_ svgContent: String, for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndoForRow(at: rowIndex, "Set Background SVG")
        setBackgroundImage(fileName: nil, svgContent: svgContent, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    func removeBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndoForRow(at: rowIndex, "Remove Background Image")
        setBackgroundImage(fileName: nil, svgContent: nil, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    @MainActor
    func pickAndSaveBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        switch SvgHelper.pickImageOrSvg() {
        case .svg(let sanitized):
            saveBackgroundSvg(sanitized, for: rowId, templateIndex: templateIndex)
        case .image(let image):
            saveBackgroundImage(image, for: rowId, templateIndex: templateIndex)
        case .none:
            break
        }
    }

    private func setBackgroundImage(fileName: String?, svgContent: String?, rowIndex: Int, templateIndex: Int?) {
        let oldFile: String?
        if let templateIndex, templateIndex < rows[rowIndex].templates.count {
            oldFile = rows[rowIndex].templates[templateIndex].backgroundImageConfig.fileName
            rows[rowIndex].templates[templateIndex].backgroundImageConfig.fileName = fileName
            rows[rowIndex].templates[templateIndex].backgroundImageConfig.svgContent = svgContent
        } else {
            oldFile = rows[rowIndex].backgroundImageConfig.fileName
            rows[rowIndex].backgroundImageConfig.fileName = fileName
            rows[rowIndex].backgroundImageConfig.svgContent = svgContent
        }
        cleanupUnreferencedImage(oldFile)
    }

    func persistImageResource(
        _ image: NSImage,
        named fileName: String,
        activeId: UUID,
        action: String
    ) -> NSImage? {
        guard let pngData = ExportService.pngData(from: image) else {
            saveError = String(localized: "Failed to \(action): could not encode image.")
            return nil
        }

        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        do {
            try ImageResourceIO.writeData(pngData, url)
        } catch {
            saveError = String(localized: "Failed to \(action): \(error.localizedDescription)")
            return nil
        }

        return Self.editorThumbnail(for: image)
    }

}

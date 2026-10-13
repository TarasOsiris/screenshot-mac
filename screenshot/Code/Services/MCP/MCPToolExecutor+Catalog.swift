#if os(macOS)
import Foundation
import MCP

struct MCPDeviceFrameItem: Encodable {
    let id: String
    let model: String
    let color: String
    let orientation: String
    let category: String
    let is3D: Bool
}

struct MCPLocalePresetItem: Encodable {
    let code: String
    let label: String
}

struct MCPSvgPresetItem: Encodable {
    let id: String
    let name: String
}

struct MCPFontList: Encodable {
    /// Imported into this project; usable only here.
    let imported: [String]
    let system: [String]
}

struct MCPScreenshotSizeItem: Encodable {
    let display: String
    let deviceCategory: String?
    let size: String
    let label: String?
}

struct MCPUndoResult: Encodable {
    let undone: String?
    let redone: String?
    let canUndo: Bool
    let canRedo: Bool
}

extension MCPToolExecutor {

    func listCatalog(_ args: MCPArguments) async throws -> CallTool.Result {
        switch try args.requiredString("kind") {
        case "device_frames":
            let category = try args.enumValue("category", DeviceCategory.self)
            let frames = DeviceFrameCatalog.allFrames
                .filter { category == nil || $0.fallbackCategory == category }
                .map { frame in
                    MCPDeviceFrameItem(
                        id: frame.id,
                        model: frame.modelName,
                        color: frame.colorName,
                        orientation: frame.isLandscape ? "landscape" : "portrait",
                        category: frame.fallbackCategory.rawValue,
                        is3D: frame.isModelBacked
                    )
                }
            return try MCPResultEncoding.result(["device_frames": frames])
        case "svg_presets":
            return try MCPResultEncoding.result(["svg_presets": SvgPresetCatalog.all.map { MCPSvgPresetItem(id: $0.id, name: $0.displayName) }])
        case "fonts":
            let checkout = try await editCheckout(args)
            defer { checkout.dispose() }
            let system = PlatformFonts.familyNameSet
            return try MCPResultEncoding.result(MCPFontList(
                imported: checkout.availableFontFamilySet.subtracting(system).sorted(),
                system: system.sorted()
            ))
        case "locale_presets":
            return try MCPResultEncoding.result(["locale_presets": LocalePresets.all.map { MCPLocalePresetItem(code: $0.code, label: $0.label) }])
        case "screenshot_sizes":
            let sizes = displayCategories.flatMap { category in
                category.sizes.map { size in
                    MCPScreenshotSizeItem(
                        display: category.name,
                        deviceCategory: category.deviceCategory?.rawValue,
                        size: "\(Int(size.width))x\(Int(size.height))",
                        label: size.subtitle
                    )
                }
            }
            return try MCPResultEncoding.result(["screenshot_sizes": sizes])
        case let kind:
            throw MCPToolError.invalidArgument("kind", "unsupported value: \(kind)")
        }
    }

    func undo(_ args: MCPArguments, redo: Bool) throws -> CallTool.Result {
        if let id = try args.optionalUUID("project_id"), id != state.activeProjectId {
            throw MCPToolError.expected("Only the project open in the app has an undo history; edits to other projects are saved directly")
        }
        guard state.activeProjectId != nil else {
            throw MCPToolError.expected("No project is open in the app")
        }
        let name: String
        if redo {
            guard state.canRedoDocumentAction else { throw MCPToolError.expected("Nothing to redo") }
            name = state.undoManager?.redoActionName ?? ""
            state.redoDocumentAction()
        } else {
            guard state.canUndoDocumentAction else { throw MCPToolError.expected("Nothing to undo") }
            state.commitAllPendingEdits()
            name = state.undoManager?.undoActionName ?? ""
            state.undoDocumentAction()
        }
        return try MCPResultEncoding.result(MCPUndoResult(
            undone: redo ? nil : name,
            redone: redo ? name : nil,
            canUndo: state.canUndoDocumentAction,
            canRedo: state.canRedoDocumentAction
        ))
    }
}
#endif

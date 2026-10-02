#if os(macOS)
import Foundation
import MCP
import SwiftUI

extension MCPToolExecutor {

    func addShape(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let row = state.rows[rowIndex]
        guard let type = try args.enumValue("type", ShapeType.self) else {
            throw MCPToolError.missingArgument("type")
        }
        try validateShapeArgs(args)

        let templateIndex = min(max(args.int("template_index") ?? 0, 0), max(row.templates.count - 1, 0))
        let centerX = row.templateCenterX(at: templateIndex)
        let centerY = row.templateHeight / 2

        state.selectRow(row.id)
        let existingIds = Set(row.shapes.map(\.id))

        switch type {
        case .image:
            let path = try args.requiredString("image_path")
            guard let image = NSImage(contentsOfFile: path) else {
                throw MCPToolError.invalidArgument("image_path", "could not load an image from \(path)")
            }
            state.addImageShape(image: image, centerX: centerX, centerY: centerY, source: .mcp)

        case .svg:
            let presetName = try args.requiredString("svg_preset")
            guard let preset = SvgPresetCatalog.all.first(where: { $0.id.caseInsensitiveCompare(presetName) == .orderedSame }) else {
                let known = SvgPresetCatalog.all.map(\.id).joined(separator: ", ")
                throw MCPToolError.invalidArgument("svg_preset", "unknown preset \(presetName); available: \(known)")
            }
            let intrinsic = SvgHelper.parseViewBoxSize(preset.sanitizedContent) ?? CGSize(width: 400, height: 400)
            let size = SvgHelper.scaledSize(intrinsic, maxDim: row.svgMaxDimension)
            state.addShape(CanvasShapeModel.defaultSvg(centerX: centerX, centerY: centerY, svgContent: preset.sanitizedContent, size: size))

        case .device:
            var shape: CanvasShapeModel
            if let category = try args.enumValue("device_category", DeviceCategory.self) {
                shape = CanvasShapeModel.defaultDevice(centerX: centerX, centerY: centerY, templateHeight: row.templateHeight, category: category)
            } else {
                shape = CanvasShapeModel.defaultDeviceFromRow(row, centerX: centerX, centerY: centerY)
            }
            if let frameId = args.string("device_frame_id") {
                shape.deviceFrameId = frameId
            }
            state.addShape(shape)

        default:
            guard let shape = CanvasShapeModel.defaultShape(for: type, row: row, centerX: centerX, centerY: centerY) else {
                throw MCPToolError.invalidArgument("type", "cannot create \(type.rawValue) via add_shape")
            }
            state.addShape(shape)
        }

        guard let newShape = state.rows[rowIndex].shapes.first(where: { !existingIds.contains($0.id) }) else {
            throw MCPToolError.failed("Shape was not added")
        }

        var patch = newShape
        try applyCommonPatch(&patch, args: args)
        if let text = args.string("text") {
            patch.text = text
        }
        if patch != newShape {
            state.updateShape(patch, forLocaleCode: state.localeState.baseLocaleCode)
        }
        return try shapeResult(rowIndex: rowIndex, shapeId: newShape.id)
    }

    func updateShape(_ args: MCPArguments) throws -> CallTool.Result {
        let location = try requireShapeLocation(args)
        try validateShapeArgs(args)
        let textRuns = args.objectArray("text_runs")
        let clearsFormatting = args.bool("clear_text_formatting") == true
        if textRuns != nil || clearsFormatting {
            try validateTextFormattingArgs(args, shape: state.rows[location.rowIndex].shapes[location.shapeIndex])
        }

        if let text = args.string("text") {
            state.updateBaseText(shapeId: location.shapeId, text: text)
            state.finishBaseTextEditIfNeeded()
        }

        // The shapes array holds the base-locale model; patch and commit against the base
        // explicitly so agent edits never land in whichever locale the UI happens to view.
        let base = state.rows[location.rowIndex].shapes[location.shapeIndex]
        var patch = base
        try applyCommonPatch(&patch, args: args)
        try applyShapePatch(&patch, args: args)
        if patch != base {
            state.updateShape(patch, forLocaleCode: state.localeState.baseLocaleCode)
        }

        // After the patch, so runs inherit any shape-level style set in the same call.
        let styled = state.rows[location.rowIndex].shapes[location.shapeIndex]
        if let textRuns {
            let encoded = try MCPRichText.encode(textRuns, onto: styled, availableFontFamilies: state.availableFontFamilySet)
            state.commitInlineText(shapeId: location.shapeId, text: encoded.text, richText: encoded.richText, forLocaleCode: state.localeState.baseLocaleCode)
        } else if clearsFormatting, styled.richText != nil {
            state.commitInlineText(shapeId: location.shapeId, text: styled.text ?? "", richText: nil, forLocaleCode: state.localeState.baseLocaleCode)
        }

        switch args.string("z_order") {
        case "front": state.bringShapeToFront(location.shapeId)
        case "back": state.sendShapeToBack(location.shapeId)
        default: break
        }

        return try shapeResult(rowIndex: location.rowIndex, shapeId: location.shapeId)
    }

    /// All throwing argument parses up front, so a bad argument can't leave a tool call
    /// half-applied (e.g. add_shape inserting a shape and then failing font validation).
    private func validateShapeArgs(_ args: MCPArguments) throws {
        _ = try args.color("color")
        _ = try args.color("outline_color")
        _ = try args.enumValue("text_align", TextAlign.self)
        _ = try args.enumValue("device_category", DeviceCategory.self)
        try validateFontName(args)
    }

    func validateTextFormattingArgs(_ args: MCPArguments, shape: CanvasShapeModel) throws {
        guard shape.type == .text else {
            throw MCPToolError.invalidArgument("shape_id", "not a text shape")
        }
        guard !(args.has("text_runs") && args.has("text")) else {
            throw MCPToolError.invalidArgument("text_runs", "pass either text or text_runs, not both")
        }
        if let runs = args.objectArray("text_runs") {
            try MCPRichText.validate(runs, availableFontFamilies: state.availableFontFamilySet)
        }
    }

    private func validateFontName(_ args: MCPArguments) throws {
        guard let fontName = args.string("font_name") else { return }
        guard state.availableFontFamilySet.contains(fontName) else {
            let custom = state.customFaces.map(\.displayName).joined(separator: ", ")
            let hint = custom.isEmpty ? "no custom fonts are imported in this project" : "imported custom fonts: \(custom)"
            throw MCPToolError.invalidArgument("font_name", "font \(fontName) is not available — it would silently render as the system font. Use a system font family or import the font into this project first (\(hint))")
        }
    }

    struct DeleteShapeResult: Encodable {
        let deletedShapeId: String
        let remainingShapes: Int
    }

    func deleteShape(_ args: MCPArguments) throws -> CallTool.Result {
        let location = try requireShapeLocation(args)
        state.deleteShape(location.shapeId)
        return try MCPResultEncoding.result(DeleteShapeResult(
            deletedShapeId: location.shapeId.uuidString,
            remainingShapes: state.rows[location.rowIndex].shapes.count
        ))
    }

    /// Fields shared by add_shape and update_shape.
    private func applyCommonPatch(_ shape: inout CanvasShapeModel, args: MCPArguments) throws {
        if let x = args.double("x") { shape.x = x }
        if let y = args.double("y") { shape.y = y }
        if let width = args.double("width") { shape.width = width }
        if let height = args.double("height") { shape.height = height }
        if let color = try args.color("color"), color != shape.colorData {
            shape.colorData = color
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .color)
        }
        if let fontSize = args.double("font_size").map({ CGFloat($0) }), fontSize != shape.fontSize {
            shape.fontSize = fontSize
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .fontSize)
        }
        if let fontName = args.string("font_name"), fontName != shape.fontName {
            try validateFontName(args)
            shape.fontName = fontName
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .fontName)
        }
        if let fontWeight = args.int("font_weight"), fontWeight != shape.fontWeight {
            RichTextUtils.applyFontWeightUpdate(to: &shape, weight: fontWeight)
        }
    }

    /// Fields only meaningful on update_shape.
    private func applyShapePatch(_ shape: inout CanvasShapeModel, args: MCPArguments) throws {
        if let rotation = args.double("rotation") { shape.rotation = rotation }
        if let opacity = args.double("opacity") { shape.opacity = opacity }
        if let radius = args.double("border_radius") { shape.borderRadius = radius }
        if let align = try args.enumValue("text_align", TextAlign.self) {
            shape.textAlign = align
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .alignment)
        }
        if let spacing = args.double("letter_spacing") {
            shape.letterSpacing = spacing
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .letterSpacing)
        }
        if let spacing = args.double("line_spacing") {
            shape.lineSpacing = spacing
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .lineHeight)
        }
        if let color = try args.color("outline_color") { shape.outlineColorData = color }
        if let width = args.double("outline_width") {
            shape.outlineWidth = width
            if width <= 0 {
                shape.outlineWidth = nil
                shape.outlineColorData = nil
            }
        }
        if let category = try args.enumValue("device_category", DeviceCategory.self) {
            shape.deviceCategory = category
            shape.deviceFrameId = nil
        }
        if let frameId = args.string("device_frame_id") { shape.deviceFrameId = frameId }
        if let points = args.int("star_points") { shape.starPointCount = points }
        if let clip = args.bool("clip_to_template") { shape.clipToTemplate = clip }
        if let shrink = args.bool("shrink_to_fit") { shape.shrinkToFit = shrink }
        if let gradient = try args.object("fill_gradient").map(Self.parseGradient) {
            shape.fillGradientConfig = gradient
            shape.fillStyle = .gradient
        }
        if let style = args.string("fill_style") {
            shape.fillStyle = style == "gradient" ? .gradient : nil
            if style == "gradient" && shape.fillGradientConfig == nil { shape.fillGradientConfig = GradientConfig() }
        }
        if let locked = args.bool("locked") { shape.isLocked = locked }
    }
}
#endif

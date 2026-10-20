#if os(macOS)
import AppKit
import Foundation
import MCP

extension MCPToolExecutor {

    func addShape(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let row = document.rows[rowIndex]
        guard let type = try args.enumValue("type", ShapeType.self) else {
            throw MCPToolError.missingArgument("type")
        }
        try validateShapeArgs(args, fonts: context.availableFontFamilies)

        let templateIndex = min(max(args.int("template_index") ?? 0, 0), max(row.templates.count - 1, 0))
        let centerX = row.templateCenterX(at: templateIndex)
        let centerY = row.templateHeight / 2

        var shape: CanvasShapeModel
        switch type {
        case .image:
            let path = try args.requiredString("image_path")
            guard let image = NSImage(contentsOfFile: path) else {
                throw MCPToolError.invalidArgument("image_path", "could not load an image from \(path). \(MCPToolCatalog.screenshotStagingHint)")
            }
            shape = DocumentEditing.makeImageShape(image: image, row: row, centerX: centerX, centerY: centerY)
            let fileName = DocumentEditing.screenshotImageFileName(for: shape.id, localeCode: nil)
            _ = DocumentEditing.pointShape(&shape, at: fileName, imageSize: image.size, localeCode: nil, localeState: &document.localeState)
            context.staged.append(StagedImageWrite(fileName: fileName, source: .file(URL(fileURLWithPath: path))))
            let device = shape.deviceCategory
            context.afterCommit.append { [state] in state.captureImport(count: 1, source: .mcp, device: device) }

        case .svg:
            let presetName = try args.requiredString("svg_preset")
            guard let preset = SvgPresetCatalog.all.first(where: { $0.id.caseInsensitiveCompare(presetName) == .orderedSame }) else {
                let known = SvgPresetCatalog.all.map(\.id).joined(separator: ", ")
                throw MCPToolError.invalidArgument("svg_preset", "unknown preset \(presetName); available: \(known)")
            }
            let intrinsic = SvgHelper.parseViewBoxSize(preset.sanitizedContent) ?? CGSize(width: 400, height: 400)
            let size = SvgHelper.scaledSize(intrinsic, maxDim: row.svgMaxDimension)
            shape = CanvasShapeModel.defaultSvg(centerX: centerX, centerY: centerY, svgContent: preset.sanitizedContent, size: size)

        case .device:
            if let category = try args.enumValue("device_category", DeviceCategory.self) {
                shape = CanvasShapeModel.defaultDevice(centerX: centerX, centerY: centerY, templateHeight: row.templateHeight, category: category)
            } else {
                shape = CanvasShapeModel.defaultDeviceFromRow(row, centerX: centerX, centerY: centerY)
            }
            if let frame = try deviceFrame(args) {
                shape.selectRealFrame(frame)
            }

        default:
            guard let made = CanvasShapeModel.defaultShape(for: type, row: row, centerX: centerX, centerY: centerY) else {
                throw MCPToolError.invalidArgument("type", "cannot create \(type.rawValue) via add_shape")
            }
            shape = made
        }

        _ = try applyPatch(&shape, args: args, fonts: context.availableFontFamilies)
        document.rows[rowIndex].shapes.append(shape)
        return .shape(shape.id)
    }

    func updateShape(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let location = try requireShapeLocation(args, in: document)
        try validateShapeArgs(args, fonts: context.availableFontFamilies)
        // The shapes array holds the base-locale model; patch and commit against the base
        // explicitly so agent edits never land in whichever locale the UI happens to view.
        let base = document.rows[location.rowIndex].shapes[location.shapeIndex]
        var patch = base
        let (restyled, clearsFormatting) = try applyPatch(&patch, args: args, fonts: context.availableFontFamilies)

        if patch != base {
            DocumentEditing.commitShapeEdit(
                patch, at: (location.rowIndex, location.shapeIndex), forLocaleCode: document.localeState.baseLocaleCode,
                rows: &document.rows, localeState: &document.localeState
            )
        }
        DocumentEditing.restyleTranslations(of: patch, properties: restyled, clearingFormatting: clearsFormatting, localeState: &document.localeState)
        if let order = args.string("z_order") {
            DocumentEditing.reorderShape(at: (location.rowIndex, location.shapeIndex), toFront: order == "front", rows: &document.rows)
        }
        return .shape(location.shapeId)
    }

    /// Checks what the schema can't: colors, a known frame, a font this project can render.
    private func validateShapeArgs(_ args: MCPArguments, fonts: Set<String>) throws {
        _ = try args.color("color")
        _ = try args.color("outline_color")
        _ = try args.enumValue("text_align", TextAlign.self)
        _ = try args.enumValue("device_category", DeviceCategory.self)
        _ = try deviceFrame(args)
        try validateFontName(args, fonts: fonts)
    }

    func validateTextFormattingArgs(_ args: MCPArguments, shape: CanvasShapeModel, fonts: Set<String>) throws {
        guard shape.type == .text else {
            throw MCPToolError.invalidArgument("shape_id", "not a text shape")
        }
        guard !(args.has("text_runs") && args.has("text")) else {
            throw MCPToolError.invalidArgument("text_runs", "pass either text or text_runs, not both")
        }
        if let runs = try args.strictObjectArray("text_runs") {
            try MCPRichText.validate(runs, availableFontFamilies: fonts)
        }
    }

    /// Mirrors the properties bar: the legacy point spacing is folded into a multiple, because the
    /// renderer ignores `lineSpacing` once `lineHeightMultiple` is set.
    private func lineHeightMultiple(_ args: MCPArguments, shape: CanvasShapeModel) -> CGFloat? {
        if let multiple = args.double("line_height") {
            return TextLayoutStyle.clampLineHeightMultiple(CGFloat(multiple))
        }
        guard let spacing = args.double("line_spacing") else { return nil }
        let font = NSFont.systemFont(
            ofSize: shape.fontSize ?? CanvasShapeModel.defaultFontSize,
            weight: CSSFontWeight(css: shape.fontWeight ?? 400).platform
        )
        return TextLayoutStyle.effectiveLineHeightMultiple(lineHeightMultiple: nil, legacyLineSpacing: CGFloat(spacing), font: font)
    }

    func deviceFrame(_ args: MCPArguments) throws -> DeviceFrame? {
        guard let id = args.string("device_frame_id") else { return nil }
        guard let frame = DeviceFrameCatalog.frame(for: id) else {
            throw MCPToolError.invalidArgument("device_frame_id", "unknown device frame \(id)")
        }
        return frame
    }

    private func validateFontName(_ args: MCPArguments, fonts: Set<String>) throws {
        guard let fontName = args.string("font_name") else { return }
        guard fonts.contains(fontName) else {
            throw MCPToolError.invalidArgument("font_name", "font \(fontName) is not available — it would silently render as the system font. Use a system font family or one imported into this project (list_catalog kind fonts lists them)")
        }
    }

    func deleteShape(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let location = try requireShapeLocation(args, in: document)
        let rowId = document.rows[location.rowIndex].id
        guard DocumentEditing.deleteShape(at: (location.rowIndex, location.shapeIndex), rows: &document.rows, localeState: &document.localeState) != nil else {
            throw MCPToolError.expected("The shape is locked — unlock it with update_shape locked: false first")
        }
        return .deletedShape(location.shapeId, rowId: rowId)
    }

    /// Every shape field `args` names, for add_shape and update_shape alike. Returns the text-style
    /// properties that changed (the shape's rich text is already synced to them) and whether formatting was cleared.
    private func applyPatch(
        _ shape: inout CanvasShapeModel,
        args: MCPArguments,
        fonts: Set<String>
    ) throws -> (restyled: [RichTextUtils.ShapeStyleProperty], clearsFormatting: Bool) {
        let textRuns = try args.strictObjectArray("text_runs")
        let clearsFormatting = args.bool("clear_text_formatting") == true
        if textRuns != nil || clearsFormatting {
            try validateTextFormattingArgs(args, shape: shape, fonts: fonts)
        }
        var restyled: [RichTextUtils.ShapeStyleProperty] = []
        try applyGeometryAndStyle(&shape, args: args, restyled: &restyled)
        try applyEffects(&shape, args: args)
        if let text = args.string("text") {
            shape.text = text
        }
        // Encoded against the patched shape, so runs inherit shape-level style set in the same call.
        if let textRuns {
            let encoded = try MCPRichText.encode(textRuns, onto: shape, availableFontFamilies: fonts)
            shape.text = encoded.text
            shape.richText = encoded.richText
        } else if clearsFormatting {
            shape.richText = nil
        }
        if shape.text?.isEmpty != false {
            shape.richText = nil
        }
        return (restyled, clearsFormatting)
    }

    private func applyGeometryAndStyle(_ shape: inout CanvasShapeModel, args: MCPArguments, restyled: inout [RichTextUtils.ShapeStyleProperty]) throws {
        // First, so a frame switched in the same call takes the requested position and size in its own aspect.
        if let category = try args.enumValue("device_category", DeviceCategory.self), category != shape.deviceCategory {
            shape.selectAbstractDevice(category)
        }
        if let frame = try deviceFrame(args) { shape.selectRealFrame(frame) }
        if let x = args.double("x") { shape.x = x }
        if let y = args.double("y") { shape.y = y }
        shape.applyManualSize(width: args.cgFloat("width"), height: args.cgFloat("height"))
        if let rotation = args.double("rotation") { shape.rotation = rotation }
        if let opacity = args.double("opacity") { shape.opacity = opacity }
        if let radius = args.double("border_radius") { shape.borderRadius = radius }
        if let color = try args.color("color"), color != shape.colorData {
            RichTextUtils.applyColorUpdate(to: &shape, color: color)
            restyled.append(.color)
        }
        if let fontSize = args.cgFloat("font_size"), fontSize != shape.fontSize {
            shape.fontSize = fontSize
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .fontSize)
            restyled.append(.fontSize)
        }
        if let fontName = args.string("font_name"), fontName != shape.fontName {
            shape.fontName = fontName
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .fontName)
            restyled.append(.fontName)
        }
        if let fontWeight = args.int("font_weight"), fontWeight != shape.fontWeight {
            RichTextUtils.applyFontWeightUpdate(to: &shape, weight: fontWeight)
            restyled.append(.fontWeight)
        }
        if let italic = args.bool("italic"), italic != (shape.italic ?? false) {
            RichTextUtils.applyItalicUpdate(to: &shape, italic: italic)
            restyled.append(.italic)
        }
        if let uppercase = args.bool("uppercase") { shape.uppercase = uppercase }
        if let align = try args.enumValue("text_align", TextAlign.self), align != shape.textAlign {
            shape.textAlign = align
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .alignment)
            restyled.append(.alignment)
        }
        if let align = try args.enumValue("vertical_align", TextVerticalAlign.self) { shape.textVerticalAlign = align }
        if let spacing = args.cgFloat("letter_spacing"), spacing != shape.letterSpacing {
            shape.letterSpacing = spacing
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .letterSpacing)
            restyled.append(.letterSpacing)
        }
        if let multiple = lineHeightMultiple(args, shape: shape),
           multiple != shape.lineHeightMultiple || shape.lineSpacing != nil {
            shape.lineHeightMultiple = multiple
            shape.lineSpacing = nil
            RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .lineHeight)
            restyled.append(.lineHeight)
        }
        if let points = args.int("star_points") { shape.starPointCount = points }
        if let clip = args.bool("clip_to_template") { shape.clipToTemplate = clip }
        if let shrink = args.bool("shrink_to_fit") { shape.shrinkToFit = shrink }
        if let locked = args.bool("locked") { shape.isLocked = locked }
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Outline, fill, shadow and the text plate.
    private func applyEffects(_ shape: inout CanvasShapeModel, args: MCPArguments) throws {
        if let color = try args.color("outline_color") { shape.outlineColorData = color }
        if let width = args.double("outline_width") {
            shape.outlineWidth = width > 0 ? width : nil
            if width <= 0 { shape.outlineColorData = nil }
        }
        if let gradient = try args.object("fill_gradient").map(Self.parseGradient) {
            shape.fillGradientConfig = gradient
            shape.fillStyle = .gradient
        }
        if let style = args.string("fill_style") {
            shape.fillStyle = style == "gradient" ? .gradient : nil
            if style == "gradient" && shape.fillGradientConfig == nil { shape.fillGradientConfig = GradientConfig() }
        }
        if args.isNull("shadow") {
            shape.shadow = nil
        } else if let shadow = args.object("shadow") {
            var config = shape.shadow ?? ShadowConfig()
            config.enabled = true
            if let color = try shadow.color("color") { config.colorData = color }
            if let opacity = shadow.double("opacity") { config.opacity = clamp(opacity, ShadowConfig.opacityRange) }
            if let radius = shadow.double("radius") { config.radius = CGFloat(clamp(radius, ShadowConfig.radiusRange)) }
            if let x = shadow.double("offset_x") { config.offsetX = CGFloat(clamp(x, ShadowConfig.offsetRange)) }
            if let y = shadow.double("offset_y") { config.offsetY = CGFloat(clamp(y, ShadowConfig.offsetRange)) }
            shape.shadow = config
        }
        if args.isNull("text_background") {
            shape.textBackgroundPayload = CanvasShapeModel.TextBackgroundPayload()
        } else if let plate = args.object("text_background") {
            shape.textBackgroundColorData = try plate.color("color") ?? shape.textBackgroundColorData
                ?? CodableColor(CanvasShapeModel.defaultTextBackgroundColor)
            if let opacity = plate.double("opacity") { shape.textBackgroundOpacity = min(max(opacity, 0), 1) }
            if let radius = plate.double("radius") { shape.textBackgroundCornerRadius = radius }
            if let padding = plate.double("padding") { shape.textBackgroundPadding = padding }
            if let color = try plate.color("outline_color") { shape.textBackgroundOutlineColorData = color }
            if let width = plate.double("outline_width") {
                shape.textBackgroundOutlineWidth = width > 0 ? width : nil
                if width <= 0 { shape.textBackgroundOutlineColorData = nil }
            }
        }
    }
}
#endif

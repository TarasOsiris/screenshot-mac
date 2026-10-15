#if os(macOS)
import AppKit
import Foundation
import MCP

/// What update_row and update_template share: one background, row-wide or per column.
protocol MCPBackgroundTarget {
    var backgroundStyle: BackgroundStyle { get set }
    var mcpBackgroundColor: CodableColor { get set }
    var gradientConfig: GradientConfig { get set }
    var backgroundImageConfig: BackgroundImageConfig { get set }
    var backgroundBlur: Double { get set }
}

extension ScreenshotRow: MCPBackgroundTarget {
    var mcpBackgroundColor: CodableColor {
        get { backgroundColorData }
        set { backgroundColorData = newValue }
    }
}

extension ScreenshotTemplate: MCPBackgroundTarget {
    var mcpBackgroundColor: CodableColor {
        get { backgroundColor }
        set { backgroundColor = newValue }
    }
}

extension MCPToolExecutor {

    static let backgroundKeys = [
        "background_color", "background_gradient", "background_image_path", "background_image_locale",
        "background_fill_mode", "background_image_opacity", "background_blur",
    ]

    func applyBackground<Target: MCPBackgroundTarget>(
        _ args: MCPArguments,
        to target: inout Target,
        localeState: LocaleState,
        context: inout MCPEditContext
    ) throws {
        if let color = try args.color("background_color") {
            target.backgroundStyle = .color
            target.mcpBackgroundColor = color
        }
        if let gradient = try args.object("background_gradient").map(Self.parseGradient) {
            target.backgroundStyle = .gradient
            target.gradientConfig = gradient
        }
        if let path = args.string("background_image_path") {
            try requireImage(at: path, key: "background_image_path")
            let fileName = "bg-\(UUID().uuidString).png"
            _ = DocumentEditing.setBackgroundImage(
                BackgroundImageSource(fileName: fileName, svgContent: nil),
                on: &target.backgroundImageConfig,
                localeCode: try imageLocale(args, key: "background_image_locale", localeState: localeState)
            )
            target.backgroundStyle = .image
            context.staged.append(StagedImageWrite(fileName: fileName, source: .file(URL(fileURLWithPath: path))))
        } else if args.has("background_image_locale") {
            throw MCPToolError.invalidArgument("background_image_locale", "only meaningful with background_image_path")
        }
        if let mode = try args.enumValue("background_fill_mode", ImageFillMode.self) {
            target.backgroundImageConfig.fillMode = mode
        }
        if let opacity = args.double("background_image_opacity") {
            target.backgroundImageConfig.opacity = min(max(opacity, 0), 1)
        }
        if let blur = args.double("background_blur") {
            target.backgroundBlur = max(blur, 0)
        }
    }

    /// The locale an image goes to: nil for the base image, which every other language falls back to.
    func imageLocale(_ args: MCPArguments, key: String, localeState: LocaleState) throws -> String? {
        guard let code = args.string(key), code != localeState.baseLocaleCode else { return nil }
        guard localeState.hasLocale(code) else { throw MCPToolError.notFound("Locale \(code)") }
        return code
    }

    func requireImage(at path: String, key: String) throws {
        guard NSImage(contentsOfFile: path) != nil else {
            throw MCPToolError.invalidArgument(key, "could not load an image from \(path). \(MCPToolCatalog.screenshotStagingHint)")
        }
    }

    func updateTemplate(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let templateIndex = try templateIndex(of: try args.uuid("template_id"), in: document.rows[rowIndex])
        let localeState = document.localeState
        try applyBackground(args, to: &document.rows[rowIndex].templates[templateIndex], localeState: localeState, context: &context)
        let setsBackground = Self.backgroundKeys.contains(where: args.has)
        document.rows[rowIndex].templates[templateIndex].overrideBackground = args.bool("override_background") ?? (setsBackground ? true : document.rows[rowIndex].templates[templateIndex].overrideBackground)
        return .row(document.rows[rowIndex].id)
    }

    func duplicateShape(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let location = try requireShapeLocation(args, in: document)
        let shape = document.rows[location.rowIndex].shapes[location.shapeIndex]
        if let columns = args.string("to_columns") {
            let direction: DuplicateDirection = columns == "left" ? .left : columns == "right" ? .right : .all
            DocumentEditing.duplicateShapesToTemplates(
                [shape], direction: direction, in: &document.rows[location.rowIndex],
                localeState: &document.localeState, resources: context.resources
            )
            return .row(document.rows[location.rowIndex].id)
        }
        let copy = DocumentEditing.duplicateShape(
            shape,
            offsetX: args.double("offset_x").map { CGFloat($0) } ?? 50,
            offsetY: args.double("offset_y").map { CGFloat($0) } ?? 50,
            in: &document.rows[location.rowIndex],
            localeState: &document.localeState,
            resources: context.resources
        )
        return .shape(copy.id)
    }

    func duplicateRow(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let label = args.string("label") ?? AppState.defaultDuplicateName(for: document.rows[rowIndex].label)
        guard let copy = DocumentEditing.copyRow(
            at: rowIndex, label: label, rows: &document.rows,
            localeState: &document.localeState, resources: context.resources
        ) else {
            throw MCPToolError.expected("A variant row can't be copied in place — it would be a second row of its size in that variant. Use create_variant.")
        }
        return .row(copy.id)
    }

    func duplicateTemplate(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let index = try templateIndex(of: try args.uuid("template_id"), in: document.rows[rowIndex])
        DocumentEditing.duplicateTemplate(
            at: index, to: index + 1, in: &document.rows[rowIndex],
            localeState: &document.localeState, resources: context.resources
        )
        return .row(document.rows[rowIndex].id)
    }

    func moveTemplate(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let index = try templateIndex(of: try args.uuid("template_id"), in: document.rows[rowIndex])
        guard let destination = args.int("to_index"), document.rows[rowIndex].templates.indices.contains(destination) else {
            throw MCPToolError.invalidArgument("to_index", "row has \(document.rows[rowIndex].templates.count) columns")
        }
        DocumentEditing.moveTemplate(in: &document.rows[rowIndex], from: index, to: destination)
        return .row(document.rows[rowIndex].id)
    }

    func replaceImage(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let location = try requireShapeLocation(args, in: document)
        let shape = document.rows[location.rowIndex].shapes[location.shapeIndex]
        guard shape.type == .device || shape.type == .image else {
            throw MCPToolError.invalidArgument("shape_id", "not a device or image shape")
        }
        let path = try args.requiredString("image_path")
        guard let image = NSImage(contentsOfFile: path) else {
            throw MCPToolError.invalidArgument("image_path", "could not load an image from \(path). \(MCPToolCatalog.screenshotStagingHint)")
        }
        let localeCode = try imageLocale(args, key: "locale", localeState: document.localeState)
        let fileName = DocumentEditing.screenshotImageFileName(for: shape.id, localeCode: localeCode)
        _ = DocumentEditing.pointShape(
            &document.rows[location.rowIndex].shapes[location.shapeIndex], at: fileName,
            imageSize: image.size, localeCode: localeCode, localeState: &document.localeState
        )
        context.staged.append(StagedImageWrite(fileName: fileName, source: .file(URL(fileURLWithPath: path))))
        let device = shape.deviceCategory
        context.afterCommit.append { [state] in state.captureImport(count: 1, source: .mcp, device: device) }
        return .shape(shape.id)
    }

    func setAllDevices(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let frame = try deviceFrame(args)
        let category = try args.enumValue("device_category", DeviceCategory.self)
        guard frame != nil || category != nil else {
            throw MCPToolError.missingArgument("device_frame_id or device_category")
        }
        let rowIndex = args.has("row_id") ? try requireRowIndex(args, in: document) : nil
        var changed = false
        for index in rowIndex.map({ [$0] }) ?? Array(document.rows.indices) {
            changed = DocumentEditing.changeAllDevices(in: &document.rows[index]) { shape in
                if let frame { shape.selectRealFrame(frame) } else if let category { shape.selectAbstractDevice(category) }
            } || changed
        }
        guard changed else {
            throw MCPToolError.expected("No unlocked device frames to change")
        }
        return rowIndex.map { .row(document.rows[$0].id) } ?? .project
    }

    func arrangeShapes(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let ids = Set(try args.uuidArray("shape_ids") ?? [])
        guard let first = ids.first, let rowIndex = document.shapeLocation(for: first)?.rowIndex else {
            throw MCPToolError.missingArgument("shape_ids")
        }
        let row = document.rows[rowIndex]
        guard ids.allSatisfy({ id in row.shapes.contains { $0.id == id } }) else {
            throw MCPToolError.invalidArgument("shape_ids", "every shape must exist and be in the same row")
        }
        let indices = row.shapes.indices.filter { ids.contains(row.shapes[$0].id) && !row.shapes[$0].resolvedIsLocked }
        let action = try args.requiredString("action")
        let alignments: [String: ShapeAlignment] = [
            "align_left": .left, "align_center": .centerH, "align_right": .right,
            "align_top": .top, "align_middle": .centerV, "align_bottom": .bottom,
            "distribute_horizontally": .distributeH, "distribute_vertically": .distributeV,
        ]
        if let alignment = alignments[action] {
            let needed = alignment == .distributeH || alignment == .distributeV ? 3 : 2
            guard indices.count >= needed else {
                throw MCPToolError.invalidArgument("shape_ids", "\(action) needs at least \(needed) unlocked shapes")
            }
            DocumentEditing.align(alignment, shapesAt: indices, in: &document.rows[rowIndex])
        } else {
            let axis: CenterAxis = action.hasSuffix("horizontally") ? .horizontally : action.hasSuffix("vertically") ? .vertically : .both
            for index in indices {
                DocumentEditing.center(shapeAt: index, in: &document.rows[rowIndex], axis: axis)
            }
        }
        return .row(row.id)
    }

    func setBaseLocale(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let code = try args.requiredString("code")
        guard document.localeState.hasLocale(code) else { throw MCPToolError.notFound("Locale \(code)") }
        guard code != document.localeState.baseLocaleCode else { return .locales }
        LocaleService.setBaseLocale(code, rows: &document.rows, state: &document.localeState)
        // The new base points at what were per-language screenshots, which the editor hasn't decoded.
        context.repointsImages = true
        return .locales
    }

    func setLocaleLayout(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let location = try requireShapeLocation(args, in: document)
        let code = try args.requiredString("locale_code")
        guard document.localeState.hasLocale(code) else { throw MCPToolError.notFound("Locale \(code)") }
        guard code != document.localeState.baseLocaleCode else {
            throw MCPToolError.expected("\(code) is the base locale — use update_shape instead")
        }
        if let fontName = args.string("font_name"), !context.availableFontFamilies.contains(fontName) {
            throw MCPToolError.invalidArgument("font_name", "font \(fontName) is not available in this project (list_catalog kind fonts)")
        }
        let base = document.rows[location.rowIndex].shapes[location.shapeIndex]
        if args.bool("reset") == true {
            var merged = LocaleService.mergedOverride(for: base, localeCode: code, localeState: document.localeState)
            let layoutFields: [LocaleOverrideField] = [.positionX, .positionY, .width, .height, .font, .fontSize, .fontWeight, .textAlign]
            for field in layoutFields { field.clear(in: &merged) }
            LocaleService.writeSplitOverride(
                &document.localeState, localeCode: code, shapeId: base.id,
                textKey: base.textTranslationKey, override: merged.isEmpty ? nil : merged
            )
        }
        var resolved = LocaleService.resolveShape(base, localeCode: code, localeState: document.localeState)
        let before = resolved
        if let x = args.double("x") { resolved.x = x }
        if let y = args.double("y") { resolved.y = y }
        if let width = args.double("width") { resolved.width = width }
        if let height = args.double("height") { resolved.height = height }
        if let size = args.double("font_size") { resolved.fontSize = size }
        if let name = args.string("font_name") { resolved.fontName = name }
        if let weight = args.int("font_weight") { resolved.fontWeight = weight }
        if let align = try args.enumValue("text_align", TextAlign.self) { resolved.textAlign = align }
        if resolved != before {
            document.rows[location.rowIndex].shapes[location.shapeIndex] = LocaleService.splitUpdate(
                base: base, updated: resolved, localeState: &document.localeState, forLocaleCode: code
            )
        }
        return .shape(base.id)
    }
}
#endif

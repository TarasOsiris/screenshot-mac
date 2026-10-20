#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    func addRow(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let size = try args.screenshotSize("size")
        let beforeIndex = args.has("before_row_id") ? try requireRowIndex(args, key: "before_row_id", in: document) : nil
        let afterIndex = args.has("after_row_id") ? try requireRowIndex(args, key: "after_row_id", in: document) : nil

        let row = DocumentEditing.newRow(
            inVariant: (beforeIndex ?? afterIndex).flatMap { document.rows[$0].activeVariantId },
            rows: document.rows,
            defaults: AppState.storedNewRowDefaults()
        )
        let index = beforeIndex ?? afterIndex.map { $0 + 1 } ?? document.rows.count
        document.rows.insert(row, at: index)
        if let label = args.string("label") {
            DocumentEditing.setLabel(label, ofRowAt: index, in: &document.rows)
        }
        if let size {
            DocumentEditing.resize(&document.rows[index], width: size.width, height: size.height)
        }
        return .row(row.id)
    }

    func updateRow(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let row = document.rows[rowIndex]

        if args.has("width") || args.has("height") {
            let width = args.double("width").map { CGFloat($0) } ?? row.templateWidth
            let height = args.double("height").map { CGFloat($0) } ?? row.templateHeight
            guard width >= 100, height >= 100 else {
                throw MCPToolError.invalidArgument("width/height", "must be at least 100 pixels")
            }
            DocumentEditing.resize(&document.rows[rowIndex], width: width, height: height)
        }
        if let label = args.string("label") {
            if let source = DocumentEditing.labelSource(of: row, in: document.rows) {
                throw MCPToolError.invalidArgument("label", "this variant row follows the label of row \(source.id.uuidString); rename that row instead")
            }
            DocumentEditing.setLabel(label, ofRowAt: rowIndex, in: &document.rows)
        }
        if let showDevice = args.bool("show_device") {
            document.rows[rowIndex].showDevice = showDevice
        }
        if let device = try rowDevice(args) {
            document.rows[rowIndex].defaultDeviceCategory = device.category
            document.rows[rowIndex].defaultDeviceFrameId = device.frameId
        }
        let localeState = document.localeState
        try applyBackground(args, to: &document.rows[rowIndex], localeState: localeState, context: &context)
        if let exclude = args.bool("exclude_from_upload") {
            document.rows[rowIndex].excludeFromAppStoreConnect = exclude
        }
        if let span = args.bool("span_background") {
            document.rows[rowIndex].spanBackgroundAcrossRow = span
        }
        return .row(row.id)
    }

    /// A row's default device: a frame decides the category, so the two never disagree; a bare category drops the old frame.
    func rowDevice(_ args: MCPArguments) throws -> (category: DeviceCategory, frameId: String?)? {
        let category = try args.enumValue("device_category", DeviceCategory.self)
        if let frame = try deviceFrame(args) { return (frame.fallbackCategory, frame.id) }
        return category.map { ($0, nil) }
    }

    func moveRow(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let rowId = document.rows[rowIndex].id
        let up = try args.requiredString("direction") == "up"
        if let target = DocumentEditing.rowMoveTarget(from: rowIndex, up: up, in: document.rows) {
            document.rows.swapAt(rowIndex, target)
        }
        return .row(rowId)
    }

    func deleteRow(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let rowId = document.rows[try requireRowIndex(args, in: document)].id
        guard DocumentEditing.deleteRows([rowId], rows: &document.rows, localeState: &document.localeState) != nil else {
            throw MCPToolError.expected("Cannot delete the last row of a project")
        }
        return .deletedRow(rowId)
    }

    func addTemplate(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let row = document.rows[rowIndex]
        let insertIndex: Int
        if let beforeId = try args.optionalUUID("before_template_id") {
            insertIndex = try templateIndex(of: beforeId, in: row)
        } else if let afterId = try args.optionalUUID("after_template_id") {
            insertIndex = try templateIndex(of: afterId, in: row) + 1
        } else {
            insertIndex = row.templates.count
        }
        DocumentEditing.insertTemplate(in: &document.rows[rowIndex], at: insertIndex)
        return .row(row.id)
    }

    func removeTemplate(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let row = document.rows[rowIndex]
        let index = try templateIndex(of: try args.uuid("template_id"), in: row)
        guard row.templates.count > 1 else {
            throw MCPToolError.expected("Cannot remove the last template column of a row")
        }
        _ = DocumentEditing.removeTemplate(at: index, fromRowAt: rowIndex, rows: &document.rows, localeState: &document.localeState)
        return .row(row.id)
    }

    func templateIndex(of templateId: UUID, in row: ScreenshotRow) throws -> Int {
        guard let index = row.templates.firstIndex(where: { $0.id == templateId }) else {
            throw MCPToolError.notFound("Template \(templateId.uuidString)")
        }
        return index
    }

    static func parseGradient(_ args: MCPArguments) throws -> GradientConfig {
        guard let stopArgs = args.objectArray("stops"), stopArgs.count >= 2 else {
            throw MCPToolError.invalidArgument("background_gradient", "needs at least 2 stops")
        }
        let stops = try stopArgs.map { stop in
            guard let color = try stop.color("color"), let location = stop.double("location") else {
                throw MCPToolError.invalidArgument("background_gradient", "each stop needs color and location")
            }
            return GradientColorStop(color: color.color, location: location)
        }
        let type = try args.enumValue("type", GradientType.self) ?? .linear
        return GradientConfig(
            stops: stops,
            angle: args.double("angle") ?? 135,
            gradientType: type,
            centerX: args.double("center_x") ?? 0.5,
            centerY: args.double("center_y") ?? 0.5
        )
    }
}
#endif

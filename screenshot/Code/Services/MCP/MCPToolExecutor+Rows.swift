#if DEBUG && os(macOS)
import Foundation
import MCP
import SwiftUI

extension MCPToolExecutor {

    func addRow(_ args: MCPArguments) throws -> CallTool.Result {
        let size = try args.string("size").map { size in
            guard let parsed = parseSizeString(size) else {
                throw MCPToolError.invalidArgument("size", "expected \"WIDTHxHEIGHT\", got \(size)")
            }
            return parsed
        }
        let beforeIndex = args.has("before_row_id") ? try requireRowIndex(args, key: "before_row_id") : nil
        let afterIndex = args.has("after_row_id") ? try requireRowIndex(args, key: "after_row_id") : nil

        let existingIds = Set(state.rows.map(\.id))
        var newIndex: Int?
        // One transaction for the create + label + resize; the nested withUndo calls join it.
        state.withUndo("Add Row") {
            if let beforeIndex {
                state.addRowAbove(state.rows[beforeIndex].id)
            } else if let afterIndex {
                state.addRowBelow(state.rows[afterIndex].id)
            } else {
                state.addRow()
            }
            guard let index = state.rows.firstIndex(where: { !existingIds.contains($0.id) }) else { return }
            newIndex = index
            if let label = args.string("label") {
                state.updateRowLabel(state.rows[index].id, text: label)
            }
            if let size {
                state.resizeRow(at: index, newWidth: size.width, newHeight: size.height)
            }
        }

        guard let newIndex else {
            throw MCPToolError.failed("Row was not added")
        }
        return try rowResult(newIndex)
    }

    func updateRow(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let rowId = state.rows[rowIndex].id

        if let label = args.string("label") {
            state.updateRowLabel(rowId, text: label)
        }

        if args.has("width") || args.has("height") {
            let row = state.rows[rowIndex]
            let width = args.double("width").map { CGFloat($0) } ?? row.templateWidth
            let height = args.double("height").map { CGFloat($0) } ?? row.templateHeight
            guard width >= 100, height >= 100 else {
                throw MCPToolError.invalidArgument("width/height", "must be at least 100 pixels")
            }
            state.resizeRow(at: rowIndex, newWidth: width, newHeight: height)
        }

        let color = try args.color("background_color")
        let gradient = try args.object("background_gradient").map(Self.parseGradient)
        let span = args.bool("span_background")
        if color != nil || gradient != nil || span != nil {
            state.updateRowContinuous(rowId) { row in
                if let color {
                    row.backgroundStyle = .color
                    row.backgroundColorData = color
                }
                if let gradient {
                    row.backgroundStyle = .gradient
                    row.gradientConfig = gradient
                }
                if let span {
                    row.spanBackgroundAcrossRow = span
                }
            }
            state.finishContinuousRowEditIfNeeded()
        }

        if let showDevice = args.bool("show_device"), state.rows[rowIndex].showDevice != showDevice {
            state.toggleShowDevice(for: rowId)
        }

        if args.has("device_category") || args.has("device_frame_id") {
            let row = state.rows[rowIndex]
            let category = try args.enumValue("device_category", DeviceCategory.self) ?? row.defaultDeviceCategory
            let frameId = args.string("device_frame_id") ?? row.defaultDeviceFrameId
            state.setDefaultDevice(for: rowId, category: category, frameId: frameId)
        }

        return try rowResult(rowIndex)
    }

    func moveRow(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let rowId = state.rows[rowIndex].id
        switch try args.requiredString("direction") {
        case "up": state.moveRowUp(rowId)
        case "down": state.moveRowDown(rowId)
        default: throw MCPToolError.invalidArgument("direction", "expected up or down")
        }
        guard let newIndex = state.rowIndex(for: rowId) else {
            throw MCPToolError.notFound("Row \(rowId.uuidString)")
        }
        return try rowResult(newIndex)
    }

    struct DeleteRowResult: Encodable {
        let deletedRowId: String
        let remainingRows: Int
    }

    func deleteRow(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let rowId = state.rows[rowIndex].id
        state.deleteRow(rowId)
        return try MCPResultEncoding.result(DeleteRowResult(
            deletedRowId: rowId.uuidString,
            remainingRows: state.rows.count
        ))
    }

    func addTemplate(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let rowId = state.rows[rowIndex].id

        if let beforeId = try args.optionalUUID("before_template_id") {
            guard state.rows[rowIndex].templates.contains(where: { $0.id == beforeId }) else {
                throw MCPToolError.notFound("Template \(beforeId.uuidString)")
            }
            state.insertTemplateBefore(beforeId, in: rowId)
        } else if let afterId = try args.optionalUUID("after_template_id") {
            guard state.rows[rowIndex].templates.contains(where: { $0.id == afterId }) else {
                throw MCPToolError.notFound("Template \(afterId.uuidString)")
            }
            state.insertTemplateAfter(afterId, in: rowId)
        } else {
            state.addTemplate(to: rowId)
        }
        return try rowResult(rowIndex)
    }

    func removeTemplate(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let templateId = try args.uuid("template_id")
        guard state.rows[rowIndex].templates.contains(where: { $0.id == templateId }) else {
            throw MCPToolError.notFound("Template \(templateId.uuidString)")
        }
        guard state.rows[rowIndex].templates.count > 1 else {
            throw MCPToolError.failed("Cannot remove the last template column of a row")
        }
        state.removeTemplate(templateId, from: state.rows[rowIndex].id)
        return try rowResult(rowIndex)
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

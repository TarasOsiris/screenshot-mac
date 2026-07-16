#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    func addLocale(_ args: MCPArguments) throws -> CallTool.Result {
        let code = try args.requiredString("code")
        guard !state.localeState.locales.contains(where: { $0.code == code }) else {
            throw MCPToolError.failed("Locale \(code) already exists")
        }
        let preset = LocalePresets.all.first { $0.code == code }
        let label = args.string("label") ?? preset?.label ?? code
        state.addLocale(LocaleDefinition(code: code, label: label))
        return try MCPResultEncoding.result(["locales": MCPSnapshotBuilder.locales(state.localeState)])
    }

    func removeLocale(_ args: MCPArguments) throws -> CallTool.Result {
        let code = try args.requiredString("code")
        guard state.localeState.locales.contains(where: { $0.code == code }) else {
            throw MCPToolError.notFound("Locale \(code)")
        }
        guard code != state.localeState.baseLocaleCode else {
            throw MCPToolError.failed("Cannot remove the base locale")
        }
        state.removeLocale(code)
        return try MCPResultEncoding.result(["locales": MCPSnapshotBuilder.locales(state.localeState)])
    }

    func setTranslation(_ args: MCPArguments) throws -> CallTool.Result {
        let location = try requireShapeLocation(args)
        let code = try args.requiredString("locale_code")
        let text = try args.requiredString("text")

        guard state.localeState.locales.contains(where: { $0.code == code }) else {
            throw MCPToolError.notFound("Locale \(code)")
        }
        guard code != state.localeState.baseLocaleCode else {
            throw MCPToolError.failed("\(code) is the base locale — use update_shape's text field instead")
        }
        let shape = state.rows[location.rowIndex].shapes[location.shapeIndex]
        guard shape.type == .text else {
            throw MCPToolError.invalidArgument("shape_id", "not a text shape")
        }

        state.updateTranslationText(shapeId: location.shapeId, localeCode: code, text: text)
        state.finishTranslationEditIfNeeded()
        return try shapeResult(rowIndex: location.rowIndex, shapeId: location.shapeId)
    }
}
#endif

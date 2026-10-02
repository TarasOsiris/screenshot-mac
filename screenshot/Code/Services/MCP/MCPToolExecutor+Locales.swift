#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    func addLocale(_ args: MCPArguments) throws -> CallTool.Result {
        let code = try args.requiredString("code")
        guard !state.localeState.locales.contains(where: { $0.code == code }) else {
            throw MCPToolError.expected("Locale \(code) already exists")
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
            throw MCPToolError.expected("Cannot remove the base locale")
        }
        state.removeLocale(code)
        return try MCPResultEncoding.result(["locales": MCPSnapshotBuilder.locales(state.localeState)])
    }

    func setTranslation(_ args: MCPArguments) throws -> CallTool.Result {
        let location = try requireShapeLocation(args)
        let code = try args.requiredString("locale_code")
        let textRuns = try args.strictObjectArray("text_runs")
        if textRuns == nil { _ = try args.requiredString("text") }

        guard state.localeState.locales.contains(where: { $0.code == code }) else {
            throw MCPToolError.notFound("Locale \(code)")
        }
        guard code != state.localeState.baseLocaleCode else {
            throw MCPToolError.expected("\(code) is the base locale — use update_shape's text field instead")
        }
        let shape = state.rows[location.rowIndex].shapes[location.shapeIndex]
        try validateTextFormattingArgs(args, shape: shape)

        let encoded = try textRuns.map { runs in
            let resolved = LocaleService.resolveShape(shape, localeCode: code, localeState: state.localeState)
            return try MCPRichText.encode(runs, onto: resolved, availableFontFamilies: state.availableFontFamilySet)
        }
        let fits = state.setTranslation(
            shapeId: location.shapeId, localeCode: code,
            text: encoded?.text ?? args.string("text") ?? "", richText: encoded?.richText,
            autoFits: args.bool("auto_fit") ?? true
        )
        let alsoFitted = fits
            .filter { $0.key != location.shapeId && ($0.value.action != .none || $0.value.stillOverflows) }
            .map { MCPAutoFitSnapshot($0.value, shapeId: $0.key) }
            .sorted { $0.shapeId ?? "" < $1.shapeId ?? "" }
        return try MCPResultEncoding.result(MCPSetTranslationResult(
            shape: try shapeSnapshot(rowIndex: location.rowIndex, shapeId: location.shapeId),
            autoFit: fits[location.shapeId].map { MCPAutoFitSnapshot($0) },
            alsoFitted: alsoFitted.isEmpty ? nil : alsoFitted
        ))
    }
}

/// A shape snapshot plus what auto-fit did, flattened so `set_translation` keeps its result shape.
struct MCPSetTranslationResult: Encodable {
    let shape: MCPShapeSnapshot
    let autoFit: MCPAutoFitSnapshot?
    /// Other boxes sharing the translation that the fit changed or couldn't fix.
    let alsoFitted: [MCPAutoFitSnapshot]?

    private enum CodingKeys: String, CodingKey { case autoFit, alsoFitted }

    func encode(to encoder: Encoder) throws {
        try shape.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(autoFit, forKey: .autoFit)
        try container.encodeIfPresent(alsoFitted, forKey: .alsoFitted)
    }
}

struct MCPAutoFitSnapshot: Encodable {
    let shapeId: String?
    let applied: String
    let fontScale: Double
    let addedHeight: Double
    let stillOverflows: Bool

    init(_ result: TextAutoFitResult, shapeId: UUID? = nil) {
        self.shapeId = shapeId?.uuidString
        applied = result.action.rawValue
        fontScale = (Double(result.fontScale) * 100).rounded() / 100
        addedHeight = Double(result.contribution.addedHeight)
        stillOverflows = result.stillOverflows
    }
}
#endif

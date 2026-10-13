#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    func addLocale(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let code = try args.requiredString("code")
        guard !document.localeState.hasLocale(code) else {
            throw MCPToolError.expected("Locale \(code) already exists")
        }
        let preset = LocalePresets.all.first { $0.code == code }
        let label = args.string("label") ?? preset?.label ?? code
        LocaleService.addLocale(&document.localeState, locale: LocaleDefinition(code: code, label: label))
        // Count, not code: which languages a user targets says what they are building.
        let count = document.localeState.locales.count
        context.afterCommit.append { AnalyticsService.capture(.localeAdded, [.localeCount: count]) }
        return .locales
    }

    func removeLocale(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let code = try args.requiredString("code")
        guard document.localeState.hasLocale(code) else {
            throw MCPToolError.notFound("Locale \(code)")
        }
        guard code != document.localeState.baseLocaleCode else {
            throw MCPToolError.expected("Cannot remove the base locale")
        }
        _ = DocumentEditing.removeLocale(code, rows: &document.rows, localeState: &document.localeState)
        return .locales
    }

    func setTranslation(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let location = try requireShapeLocation(args, in: document)
        let code = try args.requiredString("locale_code")
        let textRuns = try args.strictObjectArray("text_runs")
        if textRuns == nil { _ = try args.requiredString("text") }

        guard document.localeState.hasLocale(code) else {
            throw MCPToolError.notFound("Locale \(code)")
        }
        guard code != document.localeState.baseLocaleCode else {
            throw MCPToolError.expected("\(code) is the base locale — use update_shape's text field instead")
        }
        let shape = document.rows[location.rowIndex].shapes[location.shapeIndex]
        try validateTextFormattingArgs(args, shape: shape, fonts: context.availableFontFamilies)

        let encoded = try textRuns.map { runs in
            let resolved = LocaleService.resolveShape(shape, localeCode: code, localeState: document.localeState)
            return try MCPRichText.encode(runs, onto: resolved, availableFontFamilies: context.availableFontFamilies)
        }
        let fits = DocumentEditing.setTranslation(
            textKey: shape.textTranslationKey, localeCode: code,
            text: encoded?.text ?? args.string("text") ?? "", richText: encoded?.richText,
            autoFits: args.bool("auto_fit") ?? true,
            rows: document.rows, localeState: &document.localeState,
            availableFontFamilies: context.availableFontFamilies
        )
        return .translation(shapeId: location.shapeId, fits: fits)
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

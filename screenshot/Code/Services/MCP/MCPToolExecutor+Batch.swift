#if os(macOS)
import Foundation
import MCP

struct MCPBatchResult: Encodable {
    let results: [Value]
    /// Images the batch points at that could not be written; their shapes show empty.
    let imageWriteFailures: [String]?
}

struct MCPBatchTranslationRecord: Encodable {
    let shapeId: String
    let autoFit: MCPAutoFitSnapshot?
}

struct MCPBatchImportRecord: Encodable {
    let rowId: String
    let imported: Int
    let locale: String
    let failures: [String]
}

extension MCPEditResult {
    /// The id a later batch operation reaches with "$N".
    var producedId: UUID? {
        switch self {
        case .row(let id), .shape(let id): id
        case .translation(let shapeId, _): shapeId
        case .imported(let rowId, _, _, _): rowId
        case .locales, .variants, .project, .deletedRow, .deletedShape: nil
        }
    }
}

extension MCPToolExecutor {

    func batch(_ args: MCPArguments) async throws -> CallTool.Result {
        guard let operations = try args.strictObjectArray("operations"), !operations.isEmpty else {
            throw MCPToolError.missingArgument("operations")
        }
        let parsed = try operations.enumerated().map { index, operation in
            let name = operation.string("tool") ?? ""
            do {
                guard let tool = MCPToolName(rawValue: name), tool.isAvailable, tool.isEditing else {
                    throw MCPToolError.unknownTool(name)
                }
                let arguments = operation.object("arguments")?.rawValues ?? [:]
                guard arguments["project_id"] == nil else {
                    throw MCPToolError.invalidArgument("project_id", "set project_id on the batch, not on an operation")
                }
                let schema = try MCPToolCatalog.requireInputSchema(for: tool)
                try MCPArgumentValidator.validate(arguments, against: schema)
                return (tool: tool, arguments: arguments, schema: schema)
            } catch let error as MCPToolError {
                throw error.inOperation(index, name)
            }
        }
        return try await runEdits(parsed, actionName: "Batch Edit", args: args)
    }

    func setTranslations(_ args: MCPArguments) async throws -> CallTool.Result {
        guard let entries = try args.strictObjectArray("entries"), !entries.isEmpty else {
            throw MCPToolError.missingArgument("entries")
        }
        return try await runEdits(
            entries.map { (tool: MCPToolName.setTranslation, arguments: $0.rawValues, schema: MCPToolCatalog.inputSchema(for: .setTranslation)) },
            actionName: "Edit Translations",
            args: args
        )
    }

    /// Applies `operations` in order inside one mutation — one undo step, and nothing applied if any throws.
    private func runEdits(
        _ operations: [(tool: MCPToolName, arguments: [String: Value], schema: Value?)],
        actionName: String,
        args: MCPArguments
    ) async throws -> CallTool.Result {
        try await serializingEdits(args) { [self] in
            let checkout = try await editCheckout(args)
            defer { checkout.dispose() }
            var context = MCPEditContext(availableFontFamilies: checkout.availableFontFamilySet, resources: checkout)
            let results = try checkout.mutate(actionName) { document in
                var results: [MCPEditResult] = []
                var producedIds: [UUID?] = []
                for (index, operation) in operations.enumerated() {
                    do {
                        let arguments = try Self.resolvingReferences(in: operation.arguments, to: producedIds)
                        let result = try applyEdit(operation.tool, MCPArguments(arguments, schema: operation.schema), to: &document, context: &context)
                        results.append(result)
                        producedIds.append(result.producedId)
                    } catch let error as MCPToolError {
                        throw error.inOperation(index, operation.tool.rawValue)
                    }
                }
                return results
            }
            let writeFailures = try await land(context, in: checkout)
            return try MCPResultEncoding.result(MCPBatchResult(
                results: try results.map { try record(of: $0, in: checkout) },
                imageWriteFailures: writeFailures.isEmpty ? nil : writeFailures
            ))
        }
    }

    /// Ids and outcomes only: a full snapshot per operation would repeat the same row many times over.
    private func record(of result: MCPEditResult, in checkout: ProjectCheckout) throws -> Value {
        switch result {
        case .row(let id): return ["row_id": .string(id.uuidString)]
        case .shape(let id): return ["shape_id": .string(id.uuidString)]
        case .deletedRow(let id): return ["deleted_row_id": .string(id.uuidString)]
        case .deletedShape(let id, _): return ["deleted_shape_id": .string(id.uuidString)]
        case .translation(let shapeId, let fits):
            return try MCPResultEncoding.value(MCPBatchTranslationRecord(shapeId: shapeId.uuidString, autoFit: fits[shapeId].map { MCPAutoFitSnapshot($0) }))
        case .imported(let rowId, let count, let locale, let failures):
            return try MCPResultEncoding.value(MCPBatchImportRecord(rowId: rowId.uuidString, imported: count, locale: locale, failures: failures))
        case .project:
            return ["applied": true]
        case .locales, .variants:
            return try MCPResultEncoding.value(render(result, in: checkout, writeFailures: []))
        }
    }

    /// Replaces "$N" in id arguments (`row_id`, `shape_ids`, …) with the id operation N produced.
    /// Only id arguments, so a text that happens to read "$5" stays a price.
    static func resolvingReferences(in arguments: [String: Value], to ids: [UUID?]) throws -> [String: Value] {
        func resolve(_ value: Value, key: String) throws -> Value {
            switch value {
            case .string(let string) where string.hasPrefix("$"):
                guard let index = Int(string.dropFirst()) else { return value }
                guard ids.indices.contains(index) else {
                    throw MCPToolError.invalidArgument(key, "\(string) refers to an operation that has not run yet")
                }
                guard let id = ids[index] else {
                    throw MCPToolError.invalidArgument(key, "operation \(index) produced no id to refer to")
                }
                return .string(id.uuidString)
            case .array(let elements):
                return .array(try elements.map { try resolve($0, key: key) })
            default:
                return value
            }
        }
        var resolved = arguments
        for (key, value) in arguments where key.hasSuffix("_id") || key.hasSuffix("_ids") {
            resolved[key] = try resolve(value, key: key)
        }
        return resolved
    }
}
#endif

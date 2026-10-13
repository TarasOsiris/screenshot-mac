#if os(macOS)
import Foundation
import MCP

struct MCPVariantSnapshot: Encodable {
    let id: String?
    let name: String
    let rowIds: [String]
}

struct MCPVariantList: Encodable {
    let variants: [MCPVariantSnapshot]
}

extension MCPToolExecutor {

    func listVariants(_ args: MCPArguments) async throws -> CallTool.Result {
        let checkout = try await editCheckout(args)
        defer { checkout.dispose() }
        return try MCPResultEncoding.result(Self.variantList(checkout.document))
    }

    static func variantList(_ document: ProjectDocument) -> MCPVariantList {
        let rowIds = Dictionary(grouping: document.rows, by: \.variantId).mapValues { $0.map(\.id.uuidString) }
        let original = MCPVariantSnapshot(id: nil, name: "Original", rowIds: rowIds[nil] ?? [])
        let variants = document.variants.map { variant in
            MCPVariantSnapshot(id: variant.id.uuidString, name: variant.name, rowIds: rowIds[variant.id] ?? [])
        }
        return MCPVariantList(variants: [original] + variants)
    }

    func createVariant(_ args: MCPArguments, _ document: inout ProjectDocument, _ context: inout MCPEditContext) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, key: "from_row_id", in: document)
        _ = DocumentEditing.createVariant(
            fromRowAt: rowIndex, name: args.string("name"), variants: &document.variants,
            rows: &document.rows, localeState: &document.localeState, resources: context.resources
        )
        return .variants
    }

    func setRowVariant(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let rowIndex = try requireRowIndex(args, in: document)
        let variantId = try args.optionalUUID("variant_id")
        if let variantId, document.variants.variant(withId: variantId) == nil {
            throw MCPToolError.notFound("Variant \(variantId.uuidString)")
        }
        let row = document.rows[rowIndex]
        if let occupant = DocumentEditing.rowOccupyingSlot(of: row, in: variantId, rows: document.rows) {
            throw MCPToolError.invalidArgument("variant_id", "that variant already has a row of this screenshot size (\(occupant.id.uuidString)); a variant holds one row per size")
        }
        DocumentEditing.setVariant(variantId, ofRowAt: rowIndex, rows: &document.rows)
        return .row(row.id)
    }

    func deleteVariant(_ args: MCPArguments, _ document: inout ProjectDocument) throws -> MCPEditResult {
        let variantId = try args.uuid("variant_id")
        guard document.variants.variant(withId: variantId) != nil else {
            throw MCPToolError.notFound("Variant \(variantId.uuidString)")
        }
        _ = DocumentEditing.deleteVariant(variantId, variants: &document.variants, rows: &document.rows, localeState: &document.localeState)
        return .variants
    }
}
#endif

#if os(macOS)
import Foundation
import MCP

struct MCPVariantSnapshot: Encodable {
    let id: String?
    let name: String
    let rowIds: [String]
}

extension MCPToolExecutor {

    func listVariants() throws -> CallTool.Result {
        let rowIds = Dictionary(grouping: state.rows, by: \.variantId).mapValues { $0.map(\.id.uuidString) }
        let original = MCPVariantSnapshot(id: nil, name: "Original", rowIds: rowIds[nil] ?? [])
        let variants = state.variants.map { variant in
            MCPVariantSnapshot(id: variant.id.uuidString, name: variant.name, rowIds: rowIds[variant.id] ?? [])
        }
        return try MCPResultEncoding.result([original] + variants)
    }

    func createVariant(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args, key: "from_row_id")
        state.createVariant(fromRow: state.rows[rowIndex].id, name: args.string("name"))
        return try listVariants()
    }

    func setRowVariant(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let variantId = try args.optionalUUID("variant_id")
        if let variantId, state.variants.variant(withId: variantId) == nil {
            throw MCPToolError.notFound("Variant \(variantId.uuidString)")
        }
        if let occupant = state.rowOccupyingSlot(of: state.rows[rowIndex], in: variantId) {
            throw MCPToolError.invalidArgument("variant_id", "that variant already has a row of this screenshot size (\(occupant.id.uuidString)); a variant holds one row per size")
        }
        state.setRowVariant(state.rows[rowIndex].id, to: variantId)
        return try rowResult(rowIndex)
    }

    func deleteVariant(_ args: MCPArguments) throws -> CallTool.Result {
        let variantId = try args.uuid("variant_id")
        guard state.variants.variant(withId: variantId) != nil else {
            throw MCPToolError.notFound("Variant \(variantId.uuidString)")
        }
        state.deleteVariant(variantId)
        return try listVariants()
    }
}
#endif

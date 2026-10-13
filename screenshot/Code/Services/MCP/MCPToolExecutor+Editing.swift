#if os(macOS)
import Foundation
import MCP

/// What an editing tool may use and leave behind inside `ProjectCheckout.mutate`, where nothing can be awaited.
@MainActor
struct MCPEditContext {
    let availableFontFamilies: Set<String>
    let resources: ImageResourceCopying
    var staged: [StagedImageWrite] = []
    /// Side effects (analytics) that must not happen for an edit that is rolled back.
    var afterCommit: [@MainActor () -> Void] = []
}

/// An editing tool's answer, rendered against the final document once the edit has landed.
enum MCPEditResult {
    case row(UUID)
    case shape(UUID)
    case locales
    case variants
    case deletedRow(UUID)
    case deletedShape(UUID, rowId: UUID)
    case translation(shapeId: UUID, fits: [UUID: TextAutoFitResult])
    case imported(rowId: UUID, count: Int, locale: String, failures: [String])
}

extension MCPToolName {
    /// Tools that edit one project's document: they take an optional `project_id` and are what `batch` accepts.
    var isEditing: Bool { editActionName != nil }

    /// The undo step's name in the editor.
    var editActionName: String? {
        switch self {
        case .addRow: "Add Row"
        case .updateRow: "Update Row"
        case .moveRow: "Move Row"
        case .deleteRow: "Delete Row"
        case .addTemplate: "Add Screenshot"
        case .removeTemplate: "Remove Screenshot"
        case .addShape: "Add Shape"
        case .updateShape: "Edit Shape"
        case .deleteShape: "Delete Shape"
        case .importScreenshots: "Import Screenshots"
        case .addLocale: "Add Language"
        case .removeLocale: "Remove Language"
        case .setTranslation: "Edit Translation"
        case .createVariant: "Create Variant"
        case .setRowVariant: "Move to Variant"
        case .deleteVariant: "Delete Variant"
        default: nil
        }
    }
}

extension MCPToolExecutor {

    /// The project an editing tool acts on: `project_id` when given, else the one open in the editor.
    func editCheckout(_ args: MCPArguments) async throws -> ProjectCheckout {
        if args.has("project_id") {
            return try await requireCheckout(args)
        }
        guard let id = state.activeProjectId else {
            throw MCPToolError.expected("No project is open in the app — pass project_id (from list_projects)")
        }
        let checkout = try await openCheckout(id)
        checkout.commitPendingEdits()
        return checkout
    }

    /// One editing tool, as one undo step in the open project or one save of a closed one.
    func runEdit(_ tool: MCPToolName, _ args: MCPArguments) async throws -> CallTool.Result {
        let checkout = try await editCheckout(args)
        defer { checkout.dispose() }
        var context = MCPEditContext(availableFontFamilies: checkout.availableFontFamilySet, resources: checkout)
        let result = try checkout.mutate(tool.editActionName ?? "") { document in
            try applyEdit(tool, args, to: &document, context: &context)
        }
        let writeFailures = try await land(context, in: checkout)
        return try MCPResultEncoding.result(render(result, in: checkout, writeFailures: writeFailures))
    }

    /// Saves the edit, then writes the images it points at. Returns the writes that failed.
    func land(_ context: MCPEditContext, in checkout: ProjectCheckout) async throws -> [String] {
        do {
            try checkout.commit()
        } catch ProjectCheckoutError.openedConcurrently(let name) {
            throw MCPToolError.expected("\(name) was opened in the app while this edit was in progress. Retry it.")
        }
        context.afterCommit.forEach { $0() }
        return await checkout.flush(context.staged)
    }

    func applyEdit(
        _ tool: MCPToolName,
        _ args: MCPArguments,
        to document: inout ProjectDocument,
        context: inout MCPEditContext
    ) throws -> MCPEditResult {
        switch tool {
        case .addRow: try addRow(args, &document)
        case .updateRow: try updateRow(args, &document)
        case .moveRow: try moveRow(args, &document)
        case .deleteRow: try deleteRow(args, &document)
        case .addTemplate: try addTemplate(args, &document)
        case .removeTemplate: try removeTemplate(args, &document)
        case .addShape: try addShape(args, &document, &context)
        case .updateShape: try updateShape(args, &document, &context)
        case .deleteShape: try deleteShape(args, &document)
        case .importScreenshots: try importScreenshots(args, &document, &context)
        case .addLocale: try addLocale(args, &document, &context)
        case .removeLocale: try removeLocale(args, &document)
        case .setTranslation: try setTranslation(args, &document, &context)
        case .createVariant: try createVariant(args, &document, &context)
        case .setRowVariant: try setRowVariant(args, &document)
        case .deleteVariant: try deleteVariant(args, &document)
        default: throw MCPToolError.unknownTool(tool.rawValue)
        }
    }

    func render(_ result: MCPEditResult, in checkout: ProjectCheckout, writeFailures: [String]) throws -> any Encodable {
        let document = checkout.document
        let fonts = checkout.availableFontFamilySet
        func rowSnapshot(_ id: UUID) throws -> MCPRowSnapshot {
            guard let index = document.rowIndex(for: id) else { throw MCPToolError.failed("Row was removed by the edit") }
            return checkout.withResolvedFonts {
                MCPSnapshotBuilder.rowSnapshot(document.rows[index], index: index, localeState: document.localeState, availableFontFamilies: fonts)
            }
        }
        func shapeSnapshot(_ id: UUID) throws -> MCPShapeSnapshot {
            guard let location = document.shapeLocation(for: id) else { throw MCPToolError.failed("Shape was removed by the edit") }
            let row = document.rows[location.rowIndex]
            return checkout.withResolvedFonts {
                MCPSnapshotBuilder.shapeSnapshot(row.shapes[location.shapeIndex], row: row, localeState: document.localeState, availableFontFamilies: fonts)
            }
        }
        // An import reports failures per image; any other edit has no way to say "partly".
        if !writeFailures.isEmpty {
            guard case .imported = result else {
                throw MCPToolError.unreadableFiles("The edit was saved, but its image could not be written: \(writeFailures.joined(separator: "; "))")
            }
        }

        switch result {
        case .row(let id):
            return try rowSnapshot(id)
        case .shape(let id):
            return try shapeSnapshot(id)
        case .locales:
            return ["locales": MCPSnapshotBuilder.locales(document.localeState)]
        case .variants:
            return Self.variantList(document)
        case .deletedRow(let id):
            return DeleteRowResult(deletedRowId: id.uuidString, remainingRows: document.rows.count)
        case .deletedShape(let id, let rowId):
            let remaining = document.rowIndex(for: rowId).map { document.rows[$0].shapes.count } ?? 0
            return DeleteShapeResult(deletedShapeId: id.uuidString, remainingShapes: remaining)
        case .translation(let shapeId, let fits):
            let alsoFitted = fits
                .filter { $0.key != shapeId && ($0.value.action != .none || $0.value.stillOverflows) }
                .map { MCPAutoFitSnapshot($0.value, shapeId: $0.key) }
                .sorted { $0.shapeId ?? "" < $1.shapeId ?? "" }
            return MCPSetTranslationResult(
                shape: try shapeSnapshot(shapeId),
                autoFit: fits[shapeId].map { MCPAutoFitSnapshot($0) },
                alsoFitted: alsoFitted.isEmpty ? nil : alsoFitted
            )
        case .imported(let rowId, let count, let locale, let failures):
            return ImportResult(
                imported: count,
                locale: count > 0 ? locale : nil,
                failures: failures + writeFailures,
                row: try rowSnapshot(rowId)
            )
        }
    }

    // MARK: - Lookups

    func requireRowIndex(_ args: MCPArguments, key: String = "row_id", in document: ProjectDocument) throws -> Int {
        let id = try args.uuid(key)
        guard let index = document.rowIndex(for: id) else {
            throw MCPToolError.notFound("Row \(id.uuidString)")
        }
        return index
    }

    func requireShapeLocation(
        _ args: MCPArguments,
        key: String = "shape_id",
        in document: ProjectDocument
    ) throws -> (rowIndex: Int, shapeIndex: Int, shapeId: UUID) {
        let id = try args.uuid(key)
        guard let location = document.shapeLocation(for: id) else {
            throw MCPToolError.notFound("Shape \(id.uuidString)")
        }
        return (location.rowIndex, location.shapeIndex, id)
    }
}

struct DeleteRowResult: Encodable {
    let deletedRowId: String
    let remainingRows: Int
}

struct DeleteShapeResult: Encodable {
    let deletedShapeId: String
    let remainingShapes: Int
}

struct ImportResult: Encodable {
    let imported: Int
    /// The locale actually written (nil when nothing was), so a caller can assert on it.
    let locale: String?
    let failures: [String]
    let row: MCPRowSnapshot
}
#endif

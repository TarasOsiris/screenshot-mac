#if DEBUG && os(macOS)
import Foundation
import MCP
import SwiftUI

/// Bridges MCP tool calls onto the main actor and the live AppState. Being @MainActor makes it
/// implicitly Sendable, so the SDK Server's handler closures can capture it and every call hops
/// to the main actor automatically.
@MainActor
final class MCPToolExecutor {
    let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            guard let tool = MCPToolName(rawValue: name) else {
                throw MCPToolError.unknownTool(name)
            }
            let args = MCPArguments(arguments)
            return try await dispatch(tool, args)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return CallTool.Result(content: [.text("Error: \(message)")], isError: true)
        }
    }

    private func dispatch(_ tool: MCPToolName, _ args: MCPArguments) async throws -> CallTool.Result {
        switch tool {
        case .listTemplates: try await listTemplates()
        case .listProjects: try listProjects()
        case .getProject: try getProject(args)
        case .createProject: try await createProject(args)
        case .renameProject: try renameProject(args)
        case .deleteProject: try deleteProject(args)
        case .switchProject: try switchProject(args)
        case .addRow: try addRow(args)
        case .updateRow: try updateRow(args)
        case .moveRow: try moveRow(args)
        case .deleteRow: try deleteRow(args)
        case .addTemplate: try addTemplate(args)
        case .removeTemplate: try removeTemplate(args)
        case .addShape: try addShape(args)
        case .updateShape: try updateShape(args)
        case .deleteShape: try deleteShape(args)
        case .importScreenshots: try importScreenshots(args)
        case .addLocale: try addLocale(args)
        case .removeLocale: try removeLocale(args)
        case .setTranslation: try setTranslation(args)
        case .exportProject: try await exportProject(args)
        case .renderPreview: try renderPreview(args)
        }
    }

    // MARK: - Shared lookups

    func requireProject(_ args: MCPArguments, key: String = "project_id") throws -> Project {
        let id = try args.uuid(key)
        guard let project = state.visibleProjects.first(where: { $0.id == id }) else {
            throw MCPToolError.notFound("Project \(id.uuidString)")
        }
        return project
    }

    func requireRowIndex(_ args: MCPArguments, key: String = "row_id") throws -> Int {
        let id = try args.uuid(key)
        guard let index = state.rowIndex(for: id) else {
            throw MCPToolError.notFound("Row \(id.uuidString)")
        }
        return index
    }

    func requireShapeLocation(_ args: MCPArguments, key: String = "shape_id") throws -> (rowIndex: Int, shapeIndex: Int, shapeId: UUID) {
        let id = try args.uuid(key)
        guard let location = state.shapeLocation(for: id) else {
            throw MCPToolError.notFound("Shape \(id.uuidString)")
        }
        return (location.rowIndex, location.shapeIndex, id)
    }

    func rowResult(_ rowIndex: Int) throws -> CallTool.Result {
        let row = state.rows[rowIndex]
        return try MCPResultEncoding.result(
            MCPSnapshotBuilder.rowSnapshot(row, index: rowIndex, localeState: state.localeState)
        )
    }

    func shapeResult(rowIndex: Int, shapeId: UUID) throws -> CallTool.Result {
        let row = state.rows[rowIndex]
        guard let shape = row.shapes.first(where: { $0.id == shapeId }) else {
            throw MCPToolError.notFound("Shape \(shapeId.uuidString)")
        }
        return try MCPResultEncoding.result(
            MCPSnapshotBuilder.shapeSnapshot(shape, row: row, localeState: state.localeState)
        )
    }

    func activeProjectSnapshotResult() throws -> CallTool.Result {
        guard let project = state.activeProject else {
            throw MCPToolError.failed("No active project")
        }
        return try MCPResultEncoding.result(
            MCPSnapshotBuilder.project(id: project.id, name: project.name, rows: state.rows, localeState: state.localeState)
        )
    }
}
#endif

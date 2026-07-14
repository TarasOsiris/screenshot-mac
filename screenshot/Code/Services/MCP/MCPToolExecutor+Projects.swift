#if DEBUG && os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    func listTemplates() async throws -> CallTool.Result {
        let templates = await TemplateService.availableTemplatesAsync()
        let items = templates.map { MCPTemplateListItem(id: $0.id, name: $0.name) }
        return try MCPResultEncoding.result(["templates": items])
    }

    func listProjects() throws -> CallTool.Result {
        try MCPResultEncoding.result(
            ["projects": MCPSnapshotBuilder.projectList(state.visibleProjects, activeProjectId: state.activeProjectId)]
        )
    }

    func getProject(_ args: MCPArguments) throws -> CallTool.Result {
        guard let id = try args.optionalUUID("project_id"), id != state.activeProjectId else {
            return try activeProjectSnapshotResult()
        }
        guard let project = state.visibleProjects.first(where: { $0.id == id }) else {
            throw MCPToolError.notFound("Project \(id.uuidString)")
        }
        guard let data = PersistenceService.loadProject(id) else {
            throw MCPToolError.failed("Project \(project.name) has no saved data yet")
        }
        return try MCPResultEncoding.result(
            MCPSnapshotBuilder.project(id: id, name: project.name, rows: data.rows, localeState: data.localeState ?? .default)
        )
    }

    func createProject(_ args: MCPArguments) async throws -> CallTool.Result {
        let name = try args.requiredString("name")

        if let templateId = args.string("template_id") {
            let templates = await TemplateService.availableTemplatesAsync()
            guard let template = templates.first(where: { $0.id == templateId }) else {
                throw MCPToolError.notFound("Template \(templateId)")
            }
            let previousError = state.saveError
            state.createProjectFromTemplate(template, name: name)
            if let saveError = state.saveError, saveError != previousError {
                throw MCPToolError.failed(saveError)
            }
        } else {
            let configurations = try (args.objectArray("rows") ?? []).map { row in
                BlankProjectRowConfiguration(
                    label: row.string("label"),
                    sizePreset: row.string("size"),
                    templateCount: row.int("template_count"),
                    deviceCategory: try row.enumValue("device_category", DeviceCategory.self),
                    deviceFrameId: row.string("device_frame_id")
                )
            }
            state.createBlankProject(name: name, rowConfigurations: configurations)
        }
        return try activeProjectSnapshotResult()
    }

    func renameProject(_ args: MCPArguments) throws -> CallTool.Result {
        let project = try requireProject(args)
        let name = try args.requiredString("name")
        state.renameProject(project.id, to: name)
        return try listProjects()
    }

    func deleteProject(_ args: MCPArguments) throws -> CallTool.Result {
        let project = try requireProject(args)
        state.deleteProject(project.id)
        return try listProjects()
    }

    func switchProject(_ args: MCPArguments) throws -> CallTool.Result {
        let project = try requireProject(args)
        if project.id != state.activeProjectId {
            state.switchToProject(project.id)
        }
        return try activeProjectSnapshotResult()
    }
}
#endif

#if os(macOS)
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

    /// Named explicitly, always. The open project used to be the default, which meant a snapshot
    /// could silently describe a different project than the caller meant — and every id it hands
    /// back is then used by other tools.
    func getProject(_ args: MCPArguments) async throws -> CallTool.Result {
        let checkout = try await requireCheckout(args)
        defer { checkout.dispose() }
        return try MCPResultEncoding.result(
            MCPSnapshotBuilder.project(
                id: checkout.projectId,
                name: checkout.projectName,
                rows: checkout.rows,
                localeState: checkout.localeState
            )
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
        return try await settledActiveProjectSnapshotResult()
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

    func switchProject(_ args: MCPArguments) async throws -> CallTool.Result {
        let project = try requireProject(args)
        if project.id != state.activeProjectId {
            // selectProject (not switchToProject) so the outgoing project's debounced edits
            // are saved before its rows are torn down — same path as every UI caller.
            state.selectProject(project.id)
        }
        return try await settledActiveProjectSnapshotResult()
    }

    /// Snapshot the active project only after its asynchronous open has finished; right
    /// after a create/switch the rows still belong to the previous project.
    func settledActiveProjectSnapshotResult() async throws -> CallTool.Result {
        await state.projectOpenTask?.value
        return try activeProjectSnapshotResult()
    }
}
#endif

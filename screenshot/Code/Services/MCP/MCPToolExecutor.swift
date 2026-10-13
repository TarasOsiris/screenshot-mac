#if os(macOS)
import Foundation
import MCP

/// Bridges MCP tool calls onto the main actor and the live AppState. Being @MainActor makes it
/// implicitly Sendable, so the SDK Server's handler closures can capture it and every call hops
/// to the main actor automatically.
@MainActor
final class MCPToolExecutor {
    let state: AppState
    let sessions: MCPSessionTracker
    /// Shared rather than per-executor: a new executor is built on every server start, so a
    /// per-instance registry would drop running jobs on a settings toggle or token rotation.
    let jobs: MCPJobStore
    /// Injected so the idempotent-retry path can be driven against a fake App Store Connect.
    let screenshotSync: AppStoreConnectScreenshotSyncService

    init(
        state: AppState,
        sessions: MCPSessionTracker = .shared,
        jobs: MCPJobStore = .shared,
        screenshotSync: AppStoreConnectScreenshotSyncService = .shared
    ) {
        self.state = state
        self.sessions = sessions
        self.jobs = jobs
        self.screenshotSync = screenshotSync
    }

    func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        // Argument *keys* only — the values carry project text the user wrote.
        CrashReportingService.breadcrumb(.mcp, "Tool \(name)", data: ["args": (arguments?.keys.sorted() ?? [])])
        // `name` is client-supplied; only a name that matched our catalog is safe to send onward.
        // A flag-gated tool is unknown while its flag is off, in analytics too.
        let tool = MCPToolName(rawValue: name).flatMap { $0.isAvailable ? $0 : nil }
        let sessionId = sessions.note(.toolCall(tool))
        do {
            guard let tool else {
                throw MCPToolError.unknownTool(name)
            }
            if let schema = MCPToolCatalog.inputSchema(for: tool) {
                try MCPArgumentValidator.validate(arguments, against: schema)
            }
            let args = MCPArguments(arguments)
            let result = try await dispatch(tool, args)
            AnalyticsService.capture(.mcpToolCalled, [.tool: tool.rawValue, .ok: true, .mcpSessionId: sessionId])
            return result
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            if error is CancellationError {
                // The client cancelled the request — expected, not our bug (matches runJob's handling).
                CrashReportingService.breadcrumb(.mcp, "Tool \(name) was cancelled")
            } else if let toolError = error as? MCPToolError, toolError.isClientError {
                CrashReportingService.breadcrumb(.mcp, "Tool \(name) rejected the request", level: .warning)
            } else {
                CrashReportingService.report(.mcpToolFailed, error: error, extra: ["tool": name], level: .warning)
            }
            AnalyticsService.capture(.mcpToolCalled, [
                .tool: tool?.rawValue ?? "unknown",
                .ok: false,
                .mcpSessionId: sessionId,
            ])
            return CallTool.Result(content: [.text("Error: \(message)")], isError: true)
        }
    }

    private func dispatch(_ tool: MCPToolName, _ args: MCPArguments) async throws -> CallTool.Result {
        switch tool {
        case .addRow, .updateRow, .moveRow, .deleteRow, .addTemplate, .removeTemplate, .addShape, .updateShape,
             .deleteShape, .importScreenshots, .addLocale, .removeLocale, .setTranslation, .createVariant,
             .setRowVariant, .deleteVariant:
            return try await runEdit(tool, args)
        case .listTemplates: return try await listTemplates()
        case .listProjects: return try listProjects()
        case .getProject: return try await getProject(args)
        case .createProject: return try await createProject(args)
        case .renameProject: return try renameProject(args)
        case .deleteProject: return try deleteProject(args)
        case .switchProject: return try await switchProject(args)
        case .exportProject: return try await exportProject(args)
        case .renderPreview: return try await renderPreview(args)
        case .getAppStoreMetadata: return try await getAppStoreMetadata(args)
        case .updateAppStoreDescription: return try await updateAppStoreDescription(args)
        case .previewAppStoreScreenshotSync: return try await previewAppStoreScreenshotSync(args)
        case .applyAppStoreScreenshotSync: return try await applyAppStoreScreenshotSync(args)
        case .getSyncJobStatus: return try getSyncJobStatus(args)
        case .cancelSyncJob: return try cancelSyncJob(args)
        case .listVariants: return try await listVariants(args)
        case .batch: return try await batch(args)
        case .setTranslations: return try await setTranslations(args)
        case .listCatalog: return try await listCatalog(args)
        case .undo: return try undo(args, redo: false)
        case .redo: return try undo(args, redo: true)
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

    func activeProjectSnapshotResult() throws -> CallTool.Result {
        guard let project = state.activeProject else {
            throw MCPToolError.expected("No active project")
        }
        return try MCPResultEncoding.result(
            MCPSnapshotBuilder.project(id: project.id, name: project.name, rows: state.rows, localeState: state.localeState, availableFontFamilies: state.availableFontFamilySet)
        )
    }
}
#endif

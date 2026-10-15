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
    /// The last edit queued per project; see `serializingEdits`.
    var editChains: [UUID: Task<Void, Never>] = [:]

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
            let schema = try MCPToolCatalog.requireInputSchema(for: tool)
            try MCPArgumentValidator.validate(arguments, against: schema)
            guard let handler = handler(for: tool) else {
                throw MCPToolError.failed("\(tool.rawValue) has no handler")
            }
            let result = try await handler(MCPArguments(arguments, schema: schema))
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

    typealias Handler = @MainActor (MCPArguments) async throws -> CallTool.Result

    /// Nil only for a tool nobody wired up, which `MCPToolCatalogTests` catches.
    func handler(for tool: MCPToolName) -> Handler? {
        if tool.isEditing {
            return { try await self.runEdit(tool, $0) }
        }
        switch tool {
        case .listTemplates: return { _ in try await self.listTemplates() }
        case .listProjects: return { _ in try self.listProjects() }
        case .getProject: return getProject
        case .createProject: return createProject
        case .renameProject: return renameProject
        case .deleteProject: return deleteProject
        case .switchProject: return switchProject
        case .exportProject: return exportProject
        case .renderPreview: return renderPreview
        case .getAppStoreMetadata: return getAppStoreMetadata
        case .updateAppStoreDescription: return updateAppStoreDescription
        case .previewAppStoreScreenshotSync: return previewAppStoreScreenshotSync
        case .applyAppStoreScreenshotSync: return applyAppStoreScreenshotSync
        case .getSyncJobStatus: return getSyncJobStatus
        case .cancelSyncJob: return cancelSyncJob
        case .listVariants: return listVariants
        case .batch: return batch
        case .setTranslations: return setTranslations
        case .listCatalog: return listCatalog
        case .undo: return { try self.undo($0, redo: false) }
        case .redo: return { try self.undo($0, redo: true) }
        case .updateAppStoreMetadata: return updateAppStoreMetadata
        case .listAppStoreApps: return { _ in try await self.listAppStoreApps() }
        case .linkProjectStores: return linkProjectStores
        case .previewPlayUpload: return previewPlayUpload
        case .uploadPlayScreenshots: return uploadPlayScreenshots
        default: return nil
        }
    }

    // MARK: - Shared lookups

    /// `row_ids`, when given, every one a row of `rows`.
    func requireRowIds(_ args: MCPArguments, among rows: [ScreenshotRow]) throws -> Set<UUID>? {
        guard let ids = try args.uuidArray("row_ids").map(Set.init) else { return nil }
        if let missing = ids.subtracting(rows.map(\.id)).first {
            throw MCPToolError.notFound("Row \(missing.uuidString)")
        }
        return ids
    }

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

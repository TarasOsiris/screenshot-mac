#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    /// Resolves the project a tool acts on — **always from its arguments**, never from whatever the
    /// editor happens to have open.
    ///
    /// The implicit-active-project default is the bug this removes. `import_screenshots` already
    /// learned the same lesson one level down for `locale`: "a present-but-unusable value has to
    /// fail rather than fall back". A silent default is invisible to the caller, and the failure it
    /// produces — building a plan from one app's artwork and uploading it to another app's listing —
    /// is one no dimension check would catch.
    func requireCheckout(_ args: MCPArguments, key: String = "project_id") async throws -> ProjectCheckout {
        let id = try args.uuid(key)
        return try await openCheckout(id)
    }

    /// For `apply`, where the project is already pinned by the plan: `project_id` stays optional and
    /// defaults to the plan's own project, because naming a different one is meaningless — the plan
    /// holds the rendered bytes.
    func requireCheckout(_ args: MCPArguments, allowingPlan plan: ASCScreenshotSyncPlan?) async throws -> ProjectCheckout {
        if let id = try args.optionalUUID("project_id") {
            if let plan, plan.projectId != id {
                throw MCPToolError.invalidArgument(
                    "project_id",
                    "does not match the plan, which was rendered from project \(plan.projectId.uuidString)"
                )
            }
            return try await openCheckout(id)
        }
        guard let plan else { throw MCPToolError.missingArgument("project_id") }
        return try await openCheckout(plan.projectId)
    }

    /// The two App Store *metadata* tools are not project-scoped when `app_id` is supplied —
    /// `project_id` exists only to look up the linked app. So they take one or the other, rather
    /// than requiring a project that plays no part in the request.
    func resolveASCAppId(fromAppIdOrProject args: MCPArguments) async throws -> String {
        if let explicit = args.string("app_id"), !explicit.isEmpty { return explicit }
        guard let id = try args.optionalUUID("project_id") else {
            throw MCPToolError.missingArgument("app_id (or project_id, to use its linked app)")
        }
        let checkout = try await openCheckout(id)
        defer { checkout.dispose() }
        guard let linked = checkout.ascAppId, !linked.isEmpty else {
            throw MCPToolError.failed("\(checkout.projectName) is not linked to an App Store Connect app — pass app_id, or link it via the App Store Connect upload wizard.")
        }
        return linked
    }

    func openCheckout(_ id: UUID) async throws -> ProjectCheckout {
        do {
            return try await ProjectCheckout.open(projectId: id, state: state)
        } catch let error as ProjectCheckoutError {
            // A bad id is the caller's mistake, so it stays breadcrumb-only rather than opening a
            // Sentry issue; an unreadable file on disk is ours.
            switch error {
            case .notFound:
                throw MCPToolError.notFound("Project \(id.uuidString)")
            case .unreadable(let name):
                throw MCPToolError.failed("Project \(name) could not be read from disk")
            }
        }
    }
}
#endif

#if os(macOS)
import Foundation
import MCP

/// What a job body reports back.
///
/// `succeeded` is separate from "the body returned" on purpose: `apply` catches its own failures
/// and *returns* a partial result rather than throwing, so a body completing tells you nothing
/// about whether the work landed.
nonisolated struct MCPJobOutcome: Sendable {
    let value: Value
    let succeeded: Bool

    init(_ value: Value, succeeded: Bool = true) {
        self.value = value
        self.succeeded = succeeded
    }
}

nonisolated enum MCPJobMode: String, Sendable, CaseIterable {
    /// Small requests run inline; large ones become a job. The default.
    case auto
    case sync
    case async
}

extension MCPToolExecutor {

    /// The envelope all four sync tools return, so an agent writes one parser.
    struct MCPSyncJobStatus: Encodable {
        let jobId: String
        let tool: String
        let phase: String
        let planId: String?
        let startedAt: String?
        let finishedAt: String?
        let elapsedMs: Int
        let completed: Int
        let total: Int
        /// Row · locale of the unit in flight. User content, which is fine in a tool result
        /// returned to the local caller — but never in a breadcrumb or an analytics property.
        let currentLabel: String?
        let cancelRequested: Bool
        let didMutate: Bool
        let sets: [SetProgress]
        let error: String?
        /// Present only once the job succeeded: the full preview/apply payload.
        let result: Value?

        struct SetProgress: Encodable {
            let setId: String
            let state: String
        }
    }

    // MARK: - Sizing

    /// Renders is the only unit both known before any work starts and proportional to elapsed
    /// time. 180 renders took ~130 s and timed out; 36 returned fine.
    static let syncPreviewRenderLimit = 40
    static let hardPreviewRenderLimit = 400
    /// Much tighter than the render limit, because `waitForDelivery` polls up to 30 s *per upload*
    /// and `verify` up to 30 s *per set* — a small diff spread over many locales is slow for
    /// reasons the step count alone doesn't show.
    static let syncApplyStepLimit = 12
    static let syncApplySetLimit = 2
    static let hardApplyStepLimit = 200

    static func previewRenderCount(_ targets: [ASCUploadTarget]) -> Int {
        targets.reduce(0) { $0 + $1.templateCount * $1.localizations.count }
    }

    static func resolveMode(_ args: MCPArguments) throws -> MCPJobMode {
        guard let raw = args.string("mode"), !raw.isEmpty else { return .auto }
        guard let mode = MCPJobMode(rawValue: raw) else {
            throw MCPToolError.invalidArgument("mode", "expected auto, sync or async")
        }
        return mode
    }

    /// A client that asked for `sync` and silently got a job id back would parse the wrong shape,
    /// so an oversized `sync` is rejected rather than upgraded.
    static func decideMode(_ requested: MCPJobMode, units: Int, fitsSync: Bool, hardLimit: Int, unitName: String) throws -> MCPJobMode {
        switch requested {
        case .async: return .async
        case .auto: return fitsSync ? .sync : .async
        case .sync:
            guard units <= hardLimit else {
                throw MCPToolError.invalidArgument(
                    "mode",
                    "an estimated \(units) \(unitName) exceeds the synchronous cap of \(hardLimit) — use mode \"async\" and poll get_sync_job_status"
                )
            }
            return .sync
        }
    }

    // MARK: - Running

    /// Registers a job, runs its body, and returns the job envelope — after awaiting the body when
    /// the caller asked for a synchronous run.
    ///
    /// The body is an explicit `@MainActor` closure, not a `nonisolated async func`: under this
    /// target's `SWIFT_APPROACHABLE_CONCURRENCY` the latter inherits the caller's executor, and the
    /// rendering inside genuinely needs the main actor anyway. What moves off the request here is
    /// the *waiting*, not the work.
    /// `owning` transfers the checkout to the job: in async mode `runJob` returns long before the
    /// body has rendered anything, so disposing at the caller's function exit would unregister the
    /// project's fonts out from under the render.
    func runJob(
        kind: MCPJobKind,
        totalUnits: Int,
        mode: MCPJobMode,
        owning checkout: ProjectCheckout? = nil,
        body: @escaping @MainActor (MCPJobHandle) async throws -> MCPJobOutcome
    ) async throws -> CallTool.Result {
        let store = jobs
        let jobId = store.register(kind: kind, totalUnits: totalUnits)
        let handle = MCPJobHandle(id: jobId, store: store)
        CrashReportingService.breadcrumb(.mcp, "MCP job started", data: [
            "kind": kind.rawValue,
            "mode": mode.rawValue,
            "units": totalUnits,
        ])
        let task = Task { @MainActor in
            defer { checkout?.dispose() }
            do {
                let outcome = try await body(handle)
                // The payload is retained either way — a partial apply's per-set detail is exactly
                // what a caller needs to recover.
                store.finish(jobId, phase: outcome.succeeded ? .succeeded : .failed) {
                    $0.result = outcome.value
                }
            } catch is CancellationError {
                store.finish(jobId, phase: .cancelled) {
                    $0.errorMessage = String(localized: "The screenshot sync was cancelled.")
                }
            } catch {
                store.finish(jobId, phase: .failed) { $0.errorMessage = error.localizedDescription }
            }
            Self.reportJobFinished(store.job(jobId), kind: kind)
        }
        store.attach(task, to: jobId)
        if mode == .sync { await task.value }
        return try jobStatusResult(jobId)
    }

    private static func reportJobFinished(_ job: MCPJobState?, kind: MCPJobKind) {
        guard let job else { return }
        // Counts, enum raw values and our own ids only — never a set id, locale or app id.
        CrashReportingService.breadcrumb(.mcp, "MCP job finished", data: [
            "kind": kind.rawValue,
            "phase": job.phase.rawValue,
            "did_mutate": job.didMutate,
            "sets": job.sets.count,
            "duration_ms": Int(job.elapsed * 1000),
        ], level: job.phase == .failed ? .warning : .info)
    }

    // MARK: - Tools

    func getSyncJobStatus(_ args: MCPArguments) throws -> CallTool.Result {
        let jobId = try args.requiredString("job_id")
        return try jobStatusResult(jobId, includeImage: args.bool("include_image") == true)
    }

    func cancelSyncJob(_ args: MCPArguments) throws -> CallTool.Result {
        let jobId = try args.requiredString("job_id")
        guard jobs.cancel(jobId) != nil else {
            throw MCPToolError.notFound("Job \(jobId)")
        }
        return try jobStatusResult(jobId)
    }

    func jobStatusResult(_ jobId: String, includeImage: Bool = false) throws -> CallTool.Result {
        guard let job = jobs.job(jobId) else {
            throw MCPToolError.notFound("Job \(jobId)")
        }
        let iso = ISO8601DateFormatter()
        let status = MCPSyncJobStatus(
            jobId: job.id,
            tool: job.kind.rawValue,
            phase: job.phase.rawValue,
            planId: job.planId,
            startedAt: job.startedAt.map(iso.string(from:)),
            finishedAt: job.finishedAt.map(iso.string(from:)),
            elapsedMs: Int(job.elapsed * 1000),
            completed: job.completedUnits,
            total: job.totalUnits,
            currentLabel: job.currentLabel,
            cancelRequested: job.cancelRequested,
            didMutate: job.didMutate,
            sets: job.sets.map { .init(setId: $0.setId, state: $0.state.rawValue) },
            error: job.errorMessage,
            result: job.result
        )
        if includeImage, let png = job.contactSheetPNG {
            return try MCPResultEncoding.result(status, pngImage: png)
        }
        return try MCPResultEncoding.result(status)
    }
}
#endif

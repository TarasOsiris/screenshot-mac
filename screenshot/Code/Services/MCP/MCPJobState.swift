#if os(macOS)
import Foundation
import MCP

nonisolated enum MCPJobKind: String, Sendable, CaseIterable {
    case preview = "preview_app_store_screenshot_sync"
    case apply = "apply_app_store_screenshot_sync"
}

nonisolated enum MCPJobPhase: String, Sendable {
    case queued
    case rendering
    case comparing
    case revalidating
    case uploading
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool { self == .succeeded || self == .failed || self == .cancelled }
}

nonisolated struct MCPJobSetProgress: Sendable, Equatable {
    /// Snake case to match `ASCScreenshotSetSyncResult.State`, which appears under `result.sets`
    /// in the same response. These are encoded *values*, so `keyEncodingStrategy` does not
    /// normalize them, and two spellings of "already applied" in one envelope is a trap.
    enum State: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case succeeded
        case alreadyApplied = "already_applied"
        case failed
        case notAttempted = "not_attempted"
    }

    let setId: String
    var state: State = .pending
}

nonisolated struct MCPJobState: Sendable {
    let id: String
    let kind: MCPJobKind
    let createdAt: Date
    var planId: String?
    var phase: MCPJobPhase = .queued
    var startedAt: Date?
    var finishedAt: Date?
    var cancelRequested = false
    /// Whether the live App Store listing has been written to. The single most useful bit when a
    /// job fails: the difference between "nothing was touched" and "your listing is half-updated".
    var didMutate = false
    var completedUnits = 0
    var totalUnits: Int
    /// Row · locale of the unit in flight. User-written, so it may go in a tool *result* but never
    /// into a breadcrumb or an analytics property.
    var currentLabel: String?
    var sets: [MCPJobSetProgress] = []
    var errorMessage: String?
    /// The terminal payload, pre-encoded. `Value` rather than a generic keeps the registry
    /// non-generic while the executor stays the one place that knows a tool's result shape.
    var result: Value?
    /// The preview's contact sheet, held back until a caller asks for it — a polling agent should
    /// not re-download ~150 KB of base64 every couple of seconds.
    var contactSheetPNG: Data?

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

/// The job table, as a pure value so the state machine is testable without a live App Store
/// Connect, a `Task`, or a clock. `MCPSessionState` is the model.
nonisolated struct MCPJobRegistry: Sendable {
    /// Matches `AppStoreConnectScreenshotSyncService.planLifetime` — a result outliving the plan it
    /// describes would invite a resume that can no longer work.
    static let resultLifetime: TimeInterval = 15 * 60
    static let capacity = 32

    private(set) var jobs: [String: MCPJobState] = [:]

    mutating func register(kind: MCPJobKind, totalUnits: Int, at now: Date, id: String = "job_\(UUID().uuidString)") -> String {
        purge(at: now)
        jobs[id] = MCPJobState(id: id, kind: kind, createdAt: now, totalUnits: totalUnits)
        return id
    }

    func job(_ id: String) -> MCPJobState? { jobs[id] }

    /// A terminal job is frozen. Progress callbacks can still be in flight when a job is cancelled
    /// or fails, and letting one land would resurrect a job the caller was already told about.
    mutating func update(_ id: String, at now: Date, _ mutate: (inout MCPJobState) -> Void) {
        guard var job = jobs[id], !job.phase.isTerminal else { return }
        if job.startedAt == nil { job.startedAt = now }
        mutate(&job)
        jobs[id] = job
    }

    mutating func finish(_ id: String, phase: MCPJobPhase, at now: Date, _ mutate: (inout MCPJobState) -> Void = { _ in }) {
        guard var job = jobs[id], !job.phase.isTerminal else { return }
        if job.startedAt == nil { job.startedAt = now }
        mutate(&job)
        job.phase = phase
        // A job cannot succeed having done less work than it set out to. This shipped once as
        // `phase: "succeeded"` on an apply that completed 38 of 44 steps and left six App Store
        // screenshots missing — a caller trusting the phase would have published the gap. The
        // body reports its own outcome, and this is the backstop for a body that forgets.
        if phase == .succeeded, job.completedUnits < job.totalUnits {
            job.phase = .failed
            job.errorMessage = job.errorMessage ?? String(
                localized: "Finished \(job.completedUnits) of \(job.totalUnits) steps. Check each set's state — some did not complete."
            )
        }
        job.finishedAt = now
        job.currentLabel = nil
        jobs[id] = job
    }

    /// Marks the intent. The actual `Task` cancellation lives in the store; the job goes terminal
    /// only once the body unwinds, so a cancel never invents a state the work hasn't reached.
    mutating func requestCancel(_ id: String, at now: Date) -> MCPJobState? {
        guard var job = jobs[id] else { return nil }
        guard !job.phase.isTerminal else { return job }
        job.cancelRequested = true
        jobs[id] = job
        return job
    }

    mutating func purge(at now: Date) {
        for (id, job) in jobs {
            guard let finishedAt = job.finishedAt else { continue }
            if now.timeIntervalSince(finishedAt) >= Self.resultLifetime { jobs[id] = nil }
        }
        guard jobs.count > Self.capacity else { return }
        // Only finished jobs are evictable — dropping a running one would strand its poller.
        let evictable = jobs.values
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
        for job in evictable.prefix(jobs.count - Self.capacity) { jobs[job.id] = nil }
    }
}
#endif

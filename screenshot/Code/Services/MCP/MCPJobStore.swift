#if os(macOS)
import Foundation
import MCP

/// Long MCP operations, tracked so a tool call can return immediately and be polled to completion.
///
/// A lock rather than an actor, for the same reason `MCPSessionTracker` uses one: the progress
/// callbacks it feeds off (`buildPlan`'s and `apply`'s) are **synchronous** `@escaping` closures.
/// An actor would force a `Task { await … }` per tick — hundreds of tasks, landing out of order
/// relative to the work they describe. It is also read from `MCPServerService.stop()`.
nonisolated final class MCPJobStore: @unchecked Sendable {
    static let shared = MCPJobStore()

    private let lock = NSLock()
    private var registry = MCPJobRegistry()
    private var tasks: [String: Task<Void, Never>] = [:]

    func register(kind: MCPJobKind, totalUnits: Int, now: Date = Date()) -> String {
        lock.withLock { registry.register(kind: kind, totalUnits: totalUnits, at: now) }
    }

    func job(_ id: String) -> MCPJobState? {
        lock.withLock { registry.job(id) }
    }

    func update(_ id: String, now: Date = Date(), _ mutate: (inout MCPJobState) -> Void) {
        lock.withLock { registry.update(id, at: now, mutate) }
    }

    func finish(_ id: String, phase: MCPJobPhase, now: Date = Date(), _ mutate: (inout MCPJobState) -> Void = { _ in }) {
        lock.withLock {
            registry.finish(id, phase: phase, at: now, mutate)
            tasks[id] = nil
        }
    }

    func attach(_ task: Task<Void, Never>, to id: String) {
        lock.withLock { tasks[id] = task }
    }

    /// Records the intent and cancels the task. The job goes terminal only when its body unwinds,
    /// so a cancel never reports a state the work hasn't actually reached.
    @discardableResult
    func cancel(_ id: String, now: Date = Date()) -> MCPJobState? {
        let (state, task): (MCPJobState?, Task<Void, Never>?) = lock.withLock {
            (registry.requestCancel(id, at: now), tasks[id])
        }
        task?.cancel()
        return state
    }

    /// Called when the server stops for good. Not on a restart: killing an in-flight upload
    /// because the user rotated a token is strictly worse than letting it finish.
    func cancelAll(now: Date = Date()) {
        let running: [Task<Void, Never>] = lock.withLock {
            // Recorded before the tasks are dropped: a poller reading the envelope while a body
            // unwinds must see a job the app has abandoned, not one still making progress.
            for id in tasks.keys { _ = registry.requestCancel(id, at: now) }
            let values = Array(tasks.values)
            tasks.removeAll()
            return values
        }
        guard !running.isEmpty else { return }
        CrashReportingService.breadcrumb(.mcp, "MCP jobs abandoned on server stop", data: ["jobs": running.count], level: .warning)
        for task in running { task.cancel() }
    }
}

/// The write end of a job, handed to the body so it can report progress without reaching for the
/// singleton — and so a test can drive a body with no store at all.
nonisolated struct MCPJobHandle: Sendable {
    let id: String
    private let store: MCPJobStore

    init(id: String, store: MCPJobStore) {
        self.id = id
        self.store = store
    }

    func update(_ mutate: @Sendable (inout MCPJobState) -> Void) {
        store.update(id, mutate)
    }

    func phase(_ phase: MCPJobPhase) {
        store.update(id) { $0.phase = phase }
    }

    func progress(completed: Int, total: Int? = nil, label: String? = nil) {
        store.update(id) {
            $0.completedUnits = completed
            if let total { $0.totalUnits = total }
            if let label { $0.currentLabel = label }
        }
    }
}
#endif

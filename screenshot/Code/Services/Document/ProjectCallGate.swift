import Foundation

/// One MCP call per project at a time.
///
/// The SDK dispatches every `tools/call` in its own child task, so two calls can interleave at any
/// `await` inside a tool. Two mutations of one project would race, and a render could observe a
/// half-applied one. Per project rather than global: rendering project A must not block editing B.
///
/// An `actor` on purpose. Under this target's `SWIFT_APPROACHABLE_CONCURRENCY` a bare
/// `nonisolated async func` inherits the caller's executor and offloads nothing — but an actor's
/// own methods always hop to its executor, so this needs no lint suppression. The continuation
/// queue mirrors `ThumbnailConcurrencyGate`.
actor ProjectCallGate {
    static let shared = ProjectCallGate()

    private var held: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var peak = 0
    private var active = 0

    /// Highest number of permits held simultaneously — for tests.
    var peakConcurrency: Int { peak }

    func acquire(_ projectId: UUID) async {
        if held.insert(projectId).inserted {
            active += 1
            peak = max(peak, active)
            return
        }
        await withCheckedContinuation { waiters[projectId, default: []].append($0) }
        // Resumed by `release`, which hands its permit over — `held` stays set.
    }

    func release(_ projectId: UUID) {
        if var queue = waiters[projectId], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[projectId] = queue.isEmpty ? nil : queue
            next.resume()
            return
        }
        held.remove(projectId)
        active -= 1
    }

    /// Runs `body` holding the project's permit. A gated body must never acquire a *second*
    /// project's permit — that is the only way to deadlock this.
    func withPermit<R>(_ projectId: UUID, _ body: () async throws -> R) async rethrows -> R {
        await acquire(projectId)
        defer { release(projectId) }
        return try await body()
    }
}

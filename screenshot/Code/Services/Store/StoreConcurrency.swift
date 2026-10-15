import Foundation

/// Store requests a few at a time: both APIs rate-limit, and a task per request trips them.
// Main-actor closures throughout: converting an array of them to another function type fails at runtime.
@MainActor
enum StoreConcurrency {
    /// Runs `operations` at most `limit` at once. `onResult` sees each result as it lands and
    /// returns false to cancel what is still running and start nothing more.
    static func forEach<T: Sendable>(
        _ operations: [@MainActor () async -> T],
        limit: Int,
        onResult: (T) -> Bool = { _ in true }
    ) async {
        await withTaskGroup(of: T.self) { group in
            var pending = operations.makeIterator()
            for _ in 0..<limit {
                guard let operation = pending.next() else { break }
                group.addTask { await operation() }
            }
            while let result = await group.next() {
                guard onResult(result) else {
                    group.cancelAll()
                    return
                }
                if let operation = pending.next() { group.addTask { await operation() } }
            }
        }
    }

    /// Stops at the first error and rethrows it once the operations already running have finished.
    static func forEach(_ operations: [@MainActor () async throws -> Void], limit: Int) async throws {
        var firstError: (any Error)?
        let caught: [@MainActor () async -> (any Error)?] = operations.map { operation in
            {
                do {
                    try await operation()
                    return nil
                } catch {
                    return error
                }
            }
        }
        await forEach(caught, limit: limit) { error in
            firstError = error
            return error == nil
        }
        if let firstError { throw firstError }
    }
}

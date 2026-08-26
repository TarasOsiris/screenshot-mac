import Foundation

extension Task where Success == Void, Failure == Never {
    /// Runs `work` after `delay` unless cancelled first — the shape every debounce here needs.
    /// The `isCancelled` re-check is the load-bearing part: `Task.sleep` throws on cancellation
    /// but `try?` swallows it, so without it a cancelled debounce still fires.
    static func delayed(_ delay: TimeInterval, _ work: @escaping () -> Void) -> Task<Void, Never> {
        Task {
            // Spelled out because this extension constrains `Success`/`Failure`, which `sleep` won't accept.
            try? await Task<Never, Never>.sleep(for: .seconds(delay))
            guard !Task<Never, Never>.isCancelled else { return }
            work()
        }
    }
}

import Foundation

/// When a failed store request may be sent again, and how long to wait first.
///
/// Both stores fail transiently often enough that a single 500 used to abort a whole upload
/// mid-flight, leaving the user's store half-updated. Whether a failure may be repeated turns
/// on whether the request could already have taken effect, so every rule is expressed against
/// one `repeatable` fact rather than against the status code alone.
nonisolated struct StoreRetryPolicy: Sendable {
    var maxAttempts: Int = 3
    var baseDelay: Duration = .milliseconds(500)
    var maxDelay: Duration = .seconds(8)

    var attempts: Int { max(1, maxAttempts) }

    /// For calls whose caller already owns a retry budget. Stacking a second one multiplies the
    /// request count against an endpoint that is, by definition, already struggling.
    static let singleAttempt = StoreRetryPolicy(maxAttempts: 1)

    /// Verbs that can be repeated without changing the outcome. A call that is repeatable for
    /// some other reason — a pinned byte range, a compensating cleanup between attempts —
    /// says so with `repeatable:` instead.
    static let idempotentMethods: Set<String> = ["GET", "HEAD", "DELETE", "PUT", "OPTIONS"]

    /// Server-side hiccups: the request failed, but an identical one may well succeed. 429 is
    /// here because it is refused before the server acts — but it still needs `repeatable`,
    /// since a proxy can rate-limit a request the origin already processed.
    static let retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]

    /// Failures where the request provably never reached the server, so repeating it is safe
    /// whatever the call's side effects.
    static let undeliveredURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
    ]

    /// Failures where the request may or may not have been processed — only safe to repeat
    /// when repeating is harmless anyway.
    static let ambiguousURLErrorCodes: Set<URLError.Code> = [.timedOut, .networkConnectionLost]

    func allowsRetry(status: Int, repeatable: Bool) -> Bool {
        repeatable && Self.retryableStatusCodes.contains(status)
    }

    func allowsRetry(transportError: Error, repeatable: Bool) -> Bool {
        guard let code = (transportError as? URLError)?.code else { return false }
        return Self.undeliveredURLErrorCodes.contains(code)
            || (repeatable && Self.ambiguousURLErrorCodes.contains(code))
    }

    func allowsRetry(status: Int, method: String) -> Bool {
        allowsRetry(status: status, repeatable: Self.isIdempotent(method))
    }

    func allowsRetry(transportError: Error, method: String) -> Bool {
        allowsRetry(transportError: transportError, repeatable: Self.isIdempotent(method))
    }

    /// A request that never left the device tells us nothing about server state, so a caller
    /// with cleanup to do can skip it.
    static func reachedServer(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return true }
        return !undeliveredURLErrorCodes.contains(code)
    }

    static func isIdempotent(_ method: String) -> Bool {
        idempotentMethods.contains(method.uppercased())
    }

    /// `Retry-After` wins when the server sends one — guessing shorter just burns the budget.
    /// Only the delta-seconds form is honoured; both stores use it, and an HTTP-date would
    /// need clock-skew handling to be worth reading.
    func delay(forAttempt attempt: Int, retryAfter: String?) -> Duration {
        if let retryAfter, let seconds = Int(retryAfter.trimmingCharacters(in: .whitespaces)), seconds > 0 {
            return min(.seconds(seconds), maxDelay)
        }
        return min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
    }
}

extension StoreRetryPolicy {
    /// Thrown by an attempt that has already judged its own failure worth repeating. Carrying
    /// the decision out of the body is what lets one loop serve callers whose failures are
    /// different types entirely.
    struct Retryable: Error {
        let underlying: Error
        var retryAfter: String?
    }

    /// Runs `body` until it succeeds, throws something other than `Retryable`, or runs out of
    /// attempts — at which point the last `Retryable`'s underlying error surfaces, so callers
    /// never see this type.
    /// `isolation` inherits the caller's context so the body isn't sent across a boundary —
    /// the callers hold non-Sendable closures and DTOs.
    func attempting<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await body()
            } catch let retryable as Retryable {
                guard attempt < attempts - 1 else { throw retryable.underlying }
                try await Task.sleep(for: delay(forAttempt: attempt, retryAfter: retryable.retryAfter))
                attempt += 1
            }
        }
    }
}

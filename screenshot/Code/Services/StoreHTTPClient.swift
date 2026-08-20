import Foundation

/// Transport-level failure, before it is mapped onto a store's own error type.
nonisolated enum StoreHTTPError: Error {
    case invalidURL
    case nonHTTPResponse
    case status(Int, message: String?)
    case transport(Error)
}

/// The bearer-token JSON request both store API clients make.
///
/// App Store Connect and Google Play had byte-for-byte the same 40-line procedure — build the
/// URL, attach the bearer token, optionally attach a body and content type, run it, reject a
/// non-HTTP response, range-check the status, and pull a human message out of the error body.
/// Only the *inputs* differ, so they become closures rather than branches: each store supplies
/// its own error-body walker and any extra headers, and maps `StoreHTTPError` onto the
/// `LocalizedError` enum it already ships (which keeps every localized string where it is).
nonisolated struct StoreHTTPClient {
    let baseURL: String
    let session: URLSession
    /// Fetched per request — both stores cache internally and refresh on expiry.
    let bearerToken: () async throws -> String
    /// Pulls a human-readable message out of this store's error-body shape.
    let errorMessage: @Sendable (Data) -> String?
    let retryPolicy: StoreRetryPolicy

    init(
        baseURL: String,
        session: URLSession,
        bearerToken: @escaping () async throws -> String,
        errorMessage: @escaping @Sendable (Data) -> String?,
        retryPolicy: StoreRetryPolicy = StoreRetryPolicy()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.bearerToken = bearerToken
        self.errorMessage = errorMessage
        self.retryPolicy = retryPolicy
    }

    /// `.shared` cannot be configured, so a wedged upload hangs for its default seven-day
    /// resource timeout. One session for both stores, shared rather than minted per caller so
    /// they pool connections instead of each holding their own.
    ///
    /// Deliberately not `waitsForConnectivity`: the retry loop above already absorbs a blip,
    /// with backoff and a bounded budget, whereas waiting parks the upload for the resource
    /// timeout with nothing on screen and then reports a timeout instead of "you are offline".
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// `bypassCache` is for reads used to verify a write made moments earlier: a cached
    /// pre-mutation response otherwise looks like the write silently failed.
    func data(
        method: String,
        path: String,
        body: Data? = nil,
        contentType: String? = nil,
        extraHeaders: [String: String] = [:],
        bypassCache: Bool = false,
        retryPolicy overridePolicy: StoreRetryPolicy? = nil
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw StoreHTTPError.invalidURL
        }

        let retryPolicy = overridePolicy ?? self.retryPolicy
        return try await retryPolicy.attempting {
            do {
                // The token is minted per attempt on purpose: a retry that straddles an expiry
                // must not resend the stale bearer.
                let (data, response) = try await perform(
                    url: url,
                    method: method,
                    body: body,
                    contentType: contentType,
                    extraHeaders: extraHeaders,
                    bypassCache: bypassCache
                )
                guard (200..<300).contains(response.statusCode) else {
                    let failure = StoreHTTPError.status(response.statusCode, message: errorMessage(data))
                    guard retryPolicy.allowsRetry(status: response.statusCode, method: method) else {
                        throw failure
                    }
                    throw StoreRetryPolicy.Retryable(
                        underlying: failure,
                        retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                    )
                }
                return data
            } catch let StoreHTTPError.transport(underlying) {
                guard retryPolicy.allowsRetry(transportError: underlying, method: method) else {
                    throw StoreHTTPError.transport(underlying)
                }
                throw StoreRetryPolicy.Retryable(underlying: StoreHTTPError.transport(underlying))
            }
            // A bearer that cannot be minted and a non-HTTP response both propagate untouched:
            // repeating either would fail identically.
        }
    }

    private func perform(
        url: URL,
        method: String,
        body: Data?,
        contentType: String?,
        extraHeaders: [String: String],
        bypassCache: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("Bearer \(try await bearerToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StoreHTTPError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw StoreHTTPError.nonHTTPResponse
        }
        return (data, http)
    }
}

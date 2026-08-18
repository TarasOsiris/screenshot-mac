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

    init(
        baseURL: String,
        session: URLSession,
        bearerToken: @escaping () async throws -> String,
        errorMessage: @escaping @Sendable (Data) -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.bearerToken = bearerToken
        self.errorMessage = errorMessage
    }

    /// `bypassCache` is for reads used to verify a write made moments earlier: a cached
    /// pre-mutation response otherwise looks like the write silently failed.
    func data(
        method: String,
        path: String,
        body: Data? = nil,
        contentType: String? = nil,
        extraHeaders: [String: String] = [:],
        bypassCache: Bool = false
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw StoreHTTPError.invalidURL
        }

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
        guard (200..<300).contains(http.statusCode) else {
            throw StoreHTTPError.status(http.statusCode, message: errorMessage(data))
        }
        return data
    }
}

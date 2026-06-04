import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Resolves a public App Store icon URL for a given bundle identifier by querying
/// the unauthenticated iTunes lookup endpoint. Results are cached in memory for the
/// session. Unpublished apps return nil — callers should fall back to a placeholder.
actor AppStoreConnectIconFetcher {
    static let shared = AppStoreConnectIconFetcher()

    private var cache: [String: URL?] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private var imageCache: [String: NSImage] = [:]
    private var imageInflight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches and decodes the icon once per bundle id, caching the decoded image for the
    /// session. Multiple views (e.g. the iPad wizard's per-step headers) share one decode
    /// instead of each `AsyncImage` re-loading the same artwork.
    func icon(forBundleId bundleId: String) async -> NSImage? {
        if let cached = imageCache[bundleId] { return cached }
        if let task = imageInflight[bundleId] { return await task.value }

        let task = Task { [session] () -> NSImage? in
            guard let url = await iconURL(forBundleId: bundleId) else { return nil }
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        imageInflight[bundleId] = task
        let result = await task.value
        imageInflight[bundleId] = nil
        if let result { imageCache[bundleId] = result }
        return result
    }

    func iconURL(forBundleId bundleId: String) async -> URL? {
        if let cached = cache[bundleId] { return cached }
        if let task = inflight[bundleId] { return await task.value }

        let task = Task { [session] () -> URL? in
            guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else {
                return nil
            }
            components.queryItems = [
                URLQueryItem(name: "bundleId", value: bundleId),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let url = components.url else { return nil }

            do {
                let (data, _) = try await session.data(from: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first else { return nil }
                let urlString = (first["artworkUrl512"] as? String)
                    ?? (first["artworkUrl100"] as? String)
                return urlString.flatMap(URL.init(string:))
            } catch {
                return nil
            }
        }

        inflight[bundleId] = task
        let result = await task.value
        inflight[bundleId] = nil
        cache[bundleId] = result
        return result
    }
}

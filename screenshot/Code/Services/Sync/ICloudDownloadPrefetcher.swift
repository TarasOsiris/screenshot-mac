import Foundation

/// Which of the metadata query's not-yet-downloaded items to actually ask the file provider for.
///
/// The query republishes the same placeholders on every progress tick, so without this the app
/// re-issues one synchronous XPC per placeholder per tick.
nonisolated struct DownloadRequestThrottle {
    var reRequestInterval: TimeInterval = 60
    var maxPerPass: Int = 24
    var maxTrackedURLs: Int = 2_000

    private var lastRequested: [URL: Date] = [:]

    var trackedCount: Int { lastRequested.count }

    /// URLs cut off by `maxPerPass` are deliberately not recorded, so the next pass picks them up.
    mutating func urlsToRequest(from candidates: some Sequence<URL>, now: Date = .now) -> [URL] {
        var selected: [URL] = []
        for url in candidates {
            guard selected.count < maxPerPass else { break }
            if let last = lastRequested[url], now.timeIntervalSince(last) < reRequestInterval { continue }
            lastRequested[url] = now
            selected.append(url)
        }
        pruneIfOverBudget()
        return selected
    }

    mutating func removeAll() {
        lastRequested.removeAll()
    }

    /// Trimming only at twice the budget keeps this amortized — trimming to exactly `maxTrackedURLs`
    /// would re-sort the whole map on every subsequent pass.
    private mutating func pruneIfOverBudget() {
        guard lastRequested.count > maxTrackedURLs * 2 else { return }
        let survivors = lastRequested.sorted { $0.value > $1.value }.prefix(maxTrackedURLs)
        lastRequested = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
    }
}

/// Runs `startDownloadingUbiquitousItem` — a synchronous XPC round trip to the file provider — on
/// its own serial queue.
///
/// The queue is load-bearing rather than tidy: doing this work on the metadata query's
/// `operationQueue` would make `NSMetadataQuery.stop()`, which is called from the main actor on
/// iCloud disable, block behind an in-flight batch.
nonisolated final class ICloudDownloadPrefetcher: @unchecked Sendable {

    private let queue = DispatchQueue(label: "xyz.tleskiv.screenshot.icloud.prefetch", qos: .utility)
    private let stateLock = NSLock()
    private var isCancelled = false
    private var throttle = DownloadRequestThrottle()

    func request(_ candidates: [URL]) {
        guard !candidates.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let urls = stateLock.withLock {
                isCancelled ? [] : throttle.urlsToRequest(from: candidates)
            }
            guard !urls.isEmpty else { return }

            let interval = PerfSignpost.begin("ICloudMonitor.prefetchRequest", "urls=\(urls.count)")
            defer { PerfSignpost.end("ICloudMonitor.prefetchRequest", interval) }
            for url in urls {
                guard !stateLock.withLock({ isCancelled }) else { return }
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
    }

    func cancel() {
        stateLock.withLock {
            isCancelled = true
            throttle.removeAll()
        }
    }
}

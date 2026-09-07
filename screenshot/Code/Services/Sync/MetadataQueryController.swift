import Foundation

/// Owns the `NSMetadataQuery` that watches the iCloud container, and the queue it reports on.
///
/// With no `operationQueue`, the query posts its notifications on the run loop that started it —
/// the main one — which is what made the update handler a main-thread workload (Sentry
/// SCREENSHOT-BRO-1F). The query lives here rather than on `ICloudMonitor` because
/// `NSMetadataQuery` isn't `Sendable`: teardown has to hop a *Sendable* box to the main thread,
/// not the query itself.
nonisolated final class MetadataQueryController: NSObject, @unchecked Sendable {

    private let query = NSMetadataQuery()
    private let queue = OperationQueue()
    private let onItems: @Sendable ([UbiquityItemProgress]) -> Void

    private let stateLock = NSLock()
    private var isStopped = false

    init(rootURL: URL, onItems: @escaping @Sendable ([UbiquityItemProgress]) -> Void) {
        self.onItems = onItems
        super.init()

        // Serial: concurrent delivery would interleave the nested disableUpdates/enableUpdates
        // counters below. Utility rather than background, which iOS throttles hard while the user
        // is watching a "Downloading…" label.
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility

        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, rootURL.path)
        query.operationQueue = queue

        for name in [Notification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(queryDidUpdate(_:)),
                name: name,
                object: query
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// `start()` needs a live run loop, so both ends stay on the main thread.
    func start() {
        if Thread.isMainThread {
            query.start()
        } else {
            DispatchQueue.main.async { self.query.start() }
        }
    }

    func stop() {
        stateLock.withLock { isStopped = true }
        NotificationCenter.default.removeObserver(self)
        if Thread.isMainThread {
            stopQuery()
        } else {
            DispatchQueue.main.async { self.stopQuery() }
        }
    }

    private func stopQuery() {
        query.disableUpdates()
        query.stop()
    }

    /// Runs on `queue`. Nothing here may block: `NSMetadataQuery.stop()` synchronizes with
    /// in-flight processing on this queue, and `stop()` is called from the main actor.
    @objc private func queryDidUpdate(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        guard !stateLock.withLock({ isStopped }) else { return }

        query.disableUpdates()
        defer { query.enableUpdates() }

        let resultCount = query.resultCount
        let interval = PerfSignpost.begin("ICloudMonitor.metadataScan", "items=\(resultCount)")
        // Settled items carry no percentages and need no download, so they can't affect the status
        // or the prefetch — dropping them here keeps the per-tick array near-empty once sync is
        // quiet, rather than one struct per file in the container.
        var items: [UbiquityItemProgress] = []
        query.enumerateResults { object, _, _ in
            if let item = object as? NSMetadataItem,
               let progress = ICloudSyncProgress.progress(from: item), progress.isInFlight {
                items.append(progress)
            }
        }
        PerfSignpost.end("ICloudMonitor.metadataScan", interval)

        onItems(items)
    }
}

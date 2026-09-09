import Foundation

nonisolated final class ICloudMonitor: NSObject, NSFilePresenter, @unchecked Sendable {

    private let rootURL: URL
    var presentedItemURL: URL? { rootURL }
    let presentedItemOperationQueue = OperationQueue()

    var onRemoteChange: (@MainActor @Sendable () -> Void)?
    var onSyncStatusChange: (@MainActor @Sendable (SyncStatus) -> Void)?
    /// A file under some project's `resources/` appeared or changed — most usefully, a download
    /// landed. Coalesced rather than per-URL: the only consumer re-reads what it is still missing.
    var onResourcesDidChange: (@MainActor @Sendable () -> Void)?

    private var recentWriteURLs: Set<URL> = []
    private let writeURLLock = NSLock()

    private var queryController: MetadataQueryController?
    private var prefetcher: ICloudDownloadPrefetcher?

    /// Every read or write of the index mod-date runs here, which is what makes a save's snapshot
    /// and the debounced remote-change check ordered rather than racing. The stat itself can block
    /// on the file provider, so it must not be on the main thread either.
    private let workQueue = DispatchQueue(label: "xyz.tleskiv.screenshot.icloud.monitor", qos: .utility)
    private var lastKnownIndexModDate: Date?

    private var debounceTimer: DispatchWorkItem?
    private var resourceDebounceTimer: DispatchWorkItem?
    private let debounceLock = NSLock()
    private let debounceInterval: TimeInterval = 1.0

    private var lastPublishedStatus: SyncStatus = .idle
    private var isStopped = false
    private let statusLock = NSLock()

    init(url: URL) {
        rootURL = url
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue.qualityOfService = .utility
    }

    deinit {
        cancelDebounceTimer()
        stopMonitoring()
    }

    // MARK: - Start / Stop

    func startMonitoring() {
        statusLock.withLock {
            isStopped = false
            lastPublishedStatus = .idle
        }
        NSFileCoordinator.addFilePresenter(self)
        workQueue.async { [weak self] in self?.snapshotIndexModDate() }

        let prefetcher = ICloudDownloadPrefetcher()
        self.prefetcher = prefetcher
        let controller = MetadataQueryController(rootURL: rootURL) { [weak self] items in
            prefetcher.request(items.compactMap { $0.isDownloaded ? nil : $0.url })
            self?.ingest(items)
        }
        queryController = controller
        controller.start()
    }

    func stopMonitoring() {
        // Before anything else: a metadata pass may already be mid-flight on the query's queue,
        // and its publish would otherwise land after the caller has reset the label to idle.
        statusLock.withLock { isStopped = true }
        NSFileCoordinator.removeFilePresenter(self)
        prefetcher?.cancel()
        prefetcher = nil
        queryController?.stop()
        queryController = nil
        cancelDebounceTimer()
    }

    private func cancelDebounceTimer() {
        debounceLock.withLock {
            debounceTimer?.cancel()
            debounceTimer = nil
            resourceDebounceTimer?.cancel()
            resourceDebounceTimer = nil
        }
    }

    /// Ask the file provider for specific items ahead of the query's opportunistic pass. Returns
    /// immediately; the synchronous XPC runs on the prefetcher's own queue.
    func requestDownload(_ urls: [URL]) {
        prefetcher?.request(urls)
    }

    /// Mark URLs as own writes so we can ignore the resulting NSFilePresenter callbacks.
    /// Call this BEFORE writing so `presentedSubitemDidChange` can filter own writes.
    func recordOwnWrite(_ urls: [URL]) {
        writeURLLock.withLock {
            for url in urls { recentWriteURLs.insert(url) }
        }

        // Clear after a short delay — remote changes arrive later
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.writeURLLock.withLock {
                for url in urls { self?.recentWriteURLs.remove(url) }
            }
        }
    }

    /// Update the index mod-date snapshot AFTER writing, so `hasIndexChanged()`
    /// correctly returns false for our own saves. Returns before the stat runs.
    func snapshotAfterWrite() {
        workQueue.async { [weak self] in self?.snapshotIndexModDate() }
    }

    // MARK: - NSFilePresenter

    func presentedSubitemDidChange(at url: URL) {
        guard !isOwnWrite(url) else { return }
        noteResourceChange(at: url)
        scheduleDebouncedReload()
    }

    func presentedItemDidChange() {
        // The debounced reload checks hasIndexChanged(), which catches own writes
        scheduleDebouncedReload()
    }

    private func isOwnWrite(_ url: URL) -> Bool {
        writeURLLock.withLock { recentWriteURLs.contains(url) }
    }

    func presentedSubitemDidAppear(at url: URL) {
        noteResourceChange(at: url)
        scheduleDebouncedReload()
    }

    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        scheduleDebouncedReload()
        completionHandler(nil)
    }

    // MARK: - Sync progress

    /// One full metadata pass — items missing from `items` have settled or are gone, so the status
    /// is recomputed from scratch rather than accumulated. Runs on the caller's queue (the query's,
    /// which is serial and off-main); tests call it directly.
    func ingest(_ items: [UbiquityItemProgress]) {
        let status = ICloudSyncProgress.status(for: items)
        let (changed, crossedIdle) = statusLock.withLock { () -> (Bool, Bool) in
            guard !isStopped, status != lastPublishedStatus else { return (false, false) }
            let wasIdle = lastPublishedStatus == .idle
            lastPublishedStatus = status
            return (true, wasIdle || status == .idle)
        }
        guard changed else { return }

        if crossedIdle {
            CrashReportingService.breadcrumb(.sync, status == .idle ? "iCloud transfer idle" : "iCloud transfer started")
        }
        // A second source for the resource hook, independent of the subitem callbacks' path shape:
        // transfers going quiet is the moment anything still unresolved is worth re-reading.
        if crossedIdle, status == .idle {
            DispatchQueue.main.async { [weak self] in
                guard let self, !statusLock.withLock({ isStopped }) else { return }
                MainActor.assumeIsolated { self.onResourcesDidChange?() }
            }
        }
        DispatchQueue.main.async { [weak self] in
            // Re-checked on the main thread: `stopMonitoring` may have run between the hop being
            // enqueued and it landing, and the caller resets the published label itself.
            guard let self, !statusLock.withLock({ isStopped }) else { return }
            MainActor.assumeIsolated { self.onSyncStatusChange?(status) }
        }
    }

    // MARK: - Change Detection

    /// Both of these run on `workQueue`, which is what keeps `lastKnownIndexModDate` consistent
    /// without a lock — a save's snapshot can't land between the stat and the compare below.
    private func snapshotIndexModDate() {
        lastKnownIndexModDate = PersistenceService.modificationDate(of: PersistenceService.indexURL)
    }

    private func hasIndexChanged() -> Bool {
        let currentDate = PersistenceService.modificationDate(of: PersistenceService.indexURL)
        guard currentDate != lastKnownIndexModDate else { return false }
        lastKnownIndexModDate = currentDate
        return true
    }

    // MARK: - Private

    /// `hasIndexChanged()` gates the reload, and a screenshot arriving never touches the index —
    /// which is why a resource that finished downloading used to reach nothing at all.
    private func noteResourceChange(at url: URL) {
        guard url.deletingLastPathComponent().lastPathComponent == PersistenceService.resourcesDirName else { return }
        schedule(\.resourceDebounceTimer) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onResourcesDidChange?() }
            }
        }
    }

    private func scheduleDebouncedReload() {
        schedule(\.debounceTimer) { [weak self] in
            guard let self, hasIndexChanged() else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onRemoteChange?() }
            }
        }
    }

    /// NSFilePresenter callbacks arrive on a background operation queue, so the shared work-item
    /// reference is guarded against concurrent cancel/replace.
    private func schedule(_ timer: ReferenceWritableKeyPath<ICloudMonitor, DispatchWorkItem?>, _ body: @escaping () -> Void) {
        let task = DispatchWorkItem(block: body)
        debounceLock.withLock {
            self[keyPath: timer]?.cancel()
            self[keyPath: timer] = task
        }
        workQueue.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }
}

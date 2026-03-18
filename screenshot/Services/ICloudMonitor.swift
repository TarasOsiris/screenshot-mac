import Foundation

enum SyncStatus: Equatable {
    case idle
    case uploading(Double)
    case downloading(Double)
}

final class ICloudMonitor: NSObject, NSFilePresenter, @unchecked Sendable {

    var presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()

    var onRemoteChange: (() -> Void)?
    private(set) var syncStatus: SyncStatus = .idle

    private var recentWriteURLs: Set<URL> = []
    private let writeURLLock = NSLock()

    private var metadataQuery: NSMetadataQuery?
    private var debounceTimer: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 1.0

    /// Track last-known mod dates of the index and active project payload files.
    private var lastKnownTrackedModDates: [URL: Date] = [:]

    override init() {
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue.qualityOfService = .utility
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Start / Stop

    func startMonitoring(url: URL) {
        presentedItemURL = url
        NSFileCoordinator.addFilePresenter(self)
        snapshotTrackedFileDates()
        startMetadataQuery()
    }

    func stopMonitoring() {
        NSFileCoordinator.removeFilePresenter(self)
        stopMetadataQuery()
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    /// Mark URLs as own writes so we can ignore the resulting NSFilePresenter callbacks.
    /// Call this BEFORE writing so `presentedSubitemDidChange` can filter own writes.
    func recordOwnWrite(_ urls: [URL]) {
        writeURLLock.lock()
        for url in urls { recentWriteURLs.insert(url) }
        writeURLLock.unlock()

        // Clear after a short delay — remote changes arrive later
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.writeURLLock.lock()
            for url in urls { self?.recentWriteURLs.remove(url) }
            self?.writeURLLock.unlock()
        }
    }

    /// Update the index mod-date snapshot AFTER writing, so `hasIndexChanged()`
    /// correctly returns false for our own saves.
    func snapshotAfterWrite() {
        snapshotTrackedFileDates()
    }

    func setTrackedProjectDataURL(_ url: URL?) {
        let previousURLs = Set(trackedFileURLs)
        trackedProjectDataURL = url
        for trackedURL in previousURLs.subtracting(trackedFileURLs) {
            lastKnownTrackedModDates.removeValue(forKey: trackedURL)
        }
        snapshotTrackedFileDates()
    }

    // MARK: - NSFilePresenter

    func presentedSubitemDidChange(at url: URL) {
        guard !isOwnWrite(url) else { return }
        scheduleDebouncedReload()
    }

    func presentedItemDidChange() {
        // The debounced reload checks hasIndexChanged(), which catches own writes
        scheduleDebouncedReload()
    }

    private func isOwnWrite(_ url: URL) -> Bool {
        writeURLLock.lock()
        defer { writeURLLock.unlock() }
        return recentWriteURLs.contains(url)
    }

    func presentedSubitemDidAppear(at url: URL) {
        scheduleDebouncedReload()
    }

    func accommodatePresentedSubitemDeletion(at url: URL) async throws {
        scheduleDebouncedReload()
    }

    // MARK: - Metadata Query (upload/download progress)

    private func startMetadataQuery() {
        guard let rootURL = presentedItemURL else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@",
                                       NSMetadataItemPathKey,
                                       rootURL.path)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        metadataQuery = query
        query.start()
    }

    private func stopMetadataQuery() {
        metadataQuery?.stop()
        metadataQuery?.disableUpdates()
        NotificationCenter.default.removeObserver(self)
        metadataQuery = nil
    }

    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        guard let query = metadataQuery else { return }

        query.disableUpdates()
        defer { query.enableUpdates() }

        var totalUploading = 0.0
        var totalDownloading = 0.0
        var uploadCount = 0
        var downloadCount = 0

        for item in query.results {
            guard let mdItem = item as? NSMetadataItem else { continue }

            if let uploadPercent = mdItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double,
               uploadPercent < 100 {
                totalUploading += uploadPercent / 100.0
                uploadCount += 1
            }
            if let downloadPercent = mdItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double,
               downloadPercent < 100 {
                totalDownloading += downloadPercent / 100.0
                downloadCount += 1
            }

            // Trigger download for items not yet downloaded
            if let status = mdItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
               status == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded,
               let url = mdItem.value(forAttribute: NSMetadataItemURLKey) as? URL {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }

        let newStatus: SyncStatus
        if downloadCount > 0 {
            newStatus = .downloading(totalDownloading / Double(downloadCount))
        } else if uploadCount > 0 {
            newStatus = .uploading(totalUploading / Double(uploadCount))
        } else {
            newStatus = .idle
        }

        DispatchQueue.main.async { [weak self] in
            self?.syncStatus = newStatus
        }
    }

    // MARK: - Change Detection

    private var indexFileURL: URL {
        PersistenceService.indexURL
    }

    private var trackedProjectDataURL: URL?

    private var trackedFileURLs: [URL] {
        var urls = [indexFileURL]
        if let trackedProjectDataURL {
            urls.append(trackedProjectDataURL)
        }
        return urls
    }

    private func snapshotTrackedFileDates() {
        for url in trackedFileURLs {
            lastKnownTrackedModDates[url] = trackedModificationDate(for: url)
        }
    }

    /// Returns true if any tracked file has been modified since our last snapshot.
    private func hasTrackedFileChanged() -> Bool {
        for url in trackedFileURLs {
            if trackedModificationDate(for: url) != lastKnownTrackedModDates[url] {
                return true
            }
        }
        return false
    }

    private func trackedModificationDate(for url: URL) -> Date {
        modificationDate(for: url) ?? .distantPast
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - Private

    private func scheduleDebouncedReload() {
        debounceTimer?.cancel()
        let task = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.hasTrackedFileChanged() else { return }
                self.snapshotTrackedFileDates()
                self.onRemoteChange?()
            }
        }
        debounceTimer = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }
}

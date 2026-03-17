import Foundation

/// Monitors iCloud Drive for remote changes to project files using NSMetadataQuery.
final class ICloudMonitor: NSObject {
    private var query: NSMetadataQuery?
    private var debounceTask: DispatchWorkItem?

    /// Called when remote changes are detected.
    var onRemoteChange: (() -> Void)?

    /// Timestamp of the last local save, used to ignore self-triggered updates.
    var lastLocalSaveDate: Date?

    override init() {
        super.init()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        self.query = query
    }

    private func stopMonitoring() {
        query?.stop()
        query = nil
        debounceTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.handleRemoteChange()
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func handleRemoteChange() {
        if let lastSave = lastLocalSaveDate,
           Date().timeIntervalSince(lastSave) < 2.0 {
            return
        }
        onRemoteChange?()
    }
}

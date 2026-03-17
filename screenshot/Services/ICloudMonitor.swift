import Foundation

/// Monitors iCloud Drive for remote changes to project files using NSMetadataQuery.
final class ICloudMonitor: NSObject {
    private var query: NSMetadataQuery?
    private var debounceTask: DispatchWorkItem?

    /// Called when remote changes are detected.
    var onRemoteChange: (() -> Void)?

    /// Modification dates of files we last wrote, keyed by file path.
    /// Used to distinguish our own saves from genuine remote changes.
    private var lastSavedFileDates: [String: Date] = [:]

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

    private func modificationDate(atPath path: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    private func handleRemoteChange() {
        // Check if any monitored files have actually changed since our last save.
        // If all file modification dates match what we wrote, this is our own
        // save echoed back by iCloud — not a remote change.
        if !lastSavedFileDates.isEmpty {
            let allUnchanged = lastSavedFileDates.allSatisfy { path, savedDate in
                guard let modDate = modificationDate(atPath: path) else { return false }
                return abs(modDate.timeIntervalSince(savedDate)) < 0.01
            }
            if allUnchanged { return }
        }
        onRemoteChange?()
    }

    /// Record the current modification dates of the given file URLs.
    /// Replaces all previously tracked files — only the active project's files are tracked.
    func recordSavedFiles(_ urls: [URL]) {
        var newDates: [String: Date] = [:]
        for url in urls {
            let path = url.path
            if let modDate = modificationDate(atPath: path) {
                newDates[path] = modDate
            }
        }
        lastSavedFileDates = newDates
    }
}

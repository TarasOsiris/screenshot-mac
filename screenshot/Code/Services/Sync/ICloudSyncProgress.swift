import Foundation

nonisolated enum SyncStatus: Equatable {
    case idle
    case uploading(Double)
    case downloading(Double)

    /// True while iCloud is uploading or downloading (i.e. sync is in progress).
    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }
}

/// One ubiquitous item's transfer state, lifted out of `NSMetadataItem` so the progress math can
/// be exercised without a live query.
nonisolated struct UbiquityItemProgress: Sendable, Equatable {
    let url: URL
    let percentUploaded: Double?
    let percentDownloaded: Double?
    let isDownloaded: Bool

    /// False for a settled item: fully transferred, and present locally.
    var isInFlight: Bool {
        !isDownloaded
            || (percentUploaded.map { $0 < 100 } ?? false)
            || (percentDownloaded.map { $0 < 100 } ?? false)
    }

    init(url: URL, percentUploaded: Double? = nil, percentDownloaded: Double? = nil, isDownloaded: Bool = true) {
        self.url = url
        self.percentUploaded = percentUploaded
        self.percentDownloaded = percentDownloaded
        self.isDownloaded = isDownloaded
    }
}

nonisolated enum ICloudSyncProgress {

    static func progress(from item: NSMetadataItem) -> UbiquityItemProgress? {
        guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
        let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        return UbiquityItemProgress(
            url: url,
            percentUploaded: item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double,
            percentDownloaded: item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double,
            isDownloaded: status != NSMetadataUbiquitousItemDownloadingStatusNotDownloaded
        )
    }

    /// Averaged fraction over the items still in flight, downloads taking precedence.
    ///
    /// Quantized to whole percent because the labels render `Int(fraction * 100)` — a finer value
    /// only produces publishes that change no pixel, and quantizing here is what makes `!=` a
    /// correct change test for the caller.
    static func status(for items: some Sequence<UbiquityItemProgress>) -> SyncStatus {
        var totalUploading = 0.0
        var totalDownloading = 0.0
        var uploadCount = 0
        var downloadCount = 0

        for item in items {
            if let percent = item.percentUploaded, percent < 100 {
                totalUploading += percent / 100.0
                uploadCount += 1
            }
            if let percent = item.percentDownloaded, percent < 100 {
                totalDownloading += percent / 100.0
                downloadCount += 1
            }
        }

        if downloadCount > 0 {
            return .downloading(quantized(totalDownloading / Double(downloadCount)))
        }
        if uploadCount > 0 {
            return .uploading(quantized(totalUploading / Double(uploadCount)))
        }
        return .idle
    }

    private static func quantized(_ fraction: Double) -> Double {
        (fraction * 100).rounded() / 100
    }
}

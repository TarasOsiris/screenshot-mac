import Foundation
@testable import Screenshot_Bro
import Testing

struct ICloudSyncProgressTests {

    private func item(
        _ name: String,
        uploaded: Double? = nil,
        downloaded: Double? = nil,
        isDownloaded: Bool = true
    ) -> UbiquityItemProgress {
        UbiquityItemProgress(
            url: URL(fileURLWithPath: "/tmp/icloud/\(name)"),
            percentUploaded: uploaded,
            percentDownloaded: downloaded,
            isDownloaded: isDownloaded
        )
    }

    @Test func emptyIsIdle() {
        #expect(ICloudSyncProgress.status(for: [UbiquityItemProgress]()) == .idle)
    }

    @Test func fullyTransferredIsIdle() {
        let items = [item("a", uploaded: 100, downloaded: 100), item("b", uploaded: 100, downloaded: 100)]
        #expect(ICloudSyncProgress.status(for: items) == .idle)
    }

    @Test func missingPercentagesAreIdle() {
        #expect(ICloudSyncProgress.status(for: [item("a"), item("b")]) == .idle)
    }

    @Test func uploadingReportsAveragedFraction() {
        let items = [item("a", uploaded: 20), item("b", uploaded: 60), item("c", uploaded: 100)]
        #expect(ICloudSyncProgress.status(for: items) == .uploading(0.4))
    }

    @Test func downloadingWinsOverUploading() {
        let items = [item("a", uploaded: 10), item("b", downloaded: 50)]
        #expect(ICloudSyncProgress.status(for: items) == .downloading(0.5))
    }

    @Test func fractionIsQuantizedToWholePercent() {
        let items = [item("a", downloaded: 33.3), item("b", downloaded: 33.4)]
        guard case .downloading(let fraction) = ICloudSyncProgress.status(for: items) else {
            Issue.record("expected downloading")
            return
        }
        #expect(fraction == 0.33)
    }

    /// Two ticks that render the same label must compare equal, or every tick republishes.
    @Test func nearbyFractionsCompareEqualAfterQuantizing() {
        let first = ICloudSyncProgress.status(for: [item("a", downloaded: 42.1)])
        let second = ICloudSyncProgress.status(for: [item("a", downloaded: 42.4)])
        #expect(first == second)
    }

    @Test func notDownloadedPlaceholderWithoutPercentStaysIdle() {
        #expect(ICloudSyncProgress.status(for: [item("a", isDownloaded: false)]) == .idle)
    }
}

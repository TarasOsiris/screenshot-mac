import Foundation
@testable import Screenshot_Bro
import Testing

nonisolated private final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [SyncStatus] = []
    private var sawOffMainThread = false

    func record(_ status: SyncStatus) {
        lock.withLock {
            statuses.append(status)
            if !Thread.isMainThread { sawOffMainThread = true }
        }
    }

    var all: [SyncStatus] { lock.withLock { statuses } }
    var everyCallbackWasOnMain: Bool { lock.withLock { !sawOffMainThread } }
}

struct ICloudMonitorPublishTests {

    private let recorder = StatusRecorder()
    /// Stored rather than local so the monitor outlives the publish hop — its last use in a test
    /// body is the `ingest` call, and the hop that follows only holds it weakly.
    private let monitor: ICloudMonitor

    init() {
        let recorder = recorder
        monitor = ICloudMonitor(url: URL(fileURLWithPath: NSTemporaryDirectory()))
        monitor.onSyncStatusChange = { recorder.record($0) }
    }

    private func item(_ name: String, downloaded: Double?) -> UbiquityItemProgress {
        UbiquityItemProgress(url: URL(fileURLWithPath: "/tmp/icloud/\(name)"), percentDownloaded: downloaded)
    }

    /// `ingest` publishes through a main-queue hop, so the assertion has to wait for it.
    private func waitForPublishes(count: Int) async {
        for _ in 0..<40 where recorder.all.count < count {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// For the negative assertions: give an unwanted second publish time to arrive.
    private func waitForQuiet() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test func publishesTheFirstNonIdleStatus() async {
        monitor.ingest([item("a", downloaded: 40)])
        await waitForPublishes(count: 1)

        #expect(recorder.all == [.downloading(0.4)])
    }

    @Test func repeatedIdenticalIngestsPublishOnce() async {
        let items = [item("a", downloaded: 40), item("b", downloaded: 60)]

        monitor.ingest(items)
        monitor.ingest(items)
        monitor.ingest(items)
        await waitForPublishes(count: 1)
        await waitForQuiet()

        #expect(recorder.all.count == 1)
    }

    @Test func aChangeThatRoundsTheSameDoesNotPublishAgain() async {
        monitor.ingest([item("a", downloaded: 42.1)])
        monitor.ingest([item("a", downloaded: 42.4)])
        await waitForPublishes(count: 1)
        await waitForQuiet()

        #expect(recorder.all.count == 1)
    }

    @Test func aRealChangePublishesAgain() async {
        monitor.ingest([item("a", downloaded: 40)])
        monitor.ingest([item("a", downloaded: 90)])
        await waitForPublishes(count: 2)

        #expect(recorder.all == [.downloading(0.4), .downloading(0.9)])
    }

    /// `onSyncStatusChange` is `@MainActor`, so the publish hop is what keeps
    /// `MainActor.assumeIsolated` from trapping.
    @Test func statusIsAlwaysPublishedOnTheMainThread() async {
        monitor.ingest([item("a", downloaded: 25)])
        monitor.ingest([item("a", downloaded: 100)])
        await waitForPublishes(count: 2)

        #expect(recorder.all.count == 2)
        #expect(recorder.everyCallbackWasOnMain)
    }

    /// A pass already in flight when the monitor is torn down must not repaint the label the
    /// caller just reset to idle.
    @Test func aPassThatLandsAfterStopPublishesNothing() async {
        monitor.stopMonitoring()
        monitor.ingest([item("a", downloaded: 40)])
        await waitForQuiet()

        #expect(recorder.all.isEmpty)
    }
}

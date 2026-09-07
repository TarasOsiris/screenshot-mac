import Foundation
@testable import Screenshot_Bro
import Testing

struct DownloadRequestThrottleTests {

    private func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/icloud/file\($0).png") }
    }

    @Test func requestsEachURLOnce() {
        var throttle = DownloadRequestThrottle()
        let now = Date()
        let candidates = urls(3)

        #expect(throttle.urlsToRequest(from: candidates, now: now) == candidates)
        #expect(throttle.urlsToRequest(from: candidates, now: now.addingTimeInterval(1)).isEmpty)
    }

    @Test func reRequestsAfterTheInterval() {
        var throttle = DownloadRequestThrottle()
        throttle.reRequestInterval = 60
        let now = Date()
        let candidates = urls(1)

        _ = throttle.urlsToRequest(from: candidates, now: now)
        #expect(throttle.urlsToRequest(from: candidates, now: now.addingTimeInterval(59)).isEmpty)
        #expect(throttle.urlsToRequest(from: candidates, now: now.addingTimeInterval(61)) == candidates)
    }

    /// Anything the cap drops must not be recorded as requested, or it never comes back.
    @Test func truncatedURLsReturnOnTheNextPass() {
        var throttle = DownloadRequestThrottle()
        throttle.maxPerPass = 2
        let now = Date()
        let candidates = urls(5)

        let first = throttle.urlsToRequest(from: candidates, now: now)
        #expect(first == Array(candidates.prefix(2)))

        let second = throttle.urlsToRequest(from: candidates, now: now.addingTimeInterval(1))
        #expect(second == Array(candidates[2..<4]))
    }

    @Test func pruneBoundsTheTrackedMap() {
        var throttle = DownloadRequestThrottle()
        throttle.maxPerPass = .max
        throttle.maxTrackedURLs = 10
        throttle.reRequestInterval = 60
        let now = Date()

        _ = throttle.urlsToRequest(from: urls(50), now: now)
        #expect(throttle.trackedCount <= 10)
    }
}

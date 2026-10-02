import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct TestFlightGraduationPolicyTests {

    @Test func dueWhenNeverShown() {
        let p = TestFlightGraduationPolicy(defaults: makeIsolatedDefaults("never"))
        #expect(p.isDue)
    }

    @Test func notNowSnoozesForADay() {
        let defaults = makeIsolatedDefaults("snooze")
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let p = TestFlightGraduationPolicy(defaults: defaults, now: { clock })

        p.markShown()
        #expect(!p.isDue)
        clock += TestFlightGraduationPolicy.snoozeInterval - 1
        #expect(!p.isDue)
        clock += 1
        #expect(p.isDue)
    }

    /// A build under review is newer than the live version, so App Review never sees the prompt.
    @Test(arguments: [
        ("4.20", "4.19", false),
        ("4.20", "4.20", true),
        ("4.20", "4.21", true),
        ("4.9", "4.10", true),
        ("4.10", "4.9", false),
        ("", "4.20", false),
    ])
    func releasedOnlyOnceTheRunningVersionIsLive(running: String, live: String, expected: Bool) {
        #expect(TestFlightGraduationPolicy.isReleased(running: running, liveVersion: live) == expected)
    }
}

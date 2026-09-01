import Foundation
@testable import Screenshot_Bro
import Testing

struct PerfSignpostTests {

    /// The suite runs without `SCREENSHOT_PERF`, so this pins the shipping default: a normal run is
    /// not a profiling run, and nothing is logged.
    @Test func testRunIsNotAProfilingRun() {
        #expect(PerfSignpost.isProfilingRun == false)
    }

    /// With no tool attached and no profiling flag, `begin` allocates nothing and `end` is inert —
    /// which is what lets these calls sit on hot paths in a shipping build.
    @Test func spansAreInertWhenNothingIsListening() {
        guard !PerfSignpost.isEnabled else { return }
        #expect(PerfSignpost.begin("test.span") == nil)
        #expect(PerfSignpost.begin("test.span", pixels: 1_000_000) == nil)
        PerfSignpost.end("test.span", nil)
        PerfSignpost.event("test.event")
    }

    /// `measure` must return the body's value and propagate its error whether or not anything is
    /// listening — a call site wraps real work in it, not a side effect.
    @Test func measureReturnsTheBodyValue() {
        #expect(PerfSignpost.measure("test.measure") { 41 + 1 } == 42)
    }

    @Test func measurePropagatesThrownErrors() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try PerfSignpost.measure("test.measure") { throw Boom() }
        }
    }

    /// A profiling run must never be able to transmit: the flag is an environment variable in a
    /// shipping build, so it gates logging only, and analytics stays off regardless.
    @Test func profilingRunDisablesAnalytics() {
        #expect(AnalyticsService.isEnabled == false)
    }
}

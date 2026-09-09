import Foundation
import MCP
@testable import Screenshot_Bro
import Testing

/// Pure, clock-injected, no `AppState` and no App Store Connect — the `MCPSessionState` pattern.
struct MCPJobStateTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func registeringStartsQueuedWithNoStartTime() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .preview, totalUnits: 180, at: epoch)
        let job = registry.job(id)
        #expect(job?.phase == .queued)
        #expect(job?.totalUnits == 180)
        #expect(job?.startedAt == nil)
        #expect(job?.finishedAt == nil)
    }

    @Test func firstUpdateStampsTheStartTime() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .preview, totalUnits: 10, at: epoch)
        registry.update(id, at: epoch.addingTimeInterval(2)) { $0.phase = .rendering }
        #expect(registry.job(id)?.startedAt == epoch.addingTimeInterval(2))
    }

    /// A cancelled or failed job must stay that way. Progress callbacks can still be in flight when
    /// a job goes terminal, and letting one land would resurrect a job the caller was already told
    /// about.
    @Test func terminalPhaseIsAbsorbing() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .apply, totalUnits: 5, at: epoch)
        registry.finish(id, phase: .cancelled, at: epoch.addingTimeInterval(1))
        registry.update(id, at: epoch.addingTimeInterval(2)) { $0.phase = .uploading; $0.completedUnits = 99 }
        #expect(registry.job(id)?.phase == .cancelled)
        #expect(registry.job(id)?.completedUnits == 0)
    }

    @Test func finishingTwiceKeepsTheFirstOutcome() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .apply, totalUnits: 5, at: epoch)
        registry.finish(id, phase: .failed, at: epoch.addingTimeInterval(1)) { $0.errorMessage = "first" }
        registry.finish(id, phase: .succeeded, at: epoch.addingTimeInterval(2)) { $0.errorMessage = "second" }
        #expect(registry.job(id)?.phase == .failed)
        #expect(registry.job(id)?.errorMessage == "first")
    }

    /// Shipped once as `phase: "succeeded"` on an apply that finished 38 of 44 steps and left six
    /// App Store screenshots missing. A caller trusting the phase would have published the gap.
    @Test func aJobThatLostStepsCannotReportSuccess() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .apply, totalUnits: 44, at: epoch)
        registry.update(id, at: epoch) { $0.completedUnits = 38 }
        registry.finish(id, phase: .succeeded, at: epoch.addingTimeInterval(1))
        #expect(registry.job(id)?.phase == .failed)
        #expect(registry.job(id)?.errorMessage?.contains("38") == true)
    }

    @Test func aJobThatCompletedEveryStepReportsSuccess() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .apply, totalUnits: 44, at: epoch)
        registry.update(id, at: epoch) { $0.completedUnits = 44 }
        registry.finish(id, phase: .succeeded, at: epoch.addingTimeInterval(1))
        #expect(registry.job(id)?.phase == .succeeded)
        #expect(registry.job(id)?.errorMessage == nil)
    }

    /// The downgrade must not overwrite a real explanation.
    @Test func theStepBackstopKeepsAnExistingErrorMessage() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .apply, totalUnits: 10, at: epoch)
        registry.finish(id, phase: .succeeded, at: epoch) { $0.errorMessage = "reserve exploded" }
        #expect(registry.job(id)?.phase == .failed)
        #expect(registry.job(id)?.errorMessage == "reserve exploded")
    }

    @Test func elapsedSpansStartToFinish() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .preview, totalUnits: 1, at: epoch)
        registry.update(id, at: epoch) { $0.phase = .rendering }
        registry.finish(id, phase: .succeeded, at: epoch.addingTimeInterval(130))
        #expect(registry.job(id)?.elapsed == 130)
    }

    @Test func cancelMarksIntentWithoutInventingATerminalState() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .apply, totalUnits: 5, at: epoch)
        registry.update(id, at: epoch) { $0.phase = .uploading }
        _ = registry.requestCancel(id, at: epoch.addingTimeInterval(1))
        #expect(registry.job(id)?.cancelRequested == true)
        #expect(registry.job(id)?.phase == .uploading, "the body decides when it has actually stopped")
    }

    @Test func cancellingAnUnknownJobReportsNothing() {
        var registry = MCPJobRegistry()
        #expect(registry.requestCancel("job_nope", at: epoch) == nil)
        #expect(registry.job("job_nope") == nil)
    }

    @Test func terminalResultsExpireAtTheRetentionBoundary() {
        var registry = MCPJobRegistry()
        let id = registry.register(kind: .preview, totalUnits: 1, at: epoch)
        registry.finish(id, phase: .succeeded, at: epoch)

        registry.purge(at: epoch.addingTimeInterval(MCPJobRegistry.resultLifetime - 1))
        #expect(registry.job(id) != nil)

        registry.purge(at: epoch.addingTimeInterval(MCPJobRegistry.resultLifetime))
        #expect(registry.job(id) == nil, "the boundary is inclusive")
    }

    @Test func purgeNeverEvictsARunningJob() {
        var registry = MCPJobRegistry()
        let running = registry.register(kind: .apply, totalUnits: 1, at: epoch)
        registry.update(running, at: epoch) { $0.phase = .uploading }
        for index in 0..<(MCPJobRegistry.capacity + 5) {
            let id = registry.register(kind: .preview, totalUnits: 1, at: epoch)
            registry.finish(id, phase: .succeeded, at: epoch.addingTimeInterval(Double(index)))
        }
        registry.purge(at: epoch.addingTimeInterval(1))
        #expect(registry.job(running) != nil, "a running job's poller must never be stranded")
        #expect(registry.jobs.count <= MCPJobRegistry.capacity + 1)
    }

    @Test func capacityEvictsTheOldestFinishedJobFirst() {
        var registry = MCPJobRegistry()
        var ids: [String] = []
        for index in 0..<(MCPJobRegistry.capacity + 3) {
            let id = registry.register(kind: .preview, totalUnits: 1, at: epoch)
            registry.finish(id, phase: .succeeded, at: epoch.addingTimeInterval(Double(index)))
            ids.append(id)
        }
        registry.purge(at: epoch.addingTimeInterval(1))
        #expect(registry.job(ids[0]) == nil)
        #expect(registry.job(ids[ids.count - 1]) != nil)
    }
}

/// The sizing rules that decide whether a call blocks or becomes a job.
@MainActor
struct MCPSyncJobThresholdTests {
    private func target(templates: Int, localizations: Int) -> ASCUploadTarget {
        ASCUploadTarget(
            versionId: "v1",
            versionLabel: "v",
            rowId: UUID(),
            rowLabel: "r",
            rowSize: CGSize(width: 10, height: 20),
            displayType: .iphone67,
            localizations: (0..<localizations).map { ASCUploadLocalization(id: "l\($0)", label: "l", localeCode: "en") },
            templateCount: templates
        )
    }

    @Test func renderCountIsTemplatesTimesLocalisationsAcrossTargets() {
        let count = MCPToolExecutor.previewRenderCount([target(templates: 9, localizations: 20), target(templates: 3, localizations: 2)])
        #expect(count == 180 + 6)
    }

    /// 36 renders returned fine in the field; 180 timed out. The limit sits above the known-good.
    @Test func autoStaysSynchronousUpToTheLimitAndSwitchesAfterIt() throws {
        let limit = MCPToolExecutor.syncPreviewRenderLimit
        let atLimit = try MCPToolExecutor.decideMode(.auto, units: limit, fitsSync: true, hardLimit: 400, unitName: "renders")
        let overLimit = try MCPToolExecutor.decideMode(.auto, units: limit + 1, fitsSync: false, hardLimit: 400, unitName: "renders")
        #expect(atLimit == .sync)
        #expect(overLimit == .async)
        #expect(limit >= 36, "the largest batch known to succeed must still run inline")
    }

    /// Silently upgrading would hand the caller a job envelope where it expected a plan.
    @Test func explicitSyncAboveTheHardCapIsRejectedRatherThanUpgraded() {
        #expect(throws: MCPToolError.self) {
            try MCPToolExecutor.decideMode(.sync, units: 401, fitsSync: false, hardLimit: 400, unitName: "renders")
        }
    }

    @Test func explicitSyncUnderTheHardCapIsHonouredEvenWhenLarge() throws {
        let mode = try MCPToolExecutor.decideMode(.sync, units: 399, fitsSync: false, hardLimit: 400, unitName: "renders")
        #expect(mode == .sync)
    }

    @Test func explicitAsyncIsHonouredForTheSmallestRequest() throws {
        let mode = try MCPToolExecutor.decideMode(.async, units: 1, fitsSync: true, hardLimit: 400, unitName: "renders")
        #expect(mode == .async)
    }

    @Test func modeDefaultsToAutoAndRejectsNonsense() throws {
        #expect(try MCPToolExecutor.resolveMode(MCPArguments(nil)) == .auto)
        #expect(try MCPToolExecutor.resolveMode(MCPArguments(["mode": .string("async")])) == .async)
        #expect(throws: MCPToolError.self) {
            try MCPToolExecutor.resolveMode(MCPArguments(["mode": .string("eventually")]))
        }
    }
}

@testable import Screenshot_Bro
import Testing

@Suite(.serialized)
struct CrashReportingServiceTests {

    // MARK: - Test-run silence

    @Test func reportingIsDisabledUnderTests() {
        #expect(CrashReportingService.isReportingEnabled == false)
    }

    /// The real guarantee: the host app launched and ran `start()`, and the SDK still never
    /// initialized — so there is no client and no transport to send anything.
    @Test func sentrySDKNeverStartsUnderTests() {
        #expect(CrashReportingService.isActive == false)
    }

    /// A future entry point that lazily initializes the SDK fails here rather than in real data.
    @Test func reportingEntryPointsDoNotStartTheSDK() {
        CrashReportingService.report(.projectDecodeFailed, extra: ["file": "project.json"])
        CrashReportingService.breadcrumb(.app, "test entry point")
        CrashReportingService.setUser(id: "test-user")
        CrashReportingService.setTag("test", for: "storage")
        CrashReportingService.setDocumentContext(["rows": 1])
        #expect(CrashReportingService.isActive == false)
    }

    // MARK: - Failure identifiers

    @Test func failureRawValuesAreUniqueAndNonEmpty() {
        let rawValues = CrashReportingService.Failure.allCases.map(\.rawValue)
        #expect(rawValues.allSatisfy { !$0.isEmpty })
        // Raw values double as Sentry fingerprints — a collision silently merges two unrelated issues.
        #expect(Set(rawValues).count == rawValues.count)
    }

    // MARK: - Path scrubbing

    @Test func scrubbingReplacesUserNameInPath() {
        #expect(
            CrashReportingService.scrubbingPaths("/Users/taras/Library/Containers/app/project.json")
                == "/Users/~/Library/Containers/app/project.json"
        )
    }

    @Test func scrubbingHandlesQuotedAndTrailingPaths() {
        #expect(CrashReportingService.scrubbingPaths("file \"/Users/taras\" missing") == "file \"/Users/~\" missing")
        #expect(CrashReportingService.scrubbingPaths("at /Users/taras") == "at /Users/~")
    }

    @Test func scrubbingReplacesEveryOccurrence() {
        #expect(
            CrashReportingService.scrubbingPaths("copy /Users/alice/a.png to /Users/alice/b.png")
                == "copy /Users/~/a.png to /Users/~/b.png"
        )
    }

    @Test func scrubbingLeavesUnrelatedTextUntouched() {
        #expect(CrashReportingService.scrubbingPaths("no paths here") == "no paths here")
        #expect(CrashReportingService.scrubbingPaths("/var/folders/tmp/x.png") == "/var/folders/tmp/x.png")
        #expect(CrashReportingService.scrubbingPaths("") == "")
    }

    // MARK: - Render-label sanitizing

    @Test func renderLabelElidesTheQuotedRowLabel() {
        #expect(RowRenderer.reportableRenderLabel("showcase row 'Onboarding Flow'") == "showcase row '…'")
        #expect(
            RowRenderer.reportableRenderLabel("export row override background 'My Row' [2]")
                == "export row override background '…' [2]"
        )
    }

    @Test func renderLabelLeavesUnquotedLabelsUntouched() {
        #expect(RowRenderer.reportableRenderLabel("single template shapes [0]") == "single template shapes [0]")
        #expect(RowRenderer.reportableRenderLabel("English") == "English")
    }

    // MARK: - Breadcrumb run coalescing

    @Test func consecutiveIdenticalBreadcrumbsCollapse() {
        CrashReportingService.resetBreadcrumbDeduplication()
        #expect(CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape") == .emit)
        #expect(CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape") == .coalesce)
        #expect(CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape") == .coalesce)
    }

    @Test func differentBreadcrumbEndsTheRunAndSummarizesIt() {
        CrashReportingService.resetBreadcrumbDeduplication()
        _ = CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape")
        _ = CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape")
        _ = CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape")

        // The count is what distinguishes three drags from one — the old behaviour dropped it.
        #expect(
            CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Delete Shape")
                == .summarizeThenEmit(category: .edit, message: "Move Shape", count: 3)
        )
        // The first message is emittable again once something else interrupted the run.
        #expect(CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape") == .emit)
    }

    @Test func runOfOneNeedsNoSummary() {
        CrashReportingService.resetBreadcrumbDeduplication()
        _ = CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape")
        #expect(CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Delete Shape") == .emit)
    }

    @Test func longRunEmitsCheckpoints() {
        CrashReportingService.resetBreadcrumbDeduplication()
        var checkpoints: [Int] = []
        for _ in 0..<120 {
            if case .checkpoint(let count) = CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Move Shape") {
                checkpoints.append(count)
            }
        }
        // A crash mid-run never writes the end-of-run summary, so the checkpoints are the only
        // evidence the run was long.
        #expect(checkpoints == [10, 100])
    }

    @Test func sameMessageInDifferentCategoriesBothEmit() {
        CrashReportingService.resetBreadcrumbDeduplication()
        #expect(CrashReportingService.recordBreadcrumbRun(category: .edit, message: "Reset") == .emit)
        #expect(CrashReportingService.recordBreadcrumbRun(category: .project, message: "Reset") == .emit)
    }

    @Test func flushClosesTheRunAndReportsItsCount() {
        CrashReportingService.resetBreadcrumbDeduplication()
        _ = CrashReportingService.recordBreadcrumbRun(category: .sync, message: "Remote change ignored")
        _ = CrashReportingService.recordBreadcrumbRun(category: .sync, message: "Remote change ignored")

        let flushed = CrashReportingService.flushBreadcrumbRun()
        #expect(flushed?.category == .sync)
        #expect(flushed?.message == "Remote change ignored")
        #expect(flushed?.count == 2)

        // Flushing resets, so the next crumb starts a fresh run.
        #expect(CrashReportingService.flushBreadcrumbRun() == nil)
        #expect(CrashReportingService.recordBreadcrumbRun(category: .sync, message: "Remote change ignored") == .emit)
    }
}

import Testing
@testable import Screenshot_Bro

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
        #expect(ExportService.reportableRenderLabel("showcase row 'Onboarding Flow'") == "showcase row '…'")
        #expect(
            ExportService.reportableRenderLabel("export row override background 'My Row' [2]")
                == "export row override background '…' [2]"
        )
    }

    @Test func renderLabelLeavesUnquotedLabelsUntouched() {
        #expect(ExportService.reportableRenderLabel("single template shapes [0]") == "single template shapes [0]")
        #expect(ExportService.reportableRenderLabel("English") == "English")
    }

    // MARK: - Breadcrumb de-duplication

    @Test func consecutiveIdenticalBreadcrumbsCollapse() {
        CrashReportingService.resetBreadcrumbDeduplication()
        #expect(CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Move Shape"))
        #expect(!CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Move Shape"))
        #expect(!CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Move Shape"))
    }

    @Test func differentBreadcrumbEndsTheRun() {
        CrashReportingService.resetBreadcrumbDeduplication()
        #expect(CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Move Shape"))
        #expect(CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Delete Shape"))
        // The first message is emittable again once something else interrupted the run.
        #expect(CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Move Shape"))
    }

    @Test func sameMessageInDifferentCategoriesBothEmit() {
        CrashReportingService.resetBreadcrumbDeduplication()
        #expect(CrashReportingService.shouldEmitBreadcrumb(category: .edit, message: "Reset"))
        #expect(CrashReportingService.shouldEmitBreadcrumb(category: .project, message: "Reset"))
    }
}

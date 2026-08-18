import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

// The Play upload flow lived in a 139-line extension on a SwiftUI view, so its three outcome
// branches — success, cancellation, failure — had no coverage at all.
@MainActor
struct GPUploadFlowModelTests {

    /// The model holds its document weakly (in the app, AppState outlives the wizard), so tests
    /// must keep it alive themselves — an inline stub would deallocate before the first assertion.
    private final class Harness {
        let model: GPUploadFlowModel
        let uploader: FakeGPUploader
        let document: StubGPDocument

        init(
            uploader: FakeGPUploader = FakeGPUploader(),
            document: StubGPDocument = StubGPDocument(),
            credentials: GooglePlayCredentialsStore? = nil
        ) {
            self.uploader = uploader
            self.document = document
            self.model = GPUploadFlowModel(
                uploader: uploader,
                credentials: credentials ?? GooglePlayCredentialsStore.isolatedForTesting()
            )
            model.bind(document: document)
        }
    }

    private func row(label: String, templates: Int = 2, width: CGFloat = 1080, height: CGFloat = 1920) -> ScreenshotRow {
        ScreenshotRow(
            label: label,
            templates: Array(repeating: ScreenshotTemplate(), count: templates),
            templateWidth: width,
            templateHeight: height
        )
    }

    private func localeState(_ codes: [String]) -> LocaleState {
        var state = LocaleState.default
        state.locales = codes.map { LocaleDefinition(code: $0, label: $0.uppercased()) }
        return state
    }

    // MARK: - Package name

    @Test func prefillTakesThePackageNameTheProjectRemembered() {
        let h = Harness(document: StubGPDocument(savedGooglePlayPackageName: "com.example.app"))
        let model = h.model
        model.prefillPackageName()
        #expect(model.packageName == "com.example.app")
    }

    /// Prefill must not clobber something the user already typed.
    @Test func prefillDoesNotOverwriteWhatTheUserTyped() {
        let h = Harness(document: StubGPDocument(savedGooglePlayPackageName: "com.example.saved"))
        let model = h.model
        model.packageName = "com.example.typed"
        model.prefillPackageName()
        #expect(model.packageName == "com.example.typed")
    }

    @Test func continuingTrimsThePackageNameAndAdvances() {
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        let document = h.document
        model.packageName = "  com.example.app \n"
        model.errorMessage = "stale"

        model.continueToPlan()

        #expect(model.packageName == "com.example.app")
        #expect(model.step == .configuringPlan)
        #expect(model.errorMessage == nil)
        #expect(document.rememberedPackageNames == ["com.example.app"])
    }

    /// A demo run must never write a package name into the user's project.
    @Test func demoModeNeverPersistsThePackageName() {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        credentials.isDemoMode = true
        let h = Harness(credentials: credentials)
        let model = h.model
        let document = h.document

        model.packageName = "com.example.demo"
        model.continueToPlan()

        #expect(document.rememberedPackageNames.isEmpty)
    }

    @Test func anEmptyPackageNameClearsTheStoredOne() {
        let h = Harness(document: StubGPDocument(savedGooglePlayPackageName: "com.old"))
        let model = h.model
        let document = h.document
        model.packageName = "   "
        model.continueToPlan()
        #expect(document.rememberedPackageNames == [String?.none])
    }

    // MARK: - Plan

    @Test func rowPlansCoverEveryRowAndLocale() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "A"), row(label: "B")],
            localeState: localeState(["en", "de", "fr"])
        ))
        let model = h.model

        let plans = model.buildRowPlans()

        #expect(plans.count == 2)
        #expect(plans.allSatisfy { $0.localeTargets.count == 3 })
        #expect(plans.map(\.rowLabel) == ["A", "B"])
    }

    /// A refresh must keep the user's per-row and per-locale choices.
    @Test func rebuildingPreservesEnabledFlags() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "A"), row(label: "B")],
            localeState: localeState(["en", "de"])
        ))
        let model = h.model
        var plans = model.buildRowPlans()
        plans[0].isEnabled = false
        plans[1].localeTargets[1].isEnabled = false

        let rebuilt = model.buildRowPlans(preserving: plans)

        #expect(rebuilt[0].isEnabled == false)
        #expect(rebuilt[1].localeTargets[1].isEnabled == false)
        #expect(rebuilt[1].localeTargets[0].isEnabled)
    }

    @Test func uploadTargetsSkipDisabledRowsAndRowsWithNoLanguages() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "Off"), row(label: "NoLangs"), row(label: "Good")],
            localeState: localeState(["en"])
        ))
        let model = h.model
        var plans = model.buildRowPlans()
        plans[0].isEnabled = false
        plans[1].localeTargets[0].isEnabled = false
        model.rowPlans = plans

        let targets = model.buildUploadTargets()

        #expect(targets.count == 1)
        #expect(targets[0].rowLabel == "Good")
    }

    /// An unlabelled row still needs something to show in the plan and in error messages.
    @Test func anUnlabelledRowGetsAFallbackLabel() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "")], localeState: localeState(["en"])
        ))
        let model = h.model
        model.rowPlans = model.buildRowPlans()
        #expect(model.buildUploadTargets().first?.rowLabel.isEmpty == false)
    }

    // MARK: - Upload outcomes

    private func readyHarness(uploader: FakeGPUploader) -> Harness {
        let h = Harness(uploader: uploader, document: StubGPDocument(
            rows: [row(label: "A", templates: 3)], localeState: localeState(["en", "de"])
        ))
        h.model.packageName = "com.example.app"
        h.model.continueToPlan()
        return h
    }

    @Test func aSuccessfulUploadSummarizesWhatWasSent() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .success(sentForReview: false)
        let h = readyHarness(uploader: uploader)
        let model = h.model

        await model.startUpload()

        #expect(model.step == .done)
        #expect(uploader.callCount == 1)
        #expect(uploader.lastPackageName == "com.example.app")
        let summary = try? #require(model.uploadSummary)
        #expect(summary?.totalScreenshots == 6, "3 templates × 2 languages")
        #expect(summary?.languageCount == 2)
        #expect(model.errorMessage == nil)
        #expect(model.uploadTask == nil, "the task handle is released so the button re-enables")
    }

    /// The summary reports what the service actually did — Google Play can reject the draft flag
    /// and send the edit to review anyway — not what the toggle asked for.
    @Test func theSummaryEchoesTheServiceNotTheToggle() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .success(sentForReview: true)
        let h = readyHarness(uploader: uploader)
        let model = h.model
        model.sendForReview = false

        await model.startUpload()

        #expect(uploader.lastSendForReview == false, "the request carried the toggle")
        #expect(model.uploadSummary?.sentForReview == true, "the summary carries the outcome")
    }

    @Test func cancellationReturnsToThePlanAndSaysTheDraftWasDiscarded() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .cancelled
        let h = readyHarness(uploader: uploader)
        let model = h.model

        await model.startUpload()

        #expect(model.step == .configuringPlan)
        #expect(model.uploadSummary == nil)
        #expect(model.errorMessage?.isEmpty == false)
        #expect(model.errorDetailsText == nil, "a cancellation isn't a failure with details")
    }

    @Test func aFailureReturnsToThePlanWithBothSummaryAndDetails() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .failure(GooglePlayUploadError.noRowsSelected)
        let h = readyHarness(uploader: uploader)
        let model = h.model

        await model.startUpload()

        #expect(model.step == .configuringPlan)
        #expect(model.errorMessage == GooglePlayUploadError.noRowsSelected.summaryDescription)
        let details = try? #require(model.errorDetailsText)
        #expect(details?.contains("Package: com.example.app") == true)
        #expect(model.uploadSummary == nil)
    }

    @Test func uploadRefusesWhenNothingIsSelected() async {
        let uploader = FakeGPUploader()
        let h = Harness(uploader: uploader, document: StubGPDocument(
            rows: [row(label: "A")], localeState: localeState(["en"])
        ))
        let model = h.model
        model.packageName = "com.example.app"
        model.continueToPlan()
        model.rowPlans = model.rowPlans.map { var p = $0; p.isEnabled = false; return p }

        await model.startUpload()

        #expect(uploader.callCount == 0)
        #expect(model.step == .configuringPlan)
        #expect(model.errorMessage?.isEmpty == false)
    }

    @Test func goBackReturnsToThePackageStep() {
        let h = Harness()
        let model = h.model
        model.packageName = "com.example.app"
        model.continueToPlan()
        model.goBack()
        #expect(model.step == .enteringPackage)
    }
}

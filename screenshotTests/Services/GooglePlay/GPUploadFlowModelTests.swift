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
        let verifier: FakeGPPackageVerifier
        let document: StubGPDocument

        init(
            uploader: FakeGPUploader = FakeGPUploader(),
            verifier: FakeGPPackageVerifier = FakeGPPackageVerifier(),
            document: StubGPDocument = StubGPDocument(),
            credentials: GooglePlayCredentialsStore? = nil
        ) {
            self.uploader = uploader
            self.verifier = verifier
            self.document = document
            self.model = GPUploadFlowModel(
                uploader: uploader,
                api: verifier,
                credentials: credentials ?? GooglePlayCredentialsStore.isolatedForTesting(),
                defaults: Self.isolatedDefaults()
            )
            model.bind(document: document)
        }

        /// The recents list is UserDefaults-backed; a test run must not write into the real one.
        static func isolatedDefaults() -> UserDefaults {
            UserDefaults(suiteName: "GPUploadFlowModelTests.\(UUID().uuidString)") ?? .standard
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

    @Test func continuingTrimsThePackageNameAndAdvances() async {
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        let document = h.document
        model.packageName = "  com.example.app \n"
        model.errorMessage = "stale"

        await model.continueToPlan()

        #expect(model.packageName == "com.example.app")
        #expect(model.step == .configuringPlan)
        #expect(model.errorMessage == nil)
        #expect(document.rememberedPackageNames == ["com.example.app"])
        #expect(h.verifier.lastPackageName == "com.example.app", "the trimmed name is what gets probed")
    }

    /// A demo run must never write a package name into the user's project.
    @Test func demoModeNeverPersistsThePackageName() async {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        credentials.isDemoMode = true
        let h = Harness(credentials: credentials)
        let model = h.model
        let document = h.document

        model.packageName = "com.example.demo"
        await model.continueToPlan()

        #expect(document.rememberedPackageNames.isEmpty)
        #expect(model.recentPackageNames.isEmpty, "demo mode stays out of the recents list too")
    }

    /// Demo mode has no API key to check against, so it must still reach the plan step.
    @Test func demoModePrefillsASamplePackageAndVerifies() async {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        credentials.isDemoMode = true
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]), credentials: credentials)
        let model = h.model

        model.prefillPackageName()
        #expect(model.packageName == GooglePlayDemoData.packageName)

        await model.continueToPlan()
        #expect(model.step == .configuringPlan)
    }

    @Test func anEmptyPackageNameGoesNowhere() async {
        let h = Harness(document: StubGPDocument(savedGooglePlayPackageName: "com.old"))
        let model = h.model
        model.packageName = "   "

        await model.continueToPlan()

        #expect(model.step == .enteringPackage)
        #expect(h.verifier.callCount == 0, "an empty name is never worth a round trip")
        #expect(h.document.rememberedPackageNames.isEmpty)
    }

    // MARK: - Package verification

    @Test func aRejectedPackageKeepsTheUserOnTheStepWithTheReason() async {
        let verifier = FakeGPPackageVerifier()
        verifier.error = GooglePlayAPIError.httpError(status: 403, message: "no access")
        let h = Harness(verifier: verifier, document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        model.packageName = "com.example.app"

        await model.continueToPlan()

        #expect(model.step == .enteringPackage)
        #expect(model.packageVerification.isVerified == false)
        if case .failed(let reason) = model.packageVerification {
            #expect(reason.isEmpty == false)
        } else {
            Issue.record("expected a failed verification, got \(model.packageVerification)")
        }
        #expect(h.document.rememberedPackageNames.isEmpty, "a package we can't reach isn't worth remembering")
    }

    /// Play answers "no such app" and "no access" identically, so 403 and 404 must both explain
    /// themselves rather than falling through to a raw HTTP string.
    @Test func permissionAndMissingAppFailuresBothGetTheirOwnMessage() {
        let forbidden = GPUploadFlowModel.verificationFailureMessage(
            for: GooglePlayAPIError.httpError(status: 403, message: "x"))
        let missing = GPUploadFlowModel.verificationFailureMessage(
            for: GooglePlayAPIError.httpError(status: 404, message: "x"))
        let unauthorized = GPUploadFlowModel.verificationFailureMessage(
            for: GooglePlayAPIError.httpError(status: 401, message: "x"))

        #expect(forbidden != missing)
        #expect(unauthorized != forbidden)
        #expect([forbidden, missing, unauthorized].allSatisfy { !$0.contains("403") && !$0.contains("404") })
    }

    @Test func editingThePackageNameDropsAnEarlierVerification() async {
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        model.packageName = "com.example.app"
        await model.verifyPackage()
        #expect(model.packageVerification.isVerified)

        model.packageName = "com.example.other"

        #expect(model.packageVerification.isVerified == false)
    }

    @Test func aMalformedPackageNameFailsWithoutAskingPlay() async {
        let h = Harness()
        let model = h.model
        model.packageName = "not a package"

        await model.verifyPackage()

        #expect(h.verifier.callCount == 0)
        #expect(model.packageVerification.isVerified == false)
    }

    // MARK: - Recents

    @Test func recentsRememberTheMostRecentFirstAndCapTheList() {
        let defaults = Harness.isolatedDefaults()
        for index in 0..<(GooglePlayRecentPackages.limit + 3) {
            GooglePlayRecentPackages.remember("com.example.app\(index)", defaults: defaults)
        }

        let recents = GooglePlayRecentPackages.load(defaults: defaults)

        #expect(recents.count == GooglePlayRecentPackages.limit)
        #expect(recents.first == "com.example.app\(GooglePlayRecentPackages.limit + 2)")
    }

    @Test func reusingAPackageMovesItToTheFrontWithoutDuplicating() {
        let defaults = Harness.isolatedDefaults()
        GooglePlayRecentPackages.remember("com.a", defaults: defaults)
        GooglePlayRecentPackages.remember("com.b", defaults: defaults)
        GooglePlayRecentPackages.remember("com.a", defaults: defaults)

        #expect(GooglePlayRecentPackages.load(defaults: defaults) == ["com.a", "com.b"])
    }

    @Test func aSuccessfulContinueRecordsThePackageInRecents() async {
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        model.packageName = "com.example.app"

        await model.continueToPlan()

        #expect(model.recentPackageNames == ["com.example.app"])
    }

    // MARK: - iPad navigation

    /// The back-swipe pops the path; the model follows it rather than driving it.
    @Test func poppingThePathTakesTheStepBackWithIt() async {
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        var path: [GPUploadStep] = []
        model.navigationDidAdvance = { path.append($0) }
        model.packageName = "com.example.app"

        await model.continueToPlan()
        #expect(path == [.configuringPlan])

        model.errorMessage = "stale"
        model.handlePathChange(from: path, to: [])

        #expect(model.step == .enteringPackage)
        #expect(model.errorMessage == nil, "the failure belonged to the step we left")
    }

    @Test func aPushDoesNotRewindTheStep() async {
        let h = Harness(document: StubGPDocument(rows: [row(label: "A")]))
        let model = h.model
        model.packageName = "com.example.app"
        await model.continueToPlan()

        model.handlePathChange(from: [], to: [.configuringPlan])

        #expect(model.step == .configuringPlan)
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

    /// Play keeps one screenshot set per language, and "en" and "en-US" both reach its en-US
    /// listing — so the wizard opens with one of them off rather than with a blocking error.
    /// The exact code wins over the mapped one.
    @Test func localesThatCollapseOntoOnePlayLanguageStartWithOneEnabled() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "A")],
            localeState: localeState(["en", "uk", "en-US"])
        ))
        let model = h.model

        let targets = model.buildRowPlans()[0].localeTargets

        #expect(targets.map(\.isEnabled) == [false, true, true])
    }

    @Test func aLanguagePlayCannotAcceptStartsOffAndCarriesNoPlayCode() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "A")],
            localeState: localeState(["en", "ar-SA"])
        ))
        let model = h.model

        let targets = model.buildRowPlans()[0].localeTargets

        #expect(targets[1].playLanguageCode == nil)
        #expect(targets[1].isEnabled == false)
        #expect(targets[0].isEnabled)
    }

    /// Demo mode softens the duplicate-language error to a warning, so the upload path cannot
    /// trust validation alone: uploading a Play language twice deletes the first set.
    @Test func uploadTargetsDropUnsupportedLanguagesAndUploadEachPlayLanguageOnce() {
        let h = Harness(document: StubGPDocument(
            rows: [row(label: "A")],
            localeState: localeState(["en", "en-US", "ar-SA"])
        ))
        let model = h.model
        var plans = model.buildRowPlans()
        for index in plans[0].localeTargets.indices {
            plans[0].localeTargets[index].isEnabled = true
        }
        model.rowPlans = plans

        let languages = model.buildUploadTargets().first?.languages ?? []

        #expect(languages.map(\.playCode) == ["en-US"])
        #expect(languages.first?.projectCode == "en", "the first claimant keeps the slot")
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

    private func readyHarness(uploader: FakeGPUploader) async -> Harness {
        let h = Harness(uploader: uploader, document: StubGPDocument(
            rows: [row(label: "A", templates: 3)], localeState: localeState(["en", "de"])
        ))
        h.model.packageName = "com.example.app"
        await h.model.continueToPlan()
        return h
    }

    @Test func aSuccessfulUploadSummarizesWhatWasSent() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .success(sentForReview: false)
        let h = await readyHarness(uploader: uploader)
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
        let h = await readyHarness(uploader: uploader)
        let model = h.model
        model.sendForReview = false

        await model.startUpload()

        #expect(uploader.lastSendForReview == false, "the request carried the toggle")
        #expect(model.uploadSummary?.sentForReview == true, "the summary carries the outcome")
    }

    @Test func cancellationReturnsToThePlanAndSaysTheDraftWasDiscarded() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .cancelled
        let h = await readyHarness(uploader: uploader)
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
        let h = await readyHarness(uploader: uploader)
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
        await model.continueToPlan()
        model.rowPlans = model.rowPlans.map { var p = $0; p.isEnabled = false; return p }

        await model.startUpload()

        #expect(uploader.callCount == 0)
        #expect(model.step == .configuringPlan)
        #expect(model.errorMessage?.isEmpty == false)
    }

    @Test func goBackReturnsToThePackageStep() async {
        let h = Harness()
        let model = h.model
        model.packageName = "com.example.app"
        await model.continueToPlan()
        model.goBack()
        #expect(model.step == .enteringPackage)
    }
}

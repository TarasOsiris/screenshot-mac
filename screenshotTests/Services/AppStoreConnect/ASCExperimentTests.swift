import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ASCExperimentPlannerTests {

    init() { BetaFeatures.shared.setABTesting(true, persist: false) }


    private func iPhoneRow(variantId: UUID?) -> ScreenshotRow {
        ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 1290, templateHeight: 2796, variantId: variantId)
    }

    private let variantB = ScreenshotVariant(name: "Variant B")
    private let variantC = ScreenshotVariant(name: "Dark hero")

    @Test func variantsWithoutRowsAreNotTreatments() {
        let rows = [iPhoneRow(variantId: nil), iPhoneRow(variantId: variantB.id)]
        #expect(ASCExperimentPlanner.variantsWithRows([variantB, variantC], rowsByVariant: ASCExperimentPlanner.rowsByVariant(rows)) == [variantB])
    }

    @Test func treatmentsMatchVariantsByNameIgnoringCase() {
        let existing = [ASCExperimentTreatment(id: "t1", attributes: .init(name: "dark HERO"))]
        let matches = ASCExperimentPlanner.treatmentMatches(variants: [variantB, variantC], existing: existing)
        #expect(matches[variantC.id]?.id == "t1")
        #expect(matches[variantB.id] == nil)
    }

    @Test func noVariantsIsAnError() {
        let issues = ASCExperimentPlanner.issues(
            variants: [], rowsByVariant: ASCExperimentPlanner.rowsByVariant([iPhoneRow(variantId: nil)]), platform: .ios, experiment: nil,
            existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.severity == .error })
    }

    @Test func moreThanThreeTreatmentsIsAnError() {
        let variants = (0..<4).map { ScreenshotVariant(name: "V\($0)") }
        let rows = variants.map { iPhoneRow(variantId: $0.id) }
        let issues = ASCExperimentPlanner.issues(
            variants: variants, rowsByVariant: ASCExperimentPlanner.rowsByVariant(rows), platform: .ios, experiment: nil,
            existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.message.contains("3") && $0.severity == .error })
    }

    @Test func existingTreatmentsCountTowardTheLimitUnlessMatched() {
        let rows = [iPhoneRow(variantId: variantB.id)]
        let existing = (1...3).map { ASCExperimentTreatment(id: "t\($0)", attributes: .init(name: "Old \($0)")) }
        let experiment = ASCExperiment.fixture(id: "e1")

        let unmatched = ASCExperimentPlanner.issues(
            variants: [variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant(rows), platform: .ios, experiment: experiment,
            existingTreatments: existing, newExperimentName: "",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(unmatched.contains { $0.severity == .error })

        let renamed = existing.dropLast() + [ASCExperimentTreatment(id: "t3", attributes: .init(name: "Variant B"))]
        let matched = ASCExperimentPlanner.issues(
            variants: [variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant(rows), platform: .ios, experiment: experiment,
            existingTreatments: Array(renamed), newExperimentName: "",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(!matched.contains { $0.severity == .error })
    }

    @Test func lockedExperimentIsAnError() {
        let issues = ASCExperimentPlanner.issues(
            variants: [variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant([iPhoneRow(variantId: variantB.id)]), platform: .ios,
            experiment: .fixture(id: "e1", state: .inReview),
            existingTreatments: [], newExperimentName: "",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.severity == .error })
    }

    @Test func languagesMissingFromTheProductPageBlockTheUpload() {
        let issues = ASCExperimentPlanner.issues(
            variants: [variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant([iPhoneRow(variantId: variantB.id)]), platform: .ios, experiment: nil,
            existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["de"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.severity == .error })
    }

    @Test func aReadyPlanHasNoErrors() {
        let issues = ASCExperimentPlanner.issues(
            variants: [variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant([iPhoneRow(variantId: nil), iPhoneRow(variantId: variantB.id)]),
            platform: .ios, experiment: nil,
            existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(!issues.contains { $0.severity == .error })
    }

    @Test func targetsCoverOnlyTheVariantsRowsAndParentToTreatmentLocalizations() {
        let original = iPhoneRow(variantId: nil)
        let variantRow = iPhoneRow(variantId: variantB.id)
        let treatment = ASCExperimentTreatment(id: "t1", attributes: .init(name: "Variant B"))
        let localization = ASCUploadLocalization(id: "tl-1", label: "en-US", localeCode: "en")

        let targets = ASCExperimentPlanner.targets(
            rowsByVariant: ASCExperimentPlanner.rowsByVariant([original, variantRow]),
            platform: .ios,
            experimentName: "Test",
            treatments: [ASCTreatmentTarget(variantId: variantB.id, treatment: treatment, localizations: [localization])]
        )

        #expect(targets.map(\.rowId) == [variantRow.id])
        #expect(targets.first?.parentKind == .treatmentLocalization)
        #expect(targets.first?.versionId == "t1")
        #expect(targets.first?.localizations.map(\.id) == ["tl-1"])
    }

    @Test func twoRowsOfOneSizeInAVariantBlockTheUpload() {
        let issues = ASCExperimentPlanner.issues(
            variants: [variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant([iPhoneRow(variantId: variantB.id), iPhoneRow(variantId: variantB.id)]),
            platform: .ios, experiment: nil,
            existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.severity == .error })
    }

    @Test func rowsExcludedFromAppStoreConnectStayOutOfTheExperiment() {
        var excluded = iPhoneRow(variantId: variantB.id)
        excluded.excludeFromAppStoreConnect = true
        let kept = iPhoneRow(variantId: variantB.id)
        let treatment = ASCExperimentTreatment(id: "t1", attributes: .init(name: "Variant B"))
        let localization = ASCUploadLocalization(id: "tl-1", label: "en-US", localeCode: "en")

        let targets = ASCExperimentPlanner.targets(
            rowsByVariant: ASCExperimentPlanner.rowsByVariant([excluded, kept]),
            platform: .ios,
            experimentName: "Test",
            treatments: [ASCTreatmentTarget(variantId: variantB.id, treatment: treatment, localizations: [localization])]
        )

        #expect(targets.map(\.rowId) == [kept.id])
        #expect(ASCExperimentPlanner.variantsWithRows([variantB], rowsByVariant: ASCExperimentPlanner.rowsByVariant([excluded])).isEmpty)
    }
}

@MainActor
struct ASCExperimentPlannerWarningTests {

    init() { BetaFeatures.shared.setABTesting(true, persist: false) }


    private func iPhoneRow(variantId: UUID?) -> ScreenshotRow {
        ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 1290, templateHeight: 2796, variantId: variantId)
    }

    @Test func aTreatmentNoVariantMatchesIsReported() {
        let variant = ScreenshotVariant(name: "B")
        let rows = [iPhoneRow(variantId: variant.id)]
        let issues = ASCExperimentPlanner.issues(
            variants: [variant], rowsByVariant: ASCExperimentPlanner.rowsByVariant(rows), platform: .ios,
            experiment: .fixture(id: "e1"),
            existingTreatments: [ASCExperimentTreatment(id: "t1", attributes: .init(name: "Old idea"))],
            newExperimentName: "", enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.severity == .warning && $0.scope == "Old idea" })
    }

    @Test func aSizeTheOriginalHasButTheVariantLacksIsReported() {
        let variant = ScreenshotVariant(name: "B")
        let rows = [iPhoneRow(variantId: variant.id)]
        let issues = ASCExperimentPlanner.issues(
            variants: [variant], rowsByVariant: ASCExperimentPlanner.rowsByVariant(rows), platform: .ios,
            experiment: nil, existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]],
            originalDisplayTypes: [.ipadPro3Gen129]
        )
        #expect(issues.contains { $0.severity == .warning && $0.scope == "B" })
    }

    @Test func tooManyScreenshotsInAVariantRowBlocksBeforeAnythingIsCreated() {
        let variant = ScreenshotVariant(name: "B")
        let row = ScreenshotRow(
            templates: Array(repeating: ScreenshotTemplate(), count: 11),
            templateWidth: 1290, templateHeight: 2796, variantId: variant.id
        )
        let issues = ASCExperimentPlanner.issues(
            variants: [variant], rowsByVariant: ASCExperimentPlanner.rowsByVariant([row]), platform: .ios,
            experiment: nil, existingTreatments: [], newExperimentName: "Test",
            enabledLocaleCodes: ["en"], localeAssignment: ["en": ["en-US"]]
        )
        #expect(issues.contains { $0.severity == .error })
    }

    @Test func noVariantGuidanceTellsEmptyVariantsApart() {
        #expect(ASCExperimentPlanner.noVariantsIssue(hasVariants: false).message != ASCExperimentPlanner.noVariantsIssue(hasVariants: true).message)
    }
}

@MainActor
struct ASCExperimentFlowModelTests {

    init() { BetaFeatures.shared.setABTesting(true, persist: false) }


    private func makeModel(
        experiments: FakeASCExperimentAPI = FakeASCExperimentAPI()
    ) -> (ASCExperimentFlowModel, FakeASCUploadAPI, StubASCDocument) {
        let uploadAPI = FakeASCUploadAPI()
        let app = ASCApp(id: "app", attributes: .init(name: "App", bundleId: "b", sku: nil, primaryLocale: "en-US"))
        let live = ASCAppStoreVersion(id: "live", attributes: .init(versionString: "1.0", appStoreState: "READY_FOR_SALE", platform: "IOS"))
        let next = ASCAppStoreVersion(id: "next", attributes: .init(versionString: "1.1", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS"))
        uploadAPI.appsWithVersions = [ASCAppWithVersions(app: app, versions: [live, next])]
        uploadAPI.versionsByAppId["app"] = [next, live]
        uploadAPI.localizationsByVersionId["live"] = [
            ASCAppStoreVersionLocalization(id: "loc-en", attributes: .init(locale: "en-US")),
        ]
        uploadAPI.localizationsByVersionId["next"] = [
            ASCAppStoreVersionLocalization(id: "loc-next-en", attributes: .init(locale: "en-US")),
            ASCAppStoreVersionLocalization(id: "loc-next-de", attributes: .init(locale: "de-DE")),
        ]
        let document = StubASCDocument(localeState: LocaleState(
            locales: [LocaleDefinition(code: "en", label: "English"), LocaleDefinition(code: "de", label: "German")],
            activeLocaleCode: "en",
            overrides: [:]
        ))
        let model = ASCExperimentFlowModel(
            uploadAPI: uploadAPI,
            experimentAPI: experiments,
            credentials: .isolatedForTesting()
        )
        model.bind(document: document)
        model.apps = uploadAPI.appsWithVersions
        model.selectedAppId = "app"
        return (model, uploadAPI, document)
    }

    @Test func configureUsesTheLiveProductPagesLanguages() async {
        let (model, _, _) = makeModel()

        await model.continueToConfigure()

        #expect(model.step == .configuring)
        #expect(model.localeAssignment == ["en": ["en-US"]])
        #expect(model.enabledLocaleCodes == ["en"])
    }

    @Test func configurePreselectsAnEditableExperimentOnThePlatform() async {
        let api = FakeASCExperimentAPI()
        api.experiments = [
            .fixture(id: "mac", platform: .macOS),
            .fixture(id: "done", state: .completed),
            .fixture(id: "draft"),
        ]
        let (model, _, _) = makeModel(experiments: api)

        await model.continueToConfigure()

        #expect(Set(model.experiments.map(\.id)) == ["done", "draft"])
        #expect(model.selectedExperimentId == "draft")
    }

    @Test func noEditableExperimentMeansCreatingOne() async {
        let api = FakeASCExperimentAPI()
        api.experiments = [.fixture(id: "done", state: .completed)]
        let (model, _, _) = makeModel(experiments: api)

        await model.continueToConfigure()

        #expect(model.selectedExperimentId == nil)
        #expect(!model.newExperimentName.isEmpty)
    }

    @Test func aSubmittedExperimentReadsAsWaitingEvenIfTheRefreshLags() async {
        let api = FakeASCExperimentAPI()
        api.experiments = [.fixture(id: "draft")]
        let (model, _, _) = makeModel(experiments: api)
        await model.continueToConfigure()

        await model.submitForReview()

        #expect(model.selectedExperiment?.state == .waitingForReview)
    }

    @Test func anApprovedExperimentIsPreselectedSoItCanBeStarted() async {
        let api = FakeASCExperimentAPI()
        api.experiments = [.fixture(id: "draft"), .fixture(id: "approved", state: .accepted)]
        let (model, _, _) = makeModel(experiments: api)

        await model.continueToConfigure()

        #expect(model.selectedExperimentId == "approved")
        #expect(model.isSelectedExperimentLocked)
    }

    @Test func newExperimentNameDefaultsFromTheProject() {
        let (model, _, _) = makeModel()
        #expect(model.newExperimentName.contains("Fixture"))
    }
}

@MainActor
struct GPListingVariantTests {

    init() { BetaFeatures.shared.setABTesting(true, persist: false) }


    @Test func listingVariantChoosesWhichRowsArePlanned() {
        let variant = ScreenshotVariant(name: "B")
        let original = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 1080, templateHeight: 1920)
        let variantRow = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 1080, templateHeight: 1920, variantId: variant.id)
        let document = StubGPDocument(rows: [original, variantRow])
        document.activeVariants = [variant]
        let model = GPUploadFlowModel(
            uploader: FakeGPUploader(),
            api: FakeGPPackageVerifier(),
            credentials: .isolatedForTesting(),
            defaults: makeIsolatedDefaults()
        )
        model.bind(document: document)

        #expect(model.buildRowPlans().map(\.id) == [original.id])

        model.listingVariantId = variant.id
        #expect(model.buildRowPlans().map(\.id) == [variantRow.id])

        model.listingVariantId = UUID()
        #expect(model.buildRowPlans().map(\.id) == [original.id], "an unknown variant falls back to the Original")
    }
}

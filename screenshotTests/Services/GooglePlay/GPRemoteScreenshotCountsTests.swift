import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct GPRemoteScreenshotCountsTests {

    @Test func statusResolvesAgainstTheRowsImageType() {
        let phone = GPImageType.phoneScreenshots.apiValue
        let tablet = GPImageType.tenInchScreenshots.apiValue
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [:], assetKey: phone) == .empty)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [phone: 0], assetKey: phone) == .empty)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [tablet: 4], assetKey: phone) == .missingForThisType)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [phone: 6], assetKey: phone) == .present(6))
        #expect(StoreRemoteScreenshotStatus.resolve(counts: nil, assetKey: phone) == nil)
    }

    /// The model holds its document weakly, so the harness keeps it alive.
    private final class Harness {
        let model: GPUploadFlowModel
        let api = FakeGPPackageVerifier()
        let document: StubGPDocument
        let english = GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "en")!
        let german = GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "de")!

        init(uploader: FakeGPUploader = FakeGPUploader(), credentials: GooglePlayCredentialsStore = .isolatedForTesting()) {
            var localeState = LocaleState.default
            localeState.locales = ["en", "de"].map { LocaleDefinition(code: $0, label: $0.uppercased()) }
            document = StubGPDocument(
                rows: [ScreenshotRow(label: "Row", templates: [ScreenshotTemplate(), ScreenshotTemplate()], templateWidth: 1080, templateHeight: 1920)],
                localeState: localeState
            )
            model = GPUploadFlowModel(
                uploader: uploader,
                api: api,
                credentials: credentials,
                defaults: makeIsolatedDefaults("gpCounts")
            )
            model.bind(document: document)
            model.packageName = "com.example.app"
        }
    }

    @Test func enteringThePlanReadsEveryMappedLanguage() async {
        let h = Harness()
        h.api.screenshotCountsByLanguage = [h.english: ["phoneScreenshots": 5], h.german: [:]]

        await h.model.continueToPlan()
        await h.model.settleRemoteScreenshotCounts()

        #expect(h.api.screenshotCountRequests == [[h.english, h.german].sorted()])
        #expect(h.model.remoteScreenshotCounts[h.english] == ["phoneScreenshots": 5])
        #expect(h.model.remoteScreenshotCounts[h.german] == [:])
    }

    @Test func aFailedReadStaysUnknown() async {
        let h = Harness()
        h.api.screenshotCountError = URLError(.notConnectedToInternet)

        await h.model.continueToPlan()
        await h.model.settleRemoteScreenshotCounts()

        #expect(h.model.remoteScreenshotCounts.isEmpty)
    }

    @Test func startingTheUploadDropsAReadInFlight() async {
        let h = Harness()
        let gate = Gate()
        h.api.screenshotCountGate = { await gate.wait() }
        h.api.screenshotCountsByLanguage = [h.english: ["phoneScreenshots": 5]]

        await h.model.continueToPlan()
        await h.model.startUpload()
        #expect(h.model.step == .done, "the upload itself has to run for this to test anything")
        gate.release()
        await h.model.settleRemoteScreenshotCounts()

        #expect(h.model.remoteScreenshotCountTask == nil)
        #expect(h.model.remoteScreenshotCounts.isEmpty)
    }

    @Test func revisitingThePlanReusesLoadedCounts() async {
        let h = Harness()
        h.api.screenshotCountsByLanguage = [h.english: ["phoneScreenshots": 5]]

        await h.model.continueToPlan()
        await h.model.settleRemoteScreenshotCounts()
        h.model.goBack()
        await h.model.continueToPlan()
        await h.model.settleRemoteScreenshotCounts()

        #expect(h.api.screenshotCountRequests.count == 1)
        #expect(h.model.remoteScreenshotCounts[h.english] == ["phoneScreenshots": 5])
    }

    @Test func aFailedUploadReloadsTheBadges() async {
        let uploader = FakeGPUploader()
        uploader.outcome = .failure(URLError(.timedOut))
        let h = Harness(uploader: uploader)
        h.api.screenshotCountsByLanguage = [h.english: ["phoneScreenshots": 5]]

        await h.model.continueToPlan()
        await h.model.startUpload()
        await h.model.settleRemoteScreenshotCounts()

        #expect(h.model.step == .configuringPlan)
        #expect(h.model.remoteScreenshotCounts[h.english] == ["phoneScreenshots": 5])
    }

    @Test func aSupersededReadNeverOverwrites() async {
        let h = Harness()
        let gate = Gate()
        h.api.screenshotCountGate = { await gate.wait() }
        h.api.screenshotCountsByLanguage = [h.english: ["phoneScreenshots": 5]]
        await h.model.continueToPlan()
        let stale = h.model.remoteScreenshotCountTask

        h.api.screenshotCountGate = nil
        h.api.screenshotCountsByLanguage = [h.english: ["phoneScreenshots": 2]]
        h.model.reloadRemoteScreenshotCounts()
        await h.model.settleRemoteScreenshotCounts()
        gate.release()
        await stale?.value

        #expect(h.model.remoteScreenshotCounts[h.english] == ["phoneScreenshots": 2])
    }

    @Test func demoCountsCycleThroughEveryBadgeState() {
        let demo = GooglePlayDemoData()
        let counts = demo.screenshotCounts(languages: ["a", "b", "c"])
        let phone = GPImageType.phoneScreenshots.apiValue
        let statuses = ["a", "b", "c"].map { StoreRemoteScreenshotStatus.resolve(counts: counts[$0], assetKey: phone) }
        #expect(statuses == [.present(5), .empty, .missingForThisType])

        demo.deleteAllImages(language: "b", imageType: phone)
        _ = demo.uploadImage(language: "b", imageType: phone)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: demo.screenshotCounts(languages: ["a", "b"])["b"], assetKey: phone) == .present(1))
    }
}

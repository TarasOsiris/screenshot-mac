import Foundation
@testable import Screenshot_Bro
import Testing

// The plan step badges each App Store locale with what it already holds, so the user can see
// where there are no screenshots at all. The badge must never claim "empty" for a locale it
// simply couldn't read.
@MainActor
struct ASCRemoteScreenshotCountsTests {

    // MARK: - Status

    @Test func statusDistinguishesEmptyMissingForTypeAndPresent() {
        let type = ASCDisplayType.iphone67
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [:], assetKey: type.appStoreConnectValue) == .empty)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [type.appStoreConnectValue: 0], assetKey: type.appStoreConnectValue) == .empty)
        #expect(StoreRemoteScreenshotStatus.resolve(
            counts: [ASCDisplayType.ipadPro129M4.appStoreConnectValue: 4],
            assetKey: type.appStoreConnectValue
        ) == .missingForThisType)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [type.appStoreConnectValue: 6], assetKey: type.appStoreConnectValue) == .present(6))
    }

    @Test func statusIsUnknownWithoutCountsOrDisplayType() {
        #expect(StoreRemoteScreenshotStatus.resolve(counts: nil, assetKey: ASCDisplayType.iphone67.appStoreConnectValue) == nil)
        #expect(StoreRemoteScreenshotStatus.resolve(counts: [:], assetKey: nil) == nil)
    }

    // MARK: - Flow model

    private final class Harness {
        let model: ASCUploadFlowModel
        let api: FakeASCUploadAPI
        let document: StubASCDocument

        init() {
            var localeState = LocaleState.default
            localeState.locales = ["en", "de"].map { LocaleDefinition(code: $0, label: $0.uppercased()) }
            api = FakeASCUploadAPI()
            document = StubASCDocument(
                rows: [ScreenshotRow(label: "Row", templates: [ScreenshotTemplate()], templateWidth: 1290, templateHeight: 2796)],
                localeState: localeState
            )
            model = ASCUploadFlowModel(api: api, credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
            model.bind(document: document)
            model.versions = [ASCAppStoreVersion(
                id: "v1",
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
            )]
            model.selectedVersionIds = ["v1"]
            api.localizationsByVersionId["v1"] = ["en-US", "de-DE"].map {
                ASCAppStoreVersionLocalization(id: "v1-\($0)", attributes: .init(locale: $0, description: "", keywords: ""))
            }
        }

        func settle() async {
            await model.settleRemoteScreenshotCounts()
        }
    }

    @Test func refreshFillsCountsPerLocalization() async {
        let h = Harness()
        h.api.screenshotCountsByLocalizationId["v1-en-US"] = ["APP_IPHONE_67": 5]

        await h.model.refreshLocalizations()
        await h.settle()

        #expect(h.model.remoteScreenshotCounts["v1-en-US"] == ["APP_IPHONE_67": 5])
        #expect(h.model.remoteScreenshotCounts["v1-de-DE"] == [:])
    }

    @Test func aFailedCountIsUnknownAndNeverBlocksThePlan() async {
        let h = Harness()
        h.api.failingCountLocalizationIds = ["v1-de-DE"]

        await h.model.refreshLocalizations()
        await h.settle()

        #expect(h.model.remoteScreenshotCounts["v1-de-DE"] == nil)
        #expect(h.model.remoteScreenshotCounts["v1-en-US"] != nil)
        #expect(h.model.errorMessage == nil)
    }

    @Test func refreshDropsStaleCounts() async {
        let h = Harness()
        h.api.screenshotCountsByLocalizationId["v1-de-DE"] = ["APP_IPHONE_67": 2]
        await h.model.refreshLocalizations()
        await h.settle()

        h.api.failingCountLocalizationIds = ["v1-de-DE"]
        await h.model.refreshLocalizations()
        await h.settle()

        #expect(h.model.remoteScreenshotCounts["v1-de-DE"] == nil)
    }

    @Test func keepingKnownOnlyFetchesNewLocalizations() async {
        let h = Harness()
        await h.model.refreshLocalizations()
        await h.settle()
        let callsAfterRefresh = h.api.screenshotCountCalls.count

        h.model.localizationsByVersionId["v1", default: []].append(
            ASCAppStoreVersionLocalization(id: "v1-fr-FR", attributes: .init(locale: "fr-FR", description: "", keywords: ""))
        )
        h.model.reloadRemoteScreenshotCounts(keepingKnown: true)
        await h.settle()

        #expect(h.api.screenshotCountCalls.dropFirst(callsAfterRefresh) == ["v1-fr-FR"])
        #expect(h.model.remoteScreenshotCounts.count == 3)
    }

    /// A locale created while the first fetch is still running must not refetch every other one.
    @Test func keepingKnownSkipsLocalizationsAlreadyInFlight() async {
        let h = Harness()
        let gate = Gate()
        h.api.screenshotCountResponder = { _ in
            await gate.wait()
            return [:]
        }
        await h.model.refreshLocalizations()
        await Task.yield()

        h.model.localizationsByVersionId["v1", default: []].append(
            ASCAppStoreVersionLocalization(id: "v1-fr-FR", attributes: .init(locale: "fr-FR", description: "", keywords: ""))
        )
        h.model.reloadRemoteScreenshotCounts(keepingKnown: true)
        gate.release()
        await h.settle()

        #expect(h.api.screenshotCountCalls.sorted() == ["v1-de-DE", "v1-en-US", "v1-fr-FR"])
        #expect(h.model.remoteScreenshotCounts.count == 3)
    }

    /// A refresh supersedes a fetch still on the wire; its late answer must not land.
    @Test func aSupersededFetchNeverOverwritesTheRefresh() async {
        let h = Harness()
        let gate = Gate()
        h.api.screenshotCountResponder = { _ in
            await gate.wait()
            return ["APP_IPHONE_67": 1]
        }
        await h.model.refreshLocalizations()
        let stale = h.model.remoteScreenshotCountTasks
        await Task.yield()

        h.api.screenshotCountResponder = { _ in ["APP_IPHONE_67": 9] }
        await h.model.refreshLocalizations()
        await h.settle()
        gate.release()
        for task in stale { await task.value }

        #expect(h.model.remoteScreenshotCounts["v1-en-US"] == ["APP_IPHONE_67": 9])
        #expect(h.model.remoteScreenshotCounts["v1-de-DE"] == ["APP_IPHONE_67": 9])
    }

    /// A half-loaded fetch would compare a row against whichever locales happened to answer first.
    @Test func listingIssuesWaitForTheCountsToSettle() async throws {
        let h = Harness()
        h.api.localizationsByVersionId["v1", default: []].append(
            ASCAppStoreVersionLocalization(id: "v1-sk", attributes: .init(locale: "sk", description: "", keywords: ""))
        )
        await h.model.refreshLocalizations()
        await h.settle()
        let destination = try #require(h.model.destinationPlans.first)
        let rowId = try #require(destination.rowPlans.first?.id)
        #expect((h.model.listingConsistencyIssues(for: destination)[rowId] ?? []).contains { $0.message.contains("sk has no") })

        h.model.remoteScreenshotCountsInFlight = ["v1-de-DE"]
        #expect(h.model.listingConsistencyIssues(for: destination).isEmpty)
    }

    @Test func demoCountsCoverEveryBadgeState() {
        let demo = AppStoreConnectDemoData()
        demo.updateContext(localeCodes: ["de", "fr"], rowSizes: [CGSize(width: 1290, height: 2796)])
        let type = ASCDisplayType.detect(width: 1290, height: 2796)
        let statuses = ["en-US", "de", "fr"].map {
            StoreRemoteScreenshotStatus.resolve(counts: demo.screenshotCounts(parentId: "demo-vloc-demo-version-ios-\($0)"), assetKey: type?.appStoreConnectValue)
        }
        #expect(statuses == [.present(5), .empty, .missingForThisType])
    }

    @Test func demoCountsStillShowPresentWhenNoRowSizeMatched() {
        let demo = AppStoreConnectDemoData()
        demo.updateContext(localeCodes: [], rowSizes: [CGSize(width: 100, height: 100)])
        let counts = demo.screenshotCounts(parentId: "demo-vloc-demo-version-ios-en-US")
        #expect(StoreRemoteScreenshotStatus.resolve(counts: counts, assetKey: ASCDisplayType.iphone69.appStoreConnectValue) == .present(5))
    }
}

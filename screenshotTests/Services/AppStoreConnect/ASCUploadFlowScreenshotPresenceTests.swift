import Foundation
@testable import Screenshot_Bro
import Testing

// The plan step's per-locale "No screenshots yet" indicator. Two halves are pinned here: the sweep
// (`loadScreenshotPresence()`), which records *which display types* a version localization has
// screenshots for, and the row's reading of it (`ASCLocaleRowContext.presenceState`), which is
// scoped to the display type that row uploads. The scoping is the point: App Store Connect carries
// screenshots between versions and keeps sets for other device families, so "has any screenshot at
// all" quietly never flagged a locale that was missing the size actually being uploaded.
@MainActor
struct ASCUploadFlowScreenshotPresenceTests {

    private final class Harness {
        let model: ASCUploadFlowModel
        let screenshotPresenceAPI: FakeASCScreenshotPresenceAPI
        let document: StubASCDocument

        init() {
            var localeState = LocaleState.default
            localeState.locales = [LocaleDefinition(code: "en", label: "EN")]

            screenshotPresenceAPI = FakeASCScreenshotPresenceAPI()
            document = StubASCDocument(rows: [], localeState: localeState)
            model = ASCUploadFlowModel(
                api: FakeASCUploadAPI(),
                screenshotPresenceAPI: screenshotPresenceAPI,
                credentials: AppStoreConnectCredentialsStore.isolatedForTesting()
            )
            model.bind(document: document)
        }

        /// One localization on one version, with `sets` describing (display type, screenshot count).
        /// Sets are keyed by `appStoreConnectValue`, because that is what App Store Connect
        /// actually returns — it has no `APP_IPHONE_69` or `APP_IPAD_PRO_11_M4` set to hand back.
        func seed(localizationId: String, sets: [(ASCDisplayType, Int)]) {
            model.localizationsByVersionId["version-1", default: []].append(
                ASCAppStoreVersionLocalization(id: localizationId, attributes: .init(locale: "sk"))
            )
            screenshotPresenceAPI.screenshotSetsByLocalizationId[localizationId] = sets.enumerated().map { index, entry in
                let setId = "\(localizationId)-set-\(index)"
                screenshotPresenceAPI.screenshotOrderBySetId[setId] = (0..<entry.1).map { "shot-\($0)" }
                return ASCAppScreenshotSet(
                    id: setId,
                    attributes: .init(screenshotDisplayType: entry.0.appStoreConnectValue)
                )
            }
        }
    }

    private func context(
        _ map: [String: Set<String>]
    ) -> ASCLocaleRowContext {
        ASCLocaleRowContext(
            versionId: "version-1",
            versionAcceptsNewLocales: true,
            existingStoreLocaleCodes: [],
            inFlightKeys: [],
            errors: [:],
            screenshotDisplayTypesByLocalizationId: map,
            create: { _ in }
        )
    }

    private func localization(_ id: String) -> ASCAppStoreVersionLocalization {
        ASCAppStoreVersionLocalization(id: id, attributes: .init(locale: "sk"))
    }

    // MARK: - The sweep

    @Test
    func localizationWithNoSetsRecordsNoDisplayTypes() async {
        let harness = Harness()
        harness.seed(localizationId: "loc-no-sets", sets: [])

        await harness.model.loadScreenshotPresence()

        #expect(harness.model.screenshotDisplayTypesByLocalizationId["loc-no-sets"] == [])
    }

    /// A set can exist with nothing in it, so presence is "the set has a non-empty order", not
    /// "a set exists".
    @Test
    func emptySetDoesNotCountAsPresence() async {
        let harness = Harness()
        harness.seed(localizationId: "loc-empty-set", sets: [(.iphone67, 0)])

        await harness.model.loadScreenshotPresence()

        #expect(harness.model.screenshotDisplayTypesByLocalizationId["loc-empty-set"] == [])
    }

    @Test
    func recordsOnlyTheDisplayTypesThatHaveScreenshots() async {
        let harness = Harness()
        harness.seed(localizationId: "loc-mixed", sets: [(.iphone67, 3), (.ipadPro11M4, 0), (.desktop, 1)])

        await harness.model.loadScreenshotPresence()

        #expect(
            harness.model.screenshotDisplayTypesByLocalizationId["loc-mixed"]
                == [ASCDisplayType.iphone67.appStoreConnectValue, ASCDisplayType.desktop.appStoreConnectValue]
        )
    }

    /// Fail-open: a failed read must stay *unknown* rather than become "has none", or a transient
    /// API error manufactures a badge next to a locale that is fine.
    @Test
    func failedSetFetchLeavesTheKeyAbsent() async {
        let harness = Harness()
        harness.seed(localizationId: "loc-broken", sets: [])
        harness.screenshotPresenceAPI.failingLocalizationIds = ["loc-broken"]

        await harness.model.loadScreenshotPresence()

        #expect(harness.model.screenshotDisplayTypesByLocalizationId["loc-broken"] == nil)
    }

    @Test
    func failedOrderFetchLeavesTheKeyAbsent() async {
        let harness = Harness()
        harness.seed(localizationId: "loc-broken-order", sets: [(.iphone67, 2)])
        harness.screenshotPresenceAPI.failingSetIds = ["loc-broken-order-set-0"]

        await harness.model.loadScreenshotPresence()

        #expect(harness.model.screenshotDisplayTypesByLocalizationId["loc-broken-order"] == nil)
    }

    @Test
    func checksLocalizationsAcrossMultipleSelectedVersions() async {
        let harness = Harness()
        harness.model.localizationsByVersionId = [
            "version-1": [ASCAppStoreVersionLocalization(id: "loc-1", attributes: .init(locale: "fr-FR"))],
            "version-2": [ASCAppStoreVersionLocalization(id: "loc-2", attributes: .init(locale: "de-DE"))],
        ]
        harness.screenshotPresenceAPI.screenshotSetsByLocalizationId["loc-2"] = [
            ASCAppScreenshotSet(id: "set-2", attributes: .init(screenshotDisplayType: ASCDisplayType.iphone67.rawValue)),
        ]
        harness.screenshotPresenceAPI.screenshotOrderBySetId["set-2"] = ["shot-1"]

        await harness.model.loadScreenshotPresence()

        #expect(harness.model.screenshotDisplayTypesByLocalizationId["loc-1"] == [])
        #expect(harness.model.screenshotDisplayTypesByLocalizationId["loc-2"] == [ASCDisplayType.iphone67.rawValue])
    }

    /// Publishing per locale rather than once at the end is what makes the badges appear while the
    /// sweep is still running — and what stops a cancellation discarding work already paid for.
    @Test
    func publishesEachLocalizationAsItResolves() async {
        let harness = Harness()
        let total = 12
        for index in 0..<total {
            harness.seed(localizationId: "loc-\(index)", sets: [])
        }
        // The sweep keeps a bounded number of reads in flight and only starts another once one has
        // been published, so the last call cannot begin until earlier results are already in the
        // map. Asserting a lower bound rather than an exact count: a task is *created* after N
        // publishes but may not *run* until more have landed, so the exact figure isn't the
        // invariant — "results are visible before the sweep returns" is.
        var publishedWhenLastCallArrived: Int?
        var callCount = 0
        harness.screenshotPresenceAPI.onListScreenshotSets = { [weak model = harness.model] _ in
            callCount += 1
            if callCount == total {
                publishedWhenLastCallArrived = model?.screenshotDisplayTypesByLocalizationId.count
            }
        }

        await harness.model.loadScreenshotPresence()

        #expect((publishedWhenLastCallArrived ?? 0) > 0)
        #expect(harness.model.screenshotDisplayTypesByLocalizationId.count == total)
    }

    // MARK: - How a row reads it

    @Test
    func rowIsCheckingUntilEveryCandidateIsKnown() {
        let context = context(["known": [ASCDisplayType.iphone67.rawValue]])

        let state = context.presenceState(
            candidates: [localization("known"), localization("unknown")],
            displayType: .iphone67
        )

        #expect(state == .checking)
    }

    /// The regression this whole change exists for: leftover screenshots for another device family
    /// used to count as "has screenshots" and silently suppressed the badge.
    @Test
    func rowIsMissingWhenOtherDisplayTypesHaveScreenshotsButThisOneDoesNot() {
        let context = context([
            "sk": [
                ASCDisplayType.ipadPro11M4.appStoreConnectValue,
                ASCDisplayType.desktop.appStoreConnectValue,
            ],
        ])

        #expect(context.presenceState(candidates: [localization("sk")], displayType: .iphone69) == .missing)
        #expect(context.presenceState(candidates: [localization("sk")], displayType: .ipadPro11M4) == .hasScreenshots)
    }

    /// Several display types upload into one App Store Connect set (`.iphone69` lands in
    /// `APP_IPHONE_67`, `.ipadPro11M4` in `APP_IPAD_PRO_3GEN_11`). Presence has to be measured
    /// against the set the upload will actually land in, or a 6.9" row would be told "no
    /// screenshots yet" while looking straight at the ones it is about to replace.
    @Test
    func aliasedDisplayTypesMatchTheSetTheyUploadInto() {
        let context = context(["sk": [ASCDisplayType.iphone67.appStoreConnectValue]])

        #expect(context.presenceState(candidates: [localization("sk")], displayType: .iphone69) == .hasScreenshots)
        #expect(context.presenceState(candidates: [localization("sk")], displayType: .iphone67) == .hasScreenshots)
        #expect(context.presenceState(candidates: [localization("sk")], displayType: .iphone61) == .missing)
    }

    @Test
    func rowIsMissingOnlyWhenEveryCandidateIsMissing() {
        let context = context(["a": [], "b": [ASCDisplayType.iphone67.rawValue]])

        #expect(context.presenceState(candidates: [localization("a")], displayType: .iphone67) == .missing)
        #expect(
            context.presenceState(
                candidates: [localization("a"), localization("b")],
                displayType: .iphone67
            ) == .hasScreenshots
        )
    }

    /// A locale App Store Connect doesn't carry can't be "missing screenshots" — and the empty
    /// `allSatisfy` would otherwise say it is.
    @Test
    func rowWithNoCandidatesIsNeverFlagged() {
        #expect(context([:]).presenceState(candidates: [], displayType: .iphone67) == .hasScreenshots)
    }

    /// With no upload target chosen the row can't scope, so it falls back to "any display type".
    @Test
    func rowWithoutADisplayTypeFallsBackToAnyDisplayType() {
        let hasSome = context(["sk": [ASCDisplayType.desktop.rawValue]])
        let hasNone = context(["sk": []])

        #expect(hasSome.presenceState(candidates: [localization("sk")], displayType: nil) == .hasScreenshots)
        #expect(hasNone.presenceState(candidates: [localization("sk")], displayType: nil) == .missing)
    }
}

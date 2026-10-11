import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ASCWatchSizeConsistencyTests {
    private let en = ASCAppStoreVersionLocalization(id: "loc-en", attributes: .init(locale: "en-US"))
    private let de = ASCAppStoreVersionLocalization(id: "loc-de", attributes: .init(locale: "de-DE"))

    private func row(_ displayType: ASCDisplayType, sizeIndex: Int = 0, isEnabled: Bool = true) -> ASCRowPlan {
        let size = displayType.acceptedPortraitSizes[sizeIndex]
        return ASCRowPlan(
            id: UUID(),
            rowLabel: displayType.shortLabel,
            rowSize: CGSize(width: size.0, height: size.1),
            templateCount: 5,
            isEnabled: isEnabled,
            detectedAssetType: displayType,
            selectedAssetType: displayType,
            localeTargets: [],
            inferredStorePlatform: .apple
        )
    }

    private func remoteIssue(_ rows: [ASCRowPlan], counts: [String: [String: Int]]) -> UploadIssue? {
        ASCWatchSizeConsistency.remoteConflictIssue(
            destination: ASCDestinationPlan(
                id: "version",
                version: ASCAppStoreVersion(
                    id: "version",
                    attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
                ),
                localizations: [en, de],
                rowPlans: rows
            ),
            remoteCounts: counts
        )
    }

    @Test func twoWatchSizesInOneUploadIsAnError() {
        let issue = ASCWatchSizeConsistency.mixedPlanIssue(plans: [row(.watchUltra), row(.watchSeries10)])
        #expect(issue?.severity == .error)
    }

    @Test func bothUltraSizesInOneUploadIsAnError() {
        let issue = ASCWatchSizeConsistency.mixedPlanIssue(plans: [row(.watchUltra), row(.watchUltra, sizeIndex: 1)])
        #expect(issue?.severity == .error)
    }

    @Test func oneWatchSizeAlongsidePhonesIsFine() {
        #expect(ASCWatchSizeConsistency.mixedPlanIssue(plans: [row(.watchUltra), row(.iphone69), row(.ipadPro129M4)]) == nil)
    }

    @Test func disabledWatchRowDoesNotCount() {
        #expect(ASCWatchSizeConsistency.mixedPlanIssue(plans: [row(.watchUltra), row(.watchSeries7, isEnabled: false)]) == nil)
    }

    @Test func differentRemoteWatchSizeWarns() {
        let issue = remoteIssue([row(.watchUltra)], counts: [de.id: ["APP_WATCH_SERIES_7": 4]])
        #expect(issue?.severity == .warning)
    }

    @Test func sameRemoteWatchSizeIsReplacedNotMixed() {
        #expect(remoteIssue([row(.watchUltra)], counts: [en.id: ["APP_WATCH_ULTRA": 4]]) == nil)
    }

    @Test func remoteWatchSetWithoutWatchUploadIsQuiet() {
        #expect(remoteIssue([row(.iphone69)], counts: [en.id: ["APP_WATCH_SERIES_7": 4]]) == nil)
        #expect(remoteIssue([row(.iphone69)], counts: [en.id: ["APP_WATCH_SERIES_7": 0, "APP_WATCH_ULTRA": 0]]) == nil)
    }
}

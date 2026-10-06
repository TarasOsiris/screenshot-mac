import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ASCDuoReadinessTests {
    private let en = ASCAppStoreVersionLocalization(id: "loc-en", attributes: .init(locale: "en-US"))

    private func row(_ displayType: ASCDisplayType, isEnabled: Bool = true) -> ASCRowPlan {
        ASCRowPlan(
            id: UUID(),
            rowLabel: displayType.shortLabel,
            rowSize: CGSize(width: displayType.acceptedPortraitSizes[0].0, height: displayType.acceptedPortraitSizes[0].1),
            templateCount: 5,
            isEnabled: isEnabled,
            detectedAssetType: displayType,
            selectedAssetType: displayType,
            localeTargets: [],
            inferredStorePlatform: .apple
        )
    }

    private func issue(
        _ rows: [ASCRowPlan],
        platform: String = "IOS",
        counts: [String: [String: Int]] = ["loc-en": [:]]
    ) -> UploadIssue? {
        ASCDuoReadiness.issue(
            destination: ASCDestinationPlan(
                id: "version",
                version: ASCAppStoreVersion(
                    id: "version",
                    attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: platform)
                ),
                localizations: [en],
                rowPlans: rows
            ),
            remoteCounts: counts
        )
    }

    @Test func iphoneUploadWithoutDuoWarns() {
        let warning = issue([row(.iphone69)])
        #expect(warning?.severity == .warning)
    }

    @Test func plannedDuoRowSilencesIt() {
        #expect(issue([row(.iphone69), row(.iphoneDuo)]) == nil)
    }

    @Test func disabledDuoRowDoesNotCount() {
        #expect(issue([row(.iphone69), row(.iphoneDuo, isEnabled: false)]) != nil)
    }

    @Test func existingRemoteDuoSetSilencesIt() {
        #expect(issue([row(.iphone69)], counts: [en.id: ["APP_IPHONE_DUO": 3]]) == nil)
    }

    @Test func unknownRemoteCountsStayQuiet() {
        #expect(issue([row(.iphone69)], counts: [:]) == nil)
    }

    @Test func nonIPhoneUploadsAreQuiet() {
        #expect(issue([row(.ipadPro129M4)]) == nil)
        #expect(issue([row(.desktop)], platform: "MAC_OS") == nil)
    }
}

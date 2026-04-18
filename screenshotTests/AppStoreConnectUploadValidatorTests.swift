import Foundation
import Testing
@testable import Screenshot_Bro

struct AppStoreConnectUploadValidatorTests {
    @Test func rejectsRowsThatResolveToSameAppStoreConnectScreenshotSet() {
        let localization = ASCAppStoreVersionLocalization(
            id: "localization-en",
            attributes: .init(locale: "en-US")
        )
        let localeTarget = UploadToAppStoreConnectView.LocaleTarget(
            appLocaleCode: "en",
            appLocaleLabel: "English",
            selectedASCLocalizationId: localization.id,
            candidates: [localization],
            isEnabled: true
        )
        let version = ASCAppStoreVersion(
            id: "version-1",
            attributes: .init(
                versionString: "1.0",
                appStoreState: "PREPARE_FOR_SUBMISSION",
                platform: "IOS"
            )
        )
        let plans = [
            UploadToAppStoreConnectView.RowPlan(
                id: UUID(),
                rowLabel: "iPad 13-inch",
                rowSize: CGSize(width: 2064, height: 2752),
                templateCount: ASCUploadLimits.minScreenshotsPerSet,
                isEnabled: true,
                detectedDisplayType: .ipadPro129M4,
                selectedDisplayType: .ipadPro129M4,
                localeTargets: [localeTarget]
            ),
            UploadToAppStoreConnectView.RowPlan(
                id: UUID(),
                rowLabel: "iPad 12.9-inch",
                rowSize: CGSize(width: 2048, height: 2732),
                templateCount: ASCUploadLimits.minScreenshotsPerSet,
                isEnabled: true,
                detectedDisplayType: .ipadPro3Gen129,
                selectedDisplayType: .ipadPro3Gen129,
                localeTargets: [localeTarget]
            )
        ]

        let issues = ASCUploadValidator.validate(version: version, plans: plans)

        #expect(issues.contains { issue in
            issue.scope == "iPad 12.9-inch" &&
            issue.message.contains("same App Store screenshot set")
        })
    }

    @Test func rejectsDisplayTypeIncompatibleWithVersionPlatform() {
        let localization = ASCAppStoreVersionLocalization(
            id: "localization-en",
            attributes: .init(locale: "en-US")
        )
        let localeTarget = UploadToAppStoreConnectView.LocaleTarget(
            appLocaleCode: "en",
            appLocaleLabel: "English",
            selectedASCLocalizationId: localization.id,
            candidates: [localization],
            isEnabled: true
        )
        let macVersion = ASCAppStoreVersion(
            id: "version-1",
            attributes: .init(
                versionString: "1.0",
                appStoreState: "PREPARE_FOR_SUBMISSION",
                platform: "MAC_OS"
            )
        )
        let plans = [
            UploadToAppStoreConnectView.RowPlan(
                id: UUID(),
                rowLabel: "iPhone row on a macOS version",
                rowSize: CGSize(width: 1290, height: 2796),
                templateCount: ASCUploadLimits.minScreenshotsPerSet,
                isEnabled: true,
                detectedDisplayType: .iphone67,
                selectedDisplayType: .iphone67,
                localeTargets: [localeTarget]
            )
        ]

        let issues = ASCUploadValidator.validate(version: macVersion, plans: plans)
        #expect(issues.contains { $0.severity == .error && $0.message.contains("can't be uploaded") })
    }

    @Test func flagsEmptyProjectInsteadOfEnableMessage() {
        let version = ASCAppStoreVersion(
            id: "version-1",
            attributes: .init(
                versionString: "1.0",
                appStoreState: "PREPARE_FOR_SUBMISSION",
                platform: "IOS"
            )
        )
        let issues = ASCUploadValidator.validate(version: version, plans: [])
        #expect(issues.contains { $0.message.contains("no rows to upload") })
        #expect(!issues.contains { $0.message.contains("Enable at least one row") })
    }

    @Test func ipadDisplayTypeNoLongerEmitsSpeculativeWarning() {
        let localization = ASCAppStoreVersionLocalization(
            id: "localization-en",
            attributes: .init(locale: "en-US")
        )
        let localeTarget = UploadToAppStoreConnectView.LocaleTarget(
            appLocaleCode: "en",
            appLocaleLabel: "English",
            selectedASCLocalizationId: localization.id,
            candidates: [localization],
            isEnabled: true
        )
        let version = ASCAppStoreVersion(
            id: "version-1",
            attributes: .init(
                versionString: "1.0",
                appStoreState: "PREPARE_FOR_SUBMISSION",
                platform: "IOS"
            )
        )
        let plans = [
            UploadToAppStoreConnectView.RowPlan(
                id: UUID(),
                rowLabel: "iPad",
                rowSize: CGSize(width: 2064, height: 2752),
                templateCount: ASCUploadLimits.minScreenshotsPerSet,
                isEnabled: true,
                detectedDisplayType: .ipadPro129M4,
                selectedDisplayType: .ipadPro129M4,
                localeTargets: [localeTarget]
            )
        ]
        let issues = ASCUploadValidator.validate(version: version, plans: plans)
        #expect(!issues.contains { $0.severity == .warning })
    }
}

import Foundation
import Testing
@testable import Screenshot_Bro

struct AppStoreConnectUploadValidatorTests {
    @Test func screenshotUploadabilityExcludesReviewLockedVersions() {
        func version(_ state: String) -> ASCAppStoreVersion {
            ASCAppStoreVersion(
                id: "version-\(state)",
                attributes: .init(versionString: "1.0", appStoreState: state, platform: "IOS")
            )
        }

        let waitingForReview = version("WAITING_FOR_REVIEW")
        let inReview = version("IN_REVIEW")
        let editable = version("PREPARE_FOR_SUBMISSION")
        let app = ASCApp(
            id: "app-1",
            attributes: .init(name: "App", bundleId: "com.example.app", sku: nil, primaryLocale: "en-US")
        )

        #expect(editable.isScreenshotUploadable)
        #expect(!waitingForReview.isScreenshotUploadable)
        #expect(!inReview.isScreenshotUploadable)
        #expect(!ASCAppWithVersions(app: app, versions: [waitingForReview, inReview]).hasScreenshotUploadableVersion)
        #expect(ASCAppWithVersions(app: app, versions: [waitingForReview, editable]).hasScreenshotUploadableVersion)
    }

    @Test func validatorRejectsReviewLockedVersionForScreenshots() {
        let localization = ASCAppStoreVersionLocalization(id: "localization-en", attributes: .init(locale: "en-US"))
        let version = ASCAppStoreVersion(
            id: "version-review",
            attributes: .init(versionString: "1.0", appStoreState: "IN_REVIEW", platform: "IOS")
        )

        let issues = ASCUploadValidator.validate(
            version: version,
            plans: [
                plan(
                    label: "Phone",
                    size: CGSize(width: 1290, height: 2796),
                    displayType: .iphone67,
                    localization: localization
                )
            ]
        )

        #expect(issues.contains { $0.severity == .error && $0.message.contains("Screenshots can only be changed") })
        #expect(!issues.contains { $0.message.contains("Screenshots can only be changed") && $0.demoDowngradable })
    }

    @Test func rejectsRowsThatResolveToSameAppStoreConnectScreenshotSet() {
        let localization = ASCAppStoreVersionLocalization(
            id: "localization-en",
            attributes: .init(locale: "en-US")
        )
        let localeTarget = UploadToAppStoreConnectView.LocaleTarget(
            appLocaleCode: "en",
            appLocaleLabel: "English",
            selectedASCLocalizationIds: [localization.id],
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

    @Test func collidingRowsAcrossManyLocalesEmitOneErrorPerPartner() {
        let localizations = ["en-US", "fr-FR", "de-DE", "es-ES"].map { locale in
            ASCAppStoreVersionLocalization(id: "localization-\(locale)", attributes: .init(locale: locale))
        }
        let localeTargets = localizations.map { localization in
            UploadToAppStoreConnectView.LocaleTarget(
                appLocaleCode: localization.attributes.locale,
                appLocaleLabel: localization.attributes.locale,
                selectedASCLocalizationIds: [localization.id],
                candidates: [localization],
                isEnabled: true
            )
        }
        let version = ASCAppStoreVersion(
            id: "version-1",
            attributes: .init(
                versionString: "1.0",
                appStoreState: "PREPARE_FOR_SUBMISSION",
                platform: "IOS"
            )
        )
        func plan(_ label: String) -> UploadToAppStoreConnectView.RowPlan {
            UploadToAppStoreConnectView.RowPlan(
                id: UUID(),
                rowLabel: label,
                rowSize: CGSize(width: 2064, height: 2752),
                templateCount: ASCUploadLimits.minScreenshotsPerSet,
                isEnabled: true,
                detectedDisplayType: .ipadPro129M4,
                selectedDisplayType: .ipadPro129M4,
                localeTargets: localeTargets
            )
        }
        let issues = ASCUploadValidator.validate(version: version, plans: [plan("iPad 13"), plan("iPad 13 copy")])

        let collisionErrors = issues.filter { $0.message.contains("same App Store screenshot set") }
        #expect(collisionErrors.count == 1)
        #expect(collisionErrors.first?.scope == "iPad 13 copy")
    }

    @Test func rejectsDisplayTypeIncompatibleWithVersionPlatform() {
        let localization = ASCAppStoreVersionLocalization(
            id: "localization-en",
            attributes: .init(locale: "en-US")
        )
        let localeTarget = UploadToAppStoreConnectView.LocaleTarget(
            appLocaleCode: "en",
            appLocaleLabel: "English",
            selectedASCLocalizationIds: [localization.id],
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
            selectedASCLocalizationIds: [localization.id],
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

    @Test func assignFansBroadCodeToEveryRegionVariant() {
        let locs = ["en-US", "en-GB", "en-CA"].map {
            ASCAppStoreVersionLocalization(id: "loc-\($0)", attributes: .init(locale: $0))
        }
        let assignment = ASCLocaleMatcher.assign(appCodes: ["en"], to: locs)
        #expect(Set((assignment["en"] ?? []).map(\.id)) == Set(locs.map(\.id)))
    }

    @Test func assignDeconflictsSpecificCodeFromBroadCode() {
        let locs = ["en-US", "en-GB", "en-CA"].map {
            ASCAppStoreVersionLocalization(id: "loc-\($0)", attributes: .init(locale: $0))
        }
        let assignment = ASCLocaleMatcher.assign(appCodes: ["en", "en-GB"], to: locs)
        #expect(assignment["en-GB"]?.map(\.attributes.locale) == ["en-GB"])
        #expect(Set((assignment["en"] ?? []).map(\.attributes.locale)) == ["en-US", "en-CA"])
    }

    @Test func collidesWhenTwoRowsFanOutToSameAppStoreLocale() {
        let locs = ["en-US", "en-GB"].map {
            ASCAppStoreVersionLocalization(id: "loc-\($0)", attributes: .init(locale: $0))
        }
        let localeTarget = UploadToAppStoreConnectView.LocaleTarget(
            appLocaleCode: "en",
            appLocaleLabel: "English",
            selectedASCLocalizationIds: Set(locs.map(\.id)),
            candidates: locs,
            isEnabled: true
        )
        let version = ASCAppStoreVersion(
            id: "version-1",
            attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
        )
        func plan(_ label: String) -> UploadToAppStoreConnectView.RowPlan {
            UploadToAppStoreConnectView.RowPlan(
                id: UUID(),
                rowLabel: label,
                rowSize: CGSize(width: 2064, height: 2752),
                templateCount: ASCUploadLimits.minScreenshotsPerSet,
                isEnabled: true,
                detectedDisplayType: .ipadPro129M4,
                selectedDisplayType: .ipadPro129M4,
                localeTargets: [localeTarget]
            )
        }
        let issues = ASCUploadValidator.validate(version: version, plans: [plan("A"), plan("B")])
        #expect(issues.contains { $0.scope == "B" && $0.message.contains("same App Store screenshot set") })
    }

    @Test func sameRowsDoNotCollideAcrossDifferentVersions() {
        let iosLocalization = ASCAppStoreVersionLocalization(id: "ios-loc-en", attributes: .init(locale: "en-US"))
        let macLocalization = ASCAppStoreVersionLocalization(id: "mac-loc-en", attributes: .init(locale: "en-US"))
        let iosDestination = UploadToAppStoreConnectView.DestinationPlan(
            id: "ios-version",
            version: ASCAppStoreVersion(
                id: "ios-version",
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
            ),
            localizations: [iosLocalization],
            rowPlans: [
                plan(
                    label: "Phone",
                    size: CGSize(width: 1290, height: 2796),
                    displayType: .iphone67,
                    localization: iosLocalization
                )
            ]
        )
        let macDestination = UploadToAppStoreConnectView.DestinationPlan(
            id: "mac-version",
            version: ASCAppStoreVersion(
                id: "mac-version",
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "MAC_OS")
            ),
            localizations: [macLocalization],
            rowPlans: [
                plan(
                    label: "Desktop",
                    size: CGSize(width: 2880, height: 1800),
                    displayType: .desktop,
                    localization: macLocalization
                )
            ]
        )

        let issues = ASCUploadValidator.validate(destinations: [iosDestination, macDestination])

        #expect(!issues.contains { $0.message.contains("same App Store screenshot set") })
        #expect(!issues.contains { $0.severity == .error })
    }

    @Test func multiVersionValidationScopesPlatformMismatchesToDestinations() {
        let localization = ASCAppStoreVersionLocalization(id: "loc-en", attributes: .init(locale: "en-US"))
        let iosDestination = UploadToAppStoreConnectView.DestinationPlan(
            id: "ios-version",
            version: ASCAppStoreVersion(
                id: "ios-version",
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
            ),
            localizations: [localization],
            rowPlans: [
                plan(
                    label: "Mac row",
                    size: CGSize(width: 2880, height: 1800),
                    displayType: .desktop,
                    localization: localization
                )
            ]
        )
        let macDestination = UploadToAppStoreConnectView.DestinationPlan(
            id: "mac-version",
            version: ASCAppStoreVersion(
                id: "mac-version",
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "MAC_OS")
            ),
            localizations: [localization],
            rowPlans: [
                plan(
                    label: "Phone row",
                    size: CGSize(width: 1290, height: 2796),
                    displayType: .iphone67,
                    localization: localization
                )
            ]
        )

        let issues = ASCUploadValidator.validate(destinations: [iosDestination, macDestination])

        #expect(issues.contains { issue in
            issue.scope?.contains("iOS") == true &&
            issue.scope?.contains("Mac row") == true &&
            issue.message.contains("can't be uploaded")
        })
        #expect(issues.contains { issue in
            issue.scope?.contains("macOS") == true &&
            issue.scope?.contains("Phone row") == true &&
            issue.message.contains("can't be uploaded")
        })
        #expect(!issues.filter { $0.message.contains("can't be uploaded") }.contains { !$0.demoDowngradable })
    }

    private func plan(
        label: String,
        size: CGSize,
        displayType: ASCDisplayType,
        localization: ASCAppStoreVersionLocalization
    ) -> UploadToAppStoreConnectView.RowPlan {
        UploadToAppStoreConnectView.RowPlan(
            id: UUID(),
            rowLabel: label,
            rowSize: size,
            templateCount: ASCUploadLimits.minScreenshotsPerSet,
            isEnabled: true,
            detectedDisplayType: displayType,
            selectedDisplayType: displayType,
            localeTargets: [
                UploadToAppStoreConnectView.LocaleTarget(
                    appLocaleCode: "en",
                    appLocaleLabel: "English",
                    selectedASCLocalizationIds: [localization.id],
                    candidates: [localization],
                    isEnabled: true
                )
            ]
        )
    }
}

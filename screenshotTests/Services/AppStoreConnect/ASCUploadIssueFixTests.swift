import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

/// The plan banner used to repeat one identical locale error per locale — seven lines for two
/// rows. These pin the merged shape and the one-click fixes the merged lines carry.
@MainActor
struct ASCUploadIssueFixTests {

    // MARK: - Fixtures

    private func localization(_ locale: String) -> ASCAppStoreVersionLocalization {
        ASCAppStoreVersionLocalization(id: "loc-\(locale)", attributes: .init(locale: locale))
    }

    private func target(
        _ code: String,
        candidates: [ASCAppStoreVersionLocalization],
        selectedIds: Set<String> = [],
        isEnabled: Bool = true
    ) -> ASCLocaleTarget {
        ASCLocaleTarget(
            appLocaleCode: code,
            appLocaleLabel: code.uppercased(),
            selectedASCLocalizationIds: selectedIds,
            candidates: candidates,
            isEnabled: isEnabled
        )
    }

    private func rowPlan(
        label: String = "Phone",
        size: CGSize = CGSize(width: 1290, height: 2796),
        detected: ASCDisplayType? = .iphone67,
        selected: ASCDisplayType?,
        targets: [ASCLocaleTarget]
    ) -> ASCRowPlan {
        ASCRowPlan(
            id: UUID(),
            rowLabel: label,
            rowSize: size,
            templateCount: ASCUploadLimits.recommendedScreenshotsPerSet,
            isEnabled: true,
            detectedAssetType: detected,
            selectedAssetType: selected,
            localeTargets: targets,
            inferredStorePlatform: .apple
        )
    }

    private func version(id: String = "version-1", platform: String = "IOS") -> ASCAppStoreVersion {
        ASCAppStoreVersion(
            id: id,
            attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: platform)
        )
    }

    // MARK: - Merging

    @Test func unselectedLocalesBecomeOneIssuePerRow() {
        let plan = rowPlan(
            selected: .iphone67,
            targets: [
                target("es", candidates: [localization("es-ES")]),
                target("it", candidates: [localization("it")]),
                target("ko", candidates: [localization("ko")]),
            ]
        )

        let issues = AppStoreConnectUploadValidator.validate(version: version(), plans: [plan])
        let unselected = issues.filter { $0.message.contains("App Store locales for") }

        #expect(unselected.count == 1)
        for code in ["ES", "IT", "KO"] {
            #expect(unselected.first?.message.contains(code) == true)
        }
        #expect(unselected.first?.fix?.appLocaleCodes == ["es", "it", "ko"])
    }

    @Test func unmatchedLocalesBecomeOneIssuePerRow() {
        let plan = rowPlan(
            selected: .iphone67,
            targets: [
                target("en", candidates: [localization("en-US")], selectedIds: ["loc-en-US"]),
                target("sk", candidates: []),
                target("fa", candidates: []),
            ]
        )

        let issues = AppStoreConnectUploadValidator.validate(version: version(), plans: [plan])
        let unmatched = issues.filter { $0.message.contains("No App Store locale matches") }

        #expect(unmatched.count == 1)
        #expect(unmatched.first?.message.contains("SK") == true)
        #expect(unmatched.first?.message.contains("FA") == true)
    }

    // MARK: - Fixes

    @Test func missingDisplayTypeOffersTheDetectedOne() {
        let plan = rowPlan(
            selected: nil,
            targets: [target("en", candidates: [localization("en-US")], selectedIds: ["loc-en-US"])]
        )

        let issue = AppStoreConnectUploadValidator.validate(version: version(), plans: [plan])
            .first { $0.message.contains("Pick a display type") }

        #expect(issue?.fix?.action == .useDetectedAssetType)
        #expect(issue?.fix?.rowId == plan.id)
    }

    /// A detection the version's platform rejects would swap one blocking error for another, so
    /// there is nothing to offer.
    @Test func noFixWhenTheDetectedTypeIsAlsoUnusable() {
        let plan = rowPlan(
            size: CGSize(width: 1290, height: 2796),
            detected: .iphone67,
            selected: nil,
            targets: [target("en", candidates: [localization("en-US")], selectedIds: ["loc-en-US"])]
        )

        let issue = AppStoreConnectUploadValidator.validate(version: version(platform: "MAC_OS"), plans: [plan])
            .first { $0.message.contains("Pick a display type") }

        #expect(issue != nil)
        #expect(issue?.fix == nil)
    }

    @Test func applyingTheLocaleFixSelectsEveryMatchAndEnablesTheLocale() {
        let plan = rowPlan(
            selected: .iphone67,
            targets: [
                target("es", candidates: [localization("es-ES"), localization("es-MX")]),
                target("it", candidates: [localization("it")], isEnabled: false),
            ]
        )
        let model = ASCUploadFlowModel(credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        model.updateDestinationPlans([
            ASCDestinationPlan(id: "version-1", version: version(), localizations: [], rowPlans: [plan])
        ])

        let fix = UploadIssueFix(
            .selectMatchingStoreLocales,
            destinationId: "version-1",
            rowId: plan.id,
            appLocaleCodes: ["es", "it"]
        )
        model.apply(fix)

        let targets = model.destinationPlans[0].rowPlans[0].localeTargets
        #expect(targets.allSatisfy { $0.isEnabled })
        #expect(targets[0].selectedASCLocalizationIds == ["loc-es-ES", "loc-es-MX"])
        #expect(targets[1].selectedASCLocalizationIds == ["loc-it"])
        #expect(!model.validationIssues.contains { $0.message.contains("App Store locale") })
    }

    @Test func applyingTheDisplayTypeFixSelectsTheDetectedType() {
        let plan = rowPlan(
            selected: nil,
            targets: [target("en", candidates: [localization("en-US")], selectedIds: ["loc-en-US"])]
        )
        let model = ASCUploadFlowModel(credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        model.updateDestinationPlans([
            ASCDestinationPlan(id: "version-1", version: version(), localizations: [], rowPlans: [plan])
        ])

        model.apply(UploadIssueFix(.useDetectedAssetType, destinationId: "version-1", rowId: plan.id))

        #expect(model.destinationPlans[0].rowPlans[0].selectedAssetType == .iphone67)
    }

    /// A fix tapped against a plan a Refresh has already replaced must not touch another row.
    @Test func applyingAFixForAMissingRowChangesNothing() {
        let plan = rowPlan(
            selected: .iphone67,
            targets: [target("es", candidates: [localization("es-ES")])]
        )
        let model = ASCUploadFlowModel(credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        model.updateDestinationPlans([
            ASCDestinationPlan(id: "version-1", version: version(), localizations: [], rowPlans: [plan])
        ])

        model.apply(UploadIssueFix(.selectMatchingStoreLocales, destinationId: "version-1", rowId: UUID(), appLocaleCodes: ["es"]))
        model.apply(UploadIssueFix(.selectMatchingStoreLocales, destinationId: "other", rowId: plan.id, appLocaleCodes: ["es"]))

        #expect(model.destinationPlans[0].rowPlans[0].localeTargets[0].selectedASCLocalizationIds.isEmpty)
    }
}

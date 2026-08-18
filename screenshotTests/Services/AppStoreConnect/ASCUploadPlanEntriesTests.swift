import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

// The plan fan-out used to be five computed properties on a SwiftUI view, re-derived on every
// body pass. Now it is a value built once per plan change — which introduces a staleness risk
// these tests exist to close.
@MainActor
struct ASCUploadPlanEntriesTests {

    // MARK: - Fixtures

    private func localization(_ locale: String) -> ASCAppStoreVersionLocalization {
        ASCAppStoreVersionLocalization(
            id: "loc-\(locale)",
            attributes: .init(locale: locale)
        )
    }

    private func target(
        appLocaleCode: String,
        candidates: [ASCAppStoreVersionLocalization],
        selectedIds: Set<String>? = nil,
        isEnabled: Bool = true
    ) -> ASCLocaleTarget {
        ASCLocaleTarget(
            appLocaleCode: appLocaleCode,
            appLocaleLabel: appLocaleCode.uppercased(),
            selectedASCLocalizationIds: selectedIds ?? Set(candidates.prefix(1).map(\.id)),
            candidates: candidates,
            isEnabled: isEnabled
        )
    }

    private func rowPlan(
        label: String,
        templateCount: Int = 2,
        assetType: ASCDisplayType? = .iphone67,
        targets: [ASCLocaleTarget],
        isEnabled: Bool = true
    ) -> ASCRowPlan {
        ASCRowPlan(
            id: UUID(),
            rowLabel: label,
            rowSize: CGSize(width: 1290, height: 2796),
            templateCount: templateCount,
            isEnabled: isEnabled,
            detectedAssetType: assetType,
            selectedAssetType: assetType,
            localeTargets: targets,
            inferredStorePlatform: .apple
        )
    }

    private func destination(_ id: String, rowPlans: [ASCRowPlan]) -> ASCDestinationPlan {
        ASCDestinationPlan(
            id: id,
            version: ASCAppStoreVersion(
                id: id,
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
            ),
            localizations: [],
            rowPlans: rowPlans
        )
    }

    // MARK: - Tests

    @Test func emptyIsAllZeroes() {
        let plan = ASCUploadPlanEntries.empty
        #expect(plan.all.isEmpty)
        #expect(plan.selected.isEmpty)
        #expect(plan.skipped.isEmpty)
        #expect(plan.screenshotCount == 0)
        #expect(plan.versionCount == 0)
        #expect(plan.localeCount == 0)
    }

    @Test func oneEntryPerSelectedCandidate() {
        let en = localization("en-US")
        let plan = ASCUploadPlanEntries(destinations: [
            destination("v1", rowPlans: [rowPlan(label: "Hero", targets: [
                target(appLocaleCode: "en", candidates: [en])
            ])])
        ])

        #expect(plan.all.count == 1)
        #expect(plan.selected.count == 1)
        #expect(plan.skipped.isEmpty)
        #expect(plan.selected[0].appStoreLocaleCode == "en-US")
        // Screenshot count is the row's template count, once per selected candidate.
        #expect(plan.screenshotCount == 2)
    }

    @Test func aLocaleFanningOutToTwoStoreLocalesMakesTwoEntries() {
        let plan = ASCUploadPlanEntries(destinations: [
            destination("v1", rowPlans: [rowPlan(label: "Hero", targets: [
                target(
                    appLocaleCode: "en",
                    candidates: [localization("en-US"), localization("en-GB")],
                    selectedIds: ["loc-en-US", "loc-en-GB"]
                )
            ])])
        ])

        #expect(plan.selected.count == 2)
        #expect(plan.screenshotCount == 4)
        #expect(Set(plan.selected.compactMap(\.appStoreLocaleCode)) == ["en-US", "en-GB"])
    }

    /// Each skip has a distinct reason, and the entry is still emitted so the plan screen can
    /// explain why a row/locale is not being uploaded.
    @Test func eachKindOfSkipIsReportedOnce() {
        let en = localization("en-US")
        let plan = ASCUploadPlanEntries(destinations: [
            destination("v1", rowPlans: [
                rowPlan(label: "NoStoreLocale", targets: [target(appLocaleCode: "xx", candidates: [])]),
                rowPlan(label: "Unchecked", targets: [target(appLocaleCode: "en", candidates: [en], isEnabled: false)]),
                rowPlan(label: "NoDisplayType", assetType: nil, targets: [target(appLocaleCode: "en", candidates: [en])]),
                rowPlan(label: "NoneSelected", targets: [target(appLocaleCode: "en", candidates: [en], selectedIds: [])]),
            ])
        ])

        #expect(plan.selected.isEmpty)
        #expect(plan.skipped.count == 4)
        #expect(plan.screenshotCount == 0)
        #expect(plan.skipped.allSatisfy { $0.skipReason != nil })
        #expect(Set(plan.skipped.compactMap(\.skipReason)).count == 4, "each skip explains itself differently")
    }

    @Test func aDisabledRowPlanContributesNothingAtAll() {
        let plan = ASCUploadPlanEntries(destinations: [
            destination("v1", rowPlans: [
                rowPlan(label: "Off", targets: [target(appLocaleCode: "en", candidates: [localization("en-US")])], isEnabled: false)
            ])
        ])
        #expect(plan.all.isEmpty, "a disabled row isn't even listed as skipped")
    }

    @Test func groupsAndCountsSpanDestinations() {
        let rows = [
            rowPlan(label: "A", targets: [target(appLocaleCode: "en", candidates: [localization("en-US")])]),
            rowPlan(label: "B", targets: [target(appLocaleCode: "de", candidates: [localization("de-DE")])]),
        ]
        let plan = ASCUploadPlanEntries(destinations: [
            destination("v1", rowPlans: rows),
            destination("v2", rowPlans: rows),
        ])

        #expect(plan.selected.count == 4)
        #expect(plan.versionCount == 2)
        // Locale count is per (destination, store locale), not per locale.
        #expect(plan.localeCount == 4)
        // One row group per (destination, row).
        #expect(plan.rowGroups.count == 4)
        #expect(plan.screenshotCount == 8)
    }

    /// Row groups keep the order the plan generated them in, so the plan screen doesn't reshuffle
    /// rows relative to the editor.
    @Test func rowGroupsPreserveSourceOrder() {
        let plan = ASCUploadPlanEntries(destinations: [
            destination("v1", rowPlans: [
                rowPlan(label: "First", targets: [target(appLocaleCode: "en", candidates: [localization("en-US")])]),
                rowPlan(label: "Second", targets: [target(appLocaleCode: "en", candidates: [localization("en-US")])]),
                rowPlan(label: "Third", targets: [target(appLocaleCode: "en", candidates: [localization("en-US")])]),
            ])
        ])
        #expect(plan.rowGroups.map(\.rowLabel) == ["First", "Second", "Third"])
    }

    // MARK: - The staleness trap

    /// The whole point of `private(set) destinationPlans` + `updateDestinationPlans`: a write that
    /// bypassed the setter would leave `planEntries` describing the previous plan.
    @Test func writingThroughTheModelRefreshesTheMemo() {
        let model = ASCUploadFlowModel(credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        #expect(model.planEntries.all.isEmpty)

        model.updateDestinationPlans([
            destination("v1", rowPlans: [rowPlan(label: "Hero", targets: [
                target(appLocaleCode: "en", candidates: [localization("en-US")])
            ])])
        ])
        #expect(model.planEntries.selected.count == 1)
        #expect(model.planEntries.screenshotCount == 2)

        model.updateDestinationPlans([])
        #expect(model.planEntries.all.isEmpty, "clearing the plan must clear the memo")
    }

    @Test func theBindingAlsoRefreshesTheMemo() {
        let model = ASCUploadFlowModel(credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        model.destinationPlansBinding.wrappedValue = [
            destination("v1", rowPlans: [rowPlan(label: "Hero", targets: [
                target(appLocaleCode: "en", candidates: [localization("en-US")])
            ])])
        ]
        #expect(model.planEntries.selected.count == 1)
    }
}

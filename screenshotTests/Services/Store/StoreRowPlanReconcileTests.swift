import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

struct StoreRowPlanReconcileTests {
    private func locale(_ code: String, enabled: Bool = true) -> GPLocaleTarget {
        GPLocaleTarget(appLocaleCode: code, appLocaleLabel: code, playLanguageCode: code, isEnabled: enabled)
    }

    private func plan(id: UUID = UUID(), enabled: Bool = true, locales: [GPLocaleTarget]) -> GPRowPlan {
        GPRowPlan(
            id: id, rowLabel: "Hero", rowSize: CGSize(width: 1080, height: 1920), templateCount: 2,
            isEnabled: enabled, detectedAssetType: .phoneScreenshots, selectedAssetType: .phoneScreenshots,
            localeTargets: locales, inferredStorePlatform: nil
        )
    }

    @Test func aRowTheUserNeverReviewedStaysOut() {
        let reviewed = plan(locales: [locale("en")])
        let rebuilt = [reviewed, plan(locales: [locale("en")])]
        #expect(GPRowPlan.reconciling([reviewed], with: rebuilt).map(\.id) == [reviewed.id])
    }

    @Test func aLocaleAddedSinceTheReviewStartsOff() {
        let id = UUID()
        let reconciled = GPRowPlan.reconciling(
            [plan(id: id, locales: [locale("en")])],
            with: [plan(id: id, locales: [locale("en"), locale("fr")])]
        )
        #expect(reconciled.first?.localeTargets.map(\.isEnabled) == [true, false])
    }

    @Test func emptiedOnlyWhenTheReviewedPlanHadSomethingToUpload() {
        let id = UUID()
        let reviewed = [plan(id: id, locales: [locale("en")])]
        #expect(GPRowPlan.reconcileEmptied(reviewed, into: []))
        #expect(GPRowPlan.reconcileEmptied(reviewed, into: [plan(id: id, locales: [])]))
        #expect(!GPRowPlan.reconcileEmptied(reviewed, into: reviewed))
        #expect(!GPRowPlan.reconcileEmptied([plan(enabled: false, locales: [locale("en")])], into: []))
    }
}

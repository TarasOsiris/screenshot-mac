import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

struct StoreRowPlanReconcileTests {
    @Test func aRowTheUserNeverReviewedStaysOut() {
        let reviewed = makeGPRowPlan(locales: [makeGPLocaleTarget("en")])
        let rebuilt = [reviewed, makeGPRowPlan(locales: [makeGPLocaleTarget("en")])]
        #expect(GPRowPlan.reconciling([reviewed], with: rebuilt).map(\.id) == [reviewed.id])
    }

    @Test func aLocaleAddedSinceTheReviewStartsOff() {
        let id = UUID()
        let reconciled = GPRowPlan.reconciling(
            [makeGPRowPlan(id: id, locales: [makeGPLocaleTarget("en")])],
            with: [makeGPRowPlan(id: id, locales: [makeGPLocaleTarget("en"), makeGPLocaleTarget("fr")])]
        )
        #expect(reconciled.first?.localeTargets.map(\.isEnabled) == [true, false])
    }

    @Test func emptiedOnlyWhenTheReviewedPlanHadSomethingToUpload() {
        let id = UUID()
        let reviewed = [makeGPRowPlan(id: id, locales: [makeGPLocaleTarget("en")])]
        #expect(GPRowPlan.reconcileEmptied(reviewed, into: []))
        #expect(GPRowPlan.reconcileEmptied(reviewed, into: [makeGPRowPlan(id: id, locales: [])]))
        #expect(!GPRowPlan.reconcileEmptied(reviewed, into: reviewed))
        #expect(!GPRowPlan.reconcileEmptied([makeGPRowPlan(enabled: false, locales: [makeGPLocaleTarget("en")])], into: []))
    }
}

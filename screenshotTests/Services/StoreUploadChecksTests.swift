import Foundation
@testable import Screenshot_Bro
import Testing

struct StoreUploadChecksTests {

    private func claim(_ row: String, _ key: String) -> UploadTargetClaim {
        UploadTargetClaim(rowName: row, key: key)
    }

    private func collisions(_ claims: [UploadTargetClaim]) -> [UploadIssue] {
        StoreUploadChecks.collisionIssues(claims) { rowName, partner in
            UploadIssue(severity: .error, scope: rowName, message: "\(rowName) collides with \(partner)")
        }
    }

    // MARK: - Row naming

    @Test func unlabelledRowsGetAPlaceholderName() {
        #expect(StoreUploadChecks.rowName("") == "Row")
        #expect(StoreUploadChecks.rowName("Onboarding") == "Onboarding")
    }

    @Test func sizeLabelDropsFractionalPixels() {
        #expect(StoreUploadChecks.sizeLabel(CGSize(width: 1242, height: 2688)) == "1242×2688")
        #expect(StoreUploadChecks.sizeLabel(CGSize(width: 1242.7, height: 2688.2)) == "1242×2688")
    }

    // MARK: - Early exits

    @Test func noPlansBlocks() {
        let issue = StoreUploadChecks.emptyPlansIssue(planCount: 0, enabledCount: 0)
        #expect(issue?.severity == .error)
        #expect(issue?.hint != nil)
    }

    @Test func plansButNoneEnabledBlocks() {
        let issue = StoreUploadChecks.emptyPlansIssue(planCount: 3, enabledCount: 0)
        #expect(issue?.severity == .error)
    }

    @Test func atLeastOneEnabledPlanPasses() {
        #expect(StoreUploadChecks.emptyPlansIssue(planCount: 3, enabledCount: 1) == nil)
    }

    // MARK: - Collision detection

    @Test func distinctTargetsDoNotCollide() {
        #expect(collisions([claim("A", "en|PHONE"), claim("B", "de|PHONE")]).isEmpty)
    }

    @Test func firstClaimWinsAndTheSecondReports() {
        let issues = collisions([claim("A", "en|PHONE"), claim("B", "en|PHONE")])
        #expect(issues.count == 1)
        #expect(issues[0].scope == "B", "the row that arrives second is the one told about the clash")
        #expect(issues[0].message.contains("with A"))
    }

    /// The reason the algorithm tracks partners at all: two rows sharing twelve locales must
    /// report once, not twelve times.
    @Test func collidingRowsAcrossManyLocalesReportOncePerPartner() {
        let locales = ["en", "de", "fr", "es", "it", "ja", "ko", "pt", "nl", "sv", "da", "fi"]
        let claims = locales.map { claim("A", "\($0)|PHONE") } + locales.map { claim("B", "\($0)|PHONE") }
        let issues = collisions(claims)
        #expect(issues.count == 1)
    }

    @Test func threeWayCollisionReportsEachPartnerSeparately() {
        let issues = collisions([claim("A", "en|PHONE"), claim("B", "en|PHONE"), claim("C", "en|PHONE")])
        // B clashes with A; C clashes with A too (A owns the key).
        #expect(issues.count == 2)
        #expect(Set(issues.map(\.scope)) == ["B", "C"])
    }

    /// Two unlabelled rows both read as "Row" — that is still a real collision.
    @Test func identicallyNamedRowsStillCollide() {
        let issues = collisions([claim("Row", "en|PHONE"), claim("Row", "en|PHONE")])
        #expect(issues.count == 1)
    }

    @Test func differentAssetTypesOnTheSameLocaleDoNotCollide() {
        #expect(collisions([claim("A", "en|PHONE"), claim("B", "en|TABLET")]).isEmpty)
    }

    @Test func noClaimsProducesNoIssues() {
        #expect(collisions([]).isEmpty)
    }

    @Test func aSingleClaimProducesNoIssues() {
        #expect(collisions([claim("A", "en|PHONE")]).isEmpty)
    }
}

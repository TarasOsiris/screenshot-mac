import Foundation
@testable import Screenshot_Bro
import Testing

struct StoreUploadChecksTests {

    /// Rows are identified by id, so two claims meaning "the same row" need the same UUID.
    /// Deriving it from the label keeps the tests reading the way they did.
    private func rowId(_ label: String) -> UUID {
        var bytes = Array(label.utf8.prefix(16))
        bytes.append(contentsOf: repeatElement(0, count: 16 - bytes.count))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func claim(_ row: String, _ key: String, locale: String = "English") -> UploadTargetClaim {
        UploadTargetClaim(rowId: rowId(row), rowName: row, targetLabel: locale, key: key, slotLabel: key)
    }

    private func collisions(_ claims: [UploadTargetClaim]) -> [UploadIssue] {
        StoreUploadChecks.collisionIssues(
            claims,
            sameRow: { rowName, labels, slot in
                UploadIssue(severity: .error, scope: rowName, message: "\(labels.joined(separator: "+")) share \(slot)")
            },
            otherRow: { rowName, partner in
                UploadIssue(severity: .error, scope: rowName, message: "\(rowName) collides with \(partner)")
            }
        )
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

    /// Two unlabelled rows both read as "Row", and that is still a real collision between two
    /// rows — the check tells them apart by id, not by the name it puts in the message.
    @Test func identicallyNamedRowsStillCollide() {
        let first = UploadTargetClaim(rowId: UUID(), rowName: "Row", targetLabel: "English", key: "en|PHONE", slotLabel: "en")
        let second = UploadTargetClaim(rowId: UUID(), rowName: "Row", targetLabel: "English", key: "en|PHONE", slotLabel: "en")
        let issues = collisions([first, second])
        #expect(issues.count == 1)
        #expect(issues[0].message.contains("collides with"))
    }

    // MARK: - Collisions inside one row

    /// Several project locales can map to one store language ("en" and "en-US" both reach Play's
    /// en-US). Disabling a row cannot fix that, so it must not be reported as a row clash.
    @Test func oneRowClaimingASlotTwiceReportsItself() {
        let issues = collisions([
            claim("Android Phone", "en-US|PHONE", locale: "English"),
            claim("Android Phone", "en-US|PHONE", locale: "English (US)")
        ])
        #expect(issues.count == 1)
        #expect(issues[0].scope == "Android Phone")
        #expect(issues[0].message == "English+English (US) share en-US|PHONE")
    }

    @Test func aSlotClaimedThreeTimesInOneRowReportsOnceNamingAll() {
        let issues = collisions([
            claim("A", "en-US|PHONE", locale: "English"),
            claim("A", "en-US|PHONE", locale: "English (UK)"),
            claim("A", "en-US|PHONE", locale: "English (US)")
        ])
        #expect(issues.count == 1)
        #expect(issues[0].message == "English+English (UK)+English (US) share en-US|PHONE")
    }

    /// A row that duplicates a slot internally still owns it against other rows — once.
    @Test func anInternalDuplicateStillCollidesWithAnotherRow() {
        let issues = collisions([
            claim("A", "en-US|PHONE", locale: "English"),
            claim("A", "en-US|PHONE", locale: "English (US)"),
            claim("B", "en-US|PHONE")
        ])
        #expect(issues.count == 2)
        #expect(issues.filter { $0.scope == "B" }.count == 1)
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

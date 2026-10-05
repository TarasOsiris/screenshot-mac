import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ASCListingConsistencyTests {

    // MARK: - Fixtures

    private func localization(_ locale: String) -> ASCAppStoreVersionLocalization {
        ASCAppStoreVersionLocalization(id: "loc-\(locale)", attributes: .init(locale: locale))
    }

    private func target(
        _ appLocaleCode: String,
        _ candidates: [ASCAppStoreVersionLocalization],
        isEnabled: Bool = true
    ) -> ASCLocaleTarget {
        ASCLocaleTarget(
            appLocaleCode: appLocaleCode,
            appLocaleLabel: appLocaleCode,
            selectedASCLocalizationIds: Set(candidates.map(\.id)),
            candidates: candidates,
            isEnabled: isEnabled
        )
    }

    private func row(
        templateCount: Int = 7,
        displayType: ASCDisplayType? = .desktop,
        targets: [ASCLocaleTarget],
        isEnabled: Bool = true
    ) -> ASCRowPlan {
        ASCRowPlan(
            id: UUID(),
            rowLabel: "Mac",
            rowSize: CGSize(width: 2880, height: 1800),
            templateCount: templateCount,
            isEnabled: isEnabled,
            detectedAssetType: displayType,
            selectedAssetType: displayType,
            localeTargets: targets,
            inferredStorePlatform: .apple
        )
    }

    private func destination(_ localizations: [ASCAppStoreVersionLocalization], row: ASCRowPlan) -> ASCDestinationPlan {
        ASCDestinationPlan(
            id: "version",
            version: ASCAppStoreVersion(
                id: "version",
                attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "MAC_OS")
            ),
            localizations: localizations,
            rowPlans: [row]
        )
    }

    private func issues(
        _ row: ASCRowPlan,
        _ localizations: [ASCAppStoreVersionLocalization],
        counts: [String: [String: Int]],
        primaryLocale: String? = "en-US"
    ) -> [UploadIssue] {
        ASCListingConsistency.issues(
            row: row,
            in: destination(localizations, row: row),
            remoteCounts: counts,
            primaryLocale: primaryLocale
        )
    }

    private func mac(_ count: Int) -> [String: Int] { ["APP_DESKTOP": count] }

    // MARK: - Tests

    @Test func evenSetsAreQuiet() {
        let en = localization("en-US"), de = localization("de-DE"), fr = localization("fr-FR")
        let plan = row(targets: [target("en", [en])])
        #expect(issues(plan, [en, de, fr], counts: [de.id: mac(7), fr.id: mac(7)]).isEmpty)
    }

    @Test func targetingAnOutlierEvensItOut() {
        let en = localization("en-US"), hu = localization("hu")
        let plan = row(templateCount: 6, displayType: .iphone69, targets: [target("en", [en]), target("hu", [hu])])
        #expect(issues(plan, [en, hu], counts: [hu.id: ["APP_IPHONE_67": 7]]).isEmpty)
    }

    @Test func untargetedOutliersAreListedAgainstTheMajority() throws {
        let en = localization("en-US"), de = localization("de-DE"), id = localization("id")
        let zh = localization("zh-Hans"), frCA = localization("fr-CA")
        let plan = row(targets: [target("en", [en]), target("de", [de])])
        let found = issues(plan, [en, de, id, zh, frCA], counts: [id.id: mac(2), zh.id: mac(4), frCA.id: mac(5)])
        #expect(found.count == 1)
        let issue = try #require(found.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Most locales have 7 Mac screenshots"))
        #expect(issue.message.contains("fr-CA has 5"))
        #expect(issue.message.contains("id has 2"))
        #expect(issue.message.contains("zh-Hans has 4"))
        #expect(issue.fix == nil)
        #expect(issue.hint?.contains("Not in this project") == true)
    }

    @Test func singleOutlierNamesEveryOtherLocale() throws {
        let en = localization("en-US"), de = localization("de-DE"), hu = localization("hu")
        let plan = row(templateCount: 6, displayType: .iphone69, targets: [target("en", [en]), target("de", [de])])
        let issue = try #require(issues(plan, [en, de, hu], counts: [hu.id: ["APP_IPHONE_67": 7]]).first)
        #expect(issue.message.contains("hu has 7 iPhone 6.9\" screenshots where every other locale has 6"))
    }

    @Test func noSetFallsBackToThePrimaryLanguage() throws {
        let en = localization("en-US"), sk = localization("sk"), sl = localization("sl-SI")
        let plan = row(targets: [target("en", [en])])
        let issue = try #require(issues(plan, [en, sk, sl], counts: [sk.id: [:], sl.id: ["APP_IPHONE_67": 3]]).first)
        let english = LocaleDefinition.displayName(forCode: "en-US")
        #expect(issue.message.contains("sk and sl-SI have no Mac set, so they fall back to \(english)"))
    }

    @Test func otherSizeOfTheFamilyIsNotAFallback() throws {
        let en = localization("en-US"), it = localization("it")
        let plan = row(templateCount: 6, displayType: .iphone69, targets: [target("en", [en])])
        let issue = try #require(issues(plan, [en, it], counts: [it.id: ["APP_IPHONE_65": 6]]).first)
        #expect(issue.message == "it has no iPhone 6.9\" set.")
    }

    @Test func missingPrimaryIsCalledOut() {
        let en = localization("en-US"), de = localization("de-DE"), sk = localization("sk")
        let plan = row(targets: [target("de", [de])])
        let found = issues(plan, [en, de, sk], counts: [en.id: [:], sk.id: [:]])
        #expect(found.contains { $0.message.contains("en-US, the primary language, has no Mac set") })
        #expect(found.contains { $0.message == "sk has no Mac set." })
        #expect(!found.contains { $0.message.contains("fall back to") && !$0.message.contains("nothing to fall back to") })
    }

    @Test func unknownCountsClaimNothing() {
        let en = localization("en-US"), de = localization("de-DE"), fr = localization("fr-FR")
        let plan = row(targets: [target("en", [en])])
        #expect(issues(plan, [en, de, fr], counts: [:]).isEmpty)
    }

    @Test func disabledRowOrNoDisplayTypeIsQuiet() {
        let en = localization("en-US"), id = localization("id")
        let counts = [id.id: mac(2)]
        #expect(issues(row(targets: [target("en", [en])], isEnabled: false), [en, id], counts: counts).isEmpty)
        #expect(issues(row(displayType: nil, targets: [target("en", [en])]), [en, id], counts: counts).isEmpty)
    }

    @Test func deselectedLocaleOffersTheFix() throws {
        let en = localization("en-US"), de = localization("de-DE"), id = localization("id")
        let plan = row(targets: [target("en", [en]), target("de", [de]), target("id", [id], isEnabled: false)])
        let issue = try #require(issues(plan, [en, de, id], counts: [id.id: mac(2)]).first)
        let fix = try #require(issue.fix)
        #expect(fix.action == .selectMatchingStoreLocales)
        #expect(fix.destinationId == "version")
        #expect(fix.rowId == plan.id)
        #expect(fix.appLocaleCodes == ["id"])
        #expect(issue.hint?.contains("Not in this project") != true)
    }

    @Test func anotherRowsUploadCountsAsWhatTheLocaleWillHold() {
        let en = localization("en-US"), de = localization("de-DE"), sk = localization("sk")
        let plan = row(displayType: .iphone69, targets: [target("en", [en])])
        let deRow = row(displayType: .iphone69, targets: [target("de", [de])])
        let skRow = row(displayType: .iphone65, targets: [target("sk", [sk])])
        let found = ASCListingConsistency.issues(
            row: plan,
            in: ASCDestinationPlan(
                id: "version",
                version: destination([], row: plan).version,
                localizations: [en, de, sk],
                rowPlans: [plan, deRow, skRow]
            ),
            remoteCounts: [de.id: ["APP_IPHONE_67": 3], sk.id: [:]],
            primaryLocale: "en-US"
        )
        #expect(!found.contains { $0.message.contains("de-DE") })
        #expect(found.contains { $0.message == "sk has no iPhone 6.9\" set." })
    }

    @Test func outlierClaimedByAnotherRowOffersNoFix() throws {
        let en = localization("en-US"), de = localization("de-DE")
        let plan = row(targets: [target("en", [en]), target("de", [de], isEnabled: false)])
        let deRow = row(templateCount: 3, targets: [target("de", [de])])
        let issue = try #require(ASCListingConsistency.issues(
            row: plan,
            in: ASCDestinationPlan(
                id: "version",
                version: destination([], row: plan).version,
                localizations: [en, de],
                rowPlans: [plan, deRow]
            ),
            remoteCounts: [:],
            primaryLocale: "en-US"
        ).first)
        #expect(issue.message == "de-DE has 3 Mac screenshots where every other locale has 7.")
        #expect(issue.fix == nil)
        #expect(issue.hint == nil)
    }

    @Test func singularCountReadsAsOneScreenshot() throws {
        let en = localization("en-US"), de = localization("de-DE")
        let plan = row(targets: [target("en", [en])])
        let issue = try #require(issues(plan, [en, de], counts: [de.id: mac(1)]).first)
        #expect(issue.message == "de-DE has 1 Mac screenshot where every other locale has 7.")
    }

    @Test func missingLocalesDropTheEveryOtherClaim() throws {
        let en = localization("en-US"), de = localization("de-DE"), sk = localization("sk")
        let plan = row(targets: [target("en", [en])])
        let found = issues(plan, [en, de, sk], counts: [de.id: mac(2), sk.id: [:]])
        #expect(found.contains { $0.message.hasPrefix("Most locales have 7 Mac screenshots, but de-DE has 2") })
        #expect(!found.contains { $0.message.contains("every other locale") })
    }

    @Test func referenceCountPrefersTheUploadOnATie() {
        #expect(ASCListingConsistency.referenceCount([6, 7], preferring: 6) == 6)
        #expect(ASCListingConsistency.referenceCount([4, 5], preferring: 6) == 5)
        #expect(ASCListingConsistency.referenceCount([7, 7, 2], preferring: 2) == 7)
        #expect(ASCListingConsistency.referenceCount([], preferring: 2) == nil)
    }
}

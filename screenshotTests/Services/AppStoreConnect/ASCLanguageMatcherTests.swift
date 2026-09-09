import Foundation
@testable import Screenshot_Bro
import Testing

// The upload wizard offers to create a missing App Store localization, which means POSTing a
// locale string Apple has to accept. The project's locale catalog is wider than the store's, so
// the mapping is a filter as much as a translation — these pin both halves.
@MainActor
struct ASCLanguageMatcherTests {

    /// The guard that matters: whatever the catalog grows into, no project code may map to a
    /// string the App Store doesn't offer.
    @Test func everyCatalogCodeMapsToNilOrARealAppStoreLanguage() {
        for entry in LocaleDefinition.catalog {
            guard let mapped = ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: entry.code) else { continue }
            #expect(
                ASCLanguageMatcher.appStoreLanguageCodes.contains(mapped),
                "\(entry.code) maps to \(mapped), which is not an App Store language"
            )
        }
    }

    @Test func bareLanguagesGainTheRegionTheStoreRequires() {
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "en") == "en-US")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "de") == "de-DE")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "nl") == "nl-NL")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "ar") == "ar-SA")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "pt") == "pt-BR")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "sl") == "sl-SI")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "bn") == "bn-BD")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "mr") == "mr-IN")
    }

    /// Chinese is script-tagged on the App Store, not region-tagged as it is on Google Play.
    @Test func chineseUsesScriptTags() {
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "zh") == "zh-Hans")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "zh-Hant") == "zh-Hant")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "zh-hans") == "zh-Hans")
    }

    /// Hebrew is `he` here; Google Play wants `iw-IL`. Easy to cross-wire between the two tables.
    @Test func hebrewIsNotThePlayCode() {
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "he") == "he")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "he") == "iw-IL")
    }

    @Test func languagesTheAppStoreDoesNotOfferMapToNil() {
        for code in ["bg", "sr", "fa", "fil", "sw", "af", "is", "cy", "eu", "gl"] {
            #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: code) == nil, "\(code)")
        }
    }

    /// Two project locales can map onto one App Store locale, and `ASCLocaleMatcher` awards it to
    /// the longer code — so `en` is left unmatched while `en-US` holds the only candidate. The
    /// wizard must not offer to create `en-US` a second time; this pins the collision the guard
    /// in `existingStoreLocaleCodes` exists for.
    @Test func twoProjectLocalesCanMapOntoOneAppStoreLocale() {
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "en") == "en-US")
        #expect(ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: "en-US") == "en-US")

        let existing = ASCAppStoreVersionLocalization(id: "loc", attributes: .init(locale: "en-US"))
        let assignment = ASCLocaleMatcher.assign(appCodes: ["en", "en-US"], to: [existing])
        #expect(assignment["en-US"]?.count == 1)
        #expect(assignment["en"] == nil, "the longer project code claims it")
    }

    /// The whole point of the mapping: a created localization has to match back to the project
    /// locale that asked for it, through the matcher the plan already uses.
    @Test func everyMappedCodeMatchesBackThroughASCLocaleMatcher() {
        for entry in LocaleDefinition.catalog {
            guard let mapped = ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: entry.code) else { continue }
            let created = ASCAppStoreVersionLocalization(id: "loc", attributes: .init(locale: mapped))
            let assignment = ASCLocaleMatcher.assign(appCodes: [entry.code], to: [created])
            #expect(assignment[entry.code]?.count == 1, "\(entry.code) -> \(mapped) does not match back")
        }
    }
}

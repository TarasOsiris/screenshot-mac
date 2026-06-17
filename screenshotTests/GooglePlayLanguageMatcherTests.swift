#if DEBUG
import Testing
@testable import Screenshot_Bro

struct GooglePlayLanguageMatcherTests {
    @Test func mapsBareLanguagesToListingCodes() {
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "en") == "en-US")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "de") == "de-DE")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "fr") == "fr-FR")
    }

    @Test func mapsPlayQuirks() {
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "he") == "iw-IL")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "zh-Hans") == "zh-CN")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "zh-Hant") == "zh-TW")
    }

    @Test func preservesRegionedCodes() {
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "pt-BR") == "pt-BR")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "en-GB") == "en-GB")
    }

    @Test func fallsBackToCodeWhenUnknown() {
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "xx") == "xx")
    }
}
#endif

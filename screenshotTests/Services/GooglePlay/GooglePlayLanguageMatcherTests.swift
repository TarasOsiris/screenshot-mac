@testable import Screenshot_Bro
import Testing

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

    /// A code Play accepts verbatim needs no table entry — that is what keeps `de-DE` (App Store
    /// Connect hands those back) and `en-IN` working.
    @Test func passesThroughCodesPlayAcceptsVerbatim() {
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "en-IN") == "en-IN")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "es-419") == "es-419")
    }

    /// Anything else has no Play listing to upload to; sending it would fail partway through.
    @Test func unsupportedCodesResolveToNothing() {
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "ar-SA") == nil, "Play's Arabic is \"ar\"")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "uz") == nil)
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "bs") == nil, "Bosnian isn't a Play listing language")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "mt") == nil, "Maltese isn't a Play listing language")
        #expect(GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: "xx") == nil)
    }

    /// The table is hand-transcribed; a value Play doesn't accept would only surface as a rejected
    /// upload. This is what caught "gu-IN" (Play uses "gu") and "mn" (Play uses "mn-MN").
    @Test func everyMappedCodeIsAPlayListingLanguage() {
        for (projectCode, playCode) in GooglePlayLanguageMatcher.table {
            #expect(
                GooglePlayListingLanguages.all.contains(playCode),
                "\(projectCode) maps to \(playCode), which Google Play does not accept"
            )
        }
    }

    // MARK: - Default selection

    /// `en` and `en-US` both land on Play's `en-US`, and Play keeps one screenshot set per
    /// language, so only one may upload.
    @Test func defaultsPickTheExactCodeWhenSeveralCollapse() {
        let codes = GooglePlayLanguageMatcher.defaultUploadCodes(among: ["en", "uk", "en-US"])
        #expect(codes == ["en-US", "uk"])
    }

    @Test func defaultsKeepTheFirstWhenNeitherCodeIsExact() {
        let codes = GooglePlayLanguageMatcher.defaultUploadCodes(among: ["zh", "zh-Hans"])
        #expect(codes == ["zh"], "both map to zh-CN and neither is spelled that way")
    }

    @Test func defaultsDropLanguagesPlayCannotAccept() {
        #expect(GooglePlayLanguageMatcher.defaultUploadCodes(among: ["ar-SA", "uk"]) == ["uk"])
    }

    @Test func defaultsKeepEveryDistinctLanguage() {
        #expect(GooglePlayLanguageMatcher.defaultUploadCodes(among: ["en", "de", "uk"]) == ["en", "de", "uk"])
    }
}

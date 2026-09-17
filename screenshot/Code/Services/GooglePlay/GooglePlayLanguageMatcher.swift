import Foundation

/// The store-listing languages Google Play accepts, verbatim as the Play Developer API spells
/// them. Play uses a few non-obvious codes (Hebrew "iw-IL", Latin American Spanish "es-419",
/// Chinese "zh-CN"/"zh-HK"/"zh-TW"), and some languages are bare while their neighbours are
/// region-qualified ("ar" but "hi-IN"), so the list is transcribed rather than derived.
/// Source: https://support.google.com/googleplay/android-developer/answer/9844778
nonisolated enum GooglePlayListingLanguages {
    static let all: Set<String> = [
        "af", "am", "ar", "az-AZ", "be", "bg", "bn-BD", "ca", "cs-CZ", "da-DK",
        "de-DE", "el-GR", "en-AU", "en-CA", "en-GB", "en-IN", "en-SG", "en-US", "en-ZA", "es-419",
        "es-ES", "es-US", "et", "eu-ES", "fa", "fa-AE", "fa-AF", "fa-IR", "fi-FI", "fil",
        "fr-CA", "fr-FR", "gl-ES", "gu", "hi-IN", "hr", "hu-HU", "hy-AM", "id", "is-IS",
        "it-IT", "iw-IL", "ja-JP", "ka-GE", "kk", "km-KH", "kn-IN", "ko-KR", "ky-KG", "lo-LA",
        "lt", "lv", "mk-MK", "ml-IN", "mn-MN", "mr-IN", "ms", "ms-MY", "my-MM", "ne-NP",
        "nl-NL", "no-NO", "pa", "pl-PL", "pt-BR", "pt-PT", "rm", "ro", "ru-RU", "si-LK",
        "sk", "sl", "sq", "sr", "sv-SE", "sw", "ta-IN", "te-IN", "th", "tr-TR",
        "uk", "ur", "vi", "zh-CN", "zh-HK", "zh-TW", "zu"
    ]
}

/// Maps the app's project locale codes (bare languages like "en", "de", or regioned ones
/// like "pt-BR") to the listing language codes Google Play expects ("en-US", "de-DE").
///
/// Returns nil when Play has no listing language for the code — Play rejects anything outside
/// `GooglePlayListingLanguages.all`, so passing an unknown code through would only surface as a
/// failure partway into an upload. Note the mapping is many-to-one ("en" and "en-US" both land on
/// "en-US"), which is why callers have to resolve duplicates rather than assume a bijection.
nonisolated enum GooglePlayLanguageMatcher {
    static func playLanguageCode(forProjectCode code: String) -> String? {
        if let mapped = table[code] { return mapped }
        if let mapped = table[code.lowercased()] { return mapped }
        return GooglePlayListingLanguages.all.contains(code) ? code : nil
    }

    /// Which project codes should upload by default when several of them map to the same Play
    /// language. Play keeps one screenshot set per language, so only one can win: prefer the
    /// project code that *is* the Play code ("en-US" over "en"), otherwise the first the project
    /// lists. Codes Play has no language for win nothing.
    static func defaultUploadCodes(among projectCodes: [String]) -> Set<String> {
        var winnerByPlayCode: [String: String] = [:]
        for code in projectCodes {
            guard let play = playLanguageCode(forProjectCode: code) else { continue }
            guard let incumbent = winnerByPlayCode[play] else {
                winnerByPlayCode[play] = code
                continue
            }
            if incumbent != play, code == play { winnerByPlayCode[play] = code }
        }
        return Set(winnerByPlayCode.values)
    }

    /// Only codes Play actually accepts may appear as a value here;
    /// `GooglePlayLanguageMatcherTests` pins that against `GooglePlayListingLanguages.all`.
    static let table: [String: String] = [
        "en": "en-US", "fr": "fr-FR", "de": "de-DE", "es": "es-ES", "it": "it-IT",
        "pt-BR": "pt-BR", "pt-PT": "pt-PT", "pt": "pt-BR",
        "nl": "nl-NL", "ru": "ru-RU", "ja": "ja-JP", "ko": "ko-KR", "zh": "zh-CN",
        "ar": "ar", "hi": "hi-IN", "tr": "tr-TR", "pl": "pl-PL", "sv": "sv-SE",
        "da": "da-DK", "fi": "fi-FI", "no": "no-NO", "uk": "uk", "th": "th",
        "vi": "vi", "id": "id", "ms": "ms", "cs": "cs-CZ", "el": "el-GR",
        "he": "iw-IL", "hu": "hu-HU", "ro": "ro", "sk": "sk", "bg": "bg",
        "hr": "hr", "sr": "sr", "ca": "ca", "fa": "fa", "bn": "bn-BD",
        "fil": "fil", "lt": "lt", "lv": "lv", "et": "et", "sl": "sl",
        "kk": "kk", "ta": "ta-IN", "te": "te-IN", "mr": "mr-IN", "sw": "sw",
        "af": "af", "gu": "gu", "kn": "kn-IN", "ml": "ml-IN", "pa": "pa",
        "my": "my-MM", "km": "km-KH", "ne": "ne-NP", "si": "si-LK", "mn": "mn-MN",
        "az": "az-AZ", "ka": "ka-GE", "hy": "hy-AM", "be": "be", "sq": "sq",
        "mk": "mk-MK", "is": "is-IS", "eu": "eu-ES",
        "gl": "gl-ES",
        "en-US": "en-US", "en-GB": "en-GB", "en-CA": "en-CA", "en-AU": "en-AU",
        "es-ES": "es-ES", "es-MX": "es-419", "fr-FR": "fr-FR", "fr-CA": "fr-CA",
        "zh-Hans": "zh-CN", "zh-Hant": "zh-TW"
    ]
}

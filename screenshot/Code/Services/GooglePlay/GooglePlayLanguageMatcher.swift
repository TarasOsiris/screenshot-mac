import Foundation

/// Maps the app's project locale codes (bare languages like "en", "de", or regioned ones
/// like "pt-BR") to the BCP-47 listing language codes Google Play expects ("en-US", "de-DE").
/// Play uses a few non-obvious codes (Hebrew "iw", Chinese "zh-CN"/"zh-TW"); a small hardcoded
/// table is clearer than locale gymnastics. Unknown codes fall back to the code as-is.
nonisolated enum GooglePlayLanguageMatcher {
    static func playLanguageCode(forProjectCode code: String) -> String {
        if let mapped = table[code] { return mapped }
        if let mapped = table[code.lowercased()] { return mapped }
        return code
    }

    private static let table: [String: String] = [
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
        "af": "af", "gu": "gu-IN", "kn": "kn-IN", "ml": "ml-IN", "pa": "pa",
        "my": "my-MM", "km": "km-KH", "ne": "ne-NP", "si": "si-LK", "mn": "mn",
        "az": "az-AZ", "ka": "ka-GE", "hy": "hy-AM", "be": "be", "sq": "sq",
        "mk": "mk-MK", "bs": "bs", "is": "is-IS", "mt": "mt", "eu": "eu-ES",
        "gl": "gl-ES",
        "en-US": "en-US", "en-GB": "en-GB", "en-CA": "en-CA", "en-AU": "en-AU",
        "es-ES": "es-ES", "es-MX": "es-419", "fr-FR": "fr-FR", "fr-CA": "fr-CA",
        "zh-Hans": "zh-CN", "zh-Hant": "zh-TW"
    ]
}

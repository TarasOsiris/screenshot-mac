import Foundation

/// Maps the app's project locale codes ("en", "bn", "zh") to the App Store language codes
/// App Store Connect will accept when creating a version localization ("en-US", "bn-BD",
/// "zh-Hans"). Nil means the App Store has no such language, which is what stops the upload
/// wizard from offering to create one: the POST would only 400.
///
/// The project's locale catalog is deliberately wider than the store's — it carries languages
/// like Swahili and Welsh that the App Store doesn't list — so this is a filter as much as a
/// translation. Every value here either equals its key or extends it with a region subtag, so
/// `ASCLocaleMatcher.assign`'s exact-or-prefix rule matches a created localization back to the
/// project locale that asked for it without any further mapping.
nonisolated enum ASCLanguageMatcher {
    static func appStoreLanguageCode(forProjectCode code: String) -> String? {
        table[code] ?? loweredTable[code.lowercased()]
    }

    /// The 50 languages the App Store offers. Used to gate the table above and pinned by tests.
    static let appStoreLanguageCodes: Set<String> = [
        "ar-SA", "bn-BD", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB",
        "en-US", "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "gu-IN", "he", "hi", "hr",
        "hu", "id", "it", "ja", "kn-IN", "ko", "ml-IN", "mr-IN", "ms", "nl-NL",
        "no", "or-IN", "pa-IN", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sl-SI",
        "sv", "ta-IN", "te-IN", "th", "tr", "uk", "ur-PK", "vi", "zh-Hans", "zh-Hant"
    ]

    private static let table: [String: String] = [
        // Bare languages the store only offers with a region or script.
        "en": "en-US", "fr": "fr-FR", "de": "de-DE", "es": "es-ES", "nl": "nl-NL",
        "ar": "ar-SA", "zh": "zh-Hans", "pt": "pt-BR", "sl": "sl-SI", "bn": "bn-BD",
        "gu": "gu-IN", "kn": "kn-IN", "ml": "ml-IN", "mr": "mr-IN", "or": "or-IN",
        "pa": "pa-IN", "ta": "ta-IN", "te": "te-IN", "ur": "ur-PK",
        // Bare languages the store takes as-is.
        "ca": "ca", "cs": "cs", "da": "da", "el": "el", "fi": "fi", "he": "he",
        "hi": "hi", "hr": "hr", "hu": "hu", "id": "id", "it": "it", "ja": "ja",
        "ko": "ko", "ms": "ms", "no": "no", "pl": "pl", "ro": "ro", "ru": "ru",
        "sk": "sk", "sv": "sv", "th": "th", "tr": "tr", "uk": "uk", "vi": "vi",
        // Already-regioned catalog codes.
        "en-US": "en-US", "en-GB": "en-GB", "en-CA": "en-CA", "en-AU": "en-AU",
        "es-ES": "es-ES", "es-MX": "es-MX", "fr-FR": "fr-FR", "fr-CA": "fr-CA",
        "pt-BR": "pt-BR", "pt-PT": "pt-PT", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant"
    ]

    /// `zh-Hans` is the only mixed-case key, so a plain second lookup on the raw table would
    /// miss a lowercased input.
    private static let loweredTable: [String: String] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.key.lowercased(), $0.value) }
    )
}

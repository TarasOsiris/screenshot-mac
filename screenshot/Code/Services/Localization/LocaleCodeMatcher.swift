import Foundation

/// Matches a store- or folder-style locale code (`de-DE`, `en_US`) to the project locale that owns
/// it: an exact match wins, otherwise the longest project code that is a language prefix of it.
enum LocaleCodeMatcher {
    static func match(_ code: String, among projectCodes: [String]) -> String? {
        let lower = code.replacingOccurrences(of: "_", with: "-").lowercased()
        var best: String?
        var bestLength = -1
        for projectCode in projectCodes {
            let projectLower = projectCode.lowercased()
            let isMatch = lower == projectLower || lower.hasPrefix(projectLower + "-")
            if isMatch && projectLower.count > bestLength {
                best = projectCode
                bestLength = projectLower.count
            }
        }
        return best
    }

    /// Whether a folder or file-name token reads as a locale code at all, so an unmatched one can
    /// be reported instead of silently ignored alongside folders like `Previews`.
    static func looksLikeLocaleCode(_ token: String) -> Bool {
        token.range(of: #"^[a-zA-Z]{2,3}([-_][a-zA-Z0-9]{2,4}){0,2}$"#, options: .regularExpression) != nil
    }
}

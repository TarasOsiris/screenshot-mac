import Foundation

/// Filename and folder-name construction for exports. Single source of truth so disk export and
/// the App Store Connect / Google Play uploads name files identically, and the exported names stay
/// in sync with the editor preview.
enum ExportFileNaming {
    private static let invalidPathScalars: Set<Unicode.Scalar> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
    private static let pathTrimSet = CharacterSet(charactersIn: " ._-").union(.whitespacesAndNewlines)

    /// Returns the input sanitized for use as a single path component:
    /// replaces path separators and other filesystem-problematic characters
    /// (`/ \ : * ? " < > |` and control characters) with `_`, collapses runs,
    /// and trims edge whitespace, dots, dashes, and underscores. Spaces and
    /// non-ASCII characters (emoji, em-dash, etc.) are preserved.
    static func sanitizedFileName(_ name: String) -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(name.unicodeScalars.count)
        var lastWasUnderscore = false
        for scalar in name.unicodeScalars {
            let isControl = scalar.value < 0x20 || scalar.value == 0x7F
            if isControl || invalidPathScalars.contains(scalar) {
                if !lastWasUnderscore && !out.isEmpty {
                    out.append("_")
                    lastWasUnderscore = true
                }
            } else {
                out.unicodeScalars.append(scalar)
                lastWasUnderscore = false
            }
        }
        return out.trimmingCharacters(in: pathTrimSet)
    }

    private static let allowedSuffixChars: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    private static let suffixTrimSet = CharacterSet(charactersIn: "._-")

    /// Sanitizes a user-supplied filename suffix. Collapses runs of invalid characters into a single `_`,
    /// trims leading/trailing separators, and caps at 64 chars so it can't blow past the filesystem name limit.
    static func sanitizedFileSuffix(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        var lastWasUnderscore = false
        for ch in raw {
            if allowedSuffixChars.contains(ch) {
                out.append(ch)
                lastWasUnderscore = false
            } else if !lastWasUnderscore && !out.isEmpty {
                out.append("_")
                lastWasUnderscore = true
            }
        }
        let trimmed = out.trimmingCharacters(in: suffixTrimSet)
        return String(trimmed.prefix(64))
    }

    /// Returns the sanitized suffix prefixed with `_`, or empty string when the input has nothing usable.
    /// Single source of truth for the export-filename suffix segment — keeps callers in sync with the editor preview.
    static func formattedFileSuffix(_ raw: String) -> String {
        let cleaned = sanitizedFileSuffix(raw)
        return cleaned.isEmpty ? "" : "_\(cleaned)"
    }

    /// The user's Settings ▸ Export filename suffix. The upload services run outside SwiftUI and have no
    /// `@AppStorage` to read, so they take it from the key that setting is bound to.
    static var preferredCustomSuffix: String {
        UserDefaults.standard.string(forKey: "exportCustomSuffix") ?? ""
    }

    static func exportFolderName(for row: ScreenshotRow) -> String {
        let base = sanitizedFileName("\(row.displayLabel) — \(Int(row.templateWidth))x\(Int(row.templateHeight))")
        return base.isEmpty ? "row" : base
    }

    /// Sanitized row label suitable for embedding in an export filename.
    /// Falls back to `"row"` when the label is empty or sanitizes away entirely.
    static func exportRowFileNameComponent(for row: ScreenshotRow) -> String {
        let sanitized = sanitizedFileName(row.displayLabel)
        return sanitized.isEmpty ? "row" : sanitized
    }

    /// The on-disk export filename for one template: `NN_Row_locale[_suffix].ext` (e.g. `01_Onboarding_en.png`).
    /// Single source of truth so disk export and App Store Connect / Google Play uploads name files identically.
    static func screenshotFileName(row: ScreenshotRow, localeCode: String, index: Int, customSuffix: String = "", format: ExportImageFormat = .png) -> String {
        let padded = String(format: "%02d", index + 1)
        let rowName = exportRowFileNameComponent(for: row)
        let localeSuffix = sanitizedFileName(localeCode)
        return "\(padded)_\(rowName)_\(localeSuffix)\(formattedFileSuffix(customSuffix)).\(format.fileExtension)"
    }

    static func sanitizedRootFolderName(_ projectName: String) -> String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "Screenshots" : trimmed
        let sanitized = sanitizedFileName(candidate)
        return sanitized.isEmpty ? "Screenshots" : sanitized
    }

    static func uniqueFolder(named baseName: String, in parent: URL) -> URL {
        let fm = FileManager.default
        let candidate = parent.appendingPathComponent(baseName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var counter = 1
        while true {
            counter += 1
            let numbered = parent.appendingPathComponent("\(baseName) (\(counter))")
            if !fm.fileExists(atPath: numbered.path) { return numbered }
        }
    }
}

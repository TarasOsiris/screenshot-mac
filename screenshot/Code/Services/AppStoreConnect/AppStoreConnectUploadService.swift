import Foundation

/// Shared request models retained for the screenshot planner. The former delete-and-recreate
/// uploader intentionally no longer exists; all screenshot writes go through the sync service.
enum AppStoreConnectUploadError: StoreUploadErrorDescribing, LocalizedError {
    case renderFailed(rowLabel: String, displayTypeLabel: String, localeLabel: String, index: Int)
    case noRowsSelected

    var errorDescription: String? {
        switch self {
        case .renderFailed(let row, let display, let locale, let index):
            String(localized: "Could not render screenshot \(index + 1) for \(row) (\(display)) in \(locale). Check that this row previews correctly, then try again.")
        case .noRowsSelected:
            String(localized: "No rows selected for upload.")
        }
    }

    var summaryDescription: String {
        switch self {
        case .renderFailed(let row, _, let locale, let index):
            String(localized: "Could not render \(row) · \(locale) · screenshot \(index + 1).")
        case .noRowsSelected:
            String(localized: "No rows selected for upload.")
        }
    }

    var technicalDescription: String {
        switch self {
        case .renderFailed(let row, let display, let locale, let index):
            "Failure: render\nRow: \(row)\nDisplay type: \(display)\nLocale: \(locale)\nScreenshot index: \(index + 1)"
        case .noRowsSelected:
            "Failure: no rows selected"
        }
    }
}

struct ASCUploadLocalization {
    let id: String
    let label: String
    let localeCode: String
}

struct ASCUploadTarget: Identifiable {
    let id = UUID()
    /// The version — or, for an experiment, the treatment — the sets belong to.
    let versionId: String
    let versionLabel: String
    /// What each of `localizations` is: a version localization, or a treatment localization.
    let parentKind: ASCScreenshotSetParentKind
    let rowId: UUID
    let rowLabel: String
    let rowSize: CGSize
    let displayType: ASCDisplayType
    let localizations: [ASCUploadLocalization]
    let templateCount: Int
}

enum ASCLocaleMatcher {
    /// Assign each App Store localization once: exact project-locale match wins, then the
    /// longest language prefix. This prevents broad locales from double-claiming a target.
    static func assign(
        appCodes: [String],
        to localizations: [ASCAppStoreVersionLocalization]
    ) -> [String: [ASCAppStoreVersionLocalization]] {
        let lowered = appCodes.map { (code: $0, lower: $0.lowercased()) }
        var result: [String: [ASCAppStoreVersionLocalization]] = [:]
        for localization in localizations {
            let ascLower = localization.attributes.locale.lowercased()
            var bestCode: String?
            var bestLength = -1
            for (code, lower) in lowered {
                let isMatch = ascLower == lower || ascLower.hasPrefix(lower + "-")
                if isMatch && lower.count > bestLength {
                    bestCode = code
                    bestLength = lower.count
                }
            }
            if let bestCode { result[bestCode, default: []].append(localization) }
        }
        return result
    }
}

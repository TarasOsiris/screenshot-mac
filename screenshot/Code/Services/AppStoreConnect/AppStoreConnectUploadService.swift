import Foundation

/// Shared request models retained for the screenshot planner. The former delete-and-recreate
/// uploader intentionally no longer exists; all screenshot writes go through the sync service.
enum AppStoreConnectUploadError: Error, LocalizedError {
    case renderFailed(rowLabel: String, displayTypeLabel: String, localeLabel: String, index: Int)
    case noRowsSelected
    case requestFailed(ASCUploadFailureContext)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let row, let display, let locale, let index):
            String(localized: "Could not render screenshot \(index + 1) for \(row) (\(display)) in \(locale). Check that this row previews correctly, then try again.")
        case .noRowsSelected:
            String(localized: "No rows selected for upload.")
        case .requestFailed(let context):
            context.detailedMessage
        }
    }

    var summaryDescription: String {
        switch self {
        case .renderFailed(let row, _, let locale, let index):
            String(localized: "Could not render \(row) · \(locale) · screenshot \(index + 1).")
        case .noRowsSelected:
            String(localized: "No rows selected for upload.")
        case .requestFailed(let context):
            context.summaryMessage
        }
    }

    var technicalDescription: String {
        switch self {
        case .renderFailed(let row, let display, let locale, let index):
            "Failure: render\nRow: \(row)\nDisplay type: \(display)\nLocale: \(locale)\nScreenshot index: \(index + 1)"
        case .noRowsSelected:
            "Failure: no rows selected"
        case .requestFailed(let context):
            context.technicalMessage
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
    let versionId: String
    let versionLabel: String
    let rowId: UUID
    let rowLabel: String
    let rowSize: CGSize
    let displayType: ASCDisplayType
    let localizations: [ASCUploadLocalization]
    let templateCount: Int
}

struct ASCUploadFailureContext {
    let operation: String
    let versionLabel: String
    let rowLabel: String
    let displayTypeLabel: String
    let displayTypeRawValue: String
    let localeLabel: String
    let localeCode: String
    let localizationId: String
    let existingSetWasDeleted: Bool
    let httpStatus: Int?
    let apiMessage: String?
    let originalMessage: String

    init(
        operation: String,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        existingSetWasDeleted: Bool,
        underlyingError: Error
    ) {
        self.operation = operation
        versionLabel = target.versionLabel
        rowLabel = target.rowLabel
        displayTypeLabel = target.displayType.label
        displayTypeRawValue = target.displayType.appStoreConnectValue
        localeLabel = localization.label
        localeCode = localization.localeCode
        localizationId = localization.id
        self.existingSetWasDeleted = existingSetWasDeleted
        if let apiError = underlyingError as? AppStoreConnectAPIError,
           case let .httpError(status, message) = apiError {
            httpStatus = status
            apiMessage = message
        } else {
            httpStatus = nil
            apiMessage = nil
        }
        originalMessage = underlyingError.localizedDescription
    }

    nonisolated var summaryMessage: String {
        if let httpStatus { return "App Store Connect returned \(httpStatus) while trying to \(operation)." }
        return "Screenshot sync failed while trying to \(operation)."
    }

    nonisolated var detailedMessage: String {
        "Could not \(operation) for \(rowLabel) (\(displayTypeLabel)) in \(localeLabel).\n\nDestination: \(versionLabel).\n\nOriginal response: \(originalMessage)"
    }

    nonisolated var technicalMessage: String {
        [
            "Operation: \(operation)",
            "Destination: \(versionLabel)",
            "Row: \(rowLabel)",
            "Display type: \(displayTypeLabel)",
            "ASC display type: \(displayTypeRawValue)",
            "Project locale: \(localeLabel) (\(localeCode))",
            "ASC localization ID: \(localizationId)",
            "HTTP status: \(httpStatus.map(String.init) ?? "none")",
            "API message: \(apiMessage ?? "none")",
            "Original response: \(originalMessage)",
        ].joined(separator: "\n")
    }
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

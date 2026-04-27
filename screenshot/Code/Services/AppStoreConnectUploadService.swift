import Foundation
import AppKit
import CryptoKit

enum AppStoreConnectUploadError: Error, LocalizedError {
    case renderFailed(rowLabel: String, displayTypeLabel: String, localeLabel: String, index: Int)
    case noRowsSelected
    case requestFailed(ASCUploadFailureContext)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let label, let displayTypeLabel, let localeLabel, let index):
            return String(localized: "Could not render screenshot \(index + 1) for \(label) (\(displayTypeLabel)) in \(localeLabel). Check that this row previews correctly in the editor, then try the upload again.")
        case .noRowsSelected:
            return String(localized: "No rows selected for upload.")
        case .requestFailed(let context):
            return context.detailedMessage
        }
    }

    var summaryDescription: String {
        switch self {
        case .renderFailed(let label, _, let localeLabel, let index):
            return String(localized: "Could not render \(label) · \(localeLabel) · screenshot \(index + 1).")
        case .noRowsSelected:
            return String(localized: "No rows selected for upload.")
        case .requestFailed(let context):
            return context.summaryMessage
        }
    }

    var technicalDescription: String {
        switch self {
        case .renderFailed(let label, let displayTypeLabel, let localeLabel, let index):
            return [
                "Failure: render",
                "Row: \(label)",
                "Display type: \(displayTypeLabel)",
                "Locale: \(localeLabel)",
                "Screenshot index: \(index + 1)"
            ].joined(separator: "\n")
        case .noRowsSelected:
            return "Failure: no rows selected"
        case .requestFailed(let context):
            return context.technicalMessage
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
    let rowId: UUID
    let rowLabel: String
    let rowSize: CGSize
    let displayType: ASCDisplayType
    let localizations: [ASCUploadLocalization]
    let templateCount: Int
}

struct ASCUploadProgress {
    var totalSteps: Int
    var completedSteps: Int
    var currentLabel: String
}

struct ASCUploadFailureContext {
    let operation: String
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
        self.rowLabel = target.rowLabel
        self.displayTypeLabel = target.displayType.label
        self.displayTypeRawValue = target.displayType.appStoreConnectValue
        self.localeLabel = localization.label
        self.localeCode = localization.localeCode
        self.localizationId = localization.id
        self.existingSetWasDeleted = existingSetWasDeleted

        if let apiError = underlyingError as? AppStoreConnectAPIError {
            switch apiError {
            case .httpError(let status, let message):
                self.httpStatus = status
                self.apiMessage = message
                self.originalMessage = "App Store Connect returned \(status): \(message)"
            case .transport(let error):
                self.httpStatus = nil
                self.apiMessage = nil
                self.originalMessage = String(localized: "Network request failed: \(error.localizedDescription)")
            default:
                self.httpStatus = nil
                self.apiMessage = nil
                self.originalMessage = apiError.localizedDescription
            }
        } else {
            self.httpStatus = nil
            self.apiMessage = nil
            self.originalMessage = underlyingError.localizedDescription
        }
    }

    var summaryMessage: String {
        if isDisplayTypeNotAllowed {
            return String(localized: "\(displayTypeLabel) is not allowed for this app/version.")
        }
        if let httpStatus {
            return String(localized: "App Store Connect returned \(httpStatus) while trying to \(operation).")
        }
        return String(localized: "Upload failed while trying to \(operation).")
    }

    var detailedMessage: String {
        if isDisplayTypeNotAllowed {
            var messages = [
                String(localized: "Could not create the screenshot set for \(rowLabel) (\(displayTypeLabel)) in \(localeLabel)."),
                String(localized: "App Store Connect does not allow \(displayTypeLabel) (\(displayTypeRawValue)) for this app version/localization. This usually means the selected app version does not support that device family, such as uploading iPad screenshots for an iPhone-only app, or App Store Connect does not accept this display type for the selected platform."),
                String(localized: "Disable this row, choose a display type that App Store Connect accepts for this app, or update the app's device support before retrying."),
            ]
            if existingSetWasDeleted {
                messages.append(String(localized: "The existing \(displayTypeLabel) screenshot set for \(localeLabel) may already have been deleted. After fixing the issue, re-run the upload to refill that set."))
            }
            messages.append(String(localized: "Original response: \(originalMessage)"))
            return messages.joined(separator: "\n\n")
        }

        if httpStatus == 401 || httpStatus == 403 {
            return [
                String(localized: "Could not \(operation) for \(rowLabel) (\(displayTypeLabel)) in \(localeLabel)."),
                String(localized: "App Store Connect rejected the request because the API key is not authorized for this app or action. Check that the key has access to this app and enough App Store Connect permissions to edit app metadata."),
                String(localized: "Original response: \(originalMessage)")
            ].joined(separator: "\n\n")
        }

        var messages = [
            String(localized: "Could not \(operation) for \(rowLabel) (\(displayTypeLabel)) in \(localeLabel)."),
            String(localized: "App Store Connect did not accept the request. Check the selected app, version, display type, and locale, then retry."),
        ]
        if existingSetWasDeleted {
            messages.append(String(localized: "The existing \(displayTypeLabel) screenshot set for \(localeLabel) may already have been deleted. After fixing the issue, re-run the upload to refill that set."))
        }
        messages.append(String(localized: "Original response: \(originalMessage)"))
        return messages.joined(separator: "\n\n")
    }

    var technicalMessage: String {
        [
            "Operation: \(operation)",
            "Row: \(rowLabel)",
            "Display type: \(displayTypeLabel)",
            "ASC display type: \(displayTypeRawValue)",
            "Project locale: \(localeLabel) (\(localeCode))",
            "ASC localization ID: \(localizationId)",
            "Existing screenshot set deleted before failure: \(existingSetWasDeleted ? "yes" : "no")",
            "HTTP status: \(httpStatus.map(String.init) ?? "none")",
            "API message: \(apiMessage ?? "none")",
            "Original response: \(originalMessage)"
        ].joined(separator: "\n")
    }

    private var isDisplayTypeNotAllowed: Bool {
        guard httpStatus == 409 else { return false }
        let lower = (apiMessage ?? originalMessage).lowercased()
        return lower.contains("display type") && lower.contains("not allowed")
    }
}

@MainActor
final class AppStoreConnectUploadService {
    static let shared = AppStoreConnectUploadService()

    private struct RenderedScreenshot {
        let templateIndex: Int
        let fileName: String
        let data: Data
    }

    private let api: AppStoreConnectAPIService
    init(api: AppStoreConnectAPIService? = nil) { self.api = api ?? .shared }

    func upload(
        targets: [ASCUploadTarget],
        appState: AppState,
        progress: @escaping (ASCUploadProgress) -> Void
    ) async throws {
        guard !targets.isEmpty else { throw AppStoreConnectUploadError.noRowsSelected }

        let totalSteps = targets.reduce(0) { acc, target in
            acc + (target.templateCount * target.localizations.count)
        }
        var completedSteps = 0
        let fontFamilies = appState.availableFontFamilySet
        // Shared across all (target × localization) iterations so unchanged base-shape images
        // are decoded once per upload rather than once per locale.
        var imageCache: [String: NSImage] = [:]

        func emit(_ label: String) {
            progress(ASCUploadProgress(totalSteps: totalSteps, completedSteps: completedSteps, currentLabel: label))
        }

        emit("Starting…")

        for target in targets {
            guard let row = appState.rows.first(where: { $0.id == target.rowId }) else { continue }

            for localization in target.localizations {
                try Task.checkCancellation()
                let planLabel = "\(target.rowLabel) · \(localization.label) · \(target.displayType.label)"
                let fileNames = appState.referencedImageFileNames(forRow: row, localeCode: localization.localeCode)
                let rowImages = appState.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                let renderedScreenshots = try renderScreenshots(
                    row: row,
                    rowImages: rowImages,
                    target: target,
                    localization: localization,
                    localeState: appState.localeState,
                    fontFamilies: fontFamilies,
                    emit: emit
                )

                // Replace mode: dropping and recreating the set is one request vs. 1+N delete-each.
                emit("Checking existing screenshots · \(planLabel)")
                let existingSets = try await performUploadStep(
                    "check existing screenshot sets",
                    target: target,
                    localization: localization
                ) {
                    try await api.listScreenshotSets(localizationId: localization.id)
                }
                var existingSetWasDeleted = false
                let appStoreConnectDisplayType = target.displayType.appStoreConnectValue
                if let match = existingSets.first(where: { $0.attributes.screenshotDisplayType == appStoreConnectDisplayType }) {
                    emit("Deleting existing screenshots · \(planLabel)")
                    try await performUploadStep(
                        "delete the existing \(target.displayType.label) screenshot set",
                        target: target,
                        localization: localization,
                        existingSetWasDeleted: existingSetWasDeleted
                    ) {
                        try await api.deleteScreenshotSet(id: match.id)
                    }
                    existingSetWasDeleted = true
                }
                emit("Creating screenshot set · \(planLabel)")
                let set = try await performUploadStep(
                    "create the \(target.displayType.label) screenshot set",
                    target: target,
                    localization: localization,
                    existingSetWasDeleted: existingSetWasDeleted
                ) {
                    try await api.createScreenshotSet(
                        localizationId: localization.id,
                        displayType: appStoreConnectDisplayType
                    )
                }

                for rendered in renderedScreenshots {
                    try Task.checkCancellation()
                    let label = "\(target.rowLabel) · \(localization.label) · \(rendered.templateIndex + 1)/\(target.templateCount)"
                    emit(label)
                    try await uploadOneScreenshot(
                        setId: set.id,
                        fileName: rendered.fileName,
                        data: rendered.data,
                        target: target,
                        localization: localization,
                        templateIndex: rendered.templateIndex,
                        existingSetWasDeleted: existingSetWasDeleted,
                        emit: emit
                    )

                    completedSteps += 1
                    emit(label)
                }
            }
        }

        emit("Done")
    }

    private func renderScreenshots(
        row: ScreenshotRow,
        rowImages: [String: NSImage],
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        localeState: LocaleState,
        fontFamilies: Set<String>,
        emit: (String) -> Void
    ) throws -> [RenderedScreenshot] {
        var screenshots: [RenderedScreenshot] = []
        screenshots.reserveCapacity(target.templateCount)

        for templateIndex in 0..<target.templateCount {
            try Task.checkCancellation()
            emit("Rendering \(target.rowLabel) · \(localization.label) · \(templateIndex + 1)/\(target.templateCount)")
            let image = ExportService.renderSingleTemplateImage(
                index: templateIndex,
                row: row,
                screenshotImages: rowImages,
                localeCode: localization.localeCode,
                localeState: localeState,
                availableFontFamilies: fontFamilies
            )
            guard let data = ExportService.encodeImage(image, format: .png) else {
                throw AppStoreConnectUploadError.renderFailed(
                    rowLabel: target.rowLabel,
                    displayTypeLabel: target.displayType.label,
                    localeLabel: localization.label,
                    index: templateIndex
                )
            }
            screenshots.append(RenderedScreenshot(
                templateIndex: templateIndex,
                fileName: Self.fileName(row: row, index: templateIndex),
                data: data
            ))
        }

        return screenshots
    }

    private func uploadOneScreenshot(
        setId: String,
        fileName: String,
        data: Data,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        templateIndex: Int,
        existingSetWasDeleted: Bool,
        emit: (String) -> Void
    ) async throws {
        let screenshotLabel = "screenshot \(templateIndex + 1)"
        let planLabel = "\(target.rowLabel) · \(localization.label) · \(screenshotLabel)"
        emit("Reserving \(planLabel)")
        let reserved = try await performUploadStep(
            "reserve \(screenshotLabel)",
            target: target,
            localization: localization,
            existingSetWasDeleted: existingSetWasDeleted
        ) {
            try await api.reserveScreenshot(setId: setId, fileName: fileName, fileSize: data.count)
        }
        let operations = reserved.attributes.uploadOperations ?? []
        for operation in operations {
            try Task.checkCancellation()
            emit("Uploading \(planLabel)")
            try await performUploadStep(
                "upload \(screenshotLabel)",
                target: target,
                localization: localization,
                existingSetWasDeleted: existingSetWasDeleted
            ) {
                try await api.uploadChunk(operation: operation, from: data)
            }
        }
        emit("Finishing \(planLabel)")
        try await performUploadStep(
            "finish \(screenshotLabel)",
            target: target,
            localization: localization,
            existingSetWasDeleted: existingSetWasDeleted
        ) {
            try await api.commitScreenshot(id: reserved.id, md5Checksum: Self.md5Hex(data: data))
        }
    }

    private func performUploadStep<T>(
        _ operation: String,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        existingSetWasDeleted: Bool = false,
        work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch {
            throw AppStoreConnectUploadError.requestFailed(ASCUploadFailureContext(
                operation: operation,
                target: target,
                localization: localization,
                existingSetWasDeleted: existingSetWasDeleted,
                underlyingError: error
            ))
        }
    }

    private static let fileNameAllowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    private static let fileNameTrimCharacters = CharacterSet(charactersIn: "-.")

    private static func fileName(row: ScreenshotRow, index: Int) -> String {
        let padded = String(format: "%02d", index + 1)
        let labelPart = row.label.isEmpty ? "screenshot" : row.label
        let sanitized = labelPart.unicodeScalars.map { scalar -> String in
            fileNameAllowedCharacters.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let trimmed = sanitized.trimmingCharacters(in: fileNameTrimCharacters)
        let safe = trimmed.isEmpty ? "screenshot" : trimmed
        return "\(padded)_\(safe).png"
    }

    private static func md5Hex(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ASCLocaleMatcher {
    /// Prefix-match "en" → "en-US"/"en-GB". Exact match wins alone.
    static func matches(appCode: String, in localizations: [ASCAppStoreVersionLocalization]) -> [ASCAppStoreVersionLocalization] {
        let lower = appCode.lowercased()
        if let exact = localizations.first(where: { $0.attributes.locale.lowercased() == lower }) {
            return [exact]
        }
        let prefix = lower + "-"
        return localizations.filter { $0.attributes.locale.lowercased().hasPrefix(prefix) }
    }
}

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum GooglePlayUploadError: Error, LocalizedError {
    case renderFailed(rowLabel: String, imageTypeLabel: String, languageLabel: String, index: Int)
    case noRowsSelected
    case requestFailed(GPUploadFailureContext)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let label, let imageTypeLabel, let languageLabel, let index):
            return String(localized: "Could not render screenshot \(index + 1) for \(label) (\(imageTypeLabel)) in \(languageLabel). Check that this row previews correctly in the editor, then try the upload again.")
        case .noRowsSelected:
            return String(localized: "No rows selected for upload.")
        case .requestFailed(let context):
            return context.detailedMessage
        }
    }

    var summaryDescription: String {
        switch self {
        case .renderFailed(let label, _, let languageLabel, let index):
            return String(localized: "Could not render \(label) · \(languageLabel) · screenshot \(index + 1).")
        case .noRowsSelected:
            return String(localized: "No rows selected for upload.")
        case .requestFailed(let context):
            return context.summaryMessage
        }
    }

    var technicalDescription: String {
        switch self {
        case .renderFailed(let label, let imageTypeLabel, let languageLabel, let index):
            return [
                "Failure: render",
                "Row: \(label)",
                "Image type: \(imageTypeLabel)",
                "Language: \(languageLabel)",
                "Screenshot index: \(index + 1)"
            ].joined(separator: "\n")
        case .noRowsSelected:
            return "Failure: no rows selected"
        case .requestFailed(let context):
            return context.technicalMessage
        }
    }
}

struct GPUploadLanguage {
    /// Project locale code used to render locale-specific text.
    let projectCode: String
    /// BCP-47 listing language Google Play expects.
    let playCode: String
    let label: String
}

struct GPUploadTarget: Identifiable {
    let id = UUID()
    let rowId: UUID
    let rowLabel: String
    let rowSize: CGSize
    let imageType: GPImageType
    let languages: [GPUploadLanguage]
    let templateCount: Int
}

struct GPUploadProgress {
    var totalSteps: Int
    var completedSteps: Int
    var currentLabel: String
}

struct GPUploadFailureContext {
    let operation: String
    let rowLabel: String
    let imageTypeLabel: String
    let languageLabel: String
    let languageCode: String
    let httpStatus: Int?
    let apiMessage: String?
    let originalMessage: String

    init(operation: String, target: GPUploadTarget, language: GPUploadLanguage, underlyingError: Error) {
        self.operation = operation
        self.rowLabel = target.rowLabel
        self.imageTypeLabel = target.imageType.label
        self.languageLabel = language.label
        self.languageCode = language.playCode

        if let apiError = underlyingError as? GooglePlayAPIError {
            switch apiError {
            case .httpError(let status, let message):
                self.httpStatus = status
                self.apiMessage = message
                self.originalMessage = "Google Play returned \(status): \(message)"
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

    private var isReviewFlagRejected: Bool {
        httpStatus == 400 && (apiMessage ?? originalMessage).localizedCaseInsensitiveContains("changesNotSentForReview")
    }

    var summaryMessage: String {
        if isReviewFlagRejected {
            return String(localized: "This app can't save an un-reviewed draft via the API — nothing was uploaded.")
        }
        if let httpStatus {
            return String(localized: "Google Play returned \(httpStatus) while trying to \(operation).")
        }
        return String(localized: "Upload failed while trying to \(operation).")
    }

    var detailedMessage: String {
        if isReviewFlagRejected {
            return [
                String(localized: "Nothing was uploaded — the edit was discarded, so your listing is untouched."),
                String(localized: "Google Play won't hold this app's listing changes as an un-reviewed draft via the API (the Play Console's \"Save draft\" has no API equivalent for a published app). Committing would send the changes to review instead."),
                String(localized: "To upload: turn on Managed publishing in the Play Console (Publishing overview → Managed publishing) so reviewed changes are held until you publish, then enable \"Send changes to review\" here and upload again. Without Managed publishing, sending to review can make the changes go live after approval."),
                String(localized: "Original response: \(originalMessage)")
            ].joined(separator: "\n\n")
        }
        if httpStatus == 401 || httpStatus == 403 {
            return [
                String(localized: "Could not \(operation) for \(rowLabel) (\(imageTypeLabel)) in \(languageLabel)."),
                String(localized: "Google Play rejected the request because the service account is not authorized for this app. In the Play Console, invite the service account under Users and permissions and grant it access to edit this app's store listing."),
                String(localized: "Original response: \(originalMessage)")
            ].joined(separator: "\n\n")
        }
        if httpStatus == 404 {
            return [
                String(localized: "Could not \(operation) for \(rowLabel) (\(imageTypeLabel)) in \(languageLabel)."),
                String(localized: "Google Play could not find the target. Check that the package name is correct and that \(languageCode) is an active store-listing language for this app."),
                String(localized: "Original response: \(originalMessage)")
            ].joined(separator: "\n\n")
        }
        return [
            String(localized: "Could not \(operation) for \(rowLabel) (\(imageTypeLabel)) in \(languageLabel)."),
            String(localized: "Google Play did not accept the request. Check the package name, image type, and language, then retry."),
            String(localized: "Original response: \(originalMessage)")
        ].joined(separator: "\n\n")
    }

    var technicalMessage: String {
        [
            "Operation: \(operation)",
            "Row: \(rowLabel)",
            "Image type: \(imageTypeLabel)",
            "Language: \(languageLabel) (\(languageCode))",
            "HTTP status: \(httpStatus.map(String.init) ?? "none")",
            "API message: \(apiMessage ?? "none")",
            "Original response: \(originalMessage)"
        ].joined(separator: "\n")
    }
}

@MainActor
final class GooglePlayUploadService {
    static let shared = GooglePlayUploadService()

    private struct RenderedScreenshot {
        let templateIndex: Int
        let fileName: String
        let data: Data
    }

    private let api: GooglePlayAPIService
    init(api: GooglePlayAPIService? = nil) { self.api = api ?? .shared }

    /// Returns whether the committed changes were sent for review (`true`) or held as a draft (`false`).
    @discardableResult
    func upload(
        packageName: String,
        targets: [GPUploadTarget],
        sendForReview: Bool,
        appState: AppState,
        progress: @escaping (GPUploadProgress) -> Void
    ) async throws -> Bool {
        guard !targets.isEmpty else { throw GooglePlayUploadError.noRowsSelected }

        let totalSteps = targets.reduce(0) { $0 + ($1.templateCount * $1.languages.count) }
        var completedSteps = 0
        let fontFamilies = appState.availableFontFamilySet
        var imageCache: [String: NSImage] = [:]

        func emit(_ label: String) {
            progress(GPUploadProgress(totalSteps: totalSteps, completedSteps: completedSteps, currentLabel: label))
        }

        emit("Starting…")
        let edit = try await performStep("open a Play Console edit", target: targets[0], language: targets[0].languages.first) {
            try await api.insertEdit(packageName: packageName)
        }

        do {
            for target in targets {
                guard let row = appState.rows.first(where: { $0.id == target.rowId }) else { continue }

                for language in target.languages {
                    try Task.checkCancellation()
                    let planLabel = "\(target.rowLabel) · \(language.label) · \(target.imageType.label)"
                    let fileNames = appState.referencedImageFileNames(forRow: row, localeCode: language.projectCode)
                    let rowImages = appState.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    let rendered = try await renderScreenshots(
                        row: row,
                        rowImages: rowImages,
                        target: target,
                        language: language,
                        localeState: appState.localeState,
                        fontFamilies: fontFamilies,
                        emit: emit
                    )

                    // Replace mode: clear the existing set for this language+type, then re-upload.
                    emit("Clearing existing screenshots · \(planLabel)")
                    try await performStep("clear existing \(target.imageType.label) screenshots", target: target, language: language) {
                        try await api.deleteAllImages(
                            packageName: packageName,
                            editId: edit.id,
                            language: language.playCode,
                            imageType: target.imageType.apiValue
                        )
                    }

                    for screenshot in rendered {
                        try Task.checkCancellation()
                        let label = "\(target.rowLabel) · \(language.label) · \(screenshot.templateIndex + 1)/\(target.templateCount)"
                        emit("Uploading \(label)")
                        _ = try await performStep("upload screenshot \(screenshot.templateIndex + 1)", target: target, language: language) {
                            try await api.uploadImage(
                                packageName: packageName,
                                editId: edit.id,
                                language: language.playCode,
                                imageType: target.imageType.apiValue,
                                fileName: screenshot.fileName,
                                png: screenshot.data
                            )
                        }
                        completedSteps += 1
                        emit(label)
                    }
                }
            }

            emit(sendForReview ? "Submitting for review…" : "Saving draft…")
            let didSendForReview = try await performStep("commit the Play Console edit", target: targets[0], language: targets[0].languages.first) {
                try await api.commitEdit(packageName: packageName, editId: edit.id, sendForReview: sendForReview)
            }
            emit("Done")
            return didSendForReview
        } catch {
            // Abandon the half-finished edit so it doesn't linger in the Play Console.
            try? await api.deleteEdit(packageName: packageName, editId: edit.id)
            throw error
        }
    }

    private func renderScreenshots(
        row: ScreenshotRow,
        rowImages: [String: NSImage],
        target: GPUploadTarget,
        language: GPUploadLanguage,
        localeState: LocaleState,
        fontFamilies: Set<String>,
        emit: (String) -> Void
    ) async throws -> [RenderedScreenshot] {
        var screenshots: [RenderedScreenshot] = []
        screenshots.reserveCapacity(target.templateCount)

        for templateIndex in 0..<target.templateCount {
            try Task.checkCancellation()
            emit("Rendering \(target.rowLabel) · \(language.label) · \(templateIndex + 1)/\(target.templateCount)")
            let image = ExportService.renderSingleTemplateImage(
                index: templateIndex,
                row: row,
                screenshotImages: rowImages,
                localeCode: language.projectCode,
                localeState: localeState,
                availableFontFamilies: fontFamilies
            )
            // The SwiftUI render must stay on the main actor, but pull out the source bitmap
            // here and run the (CPU-bound) flatten + PNG encode off-actor so the upload UI
            // keeps animating. Play rejects an alpha channel, so encode opaque.
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            guard let source, let data = await Self.encodeOpaquePNG(source: source) else {
                throw GooglePlayUploadError.renderFailed(
                    rowLabel: target.rowLabel,
                    imageTypeLabel: target.imageType.label,
                    languageLabel: language.label,
                    index: templateIndex
                )
            }
            // Match the on-disk export name (e.g. 01_Onboarding_en.png) using the project locale code.
            let fileName = ExportService.screenshotFileName(row: row, localeCode: language.projectCode, index: templateIndex)
            screenshots.append(RenderedScreenshot(templateIndex: templateIndex, fileName: fileName, data: data))
        }
        return screenshots
    }

    /// Flatten + PNG-encode is pure CPU on an immutable `CGImage`; `nonisolated async` runs it
    /// on the cooperative pool so the main actor stays responsive during the upload.
    nonisolated private static func encodeOpaquePNG(source: CGImage) async -> Data? {
        ExportImageEncoder.opaquePNGData(fromCGImage: source)
    }

    private func performStep<T>(
        _ operation: String,
        target: GPUploadTarget,
        language: GPUploadLanguage?,
        work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch {
            let lang = language ?? GPUploadLanguage(projectCode: "", playCode: "", label: "—")
            throw GooglePlayUploadError.requestFailed(GPUploadFailureContext(
                operation: operation,
                target: target,
                language: lang,
                underlyingError: error
            ))
        }
    }
}

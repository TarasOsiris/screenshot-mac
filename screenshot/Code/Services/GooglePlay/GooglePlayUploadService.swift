import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum GooglePlayUploadError: StoreUploadErrorDescribing, LocalizedError {
    case renderFailed(rowLabel: String, imageTypeLabel: String, languageLabel: String, index: Int)
    case unreadableImages(rowLabel: String, languageLabel: String, fileNames: [String])
    case noRowsSelected
    case requestFailed(GPUploadFailureContext)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let label, let imageTypeLabel, let languageLabel, let index):
            return String(localized: "Could not render screenshot \(index + 1) for \(label) (\(imageTypeLabel)) in \(languageLabel). Check that this row previews correctly in the editor, then try the upload again.")
        case .unreadableImages(let label, let languageLabel, let fileNames):
            if fileNames.count == 1 {
                return String(localized: "Could not read 1 image used by \(label) in \(languageLabel). Re-import the missing screenshot before uploading, or the upload would publish it as a blank area.")
            }
            return String(localized: "Could not read \(fileNames.count) images used by \(label) in \(languageLabel). Re-import the missing screenshots before uploading, or the upload would publish them as blank areas.")
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
        case .unreadableImages(let label, let languageLabel, _):
            return String(localized: "Missing images for \(label) · \(languageLabel).")
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
        case .unreadableImages(let label, let languageLabel, let fileNames):
            return [
                "Failure: unreadable images",
                "Row: \(label)",
                "Language: \(languageLabel)",
                "Files: \(fileNames.joined(separator: ", "))"
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

nonisolated struct GPUploadFailureContext {
    let operation: String
    let rowLabel: String
    let imageTypeLabel: String
    let languageLabel: String
    let languageCode: String
    let httpStatus: Int?
    let apiMessage: String?
    let originalMessage: String
    /// Set when the request failed in transit. Google Play never saw it, so the message must not
    /// blame what the request contained. Typed `URLError` rather than `Error` to keep this struct
    /// implicitly Sendable — it is thrown out of a `@MainActor` service.
    let transportError: URLError?

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
                self.transportError = nil
            case .transport(let error):
                self.httpStatus = nil
                self.apiMessage = nil
                self.originalMessage = String(localized: "Network request failed: \(error.localizedDescription)")
                self.transportError = error as? URLError
            default:
                self.httpStatus = nil
                self.apiMessage = nil
                self.originalMessage = apiError.localizedDescription
                self.transportError = nil
            }
        } else {
            self.httpStatus = nil
            self.apiMessage = nil
            self.originalMessage = underlyingError.localizedDescription
            self.transportError = nil
        }
    }

    var isConnectionFailure: Bool { transportError != nil }

    /// `repeatable: true` because the only caller clears the whole screenshot set before it
    /// uploads, so whatever a failed attempt left behind is wiped before the next one starts.
    func isWorthRetrying(under policy: StoreRetryPolicy) -> Bool {
        if let httpStatus { return policy.allowsRetry(status: httpStatus, repeatable: true) }
        guard let transportError else { return false }
        return policy.allowsRetry(transportError: transportError, repeatable: true)
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
        if transportError?.code == .notConnectedToInternet {
            return String(localized: "No internet connection while trying to \(operation).")
        }
        if isConnectionFailure {
            return String(localized: "The connection failed while trying to \(operation).")
        }
        return String(localized: "Upload failed while trying to \(operation).")
    }

    /// Every branch below is the same three parts: what failed, what to do about it, and what
    /// Google Play (or the transport) actually said.
    private func detail(_ advice: String) -> String {
        [
            String(localized: "Could not \(operation) for \(rowLabel) (\(imageTypeLabel)) in \(languageLabel)."),
            advice,
            String(localized: "Original response: \(originalMessage)")
        ].joined(separator: "\n\n")
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
            return detail(String(localized: "Google Play rejected the request because the service account is not authorized for this app. In the Play Console, invite the service account under Users and permissions and grant it access to edit this app's store listing."))
        }
        if transportError?.code == .notConnectedToInternet {
            return detail(String(localized: "Your Mac lost its internet connection, so the request never reached Google Play. Nothing was published — the edit was discarded and your listing is unchanged. Reconnect and upload again."))
        }
        if isConnectionFailure {
            return detail(String(localized: "The request never completed, so Google Play never saw it. This is a connection problem, not something wrong with the package name, image type or language. Nothing was published — the edit was discarded and your listing is unchanged. Upload again when the connection is steady."))
        }
        if httpStatus == 404 {
            return detail(String(localized: "Google Play could not find the target. Check that the package name is correct and that \(languageCode) is an active store-listing language for this app."))
        }
        return detail(String(localized: "Google Play did not accept the request. Check the package name, image type, and language, then retry."))
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

    /// Everything one language's publish needs. A struct because the sequence is attempted more
    /// than once, and threading six arguments through both halves of the retry obscured it.
    private struct LanguagePublish {
        let rendered: [RenderedScreenshot]
        let packageName: String
        let editId: String
        let target: GPUploadTarget
        let language: GPUploadLanguage

        var planLabel: String { "\(target.rowLabel) · \(language.label) · \(target.imageType.label)" }
    }

    /// Longer than the transport's own backoff: this waits out a connection that just dropped,
    /// and every attempt re-sends one language's screenshots, so a tight loop would be wasteful.
    static let defaultRetryPolicy = StoreRetryPolicy(
        maxAttempts: 3,
        baseDelay: .seconds(2),
        maxDelay: .seconds(20)
    )

    private let api: GooglePlayAPIService
    private let retryPolicy: StoreRetryPolicy

    init(api: GooglePlayAPIService? = nil, retryPolicy: StoreRetryPolicy = defaultRetryPolicy) {
        self.api = api ?? .shared
        self.retryPolicy = retryPolicy
    }

    /// Returns whether the committed changes were sent for review (`true`) or held as a draft (`false`).
    @discardableResult
    func upload(
        packageName: String,
        targets: [GPUploadTarget],
        sendForReview: Bool,
        rows: [ScreenshotRow],
        source: any RowRenderSource,
        progress: @escaping (UploadProgress) -> Void
    ) async throws -> Bool {
        guard !targets.isEmpty else { throw GooglePlayUploadError.noRowsSelected }

        let totalSteps = targets.reduce(0) { $0 + ($1.templateCount * $1.languages.count) }
        var completedSteps = 0
        var imageCache: [String: NSImage] = [:]

        // Takes the count rather than reading a captured one: the publish loop reports progress
        // while it advances, and a shared `var` read through a capture cannot be passed `inout`.
        func emit(_ completed: Int, _ label: String) {
            progress(UploadProgress(totalSteps: totalSteps, completedSteps: completed, currentLabel: label))
        }

        emit(completedSteps, "Starting…")
        let edit = try await performStep("open a Play Console edit", target: targets[0], language: targets[0].languages.first) {
            try await api.insertEdit(packageName: packageName)
        }

        do {
            for target in targets {
                guard let row = rows.first(where: { $0.id == target.rowId }) else { continue }

                // Backgrounds are locale-independent, so the (blur-only) precomposed row strip is
                // built once and shared across every language — same as `ExportService.exportAll`.
                var context: RowRenderContext?

                for language in target.languages {
                    try Task.checkCancellation()
                    let rowContext = RowRenderContext.load(
                        row: row,
                        localeCode: language.projectCode,
                        from: source,
                        label: "play upload row",
                        cache: &imageCache,
                        reusing: context
                    )
                    context = rowContext
                    // App Store Connect already refuses this; Play used to publish the screenshot
                    // with the missing image rendered as a hole.
                    if !rowContext.unrenderableImageFileNames.isEmpty {
                        throw GooglePlayUploadError.unreadableImages(
                            rowLabel: target.rowLabel,
                            languageLabel: language.label,
                            fileNames: rowContext.unrenderableImageFileNames
                        )
                    }
                    let steps = completedSteps
                    let rendered = try await renderScreenshots(
                        context: rowContext,
                        target: target,
                        language: language,
                        emit: { emit(steps, $0) }
                    )

                    completedSteps = try await publishScreenshots(
                        LanguagePublish(
                            rendered: rendered,
                            packageName: packageName,
                            editId: edit.id,
                            target: target,
                            language: language
                        ),
                        baseStep: completedSteps,
                        emit: emit
                    )
                }
            }

            emit(completedSteps, sendForReview ? "Submitting for review…" : "Saving draft…")
            let didSendForReview = try await performStep("commit the Play Console edit", target: targets[0], language: targets[0].languages.first) {
                try await api.commitEdit(packageName: packageName, editId: edit.id, sendForReview: sendForReview)
            }
            emit(completedSteps, "Done")
            return didSendForReview
        } catch {
            // Abandon the half-finished edit so it doesn't linger in the Play Console.
            do {
                try await api.deleteEdit(packageName: packageName, editId: edit.id)
            } catch let abandonError {
                // The abandon failed, so a dangling edit is now stuck in the user's real console.
                CrashReportingService.report(.googlePlayEditAbandonFailed, error: abandonError)
            }
            throw error
        }
    }

    private func renderScreenshots(
        context: RowRenderContext,
        target: GPUploadTarget,
        language: GPUploadLanguage,
        emit: (String) -> Void
    ) async throws -> [RenderedScreenshot] {
        var screenshots: [RenderedScreenshot] = []
        screenshots.reserveCapacity(target.templateCount)
        await context.prepareBackground()

        for templateIndex in 0..<target.templateCount {
            try Task.checkCancellation()
            emit("Rendering \(target.rowLabel) · \(language.label) · \(templateIndex + 1)/\(target.templateCount)")
            let image = context.templateImage(at: templateIndex)
            // The SwiftUI render must stay on the main actor; the encode must not, or the upload UI
            // freezes. Play rejects an alpha channel, so encode opaque.
            guard let data = await ExportImageEncoder.opaquePNGDataOffMain(from: image) else {
                throw GooglePlayUploadError.renderFailed(
                    rowLabel: target.rowLabel,
                    imageTypeLabel: target.imageType.label,
                    languageLabel: language.label,
                    index: templateIndex
                )
            }
            // Match the on-disk export name (e.g. 01_Onboarding_en.png) using the project locale code.
            let fileName = ExportFileNaming.screenshotFileName(
                row: context.row,
                localeCode: language.projectCode,
                index: templateIndex,
                customSuffix: ExportFileNaming.preferredCustomSuffix
            )
            screenshots.append(RenderedScreenshot(templateIndex: templateIndex, fileName: fileName, data: data))
            await Task.yield()
        }
        return screenshots
    }

    /// One language's screenshots, published as a unit. The sequence clears the set before it
    /// uploads, so re-running it lands the same result however far a failed attempt got — which
    /// is what makes the image POST, not idempotent on its own, safe to repeat here. A single
    /// timed-out request used to discard the whole run and every language already uploaded.
    ///
    /// `baseStep` in, new total out, rather than a shared counter: `upload`'s `emit` reads its
    /// own `completedSteps`, and passing that `inout` past a closure that reads it is an
    /// exclusivity violation that traps at runtime.
    private func publishScreenshots(
        _ job: LanguagePublish,
        baseStep: Int,
        emit: (Int, String) -> Void
    ) async throws -> Int {
        try await retryPolicy.attempting {
            do {
                return try await publishOnce(job, baseStep: baseStep, emit: emit)
            } catch let error as GooglePlayUploadError {
                guard case .requestFailed(let context) = error,
                      context.isWorthRetrying(under: retryPolicy)
                else { throw error }

                CrashReportingService.breadcrumb(.upload, "Play: retrying a language", level: .warning)
                // Progress rewinds to where the language started, because the work is being redone.
                emit(baseStep, "Connection problem — retrying \(job.planLabel)")
                throw StoreRetryPolicy.Retryable(underlying: error)
            }
        }
    }

    private func publishOnce(
        _ job: LanguagePublish,
        baseStep: Int,
        emit: (Int, String) -> Void
    ) async throws -> Int {
        // Replace mode: clear the existing set for this language+type, then re-upload.
        emit(baseStep, "Clearing existing screenshots · \(job.planLabel)")
        try await performStep("clear existing \(job.target.imageType.label) screenshots", target: job.target, language: job.language) {
            try await api.deleteAllImages(
                packageName: job.packageName,
                editId: job.editId,
                language: job.language.playCode,
                imageType: job.target.imageType.apiValue
            )
        }

        for (offset, screenshot) in job.rendered.enumerated() {
            try Task.checkCancellation()
            let label = "\(job.target.rowLabel) · \(job.language.label) · \(screenshot.templateIndex + 1)/\(job.target.templateCount)"
            emit(baseStep + offset, "Uploading \(label)")
            _ = try await performStep("upload screenshot \(screenshot.templateIndex + 1)", target: job.target, language: job.language) {
                try await api.uploadImage(
                    packageName: job.packageName,
                    editId: job.editId,
                    language: job.language.playCode,
                    imageType: job.target.imageType.apiValue,
                    fileName: screenshot.fileName,
                    png: screenshot.data
                )
            }
            emit(baseStep + offset + 1, label)
        }
        return baseStep + job.rendered.count
    }

    private func performStep<T>(
        _ operation: String,
        target: GPUploadTarget,
        language: GPUploadLanguage?,
        work: () async throws -> T
    ) async throws -> T {
        // `operation` is a fixed English description; the target's row label is user content
        // and must never leave the device.
        CrashReportingService.breadcrumb(.upload, "Play: \(operation)")
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch {
            CrashReportingService.breadcrumb(.upload, "Play failed: \(operation)", level: .warning)
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

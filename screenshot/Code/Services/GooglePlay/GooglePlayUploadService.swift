import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

        emit(completedSteps, String(localized: "Starting…"))
        let edit = try await performStep(.openEdit, target: targets[0], language: targets[0].languages.first) {
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

            emit(completedSteps, sendForReview ? String(localized: "Submitting for review…") : String(localized: "Saving draft…"))
            let didSendForReview = try await performStep(.commitEdit, target: targets[0], language: targets[0].languages.first) {
                try await api.commitEdit(packageName: packageName, editId: edit.id, sendForReview: sendForReview)
            }
            emit(completedSteps, String(localized: "Done"))
            return didSendForReview
        } catch {
            // Abandon the half-finished edit so it doesn't linger in the Play Console. Unstructured,
            // because inside a cancelled upload the retry policy throws before the DELETE is sent.
            let abandon = await Task { try await api.deleteEdit(packageName: packageName, editId: edit.id) }.result
            if case .failure(let abandonError) = abandon {
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
            emit(String(localized: "Rendering \(target.rowLabel) · \(language.label) · \(templateIndex + 1)/\(target.templateCount)", comment: "Upload progress. Placeholders: row name, language, screenshot number, screenshot count."))
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
                emit(baseStep, String(localized: "Connection problem — retrying \(job.planLabel)", comment: "Upload progress. The placeholder is 'row · language · image type'."))
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
        emit(baseStep, String(localized: "Clearing existing screenshots · \(job.planLabel)", comment: "Upload progress. The placeholder is 'row · language · image type'."))
        try await performStep(.clearScreenshots(job.target.imageType), target: job.target, language: job.language) {
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
            emit(baseStep + offset, String(localized: "Uploading \(label)", comment: "Upload progress. The placeholder names the screenshot being uploaded."))
            _ = try await performStep(.uploadScreenshot(number: screenshot.templateIndex + 1), target: job.target, language: job.language) {
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
        _ operation: GPUploadOperation,
        target: GPUploadTarget,
        language: GPUploadLanguage?,
        work: () async throws -> T
    ) async throws -> T {
        // The diagnostic name is fixed English; the target's row label is user content and must
        // never leave the device.
        CrashReportingService.breadcrumb(.upload, "Play: \(operation.diagnosticName)")
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch {
            CrashReportingService.breadcrumb(.upload, "Play failed: \(operation.diagnosticName)", level: .warning)
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

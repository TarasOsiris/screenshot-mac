#if DEBUG
import SwiftUI

extension UploadToGooglePlayView {

    func prefillPackageName() {
        if packageName.isEmpty, let saved = state.activeProject?.googlePlayPackageName {
            packageName = saved
        }
    }

    func continueToPlan() {
        packageName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !credentials.isDemoMode, let projectId = state.activeProject?.id {
            state.setGooglePlayPackageName(packageName.isEmpty ? nil : packageName, forProject: projectId)
        }
        rowPlans = buildRowPlans(preserving: rowPlans)
        errorMessage = nil
        step = .configuringPlan
    }

    func buildRowPlans(preserving existingPlans: [GPRowPlan] = []) -> [GPRowPlan] {
        state.rows.map { row in
            let detected = GPImageType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = state.localeState.locales.map { locale -> GPLocaleTarget in
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                return GPLocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    playLanguageCode: GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: locale.code),
                    isEnabled: existingTarget?.isEnabled ?? true
                )
            }
            return GPRowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: row.templateSize,
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? (row.inferredStorePlatform != .apple),
                detectedImageType: detected,
                selectedImageType: existingPlan?.selectedImageType ?? detected,
                localeTargets: targets,
                inferredStorePlatform: row.inferredStorePlatform
            )
        }
    }

    func buildUploadTargets() -> [GPUploadTarget] {
        rowPlans.compactMap { plan -> GPUploadTarget? in
            guard plan.isEnabled else { return nil }
            let languages = plan.localeTargets
                .filter(\.isEnabled)
                .map { GPUploadLanguage(projectCode: $0.appLocaleCode, playCode: $0.playLanguageCode, label: $0.appLocaleLabel) }
            guard !languages.isEmpty else { return nil }
            return GPUploadTarget(
                rowId: plan.id,
                rowLabel: plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel,
                rowSize: plan.rowSize,
                imageType: plan.selectedImageType,
                languages: languages,
                templateCount: plan.templateCount
            )
        }
    }

    func startUpload() async {
        errorMessage = nil
        errorDetailsText = nil
        guard !validationIssues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before uploading.")
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × languages are selected.")
            return
        }

        let pkg = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        uploadProgress = nil
        step = .uploading
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        let task = Task {
            do {
                let didSendForReview = try await GooglePlayUploadService.shared.upload(
                    packageName: pkg,
                    targets: targets,
                    sendForReview: sendForReview,
                    appState: state,
                    progress: { p in self.uploadProgress = p }
                )
                let summary = UploadSummary(
                    totalScreenshots: targets.reduce(0) { $0 + $1.templateCount * $1.languages.count },
                    languageCount: Set(targets.flatMap { $0.languages.map(\.playCode) }).count,
                    packageName: pkg,
                    sentForReview: didSendForReview
                )
                uploadSummary = summary
                step = .done
                let shotNoun = summary.totalScreenshots == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
                let langNoun = summary.languageCount == 1 ? String(localized: "language") : String(localized: "languages")
                NotificationService.notify(
                    title: String(localized: "Upload complete"),
                    body: String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.languageCount) \(langNoun)")
                )
            } catch is CancellationError {
                errorMessage = String(localized: "Upload cancelled. The draft edit was discarded.")
                step = .configuringPlan
            } catch {
                let summary = uploadFailureSummary(for: error)
                errorMessage = summary
                errorDetailsText = buildErrorDetails(for: error)
                step = .configuringPlan
                NotificationService.notify(title: String(localized: "Upload failed"), body: summary)
            }
        }
        uploadTask = task
        await task.value
    }

    func uploadFailureSummary(for error: Error) -> String {
        if let uploadError = error as? GooglePlayUploadError {
            return uploadError.summaryDescription
        }
        return String(localized: "Upload failed: \(error.localizedDescription)")
    }

    func buildErrorDetails(for error: Error) -> String {
        var details: [String] = [error.localizedDescription]
        details.append("Package: \(packageName)")
        if let uploadError = error as? GooglePlayUploadError {
            details.append("Technical details:\n\(uploadError.technicalDescription)")
        }
        return details.joined(separator: "\n\n")
    }
}
#endif

import Foundation
import Observation

/// The Google Play upload wizard's state machine.
///
/// A separate model from `ASCUploadFlowModel`, not a generic shared with it. The sharable part
/// was the data layer and that is already extracted — `StoreRowPlan`, `StoreUploadChecks`,
/// `StoreUploadFailureText`. What remains differs structurally: four steps against seven, a
/// two-level plan tree against three, no pre-upload network calls, and one `upload()` against a
/// build/diff/review/apply coordinator.
@MainActor
@Observable
final class GPUploadFlowModel {

    private(set) var step: GPUploadStep = .enteringPackage

    var packageName: String = ""
    /// When off (default), the edit is committed with `changesNotSentForReview=true` so changes
    /// stage as a draft. On, they are submitted to Google Play review on commit.
    var sendForReview: Bool = false
    var rowPlans: [GPRowPlan] = []

    var uploadProgress: UploadProgress?
    var uploadSummary: GPUploadSummary?
    var errorMessage: String?
    var errorDetailsText: String?
    var isBusy = false

    let credentials: GooglePlayCredentialsStore

    @ObservationIgnored private let uploader: any GPUploadPerforming
    @ObservationIgnored private(set) weak var document: (any GPUploadDocument)?
    @ObservationIgnored var uploadTask: Task<Void, Never>?

    init(
        uploader: any GPUploadPerforming = GooglePlayUploadService.shared,
        credentials: GooglePlayCredentialsStore = .shared
    ) {
        self.uploader = uploader
        self.credentials = credentials
    }

    func bind(document: any GPUploadDocument) {
        self.document = document
    }

    var rows: [ScreenshotRow] { document?.rows ?? [] }
    var localeState: LocaleState { document?.localeState ?? .default }

    var validationIssues: [UploadIssue] {
        GooglePlayUploadValidator.validate(
            packageName: packageName,
            plans: rowPlans,
            isDemoMode: credentials.isDemoMode
        )
    }

    func prefillPackageName() {
        if packageName.isEmpty, let saved = document?.savedGooglePlayPackageName {
            packageName = saved
        }
    }

    func continueToPlan() {
        packageName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !credentials.isDemoMode {
            document?.rememberGooglePlayPackageName(packageName.isEmpty ? nil : packageName)
        }
        rowPlans = buildRowPlans(preserving: rowPlans)
        errorMessage = nil
        step = .configuringPlan
    }

    func buildRowPlans(preserving existingPlans: [GPRowPlan] = []) -> [GPRowPlan] {
        rows.map { row in
            let detected = GPImageType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = localeState.locales.map { locale -> GPLocaleTarget in
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
                detectedAssetType: detected,
                selectedAssetType: existingPlan?.selectedAssetType ?? detected,
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
                rowLabel: plan.displayLabel,
                rowSize: plan.rowSize,
                imageType: plan.selectedAssetType,
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

        guard let document else { return }

        let pkg = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        uploadProgress = nil
        step = .uploading
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        let task = Task {
            do {
                let didSendForReview = try await uploader.upload(
                    packageName: pkg,
                    targets: targets,
                    sendForReview: sendForReview,
                    rows: rows,
                    source: document,
                    progress: { p in self.uploadProgress = p }
                )
                let summary = GPUploadSummary(
                    totalScreenshots: targets.reduce(0) { $0 + $1.templateCount * $1.languages.count },
                    languageCount: Set(targets.flatMap { $0.languages.map(\.playCode) }).count,
                    packageName: pkg,
                    sentForReview: didSendForReview
                )
                uploadSummary = summary
                AnalyticsService.capture(.storeUploadFinished, [
                    .store: "play",
                    .imageCount: summary.totalScreenshots,
                    .localeCount: summary.languageCount,
                ])
                step = .done
                let shotNoun = summary.totalScreenshots == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
                let langNoun = summary.languageCount == 1 ? String(localized: "language") : String(localized: "languages")
                NotificationService.notify(
                    title: String(localized: "Upload complete"),
                    body: String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.languageCount) \(langNoun)")
                )
            } catch is CancellationError {
                errorMessage = String(localized: "Upload cancelled. The draft edit was discarded.")
                AnalyticsService.capture(.storeUploadFailed, [.store: "play", .cancelled: true])
                step = .configuringPlan
            } catch {
                let summary = StoreUploadFailureText.summary(for: error)
                errorMessage = summary
                errorDetailsText = StoreUploadFailureText.details(for: error, context: ["Package: \(packageName)"])
                AnalyticsService.capture(.storeUploadFailed, [.store: "play", .cancelled: false])
                step = .configuringPlan
                NotificationService.notify(title: String(localized: "Upload failed"), body: summary)
            }
        }
        // Assigned before the await: the footer's Cancel button needs the task reachable while
        // the upload is in flight.
        uploadTask = task
        await task.value
    }

    /// The plan screen's Back button. Only one step back exists in this flow.
    func goBack() {
        step = .enteringPackage
    }

    func cancelUpload() {
        uploadTask?.cancel()
    }

    /// The view's `.onDisappear`.
    func tearDown() {
        uploadTask?.cancel()
        uploadTask = nil
    }
}

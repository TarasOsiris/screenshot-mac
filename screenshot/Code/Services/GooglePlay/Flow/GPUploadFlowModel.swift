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

    var packageName: String = "" {
        didSet {
            guard packageName != oldValue else { return }
            packageVerification = .unverified
        }
    }
    private(set) var packageVerification: GPPackageVerification = .unverified
    /// When off (default), the edit is committed with `changesNotSentForReview=true` so changes
    /// stage as a draft. On, they are submitted to Google Play review on commit.
    var sendForReview: Bool = false
    var rowPlans: [GPRowPlan] = []

    var recentPackageNames: [String] { GooglePlayRecentPackages.load(defaults: defaults) }

    var uploadProgress: UploadProgress?
    var uploadSummary: GPUploadSummary?
    var errorMessage: String?
    var errorDetailsText: String?
    var isBusy = false

    let credentials: GooglePlayCredentialsStore

    @ObservationIgnored private let uploader: any GPUploadPerforming
    @ObservationIgnored private let api: any GPPackageVerifying
    /// Where the recents list lives. Injected so a test run never writes into the real one.
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) weak var document: (any GPUploadDocument)?
    @ObservationIgnored var uploadTask: Task<Void, Never>?

    /// Keeps the iPad `NavigationStack` path in step with `step`. Same shape as
    /// `ASCUploadFlowModel`'s: the model owns the transition, the view mirrors it.
    @ObservationIgnored var navigationDidAdvance: (GPUploadStep) -> Void = { _ in }
    @ObservationIgnored var navigationWillRetreat: () -> Void = {}

    init(
        uploader: any GPUploadPerforming = GooglePlayUploadService.shared,
        api: any GPPackageVerifying = GooglePlayAPIService.shared,
        credentials: GooglePlayCredentialsStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.uploader = uploader
        self.api = api
        self.credentials = credentials
        self.defaults = defaults
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
        guard packageName.isEmpty else { return }
        if let saved = document?.savedGooglePlayPackageName {
            packageName = saved
        } else if credentials.isDemoMode {
            packageName = GooglePlayDemoData.packageName
        }
    }

    /// Verifies the package with Play, then advances. A failure keeps the user on this step with
    /// the reason, rather than letting a typo or a missing permission surface mid-upload.
    func continueToPlan() async {
        packageName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packageName.isEmpty else { return }

        if !packageVerification.isVerified {
            await verifyPackage()
            guard packageVerification.isVerified else { return }
        }

        if !credentials.isDemoMode {
            document?.rememberGooglePlayPackageName(packageName)
            GooglePlayRecentPackages.remember(packageName, defaults: defaults)
        }
        rowPlans = buildRowPlans(preserving: rowPlans)
        errorMessage = nil
        advance(to: .configuringPlan)
    }

    func verifyPackage() async {
        let candidate = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GooglePlayUploadValidator.isValidPackageName(candidate) else {
            packageVerification = .failed(String(localized: "That isn't a valid package name. It looks like com.example.myapp."))
            return
        }

        packageVerification = .verifying
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.verifyPackage(packageName: candidate)
            // The field can change while the probe is in flight; only claim the name we checked.
            guard candidate == packageName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            packageVerification = .verified(candidate)
        } catch {
            guard candidate == packageName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            packageVerification = .failed(Self.verificationFailureMessage(for: error))
        }
    }

    /// Play answers "no such app" and "you have no access to this app" with the same 404, so the
    /// message has to cover both rather than guess.
    nonisolated static func verificationFailureMessage(for error: Error) -> String {
        switch (error as? GooglePlayAPIError)?.httpStatus {
        case 401:
            String(localized: "The service account was rejected. Check the key in Settings → Google Play.")
        case 403:
            String(localized: "This service account can't edit that app. Grant it access in the Play Console.")
        case 404:
            String(localized: "No app with that package name is reachable by this service account.")
        default:
            StoreUploadFailureText.summary(for: error)
        }
    }

    private func advance(to next: GPUploadStep) {
        step = next
        navigationDidAdvance(next)
    }

    /// A finished or failed upload drops back to the plan, popping the pushed progress screen on
    /// iPad so Back doesn't return to it.
    private func retreatToPlan() {
        step = .configuringPlan
        navigationWillRetreat()
    }

    /// The iPad back-swipe and the nav bar's Back both pop the path rather than calling `goBack()`,
    /// so the model follows the path instead of driving it.
    func handlePathChange(from oldPath: [GPUploadStep], to newPath: [GPUploadStep]) {
        guard newPath.count < oldPath.count else { return }
        step = newPath.last ?? .enteringPackage
        errorMessage = nil
        errorDetailsText = nil
    }

    func buildRowPlans(preserving existingPlans: [GPRowPlan] = []) -> [GPRowPlan] {
        let defaultCodes = GooglePlayLanguageMatcher.defaultUploadCodes(among: localeState.locales.map(\.code))
        return rows.map { row in
            let detected = GPImageType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = localeState.locales.map { locale -> GPLocaleTarget in
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                return GPLocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    playLanguageCode: GooglePlayLanguageMatcher.playLanguageCode(forProjectCode: locale.code),
                    isEnabled: existingTarget?.isEnabled ?? defaultCodes.contains(locale.code)
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
            // Demo mode softens the duplicate-language error to a warning, so the upload path
            // cannot trust validation alone: one Play language means one delete-and-reupload.
            var claimedPlayCodes: Set<String> = []
            let languages = plan.localeTargets.compactMap { target -> GPUploadLanguage? in
                guard target.isEnabled, let playCode = target.playLanguageCode else { return nil }
                guard claimedPlayCodes.insert(playCode).inserted else { return nil }
                return GPUploadLanguage(projectCode: target.appLocaleCode, playCode: playCode, label: target.appLocaleLabel)
            }
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

    var plannedCounts: GPUploadCounts {
        GPUploadCounts(targets: buildUploadTargets())
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
        advance(to: .uploading)
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
                let counts = GPUploadCounts(targets: targets)
                let summary = GPUploadSummary(
                    totalScreenshots: counts.screenshots,
                    languageCount: counts.languages,
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
                NotificationService.notify(
                    title: String(localized: "Upload complete"),
                    body: summary.countsText
                )
            } catch is CancellationError {
                errorMessage = String(localized: "Upload cancelled. The draft edit was discarded.")
                StoreUploadFailure(kind: .cancelled, errorCode: nil).report(store: "play", cancelled: true)
                retreatToPlan()
            } catch {
                let summary = StoreUploadFailureText.summary(for: error)
                errorMessage = summary
                errorDetailsText = StoreUploadFailureText.details(for: error, context: ["Package: \(packageName)"])
                StoreUploadFailure.classify(error).report(store: "play", cancelled: false)
                retreatToPlan()
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
        errorMessage = nil
        errorDetailsText = nil
        navigationWillRetreat()
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

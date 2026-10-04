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
    /// Play has no experiments API, so this is how a winning variant becomes the listing; nil is the Original.
    var listingVariantId: UUID? {
        didSet {
            guard listingVariantId != oldValue else { return }
            rowPlans = buildRowPlans(preserving: rowPlans)
        }
    }

    var recentPackageNames: [String] { GooglePlayRecentPackages.load(defaults: defaults) }

    var uploadProgress: UploadProgress?
    var uploadSummary: GPUploadSummary?
    var errorMessage: String?
    var errorDetailsText: String?
    var isBusy = false

    /// Per Play language, then image type. A missing language means "not known", never "empty".
    var remoteScreenshotCounts: [String: [String: Int]] = [:]
    @ObservationIgnored var remoteScreenshotCountTask: Task<Void, Never>?
    /// Package and languages the counts describe, so revisiting the plan doesn't re-read them.
    @ObservationIgnored private var remoteScreenshotCountsSource: String?

    let credentials: GooglePlayCredentialsStore

    @ObservationIgnored private let uploader: any GPUploadPerforming
    @ObservationIgnored private let api: any GPPackageVerifying & GPScreenshotCountReading
    /// Where the recents list lives. Injected so a test run never writes into the real one.
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) weak var document: (any GPUploadDocument)?
    @ObservationIgnored let textOverflowIssues = TextOverflowIssueCache()
    @ObservationIgnored var uploadTask: Task<Void, Never>?

    /// Keeps the iPad `NavigationStack` path in step with `step`. Same shape as
    /// `ASCUploadFlowModel`'s: the model owns the transition, the view mirrors it.
    @ObservationIgnored var navigationDidAdvance: (GPUploadStep) -> Void = { _ in }
    @ObservationIgnored var navigationWillRetreat: () -> Void = {}

    init(
        uploader: any GPUploadPerforming = GooglePlayUploadService.shared,
        api: any GPPackageVerifying & GPScreenshotCountReading = GooglePlayAPIService.shared,
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
    var variants: [ScreenshotVariant] { document?.activeVariants ?? [] }
    var localeState: LocaleState { document?.localeState ?? .default }

    /// A variant id that no longer exists falls back to the Original rather than planning nothing.
    var listingRows: [ScreenshotRow] {
        rows.inVariant(variants.variant(withId: listingVariantId)?.id)
    }

    var validationIssues: [UploadIssue] {
        let issues = GooglePlayUploadValidator.validate(
            packageName: packageName,
            plans: rowPlans,
            isDemoMode: credentials.isDemoMode
        )
        guard let document else { return issues }
        return issues + textOverflowIssues.issues(rows: listingRows, source: document)
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
        reloadRemoteScreenshotCounts()
    }

    // MARK: - Existing screenshots

    /// Reads, in the background, what the listing holds for every Play language the plan maps to.
    func reloadRemoteScreenshotCounts() {
        let languages = Array(Set(rowPlans.flatMap(\.localeTargets).compactMap(\.playLanguageCode))).sorted()
        let source = ([packageName] + languages).joined(separator: "|")
        guard source != remoteScreenshotCountsSource else { return }
        cancelRemoteScreenshotCounts()
        remoteScreenshotCounts = [:]
        guard !languages.isEmpty else { return }
        remoteScreenshotCountsSource = source
        let packageName = packageName
        let api = api
        remoteScreenshotCountTask = Task { [weak self] in
            let counts = try? await api.screenshotCounts(packageName: packageName, languages: languages)
            // Main-actor isolated, so a cancel issued before this resumes is already visible.
            guard let self, !Task.isCancelled else { return }
            if let counts {
                self.remoteScreenshotCounts = counts
            } else {
                self.remoteScreenshotCountsSource = nil
                CrashReportingService.breadcrumb(.upload, "play screenshot counts failed", data: ["count": languages.count])
            }
        }
    }

    func cancelRemoteScreenshotCounts() {
        remoteScreenshotCountTask?.cancel()
        remoteScreenshotCountTask = nil
        remoteScreenshotCountsSource = nil
    }

    func settleRemoteScreenshotCounts() async {
        await remoteScreenshotCountTask?.value
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
        reloadRemoteScreenshotCounts()
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
        return listingRows.map { row in
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

    /// Demo mode softens the duplicate-language error to a warning, so the upload path cannot
    /// trust validation alone: one Play language means one delete-and-reupload.
    private static func uploadLanguages(for plan: GPRowPlan) -> [GPUploadLanguage] {
        guard plan.isEnabled else { return [] }
        var claimedPlayCodes: Set<String> = []
        return plan.localeTargets.compactMap { target -> GPUploadLanguage? in
            guard target.isEnabled, let playCode = target.playLanguageCode else { return nil }
            guard claimedPlayCodes.insert(playCode).inserted else { return nil }
            return GPUploadLanguage(projectCode: target.appLocaleCode, playCode: playCode, label: target.appLocaleLabel)
        }
    }

    func buildUploadTargets() -> [GPUploadTarget] {
        rowPlans.compactMap { plan -> GPUploadTarget? in
            let languages = Self.uploadLanguages(for: plan)
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

    /// Catches the plan up with document edits made since it was built, never adding an unreviewed row.
    func reconcileRowPlansWithDocument() {
        let live = Dictionary(listingRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rowPlans = rowPlans.compactMap { plan -> GPRowPlan? in
            guard let row = live[plan.id] else { return nil }
            var plan = plan
            let detected = GPImageType.detect(width: row.templateWidth, height: row.templateHeight)
            // Follow a resize unless the user picked an image type other than the detected one.
            if plan.selectedAssetType == plan.detectedAssetType { plan.selectedAssetType = detected }
            plan.detectedAssetType = detected
            plan.rowLabel = row.label
            plan.rowSize = row.templateSize
            plan.templateCount = row.templates.count
            return plan
        }
    }

    func startUpload() async {
        errorMessage = nil
        errorDetailsText = nil
        reconcileRowPlansWithDocument()
        guard !validationIssues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before uploading.")
            return
        }
        let targets = buildUploadTargets()
        let counts = plannedCounts
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × languages are selected.")
            return
        }

        guard let document else { return }

        let pkg = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Its throwaway edit must not outlive the upload's own; the counts are stale after it anyway.
        cancelRemoteScreenshotCounts()
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
                let summary = GPUploadSummary(
                    counts: counts,
                    packageName: pkg,
                    sentForReview: didSendForReview
                )
                uploadSummary = summary
                AnalyticsService.capture(.storeUploadFinished, [
                    .store: "play",
                    .imageCount: counts.screenshots,
                    .localeCount: counts.languages,
                ])
                step = .done
                NotificationService.notify(
                    title: String(localized: "Upload complete"),
                    body: counts.text
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
        cancelRemoteScreenshotCounts()
        uploadTask?.cancel()
        uploadTask = nil
    }
}

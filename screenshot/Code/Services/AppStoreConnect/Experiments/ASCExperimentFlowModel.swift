import Foundation
import Observation

enum ASCExperimentStep: Hashable {
    case pickingApp
    case configuring
    case uploading
    case done
}

/// The "Upload A/B Test" wizard: one treatment per variant, then submit and start the experiment.
@MainActor
@Observable
final class ASCExperimentFlowModel {

    private(set) var step: ASCExperimentStep = .pickingApp

    var apps: [ASCAppWithVersions] = []
    var selectedAppId: String? {
        didSet {
            guard selectedAppId != oldValue else { return }
            platform = availablePlatforms.first ?? .ios
        }
    }
    var platform: ASCPlatform = .ios

    /// Every experiment on the app for `platform`, newest first.
    private(set) var experiments: [ASCExperiment] = []
    /// nil creates a new experiment named `newExperimentName`.
    private(set) var selectedExperimentId: String?
    var newExperimentName = ""
    var trafficProportion = 50
    private(set) var existingTreatments: [ASCExperimentTreatment] = []

    /// Project locale → the live product page's locale; a treatment can only localize into those.
    private(set) var localeAssignment: [String: String] = [:]
    var enabledLocaleCodes: Set<String> = []

    private(set) var uploadProgress: UploadProgress?
    private(set) var uploadedScreenshotCount = 0
    var errorMessage: String?
    var isBusy = false

    let credentials: AppStoreConnectCredentialsStore
    let screenshotSync: ASCScreenshotSyncCoordinator
    @ObservationIgnored private let uploadAPI: any ASCUploadAPI
    @ObservationIgnored private let experimentAPI: any ASCExperimentAPI
    @ObservationIgnored private(set) weak var document: (any ASCUploadDocument)?
    @ObservationIgnored var task: Task<Void, Never>?

    init(
        uploadAPI: any ASCUploadAPI = AppStoreConnectAPIService.shared,
        experimentAPI: any ASCExperimentAPI = AppStoreConnectAPIService.shared,
        credentials: AppStoreConnectCredentialsStore = .shared,
        screenshotSync: ASCScreenshotSyncCoordinator = ASCScreenshotSyncCoordinator()
    ) {
        self.uploadAPI = uploadAPI
        self.experimentAPI = experimentAPI
        self.credentials = credentials
        self.screenshotSync = screenshotSync
    }

    func bind(document: any ASCUploadDocument) {
        self.document = document
        if newExperimentName.isEmpty {
            newExperimentName = String(localized: "\(document.activeProjectName) screenshots")
        }
    }

    // MARK: - Derived

    var rows: [ScreenshotRow] { document?.rows ?? [] }
    var variants: [ScreenshotVariant] { document?.activeVariants ?? [] }
    var localeState: LocaleState { document?.localeState ?? .default }

    var selectedApp: ASCApp? { apps.first { $0.app.id == selectedAppId }?.app }

    var availablePlatforms: [ASCPlatform] {
        apps.first { $0.app.id == selectedAppId }?.platforms ?? []
    }

    var selectedExperiment: ASCExperiment? {
        experiments.first { $0.id == selectedExperimentId }
    }

    var rowsByVariant: [UUID: [ScreenshotRow]] { ASCExperimentPlanner.rowsByVariant(rows) }

    var testableVariants: [ScreenshotVariant] {
        ASCExperimentPlanner.variantsWithRows(variants, rowsByVariant: rowsByVariant)
    }

    /// Recomputed per read, so a view should read it once per body.
    var issues: [UploadIssue] {
        ASCExperimentPlanner.issues(
            variants: variants,
            rowsByVariant: rowsByVariant,
            platform: platform,
            experiment: selectedExperiment,
            existingTreatments: existingTreatments,
            newExperimentName: newExperimentName,
            enabledLocaleCodes: enabledLocaleCodes,
            localeAssignment: localeAssignment
        )
    }

    func canUpload(given issues: [UploadIssue]) -> Bool { !isBusy && !issues.hasErrors }

    // MARK: - Steps

    func loadApps() async {
        guard credentials.isConfigured, apps.isEmpty else { return }
        if credentials.isDemoMode {
            AppStoreConnectDemoData.shared.updateContext(
                localeCodes: localeState.locales.map(\.code),
                rowSizes: rows.map(\.templateSize)
            )
        }
        await run {
            apps = try await uploadAPI.listAppsWithVersions()
            let savedId = document?.savedASCAppId
            let closest = document.flatMap { AppStoreConnectAppMatcher.closestApp(projectName: $0.activeProjectName, in: apps.map(\.app)) }
            selectedAppId = apps.first { $0.app.id == savedId }?.app.id ?? closest?.id ?? apps.first?.app.id
        }
    }

    func continueToConfigure() async {
        guard let app = selectedApp else { return }
        if !credentials.isDemoMode { document?.rememberASCAppId(app.id) }
        await run {
            async let fetchedExperiments = experimentAPI.listExperiments(appId: app.id)
            let platformVersions = try await uploadAPI.listAppStoreVersions(appId: app.id)
                .filter { $0.attributes.ascPlatform == platform }
            // Before a first release there is no live page, only the version being prepared.
            guard let productPage = platformVersions.first(where: { $0.attributes.appStoreState == "READY_FOR_SALE" })
                ?? platformVersions.first else {
                throw ASCExperimentFlowError.noVersion(platform.displayName)
            }
            localeAssignment = ASCExperimentPlanner.localeAssignment(
                projectCodes: localeState.locales.map(\.code),
                productPageLocalizations: try await uploadAPI.listLocalizations(versionId: productPage.id)
            )
            enabledLocaleCodes = Set(localeAssignment.keys)
            experiments = Array(try await fetchedExperiments.filter { $0.ascPlatform == platform }.reversed())
            await selectExperiment(experiments.first { $0.state.isEditable }?.id)
            step = .configuring
        }
    }

    func selectExperiment(_ id: String?) async {
        selectedExperimentId = id
        existingTreatments = []
        guard let id else { return }
        await run {
            existingTreatments = try await experimentAPI.listTreatments(experimentId: id)
        }
    }

    func goBack() {
        errorMessage = nil
        switch step {
        case .configuring: step = .pickingApp
        case .done:
            screenshotSync.discard()
            step = .configuring
        default: break
        }
    }

    func startUpload() {
        task = Task { await upload() }
    }

    func cancel() {
        task?.cancel()
    }

    func upload() async {
        guard canUpload(given: issues), let app = selectedApp, let document else { return }
        errorMessage = nil
        uploadProgress = UploadProgress(totalSteps: 0, completedSteps: 0, currentLabel: String(localized: "Preparing experiment…"))
        step = .uploading
        isBusy = true
        defer { isBusy = false; task = nil }
        CrashReportingService.breadcrumb(.upload, "asc experiment upload", data: ["variants": testableVariants.count])
        do {
            let (experiment, isNew) = try await ensureExperiment(appId: app.id)
            let entries = try await ensureTreatments(for: experiment, isNew: isNew)
            let targets = ASCExperimentPlanner.targets(
                rowsByVariant: rowsByVariant,
                platform: platform,
                experimentName: experiment.name,
                treatments: entries
            )
            guard !targets.isEmpty else { throw ASCExperimentFlowError.nothingToUpload }

            await screenshotSync.build(
                appId: app.id,
                targets: targets,
                rows: rows,
                source: document,
                document: document.documentStamp,
                progress: { [weak self] update in self?.uploadProgress = ASCUploadFlowModel.buildProgress(update) }
            )
            try Task.checkCancellation()
            guard let plan = screenshotSync.plan else {
                throw ASCExperimentFlowError.message(screenshotSync.errorMessage ?? String(localized: "Could not prepare the screenshot sync."))
            }
            let blocked = plan.changedSets.filter { !$0.canApply }
            guard blocked.isEmpty else {
                throw ASCExperimentFlowError.message(blocked.flatMap(\.issues).joined(separator: "\n"))
            }
            if !screenshotSync.selectedSets.isEmpty {
                await screenshotSync.apply(document: document.documentStamp) { [weak self] in self?.uploadProgress = $0 }
                guard screenshotSync.result?.succeeded == true else {
                    throw ASCExperimentFlowError.message(screenshotSync.errorMessage ?? String(localized: "Screenshot sync did not complete."))
                }
            }
            uploadedScreenshotCount = plan.sets.reduce(0) { $0 + $1.proposedAssets.count }
            await refreshSelectedExperiment()
            step = .done
        } catch is CancellationError {
            errorMessage = String(localized: "Upload cancelled. Changes already made in App Store Connect were not reverted.")
            step = .configuring
        } catch {
            errorMessage = error.localizedDescription
            step = .configuring
        }
    }

    func submitForReview() async {
        guard let app = selectedApp, let experiment = selectedExperiment else { return }
        await run {
            try await experimentAPI.submitExperimentForReview(appId: app.id, platform: platform, experimentId: experiment.id)
            CrashReportingService.breadcrumb(.upload, "asc experiment submitted")
            await refreshSelectedExperiment()
        }
    }

    func startExperiment() async {
        guard let experiment = selectedExperiment else { return }
        await run {
            replace(try await experimentAPI.startExperiment(id: experiment.id))
            CrashReportingService.breadcrumb(.upload, "asc experiment started")
        }
    }

    var appStoreConnectURL: URL? {
        guard let app = selectedApp else { return nil }
        return URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)/distribution")
    }

    func tearDown() {
        task?.cancel()
        task = nil
        screenshotSync.discard()
    }

    // MARK: - Private

    private func run(_ body: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await body()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ fresh: ASCExperiment) {
        guard let index = experiments.firstIndex(where: { $0.id == fresh.id }) else { return }
        experiments[index] = fresh
    }

    private func refreshSelectedExperiment() async {
        guard let id = selectedExperimentId, let fresh = try? await experimentAPI.experiment(id: id) else { return }
        replace(fresh)
    }

    private func ensureExperiment(appId: String) async throws -> (experiment: ASCExperiment, isNew: Bool) {
        if let selectedExperiment { return (selectedExperiment, false) }
        let created = try await experimentAPI.createExperiment(
            appId: appId,
            platform: platform,
            name: newExperimentName.trimmingCharacters(in: .whitespaces),
            trafficProportion: trafficProportion
        )
        experiments.insert(created, at: 0)
        selectedExperimentId = created.id
        return (created, true)
    }

    private func ensureTreatments(for experiment: ASCExperiment, isNew: Bool) async throws -> [ASCTreatmentTarget] {
        let variants = testableVariants
        // Re-listed rather than trusting `existingTreatments`, which may predate edits made in App Store Connect.
        let existing = isNew ? [] : try await experimentAPI.listTreatments(experimentId: experiment.id)
        existingTreatments = existing
        let matches = ASCExperimentPlanner.treatmentMatches(variants: variants, existing: existing)
        let assignment = localeAssignment
        let wanted = localeState.locales.map(\.code).compactMap { code -> (projectCode: String, ascLocale: String)? in
            guard enabledLocaleCodes.contains(code), let ascLocale = assignment[code] else { return nil }
            return (code, ascLocale)
        }

        var entries: [ASCTreatmentTarget] = []
        for variant in variants {
            try Task.checkCancellation()
            let treatment: ASCExperimentTreatment
            var treatmentLocalizations: [ASCTreatmentLocalization]
            if let match = matches[variant.id] {
                treatment = match
                treatmentLocalizations = try await experimentAPI.listTreatmentLocalizations(treatmentId: treatment.id)
            } else {
                treatment = try await experimentAPI.createTreatment(experimentId: experiment.id, name: variant.name)
                treatmentLocalizations = []
            }
            var uploadLocalizations: [ASCUploadLocalization] = []
            for (projectCode, ascLocale) in wanted {
                let localization: ASCTreatmentLocalization
                if let found = treatmentLocalizations.first(where: { $0.attributes.locale == ascLocale }) {
                    localization = found
                } else {
                    localization = try await experimentAPI.createTreatmentLocalization(treatmentId: treatment.id, locale: ascLocale)
                    treatmentLocalizations.append(localization)
                }
                uploadLocalizations.append(ASCUploadLocalization(id: localization.id, label: ascLocale, localeCode: projectCode))
            }
            entries.append(ASCTreatmentTarget(variantId: variant.id, treatment: treatment, localizations: uploadLocalizations))
        }
        return entries
    }
}

enum ASCExperimentFlowError: LocalizedError {
    case noVersion(String)
    case nothingToUpload
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noVersion(let platform):
            String(localized: "This app has no \(platform) version on the App Store to run an experiment against.")
        case .nothingToUpload:
            String(localized: "No variant row has a screenshot size App Store Connect accepts for this platform.")
        case .message(let text):
            text
        }
    }
}

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
            platform = preferredPlatform
        }
    }

    /// The app's platform that most variant rows fit, so a Mac project doesn't open on iOS.
    private var preferredPlatform: ASCPlatform {
        let available = availablePlatforms
        let fits = ASCExperimentPlanner.rowsByVariant(rows).values.joined().compactMap {
            ASCDisplayType.detect(width: $0.templateWidth, height: $0.templateHeight)
        }
        return available.max { lhs, rhs in
            fits.filter { $0.accepts(platform: lhs) }.count < fits.filter { $0.accepts(platform: rhs) }.count
        } ?? .ios
    }
    var platform: ASCPlatform = .ios

    /// Every experiment on the app for `platform`, newest first.
    private(set) var experiments: [ASCExperiment] = []
    /// nil creates a new experiment named `newExperimentName`.
    private(set) var selectedExperimentId: String?
    var newExperimentName = ""
    var trafficProportion = 50
    private(set) var existingTreatments: [ASCExperimentTreatment] = []
    /// The experiment whose treatments are loading; uploading waits, or it would match against none.
    private(set) var loadingTreatmentsFor: String?

    /// Project locale → the live product page's locale; a treatment can only localize into those.
    private(set) var localeAssignment: [String: [String]] = [:]
    var enabledLocaleCodes: Set<String> = []

    private(set) var uploadProgress: UploadProgress?
    private(set) var uploadedScreenshotCount = 0
    /// Screenshots an earlier upload left in a treatment that this upload didn't replace.
    private(set) var leftoverNotes: [String] = []
    var errorMessage: String?
    /// The full text behind `errorMessage` when it had to be summarised; shown by Details.
    private(set) var errorDetailsText: String?
    var isBusy = false

    let credentials: AppStoreConnectCredentialsStore
    let screenshotSync: ASCScreenshotSyncCoordinator
    @ObservationIgnored private let uploadAPI: any ASCUploadAPI
    @ObservationIgnored private let experimentAPI: any ASCExperimentAPI
    @ObservationIgnored private let setsAPI: any ASCScreenshotSyncAPI
    @ObservationIgnored private(set) weak var document: (any ASCUploadDocument)?
    @ObservationIgnored var task: Task<Void, Never>?

    init(
        uploadAPI: any ASCUploadAPI = AppStoreConnectAPIService.shared,
        experimentAPI: any ASCExperimentAPI = AppStoreConnectAPIService.shared,
        setsAPI: any ASCScreenshotSyncAPI = AppStoreConnectAPIService.shared,
        credentials: AppStoreConnectCredentialsStore = .shared,
        screenshotSync: ASCScreenshotSyncCoordinator = ASCScreenshotSyncCoordinator()
    ) {
        self.uploadAPI = uploadAPI
        self.experimentAPI = experimentAPI
        self.setsAPI = setsAPI
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
            localeAssignment: localeAssignment,
            originalDisplayTypes: Set(rows.filter { $0.uploadsToAppStore(from: nil) }.compactMap {
                ASCExperimentPlanner.uploadableDisplayType(for: $0, platform: platform)
            })
        )
    }

    /// What Upload Treatments will do, for its confirmation.
    var uploadSummary: String {
        let testable = testableVariants
        let created = testable.count - ASCExperimentPlanner.treatmentMatches(variants: testable, existing: existingTreatments).count
        let languages = enabledLocaleCodes.filter { localeAssignment[$0] != nil }.count
        let target = selectedExperiment.map { String(localized: "“\($0.name)”") }
            ?? String(localized: "a new experiment, “\(newExperimentName.trimmingCharacters(in: .whitespaces))”,")
        var summary = String(inflecting: "Uploads ^[\(testable.count) treatment](inflect: true) to \(target) in ^[\(languages) language](inflect: true).")
        if created > 0 {
            summary += " " + String(inflecting: "^[\(created) treatment](inflect: true) will be created in App Store Connect.")
        }
        return summary + " " + String(localized: "Nothing goes live until the experiment is approved and you start it.")
    }

    /// An existing experiment past the point where its screenshots can change.
    var isSelectedExperimentLocked: Bool {
        selectedExperiment.map { !$0.state.isEditable } ?? false
    }

    func canUpload(given issues: [UploadIssue]) -> Bool {
        !isBusy && loadingTreatmentsFor == nil && !issues.hasErrors
    }

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
            await selectExperiment((experiments.first(where: \.canStart) ?? experiments.first { $0.state.isEditable })?.id)
            step = .configuring
        }
    }

    func selectExperiment(_ id: String?) async {
        selectedExperimentId = id
        existingTreatments = []
        loadingTreatmentsFor = id
        guard let id else { return }
        // Not `run`: a stale reply for an experiment the user left must not touch busy or error state.
        let result: Result<[ASCExperimentTreatment], Error>
        do {
            result = .success(try await experimentAPI.listTreatments(experimentId: id))
        } catch {
            result = .failure(error)
        }
        guard selectedExperimentId == id else { return }
        loadingTreatmentsFor = nil
        switch result {
        case .success(let treatments): existingTreatments = treatments
        case .failure(is CancellationError): break
        case .failure(let error): errorMessage = error.localizedDescription
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
        errorDetailsText = nil
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
                errorDetailsText = blocked.flatMap { set in
                    set.issues.map { "\(set.versionLabel) · \(set.localeLabel) · \(set.displayType.label): \($0)" }
                }.joined(separator: "\n")
                throw ASCExperimentFlowError.blocked(sets: blocked.count)
            }
            if !screenshotSync.selectedSets.isEmpty {
                await screenshotSync.apply(document: document.documentStamp) { [weak self] in self?.uploadProgress = $0 }
                guard screenshotSync.result?.succeeded == true else {
                    throw ASCExperimentFlowError.message(screenshotSync.errorMessage ?? String(localized: "Screenshot sync did not complete."))
                }
            }
            uploadedScreenshotCount = plan.sets.reduce(0) { $0 + $1.proposedAssets.count }
            leftoverNotes = await leftovers(in: entries, targets: targets)
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
            // App Store Connect can lag a moment behind; a second Submit would only fail.
            if let current = selectedExperiment, current.state.isEditable {
                replace(current.with(state: .waitingForReview))
            }
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
        errorDetailsText = nil
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

    /// Best effort and read-only: removing screenshots from a live test is the user's call, in App Store Connect.
    private func leftovers(in entries: [ASCTreatmentTarget], targets: [ASCUploadTarget]) async -> [String] {
        let toCheck = entries.filter { !$0.preexistingLocalizations.isEmpty }
        guard !toCheck.isEmpty else { return [] }
        uploadProgress = UploadProgress(totalSteps: 0, completedSteps: 0, currentLabel: String(localized: "Checking for screenshots from earlier uploads…"))
        var notes: [String] = []
        for entry in toCheck {
            let uploadedIds = Set(entry.localizations.map(\.id))
            let uploadedTypes = Set(targets.filter { $0.versionId == entry.treatment.id }.map(\.displayType.appStoreConnectValue))
            var stale: Set<String> = []
            // A few at a time: the upload that just ran has already spent much of the rate limit.
            let localizations = entry.preexistingLocalizations
            for start in stride(from: 0, to: localizations.count, by: 4) {
                if Task.isCancelled { return notes }
                await withTaskGroup(of: [String].self) { group in
                    for localization in localizations[start..<min(start + 4, localizations.count)] {
                        let wasUploaded = uploadedIds.contains(localization.id)
                        group.addTask { await self.staleLabels(in: localization, wasUploaded: wasUploaded, uploadedTypes: uploadedTypes) }
                    }
                    for await labels in group { stale.formUnion(labels) }
                }
            }
            if !stale.isEmpty {
                notes.append(String(localized: "“\(entry.treatment.name)” still has \(stale.sorted().joined(separator: ", ")) screenshots from an earlier upload."))
            }
        }
        return notes
    }

    /// The language, if this upload skipped it and it has screenshots; else sizes it has that this upload didn't send.
    private func staleLabels(in localization: ASCTreatmentLocalization, wasUploaded: Bool, uploadedTypes: Set<String>) async -> [String] {
        guard let sets = try? await setsAPI.listScreenshotSets(parent: .treatmentLocalization(localization.id)) else { return [] }
        var sizes: [String] = []
        for set in sets {
            guard !Task.isCancelled, let raw = set.attributes.screenshotDisplayType,
                  !wasUploaded || !uploadedTypes.contains(raw),
                  (try? await setsAPI.listScreenshots(setId: set.id, limit: 1, retryPolicy: nil))?.isEmpty == false
            else { continue }
            if !wasUploaded { return [LocaleDefinition.displayName(forCode: localization.attributes.locale)] }
            sizes.append(ASCDisplayType.allCases.first { $0.appStoreConnectValue == raw }?.label ?? raw)
        }
        return sizes
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
        let wanted = localeState.locales.map(\.code).flatMap { code -> [(projectCode: String, ascLocale: String)] in
            guard enabledLocaleCodes.contains(code) else { return [] }
            return (assignment[code] ?? []).map { (code, $0) }
        }

        var entries: [ASCTreatmentTarget] = []
        for variant in variants {
            try Task.checkCancellation()
            let treatment: ASCExperimentTreatment
            var treatmentLocalizations: [ASCTreatmentLocalization] = []
            if let match = matches[variant.id] {
                treatment = match
                treatmentLocalizations = try await experimentAPI.listTreatmentLocalizations(treatmentId: treatment.id)
            } else {
                treatment = try await experimentAPI.createTreatment(experimentId: experiment.id, name: variant.name)
                existingTreatments.append(treatment)
            }
            let preexisting = treatmentLocalizations
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
            entries.append(ASCTreatmentTarget(
                variantId: variant.id,
                treatment: treatment,
                localizations: uploadLocalizations,
                preexistingLocalizations: preexisting
            ))
        }
        return entries
    }
}

enum ASCExperimentFlowError: LocalizedError {
    case noVersion(String)
    case nothingToUpload
    case blocked(sets: Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noVersion(let platform):
            String(localized: "This app has no \(platform) version on the App Store to run an experiment against.")
        case .nothingToUpload:
            String(localized: "No variant row has a screenshot size App Store Connect accepts for this platform.")
        case .blocked(let sets):
            String(inflecting: "App Store Connect can't take ^[\(sets) screenshot set](inflect: true) yet. Open Details to see why.")
        case .message(let text):
            text
        }
    }
}

import Foundation

extension ASCUploadFlowModel {
    // MARK: - Building the upload plan

    /// Left as a computed property rather than memoized: it is O(destinations × rows), and it
    /// depends on `credentials.isDemoMode`, which can flip from a separate Settings window.
    var validationIssues: [UploadIssue] {
        var issues = AppStoreConnectUploadValidator.validate(
            destinations: destinationPlans,
            isDemoMode: credentials.isDemoMode
        )
        let variantRowCount = document?.activeVariants.isEmpty == false ? rows.filter { !$0.isOriginal }.count : 0
        if variantRowCount > 0 {
            issues.append(UploadIssue(
                severity: .warning,
                message: String(inflecting: "^[\(variantRowCount) A/B variant row](inflect: true) won't be uploaded to your product page."),
                hint: String(localized: "To test them, use Export ▸ Upload A/B Test to App Store Connect.")
            ))
        }
        if let document {
            issues += textOverflowIssues.issues(rows: rows.filter(\.uploadsToAppStoreListing), source: document)
        }
        return issues
    }

    var canStartUpload: Bool {
        !validationIssues.hasErrors
    }

    /// Apply the one-click fix an issue offers. Re-resolves the plan by id rather than trusting
    /// the issue to still describe the current state — the panel is rebuilt from the plans on
    /// every change, but a fix can be tapped against a plan a refresh has already replaced.
    func apply(_ fix: UploadIssueFix) {
        guard let destinationIndex = destinationPlans.firstIndex(where: { $0.id == fix.destinationId }),
              let rowIndex = destinationPlans[destinationIndex].rowPlans.firstIndex(where: { $0.id == fix.rowId })
        else { return }

        var plans = destinationPlans
        switch fix.action {
        case .useDetectedAssetType:
            guard let detected = plans[destinationIndex].rowPlans[rowIndex].detectedAssetType else { return }
            plans[destinationIndex].rowPlans[rowIndex].selectedAssetType = detected
        case .selectMatchingStoreLocales:
            let targets = plans[destinationIndex].rowPlans[rowIndex].localeTargets
            for index in targets.indices
            where fix.appLocaleCodes.contains(targets[index].appLocaleCode) && !targets[index].candidates.isEmpty {
                plans[destinationIndex].rowPlans[rowIndex].localeTargets[index].isEnabled = true
                plans[destinationIndex].rowPlans[rowIndex].localeTargets[index].selectedASCLocalizationIds =
                    Set(targets[index].candidates.map(\.id))
            }
        }
        CrashReportingService.breadcrumb(.upload, "asc apply plan fix", data: ["action": "\(fix.action)"])
        updateDestinationPlans(plans)
    }

    func moveToPlan() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await loadSelectedVersionLocalizations()
            updateDestinationPlans(buildDestinationPlans(preserving: destinationPlans))
            advance(to: .configuringPlan)
            reloadRemoteScreenshotCounts()
        } catch {
            errorMessage = String(localized: "Could not load App Store data: \(error.localizedDescription)")
        }
    }

    func refreshLocalizations() async {
        guard !selectedVersions.isEmpty else { return }
        seedDemoContextIfNeeded()
        isBusy = true
        errorMessage = nil
        localeCreationErrors = [:]
        defer { isBusy = false }
        do {
            try await loadSelectedVersionLocalizations()
            updateDestinationPlans(buildDestinationPlans(preserving: destinationPlans))
            reloadRemoteScreenshotCounts()
        } catch {
            errorMessage = String(localized: "Could not refresh locales: \(error.localizedDescription)")
        }
    }

    func loadSelectedVersionLocalizations() async throws {
        for version in selectedVersions {
            let fetched = try await api.listLocalizations(versionId: version.id)
            localizationsByVersionId[version.id] = fetched
        }
    }

    // MARK: - Existing screenshots

    /// Requests in flight at once. The fetch runs beside the upload, which needs the same
    /// per-hour API quota, so it trickles rather than bursting one GET per localization.
    static let screenshotCountConcurrency = 4
    /// Results published per write, so the plan re-renders a few times rather than once per locale.
    static let screenshotCountBatchSize = 8

    /// Fetches what each selected version's localizations already hold, in the background; the
    /// plan step never waits on it. A full reload drops every known count and any fetch still
    /// running; `keepingKnown` only adds localizations neither known nor in flight (a freshly
    /// created locale).
    func reloadRemoteScreenshotCounts(keepingKnown: Bool = false) {
        if !keepingKnown {
            cancelRemoteScreenshotCounts()
            remoteScreenshotCounts = [:]
        }
        var seen = Set<String>()
        let ids = selectedVersions
            .flatMap { localizationsByVersionId[$0.id] ?? [] }
            .map(\.id)
            .filter { seen.insert($0).inserted && remoteScreenshotCounts[$0] == nil && !remoteScreenshotCountsInFlight.contains($0) }
        guard !ids.isEmpty else { return }
        remoteScreenshotCountsInFlight.formUnion(ids)
        let generation = remoteScreenshotCountsGeneration
        remoteScreenshotCountTasks.append(Task { [weak self] in
            await self?.loadRemoteScreenshotCounts(localizationIds: ids, generation: generation)
        })
    }

    /// Bumping the generation is what actually stops a cancelled fetch from writing: a request
    /// already on the wire still returns, and its result is dropped.
    func cancelRemoteScreenshotCounts() {
        remoteScreenshotCountsGeneration += 1
        remoteScreenshotCountTasks.forEach { $0.cancel() }
        remoteScreenshotCountTasks = []
        remoteScreenshotCountsInFlight = []
    }

    func settleRemoteScreenshotCounts() async {
        for task in remoteScreenshotCountTasks {
            await task.value
        }
    }

    private func loadRemoteScreenshotCounts(localizationIds: [String], generation: Int) async {
        let api = api
        var pending: [String: [String: Int]] = [:]
        var failures = 0
        await withTaskGroup(of: (String, [String: Int]?).self) { group in
            var queue = localizationIds.makeIterator()
            func startNext() {
                guard let id = queue.next() else { return }
                group.addTask { (id, try? await api.screenshotCountsByDisplayType(localizationId: id)) }
            }
            for _ in 0..<Self.screenshotCountConcurrency { startNext() }
            for await (id, counts) in group {
                guard generation == remoteScreenshotCountsGeneration else {
                    group.cancelAll()
                    return
                }
                if let counts { pending[id] = counts } else { failures += 1 }
                if pending.count >= Self.screenshotCountBatchSize {
                    remoteScreenshotCounts.merge(pending) { $1 }
                    pending = [:]
                }
                startNext()
            }
        }
        guard generation == remoteScreenshotCountsGeneration else { return }
        if !pending.isEmpty { remoteScreenshotCounts.merge(pending) { $1 } }
        remoteScreenshotCountsInFlight.subtract(localizationIds)
        if failures > 0 {
            CrashReportingService.breadcrumb(.upload, "asc screenshot counts failed", data: ["count": failures])
        }
    }

    /// Catches the reviewed plan up with document edits (see `StoreRowPlan.reconciling`); false when nothing is left.
    @discardableResult
    func reconcileDestinationPlansWithDocument() -> Bool {
        let reviewed = destinationPlans
        updateDestinationPlans(buildDestinationPlans(preserving: reviewed).map { destination in
            var destination = destination
            let reviewedRows = reviewed.first { $0.id == destination.id }?.rowPlans ?? []
            destination.rowPlans = ASCRowPlan.reconciling(reviewedRows, with: destination.rowPlans)
            return destination
        })
        return !ASCRowPlan.reconcileEmptied(reviewed.flatMap(\.rowPlans), into: destinationPlans.flatMap(\.rowPlans))
    }

    func buildDestinationPlans(preserving existingPlans: [ASCDestinationPlan] = []) -> [ASCDestinationPlan] {
        selectedVersions.map { version in
            let versionLocalizations = localizationsByVersionId[version.id] ?? []
            let existingDestination = existingPlans.first(where: { $0.id == version.id })
            return ASCDestinationPlan(
                id: version.id,
                version: version,
                localizations: versionLocalizations,
                rowPlans: buildRowPlans(
                    for: version,
                    localizations: versionLocalizations,
                    preserving: existingDestination?.rowPlans ?? []
                )
            )
        }
    }

    func buildRowPlans(
        for version: ASCAppStoreVersion,
        localizations: [ASCAppStoreVersionLocalization],
        preserving existingPlans: [ASCRowPlan] = []
    ) -> [ASCRowPlan] {
        let platform = version.attributes.ascPlatform
        let demoFallbackDisplayType = credentials.isDemoMode
            ? ASCDisplayType.userSelectableCases(forPlatform: platform).first
            : nil
        let assignment = ASCLocaleMatcher.assign(appCodes: localeState.locales.map(\.code), to: localizations)
        return rows.filter(\.uploadsToAppStoreListing).map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = localeState.locales.map { locale -> ASCLocaleTarget in
                let matches = assignment[locale.code] ?? []
                let candidateIds = Set(matches.map(\.id))
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                // Preserve the prior selection, but if none of it survives the refreshed
                // candidate set, fall back to selecting all (same as a fresh target) rather
                // than leaving an enabled locale with nothing selected, which hard-blocks upload.
                let preserved = existingTarget.map { $0.selectedASCLocalizationIds.intersection(candidateIds) }
                let selectedIds = (preserved?.isEmpty == false) ? preserved! : candidateIds
                return ASCLocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    selectedASCLocalizationIds: selectedIds,
                    candidates: matches,
                    // A target that was off only because nothing matched must come back on once a
                    // candidate appears, or creating the locale (or adding it by hand and hitting
                    // Refresh) leaves the row matched but silently skipped. `candidates.isEmpty`
                    // is what tells that apart from a matched locale the user unticked.
                    isEnabled: matches.isEmpty
                        ? false
                        : (existingTarget.map { $0.isEnabled || $0.candidates.isEmpty } ?? true)
                )
            }
            // A pick that matched detection follows a resize (kept if the new size is unrecognised); an override stays.
            let previous = existingPlan?.selectedAssetType.flatMap { $0.accepts(platform: platform) ? $0 : nil }
            let followsDetection = existingPlan.map { $0.selectedAssetType == $0.detectedAssetType } ?? true
            let compatiblePreserved = followsDetection ? nil : previous
            let detectedCompatible = (detected?.accepts(platform: platform) ?? false) ? detected : nil
            let detectedIncompatible = detected != nil && detectedCompatible == nil
            return ASCRowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: row.templateSize,
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? (row.inferredStorePlatform != .android && !detectedIncompatible),
                detectedAssetType: detected,
                selectedAssetType: compatiblePreserved ?? detectedCompatible ?? previous ?? demoFallbackDisplayType,
                localeTargets: targets,
                inferredStorePlatform: row.inferredStorePlatform
            )
        }
    }
}

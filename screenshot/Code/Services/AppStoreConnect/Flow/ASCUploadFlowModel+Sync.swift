import Foundation

extension ASCUploadFlowModel {
    // MARK: - Screenshot sync and error text
    func startScreenshotReviewBuild() {
        uploadTask = Task { await buildScreenshotReview() }
    }

    func startDirectScreenshotSync() {
        uploadTask = Task { await buildAndApplyDirectScreenshotSync(strategy: .reconcile) }
    }

    /// Upload every selected screenshot and delete whatever is on the store, without matching
    /// checksums. Faster to prepare and slower to apply — see the confirmation copy.
    func startReplaceAllScreenshotSync() {
        uploadTask = Task { await buildAndApplyDirectScreenshotSync(strategy: .replaceAll) }
    }

    func startReviewedScreenshotSync() {
        uploadTask = Task { await applyPreparedScreenshotSync(returnOnFailure: .reviewingChanges) }
    }

    func startScreenshotReviewRefresh() {
        uploadTask = Task { await refreshScreenshotReview() }
    }

    func buildScreenshotReview() async {
        errorMessage = nil
        errorDetailsText = nil
        guard reconcileDestinationPlansWithDocument() else {
            errorMessage = StoreUploadFailureText.rowsRemoved
            return
        }
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before reviewing changes.")
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × locales are selected.")
            return
        }
        guard let appId = selectedApp?.id, let document else { return }

        isBusy = true
        defer { isBusy = false; uploadTask = nil }
        advance(to: .reviewingChanges)
        await screenshotSync.build(appId: appId, targets: targets, rows: rows, source: document, document: document.documentStamp, needsPreviews: true)
        if screenshotSync.plan == nil {
            errorMessage = screenshotSync.errorMessage
        }
    }

    func refreshScreenshotReview() async {
        guard let appId = selectedApp?.id, let document else { return }
        isBusy = true
        defer { isBusy = false; uploadTask = nil }
        await screenshotSync.build(appId: appId, targets: buildUploadTargets(), rows: rows, source: document, document: document.documentStamp, needsPreviews: true)
        errorMessage = screenshotSync.errorMessage
    }

    func buildAndApplyDirectScreenshotSync(strategy: ASCSyncStrategy) async {
        defer { uploadTask = nil }
        errorMessage = nil
        errorDetailsText = nil
        guard reconcileDestinationPlansWithDocument() else {
            errorMessage = StoreUploadFailureText.rowsRemoved
            return
        }
        guard !validationIssues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before uploading.")
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × locales are selected.")
            return
        }
        guard let appId = selectedApp?.id, let document else { return }

        // `totalSteps: 0` on purpose: the view draws a determinate bar whenever it is positive,
        // and a bar pinned at 0/1 for the whole build reads as a hang. Real counts arrive with
        // the first progress callback.
        uploadProgress = UploadProgress(
            totalSteps: 0,
            completedSteps: 0,
            currentLabel: String(localized: "Preparing screenshot sync…")
        )
        advance(to: .uploading)
        isBusy = true
        defer { isBusy = false }
        let outcome = await screenshotSync.buildAndApply(
            appId: appId,
            targets: targets,
            rows: rows,
            source: document,
            document: document.documentStamp,
            strategy: strategy,
            progress: { [weak self] in self?.uploadProgress = $0 }
        )

        switch outcome {
        case .applied(_, let sets):
            finishScreenshotSync(using: sets)
        case .nothingToChange(let plan):
            finishScreenshotSync(using: plan.sets)
            screenshotSync.discard()
        case .blocked(let blockedSets):
            errorMessage = String(localized: "Some screenshot sets require review before they can be synced.")
            errorDetailsText = blockedSets.flatMap(\.issues).joined(separator: "\n")
            retreatAfterScreenshotSync(to: .configuringPlan)
        case .buildFailed:
            if !screenshotSync.wasCancelled {
                errorMessage = screenshotSync.errorMessage ?? String(localized: "Could not prepare the screenshot sync.")
                errorDetailsText = errorMessage
            }
            retreatAfterScreenshotSync(to: .configuringPlan)
        case .applyFailed:
            reportFailedApply(returnTo: .configuringPlan)
        }
    }

    func applyPreparedScreenshotSync(returnOnFailure: ASCUploadStep) async {
        defer { uploadTask = nil }
        errorMessage = nil
        errorDetailsText = nil
        let selectedSets = screenshotSync.selectedSets
        guard !selectedSets.isEmpty else {
            errorMessage = ASCScreenshotSyncError.noSetsSelected.localizedDescription
            return
        }

        uploadProgress = UploadProgress(
            totalSteps: 0,
            completedSteps: 0,
            currentLabel: String(localized: "Starting upload…")
        )
        advance(to: .uploading)
        isBusy = true
        defer { isBusy = false }

        await screenshotSync.apply(document: document?.documentStamp, progress: { p in self.uploadProgress = p })
        if screenshotSync.result?.succeeded == true {
            finishScreenshotSync(using: selectedSets)
        } else {
            reportFailedApply(returnTo: returnOnFailure)
        }
    }

    private func reportFailedApply(returnTo step: ASCUploadStep) {
        let message = screenshotSync.errorMessage
            ?? screenshotSync.result?.sets.compactMap(\.error).first
            ?? String(localized: "Screenshot sync did not complete.")
        errorMessage = message
        errorDetailsText = message
        retreatAfterScreenshotSync(to: step)
        // A failed apply can still have changed some sets; nothing else on this path sends.
        reloadRemoteScreenshotCounts()
        (screenshotSync.failure ?? .unknown).report(store: "asc", cancelled: screenshotSync.wasCancelled)
        NotificationService.notify(title: String(localized: "Screenshot sync stopped"), body: message)
    }

    func finishScreenshotSync(using sets: [ASCScreenshotSetDiff]) {
        let summary = ASCUploadSummary(
            appId: selectedApp?.id,
            appName: selectedApp?.attributes.name ?? "",
            totalScreenshots: sets.reduce(0) { $0 + $1.proposedAssets.count },
            localizationCount: Set(sets.map { "\($0.versionId)|\($0.localizationId)" }).count,
            versionCount: Set(sets.map(\.versionId)).count
        )
        uploadSummary = summary
        StoreUploadFailure.reportSuccess(store: "asc", imageCount: summary.totalScreenshots, localeCount: summary.localizationCount)
        completeTerminalStep(.done)
        let body = summary.appName.isEmpty
            ? syncCompleteBody(
                screenshotCount: summary.totalScreenshots,
                localizationCount: summary.localizationCount,
                versionCount: summary.versionCount
            )
            : syncCompleteBody(
                screenshotCount: summary.totalScreenshots,
                localizationCount: summary.localizationCount,
                versionCount: summary.versionCount,
                appName: summary.appName
            )
        NotificationService.notify(title: String(localized: "Screenshot sync complete"), body: body)
    }

    private func syncCompleteBody(
        screenshotCount: Int,
        localizationCount: Int,
        versionCount: Int,
        appName: String? = nil
    ) -> String {
        let body: String
        switch (screenshotCount == 1, localizationCount == 1, versionCount == 1) {
        case (true, true, true):
            body = String(localized: "1 screenshot across 1 locale and 1 version")
        case (true, true, false):
            body = String(localized: "1 screenshot across 1 locale and \(versionCount) versions")
        case (true, false, true):
            body = String(localized: "1 screenshot across \(localizationCount) locales and 1 version")
        case (true, false, false):
            body = String(localized: "1 screenshot across \(localizationCount) locales and \(versionCount) versions")
        case (false, true, true):
            body = String(localized: "\(screenshotCount) screenshots across 1 locale and 1 version")
        case (false, true, false):
            body = String(localized: "\(screenshotCount) screenshots across 1 locale and \(versionCount) versions")
        case (false, false, true):
            body = String(localized: "\(screenshotCount) screenshots across \(localizationCount) locales and 1 version")
        case (false, false, false):
            body = String(localized: "\(screenshotCount) screenshots across \(localizationCount) locales and \(versionCount) versions")
        }
        guard let appName, !appName.isEmpty else { return body }
        return String(localized: "\(body) · \(appName)")
    }

    func buildUploadTargets() -> [ASCUploadTarget] {
        destinationPlans.flatMap { destination -> [ASCUploadTarget] in
            destination.rowPlans.compactMap { plan -> ASCUploadTarget? in
                guard plan.isEnabled, let displayType = plan.selectedAssetType else { return nil }
                guard let row = rows.first(where: { $0.id == plan.id }),
                      row.uploadsToAppStoreListing else { return nil }
                let localizations = plan.localeTargets.flatMap { target -> [ASCUploadLocalization] in
                    guard target.isEnabled else { return [] }
                    return target.selectedCandidates
                        .map { ASCUploadLocalization(id: $0.id, label: $0.attributes.locale, localeCode: target.appLocaleCode) }
                }
                guard !localizations.isEmpty else { return nil }
                return ASCUploadTarget(
                    versionId: destination.id,
                    versionLabel: destination.title,
                    parentKind: .versionLocalization,
                    rowId: plan.id,
                    rowLabel: plan.displayLabel,
                    rowSize: plan.rowSize,
                    displayType: displayType,
                    localizations: localizations,
                    templateCount: plan.templateCount
                )
            }
        }
    }
}

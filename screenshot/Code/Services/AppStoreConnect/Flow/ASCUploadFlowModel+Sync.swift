import Foundation

extension ASCUploadFlowModel {
    // MARK: - Screenshot sync and error text
    func startScreenshotReviewBuild() {
        uploadTask = Task { await buildScreenshotReview() }
    }

    func startDirectScreenshotSync() {
        uploadTask = Task { await buildAndApplyDirectScreenshotSync() }
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
        await screenshotSync.build(appId: appId, targets: targets, rows: rows, source: document, document: document.documentStamp)
        if screenshotSync.plan == nil {
            errorMessage = screenshotSync.errorMessage
        }
    }

    func refreshScreenshotReview() async {
        guard let appId = selectedApp?.id, let document else { return }
        isBusy = true
        defer { isBusy = false; uploadTask = nil }
        await screenshotSync.build(appId: appId, targets: buildUploadTargets(), rows: rows, source: document, document: document.documentStamp)
        errorMessage = screenshotSync.errorMessage
    }

    func buildAndApplyDirectScreenshotSync() async {
        errorMessage = nil
        errorDetailsText = nil
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before uploading.")
            uploadTask = nil
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × locales are selected.")
            uploadTask = nil
            return
        }
        guard let appId = selectedApp?.id, let document else {
            uploadTask = nil
            return
        }

        uploadProgress = UploadProgress(totalSteps: 1, completedSteps: 0, currentLabel: "Preparing safe screenshot sync…")
        advance(to: .uploading)
        isBusy = true
        await screenshotSync.build(appId: appId, targets: targets, rows: rows, source: document, document: document.documentStamp)
        isBusy = false

        guard let plan = screenshotSync.plan else {
            if !screenshotSync.wasCancelled {
                errorMessage = screenshotSync.errorMessage ?? String(localized: "Could not prepare the screenshot sync.")
                errorDetailsText = errorMessage
            }
            uploadTask = nil
            retreatAfterScreenshotSync(to: .configuringPlan)
            return
        }

        let blockedSets = plan.changedSets.filter { !$0.canApply }
        guard blockedSets.isEmpty else {
            errorMessage = String(localized: "Some screenshot sets require review before they can be synced.")
            errorDetailsText = blockedSets.flatMap(\.issues).joined(separator: "\n")
            uploadTask = nil
            retreatAfterScreenshotSync(to: .configuringPlan)
            return
        }

        let selectedSets = screenshotSync.selectedSets
        if selectedSets.isEmpty {
            finishScreenshotSync(using: plan.sets)
            screenshotSync.discard()
            uploadTask = nil
            return
        }
        await applyPreparedScreenshotSync(
            returnOnFailure: .configuringPlan,
            advanceToUploading: false
        )
    }

    func applyPreparedScreenshotSync(
        returnOnFailure: ASCUploadStep,
        advanceToUploading: Bool = true
    ) async {
        errorMessage = nil
        errorDetailsText = nil
        let selectedSets = screenshotSync.selectedSets
        guard !selectedSets.isEmpty else {
            errorMessage = ASCScreenshotSyncError.noSetsSelected.localizedDescription
            uploadTask = nil
            return
        }

        uploadProgress = nil
        if advanceToUploading {
            advance(to: .uploading)
        }
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        await screenshotSync.apply(document: document?.documentStamp, progress: { p in self.uploadProgress = p })
        if screenshotSync.result?.succeeded == true {
            finishScreenshotSync(using: selectedSets)
        } else {
            let message = screenshotSync.errorMessage
                ?? screenshotSync.result?.sets.compactMap(\.error).first
                ?? String(localized: "Screenshot sync did not complete.")
            errorMessage = message
            errorDetailsText = message
            retreatAfterScreenshotSync(to: returnOnFailure)
            NotificationService.notify(title: String(localized: "Screenshot sync stopped"), body: message)
        }
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
        completeTerminalStep(.done)
        let shotNoun = summary.totalScreenshots == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let locNoun = summary.localizationCount == 1 ? String(localized: "locale") : String(localized: "locales")
        let versionNoun = summary.versionCount == 1 ? String(localized: "version") : String(localized: "versions")
        let body = summary.appName.isEmpty
            ? String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) and \(summary.versionCount) \(versionNoun)")
            : String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) and \(summary.versionCount) \(versionNoun) · \(summary.appName)")
        NotificationService.notify(title: String(localized: "Screenshot sync complete"), body: body)
    }

    func buildUploadTargets() -> [ASCUploadTarget] {
        destinationPlans.flatMap { destination -> [ASCUploadTarget] in
            destination.rowPlans.compactMap { plan -> ASCUploadTarget? in
                guard plan.isEnabled, let displayType = plan.selectedAssetType else { return nil }
                guard let row = rows.first(where: { $0.id == plan.id }),
                      !row.excludeFromAppStoreConnect else { return nil }
                let localizations = plan.localeTargets.flatMap { target -> [ASCUploadLocalization] in
                    guard target.isEnabled else { return [] }
                    return target.selectedCandidates
                        .map { ASCUploadLocalization(id: $0.id, label: $0.attributes.locale, localeCode: target.appLocaleCode) }
                }
                guard !localizations.isEmpty else { return nil }
                return ASCUploadTarget(
                    versionId: destination.id,
                    versionLabel: destination.title,
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

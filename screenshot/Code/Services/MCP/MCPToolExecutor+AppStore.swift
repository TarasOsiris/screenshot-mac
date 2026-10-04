#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    func getAppStoreMetadata(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        let appId = try resolveASCAppId(fromAppIdOrProject: args)
        let versions = try await ascVersions(appId: appId, requested: args.string("version_id"))

        var metas: [ASCMetadataResult.VersionMeta] = []
        for version in versions {
            let localizations = try await ascAPI.listLocalizations(versionId: version.id)
            metas.append(ASCMetadataResult.VersionMeta(
                versionId: version.id,
                platform: version.attributes.platform,
                versionString: version.attributes.versionString,
                appStoreState: version.attributes.appStoreState,
                editable: version.isEditable,
                locales: localizations
                    .sorted { $0.attributes.locale < $1.attributes.locale }
                    .map { .init(locale: $0.attributes.locale, description: $0.attributes.description) }
            ))
        }
        return try MCPResultEncoding.result(ASCMetadataResult(appId: appId, versions: metas))
    }

    func updateAppStoreDescription(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        guard let entries = args.objectArray("descriptions"), !entries.isEmpty else {
            throw MCPToolError.missingArgument("descriptions")
        }
        let descriptions: [(locale: String, text: String)] = try entries.map {
            (try $0.requiredString("locale"), try $0.requiredString("description"))
        }

        let appId = try resolveASCAppId(fromAppIdOrProject: args)
        let targets = try await resolveEditableTargets(appId: appId, requested: args.string("version_id"))

        var results: [ASCDescriptionUpdateResult.VersionResult] = []
        for version in targets {
            let localizationIdByLocale = Dictionary(
                try await ascAPI.listLocalizations(versionId: version.id).map { ($0.attributes.locale, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            var updated: [String] = []
            var skipped: [ASCDescriptionUpdateResult.Skip] = []
            for entry in descriptions {
                guard let localizationId = localizationIdByLocale[entry.locale] else {
                    skipped.append(.init(locale: entry.locale, reason: "no App Store localization for this locale on the version"))
                    continue
                }
                do {
                    try await ascAPI.updateVersionLocalization(id: localizationId, attributes: ["description": AnyEncodable(entry.text)])
                    updated.append(entry.locale)
                } catch {
                    skipped.append(.init(locale: entry.locale, reason: error.localizedDescription))
                }
            }
            results.append(.init(
                versionId: version.id,
                platform: version.attributes.platform,
                updated: updated.sorted(),
                skipped: skipped.sorted { $0.locale < $1.locale }
            ))
        }
        return try MCPResultEncoding.result(ASCDescriptionUpdateResult(appId: appId, results: results))
    }

    func previewAppStoreScreenshotSync(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        let checkout = try await requireCheckout(args)
        // Disposed here only on the paths that throw before the job starts; once it does, the job
        // owns the checkout, because `runJob` returns long before an async body has rendered.
        var jobOwnsCheckout = false
        defer { if !jobOwnsCheckout { checkout.dispose() } }
        let appId = try resolveASCAppId(args, checkout: checkout)
        let requestedVersionIds = Set(args.stringArray("version_ids") ?? [])
        let allVersions = try await ascAPI.listAppStoreVersions(appId: appId)
        let candidateVersions: [ASCAppStoreVersion]
        if requestedVersionIds.isEmpty {
            candidateVersions = allVersions.filter(\.isScreenshotUploadable)
        } else {
            let found = allVersions.filter { requestedVersionIds.contains($0.id) }
            let missing = requestedVersionIds.subtracting(found.map(\.id))
            guard missing.isEmpty else { throw MCPToolError.notFound("App Store versions: \(missing.sorted().joined(separator: ", "))") }
            candidateVersions = found.filter(\.isScreenshotUploadable)
        }

        let requestedRowStrings = args.stringArray("row_ids") ?? []
        let requestedRowIds = try Set(requestedRowStrings.map { value -> UUID in
            guard let id = UUID(uuidString: value) else { throw MCPToolError.invalidArgument("row_ids", "not a UUID: \(value)") }
            return id
        })
        let requestedLocaleCodes = Set(args.stringArray("locale_codes") ?? [])
        let projectLocaleCodes = Set(checkout.localeState.locales.map(\.code))
        let unknownLocales = requestedLocaleCodes.subtracting(projectLocaleCodes)
        guard unknownLocales.isEmpty else {
            throw MCPToolError.invalidArgument(
                "locale_codes",
                "not in project \(checkout.projectName): \(unknownLocales.sorted().joined(separator: ", "))"
            )
        }
        let localeCodes = requestedLocaleCodes.isEmpty
            ? checkout.localeState.locales.map(\.code)
            : checkout.localeState.locales.map(\.code).filter(requestedLocaleCodes.contains)

        var issues: [String] = []
        let rows = checkout.rows.filter { row in
            requestedRowIds.isEmpty || requestedRowIds.contains(row.id)
        }
        let missingRows = requestedRowIds.subtracting(rows.map(\.id))
        guard missingRows.isEmpty else { throw MCPToolError.notFound("Rows: \(missingRows.map(\.uuidString).sorted().joined(separator: ", "))") }

        var targets: [ASCUploadTarget] = []
        for version in candidateVersions {
            let planned = MCPScreenshotTargetPlanner.targets(
                version: version,
                remoteLocalizations: try await ascAPI.listLocalizations(versionId: version.id),
                rows: rows,
                localeCodes: localeCodes
            )
            targets += planned.targets
            issues += planned.issues
        }
        guard !targets.isEmpty else {
            throw MCPToolError.expected("No compatible editable version × row × locale screenshot sets were found. \(issues.joined(separator: " "))")
        }

        // 180 renders is what timed out at ~130 s; 36 returned fine. Anything sizeable becomes a
        // job so the answer survives the client giving up on the request.
        let renders = Self.previewRenderCount(targets)
        let mode = try Self.decideMode(
            Self.resolveMode(args),
            units: renders,
            fitsSync: renders <= Self.syncPreviewRenderLimit,
            hardLimit: Self.hardPreviewRenderLimit,
            unitName: "renders"
        )

        // Every row, not the filtered set above: `buildPlan` resolves each target's row by id.
        let allRows = checkout.rows
        let stamp = checkout.documentStamp
        let projectName = checkout.projectName
        let executorIssues = issues

        let sync = screenshotSync
        jobOwnsCheckout = true
        return try await runJob(kind: .preview, totalUnits: renders, mode: mode, owning: checkout) { handle in
            handle.phase(.rendering)
            let plan = try await sync.buildPlan(
                appId: appId,
                targets: targets,
                rows: allRows,
                source: checkout,
                document: stamp,
                progress: { update in
                    handle.update {
                        $0.phase = update.stage == .rendering ? .rendering : .comparing
                        $0.completedUnits = update.completedRenders
                        $0.totalUnits = update.totalRenders
                        $0.currentLabel = update.label
                    }
                }
            )
            // Composited here rather than inside `update`: that closure is nonisolated and the
            // contact sheet is drawn with AppKit on the main actor.
            let contactSheet = MCPContactSheet.png(plan: plan)
            handle.update {
                $0.planId = plan.id
                $0.sets = plan.sets.map { MCPJobSetProgress(setId: $0.id) }
                $0.contactSheetPNG = contactSheet
            }
            // The two sets are disjoint: the executor's are collected while the targets are built,
            // so they have to be carried into the job; the plan's are what the build itself dropped.
            let result = ASCScreenshotPreviewResult(
                planId: plan.id,
                projectId: plan.projectId.uuidString,
                projectName: projectName,
                appId: plan.appId,
                expiresAt: ISO8601DateFormatter().string(from: plan.expiresAt),
                issues: executorIssues + plan.issues,
                sets: plan.sets.map { set in
                    .init(
                        setId: set.id,
                        remoteSetId: set.remoteSetId,
                        versionId: set.versionId,
                        version: set.versionLabel,
                        locale: set.localeLabel,
                        displayType: set.displayType.appStoreConnectValue,
                        status: !set.canApply ? "unavailable" : (set.isChanged ? "changed" : "unchanged"),
                        canApply: set.canApply && set.isChanged,
                        unchanged: set.unchangedCount,
                        moved: set.moveCount,
                        new: set.uploadCount,
                        removed: set.removalCount,
                        capacityFirstDeletions: set.capacityFirstDeletionCount,
                        issues: set.issues,
                        warnings: set.warnings
                    )
                }
            )
            return MCPJobOutcome(try MCPResultEncoding.value(result))
        }
    }

    func applyAppStoreScreenshotSync(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        let planId = try args.requiredString("plan_id")
        guard args.bool("confirm") == true else {
            throw MCPToolError.invalidArgument("confirm", "must be true")
        }
        guard let ids = args.stringArray("set_ids"), !ids.isEmpty else {
            throw MCPToolError.missingArgument("set_ids")
        }
        guard Set(ids).count == ids.count else {
            throw MCPToolError.invalidArgument("set_ids", "contains duplicates")
        }
        let setIds = Set(ids)
        let service = screenshotSync
        // The plan records the project it was rendered from; `validCachedPlan` rejects a mismatch.
        // Resolving the checkout here means the caller names that project too, so an apply can
        // never be aimed at a different app's artwork than the preview it came from.
        //
        // Optional, because a *successful* apply discards its plan — and the documented recovery is
        // to reissue the identical call. With no plan and no project_id there is nothing to check
        // against and nothing to render: the ledger answers, or `validCachedPlan` says planNotFound.
        let checkout = try await optionalCheckout(args, matching: service.plan(id: planId))
        // As above: ours until the job starts, the job's afterwards.
        var jobOwnsCheckout = false
        defer { if !jobOwnsCheckout { checkout?.dispose() } }
        // Sized from the plan when it is still cached. When it isn't, the ledger answers without
        // touching App Store Connect at all, so the estimate only has to be non-zero.
        let selected = service.plan(id: planId)?.sets.filter { setIds.contains($0.id) } ?? []
        let steps = selected.isEmpty
            ? ids.count
            : AppStoreConnectScreenshotSyncService.applyStepCount(selected)
        let mode = try Self.decideMode(
            Self.resolveMode(args),
            units: steps,
            // Tighter than the render limit on purpose: delivery polls up to 30 s per upload and
            // verification up to 30 s per set, so a small diff across many locales is still slow.
            fitsSync: steps <= Self.syncApplyStepLimit && ids.count <= Self.syncApplySetLimit,
            hardLimit: Self.hardApplyStepLimit,
            unitName: "upload steps"
        )
        let stamp = checkout?.documentStamp

        jobOwnsCheckout = true
        return try await runJob(kind: .apply, totalUnits: steps, mode: mode, owning: checkout) { handle in
            handle.update {
                $0.planId = planId
                $0.sets = ids.sorted().map { MCPJobSetProgress(setId: $0) }
                $0.phase = .revalidating
            }
            // Holds the plan's rendered bytes against the GUI wizard, which discards plans on this
            // same singleton and would otherwise delete them mid-apply.
            service.retainPlan(planId)
            defer { service.releasePlan(planId) }

            let result = try await service.apply(
                planId: planId,
                setIds: setIds,
                document: stamp,
                progress: { update in
                    handle.update {
                        if $0.phase == .revalidating { $0.phase = .uploading }
                        $0.completedUnits = update.completedSteps
                        $0.totalUnits = update.totalSteps
                        $0.currentLabel = update.currentLabel
                    }
                },
                setEvents: { event in
                    handle.update { job in
                        switch event {
                        case .didMutate:
                            job.didMutate = true
                        case .started(let setId):
                            if let index = job.sets.firstIndex(where: { $0.setId == setId }) {
                                job.sets[index].state = .inProgress
                            }
                        case .finished(let setResult):
                            if let index = job.sets.firstIndex(where: { $0.setId == setResult.id }) {
                                job.sets[index].state = setResult.alreadyApplied ? .alreadyApplied : .succeeded
                            }
                        }
                    }
                }
            )
            handle.update { job in
                job.didMutate = result.didMutate
                // The ledger short-circuit returns before emitting any progress, so a wholly
                // already-applied retry would otherwise finish at 0 of N and be downgraded to
                // `failed` — the exact opposite of the guarantee it exists to provide.
                if result.succeeded { job.completedUnits = job.totalUnits }
                for set in result.sets {
                    guard let index = job.sets.firstIndex(where: { $0.setId == set.id }) else { continue }
                    job.sets[index].state = switch set.state {
                    case .succeeded: .succeeded
                    case .alreadyApplied: .alreadyApplied
                    case .failed: .failed
                    case .notAttempted: .notAttempted
                    }
                }
            }
            let payload = ASCScreenshotApplyResult(
            planId: result.planId,
            succeeded: result.succeeded,
            didMutate: result.didMutate,
            attempted: result.sets.filter { !$0.alreadyApplied }.count,
            alreadyApplied: result.sets.filter(\.alreadyApplied).count,
            sets: result.sets.map { set in
                .init(
                    setId: set.id,
                    state: set.state.rawValue,
                    uploaded: set.uploaded,
                    removed: set.removed,
                    moved: set.moved,
                    preserved: set.preserved,
                    finalVerified: set.verified,
                    assetDeliveryStates: set.assetDeliveryStates,
                    nonCompleteAssets: set.nonCompleteAssets,
                    warnings: set.warnings,
                    error: set.error
                )
            }
            )
            // `apply` catches its own failures and returns a partial result, so "the body returned"
            // is not "the upload landed".
            return MCPJobOutcome(try MCPResultEncoding.value(payload), succeeded: result.succeeded)
        }
    }

    // MARK: - Helpers

    private var ascAPI: AppStoreConnectAPIService { .shared }

    private func requireASCConfigured() throws {
        guard AppStoreConnectCredentialsStore.shared.isConfigured else {
            throw MCPToolError.expected("App Store Connect is not configured — add your API key in Settings ▸ App Store Connect, or enable demo mode.")
        }
    }

    private func resolveASCAppId(_ args: MCPArguments, checkout: ProjectCheckout) throws -> String {
        if let explicit = args.string("app_id"), !explicit.isEmpty { return explicit }
        if let linked = checkout.ascAppId, !linked.isEmpty { return linked }
        throw MCPToolError.expected("No App Store Connect app id — pass app_id, or link \(checkout.projectName) to an app via the App Store Connect upload wizard.")
    }

    /// All versions to read (a specific one if requested, else every version).
    private func ascVersions(appId: String, requested versionId: String?) async throws -> [ASCAppStoreVersion] {
        let versions = try await ascAPI.listAppStoreVersions(appId: appId)
        if let versionId, !versionId.isEmpty {
            guard let match = versions.first(where: { $0.id == versionId }) else {
                throw MCPToolError.notFound("App Store version \(versionId)")
            }
            return [match]
        }
        guard !versions.isEmpty else {
            throw MCPToolError.expected("App \(appId) has no App Store versions")
        }
        return versions
    }

    /// Versions to write to: the requested one (as-is), else every editable version.
    private func resolveEditableTargets(appId: String, requested versionId: String?) async throws -> [ASCAppStoreVersion] {
        let versions = try await ascAPI.listAppStoreVersions(appId: appId)
        if let versionId, !versionId.isEmpty {
            guard let match = versions.first(where: { $0.id == versionId }) else {
                throw MCPToolError.notFound("App Store version \(versionId)")
            }
            return [match]
        }
        let editable = versions.filter { $0.isEditable }
        guard !editable.isEmpty else {
            throw MCPToolError.expected("App \(appId) has no editable App Store version (a version must be in an editable state such as Prepare for Submission)")
        }
        return editable
    }
}
#endif

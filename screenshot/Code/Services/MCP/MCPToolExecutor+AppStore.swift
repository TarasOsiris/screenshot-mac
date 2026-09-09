#if os(macOS)
import AppKit
import Foundation
import MCP

extension MCPToolExecutor {

    struct ASCScreenshotPreviewResult: Encodable {
        let planId: String
        /// Echoed so a caller can assert which project the plan was built from rather than
        /// trusting that the app happened to have the right one open.
        let projectId: String
        let projectName: String
        let appId: String
        let expiresAt: String
        let issues: [String]
        let sets: [SetResult]

        struct SetResult: Encodable {
            let setId: String
            let remoteSetId: String?
            let versionId: String
            let version: String
            let locale: String
            let displayType: String
            let status: String
            let canApply: Bool
            let unchanged: Int
            let moved: Int
            let new: Int
            let removed: Int
            let capacityFirstDeletions: Int
            let issues: [String]
            /// Non-blocking notices — most usefully "these have no App Store checksum, so they
            /// will be replaced rather than preserved", i.e. a preserve that is really a replace.
            let warnings: [String]
        }
    }

    struct ASCScreenshotApplyResult: Encodable {
        let planId: String
        let succeeded: Bool
        /// Whether anything was written to the live listing. The single most useful bit on a
        /// partial failure, and previously invisible to an agent.
        let didMutate: Bool
        let attempted: Int
        let alreadyApplied: Int
        let sets: [SetResult]

        struct SetResult: Encodable {
            let setId: String
            let state: String
            let uploaded: Int
            let removed: Int
            let moved: Int
            let preserved: Int
            let finalVerified: Bool
            let assetDeliveryStates: [String: Int]
            let nonCompleteAssets: [ASCScreenshotDeliveryProblem]
            let warnings: [String]
            let error: String?
        }
    }

    struct ASCMetadataResult: Encodable {
        let appId: String
        let versions: [VersionMeta]

        struct VersionMeta: Encodable {
            let versionId: String
            let platform: String?
            let versionString: String
            let appStoreState: String?
            let editable: Bool
            let locales: [LocaleDescription]
        }

        struct LocaleDescription: Encodable {
            let locale: String
            let description: String?
        }
    }

    struct ASCDescriptionUpdateResult: Encodable {
        let appId: String
        let results: [VersionResult]

        struct VersionResult: Encodable {
            let versionId: String
            let platform: String?
            let updated: [String]
            let skipped: [Skip]
        }

        struct Skip: Encodable {
            let locale: String
            let reason: String
        }
    }

    func getAppStoreMetadata(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        let appId = try await resolveASCAppId(fromAppIdOrProject: args)
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

        let appId = try await resolveASCAppId(fromAppIdOrProject: args)
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
        // In async mode `runJob` returns before the body has rendered anything, so disposing at
        // function exit would unregister the project's fonts out from under the render — the exact
        // silent system-face failure `ProjectFontScope` exists to prevent. Ownership transfers to
        // the job body once it is started.
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
            var claimedSetKeys = Set<String>()
            let remoteLocalizations = try await ascAPI.listLocalizations(versionId: version.id)
            let assigned = ASCLocaleMatcher.assign(appCodes: localeCodes, to: remoteLocalizations)
            for code in localeCodes where assigned[code, default: []].isEmpty {
                issues.append("Skipped \(version.id) · \(code): no unambiguous App Store localization mapping.")
            }
            for row in rows {
                guard !row.excludeFromAppStoreConnect else {
                    issues.append("Skipped row \(row.id.uuidString): excluded from App Store Connect.")
                    continue
                }
                guard let displayType = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight) else {
                    issues.append("Skipped row \(row.id.uuidString): its \(Int(row.templateWidth))×\(Int(row.templateHeight)) display type is ambiguous or unsupported.")
                    continue
                }
                guard displayType.accepts(platform: version.attributes.ascPlatform) else {
                    issues.append("Skipped row \(row.id.uuidString) for version \(version.id): \(displayType.label) is incompatible with \(version.attributes.displayPlatform ?? "the version platform").")
                    continue
                }
                let candidates = localeCodes.flatMap { code in
                    assigned[code, default: []].map {
                        ASCUploadLocalization(id: $0.id, label: $0.attributes.locale, localeCode: code)
                    }
                }
                let localizations = candidates.filter { localization in
                    let key = "\(localization.id)|\(displayType.appStoreConnectValue)"
                    guard !claimedSetKeys.contains(key) else {
                        issues.append("Skipped row \(row.id.uuidString) · \(localization.label): another row already targets this display-type set.")
                        return false
                    }
                    claimedSetKeys.insert(key)
                    return true
                }
                guard !localizations.isEmpty else { continue }
                targets.append(ASCUploadTarget(
                    versionId: version.id,
                    versionLabel: "\(version.attributes.displayPlatform ?? "App Store") · Version \(version.attributes.versionString)",
                    rowId: row.id,
                    rowLabel: row.label.isEmpty ? "Row" : row.label,
                    rowSize: row.templateSize,
                    displayType: displayType,
                    localizations: localizations,
                    templateCount: row.templates.count
                ))
            }
        }
        guard !targets.isEmpty else {
            throw MCPToolError.failed("No compatible editable version × row × locale screenshot sets were found. \(issues.joined(separator: " "))")
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

        jobOwnsCheckout = true
        let sync = screenshotSync
        return try await runJob(kind: .preview, totalUnits: renders, mode: mode) { handle in
            defer { checkout.dispose() }
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
            let contactSheet = Self.makeScreenshotContactSheet(plan: plan)
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
        return try await runJob(kind: .apply, totalUnits: steps, mode: mode) { handle in
            defer { checkout?.dispose() }
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
            throw MCPToolError.failed("App Store Connect is not configured — add your API key in Settings ▸ App Store Connect, or enable demo mode.")
        }
    }

    private func resolveASCAppId(_ args: MCPArguments, checkout: ProjectCheckout) throws -> String {
        if let explicit = args.string("app_id"), !explicit.isEmpty { return explicit }
        if let linked = checkout.ascAppId, !linked.isEmpty { return linked }
        throw MCPToolError.failed("No App Store Connect app id — pass app_id, or link \(checkout.projectName) to an app via the App Store Connect upload wizard.")
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
            throw MCPToolError.failed("App \(appId) has no App Store versions")
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
            throw MCPToolError.failed("App \(appId) has no editable App Store version (a version must be in an editable state such as Prepare for Submission)")
        }
        return editable
    }

    private static func makeScreenshotContactSheet(plan: ASCScreenshotSyncPlan) -> Data? {
        let previews = plan.sets.flatMap(\.proposedAssets).compactMap { $0.localAsset?.previewData }.prefix(20)
        let images = previews.compactMap { NSImage(data: $0) }
        guard !images.isEmpty else { return nil }
        let columns = min(5, images.count)
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let cell = CGSize(width: 150, height: 210)
        let canvasSize = CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = index / columns
            let cellRect = CGRect(
                x: CGFloat(column) * cell.width + 8,
                y: canvasSize.height - CGFloat(row + 1) * cell.height + 8,
                width: cell.width - 16,
                height: cell.height - 16
            )
            let scale = min(cellRect.width / image.size.width, cellRect.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: cellRect.midX - size.width / 2, y: cellRect.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

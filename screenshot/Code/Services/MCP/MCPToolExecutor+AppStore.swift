#if os(macOS)
import AppKit
import Foundation
import MCP

extension MCPToolExecutor {

    struct ASCScreenshotPreviewResult: Encodable {
        let planId: String
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
        }
    }

    struct ASCScreenshotApplyResult: Encodable {
        let planId: String
        let succeeded: Bool
        let sets: [SetResult]

        struct SetResult: Encodable {
            let setId: String
            let operations: [String]
            let finalVerified: Bool
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
        let appId = try resolveASCAppId(args)
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

        let appId = try resolveASCAppId(args)
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
        guard state.activeProjectId != nil else { throw MCPToolError.failed("No active project") }
        let appId = try resolveASCAppId(args)
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
        let projectLocaleCodes = Set(state.localeState.locales.map(\.code))
        let unknownLocales = requestedLocaleCodes.subtracting(projectLocaleCodes)
        guard unknownLocales.isEmpty else {
            throw MCPToolError.invalidArgument("locale_codes", "not in the active project: \(unknownLocales.sorted().joined(separator: ", "))")
        }
        let localeCodes = requestedLocaleCodes.isEmpty
            ? state.localeState.locales.map(\.code)
            : state.localeState.locales.map(\.code).filter(requestedLocaleCodes.contains)

        var issues: [String] = []
        let rows = state.rows.filter { row in
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

        let plan = try await AppStoreConnectScreenshotSyncService.shared.buildPlan(
            appId: appId,
            targets: targets,
            appState: state
        )
        let result = ASCScreenshotPreviewResult(
            planId: plan.id,
            expiresAt: ISO8601DateFormatter().string(from: plan.expiresAt),
            issues: issues + plan.issues,
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
                    issues: set.issues
                )
            }
        )
        if let contactSheet = makeScreenshotContactSheet(plan: plan) {
            return try MCPResultEncoding.result(result, pngImage: contactSheet)
        }
        return try MCPResultEncoding.result(result)
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
        let result = try await AppStoreConnectScreenshotSyncService.shared.apply(
            planId: planId,
            setIds: Set(ids),
            appState: state
        )
        return try MCPResultEncoding.result(ASCScreenshotApplyResult(
            planId: result.planId,
            succeeded: result.succeeded,
            sets: result.sets.map { set in
                var operations: [String] = []
                if set.preserved > 0 { operations.append("preserved \(set.preserved)") }
                if set.uploaded > 0 { operations.append("uploaded \(set.uploaded)") }
                if set.removed > 0 { operations.append("removed \(set.removed)") }
                if set.moved > 0 { operations.append("moved \(set.moved)") }
                return .init(
                    setId: set.id,
                    operations: operations,
                    finalVerified: set.verified,
                    error: set.error
                )
            }
        ))
    }

    // MARK: - Helpers

    private var ascAPI: AppStoreConnectAPIService { .shared }

    private func requireASCConfigured() throws {
        guard AppStoreConnectCredentialsStore.shared.isConfigured else {
            throw MCPToolError.failed("App Store Connect is not configured — add your API key in Settings ▸ App Store Connect, or enable demo mode.")
        }
    }

    private func resolveASCAppId(_ args: MCPArguments) throws -> String {
        if let explicit = args.string("app_id"), !explicit.isEmpty { return explicit }
        if let linked = state.activeProject?.ascAppId, !linked.isEmpty { return linked }
        throw MCPToolError.failed("No App Store Connect app id — pass app_id, or link the active project to an app via the App Store Connect upload wizard.")
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

    private func makeScreenshotContactSheet(plan: ASCScreenshotSyncPlan) -> Data? {
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

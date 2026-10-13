#if os(macOS)
import Foundation
import MCP

struct MCPPlayPlan: Encodable {
    let packageName: String?
    let rows: [Row]
    let issues: [Issue]
    /// Screenshots the upload would publish, every row × language.
    let screenshots: Int

    struct Row: Encodable {
        let rowId: String
        let label: String
        let size: String
        let imageType: String
        let screenshots: Int
        let languages: [String]
        let included: Bool
    }

    struct Issue: Encodable {
        let severity: String
        let message: String
        let hint: String?
    }
}

struct MCPPlayUploadResult: Encodable {
    let packageName: String
    let screenshots: Int
    let sentForReview: Bool
}

extension MCPToolExecutor {

    private struct PlayPlan {
        let packageName: String
        let isDemoMode: Bool
        let plans: [GPRowPlan]
        let targets: [GPUploadTarget]
        let issues: [UploadIssue]

        var screenshotCount: Int { GPUploadCounts(targets: targets).screenshots }
    }

    /// The wizard's own plan for the project's Original rows, narrowed by `row_ids` and `locale_codes`.
    private func playPlan(_ args: MCPArguments, checkout: ProjectCheckout) throws -> PlayPlan {
        let credentials = GooglePlayCredentialsStore.shared
        guard credentials.isConfigured else {
            throw MCPToolError.expected("Google Play is not configured — add a service account in Settings ▸ Google Play, or enable demo mode.")
        }
        let originals = checkout.rows.inVariant(nil)
        var plans = GPUploadFlowModel.rowPlans(rows: originals, localeState: checkout.localeState)
        if let rowIds = try requireRowIds(args, among: originals) {
            for i in plans.indices { plans[i].isEnabled = rowIds.contains(plans[i].id) }
        }
        if let imageType = try args.enumValue("image_type", GPImageType.self) {
            for i in plans.indices where plans[i].isEnabled { plans[i].selectedAssetType = imageType }
        }
        if let codes = args.stringArray("locale_codes") {
            if let missing = Set(codes).subtracting(checkout.localeState.locales.map(\.code)).first {
                throw MCPToolError.notFound("Locale \(missing)")
            }
            for i in plans.indices {
                for j in plans[i].localeTargets.indices {
                    plans[i].localeTargets[j].isEnabled = codes.contains(plans[i].localeTargets[j].appLocaleCode)
                }
            }
        }
        // Trimmed like the wizard's field.
        let packageName = (args.string("package_name") ?? checkout.googlePlayPackageName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PlayPlan(
            packageName: packageName,
            isDemoMode: credentials.isDemoMode,
            plans: plans,
            targets: GPUploadFlowModel.uploadTargets(from: plans),
            issues: GooglePlayUploadValidator.validate(packageName: packageName, plans: plans, isDemoMode: credentials.isDemoMode)
        )
    }

    func previewPlayUpload(_ args: MCPArguments) async throws -> CallTool.Result {
        let checkout = try await requireCheckout(args)
        defer { checkout.dispose() }
        let plan = try playPlan(args, checkout: checkout)
        let languagesByRow = Dictionary(uniqueKeysWithValues: plan.targets.map { ($0.rowId, $0.languages.map(\.playCode)) })
        return try MCPResultEncoding.result(MCPPlayPlan(
            packageName: plan.packageName.isEmpty ? nil : plan.packageName,
            rows: plan.plans.map { row in
                MCPPlayPlan.Row(
                    rowId: row.id.uuidString,
                    label: row.displayLabel,
                    size: row.sizeLabel,
                    imageType: row.selectedAssetType.rawValue,
                    screenshots: row.templateCount,
                    languages: languagesByRow[row.id] ?? [],
                    included: languagesByRow[row.id] != nil
                )
            },
            issues: plan.issues.map { MCPPlayPlan.Issue(severity: "\($0.severity)", message: $0.message, hint: $0.hint) },
            screenshots: plan.screenshotCount
        ))
    }

    func uploadPlayScreenshots(_ args: MCPArguments) async throws -> CallTool.Result {
        guard args.bool("confirm") == true else {
            throw MCPToolError.invalidArgument("confirm", "must be true: this replaces the listing's screenshots on Google Play")
        }
        let checkout = try await requireCheckout(args)
        var jobOwnsCheckout = false
        defer { if !jobOwnsCheckout { checkout.dispose() } }
        let plan = try playPlan(args, checkout: checkout)
        let errors = plan.issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw MCPToolError.expected("Fix these before uploading: \(errors.map(\.message).joined(separator: " "))")
        }
        guard !plan.targets.isEmpty else {
            throw MCPToolError.expected("Nothing to upload — no included row has a language Google Play lists.")
        }
        let mode = try Self.decideMode(
            Self.resolveMode(args),
            units: plan.screenshotCount,
            fitsSync: plan.screenshotCount <= Self.syncPlayUploadLimit,
            hardLimit: Self.hardPlayUploadLimit,
            unitName: "screenshots"
        )
        let sendForReview = args.bool("send_for_review") ?? false
        let rows = checkout.rows
        let projectId = checkout.projectId
        jobOwnsCheckout = true
        return try await runJob(kind: .playUpload, totalUnits: plan.screenshotCount, mode: mode, owning: checkout) { [state] handle in
            handle.phase(.uploading)
            let sent = try await GooglePlayUploadService.shared.upload(
                packageName: plan.packageName,
                targets: plan.targets,
                sendForReview: sendForReview,
                rows: rows,
                source: checkout,
                progress: { progress in
                    handle.update {
                        $0.completedUnits = progress.completedSteps
                        $0.totalUnits = progress.totalSteps
                        $0.currentLabel = progress.currentLabel
                    }
                }
            )
            handle.update { $0.didMutate = true }
            // As the wizard: demo mode must not link a real project to the demo (or an empty) package.
            if !plan.isDemoMode, !plan.packageName.isEmpty {
                state.setGooglePlayPackageName(plan.packageName, forProject: projectId)
            }
            return MCPJobOutcome(try MCPResultEncoding.value(MCPPlayUploadResult(
                packageName: plan.packageName, screenshots: plan.screenshotCount, sentForReview: sent
            )))
        }
    }
}
#endif

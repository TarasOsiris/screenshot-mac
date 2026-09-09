import CryptoKit
import Foundation
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ASCScreenshotDiffStatus: String, Codable, CaseIterable, Sendable {
    case unchanged
    case moved
    case new
    case removed
}

struct ASCScreenshotLocalAsset: Identifiable, Sendable {
    let id: String
    let index: Int
    let fileName: String
    let fileURL: URL
    let checksum: String
    let width: Int
    let height: Int
    let previewData: Data
}

struct ASCScreenshotRemoteAsset: Identifiable, Sendable {
    let id: String
    let index: Int
    let fileName: String
    let checksum: String
    let width: Int?
    let height: Int?
    let previewData: Data?
    let previewFileURL: URL?
    let previewError: String?
}

struct ASCScreenshotDiffItem: Identifiable, Sendable {
    let id: String
    let status: ASCScreenshotDiffStatus
    let checksum: String
    let remoteId: String?
    let originalIndex: Int?
    let proposedIndex: Int?
    let localAsset: ASCScreenshotLocalAsset?
    let remoteAsset: ASCScreenshotRemoteAsset?
}

struct ASCScreenshotSetDiff: Identifiable, Sendable {
    let id: String
    let versionId: String
    let versionLabel: String
    let rowId: UUID
    /// User-written row name — safe in the UI, must never reach a breadcrumb.
    let rowLabel: String
    let localizationId: String
    let localeCode: String
    let localeLabel: String
    let displayType: ASCDisplayType
    let remoteSetId: String?
    let items: [ASCScreenshotDiffItem]
    let remoteFingerprint: String
    /// Blocking problems — any entry here makes the set unappliable.
    let issues: [String]
    /// Non-blocking notices shown alongside the diff; they never gate `canApply`.
    let warnings: [String]
    let canApply: Bool

    var changedCount: Int { items.lazy.filter { $0.status != .unchanged }.count }
    var isChanged: Bool { changedCount > 0 }
    var uploadCount: Int { items.lazy.filter { $0.status == .new }.count }
    var removalCount: Int { items.lazy.filter { $0.status == .removed }.count }
    var moveCount: Int { items.lazy.filter { $0.status == .moved }.count }
    var unchangedCount: Int { items.lazy.filter { $0.status == .unchanged }.count }
    var capacityFirstDeletionCount: Int {
        let remoteCount = items.lazy.filter { $0.remoteAsset != nil }.count
        return max(0, remoteCount + uploadCount - 10)
    }

    var currentAssets: [ASCScreenshotDiffItem] {
        items.filter { $0.remoteAsset != nil }.sorted { ($0.originalIndex ?? .max) < ($1.originalIndex ?? .max) }
    }

    var proposedAssets: [ASCScreenshotDiffItem] {
        items.filter { $0.localAsset != nil }.sorted { ($0.proposedIndex ?? .max) < ($1.proposedIndex ?? .max) }
    }
}

struct ASCScreenshotSyncPlan: Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let expiresAt: Date
    let projectId: UUID
    let projectModifiedAt: Date?
    let appId: String
    let sets: [ASCScreenshotSetDiff]
    let issues: [String]
    let directory: URL

    var changedSets: [ASCScreenshotSetDiff] { sets.filter(\.isChanged) }
}

nonisolated struct ASCScreenshotSetSyncResult: Identifiable, Sendable {
    nonisolated enum State: String, Sendable {
        case succeeded
        /// Applied by an earlier run of this same plan, and deliberately not touched again.
        case alreadyApplied = "already_applied"
        case failed
        /// An earlier set in the same apply failed first, so this one was never started.
        case notAttempted = "not_attempted"
    }

    let id: String
    let uploaded: Int
    let removed: Int
    let moved: Int
    let preserved: Int
    let verified: Bool
    let error: String?
    let state: State
    /// `["COMPLETE": 9]` — a histogram, because nine identical strings per set × 64 sets is
    /// unreadable and the interesting case is the one that isn't COMPLETE.
    let assetDeliveryStates: [String: Int]
    /// The escape hatch when the histogram isn't all COMPLETE.
    let nonCompleteAssets: [ASCScreenshotDeliveryProblem]
    /// Carried from the diff: notices such as "these have no App Store checksum, so they will be
    /// replaced rather than preserved". Non-blocking, and previously dropped before reaching MCP.
    let warnings: [String]

    var alreadyApplied: Bool { state == .alreadyApplied }

    init(
        id: String,
        uploaded: Int,
        removed: Int,
        moved: Int,
        preserved: Int,
        verified: Bool,
        error: String?,
        state: State? = nil,
        deliveries: [ASCScreenshotDeliveryOutcome] = [],
        warnings: [String] = []
    ) {
        self.id = id
        self.uploaded = uploaded
        self.removed = removed
        self.moved = moved
        self.preserved = preserved
        self.verified = verified
        self.error = error
        self.state = state ?? (error == nil && verified ? .succeeded : .failed)
        self.assetDeliveryStates = deliveries.reduce(into: [:]) { $0[$1.state, default: 0] += 1 }
        self.nonCompleteAssets = deliveries.filter { !$0.isComplete }.map {
            ASCScreenshotDeliveryProblem(screenshotId: $0.screenshotId, state: $0.state, messages: $0.messages)
        }
        self.warnings = warnings
    }
}

nonisolated struct ASCScreenshotSyncResult: Sendable {
    let planId: String
    let sets: [ASCScreenshotSetSyncResult]
    /// Whether this run wrote anything to the live App Store listing. The difference between
    /// "nothing was touched" and "your listing is now half-updated".
    let didMutate: Bool

    init(planId: String, sets: [ASCScreenshotSetSyncResult], didMutate: Bool = false) {
        self.planId = planId
        self.sets = sets
        self.didMutate = didMutate
    }

    var succeeded: Bool { sets.allSatisfy { $0.error == nil && $0.verified } }
}

enum ASCScreenshotSyncError: LocalizedError {
    case planNotFound
    case planExpired
    case staleProject
    case staleRemote(set: String)
    case noSetsSelected
    case applyInProgress
    case partiallyAppliedSet(set: String)
    case invalidPlan(String)
    case unreadableImages(rowLabel: String, localeLabel: String, fileNames: [String])

    var errorDescription: String? {
        switch self {
        case .planNotFound:
            String(localized: "The reviewed screenshot plan is no longer available. Refresh it and try again.")
        case .planExpired:
            String(localized: "The reviewed screenshot plan expired. Refresh it before syncing.")
        case .staleProject:
            String(localized: "The project changed after the preview was created. Refresh the review before syncing.")
        case .staleRemote(let set):
            String(localized: "The App Store screenshots for \(set) changed after review. Refresh before syncing.")
        case .noSetsSelected:
            String(localized: "Select at least one changed screenshot set.")
        case .applyInProgress:
            String(localized: "Another screenshot sync is already running. Wait for it to finish, or cancel it first.")
        case .partiallyAppliedSet(let set):
            String(localized: "\(set) was partially uploaded before the last sync stopped. Refresh the review to re-diff this set — the sets that finished will not be uploaded again.")
        case .invalidPlan(let message):
            message
        case .unreadableImages(let rowLabel, let localeLabel, let fileNames):
            String(localized: "\(rowLabel) · \(localeLabel) uses \(fileNames.count) image file(s) that could not be read, so the screenshots would upload with missing content. Re-add the affected images, then try again.")
        }
    }
}

@MainActor
final class AppStoreConnectScreenshotSyncService {
    static let shared = AppStoreConnectScreenshotSyncService()
    static let planLifetime: TimeInterval = 15 * 60

    private struct CachedPlan {
        let plan: ASCScreenshotSyncPlan
        let targetsBySetId: [String: ASCUploadTarget]
        let localizationsBySetId: [String: ASCUploadLocalization]
    }

    private let api: any ASCScreenshotSyncAPI
    private var cache: [String: CachedPlan] = [:]
    /// Sets that reached a *verified* terminal state, keyed plan → set. Deliberately outlives
    /// `discardPlan`: a retry of a plan whose rendered bytes are already gone must still be able
    /// to answer "that one landed" rather than uploading it a second time.
    private var applied: [String: [String: ASCScreenshotSetSyncResult]] = [:]
    private var ledgerExpiry: [String: Date] = [:]
    /// Sets an apply reached but did not verify — a half-mutated remote set. Distinguishes
    /// "someone else edited your listing" from "we stopped halfway through this one".
    private var attempted: [String: Set<String>] = [:]
    /// Plans a running job is holding. The GUI wizard discards plans on the same singleton, and
    /// that deletes the temp directory of rendered bytes a resume needs.
    private var retained: Set<String> = []
    private var pendingDiscard: Set<String> = []
    /// One apply at a time. Two applies racing on the same version × locale × display type would
    /// both write the same App Store set — the only true double-upload race left.
    private var isApplying = false

    /// Read through a closure rather than the singleton directly: demo mode is a process-global
    /// that other suites toggle, and a test of the idempotency ledger must not be at their mercy.
    private let isDemoMode: () -> Bool

    init(
        api: (any ASCScreenshotSyncAPI)? = nil,
        isDemoMode: @escaping () -> Bool = { AppStoreConnectCredentialsStore.shared.isDemoMode }
    ) {
        self.api = api ?? AppStoreConnectAPIService.shared
        self.isDemoMode = isDemoMode
    }

    func plan(id: String) -> ASCScreenshotSyncPlan? {
        purgeExpiredPlans()
        return cache[id]?.plan
    }

    /// `needsPreviews` costs one 420 px download per remote screenshot and buys exactly one thing:
    /// the review screen's side-by-side comparison. It defaults to off because every other consumer
    /// — direct upload, MCP — would pay for thumbnails it never draws, and forgetting the flag then
    /// shows up only as latency. Checksum matching reads `sourceFileChecksum` from metadata, so the
    /// previews change no decision.
    func buildPlan(
        appId: String,
        targets: [ASCUploadTarget],
        rows: [ScreenshotRow],
        source: some RowRenderSource,
        document: DocumentStamp?,
        strategy: ASCSyncStrategy = .reconcile,
        needsPreviews: Bool = false,
        progress: @escaping (ASCSyncBuildProgress) -> Void = { _ in }
    ) async throws -> ASCScreenshotSyncPlan {
        guard let document else {
            throw ASCScreenshotSyncError.invalidPlan(String(localized: "Open a project before reviewing screenshots."))
        }
        guard !targets.isEmpty else { throw ASCScreenshotSyncError.noSetsSelected }

        purgeExpiredPlans()
        let planId = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotBro-ASCSync", isDirectory: true)
            .appendingPathComponent(planId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A target whose row is gone — the document changed while this build awaited App Store
        // Connect — is not work, so it must not be in the denominator either. `previewRenderCount`
        // sizes the job before this is known; the first callback below corrects it.
        let rowsById = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let renderable = targets.filter { rowsById[$0.rowId] != nil }
        let droppedIssues = targets.filter { rowsById[$0.rowId] == nil }.map {
            String(localized: "Skipped \($0.rowLabel) · \($0.versionLabel): its row is no longer in the project.")
        }
        let totalRenders = renderable.reduce(0) { $0 + $1.templateCount * $1.localizations.count }
        var completedRenders = 0
        var diffs: [ASCScreenshotSetDiff] = []
        var targetsBySetId: [String: ASCUploadTarget] = [:]
        var localizationsBySetId: [String: ASCUploadLocalization] = [:]
        var imageCache: [String: NSImage] = [:]
        CrashReportingService.breadcrumb(.upload, "ASC plan build started", data: [
            "targets": targets.count,
            "localizations": targets.reduce(0) { $0 + $1.localizations.count },
            "strategy": strategy.rawValue,
            "previews": needsPreviews,
        ])
        let buildSpan = PerfSignpost.begin("ASCSync.buildPlan")
        defer { PerfSignpost.end("ASCSync.buildPlan", buildSpan) }

        // Publishes the real denominator before any work, so an observer sized from the estimate is
        // corrected even when every target turned out to be unrenderable.
        progress(.init(stage: .comparing, completedRenders: 0, totalRenders: totalRenders, label: ""))

        do {
            for target in renderable {
                guard let row = rowsById[target.rowId] else { continue }

                // Backgrounds are locale-independent, so the context (and its blur-only
                // precomposed strip) is built once and reused across every localization.
                var context: RowRenderContext?

                for localization in target.localizations {
                    try Task.checkCancellation()
                    let diffId = Self.diffSetId(target: target, localization: localization)
                    guard targetsBySetId[diffId] == nil else {
                        throw ASCScreenshotSyncError.invalidPlan(
                            String(localized: "More than one row targets \(target.versionLabel) · \(localization.label) · \(target.displayType.label). Choose one row for this set.")
                        )
                    }
                    let label = "\(target.rowLabel) · \(localization.label)"
                    progress(.init(stage: .rendering, completedRenders: completedRenders, totalRenders: totalRenders, label: label))
                    let rowContext = RowRenderContext.load(
                        row: row,
                        localeCode: localization.localeCode,
                        from: source,
                        label: "asc sync row",
                        cache: &imageCache,
                        reusing: context
                    )
                    context = rowContext
                    // Rendering degrades silently to a hole, so refuse to ship a screenshot
                    // whose image the model references but disk can't produce.
                    if !rowContext.unrenderableImageFileNames.isEmpty {
                        throw ASCScreenshotSyncError.unreadableImages(
                            rowLabel: target.rowLabel,
                            localeLabel: localization.label,
                            fileNames: rowContext.unrenderableImageFileNames
                        )
                    }
                    let renderSpan = PerfSignpost.begin("ASCSync.renderSet")
                    let localAssets = try await renderAssets(
                        context: rowContext,
                        target: target,
                        localization: localization,
                        directory: directory.appendingPathComponent(Self.safeFileName(diffId), isDirectory: true)
                    )
                    PerfSignpost.end("ASCSync.renderSet", renderSpan)
                    completedRenders += target.templateCount
                    progress(.init(stage: .comparing, completedRenders: completedRenders, totalRenders: totalRenders, label: label))
                    let remotePreviewDirectory = directory
                        .appendingPathComponent("remote-previews", isDirectory: true)
                        .appendingPathComponent(Self.safeFileName(diffId), isDirectory: true)
                    let fetchSpan = PerfSignpost.begin("ASCSync.fetchRemoteSet")
                    let remote = isDemoMode()
                        // Demo previews are copied from local files, not downloaded, so there is
                        // nothing to save by skipping them.
                        ? try await demoRemoteSet(
                            from: localAssets,
                            diffId: diffId,
                            previewDirectory: remotePreviewDirectory
                        )
                        : try await fetchRemoteSet(
                            localizationId: localization.id,
                            displayType: target.displayType,
                            previewMaxDimension: needsPreviews ? 420 : nil,
                            previewDirectory: needsPreviews ? remotePreviewDirectory : nil
                        )
                    PerfSignpost.end("ASCSync.fetchRemoteSet", fetchSpan)
                    let diff = Self.makeDiff(
                        id: diffId,
                        target: target,
                        localization: localization,
                        localAssets: localAssets,
                        remoteSetId: remote.setId,
                        remoteAssets: remote.assets,
                        strategy: strategy,
                        warnings: remote.warnings
                    )
                    diffs.append(diff)
                    targetsBySetId[diffId] = target
                    localizationsBySetId[diffId] = localization
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        let now = Date()
        let plan = ASCScreenshotSyncPlan(
            id: planId,
            createdAt: now,
            expiresAt: now.addingTimeInterval(Self.planLifetime),
            projectId: document.projectId,
            projectModifiedAt: document.modifiedAt,
            appId: appId,
            sets: diffs,
            // Otherwise a dropped target is only visible as a set the caller asked for and didn't get.
            issues: droppedIssues,
            directory: directory
        )
        cache[planId] = CachedPlan(
            plan: plan,
            targetsBySetId: targetsBySetId,
            localizationsBySetId: localizationsBySetId
        )
        return plan
    }

    func apply(
        planId: String,
        setIds: Set<String>,
        document: DocumentStamp?,
        progress: @escaping (UploadProgress) -> Void = { _ in },
        setEvents: @escaping (ASCSyncApplySetEvent) -> Void = { _ in }
    ) async throws -> ASCScreenshotSyncResult {
        guard !setIds.isEmpty else { throw ASCScreenshotSyncError.noSetsSelected }
        // `buildPlan` is not the only entry point, so it cannot be the only reaper.
        purgeExpiredPlans()

        // The ledger is consulted before the plan, because a plan every one of whose sets already
        // landed may itself have been discarded — and answering "already applied" without needing
        // the plan is exactly what makes a retry after a client timeout safe.
        let ledger = applied[planId] ?? [:]
        if !ledger.isEmpty, setIds.allSatisfy({ ledger[$0] != nil }) {
            return ASCScreenshotSyncResult(
                planId: planId,
                sets: setIds.sorted().compactMap { ledger[$0] },
                didMutate: false
            )
        }

        guard !isApplying else { throw ASCScreenshotSyncError.applyInProgress }
        isApplying = true
        defer { isApplying = false }

        let cached = try validCachedPlan(id: planId, document: document)
        let selected = cached.plan.sets.filter { setIds.contains($0.id) }
        guard selected.count == setIds.count, selected.allSatisfy({ $0.isChanged && $0.canApply }) else {
            throw ASCScreenshotSyncError.invalidPlan(String(localized: "One or more selected screenshot sets cannot be applied."))
        }
        // Everything past here works on the sets that have NOT already landed. Revalidating a
        // ledgered set would fail by design: its remote fingerprint no longer matches the plan
        // precisely because we uploaded to it.
        let remaining = selected.filter { ledger[$0.id] == nil }
        guard !remaining.isEmpty else {
            return ASCScreenshotSyncResult(planId: planId, sets: selected.compactMap { ledger[$0.id] }, didMutate: false)
        }

        // Revalidate every not-yet-applied set and its cached local bytes before the first write.
        for diff in remaining {
            try Task.checkCancellation()
            for local in diff.proposedAssets.compactMap(\.localAsset) {
                guard let checksum = try? await Self.fileChecksum(at: local.fileURL),
                      checksum == local.checksum else {
                    throw ASCScreenshotSyncError.invalidPlan(
                        String(localized: "The cached reviewed bytes for \(local.fileName) changed or are unavailable. Refresh before syncing.")
                    )
                }
            }
            if !isDemoMode() {
                let snapshot = try await fetchRemoteSet(
                    localizationId: diff.localizationId,
                    displayType: diff.displayType,
                    previewMaxDimension: nil,
                    previewDirectory: nil
                )
                guard Self.remoteFingerprint(snapshot.assets) == diff.remoteFingerprint,
                      snapshot.setId == diff.remoteSetId else {
                    // We stopped halfway through this set on an earlier run, so *we* are why the
                    // remote no longer matches. Saying "someone changed your listing" would be
                    // both wrong and unactionable.
                    if attempted[planId]?.contains(diff.id) == true {
                        throw ASCScreenshotSyncError.partiallyAppliedSet(set: Self.label(for: diff))
                    }
                    throw ASCScreenshotSyncError.staleRemote(set: Self.label(for: diff))
                }
            }
        }

        // Revalidation suspends; perform the project/expiry guard once more immediately before
        // the first App Store mutation.
        _ = try validCachedPlan(id: planId, document: document)

        var results: [ASCScreenshotSetSyncResult] = selected.compactMap { ledger[$0.id] }
        var activeSet: ASCScreenshotSetDiff?
        // Once a write lands the plan's remote fingerprint is stale, so it must be discarded.
        // Before that it is still valid and worth keeping so a cancel or blip can retry cheaply.
        var didMutate = false
        // Reported the moment it first becomes true: a poller asking "is my listing half-updated?"
        // must not have to wait for the call to return to find out.
        func markMutated() {
            guard !didMutate else { return }
            didMutate = true
            setEvents(.didMutate)
        }
        let total = Self.applyStepCount(remaining)
        var completed = 0
        progress(UploadProgress(totalSteps: total, completedSteps: 0, currentLabel: "Starting screenshot sync…"))
        // Counts and ASC display types only — set labels are built from row labels, which are
        // user content and must never leave the device.
        CrashReportingService.breadcrumb(.upload, "ASC apply started", data: [
            "sets": remaining.count,
            "already_applied": results.count,
            "steps": total,
        ])

        do {
            for diff in remaining {
                try Task.checkCancellation()
                activeSet = diff
                setEvents(.started(setId: diff.id))
                // Recorded before the first write so a later resume can tell a set we half-applied
                // from one a third party changed.
                attempted[planId, default: []].insert(diff.id)
                CrashReportingService.breadcrumb(.upload, "ASC applying set", data: [
                    "display_type": diff.displayType.appStoreConnectValue,
                    "uploads": diff.uploadCount,
                    "removals": diff.removalCount,
                    "moves": diff.moveCount,
                    "new_set": diff.remoteSetId == nil,
                ])
                guard cached.targetsBySetId[diff.id] != nil,
                      cached.localizationsBySetId[diff.id] != nil else {
                    throw ASCScreenshotSyncError.invalidPlan(String(localized: "The reviewed screenshot set is incomplete."))
                }
                let setId: String
                if let existing = diff.remoteSetId {
                    setId = existing
                } else {
                    do {
                        setId = try await api.createScreenshotSet(
                            localizationId: diff.localizationId,
                            displayType: diff.displayType.appStoreConnectValue
                        ).id
                        markMutated()
                    } catch {
                        throw Self.screenshotSetCreationError(error, diff: diff)
                    }
                }
                let removed = diff.items.filter { $0.status == .removed }.sorted { ($0.originalIndex ?? 0) < ($1.originalIndex ?? 0) }
                var deletedIds = Set<String>()
                for item in removed.prefix(diff.capacityFirstDeletionCount) {
                    guard let id = item.remoteId else { continue }
                    progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Freeing capacity · \(Self.label(for: diff))"))
                    markMutated()
                    try await api.deleteScreenshot(id: id)
                    deletedIds.insert(id)
                    completed += 1
                }

                var finalIdsByLocalIndex: [Int: String] = [:]
                var deliveries: [ASCScreenshotDeliveryOutcome] = []
                // Everything the plan is keeping, so a reserve retry's cleanup can tell the
                // reservation it just orphaned apart from a screenshot that belongs here.
                let plannedRemoteIds = Set(diff.items.compactMap(\.remoteId))
                for item in diff.proposedAssets {
                    guard let local = item.localAsset, let proposedIndex = item.proposedIndex else { continue }
                    if let remoteId = item.remoteId {
                        // Already live on the store, so its state is known without another GET.
                        finalIdsByLocalIndex[proposedIndex] = remoteId
                        deliveries.append(.assumedComplete(remoteId))
                    } else {
                        progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Uploading \(local.fileName)"))
                        let data = try Data(contentsOf: local.fileURL)
                        markMutated()
                        let uploaded = try await upload(
                            data: data,
                            fileName: local.fileName,
                            setId: setId,
                            checksum: local.checksum,
                            protectedRemoteIds: plannedRemoteIds.union(finalIdsByLocalIndex.values)
                        )
                        finalIdsByLocalIndex[proposedIndex] = uploaded.id
                        deliveries.append(uploaded.delivery)
                        completed += 1
                    }
                }

                for item in removed where !deletedIds.contains(item.remoteId ?? "") {
                    guard let id = item.remoteId else { continue }
                    progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Removing \(item.remoteAsset?.fileName ?? "old screenshot")"))
                    markMutated()
                    try await api.deleteScreenshot(id: id)
                    deletedIds.insert(id)
                    completed += 1
                }

                let finalOrder = finalIdsByLocalIndex.sorted { $0.key < $1.key }.map(\.value)
                if diff.moveCount > 0 || diff.uploadCount > 0 || diff.removalCount > 0 {
                    progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Setting final order · \(Self.label(for: diff))"))
                    markMutated()
                    try await api.setScreenshotOrder(setId: setId, screenshotIds: finalOrder)
                    if diff.moveCount > 0 { completed += 1 }
                }
                let verified = try await verify(
                    setId: setId,
                    expectedIds: finalOrder,
                    expectedChecksums: diff.proposedAssets.compactMap { $0.localAsset?.checksum }
                )
                guard verified else {
                    throw ASCScreenshotSyncError.invalidPlan(
                        String(localized: "App Store Connect did not confirm the final screenshot order for \(Self.label(for: diff)).")
                    )
                }
                let setResult = ASCScreenshotSetSyncResult(
                    id: diff.id,
                    uploaded: diff.uploadCount,
                    removed: diff.removalCount,
                    moved: diff.moveCount,
                    preserved: diff.unchangedCount + diff.moveCount,
                    verified: true,
                    error: nil,
                    deliveries: deliveries,
                    warnings: diff.warnings
                )
                results.append(setResult)
                setEvents(.finished(setResult))
                // Ledgered only now — after `verify`, so an entry means App Store Connect agrees
                // about ids *and* checksums, not merely that we sent the requests.
                recordApplied(setResult, planId: planId)
                activeSet = nil
            }
            progress(UploadProgress(totalSteps: total, completedSteps: total, currentLabel: "Done"))
            CrashReportingService.breadcrumb(.upload, "ASC apply finished", data: ["sets": results.count])
            discardPlan(planId)
            return ASCScreenshotSyncResult(planId: planId, sets: results, didMutate: didMutate)
        } catch {
            // `didMutate` is the difference between "nothing was touched" and "the user's real
            // App Store Connect is now half-updated" — the single most useful bit here.
            CrashReportingService.breadcrumb(.upload, "ASC apply failed", data: [
                "did_mutate": didMutate,
                "cancelled": error is CancellationError,
                "completed_sets": results.count,
            ], level: .warning)
            let completedIds = Set(results.map(\.id))
            let failureMessage: String
            if error is CancellationError {
                failureMessage = didMutate
                    ? String(localized: "Screenshot sync was cancelled. Changes already made in App Store Connect were not reverted.")
                    : String(localized: "Screenshot sync was cancelled before anything was changed in App Store Connect.")
            } else if didMutate {
                failureMessage = String(localized: "\(error.localizedDescription) Changes already made in App Store Connect were not reverted.")
            } else {
                failureMessage = error.localizedDescription
            }
            if let activeSet, !completedIds.contains(activeSet.id) {
                results.append(ASCScreenshotSetSyncResult(
                    id: activeSet.id,
                    uploaded: 0,
                    removed: 0,
                    moved: 0,
                    preserved: 0,
                    verified: false,
                    error: failureMessage
                ))
            }
            let reportedIds = Set(results.map(\.id))
            for set in remaining where !reportedIds.contains(set.id) {
                results.append(ASCScreenshotSetSyncResult(
                    id: set.id,
                    uploaded: 0,
                    removed: 0,
                    moved: 0,
                    preserved: 0,
                    verified: false,
                    error: String(localized: "Not attempted because an earlier screenshot set failed."),
                    state: .notAttempted
                ))
            }
            // `didMutate` used to force a discard, which is exactly backwards: a half-applied
            // plan is the one whose rendered bytes a resume still needs. Discard only when the
            // plan itself is provably unusable.
            if Self.invalidatesPlan(error) { discardPlan(planId) }
            return ASCScreenshotSyncResult(planId: planId, sets: results, didMutate: didMutate)
        }
    }

    func discardPlan(_ id: String) {
        // A running job holds the rendered bytes it may still need to resume with. The GUI upload
        // wizard discards plans on this same singleton, so without this an agent's plan (and its
        // temp directory) vanishes the moment a user opens that sheet.
        guard !retained.contains(id) else {
            pendingDiscard.insert(id)
            return
        }
        // Stamped before the early return: a plan discarded twice, or one whose cache entry is
        // already gone, still has to age its ledger out rather than hold it for the process life.
        ledgerExpiry[id] = Date().addingTimeInterval(Self.planLifetime)
        guard let cached = cache.removeValue(forKey: id) else { return }
        try? FileManager.default.removeItem(at: cached.plan.directory)
    }

    /// Marks a plan as in use by a running job, so a concurrent `discardPlan` defers.
    func retainPlan(_ id: String) {
        retained.insert(id)
    }

    func releasePlan(_ id: String) {
        retained.remove(id)
        if pendingDiscard.remove(id) != nil { discardPlan(id) }
    }

    /// True only for failures that prove the cached plan can never be applied. Everything else —
    /// cancellation, a network blip, an API 5xx — leaves it resumable.
    private static func invalidatesPlan(_ error: Error) -> Bool {
        guard let syncError = error as? ASCScreenshotSyncError else { return false }
        switch syncError {
        case .planNotFound, .planExpired, .staleProject, .staleRemote,
             .invalidPlan, .unreadableImages, .noSetsSelected, .partiallyAppliedSet:
            return true
        case .applyInProgress:
            return false
        }
    }

    private func recordApplied(_ result: ASCScreenshotSetSyncResult, planId: String) {
        applied[planId, default: [:]][result.id] = ASCScreenshotSetSyncResult(
            id: result.id,
            uploaded: result.uploaded,
            removed: result.removed,
            moved: result.moved,
            preserved: result.preserved,
            verified: result.verified,
            error: nil,
            state: .alreadyApplied,
            warnings: result.warnings
        )
        attempted[planId]?.remove(result.id)
    }

    // MARK: - Matching

    static func makeDiff(
        id: String,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        localAssets: [ASCScreenshotLocalAsset],
        remoteSetId: String?,
        remoteAssets: [ASCScreenshotRemoteAsset],
        strategy: ASCSyncStrategy = .reconcile,
        issues: [String] = [],
        warnings: [String] = []
    ) -> ASCScreenshotSetDiff {
        var allIssues = issues
        if localAssets.count > 10 {
            allIssues.append(String(localized: "Apple allows at most 10 screenshots in a display-type set; this proposal has \(localAssets.count)."))
        }
        var availableByChecksum: [String: [Int]] = [:]
        for (index, remote) in remoteAssets.enumerated() {
            availableByChecksum[remote.checksum, default: []].append(index)
        }
        var matchedRemoteIndexes = Set<Int>()
        var items: [ASCScreenshotDiffItem] = []
        for local in localAssets {
            // Under `replaceAll` nothing matches, so every local asset is an upload and every
            // remote one falls through to the removal pass below.
            let matchedIndex = strategy == .replaceAll
                ? nil
                : availableByChecksum[local.checksum]?.first(where: { !matchedRemoteIndexes.contains($0) })
            if let matchedIndex {
                matchedRemoteIndexes.insert(matchedIndex)
                let remote = remoteAssets[matchedIndex]
                let status: ASCScreenshotDiffStatus = remote.index == local.index ? .unchanged : .moved
                items.append(ASCScreenshotDiffItem(
                    id: "local-\(local.id)", status: status, checksum: local.checksum,
                    remoteId: remote.id, originalIndex: remote.index, proposedIndex: local.index,
                    localAsset: local, remoteAsset: remote
                ))
            } else {
                items.append(ASCScreenshotDiffItem(
                    id: "local-\(local.id)", status: .new, checksum: local.checksum,
                    remoteId: nil, originalIndex: nil, proposedIndex: local.index,
                    localAsset: local, remoteAsset: nil
                ))
            }
        }
        for (index, remote) in remoteAssets.enumerated() where !matchedRemoteIndexes.contains(index) {
            items.append(ASCScreenshotDiffItem(
                id: "remote-\(remote.id)", status: .removed, checksum: remote.checksum,
                remoteId: remote.id, originalIndex: remote.index, proposedIndex: nil,
                localAsset: nil, remoteAsset: remote
            ))
        }
        return ASCScreenshotSetDiff(
            id: id,
            versionId: target.versionId,
            versionLabel: target.versionLabel,
            rowId: target.rowId,
            rowLabel: target.rowLabel,
            localizationId: localization.id,
            localeCode: localization.localeCode,
            localeLabel: localization.label,
            displayType: target.displayType,
            remoteSetId: remoteSetId,
            items: items,
            remoteFingerprint: remoteFingerprint(remoteAssets),
            issues: allIssues,
            warnings: warnings,
            canApply: allIssues.isEmpty
        )
    }

    // MARK: - Private helpers

    private struct RemoteSetSnapshot {
        let setId: String?
        let assets: [ASCScreenshotRemoteAsset]
        let warnings: [String]
    }

    private func fetchRemoteSet(
        localizationId: String,
        displayType: ASCDisplayType,
        previewMaxDimension: Int?,
        previewDirectory: URL?
    ) async throws -> RemoteSetSnapshot {
        let sets = try await api.listScreenshotSets(localizationId: localizationId)
        guard let set = sets.first(where: { $0.attributes.screenshotDisplayType == displayType.appStoreConnectValue }) else {
            return RemoteSetSnapshot(setId: nil, assets: [], warnings: [])
        }
        let listed = try await api.listScreenshots(setId: set.id)
        let order = try await api.listScreenshotOrder(setId: set.id)
        let byId = Dictionary(uniqueKeysWithValues: listed.map { ($0.id, $0) })
        let ordered = order.compactMap { byId[$0] } + listed.filter { !order.contains($0.id) }
        var assets: [ASCScreenshotRemoteAsset] = []
        var unmatchableCount = 0
        for (index, screenshot) in ordered.enumerated() {
            var resolved = screenshot
            var detailError: String?
            if screenshot.attributes.imageAsset == nil || screenshot.attributes.sourceFileChecksum == nil {
                do { resolved = try await api.screenshot(id: screenshot.id) }
                catch { detailError = error.localizedDescription }
            }
            var previewData: Data?
            var previewError = detailError
            if let previewMaxDimension {
                do {
                    let data = try await api.downloadScreenshotData(resolved, maxDimension: previewMaxDimension)
                    previewData = await Self.downscaledPNG(data, maxDimension: previewMaxDimension) ?? data
                    previewError = nil
                }
                catch { previewError = error.localizedDescription }
            }
            // `sourceFileChecksum` is the MD5 of the file that was uploaded. Apple re-encodes
            // renditions served from the image host, so hashing a download would never match a
            // locally rendered PNG — an asset without a checksum simply can't be matched.
            let checksum = resolved.attributes.sourceFileChecksum?.lowercased()
            if checksum == nil { unmatchableCount += 1 }
            var previewFileURL: URL?
            if let previewData, let previewDirectory {
                do {
                    try FileManager.default.createDirectory(
                        at: previewDirectory,
                        withIntermediateDirectories: true
                    )
                    let url = previewDirectory.appendingPathComponent(
                        Self.safeFileName("\(index)-\(resolved.id).png")
                    )
                    try previewData.write(to: url, options: .atomic)
                    previewFileURL = url
                } catch {
                    previewError = error.localizedDescription
                }
            }
            assets.append(ASCScreenshotRemoteAsset(
                id: resolved.id,
                index: index,
                fileName: resolved.attributes.fileName ?? "Screenshot \(index + 1)",
                checksum: checksum ?? "unavailable:\(resolved.id)",
                width: resolved.attributes.imageAsset?.width,
                height: resolved.attributes.imageAsset?.height,
                previewData: previewData,
                previewFileURL: previewFileURL,
                previewError: previewError
            ))
        }
        var warnings: [String] = []
        if unmatchableCount > 0 {
            warnings.append(
                unmatchableCount == 1
                    ? String(localized: "1 current screenshot has no App Store checksum, so it will be replaced instead of preserved.")
                    : String(localized: "\(unmatchableCount) current screenshots have no App Store checksum, so they will be replaced instead of preserved.")
            )
        }
        return RemoteSetSnapshot(setId: set.id, assets: assets, warnings: warnings)
    }

    /// Deterministic fixture used by the built-in demo flow. It deliberately contains all four
    /// statuses when a row has at least three screenshots: unchanged, moved, new, and removed.
    private func demoRemoteSet(
        from localAssets: [ASCScreenshotLocalAsset],
        diffId: String,
        previewDirectory: URL
    ) async throws -> RemoteSetSnapshot {
        guard !localAssets.isEmpty else {
            return RemoteSetSnapshot(setId: "demo-set-\(diffId)", assets: [], warnings: [])
        }
        var remotes: [ASCScreenshotRemoteAsset] = []

        // `previewData` is already the 420px downscale of these exact bytes, so reuse it rather
        // than re-reading and re-encoding the file.
        func remote(from local: ASCScreenshotLocalAsset, index: Int, suffix: String) -> ASCScreenshotRemoteAsset {
            ASCScreenshotRemoteAsset(
                id: "demo-\(diffId)-\(suffix)", index: index, fileName: local.fileName,
                checksum: local.checksum, width: local.width, height: local.height,
                previewData: local.previewData,
                previewFileURL: local.fileURL,
                previewError: nil
            )
        }

        if localAssets.count >= 3 {
            remotes.append(remote(from: localAssets[0], index: 0, suffix: "unchanged"))
            remotes.append(remote(from: localAssets[2], index: 1, suffix: "moved"))
        } else if localAssets.count == 2 {
            remotes.append(remote(from: localAssets[1], index: 0, suffix: "moved"))
        }

        var removedData = try Data(contentsOf: localAssets[0].fileURL)
        removedData.append(0) // PNG readers ignore trailing bytes; checksum remains distinct.
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let removedPreviewURL = previewDirectory.appendingPathComponent("removed.png")
        try removedData.write(to: removedPreviewURL, options: .atomic)
        remotes.append(ASCScreenshotRemoteAsset(
            id: "demo-\(diffId)-removed",
            index: remotes.count,
            fileName: "Previous Screenshot.png",
            checksum: Self.md5Hex(removedData),
            width: localAssets[0].width,
            height: localAssets[0].height,
            previewData: await Self.downscaledPNG(removedData, maxDimension: 420) ?? removedData,
            previewFileURL: removedPreviewURL,
            previewError: nil
        ))
        return RemoteSetSnapshot(setId: "demo-set-\(diffId)", assets: remotes, warnings: [])
    }

    private func renderAssets(
        context: RowRenderContext,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        directory: URL
    ) async throws -> [ASCScreenshotLocalAsset] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var assets: [ASCScreenshotLocalAsset] = []
        for index in 0..<target.templateCount {
            try Task.checkCancellation()
            // Rendering needs the main actor (ImageRenderer); everything after it does not.
            let image = context.templateImage(at: index)
            guard let data = await ExportImageEncoder.opaquePNGDataOffMain(from: image) else {
                throw AppStoreConnectUploadError.renderFailed(
                    rowLabel: target.rowLabel,
                    displayTypeLabel: target.displayType.label,
                    localeLabel: localization.label,
                    index: index
                )
            }
            let fileName = ExportFileNaming.screenshotFileName(
                row: context.row,
                localeCode: localization.localeCode,
                index: index,
                customSuffix: ExportFileNaming.preferredCustomSuffix
            )
            let url = directory.appendingPathComponent(fileName)
            let stored = try await Self.store(data, at: url, previewMaxDimension: 420)
            assets.append(ASCScreenshotLocalAsset(
                id: "\(target.rowId.uuidString)-\(localization.id)-\(index)",
                index: index,
                fileName: fileName,
                fileURL: url,
                checksum: stored.checksum,
                width: Int(target.rowSize.width),
                height: Int(target.rowSize.height),
                previewData: stored.preview
            ))
            await Task.yield()
        }
        return assets
    }

    private func upload(
        data: Data,
        fileName: String,
        setId: String,
        checksum: String,
        protectedRemoteIds: Set<String>
    ) async throws -> (id: String, delivery: ASCScreenshotDeliveryOutcome) {
        let reserved = try await reserve(
            setId: setId,
            fileName: fileName,
            fileSize: data.count,
            protectedRemoteIds: protectedRemoteIds
        )
        do {
            for operation in reserved.attributes.uploadOperations ?? [] {
                try Task.checkCancellation()
                try await api.uploadChunk(operation: operation, from: data)
            }
            try await api.commitScreenshot(id: reserved.id, md5Checksum: checksum)
            let delivery = try await waitForDelivery(screenshotId: reserved.id, expectedChecksum: checksum)
            return (reserved.id, delivery)
        } catch {
            // An unstructured Task doesn't inherit cancellation, so this cleanup still runs when
            // the failure *is* cancellation — otherwise the reservation is orphaned in the set.
            let reservedId = reserved.id
            Task { await deleteReservation(reservedId) }
            throw error
        }
    }

    /// Reserving is the one upload step that is neither idempotent nor repeatable by itself,
    /// so its retry lives here rather than in the transport: a 5xx can still have created the
    /// reservation, and a duplicate left in the set makes `verify` reject the final order for
    /// its full 30 seconds. Sweeping between attempts is what makes the retry safe — which is
    /// also why the transport must not retry this POST underneath us.
    private func reserve(
        setId: String,
        fileName: String,
        fileSize: Int,
        protectedRemoteIds: Set<String>
    ) async throws -> ASCAppScreenshot {
        let policy = api.retryPolicy
        return try await policy.attempting {
            do {
                return try await api.reserveScreenshot(setId: setId, fileName: fileName, fileSize: fileSize)
            } catch {
                guard Self.isTransient(error, policy: policy) else { throw error }
                let apiError = error as? AppStoreConnectAPIError
                CrashReportingService.breadcrumb(
                    .upload,
                    "ASC reserve retry",
                    data: apiError?.httpStatus.map { ["status": $0] },
                    level: .warning
                )
                // A request that never reached Apple cannot have left a reservation behind.
                if StoreRetryPolicy.reachedServer(apiError?.transportError ?? error) {
                    await sweepOrphanedReservations(
                        setId: setId,
                        fileName: fileName,
                        protectedRemoteIds: protectedRemoteIds
                    )
                }
                throw StoreRetryPolicy.Retryable(underlying: error)
            }
        }
    }

    /// Deletes only what this reserve attempt could have left behind: same file name, not yet
    /// delivered, and not one of the screenshots the plan is keeping.
    private func sweepOrphanedReservations(
        setId: String,
        fileName: String,
        protectedRemoteIds: Set<String>
    ) async {
        guard let existing = try? await api.listScreenshots(setId: setId) else { return }
        for id in Self.orphanedReservationIds(
            in: existing,
            fileName: fileName,
            protectedRemoteIds: protectedRemoteIds
        ) {
            await deleteReservation(id)
        }
    }

    /// Failing to remove a reservation leaves it in the user's real App Store Connect set.
    private func deleteReservation(_ id: String) async {
        do {
            try await api.deleteScreenshot(id: id)
        } catch {
            CrashReportingService.report(.appStoreOrphanCleanupFailed, error: error)
        }
    }

    static func orphanedReservationIds(
        in screenshots: [ASCAppScreenshot],
        fileName: String,
        protectedRemoteIds: Set<String>
    ) -> [String] {
        screenshots.filter { shot in
            shot.attributes.fileName == fileName
                && !protectedRemoteIds.contains(shot.id)
                && shot.attributes.assetDeliveryState?.isComplete != true
        }.map(\.id)
    }

    /// The reserve POST is repeatable only because `sweepOrphanedReservations` runs first.
    private static func isTransient(_ error: Error, policy: StoreRetryPolicy) -> Bool {
        switch error as? AppStoreConnectAPIError {
        case .httpError(let status, _): policy.allowsRetry(status: status, repeatable: true)
        case .transport(let underlying): policy.allowsRetry(transportError: underlying, repeatable: true)
        case .invalidURL, .decodingFailed, .none: false
        }
    }

    @discardableResult
    private func waitForDelivery(
        screenshotId: String,
        expectedChecksum: String
    ) async throws -> ASCScreenshotDeliveryOutcome {
        if isDemoMode() { return .assumedComplete(screenshotId) }
        for _ in 0..<30 {
            try Task.checkCancellation()
            let screenshot = try await api.screenshot(id: screenshotId, retryPolicy: .singleAttempt)
            let delivery = screenshot.attributes.assetDeliveryState
            if delivery?.isComplete == true {
                if let checksum = screenshot.attributes.sourceFileChecksum,
                   checksum.caseInsensitiveCompare(expectedChecksum) != .orderedSame {
                    throw ASCScreenshotSyncError.invalidPlan(
                        String(localized: "App Store Connect completed an upload with an unexpected checksum.")
                    )
                }
                return ASCScreenshotDeliveryOutcome(
                    screenshotId: screenshotId,
                    state: delivery?.state ?? "COMPLETE",
                    messages: delivery?.warnings?.compactMap { $0.message ?? $0.code } ?? []
                )
            }
            if delivery?.isFailed == true {
                let details = screenshot.attributes.assetDeliveryState?.errors?
                    .compactMap { $0.message ?? $0.code }
                    .joined(separator: ", ")
                throw ASCScreenshotSyncError.invalidPlan(
                    details.map { String(localized: "App Store Connect rejected the screenshot: \($0)") }
                        ?? String(localized: "App Store Connect rejected the screenshot upload.")
                )
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw ASCScreenshotSyncError.invalidPlan(
            String(localized: "App Store Connect did not finish processing the uploaded screenshot in time.")
        )
    }

    private func verify(
        setId: String,
        expectedIds: [String],
        expectedChecksums: [String]
    ) async throws -> Bool {
        if isDemoMode() { return true }
        var lastError: Error?
        for attempt in 0..<30 {
            try Task.checkCancellation()
            do {
                let actual = try await orderedRemoteChecksums(setId: setId)
                if Self.matchesFinalOrder(
                    actual: actual,
                    expectedIds: expectedIds,
                    expectedChecksums: expectedChecksums
                ) {
                    return true
                }
                lastError = nil
            } catch {
                lastError = error
            }

            if attempt < 29 {
                try await Task.sleep(for: .seconds(1))
            }
        }
        if let lastError { throw lastError }
        return false
    }

    static func matchesFinalOrder(
        actual: [(id: String, checksum: String)],
        expectedIds: [String],
        expectedChecksums: [String]
    ) -> Bool {
        actual.map(\.id) == expectedIds
            && actual.map { $0.checksum.lowercased() } == expectedChecksums.map { $0.lowercased() }
    }

    /// Only called from `verify`'s poll loop, which owns the retry budget.
    private func orderedRemoteChecksums(setId: String) async throws -> [(id: String, checksum: String)] {
        let screenshots = try await api.listScreenshots(setId: setId, retryPolicy: .singleAttempt)
        let order = try await api.listScreenshotOrder(setId: setId)
        let byId = Dictionary(uniqueKeysWithValues: screenshots.map { ($0.id, $0) })
        var actual: [(id: String, checksum: String)] = []
        for id in order {
            guard var screenshot = byId[id] else { continue }
            if screenshot.attributes.sourceFileChecksum == nil {
                screenshot = try await api.screenshot(id: id)
            }
            // A just-committed asset may not have published its checksum yet; report it as
            // pending so `verify` keeps retrying instead of comparing against a wrong value.
            actual.append((id, screenshot.attributes.sourceFileChecksum?.lowercased() ?? "pending:\(id)"))
        }
        return actual
    }

    private func validCachedPlan(id: String, document: DocumentStamp?) throws -> CachedPlan {
        guard let cached = cache[id] else { throw ASCScreenshotSyncError.planNotFound }
        guard cached.plan.expiresAt > Date() else {
            discardPlan(id)
            throw ASCScreenshotSyncError.planExpired
        }
        guard let document,
              document.projectId == cached.plan.projectId,
              document.modifiedAt == cached.plan.projectModifiedAt else {
            throw ASCScreenshotSyncError.staleProject
        }
        return cached
    }

    /// A 409 here nearly always means the app version doesn't support that device family (iPad
    /// screenshots on an iPhone-only app, say). Apple's raw text doesn't say what to do about it.
    private static func screenshotSetCreationError(_ error: Error, diff: ASCScreenshotSetDiff) -> Error {
        guard let apiError = error as? AppStoreConnectAPIError,
              case .httpError(let status, let message) = apiError, status == 409 else { return error }
        let lowered = message.lowercased()
        guard lowered.contains("display type"), lowered.contains("not allowed") else { return error }
        return ASCScreenshotSyncError.invalidPlan(
            String(localized: "App Store Connect does not allow \(diff.displayType.label) for \(label(for: diff)). This usually means the app version doesn't support that device family. Exclude this row, choose a display type the app accepts, or update the app's device support, then try again.")
        )
    }

    private func purgeExpiredPlans() {
        let now = Date()
        let expired = cache.values.filter { $0.plan.expiresAt <= now }
        for cached in expired { discardPlan(cached.plan.id) }
        for (id, expiry) in ledgerExpiry where expiry <= now {
            ledgerExpiry[id] = nil
            applied[id] = nil
            attempted[id] = nil
        }
    }

    /// The denominator `apply` reports progress against. Shared so the MCP layer can size a job
    /// before starting one without re-deriving the formula and drifting from it.
    static func applyStepCount(_ sets: [ASCScreenshotSetDiff]) -> Int {
        sets.reduce(0) { $0 + max(1, $1.uploadCount + $1.removalCount + ($1.moveCount > 0 ? 1 : 0)) }
    }

    nonisolated static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `@concurrent` is load-bearing — see the concurrency note in CLAUDE.md.
    @concurrent nonisolated static func fileChecksum(at url: URL) async throws -> String {
        md5Hex(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    @concurrent nonisolated private static func store(
        _ data: Data,
        at url: URL,
        previewMaxDimension: Int
    ) async throws -> (checksum: String, preview: Data) {
        try data.write(to: url, options: .atomic)
        return (md5Hex(data), await downscaledPNG(data, maxDimension: previewMaxDimension) ?? data)
    }

    nonisolated static func remoteFingerprint(_ assets: [ASCScreenshotRemoteAsset]) -> String {
        assets.map { "\($0.id):\($0.checksum):\($0.index)" }.joined(separator: "|")
    }

    @concurrent nonisolated private static func downscaledPNG(_ data: Data, maxDimension: Int) async -> Data? {
        guard maxDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    nonisolated private static func safeFileName(_ value: String) -> String {
        let base = URL(fileURLWithPath: value).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-|"))
        let sanitized = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return sanitized.isEmpty || sanitized == "." || sanitized == ".." ? UUID().uuidString : sanitized
    }

    private static func diffSetId(target: ASCUploadTarget, localization: ASCUploadLocalization) -> String {
        "\(target.versionId)|\(localization.id)|\(target.displayType.appStoreConnectValue)"
    }

    private static func label(for diff: ASCScreenshotSetDiff) -> String {
        "\(diff.versionLabel) · \(diff.localeLabel) · \(diff.displayType.label)"
    }
}

import Foundation

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
    let parentKind: ASCScreenshotSetParentKind
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

    var parent: ASCScreenshotSetParent { ASCScreenshotSetParent(kind: parentKind, id: localizationId) }

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
    var error: String?
    var state: State
    /// `["COMPLETE": 9]` — a histogram, because nine identical strings per set × 64 sets is
    /// unreadable and the interesting case is the one that isn't COMPLETE.
    let assetDeliveryStates: [String: Int]
    /// The escape hatch when the histogram isn't all COMPLETE.
    let nonCompleteAssets: [ASCScreenshotDeliveryProblem]
    /// Carried from the diff: notices such as "these have no App Store checksum, so they will be
    /// replaced rather than preserved". Non-blocking, and previously dropped before reaching MCP.
    let warnings: [String]
    /// `error` is already localized prose, which analytics must never carry. This keeps the shape
    /// of the failure — kind plus HTTP status — so a rate limit reports as itself.
    let failure: StoreUploadFailure?

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
        warnings: [String] = [],
        failure: StoreUploadFailure? = nil
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
        self.failure = failure
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
            fileNames.count == 1
                ? String(localized: "\(rowLabel) · \(localeLabel) uses 1 image file that could not be read, so the screenshots would upload with missing content. Re-add the affected image, then try again.")
                : String(localized: "\(rowLabel) · \(localeLabel) uses \(fileNames.count) image files that could not be read, so the screenshots would upload with missing content. Re-add the affected images, then try again.")
        }
    }
}

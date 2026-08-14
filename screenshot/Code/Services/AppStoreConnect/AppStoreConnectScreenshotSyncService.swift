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

struct ASCScreenshotSetSyncResult: Identifiable, Sendable {
    let id: String
    let uploaded: Int
    let removed: Int
    let moved: Int
    let preserved: Int
    let verified: Bool
    let error: String?
}

struct ASCScreenshotSyncResult: Sendable {
    let planId: String
    let sets: [ASCScreenshotSetSyncResult]

    var succeeded: Bool { sets.allSatisfy { $0.error == nil && $0.verified } }
}

enum ASCScreenshotSyncError: LocalizedError {
    case planNotFound
    case planExpired
    case staleProject
    case staleRemote(set: String)
    case noSetsSelected
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

    private let api: AppStoreConnectAPIService
    private var cache: [String: CachedPlan] = [:]

    init(api: AppStoreConnectAPIService? = nil) {
        self.api = api ?? .shared
    }

    func plan(id: String) -> ASCScreenshotSyncPlan? {
        purgeExpiredPlans()
        return cache[id]?.plan
    }

    func buildPlan(
        appId: String,
        targets: [ASCUploadTarget],
        appState: AppState,
        progress: @escaping (String) -> Void = { _ in }
    ) async throws -> ASCScreenshotSyncPlan {
        guard let projectId = appState.activeProjectId else {
            throw ASCScreenshotSyncError.invalidPlan(String(localized: "Open a project before reviewing screenshots."))
        }
        guard !targets.isEmpty else { throw ASCScreenshotSyncError.noSetsSelected }

        purgeExpiredPlans()
        let planId = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotBro-ASCSync", isDirectory: true)
            .appendingPathComponent(planId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var diffs: [ASCScreenshotSetDiff] = []
        var targetsBySetId: [String: ASCUploadTarget] = [:]
        var localizationsBySetId: [String: ASCUploadLocalization] = [:]
        var imageCache: [String: NSImage] = [:]
        let fontFamilies = appState.availableFontFamilySet

        do {
            for target in targets {
                guard let row = appState.rows.first(where: { $0.id == target.rowId }) else { continue }
                for localization in target.localizations {
                    try Task.checkCancellation()
                    let diffId = Self.diffSetId(target: target, localization: localization)
                    guard targetsBySetId[diffId] == nil else {
                        throw ASCScreenshotSyncError.invalidPlan(
                            String(localized: "More than one row targets \(target.versionLabel) · \(localization.label) · \(target.displayType.label). Choose one row for this set.")
                        )
                    }
                    progress("Rendering \(target.rowLabel) · \(localization.label)")
                    let imageNames = appState.referencedImageFileNames(forRow: row, localeCode: localization.localeCode)
                    let rowImages = appState.loadFullResolutionImages(fileNames: imageNames, cache: &imageCache)
                    // Rendering degrades silently to a hole, so refuse to ship a screenshot
                    // whose image the model references but disk can't produce.
                    let unreadable = imageNames.subtracting(rowImages.keys).sorted()
                    if !unreadable.isEmpty {
                        throw ASCScreenshotSyncError.unreadableImages(
                            rowLabel: target.rowLabel,
                            localeLabel: localization.label,
                            fileNames: unreadable
                        )
                    }
                    let localAssets = try await renderAssets(
                        row: row,
                        target: target,
                        localization: localization,
                        rowImages: rowImages,
                        localeState: appState.localeState,
                        fontFamilies: fontFamilies,
                        directory: directory.appendingPathComponent(Self.safeFileName(diffId), isDirectory: true)
                    )
                    progress("Comparing \(target.rowLabel) · \(localization.label)")
                    let remotePreviewDirectory = directory
                        .appendingPathComponent("remote-previews", isDirectory: true)
                        .appendingPathComponent(Self.safeFileName(diffId), isDirectory: true)
                    let remote = AppStoreConnectCredentialsStore.shared.isDemoMode
                        ? try demoRemoteSet(
                            from: localAssets,
                            diffId: diffId,
                            previewDirectory: remotePreviewDirectory
                        )
                        : try await fetchRemoteSet(
                            localizationId: localization.id,
                            displayType: target.displayType,
                            previewMaxDimension: 420,
                            previewDirectory: remotePreviewDirectory
                        )
                    let diff = Self.makeDiff(
                        id: diffId,
                        target: target,
                        localization: localization,
                        localAssets: localAssets,
                        remoteSetId: remote.setId,
                        remoteAssets: remote.assets,
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
            projectId: projectId,
            projectModifiedAt: Self.projectModifiedStamp(appState),
            appId: appId,
            sets: diffs,
            issues: [],
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
        appState: AppState,
        progress: @escaping (UploadProgress) -> Void = { _ in }
    ) async throws -> ASCScreenshotSyncResult {
        guard !setIds.isEmpty else { throw ASCScreenshotSyncError.noSetsSelected }
        let cached = try validCachedPlan(id: planId, appState: appState)
        let selected = cached.plan.sets.filter { setIds.contains($0.id) }
        guard selected.count == setIds.count, selected.allSatisfy({ $0.isChanged && $0.canApply }) else {
            throw ASCScreenshotSyncError.invalidPlan(String(localized: "One or more selected screenshot sets cannot be applied."))
        }

        // Revalidate every selected set and all cached local bytes before the first write.
        for diff in selected {
            try Task.checkCancellation()
            for local in diff.proposedAssets.compactMap(\.localAsset) {
                guard let checksum = try? await Self.fileChecksum(at: local.fileURL),
                      checksum == local.checksum else {
                    throw ASCScreenshotSyncError.invalidPlan(
                        String(localized: "The cached reviewed bytes for \(local.fileName) changed or are unavailable. Refresh before syncing.")
                    )
                }
            }
            if !AppStoreConnectCredentialsStore.shared.isDemoMode {
                let snapshot = try await fetchRemoteSet(
                    localizationId: diff.localizationId,
                    displayType: diff.displayType,
                    previewMaxDimension: nil,
                    previewDirectory: nil
                )
                guard Self.remoteFingerprint(snapshot.assets) == diff.remoteFingerprint,
                      snapshot.setId == diff.remoteSetId else {
                    throw ASCScreenshotSyncError.staleRemote(set: Self.label(for: diff))
                }
            }
        }

        // Revalidation suspends; perform the project/expiry guard once more immediately before
        // the first App Store mutation.
        _ = try validCachedPlan(id: planId, appState: appState)

        var results: [ASCScreenshotSetSyncResult] = []
        var activeSet: ASCScreenshotSetDiff?
        // Once a write lands the plan's remote fingerprint is stale, so it must be discarded.
        // Before that it is still valid and worth keeping so a cancel or blip can retry cheaply.
        var didMutate = false
        let total = selected.reduce(0) { $0 + max(1, $1.uploadCount + $1.removalCount + ($1.moveCount > 0 ? 1 : 0)) }
        var completed = 0
        progress(UploadProgress(totalSteps: total, completedSteps: 0, currentLabel: "Starting screenshot sync…"))

        do {
            for diff in selected {
                try Task.checkCancellation()
                activeSet = diff
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
                        didMutate = true
                    } catch {
                        throw Self.screenshotSetCreationError(error, diff: diff)
                    }
                }
                let removed = diff.items.filter { $0.status == .removed }.sorted { ($0.originalIndex ?? 0) < ($1.originalIndex ?? 0) }
                var deletedIds = Set<String>()
                for item in removed.prefix(diff.capacityFirstDeletionCount) {
                    guard let id = item.remoteId else { continue }
                    progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Freeing capacity · \(Self.label(for: diff))"))
                    didMutate = true
                    try await api.deleteScreenshot(id: id)
                    deletedIds.insert(id)
                    completed += 1
                }

                var finalIdsByLocalIndex: [Int: String] = [:]
                for item in diff.proposedAssets {
                    guard let local = item.localAsset, let proposedIndex = item.proposedIndex else { continue }
                    if let remoteId = item.remoteId {
                        finalIdsByLocalIndex[proposedIndex] = remoteId
                    } else {
                        progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Uploading \(local.fileName)"))
                        let data = try Data(contentsOf: local.fileURL)
                        didMutate = true
                        let uploadedId = try await upload(
                            data: data,
                            fileName: local.fileName,
                            setId: setId,
                            checksum: local.checksum
                        )
                        finalIdsByLocalIndex[proposedIndex] = uploadedId
                        completed += 1
                    }
                }

                for item in removed where !deletedIds.contains(item.remoteId ?? "") {
                    guard let id = item.remoteId else { continue }
                    progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Removing \(item.remoteAsset?.fileName ?? "old screenshot")"))
                    didMutate = true
                    try await api.deleteScreenshot(id: id)
                    deletedIds.insert(id)
                    completed += 1
                }

                let finalOrder = finalIdsByLocalIndex.sorted { $0.key < $1.key }.map(\.value)
                if diff.moveCount > 0 || diff.uploadCount > 0 || diff.removalCount > 0 {
                    progress(UploadProgress(totalSteps: total, completedSteps: completed, currentLabel: "Setting final order · \(Self.label(for: diff))"))
                    didMutate = true
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
                results.append(ASCScreenshotSetSyncResult(
                    id: diff.id,
                    uploaded: diff.uploadCount,
                    removed: diff.removalCount,
                    moved: diff.moveCount,
                    preserved: diff.unchangedCount + diff.moveCount,
                    verified: true,
                    error: nil
                ))
                activeSet = nil
            }
            progress(UploadProgress(totalSteps: total, completedSteps: total, currentLabel: "Done"))
            discardPlan(planId)
            return ASCScreenshotSyncResult(planId: planId, sets: results)
        } catch {
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
            for set in selected where !reportedIds.contains(set.id) {
                results.append(ASCScreenshotSetSyncResult(
                    id: set.id,
                    uploaded: 0,
                    removed: 0,
                    moved: 0,
                    preserved: 0,
                    verified: false,
                    error: String(localized: "Not attempted because an earlier screenshot set failed.")
                ))
            }
            if didMutate || error is ASCScreenshotSyncError { discardPlan(planId) }
            return ASCScreenshotSyncResult(planId: planId, sets: results)
        }
    }

    func discardPlan(_ id: String) {
        guard let cached = cache.removeValue(forKey: id) else { return }
        try? FileManager.default.removeItem(at: cached.plan.directory)
    }

    // MARK: - Matching

    static func makeDiff(
        id: String,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        localAssets: [ASCScreenshotLocalAsset],
        remoteSetId: String?,
        remoteAssets: [ASCScreenshotRemoteAsset],
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
            let matchedIndex = availableByChecksum[local.checksum]?.first(where: { !matchedRemoteIndexes.contains($0) })
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
                    previewData = Self.downscaledPNG(data, maxDimension: previewMaxDimension) ?? data
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
    ) throws -> RemoteSetSnapshot {
        guard !localAssets.isEmpty else {
            return RemoteSetSnapshot(setId: "demo-set-\(diffId)", assets: [], warnings: [])
        }
        var remotes: [ASCScreenshotRemoteAsset] = []

        func remote(from local: ASCScreenshotLocalAsset, index: Int, suffix: String) throws -> ASCScreenshotRemoteAsset {
            let data = try Data(contentsOf: local.fileURL)
            return ASCScreenshotRemoteAsset(
                id: "demo-\(diffId)-\(suffix)", index: index, fileName: local.fileName,
                checksum: local.checksum, width: local.width, height: local.height,
                previewData: Self.downscaledPNG(data, maxDimension: 420) ?? data,
                previewFileURL: local.fileURL,
                previewError: nil
            )
        }

        if localAssets.count >= 3 {
            remotes.append(try remote(from: localAssets[0], index: 0, suffix: "unchanged"))
            remotes.append(try remote(from: localAssets[2], index: 1, suffix: "moved"))
        } else if localAssets.count == 2 {
            remotes.append(try remote(from: localAssets[1], index: 0, suffix: "moved"))
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
            previewData: Self.downscaledPNG(removedData, maxDimension: 420) ?? removedData,
            previewFileURL: removedPreviewURL,
            previewError: nil
        ))
        return RemoteSetSnapshot(setId: "demo-set-\(diffId)", assets: remotes, warnings: [])
    }

    private func renderAssets(
        row: ScreenshotRow,
        target: ASCUploadTarget,
        localization: ASCUploadLocalization,
        rowImages: [String: NSImage],
        localeState: LocaleState,
        fontFamilies: Set<String>,
        directory: URL
    ) async throws -> [ASCScreenshotLocalAsset] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var assets: [ASCScreenshotLocalAsset] = []
        for index in 0..<target.templateCount {
            try Task.checkCancellation()
            // Rendering needs the main actor (ImageRenderer); everything after it does not.
            let image = ExportService.renderSingleTemplateImage(
                index: index,
                row: row,
                screenshotImages: rowImages,
                localeCode: localization.localeCode,
                localeState: localeState,
                availableFontFamilies: fontFamilies
            )
            guard let data = ExportService.encodeImage(image, format: .png) else {
                throw AppStoreConnectUploadError.renderFailed(
                    rowLabel: target.rowLabel,
                    displayTypeLabel: target.displayType.label,
                    localeLabel: localization.label,
                    index: index
                )
            }
            let fileName = Self.safeFileName(String(format: "%02d-%@.png", index + 1, target.rowLabel))
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
        }
        return assets
    }

    private func upload(
        data: Data,
        fileName: String,
        setId: String,
        checksum: String
    ) async throws -> String {
        let reserved = try await api.reserveScreenshot(setId: setId, fileName: fileName, fileSize: data.count)
        do {
            for operation in reserved.attributes.uploadOperations ?? [] {
                try Task.checkCancellation()
                try await api.uploadChunk(operation: operation, from: data)
            }
            try await api.commitScreenshot(id: reserved.id, md5Checksum: checksum)
            try await waitForDelivery(screenshotId: reserved.id, expectedChecksum: checksum)
            return reserved.id
        } catch {
            // An unstructured Task doesn't inherit cancellation, so this cleanup still runs when
            // the failure *is* cancellation — otherwise the reservation is orphaned in the set.
            let reservedId = reserved.id
            Task { try? await api.deleteScreenshot(id: reservedId) }
            throw error
        }
    }

    private func waitForDelivery(screenshotId: String, expectedChecksum: String) async throws {
        if AppStoreConnectCredentialsStore.shared.isDemoMode { return }
        for _ in 0..<30 {
            try Task.checkCancellation()
            let screenshot = try await api.screenshot(id: screenshotId)
            let state = screenshot.attributes.assetDeliveryState?.state?.uppercased()
            if state == "COMPLETE" {
                if let checksum = screenshot.attributes.sourceFileChecksum,
                   checksum.caseInsensitiveCompare(expectedChecksum) != .orderedSame {
                    throw ASCScreenshotSyncError.invalidPlan(
                        String(localized: "App Store Connect completed an upload with an unexpected checksum.")
                    )
                }
                return
            }
            if state == "FAILED" {
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
        if AppStoreConnectCredentialsStore.shared.isDemoMode { return true }
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

    private func orderedRemoteChecksums(setId: String) async throws -> [(id: String, checksum: String)] {
        let screenshots = try await api.listScreenshots(setId: setId)
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

    private func validCachedPlan(id: String, appState: AppState) throws -> CachedPlan {
        guard let cached = cache[id] else { throw ASCScreenshotSyncError.planNotFound }
        guard cached.plan.expiresAt > Date() else {
            discardPlan(id)
            throw ASCScreenshotSyncError.planExpired
        }
        guard appState.activeProjectId == cached.plan.projectId,
              Self.projectModifiedStamp(appState) == cached.plan.projectModifiedAt else {
            throw ASCScreenshotSyncError.staleProject
        }
        return cached
    }

    /// Both the build and the pre-write guard must derive this the same way, or a project with
    /// no recorded modification date can never satisfy the guard it was stamped with.
    private static func projectModifiedStamp(_ appState: AppState) -> Date? {
        appState.activeProjectDataModifiedAt ?? appState.activeProject?.modifiedAt
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
        let expired = cache.values.filter { $0.plan.expiresAt <= Date() }
        for cached in expired { discardPlan(cached.plan.id) }
    }

    nonisolated static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hashing and thumbnailing a multi-MB PNG is pure CPU; `nonisolated async` runs these off
    /// the main actor (on the cooperative pool) so the sync UI stays responsive.
    nonisolated static func fileChecksum(at url: URL) async throws -> String {
        md5Hex(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    nonisolated private static func store(
        _ data: Data,
        at url: URL,
        previewMaxDimension: Int
    ) async throws -> (checksum: String, preview: Data) {
        try data.write(to: url, options: .atomic)
        return (md5Hex(data), downscaledPNG(data, maxDimension: previewMaxDimension) ?? data)
    }

    nonisolated static func remoteFingerprint(_ assets: [ASCScreenshotRemoteAsset]) -> String {
        assets.map { "\($0.id):\($0.checksum):\($0.index)" }.joined(separator: "|")
    }

    nonisolated private static func downscaledPNG(_ data: Data, maxDimension: Int) -> Data? {
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

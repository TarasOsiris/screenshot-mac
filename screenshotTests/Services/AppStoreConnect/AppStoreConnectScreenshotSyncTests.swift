import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct AppStoreConnectScreenshotSyncTests {
    @Test func identicalOrderIsUnchanged() {
        let diff = makeDiff(local: ["a", "b"], remote: ["a", "b"])
        #expect(diff.unchangedCount == 2)
        #expect(diff.moveCount == 0)
        #expect(!diff.isChanged)
    }

    @Test func reorderOnlyPreservesAssetsAndMarksMoves() {
        let diff = makeDiff(local: ["a", "b"], remote: ["b", "a"])
        #expect(diff.moveCount == 2)
        #expect(diff.uploadCount == 0)
        #expect(diff.removalCount == 0)
        #expect(diff.proposedAssets.map(\.remoteId) == ["remote-1", "remote-0"])
    }

    @Test func additionsAndRemovalsAreReportedSeparately() {
        let diff = makeDiff(local: ["a", "new"], remote: ["a", "old"])
        #expect(diff.unchangedCount == 1)
        #expect(diff.uploadCount == 1)
        #expect(diff.removalCount == 1)
    }

    @Test func duplicateChecksumsMatchInStableOriginalOrder() {
        let diff = makeDiff(local: ["same", "same", "same"], remote: ["same", "same"])
        #expect(diff.proposedAssets[0].remoteId == "remote-0")
        #expect(diff.proposedAssets[1].remoteId == "remote-1")
        #expect(diff.proposedAssets[2].status == .new)
    }

    @Test func emptyRemoteSetMakesEveryLocalAssetNew() {
        let diff = makeDiff(local: ["a", "b"], remote: [])
        #expect(diff.uploadCount == 2)
        #expect(diff.removalCount == 0)
    }

    @Test func fullSetFreesOnlyMinimumRequiredCapacity() {
        let local = (0..<10).map { $0 < 8 ? "same-\($0)" : "new-\($0)" }
        let remote = (0..<10).map { $0 < 8 ? "same-\($0)" : "old-\($0)" }
        let diff = makeDiff(local: local, remote: remote)
        #expect(diff.uploadCount == 2)
        #expect(diff.removalCount == 2)
        #expect(diff.capacityFirstDeletionCount == 2)
    }

    @Test func proposalsOverAppleLimitCannotBeApplied() {
        let diff = makeDiff(local: (0...10).map { "new-\($0)" }, remote: [])
        #expect(!diff.canApply)
        #expect(diff.issues.contains { $0.contains("at most 10") })
    }

    @Test func remotesWithoutAChecksumAreReplacedAndWarnedAboutWithoutBlocking() {
        let diff = makeDiff(
            local: ["a", "b"],
            remote: ["a", "unavailable:remote-1"],
            warnings: ["1 current screenshot has no App Store checksum, so it will be replaced instead of preserved."]
        )

        #expect(diff.warnings.count == 1)
        #expect(diff.issues.isEmpty)
        #expect(diff.canApply)
        #expect(diff.unchangedCount == 1)
        #expect(diff.uploadCount == 1)
        #expect(diff.removalCount == 1)
    }

    @Test func warningsDoNotRescueASetThatHasABlockingIssue() {
        let diff = makeDiff(
            local: (0...10).map { "new-\($0)" },
            remote: [],
            warnings: ["heads up"]
        )

        #expect(diff.warnings == ["heads up"])
        #expect(!diff.canApply)
    }

    @Test func pendingChecksumsNeverSatisfyFinalOrderVerification() {
        let actual = [
            (id: "shot-a", checksum: "abc"),
            (id: "shot-b", checksum: "pending:shot-b")
        ]

        #expect(!AppStoreConnectScreenshotSyncService.matchesFinalOrder(
            actual: actual,
            expectedIds: ["shot-a", "shot-b"],
            expectedChecksums: ["abc", "def"]
        ))
    }

    @Test func coordinatorSelectsOnlyChangedApplicableSets() {
        let changed = makeDiff(local: ["new"], remote: ["old"])
        let unchanged = makeDiff(local: ["same"], remote: ["same"], id: "unchanged-set")
        let coordinator = ASCScreenshotSyncCoordinator()
        coordinator.plan = ASCScreenshotSyncPlan(
            id: "plan",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(60),
            projectId: UUID(),
            projectModifiedAt: Date(),
            appId: "app",
            sets: [changed, unchanged],
            issues: [],
            directory: URL(fileURLWithPath: "/tmp/plan")
        )
        coordinator.phase = .ready

        coordinator.toggle(changed, included: true)
        coordinator.toggle(unchanged, included: true)

        #expect(coordinator.selectedSetIds == Set([changed.id]))
        #expect(coordinator.canApply)
    }

    @Test func coordinatorBulkSelectionOnlyTakesChangedApplicableSets() {
        let changed = makeDiff(local: ["new"], remote: ["old"])
        let unchanged = makeDiff(local: ["same"], remote: ["same"], id: "unchanged-set")
        let blocked = makeDiff(local: ["new"], remote: ["old"], id: "blocked-set", issues: ["No display type"])
        let coordinator = ASCScreenshotSyncCoordinator()
        coordinator.plan = makePlan(sets: [changed, unchanged, blocked])
        coordinator.phase = .ready

        coordinator.selectAllChanged()
        #expect(coordinator.selectedSetIds == Set([changed.id]))

        coordinator.deselectAll()
        #expect(coordinator.selectedSetIds.isEmpty)
        #expect(!coordinator.canApply)
    }

    @Test func coordinatorSelectionTotalsMatchTheIncludedSets() {
        let changed = makeDiff(local: ["a", "new"], remote: ["a", "old"])
        let coordinator = ASCScreenshotSyncCoordinator()
        coordinator.plan = makePlan(sets: [changed])
        coordinator.phase = .ready
        coordinator.selectAllChanged()

        let totals = coordinator.selectionTotals
        #expect(totals.setCount == 1)
        #expect(totals.uploads == 1)
        #expect(totals.removals == 1)
        #expect(totals.preserved == 1)
    }

    @Test func coordinatorDiscardClearsTheReviewOutline() {
        let changed = makeDiff(local: ["new"], remote: ["old"])
        let coordinator = ASCScreenshotSyncCoordinator()
        coordinator.plan = makePlan(sets: [changed])
        coordinator.phase = .ready
        coordinator.selectAllChanged()

        coordinator.discard()

        #expect(coordinator.outline.versions.isEmpty)
        #expect(coordinator.selectedSetIds.isEmpty)
        #expect(coordinator.plan == nil)
    }

    @Test func coordinatorRejectsExpiredReview() {
        let changed = makeDiff(local: ["new"], remote: ["old"])
        let coordinator = ASCScreenshotSyncCoordinator()
        coordinator.plan = ASCScreenshotSyncPlan(
            id: "expired",
            createdAt: Date().addingTimeInterval(-120),
            expiresAt: Date().addingTimeInterval(-60),
            projectId: UUID(),
            projectModifiedAt: Date(),
            appId: "app",
            sets: [changed],
            issues: [],
            directory: URL(fileURLWithPath: "/tmp/expired-plan")
        )
        coordinator.phase = .ready
        coordinator.toggle(changed, included: true)

        #expect(coordinator.isExpired)
        #expect(!coordinator.canApply)
    }

    @Test func imageAssetTemplateURLUsesDimensionsAndFilenameFormat() {
        let asset = ASCImageAsset(
            templateUrl: "https://example.test/image_{w}x{h}.{f}",
            width: 1200,
            height: 2400
        )
        let full = AppStoreConnectAPIService.resolvedImageAssetURL(asset, fileName: "store-shot.jpg")
        #expect(full?.absoluteString == "https://example.test/image_1200x2400.jpg")
    }

    @Test func imageAssetTemplateURLRequestsAThumbnailWhenBounded() {
        let asset = ASCImageAsset(
            templateUrl: "https://example.test/image_{w}x{h}.{f}",
            width: 1200,
            height: 2400
        )
        let bounded = AppStoreConnectAPIService.resolvedImageAssetURL(
            asset,
            fileName: "store-shot.jpg",
            maxDimension: 600
        )
        #expect(bounded?.absoluteString == "https://example.test/image_300x600.jpg")
    }

    @Test func imageAssetTemplateURLNeverUpscales() {
        let asset = ASCImageAsset(
            templateUrl: "https://example.test/{w}x{h}.{f}",
            width: 300,
            height: 600
        )
        let url = AppStoreConnectAPIService.resolvedImageAssetURL(
            asset,
            fileName: "shot.png",
            maxDimension: 4000
        )
        #expect(url?.absoluteString == "https://example.test/300x600.png")
    }

    @Test func screenshotDetailsDecodeChecksumAssetDimensionsAndDeliveryState() throws {
        let json = """
        {
          "type": "appScreenshots",
          "id": "shot-1",
          "attributes": {
            "fileName": "shot.png",
            "fileSize": 42,
            "sourceFileChecksum": "abc123",
            "imageAsset": { "templateUrl": "https://example.test/{w}x{h}.{f}", "width": 1290, "height": 2796 },
            "assetDeliveryState": { "state": "COMPLETE", "errors": [{ "code": "NONE", "message": "Ready" }] }
          }
        }
        """
        let screenshot = try JSONDecoder().decode(ASCAppScreenshot.self, from: Data(json.utf8))
        #expect(screenshot.attributes.sourceFileChecksum == "abc123")
        #expect(screenshot.attributes.imageAsset?.width == 1290)
        #expect(screenshot.attributes.imageAsset?.height == 2796)
        #expect(screenshot.attributes.assetDeliveryState?.state == "COMPLETE")
        #expect(screenshot.attributes.assetDeliveryState?.errors?.first?.message == "Ready")
    }

    @Test func finalOrderVerificationRequiresMatchingIdsAndChecksums() {
        let actual = [
            (id: "shot-a", checksum: "ABC"),
            (id: "shot-b", checksum: "def")
        ]

        #expect(AppStoreConnectScreenshotSyncService.matchesFinalOrder(
            actual: actual,
            expectedIds: ["shot-a", "shot-b"],
            expectedChecksums: ["abc", "DEF"]
        ))
        #expect(!AppStoreConnectScreenshotSyncService.matchesFinalOrder(
            actual: actual,
            expectedIds: ["shot-b", "shot-a"],
            expectedChecksums: ["def", "abc"]
        ))
        #expect(!AppStoreConnectScreenshotSyncService.matchesFinalOrder(
            actual: actual,
            expectedIds: ["shot-a", "shot-b"],
            expectedChecksums: ["abc", "different"]
        ))
    }

    private func makePlan(sets: [ASCScreenshotSetDiff]) -> ASCScreenshotSyncPlan {
        ASCScreenshotSyncPlan(
            id: "plan",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(60),
            projectId: UUID(),
            projectModifiedAt: Date(),
            appId: "app",
            sets: sets,
            issues: [],
            directory: URL(fileURLWithPath: "/tmp/plan")
        )
    }

    private func makeDiff(
        local checksums: [String],
        remote remoteChecksums: [String],
        id: String = "set",
        issues: [String] = [],
        warnings: [String] = []
    ) -> ASCScreenshotSetDiff {
        let local = checksums.enumerated().map { index, checksum in
            ASCScreenshotLocalAsset(
                id: "local-\(index)",
                index: index,
                fileName: "\(index).png",
                fileURL: URL(fileURLWithPath: "/tmp/\(index).png"),
                checksum: checksum,
                width: 1290,
                height: 2796,
                previewData: Data()
            )
        }
        let remote = remoteChecksums.enumerated().map { index, checksum in
            ASCScreenshotRemoteAsset(
                id: "remote-\(index)",
                index: index,
                fileName: "remote-\(index).png",
                checksum: checksum,
                width: 1290,
                height: 2796,
                previewData: nil,
                previewFileURL: nil,
                previewError: nil
            )
        }
        let target = ASCUploadTarget(
            versionId: "version",
            versionLabel: "iOS · Version 1.0",
            rowId: UUID(),
            rowLabel: "iPhone",
            rowSize: CGSize(width: 1290, height: 2796),
            displayType: .iphone67,
            localizations: [],
            templateCount: checksums.count
        )
        return AppStoreConnectScreenshotSyncService.makeDiff(
            id: id,
            target: target,
            localization: ASCUploadLocalization(id: "loc", label: "en-US", localeCode: "en"),
            localAssets: local,
            remoteSetId: "remote-set",
            remoteAssets: remote,
            issues: issues,
            warnings: warnings
        )
    }
}

/// The sweep that makes retrying a non-idempotent reserve safe: after a 5xx the reservation may
/// or may not exist server-side, and a duplicate left behind makes `verify` reject the final
/// order. It must delete exactly what the failed attempt could have created — nothing else.
struct ASCOrphanedReservationTests {

    private func screenshot(_ id: String, fileName: String, state: String?) -> ASCAppScreenshot {
        ASCAppScreenshot(
            id: id,
            attributes: ASCAppScreenshot.Attributes(
                fileName: fileName,
                assetDeliveryState: state.map { ASCAssetDeliveryState(state: $0, errors: nil, warnings: nil) }
            )
        )
    }

    @Test func sweepsAnIncompleteReservationForTheSameFileName() {
        let ids = AppStoreConnectScreenshotSyncService.orphanedReservationIds(
            in: [screenshot("orphan", fileName: "01.png", state: "UPLOAD_COMPLETE")],
            fileName: "01.png",
            protectedRemoteIds: []
        )
        #expect(ids == ["orphan"])
    }

    /// A delivered screenshot is real content, not a leftover — deleting it would destroy the
    /// user's existing App Store listing.
    @Test func neverSweepsACompletedScreenshot() {
        let ids = AppStoreConnectScreenshotSyncService.orphanedReservationIds(
            in: [screenshot("live", fileName: "01.png", state: "COMPLETE")],
            fileName: "01.png",
            protectedRemoteIds: []
        )
        #expect(ids.isEmpty)
    }

    @Test func completeStateIsMatchedCaseInsensitively() {
        let ids = AppStoreConnectScreenshotSyncService.orphanedReservationIds(
            in: [screenshot("live", fileName: "01.png", state: "complete")],
            fileName: "01.png",
            protectedRemoteIds: []
        )
        #expect(ids.isEmpty)
    }

    /// Anything the plan is keeping or has already uploaded this run is off limits, even if
    /// App Store Connect has not finished delivering it yet.
    @Test func neverSweepsAProtectedId() {
        let ids = AppStoreConnectScreenshotSyncService.orphanedReservationIds(
            in: [screenshot("kept", fileName: "01.png", state: nil)],
            fileName: "01.png",
            protectedRemoteIds: ["kept"]
        )
        #expect(ids.isEmpty)
    }

    @Test func ignoresOtherFileNames() {
        let ids = AppStoreConnectScreenshotSyncService.orphanedReservationIds(
            in: [screenshot("other", fileName: "02.png", state: nil)],
            fileName: "01.png",
            protectedRemoteIds: []
        )
        #expect(ids.isEmpty)
    }

    @Test func picksOnlyTheOrphansOutOfAMixedSet() {
        let ids = AppStoreConnectScreenshotSyncService.orphanedReservationIds(
            in: [
                screenshot("live", fileName: "01.png", state: "COMPLETE"),
                screenshot("kept", fileName: "01.png", state: nil),
                screenshot("orphan-a", fileName: "01.png", state: nil),
                screenshot("orphan-b", fileName: "01.png", state: "UPLOAD_COMPLETE"),
                screenshot("elsewhere", fileName: "02.png", state: nil),
            ],
            fileName: "01.png",
            protectedRemoteIds: ["kept"]
        )
        #expect(ids == ["orphan-a", "orphan-b"])
    }
}

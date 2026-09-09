import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

// Also covers `makeDiff` under the two strategies, which is where Replace All is implemented.
// The direct upload path used to publish `totalSteps: 1, completedSteps: 0` for the whole plan
// build, which `UploadProgressView` draws as a determinate bar pinned at "0 / 1" — a slow sync and
// a hung one looked identical. The counts were already being computed and thrown away.
@MainActor
struct ASCUploadProgressTests {

    private func update(
        _ stage: ASCSyncBuildProgress.Stage,
        completed: Int,
        total: Int
    ) -> ASCSyncBuildProgress {
        ASCSyncBuildProgress(stage: stage, completedRenders: completed, totalRenders: total, label: "Row · en-US")
    }

    @Test func buildProgressCarriesTheRenderCounts() {
        let progress = ASCUploadFlowModel.buildProgress(update(.rendering, completed: 74, total: 180))
        #expect(progress.totalSteps == 180)
        #expect(progress.completedSteps == 74)
        #expect(progress.currentLabel.contains("Row · en-US"))
    }

    /// The two stages have to be distinguishable, because "comparing" is when the network round
    /// trips happen and the renders counter stops moving.
    @Test func theStageIsVisibleInTheLabel() {
        let rendering = ASCUploadFlowModel.buildProgress(update(.rendering, completed: 1, total: 2)).currentLabel
        let comparing = ASCUploadFlowModel.buildProgress(update(.comparing, completed: 2, total: 2)).currentLabel
        #expect(rendering != comparing)
    }

    /// The denominator is always the build's own, never invented. A zero total is what
    /// `UploadProgressView` reads as "indeterminate", and passing it through is what keeps an
    /// empty build honest instead of showing a bar that cannot move.
    @Test func theDenominatorIsAlwaysTheBuildsOwn() {
        for total in [0, 1, 12, 180] {
            let progress = ASCUploadFlowModel.buildProgress(update(.rendering, completed: 0, total: total))
            #expect(progress.totalSteps == total)
        }
    }
}

// `makeDiff` is the whole of Replace All: it stops matching, so every local asset becomes an
// upload and every remote one a removal. The capacity arithmetic behind Apple's 10-screenshot
// limit then has to hold for a set that is already full.
@MainActor
struct ASCReplaceAllDiffTests {

    private func local(_ index: Int, checksum: String) -> ASCScreenshotLocalAsset {
        ASCScreenshotLocalAsset(
            id: "l\(index)", index: index, fileName: "l\(index).png",
            fileURL: URL(fileURLWithPath: "/tmp/l\(index).png"),
            checksum: checksum, width: 1290, height: 2796, previewData: Data()
        )
    }

    private func remote(_ index: Int, checksum: String) -> ASCScreenshotRemoteAsset {
        ASCScreenshotRemoteAsset(
            id: "r\(index)", index: index, fileName: "r\(index).png", checksum: checksum,
            width: 1290, height: 2796, previewData: nil, previewFileURL: nil, previewError: nil
        )
    }

    private func diff(strategy: ASCSyncStrategy, count: Int) -> ASCScreenshotSetDiff {
        let checksums = (0..<count).map { "checksum-\($0)" }
        return AppStoreConnectScreenshotSyncService.makeDiff(
            id: "set",
            target: ASCUploadTarget(
                versionId: "v1", versionLabel: "iOS · 1.0", rowId: UUID(), rowLabel: "Row",
                rowSize: CGSize(width: 1290, height: 2796), displayType: .iphone67,
                localizations: [ASCUploadLocalization(id: "loc", label: "en-US", localeCode: "en")],
                templateCount: count
            ),
            localization: ASCUploadLocalization(id: "loc", label: "en-US", localeCode: "en"),
            localAssets: checksums.enumerated().map { local($0.offset, checksum: $0.element) },
            remoteSetId: "set-1",
            remoteAssets: checksums.enumerated().map { remote($0.offset, checksum: $0.element) },
            strategy: strategy
        )
    }

    /// Identical bytes on both sides: reconcile touches nothing, replaceAll rewrites everything.
    @Test func theStrategyDecidesWhetherIdenticalBytesAreWork() {
        let reconciled = diff(strategy: .reconcile, count: 3)
        #expect(reconciled.unchangedCount == 3)
        #expect(reconciled.uploadCount == 0)
        #expect(reconciled.removalCount == 0)

        let replaced = diff(strategy: .replaceAll, count: 3)
        #expect(replaced.unchangedCount == 0)
        #expect(replaced.uploadCount == 3)
        #expect(replaced.removalCount == 3)
    }

    /// A full set replaced wholesale is 10 remote + 10 uploads against a cap of 10, so all ten
    /// removals must happen before the first upload or App Store Connect rejects the eleventh.
    @Test func aFullSetDeletesAllTenBeforeUploading() {
        let replaced = diff(strategy: .replaceAll, count: 10)
        #expect(replaced.uploadCount == 10)
        #expect(replaced.removalCount == 10)
        #expect(replaced.capacityFirstDeletionCount == 10)
        #expect(replaced.canApply, "ten proposed screenshots is exactly Apple's limit")
    }

    /// Reconcile on the same full set needs no capacity juggling at all.
    @Test func reconcileOnAFullUnchangedSetFreesNothing() {
        #expect(diff(strategy: .reconcile, count: 10).capacityFirstDeletionCount == 0)
    }
}

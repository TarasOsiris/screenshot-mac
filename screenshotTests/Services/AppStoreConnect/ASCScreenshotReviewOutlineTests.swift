import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ASCScreenshotReviewOutlineTests {
    @Test func groupsByVersionThenRowPreservingGeneratedOrder() {
        let hero = UUID()
        let feature = UUID()
        let outline = ASCScreenshotReviewOutline(sets: [
            makeDiff(id: "v1-hero-en", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "en-US"),
            makeDiff(id: "v1-hero-de", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "de-DE"),
            makeDiff(id: "v1-feature-en", versionId: "v1", rowId: feature, rowLabel: "Feature", locale: "en-US"),
            makeDiff(id: "v2-hero-en", versionId: "v2", rowId: hero, rowLabel: "Hero", locale: "en-US")
        ])

        #expect(outline.versions.map(\.id) == ["v1", "v2"])
        #expect(outline.versions[0].devices.map(\.rowLabel) == ["Hero", "Feature"])
        #expect(outline.versions[0].devices[0].sets.map(\.localeLabel) == ["en-US", "de-DE"])
        #expect(outline.versions[1].devices.count == 1)
    }

    @Test func theSameRowInTwoVersionsStaysTwoGroups() {
        let hero = UUID()
        let outline = ASCScreenshotReviewOutline(sets: [
            makeDiff(id: "v1-hero", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "en-US"),
            makeDiff(id: "v2-hero", versionId: "v2", rowId: hero, rowLabel: "Hero", locale: "en-US")
        ])

        let groupIds = outline.versions.flatMap(\.devices).map(\.id)
        #expect(Set(groupIds).count == 2)
    }

    @Test func groupAggregatesItemCountsAcrossItsLocales() throws {
        let hero = UUID()
        let outline = ASCScreenshotReviewOutline(sets: [
            makeDiff(id: "en", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "en-US",
                     local: ["a", "new"], remote: ["a", "old"]),
            makeDiff(id: "de", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "de-DE",
                     local: ["a", "b"], remote: ["b", "a"]),
            makeDiff(id: "fr", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "fr-FR",
                     local: ["a"], remote: ["a"])
        ])
        let group = try #require(outline.versions.first?.devices.first)

        #expect(group.sets.count == 3)
        #expect(group.changedCount == 2)
        #expect(group.uploadCount == 1)
        #expect(group.removalCount == 1)
        #expect(group.moveCount == 2)
        #expect(group.blockedCount == 0)
    }

    @Test func outlineCountsChangedUnchangedAndBlockedSets() {
        let hero = UUID()
        let outline = ASCScreenshotReviewOutline(sets: [
            makeDiff(id: "changed", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "en-US",
                     local: ["new"], remote: ["old"]),
            makeDiff(id: "unchanged", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "de-DE",
                     local: ["a"], remote: ["a"]),
            makeDiff(id: "blocked", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "fr-FR",
                     local: ["new"], remote: ["old"], issues: ["No display type"])
        ])

        #expect(outline.changedCount == 2)
        #expect(outline.unchangedCount == 1)
        #expect(outline.blockedCount == 1)
        #expect(outline.versions[0].changedCount == 2)
        #expect(outline.versions[0].blockedCount == 1)
        #expect(outline.versions[0].setCount == 3)
    }

    @Test func emptyOutlineHasNoVersions() {
        #expect(ASCScreenshotReviewOutline.empty.versions.isEmpty)
        #expect(ASCScreenshotReviewOutline.empty.changedCount == 0)
    }

    @Test func selectionTotalsSumTheIncludedSets() {
        let hero = UUID()
        let totals = ASCScreenshotSelectionTotals(sets: [
            makeDiff(id: "en", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "en-US",
                     local: ["a", "new"], remote: ["a", "old"]),
            makeDiff(id: "de", versionId: "v1", rowId: hero, rowLabel: "Hero", locale: "de-DE",
                     local: ["a", "b"], remote: ["b", "a"])
        ])

        #expect(totals.setCount == 2)
        #expect(totals.uploads == 1)
        #expect(totals.removals == 1)
        #expect(totals.moves == 2)
        #expect(totals.preserved == 1)
    }

    private func makeDiff(
        id: String,
        versionId: String,
        rowId: UUID,
        rowLabel: String,
        locale: String,
        local: [String] = ["new"],
        remote: [String] = ["old"],
        issues: [String] = []
    ) -> ASCScreenshotSetDiff {
        let localAssets = local.enumerated().map { index, checksum in
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
        let remoteAssets = remote.enumerated().map { index, checksum in
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
            versionId: versionId,
            versionLabel: "iOS · \(versionId)",
            rowId: rowId,
            rowLabel: rowLabel,
            rowSize: CGSize(width: 1290, height: 2796),
            displayType: .iphone67,
            localizations: [],
            templateCount: local.count
        )
        return AppStoreConnectScreenshotSyncService.makeDiff(
            id: id,
            target: target,
            localization: ASCUploadLocalization(id: "loc-\(locale)", label: locale, localeCode: locale),
            localAssets: localAssets,
            remoteSetId: "remote-set",
            remoteAssets: remoteAssets,
            issues: issues
        )
    }
}

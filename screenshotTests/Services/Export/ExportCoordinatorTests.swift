import AppKit
import Foundation
@testable import Screenshot_Bro
import Testing

/// A `RowRenderSource` whose disk holds nothing, so anything in the context's images
/// can only have come from the seed.
@MainActor
private final class EmptyRenderSource: RowRenderSource {
    var localeState: LocaleState = .default
    var availableFontFamilySet: Set<String> = []
    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> { [] }
    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] { [:] }
}

@MainActor
struct ExportCoordinatorTests {

    // MARK: - Seed images

    /// The showcase sheet's transient background exists only in memory — the loader can never
    /// produce it from referenced file names, so the seed must reach the context's images.
    @Test func seedImagesReachTheRenderContext() {
        let row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 100, templateHeight: 100)
        var cache: [String: NSImage] = [:]
        let seeded = NSImage(size: NSSize(width: 2, height: 2))

        let context = RowRenderContext.load(
            row: row,
            localeCode: "en",
            from: EmptyRenderSource(),
            label: "test",
            cache: &cache,
            seedImages: [ShowcaseExportConfig.transientBackgroundKey: seeded]
        )

        #expect(context.images[ShowcaseExportConfig.transientBackgroundKey] === seeded)
        #expect(context.missingImageFileNames.isEmpty)
    }

    // MARK: - Row file naming

    @Test func rowFileNameIsZeroPadded() {
        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 100, templateHeight: 100)
        row.label = ""
        #expect(ExportCoordinator.rowFileName(row, index: 0) == "01.png")
        #expect(ExportCoordinator.rowFileName(row, index: 8) == "09.png")
        #expect(ExportCoordinator.rowFileName(row, index: 9) == "10.png")
        #expect(ExportCoordinator.rowFileName(row, index: 99) == "100.png")
    }

    @Test func rowFileNameIncludesLabelWhenPresent() {
        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 100, templateHeight: 100)
        row.label = "Onboarding"
        #expect(ExportCoordinator.rowFileName(row, index: 2) == "03_Onboarding.png")
        // Rows carry a default label ("Screenshot 1"), so the labelled form is the common case.
        let defaultLabelled = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 100, templateHeight: 100)
        #expect(ExportCoordinator.rowFileName(defaultLabelled, index: 0).hasPrefix("01_"))
    }

    /// Zero-padded numbering keeps Finder and the stores sorting exports in row order.
    @Test func rowFileNamesSortLexicographicallyInRowOrder() {
        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 100, templateHeight: 100)
        row.label = ""
        let names = (0..<12).map { ExportCoordinator.rowFileName(row, index: $0) }
        #expect(names == names.sorted())
    }

    // MARK: - Export folder bookmark

    @Test func bookmarkStartsEmpty() {
        let store = ExportFolderBookmark(defaults: makeIsolatedDefaults("empty"))
        #expect(!store.hasDestination)
        #expect(store.bookmarkData.isEmpty)
        #expect(store.displayPath.isEmpty)
        #expect(store.resolve() == nil)
    }

    @Test func savingAFolderMakesItResolvable() throws {
        let store = ExportFolderBookmark(defaults: makeIsolatedDefaults("save"))
        let dir = makeTemporaryDataDirectory(label: "export-bookmark")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(store.save(dir))
        #expect(store.hasDestination)
        #expect(store.displayPath.isEmpty == false)

        let resolved = try #require(store.resolve())
        #expect(resolved.standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test func clearForgetsTheDestination() {
        let store = ExportFolderBookmark(defaults: makeIsolatedDefaults("clear"))
        let dir = makeTemporaryDataDirectory(label: "export-bookmark-clear")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(store.save(dir))
        store.clear()
        #expect(!store.hasDestination)
        #expect(store.displayPath.isEmpty)
    }

    /// A bookmark that no longer resolves must be dropped, not left to fail on every export.
    @Test func unresolvableBookmarkIsCleared() {
        let defaults = makeIsolatedDefaults("stale")
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: ExportFolderBookmark.bookmarkKey)
        let store = ExportFolderBookmark(defaults: defaults)

        #expect(store.hasDestination)
        #expect(store.resolve() == nil)
        #expect(!store.hasDestination, "a bookmark that can't resolve should be forgotten")
    }

    /// A folder the user deleted is expected: forgotten, and filed as a breadcrumb rather than a Sentry event.
    @Test func deletedFolderIsForgottenAsAnExpectedFailure() throws {
        let store = ExportFolderBookmark(defaults: makeIsolatedDefaults("deleted"))
        let dir = makeTemporaryDataDirectory(label: "export-bookmark-deleted")
        #expect(store.save(dir))
        let stored = store.bookmarkData
        try FileManager.default.removeItem(at: dir)

        var isStale = false
        do {
            _ = try URL(resolvingBookmarkData: stored, options: ExportFolderService.bookmarkResolveOptions,
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
            Issue.record("a deleted folder's bookmark should not resolve")
        } catch {
            #expect(ExportFolderService.isExpectedResolveFailure(error) || ExportFolderService.bookmarkTargetIsGone(stored))
        }
        #expect(store.resolve() == nil)
        #expect(!store.hasDestination)
    }

    @Test func expectedResolveFailureLooksThroughUnderlyingErrors() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError),
        ])
        #expect(ExportFolderService.isExpectedResolveFailure(wrapped))
        #expect(ExportFolderService.isExpectedResolveFailure(CocoaError(.fileReadNoPermission)))
        #expect(!ExportFolderService.isExpectedResolveFailure(CocoaError(.fileReadCorruptFile)))
    }

    /// A bare 259 is expected only when the bookmark parses and names a folder that is gone.
    @Test func onlyAParseableBookmarkToAMissingFolderCountsAsGone() throws {
        #expect(!ExportFolderService.bookmarkTargetIsGone(Data([0x00, 0x01, 0x02, 0x03])))

        let dir = makeTemporaryDataDirectory(label: "export-bookmark-corrupt")
        let bookmark = try dir.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #expect(!ExportFolderService.bookmarkTargetIsGone(bookmark))
        try FileManager.default.removeItem(at: dir)
        #expect(ExportFolderService.bookmarkTargetIsGone(bookmark))
    }

    @Test func folderInTheTrashIsNotADestination() {
        #expect(ExportFolderService.isInTrash(URL(fileURLWithPath: "/Users/someone/.Trash/Shots")))
        #expect(ExportFolderService.isInTrash(URL(fileURLWithPath: "/Volumes/SSD/.Trashes/501/Shots")))
        #expect(!ExportFolderService.isInTrash(URL(fileURLWithPath: "/Users/someone/Desktop/Shots")))
    }

    /// Unplugging a drive must not cost the user their remembered export folder.
    @Test func folderOnUnmountedVolumeIsKept() {
        let defaults = makeIsolatedDefaults("unmounted")
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: ExportFolderBookmark.bookmarkKey)
        defaults.set("/Volumes/NoSuchVolume-\(UUID().uuidString)/Shots", forKey: ExportFolderBookmark.pathKey)
        let store = ExportFolderBookmark(defaults: defaults)

        #expect(store.resolve() == nil)
        #expect(store.hasDestination)
        #expect(!ExportFolderService.isOnUnmountedVolume("/Users/someone/Desktop/Shots"))
    }
}

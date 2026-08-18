import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ExportCoordinatorTests {

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

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "ExportCoordinatorTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func bookmarkStartsEmpty() {
        let store = ExportFolderBookmark(defaults: makeDefaults("empty"))
        #expect(!store.hasDestination)
        #expect(store.bookmarkData.isEmpty)
        #expect(store.displayPath.isEmpty)
        #expect(store.resolve() == nil)
    }

    @Test func savingAFolderMakesItResolvable() throws {
        let store = ExportFolderBookmark(defaults: makeDefaults("save"))
        let dir = makeTemporaryDataDirectory(label: "export-bookmark")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(store.save(dir))
        #expect(store.hasDestination)
        #expect(store.displayPath.isEmpty == false)

        let resolved = try #require(store.resolve())
        #expect(resolved.standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test func clearForgetsTheDestination() {
        let store = ExportFolderBookmark(defaults: makeDefaults("clear"))
        let dir = makeTemporaryDataDirectory(label: "export-bookmark-clear")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(store.save(dir))
        store.clear()
        #expect(!store.hasDestination)
        #expect(store.displayPath.isEmpty)
    }

    /// A bookmark that no longer resolves must be dropped, not left to fail on every export.
    @Test func unresolvableBookmarkIsCleared() {
        let defaults = makeDefaults("stale")
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: ExportFolderBookmark.bookmarkKey)
        let store = ExportFolderBookmark(defaults: defaults)

        #expect(store.hasDestination)
        #expect(store.resolve() == nil)
        #expect(!store.hasDestination, "a bookmark that can't resolve should be forgotten")
    }
}

import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct LocaleFolderImportPlannerTests {
    private let rowSize = CGSize(width: 1320, height: 2868)

    /// Builds a folder of empty files; the size probe reads the size from the file name instead.
    private func makeFolder(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocaleFolderImport-\(UUID().uuidString)")
        for path in paths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return root
    }

    private func probe(_ url: URL) -> CGSize? {
        url.lastPathComponent.contains("ipad") ? CGSize(width: 2064, height: 2752) : CGSize(width: 1320, height: 2868)
    }

    private func names(_ batch: LocaleFolderImportPlan.LocaleBatch?) -> [String] {
        batch?.files.map(\.lastPathComponent) ?? []
    }

    @Test func fastlaneDeliverTreeMapsStoreCodesToProjectLocales() throws {
        let folder = try makeFolder([
            "en-US/2_home.png", "en-US/10_settings.png", "en-US/1_ipad_home.png",
            "de-DE/1_home.png", "de-DE/2_settings.png",
            "fr-FR/1_home.png", "Previews/1.png",
        ])
        let plan = LocaleFolderImportPlanner.plan(
            folder: folder, projectLocaleCodes: ["en", "de"], rowSize: rowSize, pixelSize: probe
        )
        #expect(plan.batches.map(\.localeCode) == ["en", "de"])
        #expect(names(plan.batches.first) == ["2_home.png", "10_settings.png"], "Finder order, iPad shot skipped")
        #expect(names(plan.batches.last) == ["1_home.png", "2_settings.png"])
        #expect(plan.skippedForSize.map(\.lastPathComponent) == ["1_ipad_home.png"])
        #expect(plan.unmatchedLocaleFolders == ["fr-FR"], "Previews isn't a locale, so it isn't reported")
        #expect(plan.imageCount == 4)
    }

    @Test func supplyTreeFindsNestedScreenshots() throws {
        let folder = try makeFolder(["en-US/images/phoneScreenshots/1.png", "en-US/images/phoneScreenshots/2.png"])
        let plan = LocaleFolderImportPlanner.plan(folder: folder, projectLocaleCodes: ["en"], rowSize: rowSize, pixelSize: probe)
        #expect(names(plan.batches.first) == ["1.png", "2.png"])
    }

    @Test func flatFolderReadsTheLocaleFromFileNames() throws {
        let folder = try makeFolder(["01_en.png", "01_de-DE.png", "02_de-DE.png", "notes.txt", "cover.png"])
        let plan = LocaleFolderImportPlanner.plan(folder: folder, projectLocaleCodes: ["en", "de"], rowSize: rowSize, pixelSize: probe)
        #expect(names(plan.batches.first) == ["01_en.png"])
        #expect(names(plan.batches.last) == ["01_de-DE.png", "02_de-DE.png"])
    }

    @Test func mostSpecificProjectLocaleWins() {
        #expect(LocaleCodeMatcher.match("pt-BR", among: ["pt", "pt-BR"]) == "pt-BR")
        #expect(LocaleCodeMatcher.match("pt_PT", among: ["pt", "pt-BR"]) == "pt")
        #expect(LocaleCodeMatcher.match("EN-us", among: ["en-US"]) == "en-US")
        #expect(LocaleCodeMatcher.match("es-MX", among: ["en"]) == nil)
    }

    @Test func presetLocaleOffersTheBundledLanguage() {
        #expect(LocaleFolderImportPlanner.presetLocale(forFolderName: "fr-FR")?.code == "fr-FR")
        #expect(LocaleFolderImportPlanner.presetLocale(forFolderName: "de-DE")?.code == "de")
        #expect(LocaleFolderImportPlanner.presetLocale(forFolderName: "Previews") == nil)
    }
}

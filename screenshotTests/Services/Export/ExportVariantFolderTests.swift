import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

@MainActor
struct ExportVariantFolderTests {

    init() { BetaFeatures.shared.setABTesting(true, persist: false) }


    @Test func variantsExportIntoTheirOwnTopLevelFolders() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let variant = ScreenshotVariant(name: "Dark hero")

        let export = try await ExportService.exportAll(
            rows: [makeTestRow(label: "Phone", bgColor: .white), makeTestRow(label: "Phone", bgColor: .white, variantId: variant.id)],
            projectName: "VariantProject",
            to: tempDir,
            source: EmptyDiskRenderSource(),
            variants: [variant]
        )

        let topLevel = Set(export.fileURLs.map { url in
            url.path.replacingOccurrences(of: export.folderURL.path + "/", with: "")
                .split(separator: "/").first.map(String.init) ?? ""
        })
        #expect(topLevel == [String(localized: "Original"), "Dark hero"])
        for url in export.fileURLs {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func rowFolderNamesAreDedupedPerVariantFolder() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let variant = ScreenshotVariant(name: "Dark hero")
        let original = makeTestRow(label: "Phone", bgColor: .white)

        let export = try await ExportService.exportAll(
            rows: [original, makeTestRow(label: "Phone", bgColor: .white, variantId: variant.id)],
            projectName: "VariantProject",
            to: tempDir,
            source: EmptyDiskRenderSource(),
            variants: [variant]
        )

        let rowFolders = Set(export.fileURLs.map { $0.deletingLastPathComponent().lastPathComponent })
        #expect(rowFolders == [ExportFileNaming.exportFolderName(for: original)], "no \"(2)\" suffix across variant folders")
    }

    @Test func projectWithoutVariantsKeepsItsLayout() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let export = try await ExportService.exportAll(
            rows: [makeTestRow(label: "Phone", bgColor: .white)],
            projectName: "PlainProject",
            to: tempDir,
            source: EmptyDiskRenderSource(),
            variants: []
        )

        #expect(!export.fileURLs.isEmpty)
        // By path: `deletingLastPathComponent()` adds a trailing slash, so the URLs never compare equal.
        #expect(export.fileURLs.allSatisfy { $0.deletingLastPathComponent().path == export.folderURL.path })
    }
}

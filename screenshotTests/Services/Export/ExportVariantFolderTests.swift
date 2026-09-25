import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

@MainActor
struct ExportVariantFolderTests {

    init() { BetaFeatures.shared.setABTesting(true, persist: false) }


    private func makeRow(label: String, variantId: UUID? = nil) -> ScreenshotRow {
        ScreenshotRow(
            label: label,
            templates: [ScreenshotTemplate()],
            templateWidth: 200,
            templateHeight: 400,
            bgColor: .white,
            variantId: variantId
        )
    }

    @Test func variantsExportIntoTheirOwnTopLevelFolders() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let variant = ScreenshotVariant(name: "Dark hero")

        let export = try await ExportService.exportAll(
            rows: [makeRow(label: "Phone"), makeRow(label: "Phone", variantId: variant.id)],
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

        let export = try await ExportService.exportAll(
            rows: [makeRow(label: "Phone"), makeRow(label: "Phone", variantId: variant.id)],
            projectName: "VariantProject",
            to: tempDir,
            source: EmptyDiskRenderSource(),
            variants: [variant]
        )

        let rowFolders = Set(export.fileURLs.map { $0.deletingLastPathComponent().lastPathComponent })
        #expect(rowFolders == ["Phone"])
    }

    @Test func projectWithoutVariantsKeepsItsLayout() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let export = try await ExportService.exportAll(
            rows: [makeRow(label: "Phone")],
            projectName: "PlainProject",
            to: tempDir,
            source: EmptyDiskRenderSource(),
            variants: []
        )

        #expect(export.fileURLs.allSatisfy { $0.deletingLastPathComponent() == export.folderURL })
    }
}

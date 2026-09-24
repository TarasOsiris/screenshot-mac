import Foundation
@testable import Screenshot_Bro
import Testing

struct TemplateServiceTests {

    @Test func metadataDefaultsToExcludedWhenFileIsMissing() {
        let tempDir = makeTemporaryDataDirectory(label: "template-metadata-tests")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = TemplateService.loadMetadata(at: tempDir)

        #expect(metadata == ProjectTemplateMetadata(includeInReleaseBuild: false))
    }

    @Test func metadataRoundTripsExplicitReleaseFlag() throws {
        let tempDir = makeTemporaryDataDirectory(label: "template-metadata-tests")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadataURL = TemplateService.metadataURL(for: tempDir)
        let data = try JSONEncoder().encode(ProjectTemplateMetadata(includeInReleaseBuild: true))
        try data.write(to: metadataURL, options: .atomic)

        let metadata = TemplateService.loadMetadata(at: tempDir)

        #expect(metadata == ProjectTemplateMetadata(includeInReleaseBuild: true))
    }

    /// A template whose `project.json` won't decode reaches the user as "Failed to create project
    /// from template", and nothing before this fails — the suites that read the bundle skip an
    /// undecodable entry, so a hand-edited or regenerated template can ship broken. One shipped
    /// that way with a shape missing its `id`.
    @Test func everyBundledTemplateDecodes() throws {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        let entries = try FileManager.default.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var decoded = 0

        for entry in entries {
            let projectURL = entry.appendingPathComponent("project.json")
            guard let data = try? Data(contentsOf: projectURL) else { continue }
            let name = entry.lastPathComponent
            #expect(throws: Never.self, "Template '\(name)' does not decode") {
                _ = try PersistenceService.decoder.decode(ProjectData.self, from: data)
            }
            decoded += 1
        }

        #expect(decoded > 10, "Found only \(decoded) bundled templates — the bundle didn't load")
    }
}

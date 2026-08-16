import Foundation
import Testing
@testable import Screenshot_Bro

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
}

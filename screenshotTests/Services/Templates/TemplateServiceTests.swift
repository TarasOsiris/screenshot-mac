import CoreGraphics
import Foundation
import ImageIO
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

    private static func bundledProjects() throws -> [(name: String, project: ProjectData)] {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        let entries = try FileManager.default.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
        return try entries.compactMap { entry in
            guard let data = try? Data(contentsOf: entry.appendingPathComponent("project.json")) else { return nil }
            return (entry.lastPathComponent, try PersistenceService.decoder.decode(ProjectData.self, from: data))
        }
    }

    /// App Store search shows a screenshot ~390 px tall, so text under 2 % of the canvas height
    /// renders at 4–6 px there. Labels sized to a button or badge shape follow their container.
    @Test func bundledTemplateTextMeetsLegibilityFloor() throws {
        for (name, project) in try Self.bundledProjects() {
            for row in project.rows {
                let containers = row.shapes.filter { $0.type == .rectangle || $0.type == .circle }
                for shape in row.shapes where shape.type == .text && !(shape.text ?? "").isEmpty {
                    let center = CGPoint(x: shape.x + shape.width / 2, y: shape.y + shape.height / 2)
                    let isLabel = containers.contains {
                        CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).contains(center)
                            && $0.width * $0.height < 4 * shape.width * shape.height
                    }
                    guard !isLabel, let fontSize = shape.fontSize else { continue }
                    #expect(fontSize >= (0.02 * row.templateHeight).rounded(.up),
                            "\(name) '\(row.label)': \"\(shape.text ?? "")\" is \(fontSize)pt")
                }
            }
        }
    }

    /// The picker's device caption and filter come from this; a template that summarises to no
    /// device would vanish under every filter but "All".
    @Test func everyBundledTemplateSummarisesItsDevices() throws {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        for (name, _) in try Self.bundledProjects() {
            #expect(!TemplateService.deviceFamilies(ofTemplateAt: bundleURL.appendingPathComponent(name)).isEmpty, "\(name)")
        }
        #expect(TemplateService.deviceFamilies(ofTemplateAt: bundleURL.appendingPathComponent("amethyst")) == [.iphone, .android, .ipad])
    }

    /// Cards are 230–320 pt wide, so a 1× preview is upscaled and blurry on Retina.
    @Test func bundledTemplatePreviewsAreRetinaResolution() throws {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        for (name, _) in try Self.bundledProjects() {
            let previewURL = bundleURL.appendingPathComponent(name).appendingPathComponent(TemplateService.previewFileName)
            let source = try #require(CGImageSourceCreateWithURL(previewURL as CFURL, nil), "\(name) has no preview")
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            #expect(height >= 288, "\(name) preview is \(height) px tall")
        }
    }

    /// Spaced-out capitals ("F O R M A") break the moment a user retypes or translates them;
    /// tracking belongs in `letterSpacing`.
    @Test func bundledTemplateTextHasNoSpaceTracking() throws {
        let spacedLetters = try Regex(#"(?:\b\S ){3,}\S\b"#)
        for (name, project) in try Self.bundledProjects() {
            for row in project.rows {
                for shape in row.shapes where shape.type == .text {
                    let text = shape.text ?? ""
                    #expect(text.firstMatch(of: spacedLetters) == nil, "\(name): \"\(text)\"")
                }
            }
        }
    }
}

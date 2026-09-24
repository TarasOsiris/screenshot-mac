import Foundation
@testable import Screenshot_Bro
import Testing

/// The bundled templates and `Templates.bundle/shared/fonts` are one contract: a template stores
/// a font name, and `PersistenceService.copySharedFonts` has to find the file behind it. Nothing
/// but this suite fails when they drift — a template would just render in a fallback face.
struct SharedTemplateFontsTests {

    private func templatesBundleURL() throws -> URL {
        try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
    }

    private func sharedFontIdentityKeys() throws -> [String: Set<String>] {
        let sharedFontsURL = try #require(TemplateService.sharedFontsURL)
        let files = try FileManager.default.contentsOfDirectory(
            at: sharedFontsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, CustomFont.identityKeys(at: $0)) })
    }

    private func bundledTemplateProjects() throws -> [(name: String, data: ProjectData)] {
        let bundleURL = try templatesBundleURL()
        let entries = try FileManager.default.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return entries.compactMap { entry in
            guard let data = try? Data(contentsOf: entry.appendingPathComponent("project.json")),
                  let project = try? PersistenceService.decoder.decode(ProjectData.self, from: data) else {
                return nil
            }
            return (entry.lastPathComponent, project)
        }
    }

    @Test func theBundleShipsSharedFontsAndTemplates() throws {
        #expect(!(try sharedFontIdentityKeys()).isEmpty)
        #expect((try bundledTemplateProjects()).count > 10)
    }

    /// Every font a template names has to be resolvable: either the system supplies it, or one of
    /// the shared files claims it. An unmatched name means that template ships without its font.
    @Test func everyBundledTemplateFontIsASystemFamilyOrAShippedFile() throws {
        let identityKeys = try sharedFontIdentityKeys()
        let systemFamilies = PlatformFonts.familyNameSet

        for (name, project) in try bundledTemplateProjects() {
            for fontName in project.referencedFontNames() {
                let matched = identityKeys.values.contains { $0.contains(fontName) }
                #expect(
                    matched || systemFamilies.contains(fontName),
                    "Template '\(name)' names font '\(fontName)', which is neither a system family nor a shared font"
                )
            }
        }
    }

    /// No template needs every shared font — which is the whole reason copying all of them was
    /// waste. If one ever does, the filter has stopped saving anything and is pure risk.
    @Test func noBundledTemplateNeedsEverySharedFont() throws {
        let identityKeys = try sharedFontIdentityKeys()

        for (name, project) in try bundledTemplateProjects() {
            let referenced = project.referencedFontNames()
            let needed = identityKeys.filter { !$0.value.isDisjoint(with: referenced) }
            #expect(needed.count < identityKeys.count, "Template '\(name)' references every shared font")
        }
    }
}

import CoreText
import Foundation

/// A project's own fonts, registered for the duration of a render.
///
/// Rendering a project the editor does not have open would otherwise draw its custom-font text in
/// the system face — the exact failure `RowRenderContext.availableFontFamilies` exists to prevent,
/// because `CustomFontLibrary` registers by *active* project id.
///
/// Lifted from `ProjectThumbnailService.render`, which has been doing precisely this against
/// non-open projects since thumbnails shipped.
@MainActor
final class ProjectFontScope {
    /// Only the URLs this scope actually registered. Registering an already-registered URL returns
    /// `false`, and unregistering one somebody else registered would strip it from them — so this
    /// filter is the safety property, not a micro-optimisation.
    private let registeredURLs: [URL]
    private let fonts: [String: CustomFont]
    private let instances: [CustomFont]
    let availableFamilySet: Set<String>

    private init(registeredURLs: [URL], fontURLs: [URL]) {
        self.registeredURLs = registeredURLs
        self.fonts = Dictionary(
            uniqueKeysWithValues: fontURLs.compactMap { url in
                CustomFont.parseMetadata(at: url).map { ($0.fileName, $0) }
            }
        )
        self.instances = fontURLs.flatMap(CustomFont.allInstances(at:))
        // The cached set, not a fresh enumeration: enumerating installed families per render is
        // what made a batch of thumbnails slow.
        var families = PlatformFonts.familyNameSet
        for font in fonts.values {
            families.insert(font.familyName)
            families.insert(font.displayName)
        }
        self.availableFamilySet = families
    }

    /// nil when a font's bytes are not materialized yet (an iCloud placeholder), so a caller can
    /// refuse rather than render text in the wrong face.
    static func make(projectId: UUID) -> ProjectFontScope? {
        guard let fontURLs = loadFontURLs(projectId: projectId) else { return nil }
        return make(fontURLs: fontURLs)
    }

    /// For callers that already resolved the URLs and made their own decision about placeholders.
    static func make(fontURLs: [URL]) -> ProjectFontScope {
        var registered: [URL] = []
        for url in fontURLs where CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
            registered.append(url)
        }
        return ProjectFontScope(registeredURLs: registered, fontURLs: fontURLs)
    }

    /// Must wrap a **synchronous** render. `CustomFontRegistry.withTemporaryFonts` is a scoped swap
    /// restored by `defer`, so holding it across a suspension point would leave the process-wide
    /// registry pointing at this project while the editor's own canvas draws.
    func withResolvedFonts<R>(_ body: () -> R) -> R {
        CustomFontRegistry.withTemporaryFonts(fonts, instances: instances, perform: body)
    }

    func dispose() {
        for url in registeredURLs {
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Returns nil when any font file exists but its bytes cannot be read — see `make`.
    nonisolated static func loadFontURLs(projectId: UUID) -> [URL]? {
        let dir = PersistenceService.resourcesDir(projectId)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let fontURLs = files.filter { CustomFontLibrary.fontExtensions.contains($0.pathExtension.lowercased()) }
        for url in fontURLs where PersistenceService.readData(from: url) == nil {
            return nil
        }
        return fontURLs
    }
}

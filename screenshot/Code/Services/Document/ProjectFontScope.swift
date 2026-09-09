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

    /// Live scopes by project, so two concurrent checkouts of the same project share one
    /// registration. Without this the second registers nothing (`CTFontManagerRegisterFontsForURL`
    /// returns false for an already-registered URL, and only true URLs are recorded), so the first
    /// to finish would unregister the fonts out from under the other.
    private static var live: [UUID: (scope: ProjectFontScope, holders: Int)] = [:]
    private let projectId: UUID?

    private init(registeredURLs: [URL], fontURLs: [URL], projectId: UUID?) {
        self.projectId = projectId
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

    /// nil when a font's bytes are not materialized yet — a refusal, not a reason to render with
    /// somebody else's fonts. Shared with any other live scope for the same project.
    static func make(projectId: UUID) async -> ProjectFontScope? {
        if var entry = live[projectId] {
            entry.holders += 1
            live[projectId] = entry
            return entry.scope
        }
        // Detached because the resolve stats every font file, which blocks on the file provider for
        // a ubiquitous path — the same split `ProjectThumbnailService` already makes.
        guard let fontURLs = await Task.detached(operation: { loadFontURLs(projectId: projectId) }).value else {
            return nil
        }
        let scope = register(fontURLs: fontURLs, projectId: projectId)
        live[projectId] = (scope, 1)
        return scope
    }

    /// For callers that already resolved the URLs and made their own decision about placeholders.
    /// Unshared: the caller owns the registration for as long as it holds the scope.
    static func make(fontURLs: [URL]) -> ProjectFontScope {
        register(fontURLs: fontURLs, projectId: nil)
    }

    private static func register(fontURLs: [URL], projectId: UUID?) -> ProjectFontScope {
        var registered: [URL] = []
        for url in fontURLs where CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
            registered.append(url)
        }
        return ProjectFontScope(registeredURLs: registered, fontURLs: fontURLs, projectId: projectId)
    }

    /// Must wrap a **synchronous** render. `CustomFontRegistry.withTemporaryFonts` is a scoped swap
    /// restored by `defer`, so holding it across a suspension point would leave the process-wide
    /// registry pointing at this project while the editor's own canvas draws.
    func withResolvedFonts<R>(_ body: () -> R) -> R {
        CustomFontRegistry.withTemporaryFonts(fonts, instances: instances, perform: body)
    }

    func dispose() {
        if let projectId, var entry = Self.live[projectId] {
            entry.holders -= 1
            guard entry.holders <= 0 else {
                Self.live[projectId] = entry
                return
            }
            Self.live[projectId] = nil
        }
        for url in registeredURLs {
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Returns nil when any font file's bytes have not downloaded yet — see `make`. Blocks on the
    /// file provider per file, so it must not be called from the main actor.
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
        // A stat, not a read: the question is whether the bytes are here, and reading every font
        // file in full to answer it is a coordinated iCloud read per file.
        for url in fontURLs where PersistenceService.availability(of: url) != .present {
            return nil
        }
        return fontURLs
    }
}

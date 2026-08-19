#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreText
import Observation

/// User-imported font files: importing, registering with CoreText, and reclaiming files whose
/// family nothing references any more.
///
/// Its only tie to the document is the set of families the project's shapes actually use, and
/// that is passed in — `AppState` still owns the walk. The active project id is passed per call
/// rather than mirrored here, because a mirrored copy goes stale in the middle of a project
/// switch, which is exactly when these paths run.
@Observable
@MainActor
final class CustomFontLibrary {
    nonisolated static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

    /// fileName → CustomFont.
    private(set) var customFonts: [String: CustomFont] = [:]

    /// Families referenced at any point this session. A font the user has imported but not yet
    /// applied must survive the next autosave, so cleanup only removes families that were once
    /// in use — see `cleanupUnreferenced`.
    @ObservationIgnored private var everReferencedFontFamilies: Set<String> = []

    @ObservationIgnored private var cachedAvailableFamilySet: Set<String>?

    /// System families plus every registered custom family. A `RowRenderSource` requirement, so
    /// `AppState` forwards it.
    ///
    /// Resolved on first read, never in `init`: `AppState` is constructed before the first frame
    /// and nothing on that path reads this — only the canvas, the font picker and the renderers
    /// do — so the system font enumeration has no business blocking launch.
    private(set) var availableFamilySet: Set<String> {
        get {
            if let cachedAvailableFamilySet { return cachedAvailableFamilySet }
            let set = systemAndCustomFamilies()
            cachedAvailableFamilySet = set
            return set
        }
        set { cachedAvailableFamilySet = newValue }
    }

    @ObservationIgnored private var lastFontCleanupAt: Date = .distantPast

    /// Both parameters default to empty; a test that needs a font record without a parseable
    /// font file on disk constructs its own library rather than mutating a shared one.
    init(customFonts: [String: CustomFont] = [:], everReferenced: Set<String> = []) {
        self.customFonts = customFonts
        everReferencedFontFamilies = everReferenced
    }

    /// Takes the project id because instances are read back off the font files in that project's
    /// resources directory.
    func refreshAvailableFamilies(projectId: UUID?) {
        PlatformFonts.invalidateFamilyNameCache()
        let resourcesURL = projectId.map { PersistenceService.resourcesDir($0) }
        var instances: [CustomFont] = []
        if let resourcesURL {
            for font in customFonts.values {
                instances.append(contentsOf: CustomFont.allInstances(at: resourcesURL.appendingPathComponent(font.fileName)))
            }
        }
        availableFamilySet = systemAndCustomFamilies()
        CustomFontRegistry.update(with: customFonts, instances: instances)
    }

    /// Process-registered fonts (via CTFontManager) don't appear in the system family list, so
    /// add both family and display names.
    private func systemAndCustomFamilies() -> Set<String> {
        var families = PlatformFonts.familyNameSet
        for font in customFonts.values {
            families.insert(font.familyName)
            families.insert(font.displayName)
        }
        return families
    }

    // MARK: - Custom Fonts

    func loadCustomFonts(projectId activeId: UUID) {
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil) else { return }

        var changed = false
        for file in files where Self.fontExtensions.contains(file.pathExtension.lowercased()) {
            let fileName = file.lastPathComponent
            guard customFonts[fileName] == nil else { continue }
            if let font = registerFont(at: file) {
                customFonts[fileName] = font
                changed = true
            }
        }
        if changed { refreshAvailableFamilies(projectId: activeId) }
    }

    func unregisterCustomFonts(projectId activeId: UUID?) {
        guard let activeId else {
            customFonts.removeAll()
            everReferencedFontFamilies.removeAll()
            refreshAvailableFamilies(projectId: activeId)
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        for fileName in customFonts.keys {
            let url = resourcesURL.appendingPathComponent(fileName) as CFURL
            CTFontManagerUnregisterFontsForURL(url, .process, nil)
        }
        customFonts.removeAll()
        everReferencedFontFamilies.removeAll()
        refreshAvailableFamilies(projectId: activeId)
    }

    /// Imports a single font file or every font in a folder, opportunistically pulling in
    /// sibling family files when the sandbox allows parent-directory access.
    @discardableResult
    func importCustomFont(from url: URL, projectId activeId: UUID) -> ImportedCustomFontSelection? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var firstImportedFont: CustomFont?
        var firstFamily: String?

        if isDirectory {
            firstImportedFont = importFontsFromDirectory(url, activeId: activeId)
            firstFamily = firstImportedFont?.familyName
        } else if let primary = importFontFile(at: url, activeId: activeId) {
            firstImportedFont = primary
            firstFamily = primary.familyName
            importFamilySiblings(of: url, familyName: primary.familyName, activeId: activeId)
        }

        refreshAvailableFamilies(projectId: activeId)
        if let firstImportedFont, !isDirectory {
            return firstImportedFont.selectionResult()
        }
        guard let family = firstFamily else { return nil }
        return CustomFontRegistry.preferredSelection(for: family, in: customFonts)
    }

    // MARK: - Private import helpers

    private func importFontsFromDirectory(_ dirURL: URL, activeId: UUID) -> CustomFont? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { return nil }
        var firstImportedFont: CustomFont?
        for file in files where Self.fontExtensions.contains(file.pathExtension.lowercased()) {
            if let font = importFontFile(at: file, activeId: activeId), firstImportedFont == nil {
                firstImportedFont = font
            }
        }
        return firstImportedFont
    }

    /// Best-effort scan of `url`'s parent folder for other files with the same family name.
    /// Sandbox typically blocks directory access for files picked individually, so this
    /// silently no-ops in that case.
    private func importFamilySiblings(of url: URL, familyName: String, activeId: UUID) {
        let parent = url.deletingLastPathComponent()
        let fm = FileManager.default
        guard let siblings = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return }
        for sibling in siblings where Self.fontExtensions.contains(sibling.pathExtension.lowercased()) {
            guard sibling != url else { continue }
            guard customFonts[sibling.lastPathComponent] == nil else { continue }
            guard let metadata = parseFontMetadata(at: sibling), metadata.familyName == familyName else { continue }
            _ = importFontFile(at: sibling, activeId: activeId, preParsed: metadata)
        }
    }

    /// Copies the file into the project's resources dir and registers it. Pass `preParsed`
    /// to skip a redundant CT descriptor read when metadata is already known. Caller is
    /// responsible for invoking `refreshAvailableFamilies(projectId:)` once after a batch.
    private func importFontFile(at url: URL, activeId: UUID, preParsed: CustomFont? = nil) -> CustomFont? {
        let fileName = url.lastPathComponent
        let destURL = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        let fm = FileManager.default

        if !fm.fileExists(atPath: destURL.path) {
            do {
                try fm.copyItem(at: url, to: destURL)
            } catch {
                // The import silently no-ops and the project renders in a fallback face.
                CrashReportingService.report(.customFontCopyFailed, error: error, extra: ["extension": url.pathExtension])
                return nil
            }
        }
        if customFonts[fileName] == nil {
            if let preParsed {
                _ = CTFontManagerRegisterFontsForURL(destURL as CFURL, .process, nil)
                customFonts[fileName] = preParsed
            } else if let font = registerFont(at: destURL) {
                customFonts[fileName] = font
            }
        }
        return customFonts[fileName]
    }

    /// Per-file removal without refreshing the global font set. Call
    /// `refreshAvailableFamilies(projectId:)` once after a batch of removals.
    private func removeCustomFontFile(_ fileName: String, projectId activeId: UUID) {
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let url = resourcesURL.appendingPathComponent(fileName)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
        customFonts.removeValue(forKey: fileName)
    }

    // MARK: - Reference tracking & cleanup

    /// Removes any custom font file whose family is no longer referenced by any shape,
    /// but only if that family has previously been referenced. Without this guard, a
    /// family the user just imported (and not yet applied) would be deleted by the next
    /// debounced save.
    func cleanupUnreferenced(referenced: @autoclosure () -> Set<String>, projectId activeId: UUID) {
        guard !customFonts.isEmpty else { return }
        let referenced = referenced()
        everReferencedFontFamilies.formUnion(referenced)
        let toRemove = customFonts.filter { _, font in
            !referenced.contains(font.familyName) && everReferencedFontFamilies.contains(font.familyName)
        }
        guard !toRemove.isEmpty else { return }
        for fileName in toRemove.keys {
            removeCustomFontFile(fileName, projectId: activeId)
        }
        refreshAvailableFamilies(projectId: activeId)
    }

    /// Autosave-path variant: reclaiming unused font files only needs to happen
    /// eventually, so the full-document walk is throttled instead of running on
    /// every 0.3 s save tick. Quit (`saveAll`) and project switch still run the
    /// unthrottled cleanup.
    func cleanupUnreferencedThrottled(referenced: @autoclosure () -> Set<String>, projectId activeId: UUID) {
        guard !customFonts.isEmpty else { return }
        guard Date().timeIntervalSince(lastFontCleanupAt) > 30 else { return }
        lastFontCleanupAt = Date()
        cleanupUnreferenced(referenced: referenced(), projectId: activeId)
    }

    /// Rebuilds the in-session reference tracker from the loaded project so subsequent
    /// cleanup only removes fonts that were once used in this project.
    func seedReferenced(_ families: Set<String>) {
        everReferencedFontFamilies = families
    }

    private func registerFont(at url: URL) -> CustomFont? {
        // May fail if already registered — that's OK
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return CustomFont.parseMetadata(at: url)
    }

    private func parseFontMetadata(at url: URL) -> CustomFont? {
        CustomFont.parseMetadata(at: url)
    }
}

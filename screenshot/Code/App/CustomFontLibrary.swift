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
            let set = customFamilies(addedTo: PlatformFonts.familyNameSet)
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

    /// The one place the font tables are made current. `scan` supplies the file reads a load
    /// already did off the main actor; without one they happen here, which is why this takes
    /// the project id — instances are read back off the font files in its resources directory.
    func refreshAvailableFamilies(projectId: UUID?, from scan: CustomFontScan? = nil) {
        // Registration changes the process font set, so replace the shared cache instead of
        // clearing it — the next reader is usually the canvas or a renderer, on the main actor.
        let systemFamilies = scan?.systemFamilies ?? Set(PlatformFonts.systemFamilyNames)
        PlatformFonts.primeFamilyNameCache(systemFamilies)
        availableFamilySet = customFamilies(addedTo: systemFamilies)
        CustomFontRegistry.update(with: customFonts, instances: scan?.instances ?? readInstances(projectId: projectId))
    }

    /// Process-registered fonts (via CTFontManager) don't appear in the system family list, so
    /// add both family and display names.
    private func customFamilies(addedTo systemFamilies: Set<String>) -> Set<String> {
        var families = systemFamilies
        for font in customFonts.values {
            families.insert(font.familyName)
            families.insert(font.displayName)
        }
        return families
    }

    private func readInstances(projectId: UUID?) -> [CustomFont] {
        guard let projectId else { return [] }
        let resourcesURL = PersistenceService.resourcesDir(projectId)
        return customFonts.values.flatMap {
            CustomFont.allInstances(at: resourcesURL.appendingPathComponent($0.fileName))
        }
    }

    // MARK: - Custom Fonts

    func loadCustomFonts(projectId activeId: UUID) {
        let scan = CustomFontScan.run(
            resourcesURL: PersistenceService.resourcesDir(activeId),
            existing: Set(customFonts.keys)
        )
        guard !scan.newFonts.isEmpty else { return }
        customFonts.merge(scan.newFonts) { current, _ in current }
        refreshAvailableFamilies(projectId: activeId, from: scan)
    }

    /// Off-main sibling of `loadCustomFonts`. Registering a font mmaps the file, and in an
    /// iCloud project those bytes may still be in the cloud — that page-in blocked the main
    /// thread for seconds on reload and on project switch.
    func loadCustomFontsAsync(projectId activeId: UUID) async {
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let known = Set(customFonts.keys)
        let scan = await Task.detached(priority: .userInitiated) {
            CustomFontScan.run(resourcesURL: resourcesURL, existing: known)
        }.value

        guard !scan.newFonts.isEmpty else { return }
        // An import that landed while the scan ran isn't in its reads, so those are unusable.
        let importLanded = Set(customFonts.keys) != known
        customFonts.merge(scan.newFonts) { current, _ in current }
        refreshAvailableFamilies(projectId: activeId, from: importLanded ? nil : scan)
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
            guard let metadata = CustomFont.parseMetadata(at: sibling), metadata.familyName == familyName else { continue }
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
            let instances = Self.register(at: destURL)
            customFonts[fileName] = preParsed ?? instances.first
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

    /// Reclaims bundled template fonts that `PersistenceService.copySharedFonts` left in a project
    /// which never used them — 4.12 and earlier copied all of them into every template project.
    /// `cleanupUnreferenced`'s "was once referenced" guard exists to protect a user font imported
    /// but not yet applied, so it can never reach these; the file name is what tells them apart —
    /// it matches one we ship in `Templates.bundle/shared/fonts`. A user import that happens to
    /// share a shipped file name is reclaimed with them, and is re-importable.
    func reclaimUnusedSharedFonts(referenced: Set<String>, projectId activeId: UUID) {
        guard !customFonts.isEmpty, let sharedFontsURL = TemplateService.sharedFontsURL else { return }
        let shipped = Set(
            ((try? FileManager.default.contentsOfDirectory(
                at: sharedFontsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []).map(\.lastPathComponent)
        )
        guard !shipped.isEmpty else { return }
        let toRemove = customFonts.filter { fileName, font in
            shipped.contains(fileName) && !referenced.contains(font.familyName)
        }
        guard !toRemove.isEmpty else { return }
        for fileName in toRemove.keys {
            removeCustomFontFile(fileName, projectId: activeId)
        }
        CrashReportingService.breadcrumb(.project, "Reclaimed unused bundled fonts", data: ["count": toRemove.count])
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

    /// Registers a font file with the process and returns every named instance it exposes, the
    /// first being its primary face. Downloads first: registration mmaps the file, which stalls
    /// on an iCloud file whose bytes haven't materialized.
    nonisolated static func register(at url: URL) -> [CustomFont] {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        // May fail if already registered — that's OK
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return CustomFont.allInstances(at: url)
    }
}

/// Everything a font load does that touches the file system or CoreText, gathered so it can
/// run off the main actor: the directory listing, registration, and the descriptor reads —
/// all of which mmap files that an iCloud project may not have materialized yet.
nonisolated struct CustomFontScan: Sendable {
    /// Files registered by this scan (keyed by file name); already-known files are skipped.
    var newFonts: [String: CustomFont] = [:]
    /// Every named instance across all registered files, for `CustomFontRegistry`.
    var instances: [CustomFont] = []
    var systemFamilies: Set<String> = []

    static func run(resourcesURL: URL, existing: Set<String>) -> CustomFontScan {
        let files = (try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil))?
            .filter { CustomFontLibrary.fontExtensions.contains($0.pathExtension.lowercased()) } ?? []
        // Nothing new means nothing to apply, so don't pay for the reads below.
        guard files.contains(where: { !existing.contains($0.lastPathComponent) }) else { return CustomFontScan() }

        var scan = CustomFontScan()
        for file in files {
            let fileName = file.lastPathComponent
            guard !existing.contains(fileName) else {
                scan.instances.append(contentsOf: CustomFont.allInstances(at: file))
                continue
            }
            let instances = CustomFontLibrary.register(at: file)
            guard let font = instances.first else { continue }
            scan.newFonts[fileName] = font
            scan.instances.append(contentsOf: instances)
        }
        scan.systemFamilies = Set(PlatformFonts.systemFamilyNames)
        return scan
    }
}

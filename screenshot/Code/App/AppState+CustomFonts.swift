import SwiftUI
import CoreText

extension AppState {
    // MARK: - Custom Fonts

    func loadCustomFonts() {
        guard let activeId = activeProjectId else { return }
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
        if changed { refreshAvailableFontFamilies() }
    }

    func unregisterCustomFonts() {
        guard let activeId = activeProjectId else {
            customFonts.removeAll()
            everReferencedFontFamilies.removeAll()
            refreshAvailableFontFamilies()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        for fileName in customFonts.keys {
            let url = resourcesURL.appendingPathComponent(fileName) as CFURL
            CTFontManagerUnregisterFontsForURL(url, .process, nil)
        }
        customFonts.removeAll()
        everReferencedFontFamilies.removeAll()
        refreshAvailableFontFamilies()
    }

    /// Imports a single font file or every font in a folder, opportunistically pulling in
    /// sibling family files when the sandbox allows parent-directory access.
    @discardableResult
    func importCustomFont(from url: URL) -> ImportedCustomFontSelection? {
        guard let activeId = activeProjectId else { return nil }
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

        refreshAvailableFontFamilies()
        if let firstImportedFont, !isDirectory {
            return firstImportedFont.selectionResult()
        }
        guard let family = firstFamily else { return nil }
        return CustomFontRegistry.preferredSelection(for: family, in: customFonts)
    }

    func removeCustomFont(_ fileName: String) {
        removeCustomFontFile(fileName)
        refreshAvailableFontFamilies()
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
    /// responsible for invoking `refreshAvailableFontFamilies()` once after a batch.
    private func importFontFile(at url: URL, activeId: UUID, preParsed: CustomFont? = nil) -> CustomFont? {
        let fileName = url.lastPathComponent
        let destURL = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        let fm = FileManager.default

        if !fm.fileExists(atPath: destURL.path) {
            guard (try? fm.copyItem(at: url, to: destURL)) != nil else { return nil }
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
    /// `refreshAvailableFontFamilies()` once after a batch of removals.
    private func removeCustomFontFile(_ fileName: String) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let url = resourcesURL.appendingPathComponent(fileName)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
        customFonts.removeValue(forKey: fileName)
    }

    // MARK: - Reference tracking & cleanup

    /// Family names referenced by any shape (base or locale override). A `shape.fontName`
    /// like "Tinos" or "Playfair Display Italic" is resolved to its underlying family so
    /// that all variants of that family stay alive together.
    func allReferencedFontFamilies() -> Set<String> {
        var result = Set<String>()
        for row in rows {
            for shape in row.shapes {
                if let name = shape.fontName, !name.isEmpty {
                    result.insert(CustomFontRegistry.resolve(name).family)
                }
            }
        }
        for shapeOverrides in localeState.overrides.values {
            for override in shapeOverrides.values {
                if let name = override.fontName, !name.isEmpty {
                    result.insert(CustomFontRegistry.resolve(name).family)
                }
            }
        }
        return result
    }

    /// Removes any custom font file whose family is no longer referenced by any shape,
    /// but only if that family has previously been referenced. Without this guard, a
    /// family the user just imported (and not yet applied) would be deleted by the next
    /// debounced save.
    func cleanupUnreferencedFonts() {
        guard !customFonts.isEmpty else { return }
        let referenced = allReferencedFontFamilies()
        everReferencedFontFamilies.formUnion(referenced)
        let toRemove = customFonts.filter { _, font in
            !referenced.contains(font.familyName) && everReferencedFontFamilies.contains(font.familyName)
        }
        guard !toRemove.isEmpty else { return }
        for fileName in toRemove.keys {
            removeCustomFontFile(fileName)
        }
        refreshAvailableFontFamilies()
    }

    /// Rebuilds the in-session reference tracker from the loaded project so subsequent
    /// cleanup only removes fonts that were once used in this project.
    func seedReferencedFontFamiliesFromLoadedProject() {
        everReferencedFontFamilies = allReferencedFontFamilies()
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

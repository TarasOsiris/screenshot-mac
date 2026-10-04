import Foundation

nonisolated extension PersistenceService {
    @discardableResult
    static func copyProject(from sourceId: UUID, to destId: UUID) -> Bool {
        copyDirectory(from: projectDirectoryURL(sourceId), to: projectDirectoryURL(destId))
    }

    @discardableResult
    static func copyProjectFromURL(_ sourceURL: URL, to destId: UUID) -> Bool {
        guard copyDirectory(from: sourceURL, to: projectDirectoryURL(destId)) else { return false }
        TemplateService.stripTemplateArtifacts(in: projectDirectoryURL(destId))
        let loaded = loadProject(destId)
        copySharedFonts(to: destId, referencedBy: loaded)
        // Update modifiedAt so iCloud sync treats this as a fresh project
        if var data = loaded {
            data.modifiedAt = Date()
            try? saveProject(destId, data: data)
        }
        return true
    }

    /// A template's fonts live in the bundle's `shared/fonts`; the project gets its own copy so it
    /// survives iCloud sync and transfer. Only the ones it actually uses — copying all of them put
    /// ~1.2 MB of dead weight in every project, which nothing reclaimed. `data` is nil only when
    /// the copied `project.json` won't decode, where copying everything is the safe guess.
    private static func copySharedFonts(to projectId: UUID, referencedBy data: ProjectData?) {
        guard let sharedFontsURL = TemplateService.sharedFontsURL else { return }
        let fm = FileManager.default
        guard let fonts = try? fm.contentsOfDirectory(at: sharedFontsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let referenced = data?.referencedFontNames()
        let destResources = resourcesDir(projectId)
        try? fm.createDirectory(at: destResources, withIntermediateDirectories: true)
        for fontURL in fonts {
            if let referenced, referenced.isDisjoint(with: CustomFont.identityKeys(at: fontURL)) { continue }
            let destURL = destResources.appendingPathComponent(fontURL.lastPathComponent)
            if !fm.fileExists(atPath: destURL.path) {
                try? fm.copyItem(at: fontURL, to: destURL)
            }
        }
    }

    private static func copyDirectory(from src: URL, to dst: URL) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        do {
            // copyItem does not create intermediates, and a missing projects/ makes it fail with
            // an ENOENT that names the *source* — which reads as a broken template, not a
            // missing destination.
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst)
            return true
        } catch {
            // Silently yields an empty duplicated / template-instantiated project.
            CrashReportingService.report(.projectDirectoryCopyFailed, error: error)
            return false
        }
    }

    /// Safely replace a project directory at destination with source.
    /// Copies to a temp location first, then swaps, to avoid data loss if the copy fails.
    static func replaceProjectDir(_ id: UUID, from sourceRoot: URL, to destRoot: URL) throws {
        let fm = FileManager.default
        let srcDir = projectDirectoryURL(id, at: sourceRoot)
        let dstDir = projectDirectoryURL(id, at: destRoot)
        guard fm.fileExists(atPath: srcDir.path) else { return }

        if !fm.fileExists(atPath: dstDir.path) {
            try fm.copyItem(at: srcDir, to: dstDir)
        } else {
            // Copy to temp first, then swap — if copy fails, destination is preserved
            let tmpDir = dstDir.deletingLastPathComponent()
                .appendingPathComponent(id.uuidString + ".tmp", isDirectory: true)
            try? fm.removeItem(at: tmpDir)
            try fm.copyItem(at: srcDir, to: tmpDir)
            try? fm.removeItem(at: dstDir)
            try fm.moveItem(at: tmpDir, to: dstDir)
        }
    }
}

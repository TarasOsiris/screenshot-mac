#if DEBUG && os(macOS)
import AppKit
import Foundation

enum DebugTemplateService {
    private static let bookmarkKey = "debugTemplatesBundleBookmark"

    /// Source path hint for the NSOpenPanel.
    /// Relies on this file being at screenshot/Services/DebugTemplateService.swift
    /// and Templates.bundle being at screenshot/Templates.bundle.
    static var sourceTemplatesBundleURL: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // screenshot/
            .appendingPathComponent("Templates.bundle", isDirectory: true)
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale {
            if let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    @MainActor
    static func pickTemplatesBundleFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select Templates.bundle folder"
        panel.message = "Grant access to the Templates.bundle folder in the source tree so templates can be saved there."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = sourceTemplatesBundleURL.deletingLastPathComponent()
        panel.prompt = "Select"

        let response = CrashReportingService.withAppHangTrackingPaused { panel.runModal() }
        guard response == .OK, let url = panel.url else { return nil }

        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
        return url
    }

    @MainActor
    static func getTemplatesBundleURL() -> URL? {
        resolveBookmark() ?? pickTemplatesBundleFolder()
    }

    static func existingTemplateNames(at bundleURL: URL) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && fm.fileExists(atPath: url.appendingPathComponent("project.json").path)
            }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @MainActor
    static func saveProjectAsTemplate(projectId: UUID, templateName: String, bundleURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let destURL = bundleURL.appendingPathComponent(templateName, isDirectory: true)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }

        let sourceURL = PersistenceService.projectDataURL(projectId).deletingLastPathComponent()
        try fm.copyItem(at: sourceURL, to: destURL)

        let projectJSON = destURL.appendingPathComponent("project.json")
        let projectData = try PersistenceService.decoder.decode(ProjectData.self, from: Data(contentsOf: projectJSON))
        let usedFonts = referencedFontFamilies(in: projectData)

        moveFontsToShared(templateResources: destURL.appendingPathComponent("resources", isDirectory: true), bundleURL: bundleURL, usedFontFamilies: usedFonts)

        let metadataURL = TemplateService.metadataURL(for: destURL)
        let metadata = ProjectTemplateMetadata(includeInReleaseBuild: false)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)

        _ = generatePreviewImage(templateURL: destURL, projectData: projectData)

        print("[DebugTemplateService] Saved template '\(templateName)' to \(destURL.path)")
    }

    /// Regenerate preview images for all templates in the bundle.
    @MainActor
    static func regenerateAllPreviews(bundleURL: URL) {
        regeneratePreviews(bundleURL: bundleURL, missingOnly: false)
    }

    /// Regenerate preview images only for templates without an existing preview.png.
    @MainActor
    static func generateMissingPreviews(bundleURL: URL) {
        regeneratePreviews(bundleURL: bundleURL, missingOnly: true)
    }

    static func previewURL(for templateURL: URL) -> URL {
        templateURL.appendingPathComponent(TemplateService.previewFileName)
    }

    @MainActor
    private static func regeneratePreviews(bundleURL: URL, missingOnly: Bool) {
        let didAccess = bundleURL.startAccessingSecurityScopedResource()
        let allNames = existingTemplateNames(at: bundleURL)
        let names = missingOnly
            ? allNames.filter { !FileManager.default.fileExists(atPath: previewURL(for: bundleURL.appendingPathComponent($0, isDirectory: true)).path) }
            : allNames
        let total = names.count
        let label = missingOnly ? "missing" : "all"
        print("[DebugTemplateService] Starting preview regeneration for \(total) \(label) templates...")

        Task { @MainActor in
            defer { if didAccess { bundleURL.stopAccessingSecurityScopedResource() } }
            var succeeded = 0
            for (index, name) in names.enumerated() {
                let templateURL = bundleURL.appendingPathComponent(name, isDirectory: true)
                if generatePreviewImage(templateURL: templateURL) {
                    succeeded += 1
                }
                print("[DebugTemplateService] Progress: \(index + 1)/\(total)")
                await Task.yield()
            }
            print("[DebugTemplateService] Done: regenerated \(succeeded)/\(total) preview images")
        }
    }

    /// Generate a preview image by rendering actual row canvases and compositing them.
    @MainActor
    static func generatePreviewImage(templateURL: URL, projectData existingData: ProjectData? = nil) -> Bool {
        let templateName = templateURL.lastPathComponent
        let projectData: ProjectData
        if let existingData {
            projectData = existingData
        } else {
            let projectURL = templateURL.appendingPathComponent("project.json")
            guard let data = try? Data(contentsOf: projectURL) else {
                print("[DebugTemplateService] Failed to read project.json for '\(templateName)'")
                return false
            }
            do {
                projectData = try PersistenceService.decoder.decode(ProjectData.self, from: data)
            } catch {
                print("[DebugTemplateService] Failed to decode '\(templateName)': \(error)")
                return false
            }
        }
        guard let firstRow = projectData.rows.first(where: { !$0.templates.isEmpty }) else { return false }

        var row = firstRow
        row.templates = Array(row.templates.prefix(4))

        // Load only referenced resource images
        let resourcesURL = templateURL.appendingPathComponent("resources", isDirectory: true)
        var referencedNames = Set<String>()
        for shape in row.shapes {
            if let name = shape.displayImageFileName { referencedNames.insert(name) }
            if let name = shape.fillImageConfig?.fileName { referencedNames.insert(name) }
        }
        if let name = row.backgroundImageConfig.fileName { referencedNames.insert(name) }
        for tp in row.templates {
            if let name = tp.backgroundImageConfig.fileName { referencedNames.insert(name) }
        }
        var screenshotImages: [String: NSImage] = [:]
        for name in referencedNames {
            let fileURL = resourcesURL.appendingPathComponent(name)
            if let img = NSImage(contentsOf: fileURL) {
                screenshotImages[name] = img
            }
        }

        let localeState = projectData.localeState ?? .default
        let previewHeight: CGFloat = 144

        let totalWidth = row.templateWidth * CGFloat(row.templates.count)
        let scaledWidth = totalWidth * (previewHeight / row.templateHeight)

        let previewSize = NSSize(width: scaledWidth, height: previewHeight)

        let rowImage = RowRenderer.renderRowImage(
            row: row,
            screenshotImages: screenshotImages,
            localeState: localeState
        )

        // NSBitmapImageRep ensures 1x pixel output (lockFocus produces 2x on Retina)
        guard let bitmap = RowRenderer.bitmapRep(width: scaledWidth, height: previewHeight) else { return false }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        rowImage.draw(
            in: NSRect(origin: .zero, size: previewSize),
            from: NSRect(origin: .zero, size: rowImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let preview = NSImage(size: previewSize)
        preview.addRepresentation(bitmap)

        guard let pngData = ExportService.opaquePNGData(from: preview) else {
            print("[DebugTemplateService] Failed to encode preview PNG for '\(templateName)'")
            return false
        }
        let previewURL = Self.previewURL(for: templateURL)
        do {
            try pngData.write(to: previewURL, options: .atomic)
            print("[DebugTemplateService] Preview saved for '\(templateName)' (\(Int(previewSize.width))x\(Int(previewSize.height)))")
            return true
        } catch {
            print("[DebugTemplateService] Failed to write preview for '\(templateName)': \(error)")
            return false
        }
    }

    /// The names stored on shapes, plus the family each resolves to. Promotion runs with the
    /// authoring project's fonts registered, so the resolved family is available here and only
    /// widens the match — over-promoting to `shared/fonts` is harmless, under-promoting would
    /// strand a template without its font.
    private static func referencedFontFamilies(in projectData: ProjectData) -> Set<String> {
        let stored = projectData.referencedFontNames()
        return stored.union(stored.map { CustomFontRegistry.resolve($0).family })
    }

    /// Moves font files that are actually used by the project from a template's resources
    /// into the shared/fonts directory. Unused font files are simply removed.
    private static func moveFontsToShared(templateResources: URL, bundleURL: URL, usedFontFamilies: Set<String>) {
        let fm = FileManager.default
        let sharedFontsURL = bundleURL.appendingPathComponent(TemplateService.sharedFontsSubpath, isDirectory: true)
        try? fm.createDirectory(at: sharedFontsURL, withIntermediateDirectories: true)

        guard let files = try? fm.contentsOfDirectory(at: templateResources, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }

        for file in files where CustomFontLibrary.fontExtensions.contains(file.pathExtension.lowercased()) {
            let keys = CustomFont.identityKeys(at: file)
            if !keys.isEmpty && !usedFontFamilies.isDisjoint(with: keys) {
                let sharedDest = sharedFontsURL.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: sharedDest.path) {
                    _ = try? fm.copyItem(at: file, to: sharedDest)
                }
            }
            try? fm.removeItem(at: file)
        }
    }
}
#endif

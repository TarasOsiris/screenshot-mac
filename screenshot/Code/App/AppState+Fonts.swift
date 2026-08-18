import Foundation

// The document half of custom fonts: which families the project's shapes actually reference.
// Everything else — importing, CoreText registration, file reclamation — is CustomFontLibrary.
extension AppState {
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

    func loadCustomFonts() {
        guard let activeProjectId else { return }
        fonts.loadCustomFonts(projectId: activeProjectId)
    }

    func unregisterCustomFonts() {
        fonts.unregisterCustomFonts(projectId: activeProjectId)
    }

    func importCustomFont(from url: URL) -> ImportedCustomFontSelection? {
        guard let activeProjectId else { return nil }
        return fonts.importCustomFont(from: url, projectId: activeProjectId)
    }

    func removeCustomFont(_ fileName: String) {
        guard let activeProjectId else { return }
        fonts.removeCustomFont(fileName, projectId: activeProjectId)
    }

    /// Quit and project-switch path: reclaim now.
    func cleanupUnreferencedFonts() {
        guard let activeProjectId else { return }
        fonts.cleanupUnreferenced(referenced: allReferencedFontFamilies(), projectId: activeProjectId)
    }

    /// Autosave path: the full-document walk only needs to happen eventually, so it is throttled.
    /// The `@autoclosure` keeps the walk behind the 30s gate rather than running it every tick.
    func cleanupUnreferencedFontsThrottled() {
        guard let activeProjectId else { return }
        fonts.cleanupUnreferencedThrottled(referenced: allReferencedFontFamilies(), projectId: activeProjectId)
    }

    func seedReferencedFontFamiliesFromLoadedProject() {
        fonts.seedReferenced(allReferencedFontFamilies())
    }
}

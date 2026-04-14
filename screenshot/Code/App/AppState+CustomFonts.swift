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
            if let familyName = registerFont(at: file) {
                customFonts[fileName] = familyName
                changed = true
            }
        }
        if changed { refreshAvailableFontFamilies() }
    }

    func unregisterCustomFonts() {
        guard let activeId = activeProjectId else {
            customFonts.removeAll()
            refreshAvailableFontFamilies()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        for fileName in customFonts.keys {
            let url = resourcesURL.appendingPathComponent(fileName) as CFURL
            CTFontManagerUnregisterFontsForURL(url, .process, nil)
        }
        customFonts.removeAll()
        refreshAvailableFontFamilies()
    }

    @discardableResult
    func importCustomFont(from url: URL) -> String? {
        guard let activeId = activeProjectId else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let destURL = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            // Already imported — just make sure it's registered
            if customFonts[fileName] == nil, let familyName = registerFont(at: destURL) {
                customFonts[fileName] = familyName
            }
            return customFonts[fileName]
        }

        guard (try? fm.copyItem(at: url, to: destURL)) != nil else { return nil }
        if let familyName = registerFont(at: destURL) {
            customFonts[fileName] = familyName
            refreshAvailableFontFamilies()
            return familyName
        }
        return nil
    }

    func removeCustomFont(_ fileName: String) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let url = resourcesURL.appendingPathComponent(fileName)

        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
        customFonts.removeValue(forKey: fileName)
        refreshAvailableFontFamilies()
    }

    private func registerFont(at url: URL) -> String? {
        // May fail if already registered — that's OK
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String else {
            return nil
        }
        return familyName
    }

}

import Foundation

extension ScreenshotRow {
    /// The row background's config, then each template's.
    nonisolated var backgroundImageConfigs: [BackgroundImageConfig] {
        [backgroundImageConfig] + templates.map(\.backgroundImageConfig)
    }

    nonisolated mutating func updateBackgroundImageConfigs(_ body: (inout BackgroundImageConfig) -> Void) {
        body(&backgroundImageConfig)
        for index in templates.indices { body(&templates[index].backgroundImageConfig) }
    }

    /// The row with every background image resolved for `localeCode`. Idempotent — a resolved row
    /// has no table left — so the render seams (`RowRenderContext`, the `RowRenderer` entry points)
    /// each apply it and callers may hand them a base row.
    nonisolated func localizingBackgroundImages(to localeCode: String?) -> ScreenshotRow {
        guard hasAnyLocaleBackgroundImage else { return self }
        var resolved = self
        resolved.updateBackgroundImageConfigs { $0 = $0.localized(to: localeCode) }
        return resolved
    }

    /// The row with only `localeCode`'s background images left beside the base. The editor keeps
    /// the base loaded too, since a reset, revert or undo switches back to it without a reload.
    nonisolated func keepingBackgroundImages(forLocale localeCode: String) -> ScreenshotRow {
        guard hasAnyLocaleBackgroundImage else { return self }
        var kept = self
        kept.updateBackgroundImageConfigs { $0.localeImages = $0.localeImages.filter { $0.key == localeCode } }
        return kept
    }

    /// Whether `localeCode` paints a different background image than the base anywhere in this row.
    nonisolated func hasBackgroundImageOverride(forLocale localeCode: String) -> Bool {
        if backgroundStyle == .image, backgroundImageConfig.drawsOwnImage(forLocale: localeCode) { return true }
        return templates.contains {
            $0.overrideBackground && $0.backgroundStyle == .image && $0.backgroundImageConfig.drawsOwnImage(forLocale: localeCode)
        }
    }

    /// Whether `localeCode` has a background image entry here, painted or not.
    nonisolated func hasBackgroundImageEntry(forLocale localeCode: String) -> Bool {
        backgroundImageConfigs.contains { $0.localeImages[localeCode] != nil }
    }

    /// Drops `localeCode`'s background images and returns the files they referenced.
    nonisolated mutating func removeBackgroundImageOverrides(forLocale localeCode: String) -> [String] {
        var freed: [String] = []
        updateBackgroundImageConfigs { config in
            if let file = config.localeImages.removeValue(forKey: localeCode)?.fileName { freed.append(file) }
        }
        return freed
    }

    nonisolated mutating func rebaseBackgroundImages(to newBase: String, localeCodes: [String]) {
        updateBackgroundImageConfigs { $0.rebaseLocaleImages(to: newBase, localeCodes: localeCodes) }
    }

    /// Every background image file this row keeps, in every language.
    nonisolated var allBackgroundImageFileNames: [String] {
        backgroundImageConfigs.flatMap(\.allImageFileNames)
    }

    /// Hand-written rather than over `backgroundImageConfigs`: the editor canvas asks per body.
    nonisolated private var hasAnyLocaleBackgroundImage: Bool {
        !backgroundImageConfig.localeImages.isEmpty
            || templates.contains { !$0.backgroundImageConfig.localeImages.isEmpty }
    }
}

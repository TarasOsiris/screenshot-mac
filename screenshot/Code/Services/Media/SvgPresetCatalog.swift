import Foundation

struct SvgPreset: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sanitizedContent: String
}

enum SvgPresetCatalog {
    /// All bundled SVG presets, ordered by `localizedStandardCompare` so "Shape 10" follows "Shape 9".
    static let all: [SvgPreset] = loadAll()

    private static func loadAll() -> [SvgPreset] {
        guard let bundleURL = Bundle.main.url(forResource: "SvgPresets", withExtension: "bundle"),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: bundleURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        return urls
            .filter { $0.pathExtension.lowercased() == "svg" }
            .compactMap { url -> SvgPreset? in
                guard let content = SvgHelper.loadAndSanitize(from: url) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                return SvgPreset(id: name, displayName: name, sanitizedContent: content)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import os

/// The showcase sheet's settings as of its last export: app-wide, and without project row ids.
struct ShowcaseExportSettingsStore {
    var directory: URL = PersistenceService.localBaseURL.appendingPathComponent("showcase", isDirectory: true)

    var configURL: URL { directory.appendingPathComponent("ShowcaseSettings.json") }
    var backgroundImageURL: URL { directory.appendingPathComponent("ShowcaseBackground.png") }

    /// Serial so a later export's write can never be overtaken by an earlier one's.
    private nonisolated static let writeQueue = DispatchQueue(label: "xyz.tleskiv.screenshot.showcase-settings", qos: .utility)

    struct Restored {
        var config = ShowcaseExportConfig()
        var backgroundImage: NSImage?
    }

    func load() -> Restored {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONDecoder().decode(ShowcaseExportConfig.self, from: data) else {
            return Restored()
        }
        guard config.backgroundImageConfig.fileName == ShowcaseExportConfig.transientBackgroundKey else {
            return Restored(config: config)
        }
        let image = NSImage(contentsOf: backgroundImageURL)
        if image == nil {
            config.backgroundImageConfig.fileName = nil
        }
        return Restored(config: config, backgroundImage: image)
    }

    /// `backgroundImageChanged: false` skips re-encoding the image `load` returned.
    func save(config: ShowcaseExportConfig, backgroundImage: NSImage?, backgroundImageChanged: Bool) {
        guard let configData = try? JSONEncoder().encode(config) else { return }
        let configURL = configURL
        let imageURL = backgroundImageURL
        let cgImage = backgroundImageChanged
            ? backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            : nil
        Self.writeQueue.async {
            if backgroundImageChanged {
                Self.writeBackground(cgImage, to: imageURL)
            }
            Self.write(configData, to: configURL)
        }
    }

    func waitForPendingWrites() {
        Self.writeQueue.sync {}
    }

    private nonisolated static func writeBackground(_ cgImage: CGImage?, to url: URL) {
        guard let cgImage else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = ExportImageEncoder.pngData(fromCGImage: cgImage) else { return }
        write(data, to: url)
    }

    private nonisolated static func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.export.error("Failed to save showcase settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}

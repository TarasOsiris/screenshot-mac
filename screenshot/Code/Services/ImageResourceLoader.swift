import Foundation
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads a project's image resources from its own `resources/` directory.
///
/// Split out of `AppState` because the body was identical apart from one line: `AppState` could
/// only ever load the *active* project's images, which is exactly the assumption the MCP surface
/// has to stop making.
nonisolated enum ImageResourceLoader {

    /// Pass `cache` to avoid redundant disk reads across calls (e.g. during an export).
    static func loadFullResolution(
        fileNames: Set<String>,
        from resourcesURL: URL,
        cache: inout [String: NSImage]
    ) -> [String: NSImage] {
        var images: [String: NSImage] = [:]
        for fileName in fileNames {
            if let cached = cache[fileName] {
                images[fileName] = cached
                continue
            }
            autoreleasepool {
                let url = resourcesURL.appendingPathComponent(fileName)
                guard let image = NSImage(contentsOf: url) else {
                    // Callers render a hole rather than an error, so this is the only trace.
                    AppLogger.export.warning("Image resource failed to load: \(fileName, privacy: .public)")
                    return
                }
                #if os(macOS)
                // Point size equal to pixel dimensions, so SwiftUI uses full resolution at 1x
                // export rendering rather than being limited by DPI metadata. A new NSImage
                // avoids mutating the shared NSImageRep.
                if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                    let normalized = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
                    normalized.addRepresentation(rep)
                    images[fileName] = normalized
                    cache[fileName] = normalized
                } else {
                    images[fileName] = image
                    cache[fileName] = image
                }
                #else
                // UIImage already loads at native pixel resolution.
                images[fileName] = image
                cache[fileName] = image
                #endif
            }
        }
        return images
    }
}

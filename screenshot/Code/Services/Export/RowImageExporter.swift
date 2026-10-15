#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// Writes a row's screenshots as PNG files: rendered on the main actor one at a time, encoded and
/// written off it while the next renders.
enum RowImageExporter {
    /// One file per template, named by `fileName(templateIndex)`. Returns the URLs in template order.
    static func writePNGs(
        _ context: RowRenderContext,
        to folder: URL,
        fileName: (Int) -> String
    ) async throws -> [URL] {
        var urls: [URL] = []
        try await withThrowingTaskGroup(of: Void.self) { group in
            try await context.forEachTemplate { index, image in
                // The bitmap is pulled here, on the main actor: `NSImage` can't cross to the encoder.
                guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw ExportError.renderFailed
                }
                let url = folder.appendingPathComponent(fileName(index))
                urls.append(url)
                group.addTask {
                    guard let data = await ExportImageEncoder.opaquePNGDataOffMain(fromCGImage: bitmap) else {
                        throw ExportError.renderFailed
                    }
                    try data.write(to: url)
                }
            }
            try await group.waitForAll()
        }
        return urls
    }
}

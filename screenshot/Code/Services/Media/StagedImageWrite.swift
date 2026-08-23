#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum StagedImageWriteError: Error {
    /// The source could not be read, or the encode produced nothing.
    case noImageData
    /// Carries the message rather than the `Error`, so it crosses actors without a Sendable box.
    case writeFailed(String)
}

/// Where a staged resource's bytes come from. Not `Sendable`, deliberately: `.image` holds a
/// non-`Sendable` `NSImage`, and the flush pulls its bitmap one at a time on its own actor rather
/// than decoding every image up front — 20 full-resolution bitmaps at once is ~280 MB.
enum StagedImageSource {
    /// A file already on disk. The writer decides off-actor whether it can be copied verbatim.
    case file(URL)
    case image(NSImage)
}

/// Writes one imported screenshot into a project's resources folder, entirely off the caller's
/// actor. Both the encode and the write belong here: on an iCloud-backed resources folder the
/// atomic write is the slowest step of an import, so offloading only the encode would leave most
/// of the main-thread stall in place (SCREENSHOT-BRO-W).
nonisolated enum StagedImageWriter {
    /// Injection seam for the failing-write test, defaulted so no mutable global is needed.
    typealias WriteData = @Sendable (Data, URL) throws -> Void

    static let defaultWrite: WriteData = { data, url in
        try data.write(to: url, options: .atomic)
    }

    /// Copies the source when it is already a PNG — on APFS that is a clone, so none of the
    /// (typically ~14 MB) bytes are read or rewritten — and transcodes anything else. Sniffing the
    /// real type here rather than trusting the extension keeps a JPEG named `.png` from being
    /// copied verbatim into a file the loader would then fail to decode.
    @concurrent static func persist(
        copying source: URL,
        to destination: URL,
        write: WriteData = defaultWrite
    ) async throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw StagedImageWriteError.noImageData
        }
        if CGImageSourceGetType(imageSource) as String? == UTType.png.identifier {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return
            } catch {
                throw StagedImageWriteError.writeFailed(error.localizedDescription)
            }
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw StagedImageWriteError.noImageData
        }
        try persistSync(encoding: cgImage, to: destination, write: write)
    }

    @concurrent static func persist(
        encoding cgImage: CGImage,
        to destination: URL,
        write: WriteData = defaultWrite
    ) async throws {
        try persistSync(encoding: cgImage, to: destination, write: write)
    }

    /// Already off-actor by the time either entry point calls this, so the synchronous encoder is
    /// the right one — routing through `pngDataOffMain` would only add a hop per image.
    private static func persistSync(encoding cgImage: CGImage, to destination: URL, write: WriteData) throws {
        guard let data = ExportImageEncoder.pngData(fromCGImage: cgImage) else {
            throw StagedImageWriteError.noImageData
        }
        do {
            try write(data, destination)
        } catch {
            throw StagedImageWriteError.writeFailed(error.localizedDescription)
        }
    }
}

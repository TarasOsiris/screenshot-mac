#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import UniformTypeIdentifiers

/// The `NSOpenPanel` calls that three views used to make inline. Views own presentation, not
/// file access, and each site carried its own copy of the same "iOS import is deferred to a
/// follow-up" comment — so when that branch is written it now has one home instead of three.
///
/// `SvgHelper.pickImageOrSvg()` is the same pattern in this layer and stays where it is; it
/// returns a sanitized SVG or an image, which is `SvgHelper`'s own concern rather than a picker's.
@MainActor
enum FilePicker {

    /// Font files, or a folder of them. Picking a folder imports every variant (Bold, Italic,
    /// BoldItalic…) in one gesture — the sandbox grants access to the chosen folder's contents.
    static func pickFontFilesOrFolder() -> [URL] {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = String(localized: "Pick a font file or a folder containing all variants")
        guard CrashReportingService.withAppHangTrackingPaused({ panel.runModal() }) == .OK else { return [] }
        return panel.urls
        #else
        // iOS: custom-font import via fileImporter is deferred to a follow-up.
        return []
        #endif
    }

    /// A single raster image, already read through the security-scoped URL.
    static func pickImage() async -> NSImage? {
        #if os(macOS)
        guard let url = pickFile(ofType: .image) else { return nil }
        return await NSImage.fromSecurityScopedURLOffMain(url)
        #else
        // iPad routes image selection through ImageSourceMenu (Photo Library / Camera / Files).
        return nil
        #endif
    }

    /// The raw text of a single `.svg` file. Not sanitized — callers run it through `SvgHelper`.
    static func pickSvgText() async -> String? {
        #if os(macOS)
        guard let url = pickFile(ofType: UTType(filenameExtension: "svg") ?? .xml),
              let data = await Data.fromSecurityScopedURLOffMain(url) else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        // iPad: SVG file import via fileImporter is deferred; paste still works.
        return nil
        #endif
    }

    #if os(macOS)
    private static func pickFile(ofType contentType: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard CrashReportingService.withAppHangTrackingPaused({ panel.runModal() }) == .OK else { return nil }
        return panel.url
    }
    #endif
}

import SwiftUI

enum ImageResourceIO {
    static let defaultWriteData: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
    static var writeData: (Data, URL) throws -> Void = defaultWriteData
}

/// One image handed to a batch import. `sourceURL` is present only when the caller read the image
/// off disk (the MCP `import_screenshots` tool), which is what lets the writer copy an
/// already-PNG file verbatim; drag-and-drop yields an `NSImage` with no durable originating file.
struct ImageImportSource {
    let image: NSImage
    var sourceURL: URL?
}

/// How a screenshot reached the document, as the `source` dimension on `screenshots_imported`.
/// Raw values are our own vocabulary, never user content. Getting an image in is the defining
/// action of the app, and until 4.9 only the row-level batch drop reported it — so 859 exported
/// images produced one import event.
enum ImageImportOrigin: String, CaseIterable {
    /// Multiple files dropped on a row, fanned out across its templates.
    case dropRow = "drop_row"
    /// A single image dropped on empty canvas, becoming a new image shape.
    case dropCanvas = "drop_canvas"
    /// A single image dropped onto an existing device or image shape.
    case dropShape = "drop_shape"
    /// Photos / Camera / Files on iOS, and the double-tap or context-menu picker.
    case picker
    /// The macOS open panel.
    case panel
    /// Pasted from the system pasteboard.
    case paste
    case mcp
    /// A folder whose subfolders or file names say which locale each screenshot belongs to.
    case folder
    /// DEBUG-only simulator capture. Analytics is off in DEBUG, so this never ships —
    /// it exists so the path is labelled rather than silently inheriting the default.
    case simulator
}

/// Which locale variant an import writes into.
///
/// `.active` is what the editor wants: the locale the switcher is on. Anything driving the app
/// from outside — MCP above all — needs to say so explicitly instead, because the active locale
/// is invisible to it. Importing eight Spanish screenshots while the switcher happened to sit on
/// German filed them all as `de-DE`, reported `imported: 8`, and left `es-ES` falling back to the
/// base English images with nothing anywhere reporting a problem.
enum ImageImportLocale {
    /// Whatever the locale switcher is on. The editor's behaviour.
    case active
    /// The base image every locale falls back to.
    case base
    /// One named locale, regardless of what the UI is showing.
    case locale(String)
}

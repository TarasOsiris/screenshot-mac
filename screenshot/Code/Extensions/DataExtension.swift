import Foundation

nonisolated extension Data {
    /// Unpadded base64url (RFC 4648 §5) — the encoding JWT segments and the MCP bearer token use.
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    /// The bytes behind a user-picked, security-scoped URL, read off the main actor. A file the
    /// user picks can live on iCloud Drive or a network volume, where the read blocks in `read(2)`
    /// until the file materializes — on the main actor that is an app hang (SCREENSHOT-BRO-1C).
    /// Callers get `Data` rather than a decoded image because `NSImage` isn't Sendable;
    /// `NSImage(data:)` on the caller's actor matches `NSImage(contentsOf:)`, DPI-derived `size`
    /// included. `@concurrent` is load-bearing — see the concurrency note in CLAUDE.md.
    @concurrent static func fromSecurityScopedURLOffMain(_ url: URL) async -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

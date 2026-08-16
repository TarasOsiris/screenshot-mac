import Foundation

nonisolated extension Data {
    /// Unpadded base64url (RFC 4648 §5) — the encoding JWT segments and the MCP bearer token use.
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }
}

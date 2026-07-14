import OSLog

nonisolated enum AppLogger {
    private static let subsystem = "xyz.tleskiv.screenshot"

    static let store = Logger(subsystem: subsystem, category: "Store")
    static let export = Logger(subsystem: subsystem, category: "Export")
    static let translation = Logger(subsystem: subsystem, category: "Translation")
    static let mcp = Logger(subsystem: subsystem, category: "MCP")
}

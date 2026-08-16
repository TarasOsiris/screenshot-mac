import OSLog

nonisolated enum AppLogger {
    private static let subsystem = "xyz.tleskiv.screenshot"

    static let store = Logger(subsystem: subsystem, category: "Store")
    static let export = Logger(subsystem: subsystem, category: "Export")
    static let translation = Logger(subsystem: subsystem, category: "Translation")
    static let mcp = Logger(subsystem: subsystem, category: "MCP")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let sync = Logger(subsystem: subsystem, category: "Sync")
    static let upload = Logger(subsystem: subsystem, category: "Upload")
    static let media = Logger(subsystem: subsystem, category: "Media")
}

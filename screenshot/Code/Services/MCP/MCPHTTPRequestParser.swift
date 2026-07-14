#if DEBUG && os(macOS)
import Foundation

nonisolated struct MCPHTTPRequestHead {
    let method: String
    let target: String
    let httpVersion: String
    /// Keys lowercased; duplicate headers joined with ", ".
    let headers: [String: String]

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var path: String {
        target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? target
    }

    var contentLength: Int? {
        // Negative values must read as absent, not pass through: Data.prefix/removeFirst
        // trap on negative lengths, so a hostile "Content-Length: -1" would crash the app.
        header("content-length")
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .flatMap { $0 >= 0 ? $0 : nil }
    }

    var hasTransferEncoding: Bool {
        header("transfer-encoding") != nil
    }

    var wantsClose: Bool {
        header("connection")?.lowercased().contains("close") ?? false
    }
}

enum MCPHTTPParseError: Error {
    case malformedRequestLine
    case malformedHeader
}

nonisolated enum MCPHTTPRequestParser {
    static let headerTerminator = Data("\r\n\r\n".utf8)
    static let maxHeaderBytes = 16 * 1024

    /// Range of the CRLFCRLF terminator, or nil if the head is still incomplete.
    static func headerEndRange(in data: Data) -> Range<Data.Index>? {
        data.range(of: headerTerminator)
    }

    static func parseHead(_ data: Data) throws -> MCPHTTPRequestHead {
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw MCPHTTPParseError.malformedRequestLine }

        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/") else {
            throw MCPHTTPParseError.malformedRequestLine
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw MCPHTTPParseError.malformedHeader }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw MCPHTTPParseError.malformedHeader }
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }

        return MCPHTTPRequestHead(
            method: String(parts[0]),
            target: String(parts[1]),
            httpVersion: String(parts[2]),
            headers: headers
        )
    }
}
#endif

#if DEBUG && os(macOS)
import Foundation
import MCP
import SwiftUI

enum MCPToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
    case notFound(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            "Unknown tool: \(name)"
        case .missingArgument(let key):
            "Missing required argument: \(key)"
        case .invalidArgument(let key, let why):
            "Invalid argument '\(key)': \(why)"
        case .notFound(let what):
            "\(what) not found — call get_project for current ids"
        case .failed(let message):
            message
        }
    }
}

/// Typed access to a tool call's `arguments` dictionary.
struct MCPArguments {
    private let raw: [String: Value]

    init(_ raw: [String: Value]?) {
        self.raw = raw ?? [:]
    }

    func string(_ key: String) -> String? {
        raw[key]?.stringValue
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.isEmpty else { throw MCPToolError.missingArgument(key) }
        return value
    }

    func uuid(_ key: String) throws -> UUID {
        guard let uuid = try optionalUUID(key) else {
            throw MCPToolError.missingArgument(key)
        }
        return uuid
    }

    func optionalUUID(_ key: String) throws -> UUID? {
        guard let value = string(key), !value.isEmpty else { return nil }
        guard let uuid = UUID(uuidString: value) else {
            throw MCPToolError.invalidArgument(key, "not a UUID: \(value)")
        }
        return uuid
    }

    func double(_ key: String) -> Double? {
        switch raw[key] {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }

    func int(_ key: String) -> Int? {
        switch raw[key] {
        case .int(let i): i
        case .double(let d): Int(exactly: d)
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? {
        raw[key]?.boolValue
    }

    func stringArray(_ key: String) -> [String]? {
        raw[key]?.arrayValue.map { $0.compactMap(\.stringValue) }
    }

    func objectArray(_ key: String) -> [MCPArguments]? {
        raw[key]?.arrayValue.map { $0.compactMap { $0.objectValue.map(MCPArguments.init) } }
    }

    func object(_ key: String) -> MCPArguments? {
        raw[key]?.objectValue.map(MCPArguments.init)
    }

    func has(_ key: String) -> Bool {
        raw[key] != nil && raw[key] != .null
    }

    func color(_ key: String) throws -> CodableColor? {
        guard let hex = string(key) else { return nil }
        guard let color = CodableColor(hexString: hex) else {
            throw MCPToolError.invalidArgument(key, "expected #RRGGBB or #RRGGBBAA, got \(hex)")
        }
        return color
    }

    func enumValue<E: RawRepresentable>(_ key: String, _ type: E.Type) throws -> E? where E.RawValue == String {
        guard let value = string(key) else { return nil }
        guard let parsed = E(rawValue: value) else {
            throw MCPToolError.invalidArgument(key, "unsupported value: \(value)")
        }
        return parsed
    }
}

/// JSON-Schema builders for tool input schemas.
nonisolated enum MCPSchema {
    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    static func string(_ description: String) -> Value {
        .object(["type": "string", "description": .string(description)])
    }

    static func string(_ description: String, oneOf: [String]) -> Value {
        .object([
            "type": "string",
            "description": .string(description),
            "enum": .array(oneOf.map(Value.string)),
        ])
    }

    static func number(_ description: String) -> Value {
        .object(["type": "number", "description": .string(description)])
    }

    static func integer(_ description: String) -> Value {
        .object(["type": "integer", "description": .string(description)])
    }

    static func boolean(_ description: String) -> Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    static func array(of items: Value, _ description: String) -> Value {
        .object([
            "type": "array",
            "description": .string(description),
            "items": items,
        ])
    }
}

enum MCPResultEncoding {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// Standard success result: pretty JSON text plus the same payload as structured content.
    /// Payloads must encode as JSON objects — the spec requires structuredContent to be one,
    /// so list results are wrapped in envelopes (e.g. `["projects": …]`) at the call site.
    static func result<T: Encodable>(_ payload: T) throws -> CallTool.Result {
        let data = try encoder.encode(payload)
        let structured: Value? = try JSONDecoder().decode(Value.self, from: data)
        return CallTool.Result(
            content: [.text(String(decoding: data, as: UTF8.self))],
            structuredContent: structured
        )
    }
}
#endif

#if os(macOS)
import Foundation
import MCP

enum MCPToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
    case notFound(String)
    case unreadableFiles(String)
    /// A business-rule or setup condition the caller could have checked for (no active project,
    /// ASC not configured, nothing matched the requested filters) — expected, not ours.
    case expected(String)
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
        case .unreadableFiles(let message):
            message
        case .expected(let message):
            message
        case .failed(let message):
            message
        }
    }

    /// A malformed or stale request, or an expected state/business-rule condition the caller
    /// could have checked for — the agent's mistake or current app state, not ours — so it stays
    /// breadcrumb-only rather than opening a Sentry issue. `unreadableFiles` is here for privacy
    /// too: its message names the user's paths (a sandbox read *or* write denial), which must
    /// never reach a report. Only `.failed` — something that should have worked and didn't —
    /// still opens one, or these drown the real bugs (SCREENSHOT-BRO-G).
    var isClientError: Bool {
        switch self {
        case .unknownTool, .missingArgument, .invalidArgument, .notFound, .unreadableFiles, .expected: true
        case .failed: false
        }
    }

    /// The same error, attributed to one operation of a batch.
    func inOperation(_ index: Int, _ tool: String) -> MCPToolError {
        let prefix = "operations[\(index)]"
        switch self {
        case .unknownTool(let name): return .invalidArgument("\(prefix).tool", "\(name) is not an editing tool")
        case .missingArgument(let key): return .missingArgument("\(prefix).arguments.\(key)")
        case .invalidArgument(let key, let why): return .invalidArgument("\(prefix).arguments.\(key)", why)
        case .notFound(let what): return .notFound("\(what) (\(prefix), \(tool))")
        case .unreadableFiles(let message): return .unreadableFiles("\(prefix) (\(tool)): \(message)")
        case .expected(let message): return .expected("\(prefix) (\(tool)): \(message)")
        case .failed(let message): return .failed("\(prefix) (\(tool)): \(message)")
        }
    }
}

/// Typed access to a tool call's `arguments` dictionary.
struct MCPArguments {
    private let raw: [String: Value]
    /// A handler reading a key outside the schema is a silent no-op for every client, so DEBUG traps on it.
    private let declared: [String: Value]?

    init(_ raw: [String: Value]?, schema: Value? = nil) {
        self.raw = raw ?? [:]
        self.declared = schema?.schemaProperties
    }

    private func value(_ key: String) -> Value? {
        assert(declared == nil || declared?[key] != nil, "MCP handler reads \"\(key)\", which its schema does not declare")
        return raw[key]
    }

    /// The schema of `key`'s elements, for arguments nested in an array.
    private func itemSchema(_ key: String) -> Value? {
        declared?[key]?.schemaItems
    }

    func string(_ key: String) -> String? {
        value(key)?.stringValue
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

    func uuidArray(_ key: String) throws -> [UUID]? {
        try stringArray(key)?.map { value in
            guard let uuid = UUID(uuidString: value) else {
                throw MCPToolError.invalidArgument(key, "not a UUID: \(value)")
            }
            return uuid
        }
    }

    func optionalUUID(_ key: String) throws -> UUID? {
        guard let value = string(key), !value.isEmpty else { return nil }
        guard let uuid = UUID(uuidString: value) else {
            throw MCPToolError.invalidArgument(key, "not a UUID: \(value)")
        }
        return uuid
    }

    func double(_ key: String) -> Double? {
        switch value(key) {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }

    func int(_ key: String) -> Int? {
        switch value(key) {
        case .int(let i): i
        case .double(let d): Int(exactly: d)
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? {
        value(key)?.boolValue
    }

    func stringArray(_ key: String) -> [String]? {
        value(key)?.arrayValue.map { $0.compactMap(\.stringValue) }
    }

    func objectArray(_ key: String) -> [MCPArguments]? {
        let schema = itemSchema(key)
        return value(key)?.arrayValue.map { $0.compactMap { $0.objectValue.map { MCPArguments($0, schema: schema) } } }
    }

    /// Unlike `objectArray`, rejects a non-array value or any non-object element instead of dropping it.
    func strictObjectArray(_ key: String) throws -> [MCPArguments]? {
        guard has(key) else { return nil }
        guard let elements = value(key)?.arrayValue else {
            throw MCPToolError.invalidArgument(key, "expected an array of objects")
        }
        return try elements.map { element in
            guard let object = element.objectValue else {
                throw MCPToolError.invalidArgument(key, "every element must be an object")
            }
            return MCPArguments(object, schema: itemSchema(key))
        }
    }

    func object(_ key: String) -> MCPArguments? {
        value(key)?.objectValue.map { MCPArguments($0, schema: declared?[key]) }
    }

    var rawValues: [String: Value] { raw }

    /// Given at all, a value or an explicit `null`.
    func isPresent(_ key: String) -> Bool {
        value(key) != nil
    }

    /// An explicit `null`, which some fields take to mean "remove".
    func isNull(_ key: String) -> Bool {
        value(key) == .null
    }

    func has(_ key: String) -> Bool {
        value(key).map { $0 != .null } ?? false
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

extension Value {
    /// A JSON-Schema object's declared properties; nil for a free-form object.
    nonisolated var schemaProperties: [String: Value]? { objectValue?["properties"]?.objectValue }

    /// A JSON-Schema array's element schema.
    nonisolated var schemaItems: Value? { objectValue?["items"] }
}

/// Checks a call's arguments against the tool's own input schema before any handler runs, so a
/// misspelled key or a wrong-typed value is an error rather than a silently skipped edit.
/// `null` always passes: handlers treat it as "not provided" (`MCPArguments.has`).
nonisolated enum MCPArgumentValidator {
    static func validate(_ arguments: [String: Value]?, against schema: Value) throws {
        try validateObject(arguments ?? [:], schema: schema, path: "")
    }

    private static func validateObject(_ object: [String: Value], schema: Value, path: String) throws {
        guard let properties = schema.schemaProperties else { return }
        for key in object.keys.sorted() {
            let keyPath = path.isEmpty ? key : "\(path).\(key)"
            guard let property = properties[key] else {
                let accepted = properties.keys.sorted().joined(separator: ", ")
                throw MCPToolError.invalidArgument(keyPath, "unknown argument; accepted: \(accepted)")
            }
            if let value = object[key] {
                try validateValue(value, schema: property, path: keyPath)
            }
        }
    }

    private static func validateValue(_ value: Value, schema: Value, path: String) throws {
        guard value != .null, let spec = schema.objectValue, let type = spec["type"]?.stringValue else { return }
        switch type {
        case "string":
            guard let string = value.stringValue else { throw mismatch(path, "a string") }
            if let allowed = spec["enum"]?.arrayValue?.compactMap(\.stringValue), !allowed.contains(string) {
                throw MCPToolError.invalidArgument(path, "must be one of \(allowed.joined(separator: ", ")), got \(string)")
            }
        case "number":
            switch value {
            case .int, .double: break
            default: throw mismatch(path, "a number")
            }
        case "integer":
            switch value {
            case .int: break
            case .double(let double) where Int(exactly: double) != nil: break
            default: throw mismatch(path, "an integer")
            }
        case "boolean":
            guard value.boolValue != nil else { throw mismatch(path, "a boolean") }
        case "array":
            guard let elements = value.arrayValue else { throw mismatch(path, "an array") }
            if let items = schema.schemaItems {
                for (index, element) in elements.enumerated() {
                    try validateValue(element, schema: items, path: "\(path)[\(index)]")
                }
            }
        case "object":
            guard let object = value.objectValue else { throw mismatch(path, "an object") }
            try validateObject(object, schema: schema, path: path)
        default:
            break
        }
    }

    private static func mismatch(_ path: String, _ expected: String) -> MCPToolError {
        .invalidArgument(path, "expected \(expected)")
    }
}

/// JSON-Schema builders for tool input schemas.
nonisolated enum MCPSchema {
    static func object(_ properties: [String: Value], required: [String] = [], description: String? = nil) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
        ]
        if let description {
            schema["description"] = .string(description)
        }
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
        // Compact: the payload also goes out as structuredContent.
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// The same encoding as `result`, as a bare `Value`. Lets a job retain its terminal payload
    /// without the registry having to know any tool's result type.
    static func value<T: Encodable>(_ payload: T) throws -> Value {
        try JSONDecoder().decode(Value.self, from: encoder.encode(payload))
    }

    /// Standard success result: JSON text plus the same payload as structured content.
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

    static func result<T: Encodable>(_ payload: T, pngImage: Data) throws -> CallTool.Result {
        let data = try encoder.encode(payload)
        let structured: Value? = try JSONDecoder().decode(Value.self, from: data)
        return CallTool.Result(
            content: [
                .text(String(decoding: data, as: UTF8.self)),
                .image(data: pngImage.base64EncodedString(), mimeType: "image/png"),
            ],
            structuredContent: structured
        )
    }
}
#endif

import MCP

/// Typed accessors over a `tools/call` argument bag (`[String: Value]`). Keeps each tool's
/// `execute` free of repetitive `Value` unwrapping and gives uniform errors for missing/mistyped
/// arguments. (UUID *parsing* lives in `KanvasMCPGateway` — the single validation site — so these
/// accessors deal only in primitives.)
struct Arguments {
    let raw: [String: Value]

    init(_ raw: [String: Value]?) { self.raw = raw ?? [:] }

    /// A required string argument. Throws if absent or non-string.
    func string(_ key: String) throws -> String {
        guard let value = raw[key] else { throw ArgumentError.missing(key) }
        guard let string = value.stringValue else { throw ArgumentError.wrongType(key, expected: "string") }
        return string
    }

    /// An optional string argument; `nil` when absent or JSON null. Throws when the key is
    /// present with a non-string value — silently dropping a mistyped argument would make the
    /// model believe it was applied.
    func optionalString(_ key: String) throws -> String? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        guard let string = value.stringValue else {
            throw ArgumentError.wrongType(key, expected: "string")
        }
        return string
    }

    /// A required number argument (accepts JSON int or double). Throws if absent or non-numeric.
    func double(_ key: String) throws -> Double {
        guard let value = raw[key] else { throw ArgumentError.missing(key) }
        if let double = value.doubleValue { return double }
        if let int = value.intValue { return Double(int) }
        throw ArgumentError.wrongType(key, expected: "number")
    }

    /// An optional boolean argument; `nil` when absent or JSON null. Throws when the key is
    /// present with a non-boolean value — same loud-failure contract as `optionalString`:
    /// silently dropping a mistyped flag would make the model believe it was applied.
    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        guard let bool = value.boolValue else {
            throw ArgumentError.wrongType(key, expected: "boolean")
        }
        return bool
    }

    /// An optional number argument; `nil` when absent or JSON null. Throws when the key is
    /// present with a non-numeric value — same loud-failure contract as `optionalString`.
    func optionalDouble(_ key: String) throws -> Double? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        if let double = value.doubleValue { return double }
        if let int = value.intValue { return Double(int) }
        throw ArgumentError.wrongType(key, expected: "number")
    }
}

/// Argument-decoding failure, surfaced to the model as the tool's error text.
enum ArgumentError: Error, CustomStringConvertible {
    case missing(String)
    case wrongType(String, expected: String)

    var description: String {
        switch self {
        case let .missing(key): "Missing required argument: \(key)"
        case let .wrongType(key, expected): "Argument '\(key)' must be a \(expected)"
        }
    }
}

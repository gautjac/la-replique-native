import Foundation

/// A heterogeneous JSON value — used for tool input schemas and `tool_use`
/// arguments, where the shape is only known at runtime.
///
/// Conforms to the `ExpressibleBy*Literal` protocols so a JSON Schema can be
/// written inline as a Swift literal:
///
/// ```swift
/// let schema: JSONValue = [
///     "type": "object",
///     "properties": ["title": ["type": "string"]],
///     "required": ["title"],
/// ]
/// ```
public indirect enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:            try c.encodeNil()
        case .bool(let v):     try c.encode(v)
        case .int(let v):      try c.encode(v)
        case .double(let v):   try c.encode(v)
        case .string(let v):   try c.encode(v)
        case .array(let v):    try c.encode(v)
        case .object(let v):   try c.encode(v)
        }
    }

    // MARK: Convenience accessors

    /// The wrapped string, if this is a `.string`.
    public var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }

    /// The wrapped integer; coerces from `.double` and numeric `.string`.
    public var intValue: Int? {
        switch self {
        case .int(let v):    return v
        case .double(let v): return Int(v)
        case .string(let v): return Int(v)
        default:             return nil
        }
    }

    /// The wrapped double; coerces from `.int` and numeric `.string`.
    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v):    return Double(v)
        case .string(let v): return Double(v)
        default:             return nil
        }
    }

    /// The wrapped bool, if this is a `.bool`.
    public var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }

    /// The wrapped array, if this is an `.array`.
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v } else { return nil } }

    /// The wrapped dictionary, if this is an `.object`.
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v } else { return nil } }

    /// Key lookup on `.object` values; nil otherwise.
    public subscript(key: String) -> JSONValue? { objectValue?[key] }
}

// MARK: - Literal conformances

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}
extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

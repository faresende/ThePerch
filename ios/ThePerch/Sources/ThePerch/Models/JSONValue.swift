import Foundation

/// A flexible JSON value enum that handles arbitrary JSON structures.
/// Supports null, bool, int, double, string, array, and object types.
///
/// `nonisolated` so its Codable + Equatable conformances are usable
/// from the off-main `JSONValueDecoder` predecode path. JSONValue is
/// a value type with no shared state, so it's safe outside MainActor.
nonisolated enum JSONValue: Equatable, Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Codable Conformance

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }

    // MARK: - Convenience Accessors

    /// Returns the value as a Bool, or nil if not a bool.
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the value as an Int, or nil if not an int.
    var intValue: Int? {
        if case .int(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the value as a Double, or nil if not a double.
    var doubleValue: Double? {
        if case .double(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the value as a String, or nil if not a string.
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the value as an array of JSONValue, or nil if not an array.
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the value as a dictionary of [String: JSONValue], or nil if not an object.
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    /// Returns true if the value is null.
    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    /// Returns the numeric value as a Double, regardless of whether stored as int or double.
    var numberValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    // MARK: - Convenience Constructors

    /// Creates a number JSONValue from a Double.
    static func number(_ value: Double) -> JSONValue {
        .double(value)
    }

    /// Creates a number JSONValue from an Int.
    static func number(_ value: Int) -> JSONValue {
        .int(value)
    }
}

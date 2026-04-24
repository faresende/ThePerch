import Foundation

/// Decodes `Decodable` types directly from a `JSONValue` enum tree,
/// skipping the JSONEncoder → Data → JSONDecoder round-trip.
/// ~2x faster per-decode vs the encode/decode path.
enum JSONValueDecoder {

    /// Decodes a `Decodable` type from a `JSONValue`.
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) -> T? {
        let decoder = _JSONValueDecoder(value: value)
        return try? T(from: decoder)
    }
}

// MARK: - Internal Decoder

private struct _JSONValueDecoder: Decoder {
    let value: JSONValue
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let dict) = value else {
            throw DecodingError.typeMismatch([String: JSONValue].self, .init(
                codingPath: codingPath, debugDescription: "Expected object, got \(value)"))
        }
        return KeyedDecodingContainer(_KeyedContainer<Key>(dict: dict, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let arr) = value else {
            throw DecodingError.typeMismatch([JSONValue].self, .init(
                codingPath: codingPath, debugDescription: "Expected array, got \(value)"))
        }
        return _UnkeyedContainer(array: arr, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _SingleValueContainer(value: value, codingPath: codingPath)
    }
}

// MARK: - Keyed Container

private struct _KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dict: [String: JSONValue]
    var codingPath: [CodingKey]
    var allKeys: [Key] { dict.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { dict[key.stringValue] != nil }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let val = dict[key.stringValue] else { return true }
        return val == .null
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try unwrap(key).toBool(codingPath + [key])
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try unwrap(key).toString(codingPath + [key])
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try unwrap(key).toDouble(codingPath + [key])
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        Float(try unwrap(key).toDouble(codingPath + [key]))
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try unwrap(key).toInt(codingPath + [key])
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        Int8(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        Int16(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        Int32(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        Int64(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        UInt(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        UInt8(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        UInt16(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        UInt32(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        UInt64(try unwrap(key).toInt(codingPath + [key]))
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let val = try unwrap(key)
        return try decodeValue(type, from: val, codingPath: codingPath + [key])
    }

    func nestedContainer<NK: CodingKey>(keyedBy type: NK.Type, forKey key: Key) throws -> KeyedDecodingContainer<NK> {
        let val = try unwrap(key)
        guard case .object(let nested) = val else {
            throw DecodingError.typeMismatch([String: JSONValue].self, .init(
                codingPath: codingPath + [key], debugDescription: "Expected object"))
        }
        return KeyedDecodingContainer(_KeyedContainer<NK>(dict: nested, codingPath: codingPath + [key]))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let val = try unwrap(key)
        guard case .array(let arr) = val else {
            throw DecodingError.typeMismatch([JSONValue].self, .init(
                codingPath: codingPath + [key], debugDescription: "Expected array"))
        }
        return _UnkeyedContainer(array: arr, codingPath: codingPath + [key])
    }

    func superDecoder() throws -> Decoder {
        _JSONValueDecoder(value: .object(dict), codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        _JSONValueDecoder(value: try unwrap(key), codingPath: codingPath + [key])
    }

    private func unwrap(_ key: Key) throws -> JSONValue {
        guard let val = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(
                codingPath: codingPath, debugDescription: "Key '\(key.stringValue)' not found"))
        }
        return val
    }
}

// MARK: - Unkeyed Container

private struct _UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [JSONValue]
    var codingPath: [CodingKey]
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }
    var currentIndex: Int = 0

    private mutating func next() throws -> JSONValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(JSONValue.self, .init(
                codingPath: codingPath, debugDescription: "Unkeyed container exhausted"))
        }
        let val = array[currentIndex]
        currentIndex += 1
        return val
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        if array[currentIndex] == .null {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try next().toBool(codingPath) }
    mutating func decode(_ type: String.Type) throws -> String { try next().toString(codingPath) }
    mutating func decode(_ type: Double.Type) throws -> Double { try next().toDouble(codingPath) }
    mutating func decode(_ type: Float.Type) throws -> Float { Float(try next().toDouble(codingPath)) }
    mutating func decode(_ type: Int.Type) throws -> Int { try next().toInt(codingPath) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { Int8(try next().toInt(codingPath)) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { Int16(try next().toInt(codingPath)) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { Int32(try next().toInt(codingPath)) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { Int64(try next().toInt(codingPath)) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { UInt(try next().toInt(codingPath)) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { UInt8(try next().toInt(codingPath)) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { UInt16(try next().toInt(codingPath)) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { UInt32(try next().toInt(codingPath)) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { UInt64(try next().toInt(codingPath)) }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let val = try next()
        return try decodeValue(type, from: val, codingPath: codingPath)
    }

    mutating func nestedContainer<NK: CodingKey>(keyedBy type: NK.Type) throws -> KeyedDecodingContainer<NK> {
        let val = try next()
        guard case .object(let dict) = val else {
            throw DecodingError.typeMismatch([String: JSONValue].self, .init(
                codingPath: codingPath, debugDescription: "Expected object"))
        }
        return KeyedDecodingContainer(_KeyedContainer<NK>(dict: dict, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let val = try next()
        guard case .array(let arr) = val else {
            throw DecodingError.typeMismatch([JSONValue].self, .init(
                codingPath: codingPath, debugDescription: "Expected array"))
        }
        return _UnkeyedContainer(array: arr, codingPath: codingPath)
    }

    mutating func superDecoder() throws -> Decoder {
        _JSONValueDecoder(value: try next(), codingPath: codingPath)
    }
}

// MARK: - Single Value Container

private struct _SingleValueContainer: SingleValueDecodingContainer {
    let value: JSONValue
    var codingPath: [CodingKey]

    func decodeNil() -> Bool { value == .null }
    func decode(_ type: Bool.Type) throws -> Bool { try value.toBool(codingPath) }
    func decode(_ type: String.Type) throws -> String { try value.toString(codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try value.toDouble(codingPath) }
    func decode(_ type: Float.Type) throws -> Float { Float(try value.toDouble(codingPath)) }
    func decode(_ type: Int.Type) throws -> Int { try value.toInt(codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { Int8(try value.toInt(codingPath)) }
    func decode(_ type: Int16.Type) throws -> Int16 { Int16(try value.toInt(codingPath)) }
    func decode(_ type: Int32.Type) throws -> Int32 { Int32(try value.toInt(codingPath)) }
    func decode(_ type: Int64.Type) throws -> Int64 { Int64(try value.toInt(codingPath)) }
    func decode(_ type: UInt.Type) throws -> UInt { UInt(try value.toInt(codingPath)) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { UInt8(try value.toInt(codingPath)) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { UInt16(try value.toInt(codingPath)) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { UInt32(try value.toInt(codingPath)) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { UInt64(try value.toInt(codingPath)) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decodeValue(type, from: value, codingPath: codingPath)
    }
}

// MARK: - JSONValue Conversion Helpers

private extension JSONValue {
    func toBool(_ path: [CodingKey]) throws -> Bool {
        if case .bool(let v) = self { return v }
        throw DecodingError.typeMismatch(Bool.self, .init(codingPath: path, debugDescription: "Expected Bool, got \(self)"))
    }

    func toString(_ path: [CodingKey]) throws -> String {
        if case .string(let v) = self { return v }
        throw DecodingError.typeMismatch(String.self, .init(codingPath: path, debugDescription: "Expected String, got \(self)"))
    }

    func toDouble(_ path: [CodingKey]) throws -> Double {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default:
            throw DecodingError.typeMismatch(Double.self, .init(codingPath: path, debugDescription: "Expected number, got \(self)"))
        }
    }

    func toInt(_ path: [CodingKey]) throws -> Int {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        default:
            throw DecodingError.typeMismatch(Int.self, .init(codingPath: path, debugDescription: "Expected number, got \(self)"))
        }
    }
}

// MARK: - Special Type Handling (Date, URL, etc.)

/// ISO8601 formatter matching the existing JSONDecoder's .iso8601 strategy.
private let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// Fallback without fractional seconds.
private let iso8601FormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// Final fallback for ISO-shaped strings that omit a timezone suffix
/// ("2026-04-24T00:00:00"). Some producers (e.g. the Oura pipeline
/// writing sleep_duration midnight stamps) do this. We treat those as
/// local-time wall clocks rather than dropping the whole record.
private let iso8601FormatterNaive: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .iso8601)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
}()

/// Decodes a value, handling special types (Date, URL, Data, Decimal) that don't
/// natively decode from JSONValue, then falling back to the standard Decoder protocol.
private func decodeValue<T: Decodable>(_ type: T.Type, from value: JSONValue, codingPath: [CodingKey]) throws -> T {
    // Handle optionals: if the value is null, try to decode nil
    if value == .null {
        // For Optional types, return nil through the decoder
        let decoder = _JSONValueDecoder(value: value, codingPath: codingPath)
        return try T(from: decoder)
    }

    // Date: parse from ISO8601 string (matches .iso8601 decoding strategy)
    if type == Date.self {
        if case .string(let str) = value {
            if let date = iso8601Formatter.date(from: str)
                ?? iso8601FormatterNoFrac.date(from: str)
                ?? iso8601FormatterNaive.date(from: str) {
                guard let decodedDate = date as? T else {
                    throw DecodingError.typeMismatch(T.self, .init(
                        codingPath: codingPath,
                        debugDescription: "Failed to decode Date as \(T.self)"
                    ))
                }
                return decodedDate
            }
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Invalid date: \(str)"))
        }
        // Also handle numeric timestamps
        if case .double(let ts) = value {
            let date = Date(timeIntervalSince1970: ts)
            guard let decodedDate = date as? T else {
                throw DecodingError.typeMismatch(T.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Failed to decode Date as \(T.self)"
                ))
            }
            return decodedDate
        }
        if case .int(let ts) = value {
            let date = Date(timeIntervalSince1970: Double(ts))
            guard let decodedDate = date as? T else {
                throw DecodingError.typeMismatch(T.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Failed to decode Date as \(T.self)"
                ))
            }
            return decodedDate
        }
        throw DecodingError.typeMismatch(Date.self, .init(codingPath: codingPath, debugDescription: "Expected date string"))
    }

    // URL: parse from string
    if type == URL.self {
        if case .string(let str) = value, let url = URL(string: str) {
            guard let decodedURL = url as? T else {
                throw DecodingError.typeMismatch(T.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Failed to decode URL as \(T.self)"
                ))
            }
            return decodedURL
        }
        throw DecodingError.typeMismatch(URL.self, .init(codingPath: codingPath, debugDescription: "Expected URL string"))
    }

    // Decimal
    if type == Decimal.self {
        switch value {
        case .double(let v):
            let decimal = Decimal(v)
            guard let decodedDecimal = decimal as? T else {
                throw DecodingError.typeMismatch(T.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Failed to decode Decimal as \(T.self)"
                ))
            }
            return decodedDecimal
        case .int(let v):
            let decimal = Decimal(v)
            guard let decodedDecimal = decimal as? T else {
                throw DecodingError.typeMismatch(T.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Failed to decode Decimal as \(T.self)"
                ))
            }
            return decodedDecimal
        case .string(let s):
            if let d = Decimal(string: s) {
                guard let decodedDecimal = d as? T else {
                    throw DecodingError.typeMismatch(T.self, .init(
                        codingPath: codingPath,
                        debugDescription: "Failed to decode Decimal as \(T.self)"
                    ))
                }
                return decodedDecimal
            }
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Invalid decimal: \(s)"))
        default:
            throw DecodingError.typeMismatch(Decimal.self, .init(codingPath: codingPath, debugDescription: "Expected number"))
        }
    }

    // For all other Decodable types, recurse through the decoder
    let decoder = _JSONValueDecoder(value: value, codingPath: codingPath)
    return try T(from: decoder)
}

import Foundation

// Pangolin runs on SQLite or PostgreSQL. Depending on the database, computed columns
// come back as `true`/`false`, `0`/`1` or even strings, and the API is still pre-release.
// These helpers decode such values tolerantly and turn a mismatched type into `nil`
// instead of failing the whole response.

extension KeyedDecodingContainer {
    func lenientBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: key) {
            switch v.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key), v.isFinite { return Int(v) }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Int(v) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Double(v) }
        return nil
    }

    func lenientString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return String(v) }
        return nil
    }

    /// Decodes an array, skipping elements that fail to decode.
    func lenientArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        guard var nested = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [T] = []
        while !nested.isAtEnd {
            if let value = try? nested.decode(T.self) {
                result.append(value)
            } else {
                _ = try? nested.decode(Skip.self)
            }
        }
        return result
    }
}

private struct Skip: Decodable {}

extension Date {
    /// Pangolin returns timestamps as Unix seconds (logs) or milliseconds (invites, expirations).
    public init(pangolinTimestamp value: Double) {
        self = value > 100_000_000_000
            ? Date(timeIntervalSince1970: value / 1000)
            : Date(timeIntervalSince1970: value)
    }

    /// Parses ISO-8601 strings with or without fractional seconds, or numeric timestamps.
    public init?(pangolinString value: String) {
        if let number = Double(value) {
            self.init(pangolinTimestamp: number)
            return
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) {
            self = date
            return
        }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: value) {
            self = date
            return
        }
        return nil
    }
}

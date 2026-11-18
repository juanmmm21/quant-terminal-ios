import Foundation

/// The API is Python: ISO-8601 with microseconds (`.465818+00:00`) or a `Z`. Apple's
/// `ISO8601DateFormatter` understands milliseconds only, so fractions are trimmed to three digits.
public enum QuantDates {
    public static func parse(_ text: String) -> Date? {
        var normalized = text
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...].prefix { $0.isNumber }
            let rest = text[text.index(dot, offsetBy: fraction.count + 1)...]
            let millis = String((fraction + "000").prefix(3))
            normalized = String(text[..<dot]) + "." + millis + rest
        }
        if !normalized.hasSuffix("Z"), normalized.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) == nil {
            normalized += "Z"  // naive timestamps from the API are UTC
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: normalized) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: normalized)
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date \(text)")
            }
            return date
        }
        return decoder
    }
}

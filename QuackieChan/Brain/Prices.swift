import Foundation

/// Finds prices in text read off the screen: "$8,000", "8.000,00 kr.", "€ 1 299", "USD 49.99".
nonisolated enum Prices {
    private static let symbols = #"(?:\$|€|£|¥|USD|EUR|GBP|DKK|SEK|NOK|kr\.?)"#
    private static let number = #"(\d{1,3}(?:[.,\u00A0 ]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    private static let patterns = [
        try! NSRegularExpression(pattern: symbols + #"\s?"# + number, options: .caseInsensitive),
        try! NSRegularExpression(pattern: number + #"\s?"# + symbols, options: .caseInsensitive),
    ]

    /// Every price in the text, as numbers (currency ignored).
    static func all(in text: String) -> [Double] {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.flatMap { pattern in
            pattern.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).flatMap { parse(String(text[$0])) }
            }
        }
    }

    /// The biggest price on screen, which on a product page or in a basket is usually the one that hurts.
    static func highest(in text: String) -> Double? {
        all(in: text).filter { $0 < 10_000_000 }.max()
    }

    /// "8,000" → 8000, "8.000,50" → 8000.5, "49.99" → 49.99, "1 299" → 1299.
    static func parse(_ raw: String) -> Double? {
        var digits = raw.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        // The last separator is a decimal point only if one or two digits follow it.
        if let last = digits.lastIndex(where: { $0 == "." || $0 == "," }),
           digits.distance(from: last, to: digits.endIndex) <= 3 {
            let whole = digits[..<last].filter(\.isNumber)
            let fraction = digits[digits.index(after: last)...]
            digits = "\(whole).\(fraction)"
        } else {
            digits = digits.filter(\.isNumber)
        }
        return Double(digits)
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value < 100 ? 2 : 0
        return formatter.string(from: value as NSNumber) ?? "\(Int(value))"
    }
}

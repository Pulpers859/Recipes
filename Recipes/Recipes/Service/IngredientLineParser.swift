import Foundation

/// Shared heuristics for turning a free-text ingredient line into structured
/// amount / unit / name parts. Used by both no-API fallbacks — the URL
/// scraper's JSON-LD path and the manual PDF/photo parser — so they behave
/// the same way and can be unit-tested in one place.
enum IngredientLineParser {

    private static let unicodeFractionMap: [Character: Double] = [
        "¼": 0.25, "½": 0.5, "¾": 0.75,
        "⅓": 0.333, "⅔": 0.667,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
    ]

    /// Separate "1½" into "1 ½" so the fraction parser can handle it.
    private static func normalizeUnicodeFractions(_ text: String) -> String {
        var result = text
        for frac in unicodeFractionMap.keys {
            let s = String(frac)
            result = result.replacingOccurrences(of: s, with: " \(s) ")
        }
        return result.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Normalize dash variants (en/em/figure dashes, minus sign) to an ASCII
    /// hyphen and comma-notation numbers ("1,5" decimal / "1,500" thousands)
    /// to dot/plain form, so the amount pattern only reasons about one notation.
    private static func normalizeNotation(_ text: String) -> String {
        var result = text
        for dash in ["–", "—", "‒", "−"] {
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        // "1,500" (thousands) first, then "1,5" (comma decimal).
        result = result.replacingOccurrences(
            of: #"(\d),(\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(\d),(\d{1,2})(?!\d)"#, with: "$1.$2", options: .regularExpression)
        return result
    }

    /// A single quantity token: mixed number ("1 1/2"), integer + unicode
    /// fraction ("1½"), plain number ("2", "1.5", "3/4"), or a bare unicode
    /// fraction ("½"). Deliberately NOT a greedy digit soup — "1 400g can"
    /// must capture "1", never "1 400".
    private static let numberToken =
        #"(?:\d+\s+\d+/\d+|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞]|\d+(?:[./]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞])"#

    /// Parse an ingredient string like "2 cups all-purpose flour" into components.
    static func parse(_ rawLine: String) -> Ingredient {
        let cleaned = normalizeNotation(rawLine.trimmingCharacters(in: .whitespacesAndNewlines))

        // Pattern: optional amount (a single quantity token, or a "2-3" range
        // of two tokens), optional unit, then name. Size qualifiers like
        // "1 400g can" keep the 400g in the name rather than summing amounts.
        // The \b after the unit prevents short units from eating the start of
        // ingredient names ("2 garlic" must not parse as unit "g" + "arlic").
        let pattern = "^(\(numberToken)(?:\\s*-\\s*\(numberToken))?)?\\s*(?:(cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|milliliters?|liters?|l|pints?|quarts?|gallons?|pinch(?:es)?|dashe?s?|sprigs?|stalks?|cloves?|cans?|packages?|bunche?s?|sticks?|pieces?|slices?|heads?)\\b)?\\s*[.,]?\\s*(.+)"

        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, range: range) {
                let amountStr = match.range(at: 1).location != NSNotFound
                    ? (Range(match.range(at: 1), in: cleaned).map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? "")
                    : ""
                let unit = match.range(at: 2).location != NSNotFound
                    ? (Range(match.range(at: 2), in: cleaned).map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? "")
                    : ""
                let name = match.range(at: 3).location != NSNotFound
                    ? (Range(match.range(at: 3), in: cleaned).map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? cleaned)
                    : cleaned

                let amount = parseFractionAmount(amountStr)

                return Ingredient(name: name, amount: amount, unit: unit)
            }
        }

        return Ingredient(name: cleaned)
    }

    /// Convert fraction strings to Double: "1 1/2" → 1.5, "¾" → 0.75, "2-3" → 2.5
    static func parseFractionAmount(_ str: String) -> Double {
        // Handle ranges like "2-3" by averaging.
        if str.contains("-") {
            let rangeParts = str.split(separator: "-").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            if rangeParts.count == 2 {
                let lo = parseSingleAmount(rangeParts[0])
                let hi = parseSingleAmount(rangeParts[1])
                if lo > 0 && hi > 0 { return (lo + hi) / 2.0 }
                if lo > 0 { return lo }
                if hi > 0 { return hi }
            }
        }
        return parseSingleAmount(str)
    }

    private static func parseSingleAmount(_ str: String) -> Double {
        let normalized = normalizeUnicodeFractions(str)
        var total: Double = 0
        let parts = normalized.split(separator: " ")

        for part in parts {
            if let unicodeFrac = part.first, let val = unicodeFractionMap[unicodeFrac] {
                total += val
            } else if part.contains("/") {
                let fracParts = part.split(separator: "/")
                if fracParts.count == 2,
                   let num = Double(fracParts[0]),
                   let den = Double(fracParts[1]), den > 0 {
                    total += num / den
                }
            } else if let num = Double(part) {
                total += num
            }
        }

        return total
    }

    /// Double parsing that tolerates a comma decimal separator, because
    /// `Double("1,5")` is nil and comma-decimal locales type exactly that.
    static func flexibleDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = Double(trimmed) { return direct }
        if trimmed.contains(","), !trimmed.contains(".") {
            return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}

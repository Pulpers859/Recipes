import Foundation

/// Shared heuristics for turning a free-text ingredient line into structured
/// amount / unit / name parts. Used by both no-API fallbacks — the URL
/// scraper's JSON-LD path and the manual PDF/photo parser — so they behave
/// the same way and can be unit-tested in one place.
enum IngredientLineParser {

    /// Parse an ingredient string like "2 cups all-purpose flour" into components.
    static func parse(_ rawLine: String) -> Ingredient {
        let cleaned = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: optional amount, optional unit, then name.
        // The \b after the unit prevents short units from eating the start of
        // ingredient names ("2 garlic" must not parse as unit "g" + "arlic").
        let pattern = #"^([\d\s¼½¾⅓⅔⅛⅜⅝⅞/.-]+)?\s*(?:(cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|liters?|l|pinch|cloves?|cans?|packages?|bunche?s?|sticks?|pieces?|slices?|heads?)\b)?\s*[.,]?\s*(.+)"#

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

    /// Convert fraction strings to Double: "1 1/2" → 1.5, "¾" → 0.75
    static func parseFractionAmount(_ str: String) -> Double {
        let fractionMap: [Character: Double] = [
            "¼": 0.25, "½": 0.5, "¾": 0.75,
            "⅓": 0.333, "⅔": 0.667,
            "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
        ]

        var total: Double = 0
        let parts = str.split(separator: " ")

        for part in parts {
            if let unicodeFrac = part.first, let val = fractionMap[unicodeFrac] {
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

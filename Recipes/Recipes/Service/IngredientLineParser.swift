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
    /// fraction ("1½"), plain number ("2", "1.5", "3/4"), leading-dot
    /// decimal (".5"), or a bare unicode fraction ("½"). Deliberately NOT a
    /// greedy digit soup — "1 400g can" must capture "1", never "1 400".
    private static let numberToken =
        #"(?:\d+\s+\d+/\d+|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞]|\d+(?:[./]\d+)?|\.\d+|[¼½¾⅓⅔⅛⅜⅝⅞])"#

    /// Parse an ingredient string like "2 cups all-purpose flour" into components.
    static func parse(_ rawLine: String) -> Ingredient {
        let cleaned = normalizeNotation(rawLine.trimmingCharacters(in: .whitespacesAndNewlines))

        // Pattern: optional amount, optional unit, then name. The amount is a
        // single quantity token, optionally followed by a range separator and
        // a second token — captured SEPARATELY so "1-1.5 lb" keeps both ends
        // instead of collapsing to the midpoint.
        //
        // What keeps "to" out of "tablespoon" is that the separator must
        // directly follow the first number token AND be followed by a second
        // one — the surrounding-whitespace requirement is belt-and-braces on
        // top of that, so don't relax the anchoring on its strength. Size
        // qualifiers like
        // "1 400g can" and "1 28-oz can" still keep their text in the name,
        // because the separator has to be immediately followed by a number.
        // The \b after the unit prevents short units from eating the start of
        // ingredient names ("2 garlic" must not parse as unit "g" + "arlic").
        let rangeSeparator = #"(?:\s*-\s*|\s+(?:to|or)\s+)"#
        let pattern = "^(?:(\(numberToken))(?:\(rangeSeparator)(\(numberToken)))?)?\\s*(?:(cups?|c|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|milliliters?|liters?|l|pints?|quarts?|gallons?|pinch(?:es)?|dashe?s?|sprigs?|stalks?|cloves?|cans?|packages?|bunche?s?|sticks?|pieces?|slices?|heads?)\\b)?\\s*[.,]?\\s*(.+)"

        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, range: range) {
                func captured(_ index: Int) -> String {
                    guard match.range(at: index).location != NSNotFound else { return "" }
                    return Range(match.range(at: index), in: cleaned)
                        .map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
                }

                let lowStr = captured(1)
                let highStr = captured(2)
                let rawUnit = captured(3)
                let unit = rawUnit.lowercased() == "c" ? "cup" : rawUnit
                let nameCapture = captured(4)
                let name = nameCapture.isEmpty ? cleaned : nameCapture

                let amount = parseSingleAmount(lowStr)
                // Only a genuinely higher bound counts. A malformed "3-2" or a
                // second token that parses to zero is dropped rather than
                // stored as a range that reads backwards.
                let high = highStr.isEmpty ? 0 : parseSingleAmount(highStr)
                let amountMax: Double? = high > amount ? high : nil

                return Ingredient(name: name, amount: amount, amountMax: amountMax, unit: unit)
            }
        }

        return Ingredient(name: cleaned)
    }

    /// Splits a free-text amount into its low and high bounds:
    /// "1-1.5" → (1, 1.5), "8 to 12" → (8, 12), "2 cups" → (2, nil).
    ///
    /// Deliberately separate from `parseFractionAmount`, which averages a
    /// range into a single scalar. Averaging is right for servings ("serves
    /// 4-6" really is about 5) and wrong for ingredients, where 1.25 lb of
    /// chicken is a number that appears nowhere in the recipe and can't be
    /// shopped for.
    static func parseAmountRange(_ str: String) -> (amount: Double, amountMax: Double?) {
        let normalized = normalizeNotation(str.trimmingCharacters(in: .whitespacesAndNewlines))

        guard let separator = normalized.range(
            of: #"\s*-\s*|\s+(?:to|or)\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return (parseSingleAmount(normalized), nil)
        }

        let low = parseSingleAmount(
            String(normalized[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        )
        let high = parseSingleAmount(
            String(normalized[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        )
        return (low, high > low ? high : nil)
    }

    /// Convert fraction strings to Double: "1 1/2" → 1.5, "¾" → 0.75, "2-3" → 2.5.
    ///
    /// The range averaging here is for SCALAR fields — servings, prep and cook
    /// times — where a single number is the only sensible answer. Ingredient
    /// amounts go through `parseAmountRange` instead and keep both ends.
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

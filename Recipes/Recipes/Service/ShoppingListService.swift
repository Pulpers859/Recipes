import Foundation
import SwiftData

// MARK: - Shopping List Service

class ShoppingListService {
    
    /// Regenerate a deduplicated shopping list from meal plan entries.
    /// Clears previously generated items, preserves manual adds and checked state.
    static func regenerateShoppingList(
        from entries: [(recipe: Recipe, servings: Int)],
        existingItems: [ShoppingItem],
        pantryItems: [PantryItem] = [],
        modelContext: ModelContext
    ) -> Int {
        
        // Remember checked state
        var checkedKeys: Set<String> = []
        for item in existingItems where item.isChecked {
            checkedKeys.insert(mergeKey(name: item.name))
        }
        
        // Separate manual vs generated items
        let generatedItems = existingItems.filter { !$0.sourceRecipeIDs.isEmpty }
        for item in generatedItems {
            modelContext.delete(item)
        }
        
        // Aggregate ingredients across all recipes
        var aggregated: [String: AggregatedIngredient] = [:]
        
        for entry in entries {
            let scaled = entry.recipe.scaledIngredients(for: entry.servings)

            for ingredient in scaled {
                let baseKey = mergeKey(name: ingredient.name)
                let normalizedUnit = normalizeUnit(ingredient.unit)

                // Combine amounts only when the units are actually
                // compatible. When they aren't ("2 cup flour" vs "500 g
                // flour"), keep a separate line item scoped by unit FAMILY
                // (weight/volume/that unit) — the old behavior silently
                // DROPPED the incoming amount, so the list under-stated what
                // to buy. Family scoping lets "500 g" and "1 kg" variants
                // still merge with each other.
                var key = baseKey
                if let existing = aggregated[baseKey],
                   convertToCommonUnit(
                       amount: ingredient.amount,
                       unit: ingredient.unit,
                       targetUnit: existing.unit
                   ) == nil {
                    key = "\(baseKey)|\(unitFamily(of: normalizedUnit))"
                }

                if var existing = aggregated[key] {
                    if let converted = convertToCommonUnit(
                        amount: ingredient.amount,
                        unit: ingredient.unit,
                        targetUnit: existing.unit
                    ) {
                        existing.amount += converted.amount
                        existing.unit = converted.unit
                    }
                    if !existing.recipeIDs.contains(entry.recipe.id) {
                        existing.recipeIDs.append(entry.recipe.id)
                    }
                    aggregated[key] = existing
                } else {
                    aggregated[key] = AggregatedIngredient(
                        displayName: cleanDisplayName(ingredient.name),
                        amount: ingredient.amount,
                        unit: normalizedUnit,
                        category: categorize(ingredient: ingredient.name),
                        recipeIDs: [entry.recipe.id],
                        pantryKey: baseKey
                    )
                }
            }
        }
        
        // Create ShoppingItems
        var count = 0
        var pantryLookup: [String: (amount: Double, unit: String, isStaple: Bool)] = [:]
        for item in pantryItems {
            let key = normalizedIngredientKey(item.name)
            if var existing = pantryLookup[key] {
                if existing.unit == normalizeUnit(item.unit) {
                    existing.amount += item.amount
                } else if existing.amount <= 0 {
                    existing.amount = item.amount
                    existing.unit = normalizeUnit(item.unit)
                }
                existing.isStaple = existing.isStaple || item.isStaple
                pantryLookup[key] = existing
            } else {
                pantryLookup[key] = (amount: max(item.amount, 0), unit: normalizeUnit(item.unit), isStaple: item.isStaple)
            }
        }
        
        // Deterministic order so pantry coverage is consumed consistently when
        // the same ingredient appears under multiple unit-scoped entries.
        for key in aggregated.keys.sorted() {
            guard var data = aggregated[key] else { continue }
            let startingAmount = data.amount
            if let pantry = pantryLookup[data.pantryKey] {
                if pantry.isStaple {
                    continue
                }
                // Only reduce by pantry stock when the units convert cleanly;
                // subtracting across incompatible units understates the list.
                if data.amount > 0, pantry.amount > 0,
                   let coverage = convertToCommonUnit(
                       amount: pantry.amount,
                       unit: pantry.unit,
                       targetUnit: data.unit
                   ) {
                    let used = min(coverage.amount, data.amount)
                    data.amount = max(0, data.amount - coverage.amount)
                    // Consume the applied stock so a second unit-variant of
                    // the same ingredient can't double-count this coverage.
                    if let usedInPantryUnit = convertToCommonUnit(
                        amount: used,
                        unit: data.unit,
                        targetUnit: pantry.unit
                    ) {
                        pantryLookup[data.pantryKey]?.amount = max(0, pantry.amount - usedInPantryUnit.amount)
                    }
                    if data.amount <= 0.0001 {
                        continue
                    }
                }
            }

            let item = ShoppingItem(
                name: data.displayName,
                amount: data.amount,
                unit: data.unit,
                category: data.category,
                sourceRecipeIDs: data.recipeIDs,
                originalAmount: startingAmount,
                pantryReductionAmount: max(0, startingAmount - data.amount)
            )
            // Restore checked state only onto the base entry: the remembered
            // key can't distinguish unit variants, and a NEW variant line
            // appearing pre-checked would get skipped at the store.
            if key == data.pantryKey, checkedKeys.contains(key) {
                item.isChecked = true
            }
            modelContext.insert(item)
            count += 1
        }
        
        return count
    }
    
    // MARK: - Merge Key
    
    /// Extracts the BASE ingredient for deduplication.
    /// "200g liquid egg whites" and "32oz egg whites" both → "egg whites"
    /// "fat-free cheddar cheese" and "cheddar cheese" both → "cheddar cheese"
    nonisolated static func normalizedIngredientKey(_ name: String) -> String {
        mergeKey(name: name)
    }
    
    static func suggestedCategory(for ingredientName: String) -> ShoppingCategory {
        categorize(ingredient: ingredientName)
    }
    
    static func parsedUnit(from rawValue: String) -> String? {
        let trimmed = rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
             "oz", "ounce", "ounces", "fl oz", "floz", "fluid ounce", "fluid ounces",
             "lb", "lbs", "pound", "pounds", "g", "gram", "grams",
             "kg", "kilogram", "kilograms", "ml", "milliliter", "milliliters", "l", "liter", "liters",
             "pinch", "pinches", "scoop", "scoops", "slice", "slices", "tube", "tubes", "roll", "rolls",
             "tortilla", "tortillas", "clove", "cloves", "can", "cans", "package", "packages",
             "piece", "pieces", "bunch", "bunches":
            return normalizeUnit(trimmed)
        default:
            return nil
        }
    }
    
    /// Generic preparation/quality qualifiers that don't change what you buy.
    /// English-only by design — the whole app currently is. Brand names do
    /// not belong in this list; they get handled by the suffix rules below
    /// (" or similar", " of choice") when recipes phrase them that way.
    private nonisolated static let qualifierPrefixes = [
        "liquid ", "fresh ", "dried ", "large ", "small ", "medium ",
        "chopped ", "diced ", "minced ", "sliced ", "shredded ", "grated ",
        "fat-free ", "fat free ", "nonfat ", "non-fat ", "low-fat ", "lowfat ",
        "low calorie ", "low-calorie ", "reduced fat ", "reduced-fat ",
        "uncured ", "lean ", "plain ", "raw ", "cooked ", "frozen ",
        "light ", "sugar-free ", "sugar free ", "whole wheat ",
    ]

    private nonisolated static let qualifierSuffixes = [
        ", divided", ", to taste", " to taste", "(optional)", ", diced",
        ", chopped", ", sliced", ", minced",
        " or similar", " of choice",
    ]

    /// Substring → canonical replacements. Self-mapping entries are not
    /// no-ops: "sharp cheddar cheese" matching "cheddar cheese" collapses to
    /// the canonical form. First match wins.
    private nonisolated static let synonyms: [(pattern: String, canonical: String)] = [
        ("egg whites?$", "egg whites"),
        ("^eggs?$", "eggs"),
        ("whole milk", "milk"),
        ("milk of choice", "milk"),
        ("brown sugar", "brown sugar"),
        ("powdered sugar", "powdered sugar"),
        ("salt & pepper.*", "salt & pepper"),
        ("salt and pepper.*", "salt & pepper"),
        ("cheddar cheese", "cheddar cheese"),
        ("mozzarella cheese", "mozzarella cheese"),
        ("cream cheese", "cream cheese"),
        ("greek yogurt", "greek yogurt"),
    ]

    private nonisolated static let leadingAmountRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^\d+[\./]?\d*\s*(g|oz|ml|lb|kg|cups?|tbsp|tsp)\s+"#, options: .caseInsensitive)
    }()

    private nonisolated static let compiledSynonyms: [(regex: NSRegularExpression, canonical: String)] = {
        synonyms.compactMap { syn in
            guard let regex = try? NSRegularExpression(pattern: syn.pattern, options: .caseInsensitive) else { return nil }
            return (regex, syn.canonical)
        }
    }()

    private nonisolated static func mergeKey(name: String) -> String {
        var s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let regex = leadingAmountRegex {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }

        // Strip qualifier prefixes until stable, so "chopped fresh basil" and
        // "fresh chopped basil" both reduce to "basil" regardless of order.
        var strippedSomething = true
        while strippedSomething {
            strippedSomething = false
            for prefix in qualifierPrefixes where s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                strippedSomething = true
            }
        }

        // Same for trailing qualifiers ("chicken breast, diced, divided").
        strippedSomething = true
        while strippedSomething {
            strippedSomething = false
            for suffix in qualifierSuffixes where s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                s = s.trimmingCharacters(in: .whitespaces)
                strippedSomething = true
            }
        }

        for syn in compiledSynonyms {
            let range = NSRange(s.startIndex..., in: s)
            if syn.regex.firstMatch(in: s, range: range) != nil {
                s = syn.canonical
                break
            }
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Display Name Cleanup
    
    /// Clean up ingredient names for display (fix "eggs eggs", remove leading amounts, etc.)
    private static func cleanDisplayName(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fix doubled words like "eggs eggs"
        let words = s.split(separator: " ")
        if words.count >= 2 {
            var deduped: [String] = []
            for word in words {
                if deduped.last?.lowercased() != String(word).lowercased() {
                    deduped.append(String(word))
                }
            }
            s = deduped.joined(separator: " ")
        }
        
        return s
    }
    
    // MARK: - Unit Normalization & Conversion
    
    static func normalizeUnit(_ unit: String) -> String {
        let u = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch u {
        case "cups", "cup": return "cup"
        case "tbsp", "tablespoon", "tablespoons": return "tbsp"
        case "tsp", "teaspoon", "teaspoons": return "tsp"
        case "fl oz", "floz", "fl. oz", "fl. oz.", "fluid ounce", "fluid ounces": return "fl oz"
        case "oz", "ounce", "ounces": return "oz"
        case "lb", "lbs", "pound", "pounds": return "lb"
        case "g", "gram", "grams": return "g"
        case "kg", "kilogram", "kilograms": return "kg"
        case "ml", "milliliter", "milliliters": return "ml"
        case "l", "liter", "liters": return "l"
        case "pinch": return "pinch"
        case "clove", "cloves": return "clove"
        case "can", "cans": return "can"
        case "package", "packages": return "package"
        case "piece", "pieces": return "piece"
        case "bunch", "bunches": return "bunch"
        case "scoop", "scoops": return "scoop"
        case "slice", "slices": return "slices"
        case "tube", "tubes": return "tube"
        case "roll", "rolls": return "rolls"
        case "tortilla", "tortillas": return "tortilla"
        default: return u
        }
    }
    
    /// Coarse unit family used to scope non-mergeable shopping lines:
    /// all weights share one bucket, all volumes another, anything else
    /// buckets by its own normalized unit.
    private static func unitFamily(of normalizedUnit: String) -> String {
        if ["g", "kg", "oz", "lb"].contains(normalizedUnit) { return "weight" }
        if ["tsp", "tbsp", "cup", "ml", "l", "fl oz"].contains(normalizedUnit) { return "volume" }
        return normalizedUnit
    }

    /// Try to convert an amount to match the target unit.
    /// If units are compatible (both weight or both volume), converts.
    /// Returns nil when units are incompatible so callers never sum or
    /// subtract amounts measured in different things.
    /// Internal (not private) so unit tests can cover the conversion table.
    static func convertToCommonUnit(amount: Double, unit: String, targetUnit: String) -> (amount: Double, unit: String)? {
        let from = normalizeUnit(unit)
        let to = targetUnit
        
        // Same unit — just add
        if from == to { return (amount, to) }
        
        // Both empty / countable — just add
        if from.isEmpty && to.isEmpty { return (amount, to) }
        if from.isEmpty || to.isEmpty {
            // One has unit, other doesn't — keep the one with a unit
            return to.isEmpty ? (amount, from) : (amount, to)
        }
        
        // Weight conversions (to grams as common base). Bare "oz" is treated
        // as a weight ounce (the US convention for solids); fluid ounces are a
        // separate "fl oz" volume token below. A unit must never appear in both
        // tables, otherwise the same "oz" silently converts as weight in one
        // combine and volume in another and corrupts the quantity.
        let weightToGrams: [String: Double] = ["g": 1, "kg": 1000, "oz": 28.35, "lb": 453.6]
        if let fromFactor = weightToGrams[from], let toFactor = weightToGrams[to] {
            let grams = amount * fromFactor
            return (grams / toFactor, to)
        }

        // Volume conversions (to tsp as common base)
        let volumeToTsp: [String: Double] = ["tsp": 1, "tbsp": 3, "cup": 48, "ml": 0.2029, "l": 202.9, "fl oz": 6]
        if let fromFactor = volumeToTsp[from], let toFactor = volumeToTsp[to] {
            let tsps = amount * fromFactor
            return (tsps / toFactor, to)
        }
        
        // Incompatible units (e.g. "pinch" vs "cup") — caller keeps amounts separate
        return nil
    }
    
    // MARK: - Auto-Categorize
    
    private static func categorize(ingredient: String) -> ShoppingCategory {
        let lower = ingredient.lowercased()
        
        if lower.contains("black pepper")
            || lower.contains("white pepper")
            || lower.contains("red pepper")
            || lower.contains("garlic powder")
            || lower.contains("onion powder")
            || lower.contains("ground cumin")
            || lower.contains("paprika")
            || lower.contains("turmeric")
            || lower.contains("cayenne")
            || lower.contains("garam masala")
            || lower.contains("chili powder")
            || lower.contains("coriander")
            || lower.contains("seasoning") {
            return .spices
        }
        
        if lower.contains("crushed tomato")
            || lower.contains("fire roasted tomato")
            || lower.contains("diced tomato")
            || lower.contains("tomato paste")
            || lower.contains("tomato sauce")
            || lower.contains("canned tomato")
            || lower.contains("can of ") {
            return .pantry
        }
        
        if lower.contains("garlic paste")
            || lower.contains("ginger paste") {
            return .pantry
        }

        // Broth/stock is shelf-stable regardless of flavor — check before the
        // keyword map, or "chicken broth" lands in the meat aisle.
        if lower.contains("broth") || lower.contains("stock") || lower.contains("bouillon") {
            return .pantry
        }
        
        let mapping: [(ShoppingCategory, [String])] = [
            (.produce, ["lettuce", "tomato", "onion", "garlic", "pepper", "carrot", "celery", "potato",
                         "mushroom", "spinach", "kale", "basil", "cilantro", "parsley", "lemon", "lime",
                         "avocado", "cucumber", "zucchini", "broccoli", "cauliflower", "corn", "bean sprout",
                         "ginger", "jalapeño", "jalapeno", "serrano", "scallion", "shallot", "leek",
                         "apple", "banana", "berry", "blueberry", "blueberries", "strawberry", "raspberry",
                         "green onion", "watermelon", "melon", "cantaloupe", "honeydew",
                         "peach", "pear", "plum", "grape", "mango", "pineapple", "orange",
                         "cherry", "cranberry", "pomegranate", "fig", "date", "nectarine", "kiwi"]),
            (.dairy, ["milk", "cream", "butter", "cheese", "yogurt", "sour cream", "egg", "half-and-half",
                       "whipping cream", "crème", "ricotta", "mozzarella", "parmesan", "cheddar",
                       "american cheese", "cream cheese", "protein powder", "whey", "casein"]),
            (.meat, ["chicken", "beef", "pork", "lamb", "turkey", "bacon", "sausage", "ground",
                      "steak", "tenderloin", "ribs", "ham", "veal", "brisket", "canadian bacon"]),
            (.seafood, ["salmon", "shrimp", "tuna", "cod", "tilapia", "crab", "lobster", "scallop",
                         "mussel", "clam", "anchovy", "fish"]),
            (.bakery, ["bread", "tortilla", "bun", "roll", "rolls", "pita", "naan", "baguette",
                        "croissant", "hawaiian"]),
            (.spices, ["cumin", "paprika", "oregano", "thyme", "rosemary", "cinnamon", "nutmeg",
                        "turmeric", "curry", "chili powder", "cayenne", "bay leaf", "sage",
                        "coriander", "cardamom", "clove", "allspice", "vanilla extract",
                        "stevia", "seasoning"]),
            (.pantry, ["flour", "sugar", "salt", "oil", "vinegar", "soy sauce", "pasta", "rice",
                        "broth", "stock", "tomato paste", "tomato sauce", "can", "canned",
                        "honey", "maple syrup", "cornstarch", "baking", "yeast", "oat",
                        "syrup", "cooking spray", "peanut butter", "jam", "jelly",
                        "pudding mix", "powdered sugar", "brown sugar", "tater tot",
                        "non-stick", "nonstick"]),
            (.frozen, ["frozen", "ice cream", "tater tot"]),
            (.beverages, ["wine", "beer", "juice", "soda", "coffee"])
        ]

        for (category, keywords) in mapping {
            if keywords.contains(where: { lower.contains($0) }) {
                return category
            }
        }

        if matchesWord(lower, "water") || matchesWord(lower, "tea") {
            return .beverages
        }

        return .other
    }

    private static func matchesWord(_ text: String, _ word: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0 == word }
    }
}

// MARK: - Aggregation Helper

private struct AggregatedIngredient {
    var displayName: String
    var amount: Double
    var unit: String
    var category: ShoppingCategory
    var recipeIDs: [UUID]
    /// Base ingredient key (no unit suffix) used for pantry-coverage and
    /// checked-state lookups, since unit-scoped entries share one ingredient.
    var pantryKey: String
}

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
                let key = mergeKey(name: ingredient.name)
                
                if var existing = aggregated[key] {
                    // Combine amounts only when the units are actually
                    // compatible — otherwise adding "3 clove" to "2 cup"
                    // would silently corrupt the quantity.
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
                    let normalizedUnit = normalizeUnit(ingredient.unit)
                    aggregated[key] = AggregatedIngredient(
                        displayName: cleanDisplayName(ingredient.name),
                        amount: ingredient.amount,
                        unit: normalizedUnit,
                        category: categorize(ingredient: ingredient.name),
                        recipeIDs: [entry.recipe.id]
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
        
        for (key, originalData) in aggregated {
            var data = originalData
            let startingAmount = data.amount
            if let pantry = pantryLookup[key] {
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
                    data.amount = max(0, data.amount - coverage.amount)
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
            if checkedKeys.contains(key) {
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
    static func normalizedIngredientKey(_ name: String) -> String {
        mergeKey(name: name)
    }
    
    static func suggestedCategory(for ingredientName: String) -> ShoppingCategory {
        categorize(ingredient: ingredientName)
    }
    
    static func parsedUnit(from rawValue: String) -> String? {
        let trimmed = rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
             "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "gram", "grams",
             "kg", "kilogram", "kilograms", "ml", "milliliter", "milliliters", "l", "liter", "liters",
             "pinch", "pinches", "scoop", "scoops", "slice", "slices", "tube", "tubes", "roll", "rolls",
             "tortilla", "tortillas", "clove", "cloves", "can", "cans", "package", "packages",
             "piece", "pieces", "bunch", "bunches":
            return normalizeUnit(trimmed)
        default:
            return nil
        }
    }
    
    private static func mergeKey(name: String) -> String {
        var s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip leading amounts that might be baked into the name (e.g. "150g liquid egg whites")
        // Pattern: optional number+unit at the start
        if let regex = try? NSRegularExpression(pattern: #"^\d+[\./]?\d*\s*(g|oz|ml|lb|kg|cups?|tbsp|tsp)\s+"#, options: .caseInsensitive) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        
        // Strip qualifiers that don't change what you buy
        let stripPrefixes = [
            "liquid ", "fresh ", "dried ", "large ", "small ", "medium ",
            "chopped ", "diced ", "minced ", "sliced ", "shredded ", "grated ",
            "fat-free ", "fat free ", "nonfat ", "non-fat ", "low-fat ", "lowfat ",
            "low calorie ", "low-calorie ", "reduced fat ", "reduced-fat ",
            "uncured ", "lean ", "plain ", "raw ", "cooked ", "frozen ",
            "light ", "sugar-free ", "sugar free ", "whole wheat ",
            "mission ", "king's hawaiian or similar ",
        ]
        for prefix in stripPrefixes {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
            }
        }
        
        // Strip trailing qualifiers
        let stripSuffixes = [
            ", divided", ", to taste", " to taste", "(optional)", ", diced",
            ", chopped", ", sliced", ", minced",
            " or similar", " of choice",
        ]
        for suffix in stripSuffixes {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
            }
        }
        
        // Normalize common ingredient synonyms
        let synonyms: [(pattern: String, canonical: String)] = [
            ("egg whites?$", "egg whites"),
            ("liquid egg whites?", "egg whites"),
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
            ("vanilla greek yogurt", "greek yogurt"),
            ("nonfat greek yogurt", "greek yogurt"),
            ("plain greek yogurt", "greek yogurt"),
        ]
        
        for syn in synonyms {
            if let regex = try? NSRegularExpression(pattern: syn.pattern, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..., in: s)
                if regex.firstMatch(in: s, range: range) != nil {
                    s = syn.canonical
                    break
                }
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
    
    private static func normalizeUnit(_ unit: String) -> String {
        let u = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch u {
        case "cups", "cup": return "cup"
        case "tbsp", "tablespoon", "tablespoons": return "tbsp"
        case "tsp", "teaspoon", "teaspoons": return "tsp"
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
    
    /// Try to convert an amount to match the target unit.
    /// If units are compatible (both weight or both volume), converts.
    /// Returns nil when units are incompatible so callers never sum or
    /// subtract amounts measured in different things.
    private static func convertToCommonUnit(amount: Double, unit: String, targetUnit: String) -> (amount: Double, unit: String)? {
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
        
        // Weight conversions (to grams as common base)
        let weightToGrams: [String: Double] = ["g": 1, "kg": 1000, "oz": 28.35, "lb": 453.6]
        if let fromFactor = weightToGrams[from], let toFactor = weightToGrams[to] {
            let grams = amount * fromFactor
            return (grams / toFactor, to)
        }
        
        // Volume conversions (to tsp as common base)
        let volumeToTsp: [String: Double] = ["tsp": 1, "tbsp": 3, "cup": 48, "ml": 0.2029, "l": 202.9, "oz": 6]
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
        
        let mapping: [(ShoppingCategory, [String])] = [
            (.produce, ["lettuce", "tomato", "onion", "garlic", "pepper", "carrot", "celery", "potato",
                         "mushroom", "spinach", "kale", "basil", "cilantro", "parsley", "lemon", "lime",
                         "avocado", "cucumber", "zucchini", "broccoli", "cauliflower", "corn", "bean sprout",
                         "ginger", "jalapeño", "jalapeno", "serrano", "scallion", "shallot", "leek",
                         "apple", "banana", "berry", "blueberry", "blueberries", "strawberry", "raspberry",
                         "green onion"]),
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
            (.beverages, ["wine", "beer", "juice", "water", "soda", "coffee", "tea"])
        ]
        
        for (category, keywords) in mapping {
            if keywords.contains(where: { lower.contains($0) }) {
                return category
            }
        }
        return .other
    }
}

// MARK: - Aggregation Helper

private struct AggregatedIngredient {
    var displayName: String
    var amount: Double
    var unit: String
    var category: ShoppingCategory
    var recipeIDs: [UUID]
}

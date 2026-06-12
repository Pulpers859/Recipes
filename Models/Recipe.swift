import Foundation
import SwiftUI
import SwiftData

// MARK: - Recipe Model

@Model
final class Recipe {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String = ""
    var ingredients: [Ingredient] = []
    var steps: [RecipeStep] = []
    var servings: Int = 4
    var prepTime: Int = 0
    var cookTime: Int = 0
    var category: RecipeCategory = RecipeCategory.other
    var tags: [String] = []
    var cuisine: String = ""
    var difficulty: Difficulty = Difficulty.medium
    var sourceURL: String?
    var sourceType: SourceType = SourceType.manual
    var notes: String = ""
    var rating: Int = 0
    var isFavorite: Bool = false
    @Attribute(.externalStorage) var photoData: [Data] = []
    var dateAdded: Date = Date()
    var dateLastCooked: Date?
    var timesCooked: Int = 0
    @Attribute(.externalStorage) var originalPDFData: Data?
    
    init(
        title: String = "",
        summary: String = "",
        ingredients: [Ingredient] = [],
        steps: [RecipeStep] = [],
        servings: Int = 4,
        prepTime: Int = 0,
        cookTime: Int = 0,
        category: RecipeCategory = .other,
        tags: [String] = [],
        cuisine: String = "",
        difficulty: Difficulty = .medium,
        sourceURL: String? = nil,
        sourceType: SourceType = .manual,
        notes: String = "",
        rating: Int = 0,
        isFavorite: Bool = false,
        photoData: [Data] = [],
        originalPDFData: Data? = nil
    ) {
        self.title = title
        self.summary = summary
        self.ingredients = ingredients
        self.steps = steps
        self.servings = servings
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.category = category
        self.tags = tags
        self.cuisine = cuisine
        self.difficulty = difficulty
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.notes = notes
        self.rating = rating
        self.isFavorite = isFavorite
        self.photoData = photoData
        self.originalPDFData = originalPDFData
    }
    
    var totalTime: Int { prepTime + cookTime }
    
    var normalizedIngredients: [Ingredient] {
        Ingredient.normalizedList(ingredients)
    }
    
    /// Returns ingredients scaled to a target serving count
    func scaledIngredients(for targetServings: Int) -> [Ingredient] {
        let baseIngredients = normalizedIngredients
        guard servings > 0 else { return baseIngredients }
        let factor = Double(targetServings) / Double(servings)
        return baseIngredients.map { ing in
            Ingredient(
                name: ing.name,
                amount: ing.amount * factor,
                unit: ing.unit,
                section: ing.section,
                isOptional: ing.isOptional
            )
        }
    }
}

// MARK: - Ingredient

struct Ingredient: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var amount: Double
    var unit: String
    var section: String  // e.g. "Sauce", "Dough", "Garnish" — groups in UI
    var isOptional: Bool
    
    init(name: String, amount: Double = 0, unit: String = "", section: String = "", isOptional: Bool = false) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.section = section
        self.isOptional = isOptional
    }
    
    var displayString: String {
        let amtStr = AmountFormatter.format(amount)
        if amount == 0 && unit.isEmpty { return name }
        // Join only non-empty parts so a missing amount never produces a
        // leading space (e.g. unit "cup" with amount 0).
        let parts = (unit.isEmpty || unit.lowercased() == name.lowercased())
            ? [amtStr, name]
            : [amtStr, unit, name]
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
    
    static func normalizedList(_ ingredients: [Ingredient]) -> [Ingredient] {
        var normalized: [Ingredient] = []
        var currentSection = ""
        
        for ingredient in ingredients {
            let trimmedName = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUnit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let explicitSection = cleanedSectionTitle(from: ingredient.section)
            
            guard !trimmedName.isEmpty else { continue }
            
            if isIngredientNoteLine(name: trimmedName, amount: ingredient.amount, unit: trimmedUnit) {
                continue
            }
            
            if isSectionHeaderLine(name: trimmedName, amount: ingredient.amount, unit: trimmedUnit, explicitSection: explicitSection) {
                currentSection = cleanedSectionTitle(from: trimmedName)
                continue
            }
            
            normalized.append(
                Ingredient(
                    name: trimmedName,
                    amount: ingredient.amount,
                    unit: trimmedUnit,
                    section: explicitSection.isEmpty ? currentSection : explicitSection,
                    isOptional: ingredient.isOptional
                )
            )
        }
        
        return normalized
    }
    
    private static func isSectionHeaderLine(name: String, amount: Double, unit: String, explicitSection: String) -> Bool {
        guard explicitSection.isEmpty else { return false }
        guard amount <= 0.0001, unit.isEmpty else { return false }
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":") else { return false }
        
        let cleaned = cleanedSectionTitle(from: trimmed)
        let lower = cleaned.lowercased()
        
        guard !cleaned.isEmpty else { return false }
        guard cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        guard lower != "ingredients", lower != "ingredient" else { return false }
        guard !lower.hasPrefix("note"), !lower.hasPrefix("tip") else { return false }
        guard !lower.contains("to taste"), !lower.contains("optional") else { return false }
        
        let wordCount = cleaned.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount <= 5
    }
    
    private static func isIngredientNoteLine(name: String, amount: Double, unit: String) -> Bool {
        guard amount <= 0.0001, unit.isEmpty else { return false }
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        return trimmed.hasPrefix("*")
            || trimmed.hasPrefix("(")
            || lower == "ingredients"
            || lower == "ingredient"
            || lower == "instructions"
            || lower == "directions"
            || lower == "method"
            || lower.hasPrefix("note:")
            || lower.hasPrefix("tip:")
    }
    
    private static func cleanedSectionTitle(from rawValue: String) -> String {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(":") {
            cleaned.removeLast()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}

// MARK: - Recipe Step

struct RecipeStep: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var order: Int
    var instruction: String
    var timerSeconds: Int?  // nil = no timer for this step
    var timerLabel: String?
    
    var timerFormatted: String? {
        guard let seconds = timerSeconds else { return nil }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 && secs > 0 { return "\(mins)m \(secs)s" }
        if mins > 0 { return "\(mins) min" }
        return "\(secs) sec"
    }
}

// MARK: - Enums

enum RecipeCategory: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, appetizer, snack, dessert, beverage, sauce, bread, soup, salad, side, other
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    
    var icon: String {
        switch self {
        case .breakfast: return "sun.rise.fill"
        case .lunch: return "fork.knife"
        case .dinner: return "moon.stars.fill"
        case .appetizer: return "leaf.fill"
        case .snack: return "carrot.fill"
        case .dessert: return "birthday.cake.fill"
        case .beverage: return "cup.and.saucer.fill"
        case .sauce: return "drop.fill"
        case .bread: return "oven.fill"
        case .soup: return "flame.fill"
        case .salad: return "leaf.circle.fill"
        case .side: return "square.grid.2x2.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum Difficulty: String, Codable, CaseIterable {
    case easy, medium, hard, expert
    
    var displayName: String { rawValue.capitalized }
    
    var color: Color {
        switch self {
        case .easy: return .green
        case .medium: return .yellow
        case .hard: return .orange
        case .expert: return .red
        }
    }
}

enum AmountFormatter {
    static func format(_ value: Double) -> String {
        if value == 0 { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

enum SourceType: String, Codable {
    case manual, pdf, image, url, aiParsed
    
    var displayName: String {
        switch self {
        case .manual: return "Manual Entry"
        case .pdf: return "PDF Import"
        case .image: return "Photo Import"
        case .url: return "Web Import"
        case .aiParsed: return "AI Parsed"
        }
    }
}

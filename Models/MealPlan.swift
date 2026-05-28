import Foundation
import SwiftData

// MARK: - Meal Plan

@Model
final class MealPlan {
    var id: UUID = UUID()
    var weekStartDate: Date = Date()
    var entries: [MealPlanEntry] = []
    var dateCreated: Date = Date()
    
    init(weekStartDate: Date = Date(), entries: [MealPlanEntry] = []) {
        self.weekStartDate = weekStartDate
        self.entries = entries
    }
    
    /// Get entries for a specific day of the week (0 = Sunday)
    func entries(for dayOfWeek: Int) -> [MealPlanEntry] {
        entries.filter { $0.dayOfWeek == dayOfWeek }
    }
}

struct MealPlanEntry: Codable, Hashable, Identifiable {
    static let shortDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var id: UUID = UUID()
    var recipeID: UUID
    var recipeTitle: String  // denormalized for display
    var dayOfWeek: Int  // 0 = Sunday, 6 = Saturday
    var mealSlot: MealSlot
    var servings: Int
    
    var dayName: String {
        guard Self.shortDayNames.indices.contains(dayOfWeek) else { return "?" }
        return Self.shortDayNames[dayOfWeek]
    }
}

enum MealSlot: String, Codable, CaseIterable {
    case breakfast, lunch, dinner, snack
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .breakfast: return "sun.rise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "carrot.fill"
        }
    }
}

// MARK: - Shopping Item

@Model
final class ShoppingItem {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var unit: String = ""
    var category: ShoppingCategory = ShoppingCategory.other
    var isChecked: Bool = false
    var sourceRecipeIDs: [UUID] = []
    var originalAmount: Double = 0
    var pantryReductionAmount: Double = 0
    var dateAdded: Date = Date()
    
    init(
        name: String,
        amount: Double = 0,
        unit: String = "",
        category: ShoppingCategory = .other,
        sourceRecipeIDs: [UUID] = [],
        originalAmount: Double? = nil,
        pantryReductionAmount: Double = 0
    ) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.category = category
        self.sourceRecipeIDs = sourceRecipeIDs
        self.originalAmount = originalAmount ?? amount
        self.pantryReductionAmount = pantryReductionAmount
    }
    
    var quantityText: String {
        let amountText = AmountFormatter.format(amount)
        return [amountText, unit]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    var hasQuantity: Bool {
        !quantityText.isEmpty
    }
    
    var isGenerated: Bool {
        !sourceRecipeIDs.isEmpty
    }
    
    var pantryCoverageText: String? {
        guard pantryReductionAmount > 0 else { return nil }
        let reductionText = AmountFormatter.format(pantryReductionAmount)
        let quantity = [reductionText, unit]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        if quantity.isEmpty {
            return "Pantry already covered part of this item"
        }
        return "Pantry already covered \(quantity)"
    }
    
    var displayString: String {
        if quantityText.isEmpty {
            return name
        }
        return [quantityText, name].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum ShoppingCategory: String, Codable, CaseIterable {
    case produce, dairy, meat, seafood, bakery, pantry, frozen, spices, beverages, other
    
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .produce: return "leaf.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .meat: return "flame.fill"
        case .seafood: return "fish.fill"
        case .bakery: return "oven.fill"
        case .pantry: return "cabinet.fill"
        case .frozen: return "snowflake"
        case .spices: return "sparkles"
        case .beverages: return "waterbottle.fill"
        case .other: return "basket.fill"
        }
    }
}

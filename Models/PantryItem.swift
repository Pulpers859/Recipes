import Foundation
import SwiftData

// MARK: - Pantry Item

@Model
final class PantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var unit: String = ""
    var category: ShoppingCategory = ShoppingCategory.other
    var isStaple: Bool = false
    var dateUpdated: Date = Date()
    
    init(
        name: String,
        amount: Double = 0,
        unit: String = "",
        category: ShoppingCategory = .other,
        isStaple: Bool = false
    ) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.category = category
        self.isStaple = isStaple
    }
    
    var displayString: String {
        let amountText = AmountFormatter.format(amount)
        if amountText.isEmpty { return name }
        return [amountText, unit, name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

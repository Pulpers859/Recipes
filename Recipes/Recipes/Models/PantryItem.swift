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

    /// Adds incoming stock only when the units agree (or one side has no
    /// unit), so "2 cups" never silently absorbs "2 lb" into a meaningless
    /// total. Returns false when the units conflicted and nothing was added.
    @discardableResult
    func absorbStock(amount incomingAmount: Double, unit incomingUnit: String) -> Bool {
        guard incomingAmount > 0 else { return true }

        let existingUnit = ShoppingListService.normalizeUnit(unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let newUnit = ShoppingListService.normalizeUnit(incomingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())

        if amount <= 0 {
            // Nothing in stock to conflict with — adopt the incoming stock
            // (and its unit, when it has one) wholesale.
            amount = incomingAmount
            if !newUnit.isEmpty { unit = incomingUnit }
            dateUpdated = Date()
            return true
        }

        // Sum only when the units genuinely agree (both named the same, or
        // both bare counts). A one-sided unit used to be treated as "close
        // enough", which summed "3" loose eggs with "2 lb" into "5 lb".
        if existingUnit == newUnit {
            amount += incomingAmount
            dateUpdated = Date()
            return true
        }

        return false
    }
}

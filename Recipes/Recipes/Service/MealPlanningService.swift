import Foundation
import SwiftData

/// Week-aware meal plan lookup plus the shared "planned servings per recipe"
/// aggregation that both MealPlanView and PantryView feed into shopping-list
/// generation. Also owns cleanup of meal-plan entries when recipes are
/// deleted, so plans never silently reference recipes that no longer exist.
enum MealPlanningService {

    // MARK: - Week Semantics

    /// The start of the week (per the user's calendar) containing `date`.
    static func weekStart(for date: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The stored plan whose week contains `date`, if one exists.
    static func plan(forWeekContaining date: Date, in plans: [MealPlan], calendar: Calendar = .current) -> MealPlan? {
        plans.first { calendar.isDate($0.weekStartDate, equalTo: date, toGranularity: .weekOfYear) }
    }

    // MARK: - Shopping List Aggregation

    /// Sums planned servings per recipe across all entries in a plan,
    /// dropping entries whose recipe no longer exists in the library.
    static func aggregatedServingEntries(
        for plan: MealPlan,
        recipes: [Recipe]
    ) -> [(recipe: Recipe, servings: Int)] {
        // `uniquingKeysWith` instead of `uniqueKeysWithValues:` so a duplicate
        // recipe id (possible after a backup restore or merge race) degrades
        // gracefully instead of trapping and crashing shopping-list generation.
        let lookup = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Clamp per-entry servings to a sane range so a corrupted/huge value
        // can't overflow the running sum or scale ingredients into nonsense.
        let maxServings = 9999

        var byID: [UUID: (recipe: Recipe, servings: Int)] = [:]
        for entry in plan.entries {
            guard let recipe = lookup[entry.recipeID] else { continue }
            let clamped = max(0, min(entry.servings, maxServings))
            if let existing = byID[recipe.id] {
                byID[recipe.id] = (recipe, min(existing.servings + clamped, maxServings))
            } else {
                byID[recipe.id] = (recipe, clamped)
            }
        }
        return Array(byID.values)
    }

    // MARK: - Entry Lifecycle

    /// Removes meal-plan entries pointing at deleted recipes. Call this
    /// whenever recipes are deleted, otherwise orphaned entries linger in the
    /// plan UI but silently drop out of shopping-list generation.
    /// The caller owns the final `modelContext.save()` so recipe deletion and
    /// meal-plan cleanup commit or roll back together.
    static func removeEntries(forRecipeIDs ids: Set<UUID>, modelContext: ModelContext) throws {
        guard !ids.isEmpty else { return }
        let plans = try modelContext.fetch(FetchDescriptor<MealPlan>())
        for plan in plans where plan.entries.contains(where: { ids.contains($0.recipeID) }) {
            // Reassign the whole array (rather than mutating in place) so
            // SwiftData reliably registers the change to the stored value array.
            plan.entries = plan.entries.filter { !ids.contains($0.recipeID) }
        }
    }

    /// Updates the denormalized `recipeTitle` on any meal-plan entries that
    /// reference `recipe`, so a rename in the editor is reflected immediately.
    static func syncTitle(for recipe: Recipe, modelContext: ModelContext) {
        let plans = (try? modelContext.fetch(FetchDescriptor<MealPlan>())) ?? []
        for plan in plans {
            guard plan.entries.contains(where: { $0.recipeID == recipe.id && $0.recipeTitle != recipe.title }) else { continue }
            var entries = plan.entries
            for index in entries.indices where entries[index].recipeID == recipe.id {
                entries[index].recipeTitle = recipe.title
            }
            plan.entries = entries
        }
    }

    /// Re-points entries at a surviving recipe after duplicate resolution so
    /// planned meals follow the merged recipe instead of disappearing.
    static func retargetEntries(fromRecipeID oldID: UUID, to canonical: Recipe, modelContext: ModelContext) {
        let plans = (try? modelContext.fetch(FetchDescriptor<MealPlan>())) ?? []
        for plan in plans {
            guard plan.entries.contains(where: { $0.recipeID == oldID }) else { continue }
            var entries = plan.entries
            for index in entries.indices where entries[index].recipeID == oldID {
                entries[index].recipeID = canonical.id
                entries[index].recipeTitle = canonical.title
            }
            plan.entries = entries
        }
        // Caller owns the final save — do not save here to preserve atomicity
        // with the surrounding conflict-resolution or delete transaction.
    }
}

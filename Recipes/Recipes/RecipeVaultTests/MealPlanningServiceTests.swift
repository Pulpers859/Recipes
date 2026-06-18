import XCTest
@testable import RecipeVault

final class MealPlanningServiceTests: XCTestCase {

    func testWeekStartIsStableWithinAWeek() {
        let calendar = Calendar.current
        let start = MealPlanningService.weekStart(for: Date(), calendar: calendar)
        let midWeek = calendar.date(byAdding: .day, value: 3, to: start)!
        XCTAssertEqual(MealPlanningService.weekStart(for: midWeek, calendar: calendar), start)
    }

    func testPlanLookupMatchesWeek() {
        let calendar = Calendar.current
        let thisWeek = MealPlanningService.weekStart(for: Date(), calendar: calendar)
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!

        let current = MealPlan(weekStartDate: thisWeek)
        let previous = MealPlan(weekStartDate: lastWeek)

        let found = MealPlanningService.plan(forWeekContaining: Date(), in: [previous, current], calendar: calendar)
        XCTAssertEqual(found?.id, current.id)

        let foundPrevious = MealPlanningService.plan(forWeekContaining: lastWeek, in: [previous, current], calendar: calendar)
        XCTAssertEqual(foundPrevious?.id, previous.id)
    }

    func testAggregationSumsServingsAndDropsOrphans() {
        let recipe = Recipe(title: "Chili", servings: 4)
        let plan = MealPlan(weekStartDate: Date(), entries: [
            MealPlanEntry(recipeID: recipe.id, recipeTitle: "Chili", dayOfWeek: 1, mealSlot: .dinner, servings: 4),
            MealPlanEntry(recipeID: recipe.id, recipeTitle: "Chili", dayOfWeek: 3, mealSlot: .lunch, servings: 2),
            // Orphan: recipe was deleted, entry must not crash or count.
            MealPlanEntry(recipeID: UUID(), recipeTitle: "Ghost", dayOfWeek: 2, mealSlot: .dinner, servings: 6),
        ])

        let entries = MealPlanningService.aggregatedServingEntries(for: plan, recipes: [recipe])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.servings, 6)
        XCTAssertEqual(entries.first?.recipe.id, recipe.id)
    }
}

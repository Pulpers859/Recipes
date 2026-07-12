import XCTest
@testable import Recipes

/// Backup round-trip tests with old (v1/v3) and current (v4) fixtures, so
/// format changes can't silently break existing user backups.
final class RecipeExportRoundTripTests: XCTestCase {

    // MARK: - Old-format fixtures still import

    func testV3RecipesOnlyFixtureImports() throws {
        let json = """
        {
          "version": 3,
          "exportDate": "2026-06-28T12:00:00Z",
          "recipeCount": 1,
          "recipes": [
            {
              "recipeID": "11111111-2222-3333-4444-555555555555",
              "title": "Weeknight Chili",
              "summary": "A fast chili.",
              "ingredients": [
                {"id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "name": "ground beef", "amount": 1, "unit": "lb", "section": "", "isOptional": false}
              ],
              "steps": [
                {"id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1", "order": 1, "instruction": "Brown the beef."}
              ],
              "servings": 4,
              "prepTime": 10,
              "cookTime": 30,
              "category": "dinner",
              "tags": ["quick"],
              "cuisine": "American",
              "difficulty": "easy",
              "notes": "",
              "rating": 4,
              "isFavorite": true,
              "dateAdded": "2026-01-02T08:30:00Z",
              "timesCooked": 3
            }
          ]
        }
        """
        let result = try RecipeExportService.importFromJSON(data: Data(json.utf8))
        XCTAssertEqual(result.recipes.count, 1)
        XCTAssertEqual(result.unreadableCount, 0)
        let recipe = try XCTUnwrap(result.recipes.first)
        XCTAssertEqual(recipe.id.uuidString, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(recipe.title, "Weeknight Chili")
        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.steps.count, 1)
        XCTAssertEqual(recipe.timesCooked, 3)
        XCTAssertTrue(recipe.isFavorite)
        // v3 files carry no aux sections; they must decode to empty, not fail.
        XCTAssertTrue(result.pantryItems.isEmpty)
        XCTAssertTrue(result.shoppingItems.isEmpty)
        XCTAssertTrue(result.mealPlans.isEmpty)
    }

    func testV1FixtureWithoutVersionKeyImports() throws {
        // The very first export format: no version, no recipeID, no dateAdded.
        let json = """
        {
          "exportDate": "2025-11-01T12:00:00Z",
          "recipeCount": 1,
          "recipes": [
            {
              "title": "Toast",
              "summary": "",
              "ingredients": [],
              "steps": [],
              "servings": 1,
              "prepTime": 1,
              "cookTime": 2,
              "category": "breakfast",
              "tags": [],
              "cuisine": "",
              "difficulty": "easy",
              "notes": "",
              "rating": 0,
              "isFavorite": false
            }
          ]
        }
        """
        let result = try RecipeExportService.importFromJSON(data: Data(json.utf8))
        XCTAssertEqual(result.recipes.count, 1)
        XCTAssertEqual(result.recipes.first?.title, "Toast")
    }

    // MARK: - v4 full-app round trip

    func testV4FullAppRoundTrip() throws {
        let recipe = Recipe(title: "Chili", servings: 4)
        let pantry = PantryItem(name: "flour", amount: 2, unit: "cup", category: .pantry, isStaple: true)
        let shopping = ShoppingItem(name: "milk", amount: 1, unit: "gal", category: .dairy)
        shopping.isChecked = true
        let plan = MealPlan(weekStartDate: Date(timeIntervalSince1970: 1_760_000_000), entries: [
            MealPlanEntry(recipeID: recipe.id, recipeTitle: "Chili", dayOfWeek: 2, mealSlot: .dinner, servings: 4)
        ])

        let data = try RecipeExportService.exportAsJSON(
            recipes: [recipe],
            pantryItems: [pantry],
            shoppingItems: [shopping],
            mealPlans: [plan]
        )
        let result = try RecipeExportService.importFromJSON(data: data)

        XCTAssertEqual(result.recipes.count, 1)
        XCTAssertEqual(result.recipes.first?.id, recipe.id)

        XCTAssertEqual(result.pantryItems.count, 1)
        let importedPantry = try XCTUnwrap(result.pantryItems.first)
        XCTAssertEqual(importedPantry.id, pantry.id)
        XCTAssertEqual(importedPantry.name, "flour")
        XCTAssertEqual(importedPantry.amount, 2, accuracy: 0.001)
        XCTAssertTrue(importedPantry.isStaple)
        XCTAssertEqual(importedPantry.category, .pantry)

        XCTAssertEqual(result.shoppingItems.count, 1)
        let importedShopping = try XCTUnwrap(result.shoppingItems.first)
        XCTAssertEqual(importedShopping.id, shopping.id)
        XCTAssertTrue(importedShopping.isChecked)
        XCTAssertEqual(importedShopping.category, .dairy)

        XCTAssertEqual(result.mealPlans.count, 1)
        let importedPlan = try XCTUnwrap(result.mealPlans.first)
        XCTAssertEqual(importedPlan.id, plan.id)
        XCTAssertEqual(importedPlan.entries.count, 1)
        XCTAssertEqual(importedPlan.entries.first?.recipeID, recipe.id)
        XCTAssertEqual(importedPlan.entries.first?.mealSlot, .dinner)
    }

    func testRecipesOnlyExportOmitsAuxKeys() throws {
        let data = try RecipeExportService.exportAsJSON(recipes: [Recipe(title: "Solo")])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["pantryItems"], "empty sections must be omitted so recipes-only exports keep their old shape")
        XCTAssertNil(object["shoppingItems"])
        XCTAssertNil(object["mealPlans"])
        XCTAssertEqual(object["version"] as? Int, RecipeExportService.currentBackupVersion)
    }

    // MARK: - Guardrails

    func testNewerVersionIsRefused() {
        let json = """
        {"version": 99, "exportDate": "2026-07-11T00:00:00Z", "recipeCount": 0, "recipes": []}
        """
        XCTAssertThrowsError(try RecipeExportService.importFromJSON(data: Data(json.utf8))) { error in
            guard case ImportError.unsupportedVersion = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
        }
    }

    func testCorruptRecordIsSkippedAndCounted() throws {
        let json = """
        {
          "version": 3,
          "exportDate": "2026-06-28T12:00:00Z",
          "recipeCount": 2,
          "recipes": [
            {"title": "Good", "summary": "", "ingredients": [], "steps": [], "servings": 1,
             "prepTime": 0, "cookTime": 0, "category": "other", "tags": [], "cuisine": "",
             "difficulty": "easy", "notes": "", "rating": 0, "isFavorite": false},
            {"title": 42}
          ]
        }
        """
        let result = try RecipeExportService.importFromJSON(data: Data(json.utf8))
        XCTAssertEqual(result.recipes.count, 1)
        XCTAssertEqual(result.unreadableCount, 1)
    }

    func testFractionalSecondDatesImport() throws {
        // The Python migration scripts emitted microsecond timestamps; a
        // strict .iso8601 decoder failed every such record.
        let json = """
        {
          "version": 3,
          "exportDate": "2026-07-11T18:23:45.123456Z",
          "recipeCount": 1,
          "recipes": [
            {"title": "Migrated", "summary": "", "ingredients": [], "steps": [], "servings": 2,
             "prepTime": 0, "cookTime": 0, "category": "other", "tags": [], "cuisine": "",
             "difficulty": "easy", "notes": "", "rating": 0, "isFavorite": false,
             "dateAdded": "2026-07-11T18:23:45.123456Z"}
          ]
        }
        """
        let result = try RecipeExportService.importFromJSON(data: Data(json.utf8))
        XCTAssertEqual(result.recipes.count, 1)
        XCTAssertEqual(result.unreadableCount, 0)
    }

    func testEmptyBackupThrows() {
        let json = """
        {"version": 4, "exportDate": "2026-07-11T00:00:00Z", "recipeCount": 0, "recipes": []}
        """
        XCTAssertThrowsError(try RecipeExportService.importFromJSON(data: Data(json.utf8)))
    }

    func testV4PantryOnlyBackupImports() throws {
        // A full-app backup of an empty recipe library must still restore
        // the pantry instead of throwing "no readable recipes".
        let json = """
        {
          "version": 4,
          "exportDate": "2026-07-11T00:00:00Z",
          "recipeCount": 0,
          "recipes": [],
          "pantryItems": [
            {"id": "99999999-8888-7777-6666-555555555555", "name": "salt", "amount": 1, "unit": "lb", "category": "pantry", "isStaple": true}
          ]
        }
        """
        let result = try RecipeExportService.importFromJSON(data: Data(json.utf8))
        XCTAssertTrue(result.recipes.isEmpty)
        XCTAssertEqual(result.pantryItems.count, 1)
        XCTAssertEqual(result.pantryItems.first?.name, "salt")
    }
}

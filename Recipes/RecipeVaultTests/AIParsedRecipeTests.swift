import XCTest
@testable import Recipes

final class AIParsedRecipeTests: XCTestCase {

    /// The model sometimes emits ingredients/steps as plain strings instead
    /// of objects. Dropping them all used to leave a steps-only (or
    /// ingredients-only) recipe that slipped past the both-empty fallback
    /// guard and saved silently wrong content.
    func testStringShapedIngredientsAndStepsDecode() throws {
        let json = """
        {
          "title": "Drifted Output",
          "ingredients": ["2 cups flour", "1 tsp salt"],
          "steps": ["Mix everything.", "Bake at 400F."]
        }
        """
        let parsed = try JSONDecoder().decode(AIParsedRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(parsed.ingredients.count, 2)
        XCTAssertEqual(parsed.steps.count, 2)
        let flour = try XCTUnwrap(parsed.ingredients.first)
        XCTAssertEqual(flour.name.lowercased(), "flour")
        XCTAssertEqual(flour.amount ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(flour.unit?.lowercased(), "cups")
        XCTAssertEqual(parsed.steps.first?.instruction, "Mix everything.")
    }

    func testMixedObjectAndStringElements() throws {
        let json = """
        {
          "title": "Mixed",
          "ingredients": [
            {"name": "butter", "amount": "1/2", "unit": "cup"},
            "3 large eggs"
          ],
          "steps": [{"order": 1, "instruction": "Cream the butter."}]
        }
        """
        let parsed = try JSONDecoder().decode(AIParsedRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(parsed.ingredients.count, 2)
        XCTAssertEqual(parsed.ingredients[0].amount ?? 0, 0.5, accuracy: 0.001)
        XCTAssertTrue(parsed.ingredients[1].name.lowercased().contains("eggs"))
        XCTAssertEqual(parsed.ingredients[1].amount ?? 0, 3, accuracy: 0.001)
    }

    func testGarbageElementIsDroppedNotFatal() throws {
        let json = """
        {
          "title": "Partly Broken",
          "ingredients": [{"nome": "wrong key"}, {"name": "sugar", "amount": 1, "unit": "cup"}],
          "steps": [{"instruction": "Stir."}]
        }
        """
        let parsed = try JSONDecoder().decode(AIParsedRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(parsed.ingredients.count, 1)
        XCTAssertEqual(parsed.ingredients.first?.name, "sugar")
    }
}

import XCTest
@testable import RecipeVault

final class ShoppingListServiceTests: XCTestCase {

    // MARK: - Merge Key

    func testStripsLeadingAmounts() {
        XCTAssertEqual(
            ShoppingListService.normalizedIngredientKey("200g liquid egg whites"),
            ShoppingListService.normalizedIngredientKey("egg whites")
        )
    }

    func testQualifierPrefixesStripInAnyOrder() {
        let a = ShoppingListService.normalizedIngredientKey("chopped fresh basil")
        let b = ShoppingListService.normalizedIngredientKey("fresh chopped basil")
        let c = ShoppingListService.normalizedIngredientKey("basil")
        XCTAssertEqual(a, c)
        XCTAssertEqual(b, c)
    }

    func testFatVariantsMerge() {
        XCTAssertEqual(
            ShoppingListService.normalizedIngredientKey("fat-free cheddar cheese"),
            ShoppingListService.normalizedIngredientKey("cheddar cheese")
        )
    }

    func testTrailingQualifiersStrip() {
        XCTAssertEqual(
            ShoppingListService.normalizedIngredientKey("chicken breast, diced, divided"),
            ShoppingListService.normalizedIngredientKey("chicken breast")
        )
    }

    func testBrandSuffixStrips() {
        XCTAssertEqual(
            ShoppingListService.normalizedIngredientKey("hamburger buns or similar"),
            ShoppingListService.normalizedIngredientKey("hamburger buns")
        )
    }

    func testGreekYogurtVariantsMerge() {
        let base = ShoppingListService.normalizedIngredientKey("greek yogurt")
        XCTAssertEqual(ShoppingListService.normalizedIngredientKey("plain greek yogurt"), base)
        XCTAssertEqual(ShoppingListService.normalizedIngredientKey("nonfat greek yogurt"), base)
        XCTAssertEqual(ShoppingListService.normalizedIngredientKey("vanilla greek yogurt"), base)
    }

    func testDistinctIngredientsDoNotMerge() {
        XCTAssertNotEqual(
            ShoppingListService.normalizedIngredientKey("chicken breast"),
            ShoppingListService.normalizedIngredientKey("chicken thighs")
        )
    }

    // MARK: - Unit Conversion

    func testWeightConversion() throws {
        let result = try XCTUnwrap(
            ShoppingListService.convertToCommonUnit(amount: 1, unit: "lb", targetUnit: "g")
        )
        XCTAssertEqual(result.amount, 453.6, accuracy: 0.5)
        XCTAssertEqual(result.unit, "g")
    }

    func testVolumeConversion() throws {
        let result = try XCTUnwrap(
            ShoppingListService.convertToCommonUnit(amount: 3, unit: "tsp", targetUnit: "tbsp")
        )
        XCTAssertEqual(result.amount, 1, accuracy: 0.001)
        XCTAssertEqual(result.unit, "tbsp")
    }

    func testIncompatibleUnitsReturnNil() {
        // The bug this guards against: "3 cloves" being summed into "2 cups".
        XCTAssertNil(ShoppingListService.convertToCommonUnit(amount: 3, unit: "clove", targetUnit: "cup"))
        XCTAssertNil(ShoppingListService.convertToCommonUnit(amount: 1, unit: "pinch", targetUnit: "g"))
    }

    func testSameUnitPassesThrough() throws {
        let result = try XCTUnwrap(
            ShoppingListService.convertToCommonUnit(amount: 2, unit: "cups", targetUnit: "cup")
        )
        XCTAssertEqual(result.amount, 2, accuracy: 0.001)
        XCTAssertEqual(result.unit, "cup")
    }

    // MARK: - Unit Parsing

    func testParsedUnitNormalizes() {
        XCTAssertEqual(ShoppingListService.parsedUnit(from: "Tablespoons"), "tbsp")
        XCTAssertEqual(ShoppingListService.parsedUnit(from: "lbs"), "lb")
        XCTAssertNil(ShoppingListService.parsedUnit(from: "chicken"))
    }
}

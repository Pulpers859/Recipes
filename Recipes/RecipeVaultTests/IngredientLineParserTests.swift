import XCTest
@testable import Recipes

final class IngredientLineParserTests: XCTestCase {

    func testAmountUnitName() {
        let ing = IngredientLineParser.parse("2 cups all-purpose flour")
        XCTAssertEqual(ing.amount, 2, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "cups")
        XCTAssertEqual(ing.name, "all-purpose flour")
    }

    func testMixedNumberFraction() {
        let ing = IngredientLineParser.parse("1 1/2 lbs chicken breast")
        XCTAssertEqual(ing.amount, 1.5, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "lbs")
        XCTAssertEqual(ing.name, "chicken breast")
    }

    func testUnicodeFraction() {
        let ing = IngredientLineParser.parse("¾ cup sugar")
        XCTAssertEqual(ing.amount, 0.75, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "cup")
        XCTAssertEqual(ing.name, "sugar")
    }

    func testShortUnitDoesNotEatName() {
        // "2 garlic" must not parse as unit "g" + name "arlic"
        let ing = IngredientLineParser.parse("2 garlic cloves")
        XCTAssertEqual(ing.amount, 2, accuracy: 0.001)
        XCTAssertEqual(ing.name, "garlic cloves")
    }

    func testNoAmount() {
        let ing = IngredientLineParser.parse("salt and pepper to taste")
        XCTAssertEqual(ing.amount, 0, accuracy: 0.001)
        XCTAssertEqual(ing.name, "salt and pepper to taste")
    }

    func testFlexibleDoubleAcceptsCommaDecimal() {
        XCTAssertEqual(IngredientLineParser.flexibleDouble("1,5"), 1.5)
        XCTAssertEqual(IngredientLineParser.flexibleDouble("1.5"), 1.5)
        XCTAssertEqual(IngredientLineParser.flexibleDouble("3"), 3)
        XCTAssertNil(IngredientLineParser.flexibleDouble(""))
        XCTAssertNil(IngredientLineParser.flexibleDouble("abc"))
        // Thousands separators are ambiguous — flexibleDouble only handles
        // the comma-as-decimal case, never "1,234.5".
        XCTAssertNil(IngredientLineParser.flexibleDouble("1,234.5"))
    }

    func testParseFractionAmount() {
        XCTAssertEqual(IngredientLineParser.parseFractionAmount("1 1/2"), 1.5, accuracy: 0.001)
        XCTAssertEqual(IngredientLineParser.parseFractionAmount("¾"), 0.75, accuracy: 0.001)
        XCTAssertEqual(IngredientLineParser.parseFractionAmount("3"), 3, accuracy: 0.001)
        XCTAssertEqual(IngredientLineParser.parseFractionAmount("1/0"), 0, accuracy: 0.001)
    }
}

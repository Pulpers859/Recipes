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

    // MARK: - Regression: size-qualified amounts must not be summed

    func testSizeQualifiedCanKeepsQualifierInName() {
        // "1 400g can" used to parse as amount 401.
        let ing = IngredientLineParser.parse("1 400g can chopped tomatoes")
        XCTAssertEqual(ing.amount, 1, accuracy: 0.001)
        XCTAssertEqual(ing.name, "400g can chopped tomatoes")
    }

    func testHyphenatedSizeQualifier() {
        // "1 28-oz can" used to parse as amount 29 with a mangled name.
        let ing = IngredientLineParser.parse("1 28-oz can San Marzano whole peeled tomatoes, drained")
        XCTAssertEqual(ing.amount, 1, accuracy: 0.001)
        XCTAssertEqual(ing.name, "28-oz can San Marzano whole peeled tomatoes, drained")
    }

    func testEnDashRange() {
        // En dashes are what most CMSs emit; only ASCII "-" used to parse.
        let ing = IngredientLineParser.parse("¼–½ tsp cayenne pepper")
        XCTAssertEqual(ing.amount, 0.375, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "tsp")
        XCTAssertEqual(ing.name, "cayenne pepper")
    }

    func testHyphenRangeStillAverages() {
        let ing = IngredientLineParser.parse("2-3 cups flour")
        XCTAssertEqual(ing.amount, 2.5, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "cups")
        XCTAssertEqual(ing.name, "flour")
    }

    func testCommaDecimalInLine() {
        // "1,5 kg" used to parse as amount 1, name "5 kg potatoes".
        let ing = IngredientLineParser.parse("1,5 kg potatoes")
        XCTAssertEqual(ing.amount, 1.5, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "kg")
        XCTAssertEqual(ing.name, "potatoes")
    }

    func testThousandsSeparatorInLine() {
        let ing = IngredientLineParser.parse("1,500 g flour")
        XCTAssertEqual(ing.amount, 1500, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "g")
        XCTAssertEqual(ing.name, "flour")
    }

    func testQuartsAndPintsRecognizedAsUnits() {
        let quarts = IngredientLineParser.parse("2 quarts water")
        XCTAssertEqual(quarts.unit.lowercased(), "quarts")
        XCTAssertEqual(quarts.name, "water")

        let pint = IngredientLineParser.parse("1 pint heavy cream")
        XCTAssertEqual(pint.unit.lowercased(), "pint")
        XCTAssertEqual(pint.name, "heavy cream")
    }

    func testLeadingDotDecimal() {
        // ".5 cup sugar" must not degrade into name "5 cup sugar".
        let ing = IngredientLineParser.parse(".5 cup sugar")
        XCTAssertEqual(ing.amount, 0.5, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "cup")
        XCTAssertEqual(ing.name, "sugar")
    }

    func testUnicodeMixedNumberNoSpace() {
        let ing = IngredientLineParser.parse("1½ cups milk")
        XCTAssertEqual(ing.amount, 1.5, accuracy: 0.001)
        XCTAssertEqual(ing.unit.lowercased(), "cups")
        XCTAssertEqual(ing.name, "milk")
    }
}

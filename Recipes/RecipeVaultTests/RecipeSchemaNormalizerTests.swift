import XCTest
@testable import Recipes

final class RecipeSchemaNormalizerTests: XCTestCase {
    func testDelishShapedTaxonomyChoosesUsefulValues() {
        let categories = [
            "low sugar", "Super Bowl", "tailgate", "weeknight meals",
            "dinner", "lunch", "main dish"
        ]
        let cuisines = [
            "Super Bowl Cuisine", "American (US) Cuisine",
            "Midwestern Cuisine", "American Cuisine"
        ]

        XCTAssertEqual(RecipeSchemaNormalizer.category(from: categories), .dinner)
        XCTAssertEqual(RecipeSchemaNormalizer.cuisine(from: cuisines), "American")
    }

    func testDelishShapedKeywordsDropPublisherMetadata() {
        let keywords = [
            "content-type: Recipe", "locale: US", "displayType: recipe",
            "shortTitle: Meatball Sub", "contentId: 7871ed46-be88-497b-8037-0afb3dcfd931",
            "best meatball sub recipe, easy homemade meatball recipe",
            "NUTRITION: low sugar", "OCCASION: Super Bowl", "CATEGORY: dinner",
            "TOTALTIME: 00:35:00", "sponsored: false"
        ]

        XCTAssertEqual(
            RecipeSchemaNormalizer.tags(from: keywords),
            ["best meatball sub recipe", "easy homemade meatball recipe", "low sugar", "Super Bowl", "dinner"]
        )
    }

    func testCookTimeFallsBackToTotalMinusPrep() {
        XCTAssertEqual(
            RecipeSchemaNormalizer.resolvedCookTime(prepTime: 15, cookTime: 0, totalTime: 35),
            20
        )
        XCTAssertEqual(
            RecipeSchemaNormalizer.resolvedCookTime(prepTime: 10, cookTime: 0, totalTime: 10),
            0,
            "a genuine no-cook recipe must stay at zero"
        )
        XCTAssertEqual(
            RecipeSchemaNormalizer.resolvedCookTime(prepTime: 15, cookTime: 25, totalTime: 60),
            25,
            "an explicit positive cook time wins"
        )
    }

    func testImageURLShapes() {
        XCTAssertEqual(
            RecipeSchemaNormalizer.imageURLStrings(from: "https://example.com/recipe.jpg"),
            ["https://example.com/recipe.jpg"]
        )
        XCTAssertEqual(
            RecipeSchemaNormalizer.imageURLStrings(from: [
                ["@type": "ImageObject", "url": "https://example.com/large.jpg"],
                ["contentUrl": "https://example.com/second.jpg"]
            ]),
            ["https://example.com/large.jpg", "https://example.com/second.jpg"]
        )
    }
}

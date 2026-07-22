import XCTest
@testable import Recipes

@MainActor
final class URLRecipeScraperServiceTests: XCTestCase {
    func testDelishShapedRecipeUsesUsefulStructuredFields() throws {
        let payload: [String: Any] = [
            "@context": "https://schema.org",
            "@type": "Recipe",
            "name": "Meatball Subs",
            "description": "Homemade meatballs with toasted bread.",
            "recipeYield": "4",
            "prepTime": "PT15M",
            "cookTime": "PT0S",
            "totalTime": "PT35M",
            "recipeCategory": [
                "low sugar", "Super Bowl", "tailgate", "weeknight meals",
                "dinner", "lunch", "main dish"
            ],
            "recipeCuisine": [
                "Super Bowl Cuisine", "American (US) Cuisine",
                "Midwestern Cuisine", "American Cuisine"
            ],
            "keywords": [
                "content-type: Recipe", "locale: US", "displayType: recipe",
                "best meatball sub recipe, easy homemade meatball recipe",
                "OCCASION: Super Bowl", "CATEGORY: dinner"
            ],
            "image": [[
                "@type": "ImageObject",
                "url": "https://hips.hearstapps.com/example/meatball-sub.jpg"
            ]],
            "recipeIngredient": [
                "1/2 c. diced celery", "Kosher salt", "1 lb ground beef"
            ],
            "recipeInstructions": [
                ["@type": "HowToStep", "text": "Mix the meatballs."],
                ["@type": "HowToStep", "text": "Bake for 20 minutes."]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let result = try URLRecipeScraperService().parseRecipeSchema(
            data,
            sourceURL: "https://www.delish.com/cooking/recipe-ideas/a51693/meatball-subs-recipe/"
        )
        let recipe = result.recipe

        XCTAssertEqual(recipe.title, "Meatball Subs")
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertEqual(recipe.prepTime, 15)
        XCTAssertEqual(recipe.cookTime, 20)
        XCTAssertEqual(recipe.category, .dinner)
        XCTAssertEqual(recipe.cuisine, "American")
        XCTAssertEqual(recipe.tags, [
            "best meatball sub recipe", "easy homemade meatball recipe",
            "Super Bowl", "dinner"
        ])
        XCTAssertEqual(recipe.ingredients[0].amount, 0.5, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[0].unit, "cup")
        XCTAssertEqual(recipe.ingredients[0].name, "diced celery")
        XCTAssertEqual(recipe.ingredients[1].amount, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[1].name, "Kosher salt")
        XCTAssertEqual(recipe.steps.map(\.instruction), [
            "Mix the meatballs.", "Bake for 20 minutes."
        ])
        XCTAssertEqual(result.imageURLStrings, [
            "https://hips.hearstapps.com/example/meatball-sub.jpg"
        ])
    }
}

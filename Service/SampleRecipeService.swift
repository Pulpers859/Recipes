import Foundation

enum SampleRecipeService {
    static func makeSampleRecipes() -> [Recipe] {
        [
            Recipe(
                title: "Sheet Pan Lemon Chicken",
                summary: "Fast weeknight chicken with roasted vegetables.",
                ingredients: [
                    Ingredient(name: "chicken thighs", amount: 6, unit: ""),
                    Ingredient(name: "baby potatoes", amount: 1.5, unit: "lb"),
                    Ingredient(name: "broccoli florets", amount: 4, unit: "cup"),
                    Ingredient(name: "olive oil", amount: 2, unit: "tbsp"),
                    Ingredient(name: "lemon", amount: 1, unit: ""),
                    Ingredient(name: "garlic", amount: 3, unit: "clove")
                ],
                steps: [
                    RecipeStep(order: 1, instruction: "Preheat oven to 425F and line a sheet pan."),
                    RecipeStep(order: 2, instruction: "Toss chicken and vegetables with oil, lemon zest, and garlic."),
                    RecipeStep(order: 3, instruction: "Roast for 30-35 minutes until chicken is cooked through.", timerSeconds: 2100, timerLabel: "Roast")
                ],
                servings: 4,
                prepTime: 15,
                cookTime: 35,
                category: .dinner,
                tags: ["sheet pan", "meal prep", "high protein"],
                cuisine: "American",
                difficulty: .easy,
                sourceType: .manual
            ),
            Recipe(
                title: "Overnight Protein Oats",
                summary: "No-cook breakfast with oats, yogurt, and berries.",
                ingredients: [
                    Ingredient(name: "rolled oats", amount: 1, unit: "cup"),
                    Ingredient(name: "greek yogurt", amount: 0.5, unit: "cup"),
                    Ingredient(name: "milk", amount: 0.75, unit: "cup"),
                    Ingredient(name: "chia seeds", amount: 1, unit: "tbsp"),
                    Ingredient(name: "blueberries", amount: 0.5, unit: "cup")
                ],
                steps: [
                    RecipeStep(order: 1, instruction: "Mix oats, yogurt, milk, and chia seeds in a jar."),
                    RecipeStep(order: 2, instruction: "Refrigerate overnight.", timerSeconds: 28800, timerLabel: "Chill"),
                    RecipeStep(order: 3, instruction: "Top with berries before serving.")
                ],
                servings: 2,
                prepTime: 10,
                cookTime: 0,
                category: .breakfast,
                tags: ["make ahead", "high protein"],
                cuisine: "American",
                difficulty: .easy,
                sourceType: .manual
            ),
            Recipe(
                title: "20-Minute Turkey Taco Bowls",
                summary: "Lean turkey taco bowls with rice and black beans.",
                ingredients: [
                    Ingredient(name: "ground turkey", amount: 1, unit: "lb"),
                    Ingredient(name: "cooked rice", amount: 3, unit: "cup"),
                    Ingredient(name: "black beans", amount: 1, unit: "can"),
                    Ingredient(name: "taco seasoning", amount: 1.5, unit: "tbsp"),
                    Ingredient(name: "salsa", amount: 0.5, unit: "cup"),
                    Ingredient(name: "shredded cheddar cheese", amount: 0.5, unit: "cup", isOptional: true)
                ],
                steps: [
                    RecipeStep(order: 1, instruction: "Brown turkey in a skillet over medium heat."),
                    RecipeStep(order: 2, instruction: "Add seasoning and a splash of water, then simmer 5 minutes.", timerSeconds: 300, timerLabel: "Simmer"),
                    RecipeStep(order: 3, instruction: "Assemble bowls with rice, beans, turkey, salsa, and cheese.")
                ],
                servings: 4,
                prepTime: 10,
                cookTime: 10,
                category: .lunch,
                tags: ["meal prep", "quick", "high protein"],
                cuisine: "Mexican",
                difficulty: .easy,
                sourceType: .manual
            )
        ]
    }
}

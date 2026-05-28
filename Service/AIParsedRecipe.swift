import Foundation

struct AnthropicTextResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

struct AIParsedRecipe: Decodable {
    let title: String
    let summary: String
    let servings: Int?
    let prepTime: Int?
    let cookTime: Int?
    let category: String?
    let cuisine: String?
    let difficulty: String?
    let tags: [String]?
    let ingredients: [ParsedIngredient]
    let steps: [ParsedStep]

    struct ParsedIngredient: Decodable {
        let name: String
        let amount: Double?
        let unit: String?
        let section: String?
        let isOptional: Bool?
    }

    struct ParsedStep: Decodable {
        let order: Int
        let instruction: String
        let timerSeconds: Int?
        let timerLabel: String?
    }

    func toRecipe(
        sourceType: SourceType,
        sourceURL: String? = nil,
        originalPDFData: Data? = nil
    ) -> Recipe {
        let normalizedIngredients = Ingredient.normalizedList(
            ingredients
                .map {
                    Ingredient(
                        name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        amount: max($0.amount ?? 0, 0),
                        unit: ($0.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        section: ($0.section ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        isOptional: $0.isOptional ?? false
                    )
                }
                .filter { !$0.name.isEmpty }
        )

        let normalizedSteps = steps
            .map {
                (
                    order: $0.order,
                    instruction: $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                    timerSeconds: $0.timerSeconds,
                    timerLabel: $0.timerLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.instruction.isEmpty }
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, step in
                RecipeStep(
                    order: index + 1,
                    instruction: step.instruction,
                    timerSeconds: step.timerSeconds.map { max($0, 0) },
                    timerLabel: step.timerLabel
                )
            }

        return Recipe(
            title: title,
            summary: summary,
            ingredients: normalizedIngredients,
            steps: normalizedSteps,
            servings: max(servings ?? 4, 1),
            prepTime: max(prepTime ?? 0, 0),
            cookTime: max(cookTime ?? 0, 0),
            category: RecipeCategory(rawValue: category ?? "") ?? .other,
            tags: tags ?? [],
            cuisine: cuisine ?? "",
            difficulty: Difficulty(rawValue: difficulty ?? "") ?? .medium,
            sourceURL: sourceURL,
            sourceType: sourceType,
            originalPDFData: originalPDFData
        )
    }
}

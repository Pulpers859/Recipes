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
                    // Clamp to a generous ceiling (7 days) so a hallucinated
                    // timer can't schedule an absurd countdown/notification,
                    // while still allowing long fermentation/brining steps.
                    timerSeconds: step.timerSeconds.map { min(max($0, 0), 604_800) },
                    timerLabel: step.timerLabel
                )
            }

        return Recipe(
            title: title,
            summary: summary,
            ingredients: normalizedIngredients,
            steps: normalizedSteps,
            // Upper-bound servings/times too: AI output is the least-trusted
            // input, and an absurd value would scale ingredients into nonsense.
            servings: min(max(servings ?? 4, 1), 1000),
            prepTime: min(max(prepTime ?? 0, 0), 100_000),
            cookTime: min(max(cookTime ?? 0, 0), 100_000),
            category: RecipeCategory(rawValue: (category ?? "").lowercased()) ?? .other,
            tags: tags ?? [],
            cuisine: cuisine ?? "",
            difficulty: Difficulty(rawValue: (difficulty ?? "").lowercased()) ?? .medium,
            sourceURL: sourceURL,
            sourceType: sourceType,
            originalPDFData: originalPDFData
        )
    }
}

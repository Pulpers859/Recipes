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

    private enum CodingKeys: String, CodingKey {
        case title, summary, servings, prepTime, cookTime
        case category, cuisine, difficulty, tags, ingredients, steps
    }

    /// The model occasionally omits fields it considers empty or emits
    /// numbers as strings ("amount": "1/2"). A strict decode used to throw
    /// the entire response away and fall back to the much weaker manual
    /// parser; salvage what's usable instead. Callers still validate that
    /// the result has ingredients or steps before trusting it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Imported Recipe"
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        servings = Self.flexibleInt(in: c, forKey: .servings)
        prepTime = Self.flexibleInt(in: c, forKey: .prepTime)
        cookTime = Self.flexibleInt(in: c, forKey: .cookTime)
        category = try? c.decode(String.self, forKey: .category)
        cuisine = try? c.decode(String.self, forKey: .cuisine)
        difficulty = try? c.decode(String.self, forKey: .difficulty)
        tags = try? c.decode([String].self, forKey: .tags)
        ingredients = ((try? c.decode([Failable<ParsedIngredient>].self, forKey: .ingredients)) ?? [])
            .compactMap { $0.value }
        steps = ((try? c.decode([Failable<ParsedStep>].self, forKey: .steps)) ?? [])
            .compactMap { $0.value }
    }

    /// Wrapper that swallows a single element's decode failure so one
    /// malformed ingredient/step doesn't discard the rest.
    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    private static func flexibleInt(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        if let text = try? container.decode(String.self, forKey: key) {
            let amount = IngredientLineParser.parseFractionAmount(text)
            if amount > 0 { return Int(amount.rounded()) }
        }
        return nil
    }

    struct ParsedIngredient: Decodable {
        let name: String
        let amount: Double?
        let unit: String?
        let section: String?
        let isOptional: Bool?

        private enum CodingKeys: String, CodingKey {
            case name, amount, unit, section, isOptional
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            if let value = try? c.decode(Double.self, forKey: .amount) {
                amount = value
            } else if let text = try? c.decode(String.self, forKey: .amount) {
                // "1/2", "1 1/2", "0.5" — reuse the shared fraction parser.
                let parsed = IngredientLineParser.parseFractionAmount(text)
                amount = parsed > 0 ? parsed : nil
            } else {
                amount = nil
            }
            unit = try? c.decode(String.self, forKey: .unit)
            section = try? c.decode(String.self, forKey: .section)
            isOptional = try? c.decode(Bool.self, forKey: .isOptional)
        }
    }

    struct ParsedStep: Decodable {
        let order: Int?
        let instruction: String
        let timerSeconds: Int?
        let timerLabel: String?

        private enum CodingKeys: String, CodingKey {
            case order, instruction, timerSeconds, timerLabel
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            instruction = try c.decode(String.self, forKey: .instruction)
            order = (try? c.decode(Int.self, forKey: .order))
                ?? (try? c.decode(Double.self, forKey: .order)).map { Int($0) }
            timerSeconds = (try? c.decode(Int.self, forKey: .timerSeconds))
                ?? (try? c.decode(Double.self, forKey: .timerSeconds)).map { Int($0) }
            timerLabel = try? c.decode(String.self, forKey: .timerLabel)
        }
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
            .enumerated()
            .map { index, step in
                (
                    order: step.order ?? index + 1,
                    position: index,
                    instruction: step.instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                    timerSeconds: step.timerSeconds,
                    timerLabel: step.timerLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.instruction.isEmpty }
            // Tie-break on original position: Swift's sort isn't stable, and
            // AI output sometimes repeats order values.
            .sorted { ($0.order, $0.position) < ($1.order, $1.position) }
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

import Foundation

/// Offline parsing heuristics for the PDF/image import pipeline: recipe
/// boundary detection and the manual (no-AI) text parser.
///
/// Extracted verbatim from `RecipeParserService` so the golden import corpus
/// and unit tests can exercise them without PDFKit/Vision/UIKit — this was a
/// move, not a rewrite; `RecipeParserService` delegates here. Behavior changes
/// belong in this file, guarded by the corpus scores.
nonisolated enum RecipeTextHeuristics {

    // MARK: - Extracted Text Repair

    /// Undoes character-level corruption that PDF text extraction produces for
    /// subsetted fonts.
    ///
    /// A cookbook PDF can embed a font subset whose glyphs sit at low custom
    /// codes. When extraction falls back to reading those codes as ASCII
    /// instead of applying the font's ToUnicode map, real characters come out
    /// as unrelated punctuation. Confirmed on a real import: the `fl` ligature
    /// arrived as `!` ("!our"), `/` as `%` ("1 1%3 CUP"), and `:` as `&`
    /// ("MACROS& 43C").
    ///
    /// This is not cosmetic. `splitIntoRecipeChunks` looks for "MACROS:" to
    /// find where a recipe starts, so the `&` corruption made a three-recipe
    /// cookbook import as ONE merged recipe. It also corrupts quantities,
    /// which is the thing this app most has to get right — "1 1%3 CUP" is not
    /// a number anyone can shop from.
    ///
    /// Every rule is deliberately guarded so legitimate text survives. On the
    /// source file these were derived from, they correct 17 occurrences and
    /// leave all 12 genuine uses (`2% plain greek yogurt`, `GARLIC POWDER &
    /// SALT`, `LUNCH & DINNER`) untouched.
    static func repairExtractedText(_ text: String) -> String {
        var repaired = text
        for rule in repairRules {
            repaired = repaired.replacingOccurrences(
                of: rule.pattern,
                with: rule.template,
                options: .regularExpression
            )
        }
        return repaired
    }

    private static let repairRules: [(pattern: String, template: String)] = [
        // "1 1%3 CUP" -> "1 1/3 CUP". Digits required on BOTH sides, so a real
        // percentage ("2% plain greek yogurt", "93% lean") is never touched —
        // those are always followed by a space or end of word.
        (#"(?<=\d)%(?=\d)"#, "/"),
        // "GARLIC SALT%PEPPER" -> "GARLIC SALT/PEPPER". A percent wedged
        // between two letters with no spaces is never legitimate prose.
        (#"(?<=\p{L})%(?=\p{L})"#, "/"),
        // "MACROS& 43C" -> "MACROS: 43C". A letter before and whitespace after
        // is the signature of a corrupted colon; it leaves "GARLIC POWDER &
        // SALT", "LUNCH & DINNER", "M&M" and "AT&T" alone, since those all
        // have either a space before the ampersand or a letter after it.
        (#"(?<=\p{L})&(?=\s|$)"#, ":"),
        // "!our" -> "flour". "!" never legally appears at the START of a word,
        // so a "!" that opens one is the fl ligature glyph. Requiring a
        // non-letter before it keeps real exclamations ("Wow!great") intact.
        (#"(?<!\p{L})!(?=\p{Ll})"#, "fl"),
    ]

    // MARK: - Recipe Boundary Detection

    /// Tuned for macro-style cookbook PDFs where each recipe starts on a page
    /// listing ingredients alongside macros/calories/servings. Traditional
    /// cookbooks where one recipe spans pages can still split wrong — the
    /// import summary tells the user to verify multi-recipe results.
    private static let ingredientsRegex = try? NSRegularExpression(pattern: #"(?i)ingredients"#)
    private static let recipeStartSupportRegexes: [NSRegularExpression] = {
        [
            #"(?i)macros\s*[:%]"#,
            #"(?i)calories\s*[:%]"#,
            #"(?i)servings\s*[:%]"#,
        ].compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Splits page texts into recipe chunks by detecting recipe boundaries.
    static func splitIntoRecipeChunks(pageTexts: [String]) -> [String] {
        // Score each page for "looks like a recipe start". An ingredients
        // section is required — macros + calories alone also match nutrition
        // summary or index pages, which used to cause bogus splits.
        var recipeStartPages: [Int] = []
        for (index, pageText) in pageTexts.enumerated() {
            let range = NSRange(pageText.startIndex..., in: pageText)

            guard ingredientsRegex?.firstMatch(in: pageText, range: range) != nil else {
                continue
            }

            let supportScore = recipeStartSupportRegexes
                .filter { $0.firstMatch(in: pageText, range: range) != nil }
                .count
            if supportScore >= 1 {
                recipeStartPages.append(index)
            }
        }

        // If we found fewer than 2 recipe starts, treat as single recipe
        if recipeStartPages.count <= 1 {
            return [pageTexts.joined(separator: "\n\n")]
        }

        // Build chunks: each recipe is from its start page to the next recipe's start page
        var chunks: [String] = []
        for (i, startPage) in recipeStartPages.enumerated() {
            let endPage = i + 1 < recipeStartPages.count
                ? recipeStartPages[i + 1]
                : pageTexts.count

            let chunk = pageTexts[startPage..<endPage].joined(separator: "\n\n")

            // Skip tiny chunks (likely table of contents or cover pages)
            if chunk.trimmingCharacters(in: .whitespacesAndNewlines).count > 100 {
                chunks.append(chunk)
            }
        }

        return chunks
    }

    // MARK: - Manual Parsing (Offline)

    private enum ManualParseSection {
        case preamble, ingredients, steps
    }

    /// `@MainActor` only because it constructs `Recipe` (a SwiftData model,
    /// main-actor-isolated under the project's default isolation) — the
    /// parsing logic itself has no actor requirements.
    @MainActor
    static func manualParse(text: String, pdfData: Data?) -> Recipe {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let title = lines.first(where: { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count < 3 { return false }
            if t.allSatisfy({ $0.isNumber || $0.isWhitespace }) { return false }
            let lower = t.lowercased()
            if lower == "table of contents" || lower == "contents" || lower == "index" { return false }
            return true
        }) ?? "Imported Recipe"

        let measurementPattern = #"(\d+[\./]?\d*|[¼½¾⅓⅔⅛⅜⅝⅞])\s*(cup|cups|tbsp|tsp|tablespoon|teaspoon|oz|ounce|lb|lbs|pound|g|gram|kg|ml|l|pinch|clove|cloves|can|cans|package|bunch|stick|sticks|piece|pieces|slices?)s?\b"#
        let measurementRegex = try? NSRegularExpression(pattern: measurementPattern, options: .caseInsensitive)
        let numberedStepRegex = try? NSRegularExpression(pattern: #"^(\d+[\.\)]\s+|step\s+\d+)"#, options: .caseInsensitive)
        let actionVerbPattern = #"(?i)^(heat|preheat|boil|simmer|bake|roast|fry|saute|sauté|grill|broil|steam|stir|whisk|mix|combine|blend|chop|dice|mince|slice|cut|peel|drain|rinse|add|pour|place|put|set|spread|layer|serve|garnish|toss|fold|cook|season|marinate|soak|reduce|bring|let|cover|remove|transfer|arrange|brush|coat|wrap|roll|shape|form|knead|rise|rest|cool|chill|refrigerate|freeze|thaw|melt|dissolve|beat|cream|sift|measure|line|grease|spray|in a|using a|take|make|prepare|meanwhile|once|when|after|before|while|carefully|gently|slowly|quickly|immediately|finally|next|then)\b"#
        let actionVerbRegex = try? NSRegularExpression(pattern: actionVerbPattern, options: .caseInsensitive)

        var ingredients: [Ingredient] = []
        var stepLines: [String] = []
        var section: ManualParseSection = .preamble

        func isHeader(_ line: String, _ keywords: [String]) -> Bool {
            let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
            return keywords.contains(lower)
        }

        for line in lines.dropFirst() {
            // Explicit section headers are the most reliable boundary signal.
            if isHeader(line, ["ingredients", "ingredient list", "what you need", "you will need"]) {
                section = .ingredients
                continue
            }
            if isHeader(line, ["instructions", "directions", "method", "steps", "preparation", "how to make it"]) {
                section = .steps
                continue
            }

            let range = NSRange(line.startIndex..., in: line)
            let looksMeasured = measurementRegex?.firstMatch(in: line, range: range) != nil
            let looksNumberedStep = numberedStepRegex?.firstMatch(in: line, range: range) != nil

            switch section {
            case .steps:
                stepLines.append(stripStepNumber(from: line))
            case .ingredients:
                if looksMeasured {
                    // A measured line is an ingredient even if it happens to be
                    // numbered ("1. 2 cups flour"); check this before the
                    // numbered-step heuristic so numbered ingredient lists
                    // aren't flipped wholesale into steps.
                    ingredients.append(IngredientLineParser.parse(line))
                } else if looksNumberedStep {
                    section = .steps
                    stepLines.append(stripStepNumber(from: line))
                } else if looksLikeInstruction(line, actionVerbRegex: actionVerbRegex) {
                    section = .steps
                    stepLines.append(line)
                } else {
                    // Short unmeasured line, e.g. "salt and pepper to taste".
                    ingredients.append(IngredientLineParser.parse(line))
                }
            case .preamble:
                if looksMeasured {
                    section = .ingredients
                    ingredients.append(IngredientLineParser.parse(line))
                } else if looksNumberedStep {
                    section = .steps
                    stepLines.append(stripStepNumber(from: line))
                }
                // Anything else before the first ingredient is headers,
                // page furniture, or summary text — skip it.
            }
        }

        let steps = stepLines.enumerated().map { idx, text in
            RecipeStep(order: idx + 1, instruction: text)
        }

        return Recipe(
            title: title,
            summary: "",
            ingredients: Ingredient.normalizedList(ingredients),
            steps: steps,
            sourceType: .pdf,
            notes: "Imported with the basic local parser — double-check ingredients and steps.\n\nOriginal text:\n\(String(text.prefix(2000)))",
            originalPDFData: pdfData
        )
    }

    /// A line in the ingredients section should only be promoted to a step
    /// when it genuinely reads like an instruction — not just because it's
    /// long or ends with a period. Ingredient lines like "1 28-oz can San
    /// Marzano whole peeled tomatoes, drained and crushed" are long and may
    /// end with a period, but they are not instructions.
    static func looksLikeInstruction(_ line: String, actionVerbRegex: NSRegularExpression?) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 30 else { return false }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let startsWithVerb = actionVerbRegex?.firstMatch(in: trimmed, range: range) != nil

        // Multiple complete sentences are a strong signal for instructions.
        let sentenceCount = trimmed.components(separatedBy: ". ")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count

        if startsWithVerb && sentenceCount >= 2 { return true }
        if startsWithVerb && trimmed.count > 100 { return true }
        if sentenceCount >= 3 { return true }

        return false
    }

    static func stripStepNumber(from line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+[\.\)]\s+|step\s+\d+[:\.\s]*)"#, options: .caseInsensitive) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        let stripped = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        return stripped.isEmpty ? line : stripped
    }
}

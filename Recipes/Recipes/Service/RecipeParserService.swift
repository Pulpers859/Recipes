import Foundation
import Combine
import PDFKit
import Vision
import UIKit

// MARK: - Recipe Parser Service

/// Dual-mode recipe parsing: Claude API (smart) or local OCR/text extraction (offline)
/// Supports both single-recipe and multi-recipe (cookbook) PDF imports.
class RecipeParserService: ObservableObject {
    @Published var isProcessing = false
    @Published var parseProgress: String = ""
    @Published var lastError: String?

    private var apiKey: String {
        APIKeyStore.loadClaudeKey() ?? ""
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    private var modelID: String {
        AIModelSettings.currentModelID
    }

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()
    
    enum ParseMode {
        case ai
        case manual
        case auto
    }
    
    // MARK: - Public API
    
    /// Parse a PDF that may contain ONE or MANY recipes. Returns an array.
    @MainActor
    func parseRecipes(from pdfData: Data, mode: ParseMode = .auto) async throws -> [Recipe] {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // Step 1: Extract selectable text per page.
        parseProgress = "Extracting text from PDF..."
        var pageTexts = try extractTextByPage(from: pdfData)

        // Step 2: Decide OCR per PAGE, not per document. A scanned cookbook
        // with one digital cover page (or a text watermark layer) used to
        // skip OCR entirely because "the PDF has text" — and then imported
        // the cover page alone as the recipe. OCR any page whose selectable
        // text is too thin to be a real content page.
        let thinPageIndices = pageTexts.indices.filter {
            pageTexts[$0].trimmingCharacters(in: .whitespacesAndNewlines).count < 40
        }
        if !thinPageIndices.isEmpty {
            parseProgress = thinPageIndices.count == pageTexts.count
                ? "No selectable text. Running OCR..."
                : "Scanning \(thinPageIndices.count) page(s) without selectable text..."
            let ocrTexts = try await ocrPages(thinPageIndices, from: pdfData)
            for (index, text) in ocrTexts {
                // Keep the original selectable text (however short) when OCR
                // comes back empty — a failed OCR pass must never destroy
                // real text like a decorative title page.
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pageTexts[index] = text
                }
            }
        }

        let allText = pageTexts.joined(separator: "\n")
        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ParserError.ocrFailed
        }

        // Step 3: Detect if this is a multi-recipe document
        let recipeChunks = splitIntoRecipeChunks(pageTexts: pageTexts)

        if recipeChunks.count <= 1 {
            let recipe = try await parseSingleText(allText, pdfData: pdfData, mode: mode)
            return [recipe]
        }

        return try await parseMultipleChunks(recipeChunks, pdfData: pdfData, mode: mode)
    }

    // MARK: - Multi-Chunk Parsing

    @MainActor
    private func parseMultipleChunks(_ chunks: [String], pdfData: Data?, mode: ParseMode) async throws -> [Recipe] {
        parseProgress = "Found \(chunks.count) recipe(s)..."

        // Slot per chunk so recovered recipes land back at their original
        // document position instead of being appended after the successes.
        var slots: [Recipe?] = Array(repeating: nil, count: chunks.count)
        var failedChunks: [(index: Int, text: String)] = []
        for (index, chunk) in chunks.enumerated() {
            parseProgress = "Parsing recipe \(index + 1) of \(chunks.count)..."
            do {
                slots[index] = try await parseSingleText(chunk, pdfData: nil, mode: mode)
            } catch {
                failedChunks.append((index, chunk))
            }
        }

        // Append the skip summary to any earlier warning (e.g. per-chunk
        // truncation notices) instead of replacing it.
        func reportSkipped(_ count: Int) {
            let message = "Skipped \(count) of \(chunks.count) detected recipe sections that couldn't be parsed."
            lastError = [lastError, message].compactMap { $0 }.joined(separator: "\n")
        }

        var leftovers: [Recipe] = []
        if !failedChunks.isEmpty && hasAPIKey {
            parseProgress = "Retrying \(failedChunks.count) section(s) with batch AI extraction..."
            if let recovered = try? await aiBatchParse(chunks: failedChunks.map(\.text), pdfData: nil) {
                if recovered.count == failedChunks.count {
                    // One recipe per failed chunk: restore document order.
                    for (recipe, failure) in zip(recovered, failedChunks) {
                        slots[failure.index] = recipe
                    }
                } else {
                    // The AI merged or split sections; order is unknowable.
                    leftovers = recovered
                }
                let stillMissing = failedChunks.count - recovered.count
                if stillMissing > 0 {
                    reportSkipped(stillMissing)
                }
            } else {
                reportSkipped(failedChunks.count)
            }
        } else if !failedChunks.isEmpty {
            reportSkipped(failedChunks.count)
        }

        var recipes = slots.compactMap { $0 }
        recipes.append(contentsOf: leftovers)

        if recipes.isEmpty {
            throw ParserError.parseError("Could not extract any recipes from the document")
        }

        recipes[0].originalPDFData = pdfData
        return recipes
    }

    /// Parse a single recipe from an image
    @MainActor
    func parseRecipeFromImage(_ imageData: Data, mode: ParseMode = .auto) async throws -> Recipe {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        parseProgress = "Running OCR on image..."
        let text = try await ocrFromImage(data: imageData)
        let recipe = try await parseSingleText(text, pdfData: nil, mode: mode)
        recipe.sourceType = .image
        // OCR uses the full-resolution original; store a downscaled copy so a
        // 15 MB camera photo doesn't live in the database forever.
        recipe.photoData = [ImageDataNormalizer.normalizedJPEGData(from: imageData) ?? imageData]
        return recipe
    }
    
    // MARK: - Page-by-Page Text Extraction
    
    private func extractTextByPage(from pdfData: Data) throws -> [String] {
        guard let document = PDFDocument(data: pdfData) else {
            throw ParserError.invalidPDF
        }
        
        var pages: [String] = []
        for i in 0..<document.pageCount {
            let text = document.page(at: i)?.string ?? ""
            pages.append(text)
        }
        return pages
    }
    
    // MARK: - Recipe Boundary Detection
    
    /// Splits page texts into recipe chunks by detecting recipe boundaries.
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

    private func splitIntoRecipeChunks(pageTexts: [String]) -> [String] {
        // Score each page for "looks like a recipe start". An ingredients
        // section is required — macros + calories alone also match nutrition
        // summary or index pages, which used to cause bogus splits.
        var recipeStartPages: [Int] = []
        for (index, pageText) in pageTexts.enumerated() {
            let range = NSRange(pageText.startIndex..., in: pageText)

            guard Self.ingredientsRegex?.firstMatch(in: pageText, range: range) != nil else {
                continue
            }

            let supportScore = Self.recipeStartSupportRegexes
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
    
    // MARK: - Single Text → Recipe
    
    private func parseSingleText(_ text: String, pdfData: Data?, mode: ParseMode) async throws -> Recipe {
        switch mode {
        case .ai:
            return try await aiParse(text: text, pdfData: pdfData)
        case .manual:
            return manualParse(text: text, pdfData: pdfData)
        case .auto:
            if hasAPIKey {
                do {
                    return try await aiParse(text: text, pdfData: pdfData)
                } catch {
                    parseProgress = "AI parsing failed, falling back to manual..."
                    // Don't clobber an earlier, more specific warning (e.g. the
                    // truncation notice) with this generic one.
                    if lastError == nil {
                        lastError = "AI parse failed: \(error.localizedDescription). Using manual extraction."
                    }
                    return manualParse(text: text, pdfData: pdfData)
                }
            } else {
                return manualParse(text: text, pdfData: pdfData)
            }
        }
    }
    
    // MARK: - AI Parsing (Single Recipe)
    
    private func aiParse(text: String, pdfData: Data?) async throws -> Recipe {
        parseProgress = "Sending to Claude for structured extraction..."
        
        let systemPrompt = """
        You are a recipe extraction assistant. Given raw text from a recipe document, extract and return ONLY a JSON object (no markdown, no backticks) with this exact structure:
        {
          "title": "Recipe Name",
          "summary": "Brief 1-2 sentence description",
          "servings": 4,
          "prepTime": 15,
          "cookTime": 30,
          "category": "dinner",
          "cuisine": "Italian",
          "difficulty": "medium",
          "tags": ["pasta", "quick"],
          "ingredients": [
            {"name": "spaghetti", "amount": 1.0, "unit": "lb", "section": "", "isOptional": false}
          ],
          "steps": [
            {"order": 1, "instruction": "Boil water...", "timerSeconds": null, "timerLabel": null}
          ]
        }
        
        Rules:
        - category must be one of: breakfast, lunch, dinner, appetizer, snack, dessert, beverage, sauce, bread, soup, salad, side, other
        - difficulty must be one of: easy, medium, hard, expert
        - amounts should be decimals (0.5 not 1/2). For gram amounts like "150G", use amount: 150 and unit: "g"
        - If a step involves waiting/cooking time, include timerSeconds and timerLabel
        - section groups related ingredients (e.g. "Sauce", "Icing") — leave empty if not applicable
        - Ignore social media handles, page numbers, watermarks, and navigation text like "BACK TO CONTENTS"
        - Return ONLY valid JSON, no other text
        """
        
        let maxChars = 12000
        let truncatedText = String(text.prefix(maxChars))
        if text.count > maxChars {
            await MainActor.run {
                let pct = Int(Double(maxChars) / Double(text.count) * 100)
                parseProgress = "Text truncated to \(pct)% for AI — review the result carefully."
                if lastError == nil {
                    lastError = "The recipe text was too long (\(text.count) characters) and was trimmed to \(maxChars) for AI parsing. Some ingredients or steps at the end may be missing."
                }
            }
        }

        let requestBody: [String: Any] = [
            "model": modelID,
            "max_tokens": 4000,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": "Extract the recipe from this text:\n\n\(truncatedText)"]
            ]
        ]

        let responseData = try await callClaudeAPI(requestBody)
        let parsed = try JSONDecoder().decode(AIParsedRecipe.self, from: responseData)
        // A decode that salvaged nothing useful is a failure, not a recipe —
        // let auto mode fall back to the manual parser.
        guard !(parsed.ingredients.isEmpty && parsed.steps.isEmpty) else {
            throw ParserError.parseError("The AI response contained no ingredients or steps")
        }
        return parsed.toRecipe(sourceType: .aiParsed, originalPDFData: pdfData)
    }
    
    // MARK: - AI Batch Parsing (Multiple Recipes)
    
    private func aiBatchParse(chunks: [String], pdfData: Data?) async throws -> [Recipe] {
        parseProgress = "Batch extracting \(chunks.count) recipes with AI..."
        
        // Budget per chunk scales with count so the total stays within the
        // context window (~100k tokens ≈ ~400k chars). Each recipe rarely
        // exceeds 6k chars of useful text even in verbose cookbooks.
        let perChunkLimit = min(8000, max(3000, 40000 / max(chunks.count, 1)))
        var anyTruncated = false
        let allChunksText = chunks.enumerated().map { index, chunk in
            if chunk.count > perChunkLimit { anyTruncated = true }
            return "=== RECIPE \(index + 1) ===\n\(String(chunk.prefix(perChunkLimit)))"
        }.joined(separator: "\n\n")
        if anyTruncated {
            await MainActor.run {
                if lastError == nil {
                    lastError = "Some recipe sections were trimmed for batch AI parsing. Review the results for missing content."
                }
            }
        }
        
        let systemPrompt = """
        You are a recipe extraction assistant. The text contains MULTIPLE recipes separated by "=== RECIPE N ===" markers. Extract ALL recipes and return ONLY a JSON array (no markdown, no backticks):
        [
          {
            "title": "Recipe Name",
            "summary": "Brief description",
            "servings": 4,
            "prepTime": 15,
            "cookTime": 30,
            "category": "breakfast",
            "cuisine": "",
            "difficulty": "easy",
            "tags": [],
            "ingredients": [
              {"name": "ingredient", "amount": 1.0, "unit": "cup", "section": "", "isOptional": false}
            ],
            "steps": [
              {"order": 1, "instruction": "Step text", "timerSeconds": null, "timerLabel": null}
            ]
          }
        ]
        
        Rules:
        - Return a JSON ARRAY of recipe objects, one per recipe found
        - category: breakfast, lunch, dinner, appetizer, snack, dessert, beverage, sauce, bread, soup, salad, side, other
        - difficulty: easy, medium, hard, expert
        - For gram amounts like "150G", use amount: 150, unit: "g"
        - Ignore social media handles, page numbers, watermarks
        - Return ONLY valid JSON array, no other text
        """
        
        let requestBody: [String: Any] = [
            "model": modelID,
            "max_tokens": 8000,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": "Extract all recipes:\n\n\(String(allChunksText.prefix(24000)))"]
            ]
        ]

        let responseData = try await callClaudeAPI(requestBody)
        let parsedArray = try JSONDecoder().decode([AIParsedRecipe].self, from: responseData)

        // Same empty-salvage guard as the single-recipe path: a tolerant
        // decode that salvaged neither ingredients nor steps is a failed
        // section, not a recipe — passing it through would put a blank
        // "Imported Recipe" in batch review and suppress the skip warning.
        return parsedArray
            .filter { !($0.ingredients.isEmpty && $0.steps.isEmpty) }
            .enumerated().map { index, parsed in
                parsed.toRecipe(sourceType: .aiParsed, originalPDFData: index == 0 ? pdfData : nil)
            }
    }
    
    // MARK: - Claude API Call Helper
    
    private func callClaudeAPI(_ requestBody: [String: Any]) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw ParserError.apiError("API key is missing")
        }
        
        guard let endpoint = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ParserError.apiError("Invalid API endpoint URL")
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ParserError.apiError("Invalid API response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let statusCode = httpResponse.statusCode
            let serverMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240) ?? ""
            if serverMessage.isEmpty {
                throw ParserError.apiError("API returned status \(statusCode)")
            }
            throw ParserError.apiError("API returned status \(statusCode): \(serverMessage)")
        }
        
        let apiResponse = try JSONDecoder().decode(AnthropicTextResponse.self, from: data)
        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text,
              let resultData = JSONPayloadExtractor.extract(from: text) else {
            throw ParserError.apiError("No JSON payload in API response")
        }
        
        return resultData
    }
    
    // MARK: - OCR
    
    /// OCRs the given pages (capped at 20 for memory/time) and returns
    /// page index → recognized text.
    private func ocrPages(_ pageIndices: [Int], from data: Data) async throws -> [Int: String] {
        guard let document = PDFDocument(data: data) else {
            throw ParserError.invalidPDF
        }

        let cap = 20
        let selected = pageIndices.filter { $0 < document.pageCount }.sorted()
        let toScan = Array(selected.prefix(cap))
        if selected.count > cap {
            await MainActor.run {
                let skipped = selected.count - cap
                parseProgress = "Only scanning the first \(cap) of \(selected.count) scanned pages (\(skipped) skipped)."
                if lastError == nil {
                    lastError = "This PDF has \(selected.count) pages needing OCR but only the first \(cap) were scanned. The remaining \(skipped) pages were skipped."
                }
            }
        }

        var results: [Int: String] = [:]
        for i in toScan {
            // Per-page resilience: a single page failing Vision (e.g. a blank
            // divider in an otherwise-digital PDF) must not fail the whole
            // import. Whole-document OCR failure still surfaces via the
            // caller's empty-text check.
            let pageText: String = await {
                guard let page = document.page(at: i) else { return "" }
                let bounds = page.bounds(for: .mediaBox)
                // Cap rendering at 150 DPI — sufficient for OCR and avoids
                // blowing memory on large-format pages.
                let maxDim: CGFloat = 2000
                let scale = min(maxDim / max(bounds.width, 1), maxDim / max(bounds.height, 1), 1.0)
                let renderSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

                let cgImage: CGImage? = autoreleasepool {
                    let renderer = UIGraphicsImageRenderer(size: renderSize)
                    let image = renderer.image { ctx in
                        UIColor.white.setFill()
                        ctx.fill(CGRect(origin: .zero, size: renderSize))
                        ctx.cgContext.scaleBy(x: scale, y: scale)
                        ctx.cgContext.translateBy(x: 0, y: bounds.height)
                        ctx.cgContext.scaleBy(x: 1, y: -1)
                        page.draw(with: .mediaBox, to: ctx.cgContext)
                    }
                    return image.cgImage
                }
                guard let cg = cgImage else { return "" }
                return (try? await recognizeText(in: cg)) ?? ""
            }()
            results[i] = pageText
        }
        return results
    }
    
    private func ocrFromImage(data: Data) async throws -> String {
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
            throw ParserError.invalidImage
        }
        return try await recognizeText(in: cgImage)
    }
    
    private func recognizeText(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Vision's perform() is synchronous and heavy; run it on a
            // background queue instead of blocking a concurrency thread.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Manual Parsing (Offline)
    
    private enum ManualParseSection {
        case preamble, ingredients, steps
    }

    private func manualParse(text: String, pdfData: Data?) -> Recipe {
        parseProgress = "Extracting with local parser..."

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
    private func looksLikeInstruction(_ line: String, actionVerbRegex: NSRegularExpression?) -> Bool {
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

    private func stripStepNumber(from line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+[\.\)]\s+|step\s+\d+[:\.\s]*)"#, options: .caseInsensitive) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        let stripped = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        return stripped.isEmpty ? line : stripped
    }
}

// MARK: - Errors

enum ParserError: LocalizedError {
    case invalidPDF
    case invalidImage
    case ocrFailed
    case apiError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Could not read PDF file"
        case .invalidImage: return "Could not read image file"
        case .ocrFailed: return "OCR text recognition failed"
        case .apiError(let msg): return "API error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}

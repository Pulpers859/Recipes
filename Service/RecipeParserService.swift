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
        
        // Step 1: Extract text per page
        parseProgress = "Extracting text from PDF..."
        let pageTexts = try extractTextByPage(from: pdfData)
        
        // If no selectable text, try OCR
        let allText = pageTexts.joined(separator: "\n")
        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parseProgress = "No selectable text. Running OCR..."
            let ocrText = try await ocrFromPDF(data: pdfData)
            let recipe = try await parseSingleText(ocrText, pdfData: pdfData, mode: mode)
            return [recipe]
        }
        
        // Step 2: Detect if this is a multi-recipe document
        let recipeChunks = splitIntoRecipeChunks(pageTexts: pageTexts)
        
        parseProgress = "Found \(recipeChunks.count) recipe(s)..."
        
        if recipeChunks.count <= 1 {
            // Single recipe — use existing flow
            let recipe = try await parseSingleText(allText, pdfData: pdfData, mode: mode)
            return [recipe]
        }
        
        // Step 3: Parse each chunk
        var recipes: [Recipe] = []
        for (index, chunk) in recipeChunks.enumerated() {
            parseProgress = "Parsing recipe \(index + 1) of \(recipeChunks.count)..."
            
            do {
                let recipe = try await parseSingleText(chunk, pdfData: nil, mode: mode)
                recipes.append(recipe)
            } catch {
                // If one recipe fails, continue with the rest
                lastError = "Skipped recipe \(index + 1): \(error.localizedDescription)"
            }
        }
        
        // If AI batch is available, try batch parsing for better results
        if recipes.isEmpty && hasAPIKey {
            parseProgress = "Trying batch AI extraction..."
            recipes = try await aiBatchParse(chunks: recipeChunks, pdfData: pdfData)
        }
        
        if recipes.isEmpty {
            throw ParserError.parseError("Could not extract any recipes from the document")
        }
        
        // Store original PDF on the first recipe
        if !recipes.isEmpty {
            recipes[0].originalPDFData = pdfData
        }
        
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
        recipe.photoData = [imageData]
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
    /// Looks for patterns like: recipe titles followed by ingredients/instructions sections.
    private static let recipeStartRegexes: [NSRegularExpression] = {
        [
            #"(?i)ingredients"#,
            #"(?i)macros\s*[:%]"#,
            #"(?i)calories\s*[:%]"#,
            #"(?i)servings\s*[:%]"#,
        ].compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private func splitIntoRecipeChunks(pageTexts: [String]) -> [String] {
        let regexes = Self.recipeStartRegexes
        
        // Score each page for "looks like a recipe start"
        var recipeStartPages: [Int] = []
        for (index, pageText) in pageTexts.enumerated() {
            let range = NSRange(pageText.startIndex..., in: pageText)
            var score = 0
            for regex in regexes {
                if regex.firstMatch(in: pageText, range: range) != nil {
                    score += 1
                }
            }
            // If page has 2+ indicators, it's likely a recipe start
            if score >= 2 {
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
                    lastError = "AI parse failed: \(error.localizedDescription). Using manual extraction."
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
        
        let truncatedText = String(text.prefix(12000))
        
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
        return parsed.toRecipe(sourceType: .aiParsed, originalPDFData: pdfData)
    }
    
    // MARK: - AI Batch Parsing (Multiple Recipes)
    
    private func aiBatchParse(chunks: [String], pdfData: Data?) async throws -> [Recipe] {
        parseProgress = "Batch extracting \(chunks.count) recipes with AI..."
        
        // Send all chunks in one request for efficiency
        let allChunksText = chunks.enumerated().map { index, chunk in
            "=== RECIPE \(index + 1) ===\n\(String(chunk.prefix(3000)))"
        }.joined(separator: "\n\n")
        
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
        
        return parsedArray.enumerated().map { index, parsed in
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
    
    private func ocrFromPDF(data: Data) async throws -> String {
        guard let document = PDFDocument(data: data) else {
            throw ParserError.invalidPDF
        }
        
        var allText = ""
        for i in 0..<min(document.pageCount, 20) {
            if let page = document.page(at: i) {
                let bounds = page.bounds(for: .mediaBox)
                let renderer = UIGraphicsImageRenderer(size: bounds.size)
                let image = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(bounds)
                    ctx.cgContext.translateBy(x: 0, y: bounds.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                if let cgImage = image.cgImage {
                    let pageText = try await recognizeText(in: cgImage)
                    allText += pageText + "\n\n"
                }
            }
        }
        return allText
    }
    
    private func ocrFromImage(data: Data) async throws -> String {
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
            throw ParserError.invalidImage
        }
        return try await recognizeText(in: cgImage)
    }
    
    private func recognizeText(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Manual Parsing (Offline)
    
    private func manualParse(text: String, pdfData: Data?) -> Recipe {
        parseProgress = "Extracting with local parser..."
        
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let title = lines.first ?? "Imported Recipe"
        
        let measurementPattern = #"(\d+[\./]?\d*)\s*(cup|cups|tbsp|tsp|oz|lb|lbs|g|kg|ml|l|pinch|clove|cloves|can|cans|package|bunch|stick|sticks|piece|pieces|slices?)s?\b"#
        let regex = try? NSRegularExpression(pattern: measurementPattern, options: .caseInsensitive)
        
        var ingredients: [Ingredient] = []
        var stepLines: [String] = []
        var foundIngredientSection = false
        
        for line in lines.dropFirst() {
            let range = NSRange(line.startIndex..., in: line)
            if let _ = regex?.firstMatch(in: line, range: range) {
                foundIngredientSection = true
                ingredients.append(Ingredient(name: line, amount: 0, unit: "", section: ""))
            } else if foundIngredientSection && line.count > 20 {
                stepLines.append(line)
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
            notes: "Original text:\n\(String(text.prefix(2000)))",
            originalPDFData: pdfData
        )
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

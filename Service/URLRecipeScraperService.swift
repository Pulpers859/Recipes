import Foundation
import Combine

/// Fetches a recipe from a URL by:
/// 1. Looking for JSON-LD structured data (schema.org/Recipe) — most recipe sites use this
/// 2. Falling back to sending raw page text to Claude API for extraction
class URLRecipeScraperService: ObservableObject {
    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var lastError: String?
    
    private var apiKey: String {
        APIKeyStore.loadClaudeKey() ?? ""
    }
    
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // MARK: - Public API
    
    @MainActor
    func scrapeRecipe(from urlString: String, allowAI: Bool = true) async throws -> Recipe {
        let url = try validatedWebURL(from: urlString)
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        // Fetch page HTML
        statusMessage = "Fetching page..."
        let (data, response) = try await urlSession.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ScraperError.fetchFailed
        }
        
        let html: String
        if let utf8 = String(data: data, encoding: .utf8) {
            html = utf8
        } else if let ascii = String(data: data, encoding: .ascii) {
            html = ascii
        } else {
            throw ScraperError.decodeFailed
        }
        
        // Strategy 1: Try JSON-LD extraction (fast, accurate, no API needed)
        statusMessage = "Looking for structured recipe data..."
        if let recipe = try? extractJSONLD(from: html, sourceURL: url.absoluteString) {
            statusMessage = "Found structured recipe data!"
            return recipe
        }
        
        // Strategy 2: Send cleaned text to Claude API
        if allowAI && !apiKey.isEmpty {
            statusMessage = "No structured data found. Sending to Claude for extraction..."
            let cleanedText = stripHTML(html)
            return try await aiExtract(text: cleanedText, sourceURL: url.absoluteString)
        }
        
        // Strategy 3: Basic fallback — just create a recipe shell with the raw text
        statusMessage = "Creating recipe from page text..."
        let cleanedText = stripHTML(html)
        return basicExtract(text: cleanedText, sourceURL: url.absoluteString)
    }
    
    // MARK: - JSON-LD Extraction
    
    private func extractJSONLD(from html: String, sourceURL: String) throws -> Recipe {
        // Find all <script type="application/ld+json"> blocks
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        
        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[jsonRange])
            
            guard let jsonData = jsonString.data(using: .utf8) else { continue }
            
            // Could be a single object or an array
            if let recipe = try? parseRecipeSchema(jsonData, sourceURL: sourceURL) {
                return recipe
            }
            
            // Try as array
            if let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                for item in array {
                    if let itemData = try? JSONSerialization.data(withJSONObject: item),
                       let recipe = try? parseRecipeSchema(itemData, sourceURL: sourceURL) {
                        return recipe
                    }
                }
            }
            
            // Try as @graph
            if let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let graph = obj["@graph"] as? [[String: Any]] {
                for item in graph {
                    if let itemData = try? JSONSerialization.data(withJSONObject: item),
                       let recipe = try? parseRecipeSchema(itemData, sourceURL: sourceURL) {
                        return recipe
                    }
                }
            }
        }
        
        throw ScraperError.noStructuredData
    }
    
    private func parseRecipeSchema(_ data: Data, sourceURL: String) throws -> Recipe {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScraperError.parseError
        }
        
        // Verify it's a Recipe type
        let isRecipeType: Bool = {
            if let type = json["@type"] as? String, type == "Recipe" { return true }
            if let types = json["@type"] as? [String], types.contains("Recipe") { return true }
            return false
        }()
        
        guard isRecipeType else {
            throw ScraperError.notRecipeType
        }
        
        let title = json["name"] as? String ?? "Imported Recipe"
        let summary = json["description"] as? String ?? ""
        
        // Parse yield/servings
        let servings: Int = {
            if let yield = json["recipeYield"] as? String {
                return extractFirstInteger(from: yield) ?? 4
            }
            if let yield = json["recipeYield"] as? [String], let first = yield.first {
                return extractFirstInteger(from: first) ?? 4
            }
            if let yield = json["recipeYield"] as? Int {
                return yield
            }
            return 4
        }()
        
        // Parse times (ISO 8601 duration → minutes)
        let prepTime = parseDuration(json["prepTime"] as? String)
        let cookTime = parseDuration(json["cookTime"] as? String)
        
        // Parse ingredients
        let ingredientStrings = json["recipeIngredient"] as? [String] ?? []
        let ingredients = ingredientStrings.map { str -> Ingredient in
            parseIngredientString(str)
        }
        
        // Parse instructions
        let steps: [RecipeStep] = {
            if let instructions = json["recipeInstructions"] as? [String] {
                return instructions.enumerated().map { idx, text in
                    RecipeStep(order: idx + 1, instruction: text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if let instructions = json["recipeInstructions"] as? [[String: Any]] {
                return instructions.enumerated().compactMap { idx, obj in
                    let text = obj["text"] as? String ?? obj["name"] as? String ?? ""
                    guard !text.isEmpty else { return nil }
                    return RecipeStep(order: idx + 1, instruction: text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if let instructions = json["recipeInstructions"] as? String {
                return instructions.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .enumerated()
                    .map { RecipeStep(order: $0.offset + 1, instruction: $0.element) }
            }
            return []
        }()
        
        // Parse category
        let categoryStr = (json["recipeCategory"] as? String)?.lowercased() ?? ""
        let category = RecipeCategory(rawValue: categoryStr) ?? guessCategory(categoryStr)
        
        // Parse cuisine
        let cuisine = json["recipeCuisine"] as? String
            ?? (json["recipeCuisine"] as? [String])?.first
            ?? ""
        
        // Parse keywords/tags
        let tags: [String] = {
            if let keywords = json["keywords"] as? String {
                return keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            if let keywords = json["keywords"] as? [String] {
                return keywords
            }
            return []
        }()
        
        return Recipe(
            title: title,
            summary: cleanHTMLEntities(summary),
            ingredients: ingredients,
            steps: steps,
            servings: servings,
            prepTime: prepTime,
            cookTime: cookTime,
            category: category,
            tags: tags,
            cuisine: cuisine,
            difficulty: guessDifficulty(prepTime: prepTime, cookTime: cookTime, stepCount: steps.count),
            sourceURL: sourceURL,
            sourceType: .url
        )
    }
    
    // MARK: - AI Extraction (Claude API)
    
    private var modelID: String {
        UserDefaults.standard.string(forKey: "ai_model_id") ?? "claude-sonnet-4-20250514"
    }

    private func aiExtract(text: String, sourceURL: String) async throws -> Recipe {
        guard !apiKey.isEmpty else {
            throw ScraperError.apiError
        }

        guard let endpoint = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ScraperError.apiError
        }

        let truncated = String(text.prefix(10000))

        let systemPrompt = """
        You are a recipe extraction assistant. Extract the recipe from this web page text and return ONLY a JSON object (no markdown, no backticks) with this structure:
        {"title":"","summary":"","servings":4,"prepTime":0,"cookTime":0,"category":"dinner","cuisine":"","difficulty":"medium","tags":[],"ingredients":[{"name":"","amount":0,"unit":"","section":"","isOptional":false}],"steps":[{"order":1,"instruction":"","timerSeconds":null,"timerLabel":null}]}
        Category must be one of: breakfast, lunch, dinner, appetizer, snack, dessert, beverage, sauce, bread, soup, salad, side, other.
        Difficulty must be one of: easy, medium, hard, expert.
        Return ONLY valid JSON.
        """

        let requestBody: [String: Any] = [
            "model": modelID,
            "max_tokens": 4000,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Extract the recipe:\n\n\(truncated)"]
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ScraperError.apiError
        }
        
        let apiResponse = try JSONDecoder().decode(AnthropicTextResponse.self, from: data)
        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let responseText = textContent.text,
              let recipeData = JSONPayloadExtractor.extract(from: responseText) else {
            throw ScraperError.apiError
        }

        let parsed = try JSONDecoder().decode(AIParsedRecipe.self, from: recipeData)
        return parsed.toRecipe(sourceType: .aiParsed, sourceURL: sourceURL)
    }
    
    // MARK: - Basic Fallback
    
    private func basicExtract(text: String, sourceURL: String) -> Recipe {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return Recipe(
            title: lines.first ?? "Web Recipe",
            summary: "Imported from \(sourceURL) — edit to refine",
            sourceURL: sourceURL,
            sourceType: .url,
            notes: String(text.prefix(3000))
        )
    }
    
    // MARK: - Helpers
    
    private func extractFirstInteger(from text: String) -> Int? {
        guard let match = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[match])
    }
    
    /// Parse ISO 8601 duration (PT30M, PT1H30M) to minutes
    private func parseDuration(_ iso: String?) -> Int {
        guard let iso = iso else { return 0 }
        let normalized = iso.uppercased()
        
        var hours = 0, minutes = 0
        let hourPattern = #"(\d+)H"#
        let minPattern = #"(\d+)M"#
        
        if let match = normalized.range(of: hourPattern, options: .regularExpression) {
            let numStr = normalized[match].dropLast()
            hours = Int(numStr) ?? 0
        }
        if let match = normalized.range(of: minPattern, options: .regularExpression) {
            let numStr = normalized[match].dropLast()
            minutes = Int(numStr) ?? 0
        }
        
        return hours * 60 + minutes
    }
    
    /// Parse an ingredient string like "2 cups all-purpose flour" into components
    private func parseIngredientString(_ str: String) -> Ingredient {
        let cleaned = cleanHTMLEntities(str.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Pattern: optional amount, optional unit, then name
        let pattern = #"^([\d\s¼½¾⅓⅔⅛⅜⅝⅞/.-]+)?\s*(cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|liters?|l|pinch|cloves?|cans?|packages?|bunche?s?|sticks?|pieces?|slices?|heads?)?\s*[.,]?\s*(.+)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, range: range) {
                let amountStr = match.range(at: 1).location != NSNotFound
                    ? (Range(match.range(at: 1), in: cleaned).map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? "")
                    : ""
                let unit = match.range(at: 2).location != NSNotFound
                    ? (Range(match.range(at: 2), in: cleaned).map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? "")
                    : ""
                let name = match.range(at: 3).location != NSNotFound
                    ? (Range(match.range(at: 3), in: cleaned).map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? cleaned)
                    : cleaned
                
                let amount = parseFractionAmount(amountStr)
                
                return Ingredient(name: name, amount: amount, unit: unit)
            }
        }
        
        return Ingredient(name: cleaned)
    }
    
    /// Convert fraction strings to Double: "1 1/2" → 1.5, "¾" → 0.75
    private func parseFractionAmount(_ str: String) -> Double {
        let fractionMap: [Character: Double] = [
            "¼": 0.25, "½": 0.5, "¾": 0.75,
            "⅓": 0.333, "⅔": 0.667,
            "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
        ]
        
        var total: Double = 0
        let parts = str.split(separator: " ")
        
        for part in parts {
            if let unicodeFrac = part.first, let val = fractionMap[unicodeFrac] {
                total += val
            } else if part.contains("/") {
                let fracParts = part.split(separator: "/")
                if fracParts.count == 2,
                   let num = Double(fracParts[0]),
                   let den = Double(fracParts[1]), den > 0 {
                    total += num / den
                }
            } else if let num = Double(part) {
                total += num
            }
        }
        
        return total
    }
    
    /// Strip HTML tags from a string
    private func stripHTML(_ html: String) -> String {
        // Remove script and style blocks first
        var cleaned = html
        let blockPatterns = [
            #"<script[^>]*>[\s\S]*?</script>"#,
            #"<style[^>]*>[\s\S]*?</style>"#,
            #"<nav[^>]*>[\s\S]*?</nav>"#,
            #"<footer[^>]*>[\s\S]*?</footer>"#,
            #"<header[^>]*>[\s\S]*?</header>"#
        ]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ")
            }
        }
        
        // Remove remaining tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            cleaned = tagRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ")
        }
        
        // Clean up whitespace
        cleaned = cleanHTMLEntities(cleaned)
        cleaned = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        
        return cleaned
    }
    
    private func cleanHTMLEntities(_ str: String) -> String {
        str.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
    }
    
    private func guessCategory(_ str: String) -> RecipeCategory {
        let lower = str.lowercased()
        for cat in RecipeCategory.allCases {
            if lower.contains(cat.rawValue) { return cat }
        }
        if lower.contains("main") || lower.contains("entree") || lower.contains("entrée") { return .dinner }
        if lower.contains("starter") { return .appetizer }
        if lower.contains("sweet") || lower.contains("cake") || lower.contains("cookie") { return .dessert }
        if lower.contains("drink") || lower.contains("cocktail") || lower.contains("smoothie") { return .beverage }
        return .other
    }
    
    private func guessDifficulty(prepTime: Int, cookTime: Int, stepCount: Int) -> Difficulty {
        let total = prepTime + cookTime
        if total < 20 && stepCount <= 5 { return .easy }
        if total < 60 && stepCount <= 10 { return .medium }
        if total < 120 { return .hard }
        return .expert
    }
    
    private func validatedWebURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw ScraperError.invalidURL
        }
        
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw ScraperError.invalidURL
        }
        
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw ScraperError.invalidURL
        }
        
        if isBlockedHost(host) {
            throw ScraperError.blockedHost
        }
        
        return url
    }
    
    private func isBlockedHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("169.254.") { return true } // Link-local
        
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let secondOctet = Int(parts[1]), (16...31).contains(secondOctet) {
                return true
            }
        }
        
        return false
    }
    
}

// MARK: - Errors

enum ScraperError: LocalizedError {
    case invalidURL, blockedHost, fetchFailed, decodeFailed, noStructuredData, parseError, notRecipeType, apiError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL format"
        case .blockedHost: return "Local/private network URLs are blocked for safety"
        case .fetchFailed: return "Could not fetch the page"
        case .decodeFailed: return "Could not read page content"
        case .noStructuredData: return "No structured recipe data found"
        case .parseError: return "Could not parse recipe data"
        case .notRecipeType: return "Structured data is not a Recipe type"
        case .apiError: return "AI extraction failed"
        }
    }
}

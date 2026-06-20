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

    // Re-validates every redirect hop so a public page can't 302 us onto a
    // private/loopback host (the classic SSRF blocklist bypass). Held as a
    // stored property so the per-task delegate outlives the request.
    private let redirectGuard = SSRFRedirectGuard()
    
    // MARK: - Public API
    
    @MainActor
    func scrapeRecipe(from urlString: String, allowAI: Bool = true) async throws -> Recipe {
        let url = try validatedWebURL(from: urlString)
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        // Fetch page HTML. The redirect guard re-checks each hop's host so a
        // safe-looking URL can't bounce us onto a private/metadata endpoint.
        statusMessage = "Fetching page..."
        let (data, response) = try await urlSession.data(from: url, delegate: redirectGuard)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ScraperError.fetchFailed
        }
        
        let html: String
        if let utf8 = String(data: data, encoding: .utf8) {
            html = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            // Latin-1 accepts any byte sequence, so legacy-encoded pages
            // (Windows-1252 etc.) still import instead of failing outright.
            html = latin1
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
        
        // Verify it's a Recipe type. Match on a "Recipe" suffix so namespaced
        // forms like "http://schema.org/Recipe" are recognised, not just the
        // bare "Recipe" string.
        let isRecipeType: Bool = {
            func matches(_ value: String) -> Bool {
                let v = value.trimmingCharacters(in: .whitespaces)
                return v == "Recipe" || v.hasSuffix("/Recipe") || v.hasSuffix("Recipe")
            }
            if let type = json["@type"] as? String, matches(type) { return true }
            if let types = json["@type"] as? [String], types.contains(where: matches) { return true }
            return false
        }()
        
        guard isRecipeType else {
            throw ScraperError.notRecipeType
        }
        
        let title = cleanHTMLEntities(json["name"] as? String ?? "Imported Recipe")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = json["description"] as? String ?? ""
        
        // Parse yield/servings. schema.org allows a string ("4 servings"), an
        // array, a bare number, or a QuantitativeValue object {"value": 4}.
        let servings: Int = {
            if let yield = json["recipeYield"] as? String {
                return extractFirstInteger(from: yield) ?? 4
            }
            if let yield = json["recipeYield"] as? [Any], let first = yield.first {
                if let s = first as? String { return extractFirstInteger(from: s) ?? 4 }
                if let n = first as? NSNumber { return max(1, n.intValue) }
            }
            if let yield = json["recipeYield"] as? NSNumber {
                return max(1, yield.intValue)
            }
            if let yield = json["recipeYield"] as? [String: Any],
               let value = yield["value"] {
                if let n = value as? NSNumber { return max(1, n.intValue) }
                if let s = value as? String { return extractFirstInteger(from: s) ?? 4 }
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
        
        // Parse instructions. Handles plain strings, arrays of strings,
        // HowToStep objects, and HowToSection groups (whose steps live in
        // itemListElement and were previously dropped entirely).
        let steps: [RecipeStep] = {
            guard let rawInstructions = json["recipeInstructions"] else { return [] }

            var texts: [String]
            if let plain = rawInstructions as? String {
                texts = plain.components(separatedBy: "\n")
            } else {
                texts = collectInstructionTexts(rawInstructions)
            }

            // Some sites cram the whole method into one string with no line
            // breaks. Left alone that becomes a single giant "step"; split a
            // long single blob into sentences so each instruction stands alone.
            let nonEmpty = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if nonEmpty.count == 1, let only = nonEmpty.first, only.count > 200 {
                texts = splitInstructionSentences(only)
            }

            return texts
                .map { cleanHTMLEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { RecipeStep(order: $0.offset + 1, instruction: $0.element) }
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
            servings: min(max(servings, 1), 1000),
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
    
    /// Recursively flattens schema.org recipeInstructions values into plain
    /// step texts. Supports HowToStep objects and nested HowToSection groups.
    private func collectInstructionTexts(_ value: Any) -> [String] {
        if let text = value as? String {
            return [text]
        }
        if let array = value as? [Any] {
            return array.flatMap { collectInstructionTexts($0) }
        }
        if let object = value as? [String: Any] {
            if let nested = object["itemListElement"] {
                return collectInstructionTexts(nested)
            }
            if let text = object["text"] as? String, !text.isEmpty {
                return [text]
            }
            if let name = object["name"] as? String, !name.isEmpty {
                return [name]
            }
        }
        return []
    }

    /// Splits a run-together instruction blob into sentences. Breaks only on a
    /// period/!/? followed by whitespace and a capital letter or digit, so it
    /// separates real steps ("...golden. Remove from heat.") without cutting
    /// decimals ("1.5 cups") or abbreviations mid-number. Falls back to the
    /// whole blob as a single step if nothing splits cleanly.
    private func splitInstructionSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[.!?])\s+(?=[A-Z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }

        let ns = text as NSString
        var pieces: [String] = []
        var lastEnd = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match else { return }
            let piece = ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            pieces.append(piece)
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < ns.length {
            pieces.append(ns.substring(from: lastEnd))
        }

        let cleaned = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
        return cleaned.count > 1 ? cleaned : [text]
    }

    // MARK: - AI Extraction (Claude API)
    
    private var modelID: String {
        AIModelSettings.currentModelID
    }

    private func aiExtract(text: String, sourceURL: String) async throws -> Recipe {
        guard !apiKey.isEmpty else {
            throw ScraperError.apiError("no API key is configured")
        }

        guard let endpoint = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ScraperError.apiError(nil)
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
            // Array form with ephemeral cache_control so the static system
            // prompt is prompt-cached across imports, matching the PDF parser.
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScraperError.apiError(nil)
        }
        guard httpResponse.statusCode == 200 else {
            // Surface the status and server message so a bad key (401), rate
            // limit (429), or overload (529) are distinguishable instead of all
            // reading as a generic "AI extraction failed".
            let serverMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240) ?? ""
            let detail = serverMessage.isEmpty
                ? "status \(httpResponse.statusCode)"
                : "status \(httpResponse.statusCode): \(serverMessage)"
            throw ScraperError.apiError(detail)
        }

        let apiResponse = try JSONDecoder().decode(AnthropicTextResponse.self, from: data)
        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let responseText = textContent.text,
              let recipeData = JSONPayloadExtractor.extract(from: responseText) else {
            throw ScraperError.apiError("the AI response did not contain readable recipe data")
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
    
    /// Parse ISO 8601 duration (PT30M, PT1H30M, P1DT2H, PT45S) to minutes.
    /// Minutes are read from the *time* component (after `T`) so the month
    /// designator in a fully-qualified duration like `P0Y0M0DT30M` can't be
    /// mistaken for 30 minutes.
    private func parseDuration(_ iso: String?) -> Int {
        guard let iso = iso else { return 0 }
        let normalized = iso.uppercased()

        // Split date portion (days/months/years) from time portion (H/M/S).
        let timePart: Substring
        let datePart: Substring
        if let tIndex = normalized.firstIndex(of: "T") {
            datePart = normalized[normalized.startIndex..<tIndex]
            timePart = normalized[normalized.index(after: tIndex)...]
        } else {
            datePart = Substring(normalized)
            timePart = ""
        }

        func number(before designator: Character, in text: Substring) -> Int {
            let pattern = "(\\d+)\(designator)"
            guard let match = text.range(of: pattern, options: .regularExpression) else { return 0 }
            return Int(text[match].dropLast()) ?? 0
        }

        let days = number(before: "D", in: datePart)
        let hours = number(before: "H", in: timePart)
        let minutes = number(before: "M", in: timePart)
        let seconds = number(before: "S", in: timePart)

        return days * 24 * 60 + hours * 60 + minutes + (seconds >= 30 ? 1 : 0)
    }
    
    /// Parse an ingredient string like "2 cups all-purpose flour" into
    /// components. Entity-decodes first, then defers to the shared parser so
    /// URL and PDF fallbacks split lines identically.
    private func parseIngredientString(_ str: String) -> Ingredient {
        IngredientLineParser.parse(cleanHTMLEntities(str))
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
        var result = str
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        // Decode numeric entities (decimal and hex), e.g. &#8217; → ’
        if result.contains("&#"),
           let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#, options: .caseInsensitive) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let hexFlagRange = Range(match.range(at: 1), in: result),
                      let digitsRange = Range(match.range(at: 2), in: result) else { continue }
                let isHex = !result[hexFlagRange].isEmpty
                guard let code = UInt32(result[digitsRange], radix: isHex ? 16 : 10),
                      let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        // &amp; must be decoded last so "&amp;lt;" doesn't double-decode to "<"
        return result.replacingOccurrences(of: "&amp;", with: "&")
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

        switch URLSafetyValidator.validate(url) {
        case .allowed:
            return url
        case .invalid:
            throw ScraperError.invalidURL
        case .blocked:
            throw ScraperError.blockedHost
        }
    }

}

// MARK: - URL Safety

/// Centralised SSRF protection shared by the initial request and the redirect
/// guard. String-prefix checks alone are easy to bypass (decimal/hex IPs,
/// IPv6 ULA), so we normalise the host before matching. DNS rebinding — a
/// public name that resolves to a private IP — is not defeated here; that
/// requires validating the *resolved* address at connect time.
enum URLSafetyValidator {
    enum Result { case allowed, invalid, blocked }

    static func validate(_ url: URL) -> Result {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return .invalid
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .invalid
        }
        return isBlockedHost(host) ? .blocked : .allowed
    }

    static func isAllowed(_ url: URL) -> Bool {
        validate(url) == .allowed
    }

    static func isBlockedHost(_ rawHost: String) -> Bool {
        // URL.host strips brackets from IPv6 literals; normalise just in case.
        let host = rawHost
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        if host.isEmpty { return true }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }

        // IPv6 loopback / unspecified / link-local / unique-local (fc00::/7).
        if host.contains(":") {
            if host == "::1" || host == "::" { return true }
            if host.hasPrefix("fe80:") { return true }          // link-local
            if host.hasPrefix("fc") || host.hasPrefix("fd") { return true } // ULA
            if host.hasPrefix("::ffff:") { return true }         // IPv4-mapped
            return false
        }

        // Dotted-quad IPv4 in private / loopback / link-local / CGNAT ranges.
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("169.254.") { return true }
        if host == "0.0.0.0" { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let secondOctet = Int(parts[1]), (16...31).contains(secondOctet) {
                return true
            }
        }
        if host.hasPrefix("100.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let secondOctet = Int(parts[1]), (64...127).contains(secondOctet) {
                return true // carrier-grade NAT 100.64.0.0/10
            }
        }

        // Non-dotted numeric forms (decimal "2130706433", hex "0x7f000001")
        // resolve to IPv4 addresses and bypass the dotted-quad checks above.
        if host.hasPrefix("0x") { return true }
        if !host.contains("."), host.allSatisfy({ $0.isNumber }) { return true }

        // Octal-encoded dotted IPv4 (e.g. "0177.0.0.1" == 127.0.0.1). Only flag
        // a fully-numeric dotted literal that has a leading-zero octet, so real
        // hostnames like "0123.example.com" or public IPs like "93.184.216.34"
        // are not falsely blocked.
        let components = host.split(separator: ".")
        let looksNumericLiteral = components.count >= 2 && components.allSatisfy { comp in
            !comp.isEmpty && comp.allSatisfy { $0.isNumber }
        }
        if looksNumericLiteral, components.contains(where: { $0.count > 1 && $0.hasPrefix("0") }) {
            return true
        }

        return false
    }
}

/// Per-task delegate that cancels any redirect to a host that wouldn't have
/// passed the initial safety check, closing the redirect-based SSRF hole.
final class SSRFRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url, URLSafetyValidator.isAllowed(url) {
            completionHandler(request)
        } else {
            // nil cancels the redirect; the task finishes with the 3xx response
            // and the caller's status-code guard rejects it.
            completionHandler(nil)
        }
    }
}

// MARK: - Errors

enum ScraperError: LocalizedError {
    case invalidURL, blockedHost, fetchFailed, decodeFailed, noStructuredData, parseError, notRecipeType
    case apiError(String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL format"
        case .blockedHost: return "Local/private network URLs are blocked for safety"
        case .fetchFailed: return "Could not fetch the page"
        case .decodeFailed: return "Could not read page content"
        case .noStructuredData: return "No structured recipe data found"
        case .parseError: return "Could not parse recipe data"
        case .notRecipeType: return "Structured data is not a Recipe type"
        case .apiError(let detail):
            if let detail, !detail.isEmpty { return "AI extraction failed (\(detail))" }
            return "AI extraction failed"
        }
    }
}

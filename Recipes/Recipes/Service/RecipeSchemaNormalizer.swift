import Foundation

/// Normalizes the loose, publisher-specific values found in schema.org Recipe
/// JSON-LD into stable Recipe Vault fields.
enum RecipeSchemaNormalizer {
    static func category(from candidates: [String]) -> RecipeCategory {
        let cleaned = candidates.map(normalizedLabel).filter { !$0.isEmpty }

        for candidate in cleaned {
            if let exact = RecipeCategory(rawValue: candidate.lowercased()) {
                return exact
            }
        }

        for candidate in cleaned {
            let lower = candidate.lowercased()
            if lower.contains("main dish") || lower.contains("main course")
                || lower.contains("entree") || lower.contains("entrée") {
                return .dinner
            }
            if lower.contains("starter") || lower.contains("hors d'oeuvre") {
                return .appetizer
            }
            for category in RecipeCategory.allCases where category != .other {
                if lower.contains(category.rawValue) { return category }
            }
        }

        return .other
    }

    static func cuisine(from candidates: [String]) -> String {
        let normalized = candidates
            .map(normalizedCuisine)
            .filter { !$0.isEmpty && !looksLikeMachineMetadata($0) }
        guard !normalized.isEmpty else { return "" }

        let recognized = normalized.filter { candidate in
            let lower = candidate.lowercased()
            return cuisineTerms.contains { lower.contains($0) }
        }
        return (recognized.isEmpty ? normalized : recognized)
            .enumerated()
            .min { lhs, rhs in
                lhs.element.count == rhs.element.count
                    ? lhs.offset < rhs.offset
                    : lhs.element.count < rhs.element.count
            }?.element ?? ""
    }

    static func tags(from rawKeywords: [String], limit: Int = 16) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for raw in rawKeywords {
            for fragment in raw.split(separator: ",", omittingEmptySubsequences: true) {
                var candidate = normalizedLabel(String(fragment))
                guard !candidate.isEmpty else { continue }

                if let colon = candidate.firstIndex(of: ":") {
                    let key = String(candidate[..<colon])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    let value = String(candidate[candidate.index(after: colon)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if droppedMetadataKeys.contains(key) { continue }
                    if humanKeywordKeys.contains(key) {
                        candidate = value
                    }
                }

                guard !candidate.isEmpty, candidate.count <= 60,
                      candidate.lowercased() != "true", candidate.lowercased() != "false",
                      URL(string: candidate)?.scheme == nil,
                      UUID(uuidString: candidate) == nil
                else { continue }

                let identity = candidate.lowercased()
                guard seen.insert(identity).inserted else { continue }
                result.append(candidate)
                if result.count == limit { return result }
            }
        }

        return result
    }

    static func resolvedCookTime(prepTime: Int, cookTime: Int, totalTime: Int) -> Int {
        if cookTime > 0 { return cookTime }
        if totalTime > prepTime { return totalTime - prepTime }
        return max(0, cookTime)
    }

    static func imageURLStrings(from value: Any?) -> [String] {
        var values: [String] = []

        func collect(_ item: Any?) {
            if let string = item as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { values.append(trimmed) }
                return
            }
            if let items = item as? [Any] {
                items.forEach(collect)
                return
            }
            if let object = item as? [String: Any] {
                for key in ["url", "contentUrl", "thumbnailUrl"] {
                    if let string = object[key] as? String {
                        collect(string)
                        break
                    }
                }
            }
        }

        collect(value)
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func normalizedLabel(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedCuisine(_ value: String) -> String {
        normalizedLabel(value)
            .replacingOccurrences(
                of: #"\s+cuisine$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeMachineMetadata(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("content-type:") || lower.contains("contentid:")
            || lower.contains("displaytype:") || lower.contains("locale:")
    }

    private static let droppedMetadataKeys: Set<String> = [
        "content-type", "locale", "displaytype", "shorttitle", "contentid",
        "subsection", "collection", "sponsored", "issyndicated", "totaltime", "filtertime"
    ]

    private static let humanKeywordKeys: Set<String> = ["nutrition", "occasion", "category", "diet"]

    private static let cuisineTerms = [
        "african", "american", "brazilian", "british", "cajun", "caribbean",
        "chinese", "creole", "ethiopian", "french", "german", "greek",
        "indian", "irish", "italian", "japanese", "korean", "mediterranean",
        "mexican", "middle eastern", "midwestern", "moroccan", "peruvian",
        "southern", "spanish", "thai", "tex-mex", "vietnamese"
    ]
}

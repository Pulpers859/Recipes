import Foundation
import SwiftData

struct ConflictResolutionResult {
    let mergedRecipes: Int
    let deletedDuplicates: Int
    /// IDs of the deleted duplicates, so the caller can clean up external
    /// state (Spotlight) AFTER its save succeeds — removing index entries
    /// before the save could roll back left ghosts either way.
    let deletedRecipeIDs: [UUID]
}

enum RecipeConflictResolverService {
    static func resolveRecipeConflicts(recipes: [Recipe], modelContext: ModelContext) -> ConflictResolutionResult {
        var mergedRecipes = 0
        var deletedDuplicates = 0
        var deletedIDs: [UUID] = []
        var deletedIDSet = Set<UUID>()

        func process(_ groups: [[Recipe]]) {
            for group in groups {
                let liveGroup = group.filter { !deletedIDSet.contains($0.id) }
                guard liveGroup.count > 1 else { continue }
                // Deterministic winner: highest quality, then oldest (stable
                // dateAdded), then id. Plain `max(by:)` over equal scores is
                // arbitrary, which made *which* record survived — and therefore
                // its dateAdded/id/spotlight entry — change run to run.
                guard let canonical = liveGroup.max(by: { lhs, rhs in
                    let ls = qualityScore(lhs), rs = qualityScore(rhs)
                    if ls != rs { return ls < rs }
                    if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
                    return lhs.id.uuidString > rhs.id.uuidString
                }) else { continue }
                // A matching group key alone is not proof of duplication.
                // Only delete when the ingredients agree enough.
                let duplicates = liveGroup.filter {
                    $0.id != canonical.id && isConfidentDuplicate($0, of: canonical)
                }
                guard !duplicates.isEmpty else { continue }

                for duplicate in duplicates {
                    merge(source: duplicate, into: canonical)
                    // Planned meals pointing at the duplicate follow the merged
                    // recipe instead of silently orphaning.
                    MealPlanningService.retargetEntries(
                        fromRecipeID: duplicate.id,
                        to: canonical,
                        modelContext: modelContext
                    )
                    deletedIDs.append(duplicate.id)
                    deletedIDSet.insert(duplicate.id)
                    modelContext.delete(duplicate)
                    deletedDuplicates += 1
                }

                mergedRecipes += 1
            }
        }

        // Pass 1: exact duplicates — same title and identical normalized
        // ingredient names (the shared library fingerprint).
        process(Array(Dictionary(grouping: recipes, by: fingerprint).values))

        // Pass 2: same title + same source URL. This catches the most common
        // real duplicate — the same page re-imported with slightly different
        // parsed ingredient names — which pass 1 can never group (its key IS
        // the ingredient list). The overlap threshold below still protects
        // deliberately edited variants.
        let withURL = recipes.filter {
            !deletedIDSet.contains($0.id)
                && !($0.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let byTitleAndURL = Dictionary(grouping: withURL) { recipe in
            recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                + "::"
                + (recipe.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        process(Array(byTitleAndURL.values))

        return ConflictResolutionResult(
            mergedRecipes: mergedRecipes,
            deletedDuplicates: deletedDuplicates,
            deletedRecipeIDs: deletedIDs
        )
    }

    /// When a non-empty source URL matches, that's strong evidence of
    /// duplication. For title-only matches, require the ingredient lists to
    /// substantially overlap before destructively merging.
    private nonisolated static func isConfidentDuplicate(_ candidate: Recipe, of canonical: Recipe) -> Bool {
        let candidateKeys = ingredientKeySet(candidate)
        let canonicalKeys = ingredientKeySet(canonical)

        // Both empty — structurally identical stubs, safe to fold.
        if candidateKeys.isEmpty && canonicalKeys.isEmpty { return true }

        // One has ingredients and the other doesn't — not safe to assume duplicate.
        if candidateKeys.isEmpty || canonicalKeys.isEmpty { return false }

        let overlap = candidateKeys.intersection(canonicalKeys).count
        let union = candidateKeys.union(canonicalKeys).count
        guard union > 0 else { return true }

        let source = (canonical.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // A shared source URL is strong evidence but still require some
        // ingredient agreement to avoid deleting user-edited variants.
        let threshold = source.isEmpty ? 0.8 : 0.5
        return Double(overlap) / Double(union) >= threshold
    }

    private nonisolated static func ingredientKeySet(_ recipe: Recipe) -> Set<String> {
        Set(recipe.normalizedIngredients.map {
            ShoppingListService.normalizedIngredientKey($0.name)
        })
    }

    private nonisolated static func fingerprint(_ recipe: Recipe) -> String {
        RecipeLibraryMaintenance.fingerprint(for: recipe)
    }
    
    private nonisolated static func qualityScore(_ recipe: Recipe) -> Int {
        var score = 0
        score += recipe.ingredients.count * 2
        score += recipe.steps.count * 3
        score += recipe.tags.count
        score += recipe.rating * 2
        score += recipe.timesCooked * 2
        if recipe.isFavorite { score += 4 }
        if !recipe.summary.isEmpty { score += 2 }
        if !recipe.notes.isEmpty { score += 2 }
        if !recipe.photoData.isEmpty { score += 4 }
        if recipe.originalPDFData != nil { score += 2 }
        return score
    }
    
    private static func merge(source: Recipe, into target: Recipe) {
        if target.summary.isEmpty, !source.summary.isEmpty {
            target.summary = source.summary
        }
        if target.cuisine.isEmpty, !source.cuisine.isEmpty {
            target.cuisine = source.cuisine
        }
        if target.sourceURL == nil, source.sourceURL != nil {
            target.sourceURL = source.sourceURL
        }
        if target.notes.isEmpty, !source.notes.isEmpty {
            target.notes = source.notes
        }
        
        target.tags = Array(Set(target.tags + source.tags)).sorted()
        
        if target.ingredients.isEmpty, !source.ingredients.isEmpty {
            target.ingredients = source.ingredients
        }
        if target.steps.isEmpty, !source.steps.isEmpty {
            target.steps = source.steps
        }
        if target.photoData.isEmpty, !source.photoData.isEmpty {
            target.photoData = source.photoData
        }
        if target.originalPDFData == nil, source.originalPDFData != nil {
            target.originalPDFData = source.originalPDFData
        }
        
        target.isFavorite = target.isFavorite || source.isFavorite
        target.rating = max(target.rating, source.rating)
        target.timesCooked = max(target.timesCooked, source.timesCooked)
        target.dateLastCooked = maxDate(target.dateLastCooked, source.dateLastCooked)
        target.dateAdded = min(target.dateAdded, source.dateAdded)
    }
    
    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.some(let l), .some(let r)): return max(l, r)
        case (.some(let l), .none): return l
        case (.none, .some(let r)): return r
        case (.none, .none): return nil
        }
    }
}

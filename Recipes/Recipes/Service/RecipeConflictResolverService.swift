import Foundation
import SwiftData

struct ConflictResolutionResult {
    let mergedRecipes: Int
    let deletedDuplicates: Int
}

enum RecipeConflictResolverService {
    static func resolveRecipeConflicts(recipes: [Recipe], modelContext: ModelContext) -> ConflictResolutionResult {
        let grouped = Dictionary(grouping: recipes, by: fingerprint)
        var mergedRecipes = 0
        var deletedDuplicates = 0
        
        for (_, group) in grouped where group.count > 1 {
            // Deterministic winner: highest quality, then oldest (stable
            // dateAdded), then id. Plain `max(by:)` over equal scores is
            // arbitrary, which made *which* record survived — and therefore
            // its dateAdded/id/spotlight entry — change run to run.
            guard let canonical = group.max(by: { lhs, rhs in
                let ls = qualityScore(lhs), rs = qualityScore(rhs)
                if ls != rs { return ls < rs }
                if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
                return lhs.id.uuidString > rhs.id.uuidString
            }) else { continue }
            // A matching title alone is not proof of duplication — two distinct
            // recipes can share a name. Only delete when the ingredients agree
            // (or the recipes share an explicit source URL via the fingerprint).
            let duplicates = group.filter {
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
                SpotlightIndexingService.shared.removeRecipe(duplicate)
                modelContext.delete(duplicate)
                deletedDuplicates += 1
            }

            mergedRecipes += 1
        }
        
        return ConflictResolutionResult(mergedRecipes: mergedRecipes, deletedDuplicates: deletedDuplicates)
    }
    
    /// Recipes in the same fingerprint group share title + source URL. When a
    /// non-empty source URL matches, that's strong evidence of duplication.
    /// For title-only matches, require the ingredient lists to substantially
    /// overlap before destructively merging.
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

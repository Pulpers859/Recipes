import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Spotlight Indexing Service

/// Indexes recipes in Spotlight so users can search them system-wide
class SpotlightIndexingService {
    
    static let shared = SpotlightIndexingService()
    private let domainID = "com.recipevault.recipes"
    private var hasCompletedLaunchIndex = false
    private let launchIndexLock = NSLock()

    /// One full reindex per launch is enough: saves call indexRecipe and
    /// deletes call removeRecipe, so the index stays in sync incrementally.
    /// Previously the whole library was reindexed on every Recipes-tab
    /// appearance, which is wasted work that grows with the library.
    func indexAllRecipesIfNeeded(_ recipes: [Recipe]) {
        // Check-and-set under a lock so two near-simultaneous tab appearances
        // can't both pass the guard and kick off a duplicate full reindex.
        launchIndexLock.lock()
        if hasCompletedLaunchIndex {
            launchIndexLock.unlock()
            return
        }
        hasCompletedLaunchIndex = true
        launchIndexLock.unlock()

        indexAllRecipes(recipes)
    }

    // MARK: - Index a Single Recipe
    
    private func makeSearchableItem(for recipe: Recipe) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = recipe.title
        attributeSet.contentDescription = buildDescription(for: recipe)
        attributeSet.keywords = buildKeywords(for: recipe)
        attributeSet.creator = recipe.cuisine.isEmpty ? nil : recipe.cuisine
        attributeSet.rating = recipe.rating > 0 ? NSNumber(value: recipe.rating) : nil
        attributeSet.duration = recipe.totalTime > 0 ? NSNumber(value: recipe.totalTime * 60) : nil

        let item = CSSearchableItem(
            uniqueIdentifier: recipe.id.uuidString,
            domainIdentifier: domainID,
            attributeSet: attributeSet
        )
        item.expirationDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())
        return item
    }

    func indexRecipe(_ recipe: Recipe) {
        CSSearchableIndex.default().indexSearchableItems([makeSearchableItem(for: recipe)]) { error in
            if let error {
                #if DEBUG
                print("Spotlight indexing error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Index All Recipes

    func indexAllRecipes(_ recipes: [Recipe]) {
        let items = recipes.map { makeSearchableItem(for: $0) }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                #if DEBUG
                print("Spotlight batch indexing error: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // MARK: - Remove from Index
    
    func removeRecipe(_ recipe: Recipe) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [recipe.id.uuidString]
        ) { error in
            if let error {
                #if DEBUG
                print("Spotlight removal error: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    func removeAllRecipes() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainID]
        ) { error in
            if let error {
                #if DEBUG
                print("Spotlight clear error: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // MARK: - Helpers
    
    private func buildDescription(for recipe: Recipe) -> String {
        var parts: [String] = []
        
        if !recipe.summary.isEmpty {
            parts.append(recipe.summary)
        }
        
        parts.append("\(recipe.category.displayName) · \(recipe.difficulty.displayName)")
        
        if recipe.totalTime > 0 {
            parts.append("\(recipe.totalTime) minutes")
        }
        
        if !recipe.cuisine.isEmpty {
            parts.append(recipe.cuisine)
        }
        
        let topIngredients = recipe.ingredients.prefix(5).map { $0.name }.joined(separator: ", ")
        if !topIngredients.isEmpty {
            parts.append("Ingredients: \(topIngredients)")
        }
        
        return parts.joined(separator: " · ")
    }
    
    private func buildKeywords(for recipe: Recipe) -> [String] {
        var keywords = recipe.tags
        keywords.append(recipe.category.displayName)
        keywords.append(recipe.difficulty.displayName)
        
        if !recipe.cuisine.isEmpty {
            keywords.append(recipe.cuisine)
        }
        
        // Add ingredient names as keywords for search
        keywords.append(contentsOf: recipe.ingredients.prefix(10).map { $0.name })
        
        return keywords
    }
}

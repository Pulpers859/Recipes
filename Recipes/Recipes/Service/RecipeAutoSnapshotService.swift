import Foundation
import SwiftData
import UIKit
import CryptoKit

/// Writes an automatic safety snapshot when the app leaves the foreground,
/// but only if the library changed since the last auto-snapshot. This closes
/// the gap where safety backups only ever fired before destructive actions —
/// ordinary edits, imports, and new recipes now produce recovery points too
/// (Settings → Safety Snapshots).
@MainActor
enum RecipeAutoSnapshotService {
    private static let fingerprintDefaultsKey = "recipeAutoSnapshot.lastFingerprint.v1"

    /// Guards against overlapping writes from rapid foreground/background flips.
    private static var isWriting = false
    private static var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    static func snapshotIfChanged(modelContext: ModelContext) {
        guard !isWriting else { return }

        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let pantryItems = (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? []
        let shoppingItems = (try? modelContext.fetch(FetchDescriptor<ShoppingItem>())) ?? []
        let mealPlans = (try? modelContext.fetch(FetchDescriptor<MealPlan>())) ?? []

        // An empty library writes nothing: an all-empty snapshot can't restore
        // anything, and it would evict a real recovery point from the pool.
        guard !recipes.isEmpty || !pantryItems.isEmpty || !shoppingItems.isEmpty || !mealPlans.isEmpty else { return }

        let fingerprint = libraryFingerprint(
            recipes: recipes,
            pantryItems: pantryItems,
            shoppingItems: shoppingItems,
            mealPlans: mealPlans
        )
        guard fingerprint != UserDefaults.standard.string(forKey: fingerprintDefaultsKey) else { return }

        let payload = RecipeExportService.makeBackupPayload(
            recipes: recipes,
            pantryItems: pantryItems,
            shoppingItems: shoppingItems,
            mealPlans: mealPlans
        )

        // iOS suspends the app moments after backgrounding; ask for extra time
        // so a photo-heavy encode isn't killed mid-write.
        isWriting = true
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "RecipeVaultAutoSnapshot") {
            Task { @MainActor in endBackgroundTaskIfNeeded() }
        }
        Task {
            do {
                try await RecipeExportService.writeAutomaticBackup(payload: payload, kind: .auto)
                // Only a durably written snapshot advances the fingerprint, so
                // a failed write is retried on the next backgrounding.
                UserDefaults.standard.set(fingerprint, forKey: fingerprintDefaultsKey)
                AnalyticsService.shared.track("auto_snapshot_written")
            } catch {
                AnalyticsService.shared.track("auto_snapshot_failed")
            }
            isWriting = false
            endBackgroundTaskIfNeeded()
        }
    }

    private static func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Stable digest of everything the backup persists, with raw photo/PDF
    /// bytes represented by their sizes (enough to notice adds, removes, and
    /// swaps without hashing megabytes). Deliberately NOT `Hasher` — its seed
    /// changes every launch, and this value must survive in UserDefaults.
    private static func libraryFingerprint(
        recipes: [Recipe],
        pantryItems: [PantryItem],
        shoppingItems: [ShoppingItem],
        mealPlans: [MealPlan]
    ) -> String {
        var digest = SHA256()
        func feed(_ value: String) {
            digest.update(data: Data(value.utf8))
            digest.update(data: Data([0x1F]))
        }

        feed("v1")
        for recipe in recipes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            feed(recipe.id.uuidString)
            feed(recipe.title)
            feed(recipe.summary)
            feed(recipe.notes)
            feed(recipe.cuisine)
            feed(recipe.category.rawValue)
            feed(recipe.difficulty.rawValue)
            feed(recipe.sourceURL ?? "")
            feed(recipe.sourceType.rawValue)
            feed(recipe.tags.joined(separator: ","))
            feed("\(recipe.servings)|\(recipe.prepTime)|\(recipe.cookTime)|\(recipe.rating)|\(recipe.isFavorite)|\(recipe.timesCooked)")
            feed(recipe.dateLastCooked.map { "\($0.timeIntervalSince1970)" } ?? "")
            for ingredient in recipe.ingredients {
                feed("\(ingredient.name)|\(ingredient.amount)|\(ingredient.unit)|\(ingredient.section)|\(ingredient.isOptional)")
            }
            for step in recipe.steps.sorted(by: { $0.order < $1.order }) {
                feed("\(step.order)|\(step.instruction)|\(step.timerSeconds ?? -1)")
            }
            feed("photos:\(recipe.photoData.count):\(recipe.photoData.reduce(0) { $0 + $1.count })")
            feed("pdf:\(recipe.originalPDFData?.count ?? 0)")
        }
        for item in pantryItems.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            feed("\(item.id.uuidString)|\(item.name)|\(item.amount)|\(item.unit)|\(item.category.rawValue)|\(item.isStaple)")
        }
        for item in shoppingItems.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            feed("\(item.id.uuidString)|\(item.name)|\(item.amount)|\(item.unit)|\(item.category.rawValue)|\(item.isChecked)")
        }
        for plan in mealPlans.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            feed("\(plan.id.uuidString)|\(plan.weekStartDate.timeIntervalSince1970)")
            for entry in plan.entries {
                feed(entry.id.uuidString)
            }
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

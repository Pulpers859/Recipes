import Foundation
import SwiftData

/// Pure orchestration logic for the destructive / data-moving actions exposed
/// in `SettingsView` (import, delete-all, duplicate resolution, fingerprinting).
///
/// This intentionally holds NO view state. Each entry point takes the recipes
/// and the `ModelContext` it needs and returns a user-facing result message,
/// so the view layer is responsible only for surfacing that message. Analytics
/// tracking stays here so the side effects match the previous in-view behavior
/// exactly — this was a behavior-preserving relocation, not a rewrite.
enum RecipeLibraryMaintenance {

    /// Upper bound on an imported backup file, matching the old in-view limit.
    static let maxBackupImportBytes = 50 * 1024 * 1024

    enum MaintenanceError: LocalizedError {
        case backupTooLarge
        case notValidJSON
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .backupTooLarge:
                return "Backup file is larger than 50 MB."
            case .notValidJSON:
                return "Selected file is not valid JSON."
            case .saveFailed(let detail):
                return "Recipes were decoded, but could not be saved: \(detail)"
            }
        }
    }

    // MARK: - Fingerprinting

    /// Stable dedupe key: lowercased title + sorted, lowercased ingredient
    /// names. Identical to the previous `recipeFingerprint(_:)` in the view.
    nonisolated static func fingerprint(for recipe: Recipe) -> String {
        let title = recipe.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ingredientNames = recipe.normalizedIngredients
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .sorted()
            .joined(separator: "|")
        return "\(title)::\(ingredientNames)"
    }

    // MARK: - Import

    /// Imports a JSON backup, skipping records that already exist by
    /// fingerprint. Throws on size / format / save failures so the caller can
    /// surface a failure message; returns the success message otherwise.
    static func importBackup(
        data: Data,
        existingRecipes: [Recipe],
        modelContext: ModelContext
    ) throws -> String {
        guard data.count <= maxBackupImportBytes else {
            throw MaintenanceError.backupTooLarge
        }

        // Validate it looks like JSON before decoding into recipes.
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MaintenanceError.notValidJSON
        }

        let imported = try RecipeExportService.importFromJSON(data: data)
        var existingFingerprints = Set(existingRecipes.map(fingerprint))
        let existingIDs = Set(existingRecipes.map(\.id))
        var insertedCount = 0
        var skippedCount = 0

        for recipe in imported {
            if existingIDs.contains(recipe.id) {
                skippedCount += 1
                continue
            }
            let key = fingerprint(for: recipe)
            if existingFingerprints.contains(key) {
                skippedCount += 1
                continue
            }
            modelContext.insert(recipe)
            existingFingerprints.insert(key)
            insertedCount += 1
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw MaintenanceError.saveFailed(error.localizedDescription)
        }

        AnalyticsService.shared.track("backup_import_json", metadata: [
            "inserted": "\(insertedCount)",
            "skipped": "\(skippedCount)"
        ])

        if skippedCount > 0 {
            return "Imported \(insertedCount) recipes (\(skippedCount) duplicates skipped)."
        } else {
            return "Imported \(insertedCount) recipes successfully!"
        }
    }

    // MARK: - Delete All

    /// Backs up, cleans up meal-plan entries, then deletes every recipe. Never
    /// throws: returns the message to show whether it succeeded or bailed early
    /// (each early exit leaves the store untouched, as before).
    static func deleteAllRecipes(
        _ recipes: [Recipe],
        modelContext: ModelContext
    ) -> String? {
        let count = recipes.count
        guard count > 0 else { return nil }

        // Write a safety backup first so this destructive action is recoverable
        // via "Import from JSON Backup".
        do {
            try RecipeExportService.writeAutomaticBackup(recipes: recipes)
        } catch {
            AnalyticsService.shared.track("recipes_delete_all_backup_failed")
            return "Nothing was deleted because the safety backup could not be written."
        }

        // Meal-plan entries for deleted recipes would linger in the plan UI
        // but silently drop out of shopping-list generation.
        do {
            try MealPlanningService.removeEntries(
                forRecipeIDs: Set(recipes.map { $0.id }),
                modelContext: modelContext
            )
        } catch {
            modelContext.rollback()
            AnalyticsService.shared.track("recipes_delete_all_plan_cleanup_failed")
            return "Nothing was deleted because meal plan cleanup could not be saved: \(error.localizedDescription)"
        }

        for recipe in recipes {
            modelContext.delete(recipe)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AnalyticsService.shared.track("recipes_delete_all_save_failed")
            return "The recipes were not deleted because the change could not be saved: \(error.localizedDescription)"
        }

        SpotlightIndexingService.shared.removeAllRecipes()

        AnalyticsService.shared.track("recipes_all_deleted", metadata: ["count": "\(count)"])
        return "Deleted \(count) recipes. A safety backup was saved on this device."
    }

    // MARK: - Duplicate Resolution

    /// Resolves duplicate recipe conflicts and persists the result. Never
    /// throws: returns the message to show.
    static func resolveConflicts(
        _ recipes: [Recipe],
        modelContext: ModelContext
    ) -> String {
        let result = RecipeConflictResolverService.resolveRecipeConflicts(recipes: recipes, modelContext: modelContext)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AnalyticsService.shared.track("resolve_recipe_conflicts_save_failed")
            return "Duplicate cleanup could not be saved: \(error.localizedDescription)"
        }

        AnalyticsService.shared.track("resolve_recipe_conflicts", metadata: [
            "merged_groups": "\(result.mergedRecipes)",
            "deleted_duplicates": "\(result.deletedDuplicates)"
        ])

        if result.deletedDuplicates == 0 {
            return "No duplicate recipe conflicts found."
        } else {
            return "Resolved \(result.mergedRecipes) conflict group(s), removed \(result.deletedDuplicates) duplicate recipes."
        }
    }
}

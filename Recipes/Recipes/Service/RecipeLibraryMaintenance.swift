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
    /// surface a failure message; otherwise returns the outcome, flagged as an
    /// error when some records could not be read (a partial import must be
    /// presented as a problem, not a success).
    static func importBackup(
        data: Data,
        existingRecipes: [Recipe],
        modelContext: ModelContext
    ) throws -> MaintenanceOutcome {
        guard data.count <= maxBackupImportBytes else {
            throw MaintenanceError.backupTooLarge
        }

        // Validate it looks like JSON before decoding into recipes.
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MaintenanceError.notValidJSON
        }

        let importResult = try RecipeExportService.importFromJSON(data: data)
        let imported = importResult.recipes
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

        // v4 backups can carry pantry, shopping, and meal-plan sections.
        // Merging is strictly additive — nothing existing is deleted or
        // overwritten; records already present (by id or, for pantry, by
        // normalized name) are skipped.
        let restored = mergeAuxiliarySections(from: importResult, modelContext: modelContext)

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

        var message = skippedCount > 0
            ? "Imported \(insertedCount) recipes (\(skippedCount) duplicates skipped)."
            : "Imported \(insertedCount) recipes successfully!"
        if !restored.isEmpty {
            message += " Also restored \(restored.joined(separator: ", "))."
        }
        if importResult.unreadableCount > 0 {
            // A partial import must never read as a full success.
            message += " Warning: \(importResult.unreadableCount) record\(importResult.unreadableCount == 1 ? "" : "s") in the file could not be read and \(importResult.unreadableCount == 1 ? "was" : "were") NOT imported."
        }
        return MaintenanceOutcome(message: message, isError: importResult.unreadableCount > 0)
    }

    /// Additively merges pantry/shopping/meal-plan records from a v4 backup.
    /// Returns human-readable fragments describing what was restored (empty
    /// when the backup carried no auxiliary sections or everything existed).
    private static func mergeAuxiliarySections(
        from importResult: RecipeExportService.ImportResult,
        modelContext: ModelContext
    ) -> [String] {
        var fragments: [String] = []

        if !importResult.pantryItems.isEmpty {
            let existing = (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? []
            let existingIDs = Set(existing.map(\.id))
            let existingKeys = Set(existing.map { ShoppingListService.normalizedIngredientKey($0.name) })
            var added = 0
            for item in importResult.pantryItems
            where !existingIDs.contains(item.id)
                && !existingKeys.contains(ShoppingListService.normalizedIngredientKey(item.name)) {
                modelContext.insert(item)
                added += 1
            }
            if added > 0 { fragments.append("\(added) pantry \(added == 1 ? "item" : "items")") }
        }

        if !importResult.shoppingItems.isEmpty {
            let existing = (try? modelContext.fetch(FetchDescriptor<ShoppingItem>())) ?? []
            let existingIDs = Set(existing.map(\.id))
            var added = 0
            for item in importResult.shoppingItems where !existingIDs.contains(item.id) {
                modelContext.insert(item)
                added += 1
            }
            if added > 0 { fragments.append("\(added) shopping \(added == 1 ? "item" : "items")") }
        }

        if !importResult.mealPlans.isEmpty {
            let existing = (try? modelContext.fetch(FetchDescriptor<MealPlan>())) ?? []
            var added = 0
            for plan in importResult.mealPlans {
                if let match = MealPlanningService.plan(forWeekContaining: plan.weekStartDate, in: existing) {
                    // Same week already planned: append only unseen entries so a
                    // re-import can't duplicate meals.
                    let knownEntryIDs = Set(match.entries.map(\.id))
                    let newEntries = plan.entries.filter { !knownEntryIDs.contains($0.id) }
                    if !newEntries.isEmpty {
                        match.entries = match.entries + newEntries
                        added += 1
                    }
                } else {
                    modelContext.insert(plan)
                    added += 1
                }
            }
            if added > 0 { fragments.append("\(added) meal \(added == 1 ? "plan" : "plans")") }
        }

        return fragments
    }

    /// Outcome of a maintenance action: the user-facing message plus an
    /// explicit success flag, so the UI never has to sniff strings to decide
    /// whether to render a success or failure banner.
    struct MaintenanceOutcome {
        let message: String
        let isError: Bool
    }

    // MARK: - Delete All

    /// Snapshot of the whole library (recipes plus pantry, shopping, and meal
    /// plans fetched from the context) ready for the off-main-thread backup
    /// write. Shared by every destructive path so the rolling safety backup
    /// always carries the full app state.
    @MainActor
    static func fullBackupPayload(
        recipes: [Recipe],
        modelContext: ModelContext
    ) -> RecipeExportService.BackupPayload {
        RecipeExportService.makeBackupPayload(
            recipes: recipes,
            pantryItems: (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? [],
            shoppingItems: (try? modelContext.fetch(FetchDescriptor<ShoppingItem>())) ?? [],
            mealPlans: (try? modelContext.fetch(FetchDescriptor<MealPlan>())) ?? []
        )
    }

    /// Backs up, cleans up meal-plan entries, then deletes every recipe. Never
    /// throws: returns the outcome to show whether it succeeded or bailed early
    /// (each early exit leaves the store untouched, as before). Async because
    /// the safety backup is encoded and written off the main thread; the
    /// caller must block interaction while awaiting.
    @MainActor
    static func deleteAllRecipes(
        _ recipes: [Recipe],
        modelContext: ModelContext
    ) async -> MaintenanceOutcome? {
        let count = recipes.count
        guard count > 0 else { return nil }

        // Write a safety backup first so this destructive action is recoverable
        // via "Import from JSON Backup".
        do {
            let payload = fullBackupPayload(recipes: recipes, modelContext: modelContext)
            try await RecipeExportService.writeAutomaticBackup(payload: payload)
        } catch {
            AnalyticsService.shared.track("recipes_delete_all_backup_failed")
            return MaintenanceOutcome(message: "Nothing was deleted because the safety backup could not be written.", isError: true)
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
            return MaintenanceOutcome(message: "Nothing was deleted because meal plan cleanup could not be saved: \(error.localizedDescription)", isError: true)
        }

        for recipe in recipes {
            modelContext.delete(recipe)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AnalyticsService.shared.track("recipes_delete_all_save_failed")
            return MaintenanceOutcome(message: "The recipes were not deleted because the change could not be saved: \(error.localizedDescription)", isError: true)
        }

        SpotlightIndexingService.shared.removeAllRecipes()

        AnalyticsService.shared.track("recipes_all_deleted", metadata: ["count": "\(count)"])
        return MaintenanceOutcome(message: "Deleted \(count) recipes. A safety backup was saved on this device.", isError: false)
    }

    // MARK: - Duplicate Resolution

    /// Resolves duplicate recipe conflicts and persists the result. Never
    /// throws: returns the outcome to show. Writes the same safety backup as
    /// the other destructive paths BEFORE deleting anything — resolution
    /// permanently removes recipes, and a wrong merge needs a recovery story.
    @MainActor
    static func resolveConflicts(
        _ recipes: [Recipe],
        modelContext: ModelContext
    ) async -> MaintenanceOutcome {
        guard !recipes.isEmpty else {
            return MaintenanceOutcome(message: "No recipes to check for duplicates.", isError: false)
        }

        do {
            let payload = fullBackupPayload(recipes: recipes, modelContext: modelContext)
            try await RecipeExportService.writeAutomaticBackup(payload: payload)
        } catch {
            AnalyticsService.shared.track("resolve_recipe_conflicts_backup_failed")
            return MaintenanceOutcome(message: "Duplicate cleanup did not run because the safety backup could not be written.", isError: true)
        }

        let result = RecipeConflictResolverService.resolveRecipeConflicts(recipes: recipes, modelContext: modelContext)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AnalyticsService.shared.track("resolve_recipe_conflicts_save_failed")
            return MaintenanceOutcome(message: "Duplicate cleanup could not be saved: \(error.localizedDescription)", isError: true)
        }

        // Only after the deletes are durably saved do we drop the Spotlight
        // entries — doing it earlier de-indexed recipes that a failed save
        // then resurrected.
        SpotlightIndexingService.shared.removeRecipes(ids: result.deletedRecipeIDs)

        AnalyticsService.shared.track("resolve_recipe_conflicts", metadata: [
            "merged_groups": "\(result.mergedRecipes)",
            "deleted_duplicates": "\(result.deletedDuplicates)"
        ])

        if result.deletedDuplicates == 0 {
            return MaintenanceOutcome(message: "No duplicate recipe conflicts found.", isError: false)
        } else {
            return MaintenanceOutcome(message: "Resolved \(result.mergedRecipes) conflict group(s), removed \(result.deletedDuplicates) duplicate recipes. A safety backup was saved first.", isError: false)
        }
    }
}

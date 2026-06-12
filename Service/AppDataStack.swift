import Foundation
import SwiftData

enum AppDataStack {
    @MainActor
    static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            MealPlan.self,
            ShoppingItem.self,
            PantryItem.self
        ])

        let config = ModelConfiguration(
            "RecipeVault",
            schema: schema,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: config)
            // Clear any stale failure flag from a previous launch so the UI
            // doesn't warn about a problem that has since resolved.
            UserDefaults.standard.removeObject(forKey: "database_error")
            return container
        } catch {
            let message = "Failed to open recipe database: \(error.localizedDescription)"
            #if DEBUG
            fatalError(message)
            #else
            UserDefaults.standard.set(message, forKey: "database_error")
            let fallback = ModelConfiguration(
                "RecipeVault",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: schema, configurations: fallback)
            } catch {
                fatalError("Failed to create fallback recipe database: \(error.localizedDescription)")
            }
            #endif
        }
    }()
}

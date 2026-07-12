import Foundation
import SwiftData

enum AppDataStack {
    static let databaseErrorKey = "database_error"
    private static let storeBaseName = "RecipeVault"

    @MainActor
    static let sharedContainer: ModelContainer = makeContainer()

    @MainActor
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Recipe.self,
            MealPlan.self,
            ShoppingItem.self,
            PantryItem.self
        ])

        let config = ModelConfiguration(
            storeBaseName,
            schema: schema,
            cloudKitDatabase: .none
        )

        // Attempt 1: normal on-disk open.
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            // Deliberately do NOT clear the failure flag here: after a store
            // reset, the next launch opens the fresh store cleanly, and wiping
            // the flag on success would destroy the "your library was reset; a
            // copy was archived" notice before the user ever acknowledged it.
            // ContentView clears the flag when the alert is dismissed.
            return container
        } catch {
            #if DEBUG
            // Fail loudly in development so schema/migration problems surface
            // immediately instead of being silently "recovered".
            fatalError("Failed to open recipe database: \(error.localizedDescription)")
            #else
            return recover(schema: schema, config: config, openError: error)
            #endif
        }
    }

    /// Recovery path for release builds. Rather than dropping straight to an
    /// in-memory store — which makes the user's whole on-disk library vanish
    /// and silently discards everything they do this session — we move the
    /// unreadable store aside (preserved for manual recovery) and recreate a
    /// fresh store AT THE SAME PATH so new data still persists across launches.
    /// In-memory is only the last resort, and the user is told which happened.
    @MainActor
    private static func recover(schema: Schema, config: ModelConfiguration, openError: Error) -> ModelContainer {
        let archived = archiveCorruptStore()

        // Attempt 2: recreate a fresh on-disk store at the same location.
        if let container = try? ModelContainer(for: schema, configurations: config) {
            let recoveryNote = archived
                ? "Your recipe library couldn't be opened and was reset to an empty library. A copy of the old data was kept on this device for recovery, and new changes will be saved normally from now on."
                : "Your recipe library couldn't be opened and was reset to an empty library. New changes will be saved normally from now on."
            UserDefaults.standard.set(recoveryNote, forKey: databaseErrorKey)
            return container
        }

        // Attempt 3 (last resort): in-memory so the app at least launches.
        UserDefaults.standard.set(
            "Your recipe library could not be opened, so the app is running on temporary storage. Changes made now will NOT be saved. Restart the app — if this keeps happening, reinstall.",
            forKey: databaseErrorKey
        )
        let fallback = ModelConfiguration(
            storeBaseName,
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try ModelContainer(for: schema, configurations: fallback)
        } catch {
            fatalError("Failed to create fallback recipe database: \(error.localizedDescription)")
        }
    }

    /// Moves the on-disk store files aside (timestamped) so a fresh store can
    /// be created at the same path while the old data is preserved for manual
    /// recovery. Returns true if anything was moved. If the store lives
    /// somewhere other than the assumed path, this is a no-op and the caller
    /// still falls through safely — no worse than the previous behaviour.
    private static func archiveCorruptStore() -> Bool {
        let fm = FileManager.default
        guard let supportDir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return false }

        let stamp = Int(Date().timeIntervalSince1970)
        var movedAny = false
        // SwiftData persists a named configuration as "<name>.store" plus its
        // SQLite WAL/SHM sidecar files in the application support directory.
        for suffix in ["store", "store-wal", "store-shm"] {
            let source = supportDir.appendingPathComponent("\(storeBaseName).\(suffix)")
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = supportDir.appendingPathComponent("\(storeBaseName)-corrupt-\(stamp).\(suffix)")
            if (try? fm.moveItem(at: source, to: destination)) != nil {
                movedAny = true
            }
        }
        return movedAny
    }
}

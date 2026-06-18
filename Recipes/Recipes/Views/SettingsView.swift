import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    
    @AppStorage("default_servings") private var defaultServings = 4
    @AppStorage("parse_mode") private var parseMode = "auto"
    @AppStorage("ai_model_id") private var aiModelID = AIModelSettings.defaultModelID
    @AppStorage("keep_screen_awake") private var keepScreenAwake = true
    @AppStorage("analytics_enabled") private var analyticsEnabled = true
    
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var tempAPIKey = ""
    @State private var showImportPicker = false
    @State private var exportMessage: String?
    @State private var importResult: String?
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var syncResult: String?
    @State private var showDeleteAllConfirm = false
    @State private var apiKeySource: APIKeyStore.KeySource?

    private let maxBackupImportBytes = 50 * 1024 * 1024
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RVDesign.sectionSpacing) {
                    RVHeroBanner(
                        title: "Settings",
                        subtitle: "Tune imports, protect your library, and keep Recipe Vault reliable.",
                        systemImage: "gearshape.fill",
                        metrics: [
                            ("Recipes", "\(recipes.count)"),
                            ("Favorites", "\(recipes.filter { $0.isFavorite }.count)")
                        ]
                    )

                    aiParsingCard
                    cookingCard
                    dataCard
                    maintenanceCard
                    analyticsCard
                    libraryCard
                    aboutCard
                }
                .padding(RVDesign.screenPadding)
                .padding(.bottom, 28)
            }
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rvBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showImportPicker) {
                JSONBackupDocumentPicker { pickedURL in
                    showImportPicker = false
                    importFromPickedFile(url: pickedURL)
                } onCancel: {
                    showImportPicker = false
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onAppear {
                AIModelSettings.migrateStoredModelIfNeeded()
                loadAPIKeyIfNeeded()
                AnalyticsService.shared.setAnalyticsEnabled(analyticsEnabled)
            }
            .alert("Delete all recipes?", isPresented: $showDeleteAllConfirm) {
                Button("Delete All", role: .destructive) { deleteAllRecipes() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all \(recipes.count) recipe(s). A safety backup will be saved on this device first.")
            }
        }
    }

    private var aiParsingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(
                title: "AI Recipe Parsing",
                subtitle: "Better extraction for messy PDFs, screenshots, and recipe pages."
            )

            HStack(spacing: 12) {
                Image(systemName: "brain.fill")
                    .foregroundStyle(Color.rvAccent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Claude API Key")
                        .font(.headline)
                        .foregroundStyle(Color.rvInk)
                    Text(apiKeyStatusText)
                        .font(.caption)
                        .foregroundStyle(apiKey.isEmpty ? Color.rvTaupe : Color.rvPrimary)
                }

                Spacer()
            }

            if showAPIKey {
                SecureField("sk-ant-...", text: $tempAPIKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .rvInsetField()

                HStack(spacing: 10) {
                    Button {
                        saveAPIKey(tempAPIKey)
                        showAPIKey = false
                    } label: {
                        Label("Save Key", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.rvAccent)
                    .disabled(tempAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel") {
                        showAPIKey = false
                        tempAPIKey = apiKey
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button(apiKey.isEmpty ? "Add API Key" : (apiKeySource == .bundledConfig ? "Override API Key" : "Change API Key")) {
                    tempAPIKey = apiKey
                    showAPIKey = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rvAccent)

                if apiKeySource == .keychain {
                    Button("Remove Saved API Key", role: .destructive) {
                        removeAPIKey()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Picker("Parse Mode", selection: $parseMode) {
                Text("Auto").tag("auto")
                Text("AI Only").tag("ai")
                Text("Manual").tag("manual")
            }
            .pickerStyle(.segmented)

            Picker("AI Model", selection: $aiModelID) {
                Text("Haiku (Fast & Cheap)").tag("claude-haiku-4-5-20251001")
                Text("Sonnet (Balanced)").tag("claude-sonnet-4-6")
            }

            RVStatusBanner(
                message: "Keys are stored in the iOS Keychain or supplied by build settings. Never commit a real key to source control.",
                tone: .info
            )
        }
        .rvCard()
    }

    private var cookingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(title: "Cooking Mode", subtitle: "Defaults for the kitchen workflow.")
            Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                .tint(Color.rvAccent)
            Stepper("Default Servings: \(defaultServings)", value: $defaultServings, in: 1...20)
        }
        .rvCard()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(
                title: "Data",
                subtitle: "Back up the vault, make a cookbook, or restore from JSON."
            )

            settingsAction("Export JSON Backup", systemImage: "arrow.up.doc.fill", trailing: "\(recipes.count) recipes", disabled: recipes.isEmpty) {
                exportJSON()
            }

            settingsAction("Export PDF Cookbook", systemImage: "book.closed.fill", disabled: recipes.isEmpty) {
                exportPDFCookbook()
            }

            settingsAction("Import JSON Backup", systemImage: "arrow.down.doc.fill") {
                showImportPicker = true
            }

            settingsAction("Import JSON from Clipboard", systemImage: "doc.on.clipboard") {
                importFromClipboardJSON()
            }

            if let message = exportMessage {
                RVStatusBanner(message: message, tone: message.lowercased().contains("failed") ? .danger : .success)
            }

            if let result = importResult {
                RVStatusBanner(message: result, tone: result.lowercased().contains("failed") ? .danger : .success)
            }
        }
        .rvCard()
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(
                title: "Maintenance",
                subtitle: "Repair duplicate imports and handle destructive cleanup with a backup-first posture."
            )

            settingsAction("Resolve Duplicate Recipes", systemImage: "arrow.triangle.merge") {
                resolveConflicts()
            }

            if let syncResult {
                RVStatusBanner(message: syncResult, tone: .info)
            }

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label("Delete All Recipes", systemImage: "trash.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous))
            }
            .disabled(recipes.isEmpty)
        }
        .rvCard()
    }

    private var analyticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(title: "Reliability", subtitle: "Local diagnostics for improving app stability.")

            Toggle("Enable anonymous usage analytics", isOn: Binding(
                get: { analyticsEnabled },
                set: { newValue in
                    analyticsEnabled = newValue
                    AnalyticsService.shared.setAnalyticsEnabled(newValue)
                }
            ))
            .tint(Color.rvAccent)

            if let lastCrash = AnalyticsService.shared.lastAbnormalShutdownDate() {
                StatRow(label: "Last abnormal shutdown", value: lastCrash.formatted(date: .abbreviated, time: .shortened))
            } else {
                StatRow(label: "Last abnormal shutdown", value: "None detected")
            }
        }
        .rvCard()
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RVSectionTitle(title: "Your Library")
            StatRow(label: "Total Recipes", value: "\(recipes.count)")
            StatRow(label: "Favorites", value: "\(recipes.filter { $0.isFavorite }.count)")
            StatRow(label: "Total Times Cooked", value: "\(recipes.reduce(0) { $0 + $1.timesCooked })")

            let categories = Set(recipes.map { $0.category })
            StatRow(label: "Categories Used", value: "\(categories.count)")

            if let mostCooked = recipes.max(by: { $0.timesCooked < $1.timesCooked }), mostCooked.timesCooked > 0 {
                StatRow(label: "Most Cooked", value: "\(mostCooked.title) (\(mostCooked.timesCooked)x)")
            }
        }
        .rvCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RVSectionTitle(title: "About")
            StatRow(label: "Version", value: "1.0.0")
            StatRow(label: "Recipe Vault", value: "SwiftUI + Claude")
        }
        .rvCard()
    }

    private func settingsAction(
        _ title: String,
        systemImage: String,
        trailing: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.rvSubtleText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous))
            .foregroundStyle(Color.rvInk)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.48 : 1)
    }
    
    // MARK: - Export JSON
    
    private func exportJSON() {
        do {
            let data = try RecipeExportService.exportAsJSON(recipes: recipes)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = "RecipeVault-Backup-\(formatter.string(from: Date())).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL)
            shareURL = tempURL
            showShareSheet = true
            exportMessage = "Exported \(recipes.count) recipes"
            AnalyticsService.shared.track("backup_export_json", metadata: ["count": "\(recipes.count)"])
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
            AnalyticsService.shared.track("backup_export_json_failed")
        }
    }
    
    // MARK: - Export PDF Cookbook
    
    private func exportPDFCookbook() {
        let data = RecipeExportService.exportAsPDFCookbook(recipes: recipes)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "RecipeVault-Cookbook-\(formatter.string(from: Date())).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            shareURL = tempURL
            showShareSheet = true
            exportMessage = "Cookbook created with \(recipes.count) recipes"
            AnalyticsService.shared.track("backup_export_pdf", metadata: ["count": "\(recipes.count)"])
        } catch {
            exportMessage = "PDF export failed: \(error.localizedDescription)"
            AnalyticsService.shared.track("backup_export_pdf_failed")
        }
    }
    
    // MARK: - Import
    
    private func importFromPickedFile(url: URL) {
        do {
            let data = try loadImportData(from: url)
            try importBackupData(data)
        } catch {
            importResult = "Import failed: \(error.localizedDescription)"
            AnalyticsService.shared.track("backup_import_json_failed")
        }
    }
    
    private func importFromClipboardJSON() {
        guard let clipboardText = UIPasteboard.general.string,
              let data = clipboardText.data(using: .utf8) else {
            importResult = "Clipboard does not contain JSON text."
            return
        }
        
        do {
            try importBackupData(data)
        } catch {
            importResult = "Import failed: \(error.localizedDescription)"
            AnalyticsService.shared.track("backup_import_json_failed")
        }
    }
    
    private func loadImportData(from url: URL) throws -> Data {
        if let data = try? Data(contentsOf: url) {
            return data
        }
        
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        var coordinationError: NSError?
        var readError: Error?
        var dataFromCoordinator: Data?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                dataFromCoordinator = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }
        
        if let dataFromCoordinator {
            return dataFromCoordinator
        }
        if let readError {
            throw readError
        }
        if let coordinationError {
            throw coordinationError
        }
        throw NSError(
            domain: "RecipeVault.Import",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not access selected file."]
        )
    }
    
    private func importBackupData(_ data: Data) throws {
        guard data.count <= maxBackupImportBytes else {
            throw NSError(
                domain: "RecipeVault.Import",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Backup file is larger than 50 MB."]
            )
        }
        
        // Validate it looks like JSON before decoding into recipes.
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NSError(
                domain: "RecipeVault.Import",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Selected file is not valid JSON."]
            )
        }
        
        let imported = try RecipeExportService.importFromJSON(data: data)
        var existingFingerprints = Set(recipes.map(recipeFingerprint))
        var insertedCount = 0
        var skippedCount = 0
        
        for recipe in imported {
            let fingerprint = recipeFingerprint(recipe)
            if existingFingerprints.contains(fingerprint) {
                skippedCount += 1
                continue
            }
            modelContext.insert(recipe)
            existingFingerprints.insert(fingerprint)
            insertedCount += 1
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw NSError(
                domain: "RecipeVault.Import",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Recipes were decoded, but could not be saved: \(error.localizedDescription)"]
            )
        }
        
        if skippedCount > 0 {
            importResult = "Imported \(insertedCount) recipes (\(skippedCount) duplicates skipped)."
        } else {
            importResult = "Imported \(insertedCount) recipes successfully!"
        }
        
        AnalyticsService.shared.track("backup_import_json", metadata: [
            "inserted": "\(insertedCount)",
            "skipped": "\(skippedCount)"
        ])
    }
    
    // MARK: - API Key Storage
    
    private func loadAPIKeyIfNeeded() {
        APIKeyStore.migrateLegacyClaudeKeyIfNeeded()
        apiKey = APIKeyStore.loadClaudeKey() ?? ""
        apiKeySource = APIKeyStore.currentClaudeKeySource()
    }
    
    private func saveAPIKey(_ rawKey: String) {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        do {
            try APIKeyStore.saveClaudeKey(trimmed)
            apiKey = trimmed
            tempAPIKey = trimmed
            apiKeySource = .keychain
            exportMessage = "API key saved securely."
        } catch {
            exportMessage = "Could not save API key: \(error.localizedDescription)"
        }
    }
    
    private func removeAPIKey() {
        do {
            try APIKeyStore.deleteClaudeKey()
            apiKey = APIKeyStore.loadClaudeKey() ?? ""
            tempAPIKey = ""
            apiKeySource = APIKeyStore.currentClaudeKeySource()
            exportMessage = apiKeySource == .bundledConfig ? "Saved override removed. App is using bundled config." : "API key removed."
        } catch {
            exportMessage = "Could not remove API key: \(error.localizedDescription)"
        }
    }

    private var apiKeyStatusText: String {
        switch apiKeySource {
        case .keychain:
            return "Active from app storage"
        case .bundledConfig:
            return "Active from Xcode config"
        case .none:
            return "Not configured"
        }
    }
    
    private func recipeFingerprint(_ recipe: Recipe) -> String {
        let title = recipe.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ingredientNames = recipe.normalizedIngredients
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .sorted()
            .joined(separator: "|")
        return "\(title)::\(ingredientNames)"
    }
    
    private func deleteAllRecipes() {
        let count = recipes.count
        guard count > 0 else { return }

        // Write a safety backup first so this destructive action is recoverable
        // via "Import from JSON Backup".
        do {
            try RecipeExportService.writeAutomaticBackup(recipes: recipes)
        } catch {
            importResult = "Nothing was deleted because the safety backup could not be written."
            AnalyticsService.shared.track("recipes_delete_all_backup_failed")
            return
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
            importResult = "Nothing was deleted because meal plan cleanup could not be saved: \(error.localizedDescription)"
            AnalyticsService.shared.track("recipes_delete_all_plan_cleanup_failed")
            return
        }

        for recipe in recipes {
            modelContext.delete(recipe)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            importResult = "The recipes were not deleted because the change could not be saved: \(error.localizedDescription)"
            AnalyticsService.shared.track("recipes_delete_all_save_failed")
            return
        }

        SpotlightIndexingService.shared.removeAllRecipes()

        importResult = "Deleted \(count) recipes. A safety backup was saved on this device."
        AnalyticsService.shared.track("recipes_all_deleted", metadata: ["count": "\(count)"])
    }

    private func resolveConflicts() {
        let result = RecipeConflictResolverService.resolveRecipeConflicts(recipes: recipes, modelContext: modelContext)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            syncResult = "Duplicate cleanup could not be saved: \(error.localizedDescription)"
            AnalyticsService.shared.track("resolve_recipe_conflicts_save_failed")
            return
        }

        if result.deletedDuplicates == 0 {
            syncResult = "No duplicate recipe conflicts found."
        } else {
            syncResult = "Resolved \(result.mergedRecipes) conflict group(s), removed \(result.deletedDuplicates) duplicate recipes."
        }
        AnalyticsService.shared.track("resolve_recipe_conflicts", metadata: [
            "merged_groups": "\(result.mergedRecipes)",
            "deleted_duplicates": "\(result.deletedDuplicates)"
        ])
    }
    
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.rvInk)
            Spacer()
            Text(value)
                .foregroundStyle(Color.rvSubtleText)
                .font(.subheadline)
        }
    }
}

// MARK: - JSON Backup Picker

struct JSONBackupDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void
        
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let firstURL = urls.first else {
                onCancel()
                return
            }
            onPick(firstURL)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Recipe.self, MealPlan.self, PantryItem.self, ShoppingItem.self], inMemory: true)
}

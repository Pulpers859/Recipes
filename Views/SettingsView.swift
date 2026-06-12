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
            Form {
                // MARK: - AI Parsing
                Section {
                    HStack {
                        Image(systemName: "brain.fill")
                            .foregroundStyle(Color.rvAccent)
                        VStack(alignment: .leading) {
                            Text("Claude API Key")
                                .font(.subheadline.bold())
                            Text(apiKeyStatusText)
                                .font(.caption)
                                .foregroundStyle(apiKey.isEmpty ? Color.rvTaupe : Color.rvPrimary)
                        }
                    }
                    
                    if showAPIKey {
                        SecureField("sk-ant-...", text: $tempAPIKey)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                        
                        HStack {
                            Button("Save") {
                                saveAPIKey(tempAPIKey)
                                showAPIKey = false
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
                        
                        if apiKeySource == .keychain {
                            Button("Remove Saved API Key", role: .destructive) {
                                removeAPIKey()
                            }
                        }
                    }
                    
                    Picker("Parse Mode", selection: $parseMode) {
                        Text("Auto (AI → Manual fallback)").tag("auto")
                        Text("AI Only").tag("ai")
                        Text("Manual Only").tag("manual")
                    }

                    Picker("AI Model", selection: $aiModelID) {
                        Text("Haiku (Fast & Cheap)").tag("claude-haiku-4-5-20251001")
                        Text("Sonnet (Balanced)").tag("claude-sonnet-4-6")
                    }
                } header: {
                    Text("AI Recipe Parsing")
                } footer: {
                    Text("You can save a key in-app, provide `ANTHROPIC_API_KEY` in Info.plist/build settings, or set it directly in `AppConfig.swift`. AI parsing sends recipe text to Claude for structured extraction. Manual mode uses local OCR only.")
                }
                
                // MARK: - Cooking
                Section("Cooking Mode") {
                    Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                    Stepper("Default Servings: \(defaultServings)", value: $defaultServings, in: 1...20)
                }
                
                // MARK: - Data Management
                Section {
                    Button {
                        exportJSON()
                    } label: {
                        HStack {
                            Label("Export as JSON Backup", systemImage: "arrow.up.doc.fill")
                            Spacer()
                            Text("\(recipes.count) recipes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(recipes.isEmpty)
                    
                    Button {
                        exportPDFCookbook()
                    } label: {
                        Label("Export as PDF Cookbook", systemImage: "book.closed.fill")
                    }
                    .disabled(recipes.isEmpty)
                    
                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import from JSON Backup", systemImage: "arrow.down.doc.fill")
                    }

                    Button {
                        importFromClipboardJSON()
                    } label: {
                        Label("Import JSON from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    
                    if let message = exportMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.rvPrimary)
                    }
                    
                    if let result = importResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(Color.rvPrimary)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("JSON backups include all recipe data and can be restored later. PDF export creates a printable cookbook with table of contents.")
                }
                
                // MARK: - Maintenance
                Section {
                    Button {
                        resolveConflicts()
                    } label: {
                        Label("Resolve Duplicate Recipes", systemImage: "arrow.triangle.merge")
                    }

                    if let syncResult {
                        Text(syncResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("Delete All Recipes", systemImage: "trash.fill")
                    }
                    .disabled(recipes.isEmpty)
                } header: {
                    Text("Maintenance")
                }
                
                // MARK: - Analytics
                Section {
                    Toggle("Enable anonymous usage analytics", isOn: Binding(
                        get: { analyticsEnabled },
                        set: { newValue in
                            analyticsEnabled = newValue
                            AnalyticsService.shared.setAnalyticsEnabled(newValue)
                        }
                    ))
                    
                    if let lastCrash = AnalyticsService.shared.lastAbnormalShutdownDate() {
                        HStack {
                            Text("Last abnormal shutdown")
                            Spacer()
                            Text(lastCrash.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Last abnormal shutdown")
                            Spacer()
                            Text("None detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Analytics")
                } footer: {
                    Text("Analytics are stored locally and used to improve reliability in future updates.")
                }
                
                // MARK: - Stats
                Section("Your Library") {
                    StatRow(label: "Total Recipes", value: "\(recipes.count)")
                    StatRow(label: "Favorites", value: "\(recipes.filter { $0.isFavorite }.count)")
                    StatRow(label: "Total Times Cooked", value: "\(recipes.reduce(0) { $0 + $1.timesCooked })")
                    
                    let categories = Set(recipes.map { $0.category })
                    StatRow(label: "Categories Used", value: "\(categories.count)")
                    
                    if let mostCooked = recipes.max(by: { $0.timesCooked < $1.timesCooked }), mostCooked.timesCooked > 0 {
                        StatRow(label: "Most Cooked", value: "\(mostCooked.title) (\(mostCooked.timesCooked)x)")
                    }
                }
                
                // MARK: - About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Recipe Vault")
                        Spacer()
                        Text("Built with SwiftUI + Claude")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("Settings")
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
                Text("This will permanently delete all \(recipes.count) recipe(s). This cannot be undone.")
            }
        }
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
        for recipe in recipes {
            modelContext.delete(recipe)
        }
        SpotlightIndexingService.shared.removeAllRecipes()
        AnalyticsService.shared.track("recipes_all_deleted", metadata: ["count": "\(count)"])
    }

    private func resolveConflicts() {
        let result = RecipeConflictResolverService.resolveRecipeConflicts(recipes: recipes, modelContext: modelContext)
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

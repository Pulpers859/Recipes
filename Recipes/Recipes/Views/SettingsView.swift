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
    @State private var isWritingBackup = false
    @State private var exportMessage: (text: String, isError: Bool)?
    @State private var importResult: (text: String, isError: Bool)?
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showDeleteAllConfirm = false
    @State private var showResolveConfirm = false
    @State private var apiKeySource: APIKeyStore.KeySource?
    @State private var apiKeyMessage: (text: String, isError: Bool)?
    /// Maintenance-card banner with an explicit error flag — tone must never
    /// be guessed by string-sniffing (a failed delete once rendered green).
    @State private var maintenanceMessage: (text: String, isError: Bool)?
    @State private var archivedStores: [ArchivedStore] = []
    @State private var backupSnapshots: [RecipeExportService.BackupSnapshot] = []
    @State private var snapshotPendingRestore: RecipeExportService.BackupSnapshot?
    @State private var snapshotMessage: (text: String, isError: Bool)?

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
                    snapshotsCard
                    analyticsCard
                    recoveryCard
                    libraryCard
                    aboutCard
                }
                .padding(RVDesign.screenPadding)
                .padding(.bottom, 28)
            }
            .background(Color.rvBackground.ignoresSafeArea())
            .overlay {
                if isWritingBackup {
                    RVBlockingProgressOverlay(message: "Saving safety backup…")
                }
            }
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
                // Directory listing + file attribute reads don't belong in
                // body; load once and refresh when an export changes things.
                archivedStores = Self.listArchivedStores()
                backupSnapshots = RecipeExportService.listBackupSnapshots()
            }
            // Status banners fade after a bit instead of sticking around
            // forever ("Exported 42 recipes" three days later reads as stale
            // state). Errors stay longer so they can be read and acted on.
            .onChange(of: exportMessage?.text) { _, newValue in
                scheduleBannerClear(newValue, isError: exportMessage?.isError ?? false) { if exportMessage?.text == newValue { withAnimation { exportMessage = nil } } }
            }
            .onChange(of: importResult?.text) { _, newValue in
                scheduleBannerClear(newValue, isError: importResult?.isError ?? false) { if importResult?.text == newValue { withAnimation { importResult = nil } } }
            }
            .onChange(of: apiKeyMessage?.text) { _, newValue in
                scheduleBannerClear(newValue, isError: apiKeyMessage?.isError ?? false) { if apiKeyMessage?.text == newValue { withAnimation { apiKeyMessage = nil } } }
            }
            .onChange(of: maintenanceMessage?.text) { _, newValue in
                scheduleBannerClear(newValue, isError: maintenanceMessage?.isError ?? false) { if maintenanceMessage?.text == newValue { withAnimation { maintenanceMessage = nil } } }
            }
            .onChange(of: snapshotMessage?.text) { _, newValue in
                scheduleBannerClear(newValue, isError: snapshotMessage?.isError ?? false) { if snapshotMessage?.text == newValue { withAnimation { snapshotMessage = nil } } }
            }
            .alert("Delete All Recipes?", isPresented: $showDeleteAllConfirm) {
                Button("Delete All", role: .destructive) { Task { await deleteAllRecipes() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes all \(recipes.count) \(recipes.count == 1 ? "recipe" : "recipes") and clears their meal plan entries. A safety backup of your library — including pantry, shopping list, and meal plans — is saved on this device first.")
            }
            .alert("Resolve Duplicate Recipes?", isPresented: $showResolveConfirm) {
                Button("Resolve Duplicates", role: .destructive) { Task { await resolveConflicts() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Recipes with the same title and ingredients are merged, and the duplicates are permanently deleted. A safety backup is saved on this device first.")
            }
            .alert(
                "Restore Snapshot?",
                isPresented: Binding(
                    get: { snapshotPendingRestore != nil },
                    set: { if !$0 { snapshotPendingRestore = nil } }
                ),
                presenting: snapshotPendingRestore
            ) { snapshot in
                Button("Restore") { restoreSnapshot(snapshot) }
                Button("Cancel", role: .cancel) { }
            } message: { snapshot in
                Text("Recipes, pantry, shopping list, and meal plans from \(snapshot.date.formatted(date: .abbreviated, time: .shortened)) will be merged into your library. Existing records are kept; duplicates are skipped.")
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

            if let message = apiKeyMessage {
                RVStatusBanner(message: message.text, tone: message.isError ? .danger : .success)
            }

            RVStatusBanner(
                message: "Keys are stored in the iOS Keychain (or a development environment variable). Never commit a real key to source control.",
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
                RVStatusBanner(message: message.text, tone: message.isError ? .danger : .success)
            }

            if let result = importResult {
                RVStatusBanner(message: result.text, tone: result.isError ? .danger : .success)
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

            settingsAction("Resolve Duplicate Recipes", systemImage: "arrow.triangle.merge", disabled: recipes.isEmpty) {
                showResolveConfirm = true
            }

            if let maintenanceMessage {
                RVStatusBanner(message: maintenanceMessage.text, tone: maintenanceMessage.isError ? .danger : .success)
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

    private var snapshotsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(
                title: "Safety Snapshots",
                subtitle: "Recovery points saved on this device before destructive actions and when you leave the app after changes."
            )

            if backupSnapshots.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.rvTaupe)
                    Text("No snapshots yet. One is saved before every delete or duplicate cleanup, and when you close the app after making changes.")
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                }
            } else {
                ForEach(backupSnapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.rvInk)
                            Text("\(snapshot.kind.displayLabel) · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.sizeBytes), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(Color.rvSubtleText)
                        }
                        Spacer()
                        Button("Restore") {
                            snapshotPendingRestore = snapshot
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.rvAccent)
                        .controlSize(.small)
                    }
                }

                RVStatusBanner(
                    message: "Restoring merges a snapshot into your current library. Nothing is deleted or overwritten — records you already have are skipped.",
                    tone: .info
                )
            }

            if let message = snapshotMessage {
                RVStatusBanner(message: message.text, tone: message.isError ? .danger : .success)
            }
        }
        .rvCard()
    }

    private func restoreSnapshot(_ snapshot: RecipeExportService.BackupSnapshot) {
        let outcome = RecipeLibraryMaintenance.restoreSnapshot(
            at: snapshot.url,
            existingRecipes: recipes,
            modelContext: modelContext
        )
        snapshotMessage = (outcome.message, outcome.isError)
        backupSnapshots = RecipeExportService.listBackupSnapshots()
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

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RVSectionTitle(
                title: "Data Recovery",
                subtitle: "If the app had to reset your library, archived copies of the old data may be available here."
            )

            let archives = archivedStores
            if archives.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.rvPrimary)
                    Text("No recovery archives found — your library has not been reset.")
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                }
            } else {
                RVStatusBanner(
                    message: "\(archives.count) archived database\(archives.count == 1 ? "" : "s") found from previous resets. These contain your old recipes and can be exported as a backup file for re-import.",
                    tone: .info
                )

                ForEach(archives, id: \.timestamp) { archive in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Archive from \(archive.displayDate)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.rvInk)
                            Text(archive.sizeText)
                                .font(.caption)
                                .foregroundStyle(Color.rvSubtleText)
                        }
                        Spacer()
                        Button("Export") {
                            exportArchivedStore(archive)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.rvAccent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .rvCard()
    }

    private struct ArchivedStore {
        let timestamp: Int
        let path: URL
        let sizeText: String
        var displayDate: String {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        init(timestamp: Int, path: URL) {
            self.timestamp = timestamp
            self.path = path
            let size = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? 0
            if size > 1_000_000 {
                sizeText = String(format: "%.1f MB", Double(size) / 1_000_000)
            } else {
                sizeText = "\(size / 1_000) KB"
            }
        }
    }

    private static func listArchivedStores() -> [ArchivedStore] {
        let fm = FileManager.default
        guard let supportDir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return [] }

        let contents = (try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
        let storeRegex = try? NSRegularExpression(pattern: #"RecipeVault-corrupt-(\d+)\.store$"#)

        return contents.compactMap { url in
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            guard let match = storeRegex?.firstMatch(in: name, range: range),
                  let tsRange = Range(match.range(at: 1), in: name),
                  let ts = Int(name[tsRange]) else { return nil }
            return ArchivedStore(timestamp: ts, path: url)
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    private func exportArchivedStore(_ archive: ArchivedStore) {
        do {
            let schema = Schema([Recipe.self, MealPlan.self, ShoppingItem.self, PantryItem.self])
            // Read-only: opening the archive read-write can mutate it (WAL
            // sidecars), and this archive may be the only copy of lost data.
            let config = ModelConfiguration(
                "RecoveryRead",
                schema: schema,
                url: archive.path,
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []

            if recipes.isEmpty {
                exportMessage = ("The archived database could not be read or contains no recipes.", true)
                return
            }

            let jsonData = try RecipeExportService.exportAsJSON(recipes: recipes)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("RecipeVault-Recovery-\(archive.timestamp).json")
            try jsonData.write(to: tempURL)
            shareURL = tempURL
            showShareSheet = true
            exportMessage = ("Exported \(recipes.count) recipes from the archive. Re-import this file to restore them.", false)
        } catch {
            exportMessage = ("Could not read archived database: \(error.localizedDescription)", true)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RVSectionTitle(title: "About")
            StatRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            StatRow(label: "Made for", value: "Your kitchen")
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
            // Full-app backup: pantry, shopping list, and meal plans ride
            // along as optional v4 sections.
            let data = try RecipeExportService.exportAsJSON(
                recipes: recipes,
                pantryItems: (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? [],
                shoppingItems: (try? modelContext.fetch(FetchDescriptor<ShoppingItem>())) ?? [],
                mealPlans: (try? modelContext.fetch(FetchDescriptor<MealPlan>())) ?? []
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = "RecipeVault-Backup-\(formatter.string(from: Date())).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL)
            shareURL = tempURL
            showShareSheet = true
            let sizeMB = Double(data.count) / (1024 * 1024)
            let sizeNote = sizeMB > 25 ? " (\(String(format: "%.0f", sizeMB)) MB — photos are embedded inline)" : ""
            exportMessage = ("Exported \(recipes.count) recipes with pantry, shopping list, and meal plans\(sizeNote)", false)
            AnalyticsService.shared.track("backup_export_json", metadata: ["count": "\(recipes.count)", "size_mb": "\(String(format: "%.1f", sizeMB))"])
        } catch {
            exportMessage = ("Export failed: \(error.localizedDescription)", true)
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
            exportMessage = ("Cookbook created with \(recipes.count) recipes", false)
            AnalyticsService.shared.track("backup_export_pdf", metadata: ["count": "\(recipes.count)"])
        } catch {
            exportMessage = ("PDF export failed: \(error.localizedDescription)", true)
            AnalyticsService.shared.track("backup_export_pdf_failed")
        }
    }
    
    // MARK: - Import
    
    private func importFromPickedFile(url: URL) {
        do {
            let data = try loadImportData(from: url)
            let outcome = try RecipeLibraryMaintenance.importBackup(
                data: data,
                existingRecipes: recipes,
                modelContext: modelContext
            )
            importResult = (outcome.message, outcome.isError)
        } catch {
            importResult = ("Import failed: \(error.localizedDescription)", true)
            AnalyticsService.shared.track("backup_import_json_failed")
        }
    }

    private func importFromClipboardJSON() {
        guard let clipboardText = UIPasteboard.general.string,
              let data = clipboardText.data(using: .utf8) else {
            importResult = ("Clipboard does not contain JSON text.", true)
            return
        }

        do {
            let outcome = try RecipeLibraryMaintenance.importBackup(
                data: data,
                existingRecipes: recipes,
                modelContext: modelContext
            )
            importResult = (outcome.message, outcome.isError)
        } catch {
            importResult = ("Import failed: \(error.localizedDescription)", true)
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
            apiKeyMessage = ("API key saved securely.", false)
        } catch {
            apiKeyMessage = ("Could not save API key: \(error.localizedDescription)", true)
        }
    }
    
    private func removeAPIKey() {
        do {
            try APIKeyStore.deleteClaudeKey()
            apiKey = APIKeyStore.loadClaudeKey() ?? ""
            tempAPIKey = ""
            apiKeySource = APIKeyStore.currentClaudeKeySource()
            apiKeyMessage = (apiKeySource == .bundledConfig ? "Saved override removed. App is using bundled config." : "API key removed.", false)
        } catch {
            apiKeyMessage = ("Could not remove API key: \(error.localizedDescription)", true)
        }
    }

    private var apiKeyStatusText: String {
        switch apiKeySource {
        case .keychain:
            return "Active from app storage"
        case .bundledConfig:
            return "Active from development environment"
        case .none:
            return "Not configured"
        }
    }

    /// Clears a status banner after a delay: 12 s for errors (they need to be
    /// read), 6 s for confirmations. Tone comes from the banner's explicit
    /// error flag — never from sniffing the message text.
    private func scheduleBannerClear(_ newValue: String?, isError: Bool, clear: @escaping () -> Void) {
        guard newValue != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(isError ? 12 : 6))
            withAnimation { clear() }
        }
    }
    
    private func deleteAllRecipes() async {
        guard !isWritingBackup else { return }
        isWritingBackup = true
        defer { isWritingBackup = false }
        if let outcome = await RecipeLibraryMaintenance.deleteAllRecipes(recipes, modelContext: modelContext) {
            maintenanceMessage = (outcome.message, outcome.isError)
        }
        backupSnapshots = RecipeExportService.listBackupSnapshots()
    }

    private func resolveConflicts() async {
        guard !isWritingBackup else { return }
        isWritingBackup = true
        defer { isWritingBackup = false }
        let outcome = await RecipeLibraryMaintenance.resolveConflicts(recipes, modelContext: modelContext)
        maintenanceMessage = (outcome.message, outcome.isError)
        backupSnapshots = RecipeExportService.listBackupSnapshots()
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

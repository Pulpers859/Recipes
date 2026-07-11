import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var parser: RecipeParserService
    
    @State private var selectedTab: ImportTab = .pdf
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var importedRecipe: Recipe?
    @State private var showFilePicker = false
    @State private var urlText = ""
    @StateObject private var scraper = URLRecipeScraperService()
    @State private var showImportSummary = false
    @State private var importedCount = 0
    @State private var pendingBatchRecipes: [Recipe] = []
    @State private var showBatchReview = false
    /// The in-flight parse. Held so Cancel/dismiss can abort it — an orphaned
    /// task used to finish minutes later and silently insert an unreviewed
    /// recipe into the library with no review sheet.
    @State private var activeImportTask: Task<Void, Never>?
    @AppStorage("parse_mode") private var parseModeSetting = "auto"
    
    private let maxPDFImportBytes = 25 * 1024 * 1024
    private let maxPhotoImportBytes = 15 * 1024 * 1024
    
    enum ImportTab: String, CaseIterable {
        case pdf = "PDF"
        case photo = "Photo"
        case url = "URL"
        
        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            case .photo: return "camera.fill"
            case .url: return "link"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RVDesign.sectionSpacing) {
                    RVHeroBanner(
                        title: "Import Recipe",
                        subtitle: "Bring in a PDF, photo, or recipe link, then review the result before it joins your vault.",
                        systemImage: "square.and.arrow.down.fill",
                        metrics: [
                            ("Mode", parseModeLabel),
                            ("AI", parser.hasAPIKey ? "Ready" : "Off")
                        ]
                    )

                    importMethodPicker

                    selectedImportPanel

                    if parser.isProcessing {
                        processingCard
                    }

                    if let error = parser.lastError {
                        RVStatusBanner(message: error, tone: .danger)
                    }

                    parsingStatusCard
                }
                .padding(RVDesign.screenPadding)
                .padding(.bottom, 28)
            }
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rvBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        activeImportTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // The parser/scraper are long-lived objects; don't greet a new
                // import session with the previous session's failure banner.
                parser.lastError = nil
                scraper.lastError = nil
                scraper.lastWarning = nil
            }
            .onDisappear {
                activeImportTask?.cancel()
            }
            .sheet(isPresented: $showFilePicker) {
                PDFImportDocumentPicker { pickedURL in
                    showFilePicker = false
                    handlePickedPDF(url: pickedURL)
                } onCancel: {
                    showFilePicker = false
                }
            }
            .sheet(item: $importedRecipe) { recipe in
                NavigationStack {
                    RecipeEditorView(recipe: recipe, isNewImport: true)
                }
            }
            .sheet(isPresented: $showBatchReview) {
                BatchImportReviewView(
                    recipes: $pendingBatchRecipes,
                    parserWarning: parser.lastError
                ) { accepted in
                    // The source PDF rides on the first parsed recipe. If the
                    // user excluded that one, move the PDF onto an accepted
                    // recipe so the only copy of the source document survives.
                    if let firstAccepted = accepted.first,
                       !accepted.contains(where: { $0.originalPDFData != nil }),
                       let orphanedPDF = pendingBatchRecipes.first(where: { $0.originalPDFData != nil })?.originalPDFData {
                        firstAccepted.originalPDFData = orphanedPDF
                    }
                    for recipe in accepted {
                        modelContext.insert(recipe)
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        // Undo the inserts — otherwise they linger unsaved in
                        // the autosaving context and can be committed later by
                        // an unrelated save despite the error we just showed.
                        // Delete the specific inserts rather than rollback():
                        // the review sheet stays open for a retry, and Save
                        // must be able to re-insert these same instances.
                        for recipe in accepted {
                            modelContext.delete(recipe)
                        }
                        return "Could not save the recipes: \(error.localizedDescription)"
                    }
                    importedCount = accepted.count
                    showImportSummary = true
                    return nil
                }
                // A stray swipe must not discard a whole parsed cookbook.
                .interactiveDismissDisabled()
            }
            .alert("Import Complete", isPresented: $showImportSummary) {
                Button("OK") { dismiss() }
            } message: {
                Text("Imported \(importedCount) recipe\(importedCount == 1 ? "" : "s"). Open each one in the Recipes tab to verify the content.")
            }
        }
    }

    private var importMethodPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            RVSectionTitle(
                title: "Choose Source",
                subtitle: "Use the cleanest source available. Structured web recipes are fastest; photos and PDFs need careful review."
            )

            Picker("Import Method", selection: $selectedTab) {
                ForEach(ImportTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .rvCard()
    }

    @ViewBuilder
    private var selectedImportPanel: some View {
        switch selectedTab {
        case .pdf:
            pdfImportView
        case .photo:
            photoImportView
        case .url:
            urlImportView
        }
    }

    private var processingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(Color.rvAccent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Working on it")
                    .font(.headline)
                    .foregroundStyle(Color.rvInk)
                Text(parser.parseProgress)
                    .font(.caption)
                    .foregroundStyle(Color.rvSubtleText)
            }
        }
        .rvCard()
    }

    private var parsingStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: parser.hasAPIKey ? "brain.fill" : "brain")
                    .foregroundStyle(parser.hasAPIKey ? Color.rvPrimary : Color.rvMuted)
                Text(parser.hasAPIKey ? "AI parsing enabled" : "AI parsing unavailable")
                    .font(.headline)
                    .foregroundStyle(Color.rvInk)
            }

            if parser.hasAPIKey {
                Text("Recipe Vault can use Claude to extract structured ingredients, steps, timing, and sections. You still get the final review.")
                    .font(.caption)
                    .foregroundStyle(Color.rvSubtleText)
            } else {
                RVStatusBanner(
                    message: "Without an API key, imports use a basic local parser. Ingredient amounts and steps usually need cleanup afterward.",
                    tone: .warning
                )
            }
        }
        .rvCard()
    }

    /// Any parse in flight, from any tab.
    private var isImporting: Bool {
        parser.isProcessing || scraper.isLoading
    }

    private var parseModeLabel: String {
        switch parseModeSetting {
        case "ai": return "AI"
        case "manual": return "Manual"
        default: return "Auto"
        }
    }
    
    // MARK: - PDF Import
    
    private var pdfImportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            RVSectionTitle(
                title: "PDF Cookbook",
                subtitle: "Best for saved recipes and cookbook pages. Multi-recipe PDFs are split automatically, then flagged for review."
            )

            Button {
                showFilePicker = true
            } label: {
                importDropZone(
                    icon: "doc.badge.arrow.up.fill",
                    title: "Select PDF",
                    subtitle: "Up to 25 MB"
                )
            }
            .buttonStyle(.plain)
            // Starting a second parse while one runs races the shared
            // parser state and can orphan the first recipe unreviewed.
            .disabled(isImporting)
            .opacity(isImporting ? 0.5 : 1)
        }
        .rvCard()
    }
    
    // MARK: - Photo Import
    
    private var photoImportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            RVSectionTitle(
                title: "Photo or Screenshot",
                subtitle: "Great for recipe cards and saved screenshots. Keep the photo sharp, well lit, and uncropped."
            )

            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                importDropZone(
                    icon: "camera.fill",
                    title: "Select Photo",
                    subtitle: "Recipe card, screenshot, or cookbook page"
                )
            }
            .disabled(isImporting)
            .opacity(isImporting ? 0.5 : 1)
            .onChange(of: selectedPhotoItem) { _, newItem in
                handlePhotoSelection(newItem)
            }
        }
        .rvCard()
    }
    
    // MARK: - URL Import
    
    private var urlImportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            RVSectionTitle(
                title: "Recipe Link",
                subtitle: "Paste a recipe page. Sites with structured recipe data import fastest and most accurately."
            )

            HStack(spacing: 12) {
                TextField("https://example.com/recipe", text: $urlText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .rvInsetField()

                Button {
                    importURL()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(LinearGradient.rvAccentGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                .accessibilityLabel("Import recipe from link")
            }

            if scraper.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(scraper.statusMessage)
                        .font(.caption)
                        .foregroundStyle(Color.rvSubtleText)
                }
            }

            if let error = scraper.lastError {
                RVStatusBanner(message: error, tone: .danger)
            }

            if let warning = scraper.lastWarning {
                RVStatusBanner(message: warning, tone: .warning)
            }

            RVStatusBanner(
                message: "Local and private-network URLs are blocked for safety. You will review the recipe before keeping it.",
                tone: .info
            )
        }
        .rvCard()
    }

    private func importDropZone(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(LinearGradient.rvAccentGradient)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.rvInk)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.rvSubtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 186)
        .background(Color.rvSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.rvAccent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
        }
    }

    private func importURL() {
        activeImportTask = Task {
            scraper.lastError = nil
            scraper.lastWarning = nil
            do {
                let recipe = try await scraper.scrapeRecipe(
                    from: urlText,
                    allowAI: parseModeSetting != "manual"
                )
                // The user cancelled or left while we were fetching — don't
                // insert an unreviewed recipe into the library.
                guard !Task.isCancelled else { return }
                modelContext.insert(recipe)
                AnalyticsService.shared.track("import_url_success", metadata: [
                    "mode": parseModeSetting
                ])
                importedRecipe = recipe
                urlText = ""
            } catch is CancellationError {
                // Cancelled by the user; nothing to report.
            } catch {
                guard !Task.isCancelled else { return }
                scraper.lastError = error.localizedDescription
                AnalyticsService.shared.track("import_url_failed")
            }
        }
    }
    
    // MARK: - Handlers
    
    private func handlePickedPDF(url: URL) {
        // The picker uses asCopy: true, so the URL may be a sandbox-local copy
        // that carries no security scope — startAccessing returning false is
        // then expected, not an error. Try the read either way and only pair
        // a stopAccessing with a successful start.
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            parser.lastError = "Could not read file: \(error.localizedDescription)"
            return
        }

        guard data.count <= maxPDFImportBytes else {
            parser.lastError = "PDF is too large. Please choose a file under 25 MB."
            return
        }

        // Parse — may return 1 or many recipes
        activeImportTask = Task {
            do {
                let mode = parseMode()
                let recipes = try await parser.parseRecipes(from: data, mode: mode)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    AnalyticsService.shared.track("import_pdf_success", metadata: [
                        "count": "\(recipes.count)",
                        "mode": parseModeSetting
                    ])

                    if recipes.count == 1 {
                        modelContext.insert(recipes[0])
                        importedRecipe = recipes.first
                    } else {
                        pendingBatchRecipes = recipes
                        showBatchReview = true
                    }
                }
            } catch is CancellationError {
                // Cancelled by the user; nothing to report.
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    parser.lastError = error.localizedDescription
                    AnalyticsService.shared.track("import_pdf_failed")
                }
            }
        }
    }
    
    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }

        activeImportTask = Task {
            await importPhoto(item)
            // Reset so picking the same photo again still triggers an import.
            await MainActor.run { selectedPhotoItem = nil }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    parser.lastError = "That photo couldn't be loaded. Try a different photo, or a screenshot of it."
                }
                return
            }
            guard data.count <= maxPhotoImportBytes else {
                await MainActor.run {
                    parser.lastError = "Image is too large. Please choose a file under 15 MB."
                }
                return
            }
            let recipe = try await parser.parseRecipeFromImage(data, mode: parseMode())
            guard !Task.isCancelled else { return }
            await MainActor.run {
                modelContext.insert(recipe)
                AnalyticsService.shared.track("import_photo_success", metadata: [
                    "mode": parseModeSetting
                ])
                importedRecipe = recipe
            }
        } catch is CancellationError {
            // Cancelled by the user; nothing to report.
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                parser.lastError = error.localizedDescription
                AnalyticsService.shared.track("import_photo_failed")
            }
        }
    }
    
    private func parseMode() -> RecipeParserService.ParseMode {
        switch parseModeSetting {
        case "ai":
            return .ai
        case "manual":
            return .manual
        default:
            return .auto
        }
    }
}

struct PDFImportDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
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

// MARK: - Batch Import Review

struct BatchImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var recipes: [Recipe]
    let parserWarning: String?
    /// Returns nil on success, or an error message to show — the sheet stays
    /// open on failure so "Save" failing never looks like it succeeded.
    let onAccept: ([Recipe]) -> String?

    @State private var selectedRecipe: Recipe?
    @State private var excluded: Set<UUID> = []
    @State private var saveError: String?
    @State private var showCancelConfirm = false

    private var accepted: [Recipe] {
        recipes.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RVDesign.sectionSpacing) {
                    RVHeroBanner(
                        title: "Review Import",
                        subtitle: "Multi-recipe splitting is approximate. Check each recipe and remove any that look wrong before saving.",
                        systemImage: "checklist",
                        metrics: [
                            ("Found", "\(recipes.count)"),
                            ("Keeping", "\(accepted.count)")
                        ]
                    )

                    if let warning = parserWarning {
                        RVStatusBanner(message: warning, tone: .warning)
                    }

                    if let saveError {
                        RVStatusBanner(message: saveError, tone: .danger)
                    }

                    ForEach(recipes) { recipe in
                        batchRecipeRow(recipe)
                    }
                }
                .padding(RVDesign.screenPadding)
                .padding(.bottom, 28)
            }
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recipes.isEmpty {
                            dismiss()
                        } else {
                            showCancelConfirm = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save \(accepted.count) Recipe\(accepted.count == 1 ? "" : "s")") {
                        if let error = onAccept(accepted) {
                            saveError = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(accepted.isEmpty)
                }
            }
            .alert("Discard \(recipes.count) Parsed Recipe\(recipes.count == 1 ? "" : "s")?", isPresented: $showCancelConfirm) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Reviewing", role: .cancel) {}
            } message: {
                Text("Nothing has been saved yet. Cancelling throws away this parse — you would need to import the document again.")
            }
            .sheet(item: $selectedRecipe) { recipe in
                NavigationStack {
                    // Preview-only: edits write back to the pending recipe in
                    // memory. Insertion happens only via "Save N Recipes",
                    // so previewing then excluding can't leak into the library.
                    RecipeEditorView(recipe: recipe, isNewImport: true, isPreviewOnly: true)
                }
            }
        }
    }

    private func batchRecipeRow(_ recipe: Recipe) -> some View {
        let isExcluded = excluded.contains(recipe.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(isExcluded ? Color.rvMuted : Color.rvInk)
                        .strikethrough(isExcluded)

                    Text("\(recipe.ingredients.count) ingredients · \(recipe.steps.count) steps")
                        .font(.caption)
                        .foregroundStyle(Color.rvSubtleText)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        selectedRecipe = recipe
                    } label: {
                        Image(systemName: "eye")
                            .foregroundStyle(Color.rvAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview \(recipe.title)")

                    Button {
                        if isExcluded {
                            excluded.remove(recipe.id)
                        } else {
                            excluded.insert(recipe.id)
                        }
                    } label: {
                        Image(systemName: isExcluded ? "arrow.uturn.backward.circle" : "xmark.circle.fill")
                            .foregroundStyle(isExcluded ? Color.rvAccent : Color.rvMuted)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExcluded ? "Include \(recipe.title)" : "Exclude \(recipe.title)")
                }
            }

            if recipe.ingredients.isEmpty && recipe.steps.isEmpty {
                RVStatusBanner(message: "This recipe has no ingredients or steps — it may not have parsed correctly.", tone: .warning)
            }
        }
        .rvCard()
        .opacity(isExcluded ? 0.5 : 1)
    }
}

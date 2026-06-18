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
                    Button("Cancel") { dismiss() }
                }
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
            .alert("Import Complete", isPresented: $showImportSummary) {
                Button("OK") { dismiss() }
            } message: {
                // Multi-recipe splitting is heuristic; say so instead of
                // implying every recipe came through cleanly.
                Text("Imported \(importedCount) recipes from this PDF. Splitting a multi-recipe PDF is approximate — open each recipe in the Recipes tab and check that nothing was merged or cut off.")
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
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scraper.isLoading)
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
        Task {
            scraper.lastError = nil
            do {
                let recipe = try await scraper.scrapeRecipe(
                    from: urlText,
                    allowAI: parseModeSetting != "manual"
                )
                modelContext.insert(recipe)
                AnalyticsService.shared.track("import_url_success", metadata: [
                    "mode": parseModeSetting
                ])
                importedRecipe = recipe
                urlText = ""
            } catch {
                scraper.lastError = error.localizedDescription
                AnalyticsService.shared.track("import_url_failed")
            }
        }
    }
    
    // MARK: - Handlers
    
    private func handlePickedPDF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            parser.lastError = "Permission denied: unable to access the selected file."
            return
        }

        // Read data synchronously while we still have security scope access
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            url.stopAccessingSecurityScopedResource()
            parser.lastError = "Could not read file: \(error.localizedDescription)"
            return
        }
        url.stopAccessingSecurityScopedResource()

        guard data.count <= maxPDFImportBytes else {
            parser.lastError = "PDF is too large. Please choose a file under 25 MB."
            return
        }

        // Parse — may return 1 or many recipes
        Task {
            do {
                let mode = parseMode()
                let recipes = try await parser.parseRecipes(from: data, mode: mode)
                await MainActor.run {
                    for recipe in recipes {
                        modelContext.insert(recipe)
                    }
                    AnalyticsService.shared.track("import_pdf_success", metadata: [
                        "count": "\(recipes.count)",
                        "mode": parseModeSetting
                    ])

                    if recipes.count == 1 {
                        // Single recipe — open editor for review
                        importedRecipe = recipes.first
                    } else {
                        // Multiple recipes — show summary
                        importedCount = recipes.count
                        showImportSummary = true
                    }
                }
            } catch {
                await MainActor.run {
                    parser.lastError = error.localizedDescription
                    AnalyticsService.shared.track("import_pdf_failed")
                }
            }
        }
    }
    
    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            await importPhoto(item)
            // Reset so picking the same photo again still triggers an import.
            await MainActor.run { selectedPhotoItem = nil }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard data.count <= maxPhotoImportBytes else {
                await MainActor.run {
                    parser.lastError = "Image is too large. Please choose a file under 15 MB."
                }
                return
            }
            let recipe = try await parser.parseRecipeFromImage(data, mode: parseMode())
            await MainActor.run {
                modelContext.insert(recipe)
                AnalyticsService.shared.track("import_photo_success", metadata: [
                    "mode": parseModeSetting
                ])
                importedRecipe = recipe
            }
        } catch {
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

import SwiftUI
import SwiftData
import UIKit

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]

    @State private var searchText = ""
    /// Search filtering runs against this, updated ~250ms after typing stops,
    /// so the whole library isn't re-filtered on every keystroke.
    @State private var debouncedSearchText = ""
    @State private var selectedCategory: RecipeCategory?
    @State private var showingImportSheet = false
    @State private var showingAddRecipe = false
    @State private var showFavoritesOnly = false
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var isSelectionMode = false
    @State private var selectedRecipeIDs: Set<UUID> = []
    @State private var showDeleteSelectedConfirm = false
    @State private var actionErrorMessage: String?
    @State private var isWritingBackup = false
    @State private var navigationPath: [RecipeRoute] = []
    @State private var pendingSpotlightRecipeID: UUID?
    @State private var spotlightRouteAttempts = 0

    @StateObject private var parser = RecipeParserService()

    enum SortOrder: String, CaseIterable {
        case dateAdded = "Date Added"
        case title = "Title"
        case rating = "Rating"
        case lastCooked = "Last Cooked"
    }

    private var filteredRecipes: [Recipe] {
        var result = recipes

        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText.lowercased()
            // Search raw ingredient names: normalizedIngredients rebuilds and
            // re-trims the whole list per recipe, which is wasted work here.
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.cuisine.lowercased().contains(query) ||
                $0.tags.contains(where: { $0.lowercased().contains(query) }) ||
                $0.ingredients.contains(where: { $0.name.lowercased().contains(query) })
            }
        }

        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        switch sortOrder {
        case .dateAdded:
            break
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .rating:
            result.sort { $0.rating > $1.rating }
        case .lastCooked:
            result.sort { ($0.dateLastCooked ?? .distantPast) > ($1.dateLastCooked ?? .distantPast) }
        }

        return result
    }

    /// Cached in state and refreshed via `.task(id:)` — computing this in
    /// body re-normalized every ingredient of every recipe on every render.
    @State private var pantrySuggestions: [PantrySuggestion] = []

    /// Cheap change-key for the suggestions: pantry composition + library
    /// size. (An ingredient edit alone refreshes on next tab appearance.)
    private var pantrySuggestionKey: Int {
        var hasher = Hasher()
        for item in pantryItems {
            hasher.combine(item.name)
            hasher.combine(item.isStaple)
            hasher.combine(item.amount > 0)
        }
        hasher.combine(recipes.count)
        return hasher.finalize()
    }

    private func computePantrySuggestions() -> [PantrySuggestion] {
        let pantryKeys = Set(
            pantryItems
                .filter { $0.isStaple || $0.amount > 0 }
                .map { ShoppingListService.normalizedIngredientKey($0.name) }
        )
        guard !pantryKeys.isEmpty else { return [] }

        let suggestions = recipes.compactMap { recipe -> PantrySuggestion? in
            let normalizedIngredients = recipe.normalizedIngredients
            guard !normalizedIngredients.isEmpty else { return nil }
            let ingredientKeys = Set(normalizedIngredients.map { ShoppingListService.normalizedIngredientKey($0.name) })
            let matchCount = ingredientKeys.intersection(pantryKeys).count
            guard matchCount > 0 else { return nil }
            let score = Double(matchCount) / Double(max(ingredientKeys.count, 1))
            return PantrySuggestion(recipe: recipe, matchedIngredients: matchCount, totalIngredients: ingredientKeys.count, score: score)
        }

        return suggestions
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.recipe.title < rhs.recipe.title
                }
                return lhs.score > rhs.score
            }
            .prefix(5)
            .map { $0 }
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedCategory != nil { count += 1 }
        if showFavoritesOnly { count += 1 }
        return count
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            recipeListRoot
        }
    }

    @ViewBuilder
    private var visibleRecipesContent: some View {
        if recipes.isEmpty {
            emptyStateView
        } else {
            recipeListContent
        }
    }

    private var recipeListRoot: some View {
        visibleRecipesContent
            .scrollDismissesKeyboard(.interactively)
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { recipeListToolbar }
            .sheet(isPresented: $showingAddRecipe) {
                NavigationStack {
                    RecipeEditorView(recipe: nil)
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportView(parser: parser)
            }
            .navigationDestination(for: RecipeRoute.self) { route in
                recipeDestination(for: route)
            }
            .onAppear(perform: handleAppear)
            .task(id: pantrySuggestionKey) {
                pantrySuggestions = computePantrySuggestions()
            }
            // Selection is invisible outside the current filter; keep what's
            // selected aligned with what's on screen.
            .onChange(of: debouncedSearchText) { _, _ in clearSelectionOnFilterChange() }
            .onChange(of: selectedCategory) { _, _ in clearSelectionOnFilterChange() }
            .onChange(of: showFavoritesOnly) { _, _ in clearSelectionOnFilterChange() }
            .task(id: searchText) {
                await updateDebouncedSearchText()
            }
            .onChange(of: navigationState.spotlightRecipeID) { _, newID in
                pendingSpotlightRecipeID = newID
                routePendingSpotlightRecipe()
            }
            .onChange(of: recipes.count) { _, _ in
                routePendingSpotlightRecipe()
            }
            .alert("Delete Selected Recipes?", isPresented: $showDeleteSelectedConfirm) {
                Button("Delete", role: .destructive) { Task { await deleteSelectedRecipes() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(deleteSelectedConfirmationMessage)
            }
            .overlay {
                if isWritingBackup {
                    RVBlockingProgressOverlay(message: "Saving safety backup…")
                }
            }
            .alert("Recipe Vault Couldn’t Finish", isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { actionErrorMessage = nil }
            } message: {
                Text(actionErrorMessage ?? "An unknown error occurred.")
            }
    }

    @ToolbarContentBuilder
    private var recipeListToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            importMenu

            Button {
                showingAddRecipe = true
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Add recipe manually")
        }
    }

    private var deleteSelectedConfirmationMessage: String {
        "This permanently deletes \(selectedRecipeIDs.count) \(selectedRecipeIDs.count == 1 ? "recipe" : "recipes") and removes \(selectedRecipeIDs.count == 1 ? "it" : "them") from your meal plan. A safety backup of your library is saved on this device first."
    }

    private func handleAppear() {
        routePendingSpotlightRecipe()
        // Keep the system Spotlight index in sync with the library so
        // recipes are actually findable from iOS search. Full reindex
        // happens once per launch; saves/deletes update incrementally.
        if !recipes.isEmpty {
            SpotlightIndexingService.shared.indexAllRecipesIfNeeded(recipes)
        }
    }

    private func updateDebouncedSearchText() async {
        // Debounce: cancelled (throws) when searchText changes again.
        if searchText.isEmpty {
            debouncedSearchText = ""
            return
        }
        guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
        debouncedSearchText = searchText
    }

    @ViewBuilder
    private func recipeDestination(for route: RecipeRoute) -> some View {
        if let recipe = recipes.first(where: { $0.id == route.recipeID }) {
            RecipeDetailView(recipe: recipe)
        } else {
            ContentUnavailableView("Recipe Not Found", systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroHeader
                    .padding(.horizontal)
                    .padding(.top, 8)

                ZStack {
                    RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous)
                        .fill(LinearGradient.rvHeroGradient)
                        .overlay {
                            RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                        }

                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.8))
                                .frame(width: 88, height: 88)

                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.rvAccent)
                        }

                        Text("Your Recipe Vault is Ready")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .foregroundStyle(Color.rvInk)

                        Text("Import recipes from PDFs, photos, or the web — your pantry, meal plan, and shopping list will build themselves around what you save.")
                            .font(.body)
                            .foregroundStyle(Color.rvSubtleText)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button {
                                showingImportSheet = true
                            } label: {
                                Label("Import Recipes", systemImage: "square.and.arrow.down")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(LinearGradient.rvAccentGradient)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }

                            Button {
                                showingAddRecipe = true
                            } label: {
                                Label("Add Manually", systemImage: "plus")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.72))
                                    .foregroundStyle(Color.rvInk)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(28)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Recipe List

    private var recipeListContent: some View {
        ScrollView {
            // Filter + sort once per render, not four times.
            let filtered = filteredRecipes
            VStack(alignment: .leading, spacing: 24) {
                heroHeader
                    .padding(.horizontal)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    searchPanel
                    selectionToolbar
                }
                .padding(.horizontal)

                if !pantrySuggestions.isEmpty && searchText.isEmpty && selectedCategory == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(
                            eyebrow: "From Your Pantry",
                            title: "Cook With What You Have",
                            subtitle: "Quick wins based on the ingredients you already keep on hand."
                        )
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(pantrySuggestions) { suggestion in
                                    NavigationLink(value: RecipeRoute(recipeID: suggestion.recipe.id)) {
                                        pantrySuggestionCard(suggestion)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(searchText.isEmpty ? "Your Collection" : "Search Results")
                                .font(.system(.title3, design: .serif, weight: .bold))
                                .foregroundStyle(Color.rvInk)

                            Text("\(filtered.count) recipe\(filtered.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(Color.rvSubtleText)
                        }

                        Spacer()

                        sortMenuPill
                    }
                    .padding(.horizontal)

                    if filtered.isEmpty {
                        emptyResultsView
                            .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(filtered, id: \.id) { recipe in
                                if isSelectionMode {
                                    Button {
                                        toggleRecipeSelection(recipe.id)
                                    } label: {
                                        RecipeCardView(
                                            recipe: recipe,
                                            selectionMode: true,
                                            isSelected: selectedRecipeIDs.contains(recipe.id)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: RecipeRoute(recipeID: recipe.id)) {
                                        RecipeCardView(recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var heroHeader: some View {
        RVHeroBanner(
            title: "Recipe Vault",
            subtitle: "Your recipes, beautifully organized and ready to cook.",
            systemImage: "fork.knife.circle.fill"
        ) {
            HStack(spacing: 10) {
                heroActionButton(
                    title: "Import",
                    systemImage: "square.and.arrow.down",
                    prominent: false
                ) {
                    showingImportSheet = true
                }

                heroActionButton(
                    title: "New Recipe",
                    systemImage: "plus",
                    prominent: true
                ) {
                    showingAddRecipe = true
                }
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.rvSubtleText)

                TextField("Search recipes, ingredients, tags...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.rvMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous)
                    .stroke(Color.rvTaupe.opacity(0.35), lineWidth: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(title: "All Recipes", isSelected: selectedCategory == nil && !showFavoritesOnly) {
                        selectedCategory = nil
                        showFavoritesOnly = false
                    }

                    FilterChip(title: "Favorites", icon: "heart.fill", isSelected: showFavoritesOnly) {
                        showFavoritesOnly.toggle()
                    }

                    ForEach(RecipeCategory.allCases.filter { $0 != .other }) { cat in
                        FilterChip(
                            title: cat.displayName,
                            icon: cat.icon,
                            isSelected: selectedCategory == cat
                        ) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(18)
        .background(Color.rvSurface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button {
                if isSelectionMode {
                    selectedRecipeIDs.removeAll()
                    isSelectionMode = false
                } else {
                    isSelectionMode = true
                }
            } label: {
                Label(
                    isSelectionMode ? "Done Selecting" : "Select Recipes",
                    systemImage: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.85))
                .foregroundStyle(Color.rvInk)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if isSelectionMode {
                Text("\(selectedRecipeIDs.count) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.rvSubtleText)
                    .lineLimit(1)

                Button(role: .destructive) {
                    showDeleteSelectedConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedRecipeIDs.isEmpty)
            } else if activeFilterCount > 0 || !searchText.isEmpty {
                Button {
                    searchText = ""
                    selectedCategory = nil
                    showFavoritesOnly = false
                } label: {
                    Text("Clear Filters")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.75))
                        .foregroundStyle(Color.rvSubtleText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortMenuPill: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                Text(sortOrder.rawValue)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.88))
            .foregroundStyle(Color.rvInk)
            .clipShape(Capsule())
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.rvMuted)

            Text("No recipes match this view")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            Text("Try a different search or clear a filter to bring more recipes back into the collection.")
                .font(.subheadline)
                .foregroundStyle(Color.rvSubtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
    }

    private func heroActionButton(
        title: String,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background {
                    if prominent {
                        Capsule()
                            .fill(LinearGradient.rvAccentGradient)
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.76))
                    }
                }
                .foregroundStyle(prominent ? Color.white : Color.rvInk)
        }
        .buttonStyle(.plain)
    }

    private func pantrySuggestionCard(_ suggestion: PantrySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.recipe.category.displayName.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.rvSubtleText)

            Text(suggestion.recipe.title)
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)
                .lineLimit(2)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.rvPrimary)
                Text("\(suggestion.matchedIngredients) of \(suggestion.totalIngredients) ingredients ready")
                    .font(.caption)
                    .foregroundStyle(Color.rvSubtleText)
            }

            ProgressView(value: suggestion.score)
                .tint(Color.rvAccent)
        }
        .padding(16)
        .frame(width: 230, alignment: .leading)
        .frame(minHeight: 150, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }

    // MARK: - Menus

    private var importMenu: some View {
        Button {
            showingImportSheet = true
            AnalyticsService.shared.track("open_import_sheet")
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .accessibilityLabel("Import recipes")
    }

    private func clearSelectionOnFilterChange() {
        if isSelectionMode {
            selectedRecipeIDs.removeAll()
        }
    }

    private func toggleRecipeSelection(_ id: UUID) {
        if selectedRecipeIDs.contains(id) {
            selectedRecipeIDs.remove(id)
        } else {
            selectedRecipeIDs.insert(id)
        }
    }

    private func deleteSelectedRecipes() async {
        guard !selectedRecipeIDs.isEmpty, !isWritingBackup else { return }
        let toDelete = recipes.filter { selectedRecipeIDs.contains($0.id) }
        let count = toDelete.count
        guard count > 0 else {
            selectedRecipeIDs.removeAll()
            isSelectionMode = false
            return
        }

        isWritingBackup = true
        defer { isWritingBackup = false }
        do {
            let payload = RecipeLibraryMaintenance.fullBackupPayload(recipes: recipes, modelContext: modelContext)
            _ = try await RecipeExportService.writeAutomaticBackup(payload: payload)
        } catch {
            actionErrorMessage = "Nothing was deleted because the safety backup could not be saved: \(error.localizedDescription)"
            AnalyticsService.shared.track("recipes_bulk_delete_backup_failed")
            return
        }

        // Drop meal-plan entries pointing at the deleted recipes so plans
        // don't keep showing meals that can no longer generate shopping items.
        do {
            try MealPlanningService.removeEntries(forRecipeIDs: Set(toDelete.map(\.id)), modelContext: modelContext)
        } catch {
            modelContext.rollback()
            actionErrorMessage = "Nothing was deleted because the meal plan cleanup could not be saved: \(error.localizedDescription)"
            AnalyticsService.shared.track("recipes_bulk_delete_plan_cleanup_failed")
            return
        }

        let deletedIDs = toDelete.map(\.id)
        for recipe in toDelete {
            modelContext.delete(recipe)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            actionErrorMessage = "The recipes were not deleted because the change could not be saved: \(error.localizedDescription)"
            AnalyticsService.shared.track("recipes_bulk_delete_save_failed")
            return
        }

        SpotlightIndexingService.shared.removeRecipes(ids: deletedIDs)

        AnalyticsService.shared.track("recipes_bulk_deleted", metadata: [
            "count": "\(count)"
        ])

        selectedRecipeIDs.removeAll()
        isSelectionMode = false
    }

    private func routePendingSpotlightRecipe() {
        guard let requestedID = pendingSpotlightRecipeID ?? navigationState.spotlightRecipeID else { return }

        guard recipes.contains(where: { $0.id == requestedID }) else {
            // Not found. On a cold launch the library query may not have
            // populated yet, so retain the request and retry on the next list
            // change. But once the library has loaded without it (or we've run
            // out of retries) the recipe is gone — clear the request so a
            // deleted-recipe tap can't linger and hijack a later navigation.
            if recipes.isEmpty && spotlightRouteAttempts < 5 {
                pendingSpotlightRecipeID = requestedID
                spotlightRouteAttempts += 1
            } else {
                pendingSpotlightRecipeID = nil
                navigationState.clearSpotlightRequest()
                spotlightRouteAttempts = 0
                AnalyticsService.shared.track("spotlight_open_missing")
            }
            return
        }

        if navigationPath.last?.recipeID != requestedID {
            navigationPath = [RecipeRoute(recipeID: requestedID)]
        }

        pendingSpotlightRecipeID = nil
        navigationState.clearSpotlightRequest()
        spotlightRouteAttempts = 0
        AnalyticsService.shared.track("spotlight_open_success")
    }
}

private struct RecipeRoute: Hashable {
    let recipeID: UUID
}

private struct PantrySuggestion: Identifiable {
    let recipe: Recipe
    let matchedIngredients: Int
    let totalIngredients: Int
    let score: Double

    var id: UUID { recipe.id }
}

private struct SectionHeaderView: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.rvSubtleText)

            Text(title)
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.rvSubtleText)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    Capsule()
                        .fill(LinearGradient.rvAccentGradient)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.82))
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.rvInk)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .buttonStyle(.plain)
    }
}

// MARK: - Recipe Card

struct RecipeCardView: View {
    let recipe: Recipe
    var selectionMode: Bool = false
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                thumbnailView

                HStack(spacing: 8) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.red.opacity(0.88))
                            .clipShape(Circle())
                    }

                    if selectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.rvPrimary : Color.white.opacity(0.85))
                            .padding(10)
                            .background(Color.black.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recipe.category.displayName.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(Color.rvSubtleText)

                        Text(recipe.title)
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .foregroundStyle(Color.rvInk)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if !selectionMode {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.rvMuted)
                    }
                }

                if shouldShowSummary {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if recipe.totalTime > 0 {
                        metadataPill(title: "\(recipe.totalTime) min", systemImage: "clock")
                    }

                    metadataPill(title: recipe.difficulty.displayName, systemImage: "speedometer")

                    if recipe.rating > 0 {
                        metadataPill(title: "\(recipe.rating)", systemImage: "star.fill")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.92))
        .contentShape(RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [recipe.title, recipe.category.displayName]
        if recipe.totalTime > 0 { parts.append("\(recipe.totalTime) minutes") }
        if recipe.rating > 0 { parts.append("rated \(recipe.rating) of 5") }
        if recipe.isFavorite { parts.append("favorite") }
        if selectionMode { parts.append(isSelected ? "selected" : "not selected") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let firstPhoto = recipe.photoData.first,
           let image = RecipeThumbnailCache.shared.thumbnail(for: firstPhoto, recipeID: recipe.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 186)
                .clipShape(RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous)
                    .fill(categoryGradient)
                    .frame(maxWidth: .infinity)
                    .frame(height: 186)

                Image(systemName: recipe.category.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
        }
    }

    private var shouldShowSummary: Bool {
        let trimmed = recipe.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        return !trimmed.lowercased().hasPrefix("imported from")
    }

    private var categoryGradient: LinearGradient {
        let colors: [Color] = {
            switch recipe.category {
                case .breakfast: return [Color.rvPrimary, Color.rvSecondary]
            case .lunch: return [Color(red: 0.58, green: 0.69, blue: 0.43), Color.rvSecondary]
            case .dinner: return [Color.rvPrimary, Color(red: 0.42, green: 0.35, blue: 0.24)]
            case .dessert: return [Color(red: 0.78, green: 0.58, blue: 0.50), Color.rvCream]
            case .beverage: return [Color.rvSecondary, Color.rvPrimary]
            case .soup: return [Color.rvTaupe, Color.rvPrimary]
            case .appetizer: return [Color.rvSecondary, Color.rvCream]
            case .snack: return [Color.rvCream, Color.rvTaupe]
            case .bread: return [Color.rvTaupe, Color.rvCream]
            default: return [Color.rvTaupe, Color.rvMuted]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func metadataPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.rvSurface.opacity(0.95))
            .foregroundStyle(Color.rvInk)
            .clipShape(Capsule())
    }
}

#Preview {
    RecipeListView()
        .environmentObject(AppNavigationState())
        .modelContainer(for: [Recipe.self, PantryItem.self], inMemory: true)
}

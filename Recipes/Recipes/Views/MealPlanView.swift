import SwiftUI
import SwiftData

struct MealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealPlan.weekStartDate, order: .reverse) private var mealPlans: [MealPlan]
    @Query(sort: \Recipe.title) private var allRecipes: [Recipe]
    @Query private var existingShoppingItems: [ShoppingItem]
    @Query private var pantryItems: [PantryItem]

    let openShoppingList: () -> Void

    @State private var selectedDay: Int = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var showAddRecipe = false
    @State private var selectedSlot: MealSlot = .dinner
    @State private var recipeSearchText = ""
    @State private var showShoppingConfirmation = false
    @State private var generatedItemCount = 0
    @State private var actionErrorMessage: String?

    /// Weeks relative to the current week (0 = this week, 1 = next week).
    @State private var weekOffset = 0

    private var displayedWeekStart: Date {
        let thisWeek = MealPlanningService.weekStart()
        return Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeek) ?? thisWeek
    }

    /// The plan for the week being viewed — not "most recent plan ever",
    /// which made the meal plan one eternal week with no rollover.
    private var currentPlan: MealPlan? {
        MealPlanningService.plan(forWeekContaining: displayedWeekStart, in: mealPlans)
    }

    private let days = MealPlanEntry.shortDayNames

    private var filteredRecipeChoices: [Recipe] {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allRecipes }

        let lowerQuery = query.lowercased()
        return allRecipes.filter { recipe in
            recipe.title.lowercased().contains(lowerQuery)
                || recipe.tags.contains(where: { $0.lowercased().contains(lowerQuery) })
                || recipe.normalizedIngredients.contains(where: { $0.name.lowercased().contains(lowerQuery) })
        }
    }

    private var recipePickerEmptyMessage: String {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "No recipes in your library yet." }
        return "No recipes match \"\(query)\"."
    }

    private var selectedDayName: String {
        days[selectedDay]
    }

    private var selectedDayEntriesCount: Int {
        currentPlan?.entries(for: selectedDay).count ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    weekSelector
                    daySelector

                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(selectedDayName)'s Plan")
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .foregroundStyle(Color.rvInk)

                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            mealSlotSection(slot)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rvBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        generateShoppingList()
                    } label: {
                        Label("Shopping List", systemImage: "cart.badge.plus")
                    }
                    .disabled((currentPlan?.entries.isEmpty ?? true) || allRecipes.isEmpty)
                }
            }
            .sheet(isPresented: $showAddRecipe) {
                recipePickerSheet
            }
            .alert("Shopping List Generated", isPresented: $showShoppingConfirmation) {
                Button("Go to Shopping List") {
                    openShoppingList()
                }
                Button("Stay Here", role: .cancel) { }
            } message: {
                Text("\(generatedItemCount) items added to your shopping list.")
            }
            .alert("Couldn’t Save Changes", isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { actionErrorMessage = nil }
            } message: {
                Text(actionErrorMessage ?? "An unknown error occurred.")
            }
            .navigationDestination(for: UUID.self) { recipeID in
                if let recipe = allRecipes.first(where: { $0.id == recipeID }) {
                    RecipeDetailView(recipe: recipe)
                }
            }
            .onAppear {
                migrateLegacyPlanIfNeeded()
            }
        }
    }

    private var weekSelector: some View {
        HStack(spacing: 12) {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.rvAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous week")

            VStack(spacing: 2) {
                Text(weekLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.rvInk)
                Text(weekRangeText)
                    .font(.caption)
                    .foregroundStyle(Color.rvSubtleText)
            }
            .frame(maxWidth: .infinity)

            if weekOffset != 0 {
                Button("This Week") {
                    weekOffset = 0
                    selectedDay = Calendar.current.component(.weekday, from: Date()) - 1
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rvAccent)
            }

            Button {
                weekOffset += 1
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.rvAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weekLabel: String {
        switch weekOffset {
        case 0: return "This Week"
        case 1: return "Next Week"
        case -1: return "Last Week"
        default: return weekOffset > 0 ? "\(weekOffset) Weeks Ahead" : "\(-weekOffset) Weeks Ago"
        }
    }

    private var weekRangeText: String {
        let start = displayedWeekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    /// Builds before week navigation kept a single eternal plan whose
    /// weekStartDate was its creation date. Rebase that plan onto the current
    /// week once, so existing entries stay visible under week semantics.
    private func migrateLegacyPlanIfNeeded() {
        let migrationKey = "meal_plan_week_migration_done"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        if MealPlanningService.plan(forWeekContaining: Date(), in: mealPlans) == nil,
           let legacyPlan = mealPlans.first,
           !legacyPlan.entries.isEmpty {
            legacyPlan.weekStartDate = MealPlanningService.weekStart()
            // Persist the rebase BEFORE marking the migration done. Setting the
            // flag first means a kill in between leaves the migration "done" but
            // unapplied, stranding the legacy plan in a past week where the
            // week-scoped lookup can never surface it again.
            guard (try? modelContext.save()) != nil else { return }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private var heroHeader: some View {
        RVHeroBanner(
            title: "Meal Plan",
            subtitle: "Shape the week, then turn it into a shopping list with pantry-aware ingredients.",
            systemImage: "calendar",
            metrics: [
                ("Planned Meals", "\(currentPlan?.entries.count ?? 0)"),
                (selectedDayName, "\(selectedDayEntriesCount)")
            ]
        )
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { day in
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: 6) {
                            Text(days[day])
                                .font(.subheadline.weight(.semibold))

                            let count = currentPlan?.entries(for: day).count ?? 0
                            Text(count == 0 ? "Open" : "\(count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedDay == day ? Color.white.opacity(0.85) : Color.rvSubtleText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background {
                            if selectedDay == day {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(LinearGradient.rvAccentGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.rvPaper)
                            }
                        }
                        .foregroundStyle(selectedDay == day ? Color.white : Color.rvInk)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func mealSlotSection(_ slot: MealSlot) -> some View {
        let entries = currentPlan?.entries(for: selectedDay).filter { $0.mealSlot == slot } ?? []

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(slot.displayName, systemImage: slot.icon)
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(Color.rvInk)

                Spacer()

                Button {
                    selectedSlot = slot
                    showAddRecipe = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.rvSurface, in: Capsule())
                        .foregroundStyle(Color.rvInk)
                }
                .buttonStyle(.plain)
            }

            if entries.isEmpty {
                Text("No meal planned for this slot yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.rvSubtleText)
                    .padding(.vertical, 6)
            } else {
                ForEach(entries) { entry in
                    entryRow(entry, in: currentPlan)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 14, y: 7)
    }

    private func entryRow(_ entry: MealPlanEntry, in plan: MealPlan?) -> some View {
        let linkedRecipe = allRecipes.first { $0.id == entry.recipeID }

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let recipe = linkedRecipe {
                    NavigationLink(value: recipe.id) {
                        Text(entry.recipeTitle)
                            .font(.headline)
                            .foregroundStyle(Color.rvInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(entry.recipeTitle)
                        .font(.headline)
                        .foregroundStyle(Color.rvSubtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Stepper("\(entry.servings) servings", value: Binding(
                    get: { entry.servings },
                    set: { newValue in updateServings(entry, to: newValue, in: plan) }
                ), in: 1...100)
                .font(.caption)
                .foregroundStyle(Color.rvSubtleText)
            }

            Spacer()

            Button {
                removeEntry(entry)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.rvMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func updateServings(_ entry: MealPlanEntry, to newValue: Int, in plan: MealPlan?) {
        guard let plan else { return }
        var entries = plan.entries
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].servings = newValue
        plan.entries = entries
        _ = saveChanges(failureMessage: "Could not update servings")
    }

    private var recipePickerSheet: some View {
        NavigationStack {
            Group {
                if filteredRecipeChoices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: recipeSearchText.isEmpty ? "book.closed" : "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.rvAccent.opacity(0.6))
                        Text(recipePickerEmptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.rvSubtleText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List(filteredRecipeChoices) { recipe in
                        Button {
                            addEntry(recipe: recipe, slot: selectedSlot)
                            recipeSearchText = ""
                            showAddRecipe = false
                        } label: {
                            HStack {
                                Image(systemName: recipe.category.icon)
                                    .foregroundStyle(Color.rvAccent)
                                VStack(alignment: .leading) {
                                    Text(recipe.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if recipe.totalTime > 0 {
                                        Text("\(recipe.totalTime) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .foregroundStyle(Color.rvInk)
                        .listRowBackground(Color.rvPaper)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rvBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recipeSearchText = ""
                        showAddRecipe = false
                    }
                }
            }
            .searchable(text: $recipeSearchText, prompt: "Search recipes...")
        }
        .presentationDetents([.medium, .large])
    }

    private func addEntry(recipe: Recipe, slot: MealSlot) {
        let plan = currentPlan ?? createCurrentPlan()
        let entry = MealPlanEntry(
            recipeID: recipe.id,
            recipeTitle: recipe.title,
            dayOfWeek: selectedDay,
            mealSlot: slot,
            servings: recipe.servings
        )
        // Reassign rather than mutate in place — MealPlanningService documents
        // that SwiftData doesn't reliably track in-place edits to this value
        // array, and this keeps the view consistent with that rule.
        plan.entries = plan.entries + [entry]
        guard saveChanges(failureMessage: "Could not add this meal to your plan") else { return }

        AnalyticsService.shared.track("meal_plan_entry_added", metadata: [
            "slot": slot.rawValue,
            "day": "\(selectedDay)"
        ])
    }

    private func removeEntry(_ entry: MealPlanEntry) {
        guard let plan = currentPlan else { return }
        plan.entries = plan.entries.filter { $0.id != entry.id }
        guard saveChanges(failureMessage: "Could not remove this meal from your plan") else { return }
    }

    private func generateShoppingList() {
        guard let plan = currentPlan else { return }

        let entries = MealPlanningService.aggregatedServingEntries(for: plan, recipes: allRecipes)
        guard !entries.isEmpty else { return }

        let count = ShoppingListService.regenerateShoppingList(
            from: entries,
            existingItems: existingShoppingItems,
            pantryItems: pantryItems,
            modelContext: modelContext
        )
        guard saveChanges(failureMessage: "Could not update your shopping list") else { return }

        generatedItemCount = count
        showShoppingConfirmation = true
        AnalyticsService.shared.track("shopping_list_generated", metadata: [
            "count": "\(count)",
            "planned_recipes": "\(entries.count)"
        ])
    }

    private func createCurrentPlan() -> MealPlan {
        let plan = MealPlan(weekStartDate: displayedWeekStart)
        modelContext.insert(plan)
        return plan
    }

    private func saveChanges(failureMessage: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            actionErrorMessage = "\(failureMessage): \(error.localizedDescription)"
            AnalyticsService.shared.track("meal_plan_save_failed")
            return false
        }
    }
}

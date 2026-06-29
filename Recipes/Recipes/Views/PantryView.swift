import SwiftUI
import SwiftData

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \ShoppingItem.dateAdded, order: .reverse) private var shoppingItems: [ShoppingItem]
    @Query(sort: \MealPlan.weekStartDate, order: .reverse) private var mealPlans: [MealPlan]
    @Query(sort: \Recipe.title) private var allRecipes: [Recipe]

    @State private var name = ""
    @State private var amount = ""
    @State private var unit = ""
    @State private var selectedCategory: ShoppingCategory = .pantry
    @State private var markAsStaple = false
    @State private var searchText = ""
    @State private var pantryStatusMessage: String?
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showClearAllConfirm = false
    @State private var showRestoreConfirm = false
    @State private var canRestoreBackup = false

    /// The plan for the current calendar week, matching MealPlanView's
    /// week-scoped semantics (not "most recent plan ever created").
    private var currentPlan: MealPlan? {
        MealPlanningService.plan(forWeekContaining: Date(), in: mealPlans)
    }
    private var checkedShoppingItems: [ShoppingItem] { shoppingItems.filter { $0.isChecked } }
    private var activePantryCoverageCount: Int { pantryItems.filter { $0.isStaple || $0.amount > 0 }.count }
    private var pantryBackupFingerprint: Int {
        var hasher = Hasher()
        for item in pantryItems {
            hasher.combine(item.id)
            hasher.combine(item.name)
            hasher.combine(item.amount)
            hasher.combine(item.unit)
            hasher.combine(item.category.rawValue)
            hasher.combine(item.isStaple)
            hasher.combine(item.dateUpdated.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    private var filteredPantryItems: [PantryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return pantryItems }

        let lowerQuery = query.lowercased()
        return pantryItems.filter { item in
            item.name.lowercased().contains(lowerQuery)
                || item.unit.lowercased().contains(lowerQuery)
                || item.category.rawValue.lowercased().contains(lowerQuery)
        }
    }

    private var groupedItems: [(ShoppingCategory, [PantryItem])] {
        let grouped = Dictionary(grouping: filteredPantryItems) { $0.category }
        return ShoppingCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    searchCard
                    quickAddCard
                    syncCard

                    if let pantryStatusMessage {
                        statusCard(pantryStatusMessage)
                    }

                    if groupedItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedItems, id: \.0) { category, items in
                            pantrySection(category, items: items)
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
                ToolbarItemGroup(placement: .primaryAction) {
                    if !pantryItems.isEmpty {
                        Button {
                            exportPantry()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }

                    if !pantryItems.isEmpty {
                        Button("Clear All", role: .destructive) {
                            showClearAllConfirm = true
                        }
                    }

                    // Surfaced only when a pre-clear snapshot exists to restore
                    // from, so an accidental Clear All is recoverable.
                    if canRestoreBackup {
                        Button {
                            showRestoreConfirm = true
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("Clear all pantry items?", isPresented: $showClearAllConfirm) {
                Button("Clear All", role: .destructive) { clearAllPantryItems() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove all \(pantryItems.count) pantry item(s). A recovery snapshot is saved first — tap Restore afterward to bring them back.")
            }
            .alert("Restore pantry from backup?", isPresented: $showRestoreConfirm) {
                Button("Restore") { restorePantryFromBackup() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This adds back items from your most recent recovery snapshot. Items already in your pantry are left untouched.")
            }
            .alert("Edit Quantity", isPresented: Binding(
                get: { editingItem != nil },
                set: { if !$0 { editingItem = nil } }
            )) {
                TextField("Amount", text: $editAmount)
                    .keyboardType(.decimalPad)
                TextField("Unit", text: $editUnit)
                Button("Save") {
                    if let item = editingItem {
                        item.amount = IngredientLineParser.flexibleDouble(editAmount) ?? 0
                        item.unit = editUnit.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.dateUpdated = Date()
                        _ = persistPantryChanges(snapshot: pantryItems)
                        pantryStatusMessage = "Updated \(item.name)."
                    }
                    editingItem = nil
                }
                Button("Cancel", role: .cancel) { editingItem = nil }
            } message: {
                if let item = editingItem {
                    Text("Set quantity for \(item.name)")
                }
            }
            .onAppear {
                refreshAutomaticBackup()
                canRestoreBackup = PantryBackupService.hasRestorableBackup()
            }
            .onChange(of: pantryBackupFingerprint) { _, _ in
                refreshAutomaticBackup()
            }
            .onChange(of: pantryStatusMessage) { _, newMessage in
                guard newMessage != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    if pantryStatusMessage == newMessage {
                        withAnimation { pantryStatusMessage = nil }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .inactive {
                    refreshAutomaticBackup()
                }
            }
        }
    }

    private var heroHeader: some View {
        RVHeroBanner(
            title: "Pantry",
            subtitle: "Track staples and quantities so your shopping list knows what’s already covered.",
            systemImage: "cabinet.fill",
            metrics: [
                ("Items", "\(pantryItems.count)"),
                ("Covering", "\(activePantryCoverageCount)")
            ]
        )
    }

    private var searchCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.rvSubtleText)

            TextField("Search pantry", text: $searchText)

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
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Add")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            HStack(spacing: 12) {
                TextField("Item", text: $name)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                TextField("Amt", text: $amount)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(width: 82)
                    .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                TextField("Unit", text: $unit)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(width: 90)
                    .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(ShoppingCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.icon).tag(category)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.rvInk)

            Toggle("Mark as staple", isOn: $markAsStaple)
                .tint(Color.rvAccent)

            Button {
                addItem()
            } label: {
                Label("Add Pantry Item", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.rvAccentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shopping Sync")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            syncButton(
                title: checkedShoppingItems.isEmpty
                    ? "No Checked Shopping Items to Stock"
                    : "Stock Checked Shopping Items (\(checkedShoppingItems.count))",
                systemImage: "cart.badge.plus",
                action: stockCheckedShoppingItems
            )
            .disabled(checkedShoppingItems.isEmpty)

            syncButton(
                title: "Refresh Shopping List Using Pantry",
                systemImage: "arrow.clockwise.circle",
                action: refreshShoppingListWithPantry
            )
            .disabled((currentPlan?.entries.isEmpty ?? true) || allRecipes.isEmpty)

            Text("Staple items are always skipped in generated shopping lists. Quantified pantry items reduce what still needs to be bought.")
                .font(.caption)
                .foregroundStyle(Color.rvSubtleText)

            Text("Your pantry is auto-saved to a JSON backup on this device, and you can export a copy anytime.")
                .font(.caption)
                .foregroundStyle(Color.rvSubtleText)
        }
        .padding(18)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func pantrySection(_ category: ShoppingCategory, items: [PantryItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(category.displayName, systemImage: category.icon)
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            ForEach(items) { item in
                pantryRow(item)
            }
        }
    }

    @State private var editingItem: PantryItem?
    @State private var editAmount = ""
    @State private var editUnit = ""

    private func pantryRow(_ item: PantryItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Color.rvInk)

                Text(stockLine(for: item))
                    .font(.caption)
                    .foregroundStyle(Color.rvSubtleText)
            }

            Spacer()

            Button {
                editingItem = item
                editAmount = item.amount > 0 ? formatAmount(item.amount) : ""
                editUnit = item.unit
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
                    .foregroundStyle(Color.rvAccent)
            }
            .buttonStyle(.plain)

            Button {
                item.isStaple.toggle()
                item.dateUpdated = Date()
                _ = persistPantryChanges(snapshot: pantryItems)
            } label: {
                Image(systemName: item.isStaple ? "checkmark.seal.fill" : "seal")
                    .font(.title3)
                    .foregroundStyle(item.isStaple ? Color.rvPrimary : Color.rvMuted)
            }
            .buttonStyle(.plain)

            Button {
                item.amount = 0
                item.dateUpdated = Date()
                _ = persistPantryChanges(snapshot: pantryItems)
            } label: {
                Text("Out")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                deletePantryItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .contextMenu {
            Button(role: .destructive) {
                deletePantryItem(item)
            } label: {
                Label("Delete Item", systemImage: "trash")
            }
        }
    }

    private func deletePantryItem(_ item: PantryItem) {
        let itemName = item.name
        let remaining = pantryItems.filter { $0.id != item.id }
        modelContext.delete(item)
        if persistPantryChanges(snapshot: remaining) {
            pantryStatusMessage = "Removed \(itemName) from pantry."
            AnalyticsService.shared.track("pantry_item_deleted")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(Color.rvAccent.opacity(0.7))

            Text("No Pantry Items Yet")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            Text("Add your staples and tracked quantities here so the rest of the app can plan around them.")
                .font(.subheadline)
                .foregroundStyle(Color.rvSubtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.rvInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func syncButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Color.rvInk)
        }
        .buttonStyle(.plain)
    }

    private func stockLine(for item: PantryItem) -> String {
        if item.isStaple {
            return "Staple item · always skipped in shopping list"
        }
        if item.amount > 0 {
            if item.unit.isEmpty {
                return "Tracked quantity: \(formatAmount(item.amount))"
            }
            return "Tracked quantity: \(formatAmount(item.amount)) \(item.unit)"
        }
        return "No quantity tracked"
    }

    private func formatAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func addItem() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let parsedAmount = IngredientLineParser.flexibleDouble(amount) ?? 0
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = ShoppingListService.normalizedIngredientKey(trimmedName)

        if let existing = pantryItems.first(where: {
            ShoppingListService.normalizedIngredientKey($0.name) == normalizedKey
        }) {
            let absorbed = existing.absorbStock(amount: parsedAmount, unit: normalizedUnit)
            existing.category = selectedCategory
            existing.isStaple = existing.isStaple || markAsStaple
            existing.dateUpdated = Date()
            pantryStatusMessage = absorbed
                ? "Updated \(existing.name)."
                : "Updated \(existing.name) — kept existing quantity because the units differ (\(existing.unit) vs \(normalizedUnit))."
        } else {
            let item = PantryItem(
                name: trimmedName,
                amount: max(parsedAmount, 0),
                unit: normalizedUnit,
                category: selectedCategory,
                isStaple: markAsStaple
            )
            modelContext.insert(item)
            pantryStatusMessage = "Added \(trimmedName) to pantry."
            if persistPantryChanges(snapshot: pantryItems + [item]) {
                AnalyticsService.shared.track("pantry_item_added", metadata: [
                    "category": selectedCategory.rawValue,
                    "is_staple": markAsStaple ? "true" : "false"
                ])

                name = ""
                amount = ""
                unit = ""
                markAsStaple = false
            }
            return
        }

        if persistPantryChanges(snapshot: pantryItems) {
            AnalyticsService.shared.track("pantry_item_added", metadata: [
                "category": selectedCategory.rawValue,
                "is_staple": markAsStaple ? "true" : "false"
            ])

            name = ""
            amount = ""
            unit = ""
            markAsStaple = false
        }
    }

    private func clearAllPantryItems() {
        let count = pantryItems.count

        // Capture a recovery snapshot to a dedicated file BEFORE deleting.
        // The rolling automatic backup is about to be overwritten with the
        // emptied pantry, so it can't be the recovery story here.
        var snapshotSaved = true
        do {
            try PantryBackupService.writePreClearBackup(pantryItems: pantryItems)
        } catch {
            snapshotSaved = false
        }

        for item in pantryItems {
            modelContext.delete(item)
        }
        if persistPantryChanges(snapshot: []) {
            canRestoreBackup = snapshotSaved && PantryBackupService.hasRestorableBackup()
            pantryStatusMessage = canRestoreBackup
                ? "Cleared \(count) pantry item(s). Tap Restore to bring them back."
                : "Cleared \(count) pantry item(s)."
            AnalyticsService.shared.track("pantry_cleared", metadata: ["count": "\(count)"])
        }
    }

    private func restorePantryFromBackup() {
        do {
            let restored = try PantryBackupService.restoreFromPreClearBackup()
            guard !restored.isEmpty else {
                pantryStatusMessage = "No recovery snapshot found to restore."
                return
            }

            // Don't duplicate items already present after a partial restore.
            let existingKeys = Set(pantryItems.map {
                ShoppingListService.normalizedIngredientKey($0.name)
            })
            var snapshot = pantryItems
            var added = 0
            for item in restored where !existingKeys.contains(ShoppingListService.normalizedIngredientKey(item.name)) {
                modelContext.insert(item)
                snapshot.append(item)
                added += 1
            }

            guard added > 0 else {
                pantryStatusMessage = "Those pantry items are already restored."
                return
            }

            if persistPantryChanges(snapshot: snapshot) {
                pantryStatusMessage = "Restored \(added) pantry item(s) from backup."
                AnalyticsService.shared.track("pantry_restored", metadata: ["count": "\(added)"])
            }
        } catch {
            pantryStatusMessage = "Could not restore pantry: \(error.localizedDescription)"
            AnalyticsService.shared.track("pantry_restore_failed")
        }
    }

    private func stockCheckedShoppingItems() {
        let checkedItems = checkedShoppingItems
        guard !checkedItems.isEmpty else {
            pantryStatusMessage = "No checked shopping items to stock."
            return
        }

        var added = 0
        var updated = 0
        var pantrySnapshot = pantryItems

        for shoppingItem in checkedItems {
            let normalizedKey = ShoppingListService.normalizedIngredientKey(shoppingItem.name)
            if let pantryMatch = pantryItems.first(where: {
                ShoppingListService.normalizedIngredientKey($0.name) == normalizedKey
            }) {
                let incomingAmount = shoppingItem.amount > 0 ? shoppingItem.amount : 1
                pantryMatch.absorbStock(amount: incomingAmount, unit: shoppingItem.unit)
                pantryMatch.category = shoppingItem.category
                pantryMatch.dateUpdated = Date()
                updated += 1
            } else {
                let item = PantryItem(
                    name: shoppingItem.name,
                    amount: shoppingItem.amount > 0 ? shoppingItem.amount : 1,
                    unit: shoppingItem.unit,
                    category: shoppingItem.category
                )
                modelContext.insert(item)
                pantrySnapshot.append(item)
                added += 1
            }
            modelContext.delete(shoppingItem)
        }

        if persistPantryChanges(snapshot: pantrySnapshot) {
            pantryStatusMessage = "Stocked pantry from shopping: \(added) added, \(updated) updated."
            AnalyticsService.shared.track("pantry_stock_from_shopping", metadata: [
                "added": "\(added)",
                "updated": "\(updated)"
            ])
        }
    }

    private func refreshShoppingListWithPantry() {
        guard let plan = currentPlan else {
            pantryStatusMessage = "Plan meals for this week first, then refresh your shopping list."
            return
        }

        let entries = MealPlanningService.aggregatedServingEntries(for: plan, recipes: allRecipes)
        guard !entries.isEmpty else {
            pantryStatusMessage = "No planned recipes found to build a shopping list."
            return
        }

        let neededCount = ShoppingListService.regenerateShoppingList(
            from: entries,
            existingItems: shoppingItems,
            pantryItems: pantryItems,
            modelContext: modelContext
        )

        if saveModelContext() {
            pantryStatusMessage = "Shopping list refreshed with pantry coverage. \(neededCount) item(s) needed."
            AnalyticsService.shared.track("pantry_refresh_shopping", metadata: [
                "needed_count": "\(neededCount)",
                "planned_recipe_count": "\(entries.count)"
            ])
        }
    }

    private func exportPantry() {
        do {
            let exportURL = try PantryBackupService.makeShareableExportFile(pantryItems: pantryItems)
            shareURL = exportURL
            showShareSheet = true
            pantryStatusMessage = "Exported \(pantryItems.count) pantry item(s)."
            AnalyticsService.shared.track("pantry_export_json", metadata: ["count": "\(pantryItems.count)"])
        } catch {
            pantryStatusMessage = "Could not export pantry: \(error.localizedDescription)"
            AnalyticsService.shared.track("pantry_export_json_failed")
        }
    }

    private func refreshAutomaticBackup() {
        do {
            _ = try PantryBackupService.writeAutomaticBackup(pantryItems: pantryItems)
        } catch {
            if !pantryItems.isEmpty {
                pantryStatusMessage = "Could not update pantry backup: \(error.localizedDescription)"
            }
            AnalyticsService.shared.track("pantry_auto_backup_failed")
        }
    }

    private func persistPantryChanges(snapshot: [PantryItem]) -> Bool {
        guard saveModelContext() else { return false }

        do {
            _ = try PantryBackupService.writeAutomaticBackup(pantryItems: snapshot)
            return true
        } catch {
            pantryStatusMessage = "Saved pantry, but backup failed: \(error.localizedDescription)"
            AnalyticsService.shared.track("pantry_auto_backup_failed")
            return true
        }
    }

    private func saveModelContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            pantryStatusMessage = "Could not save pantry changes: \(error.localizedDescription)"
            AnalyticsService.shared.track("pantry_save_failed")
            return false
        }
    }
}

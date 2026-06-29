# Recipe Vault App Review Findings

Last reviewed: 2026-06-28

## Brutally Honest Summary

Recipe Vault has a strong product center: personal recipes, import review, pantry-aware planning, and backup-first maintenance. The app feels most premium where it is calm, explicit, and recoverable. It feels weakest where large SwiftUI screens mix view layout, persistence, routing, and destructive actions in one place.

The biggest product risks are not visual. They are trust failures:

- A recipe opens to the wrong detail because list identity and navigation drift.
- A save appears to succeed because a sheet dismissed, but SwiftData failed.
- A destructive action proceeds even though its promised safety backup failed.
- Duplicate cleanup or delete cleanup partially changes meal plans and recipes.
- Import succeeds structurally while the recipe content is wrong or low quality.

Premium polish should therefore mean: stable navigation, visible save/delete outcomes, explicit recovery language, consistent empty/error states, and restrained warm visuals.

## Current Strengths

- Clear branch law and source-of-truth docs now reduce agent confusion.
- UI foundation is product-specific and appropriately restrained.
- Import flow includes review before trust, which is the right product posture.
- Pantry, meal plan, and shopping list are connected around real daily use.
- Backup/import/export services preserve backward compatibility better than a typical small app.
- Shared primitives in `Extensions/Theme.swift` give the app a coherent visual vocabulary.
- SSRF protection on URL scraping is thorough with pre-request validation and redirect-hop guarding.
- Keychain API key storage follows correct patterns (proper kSecClass, update-or-create flow, accessibility attributes).

## Issues Fixed in This Review (2026-06-28)

### Critical / High Severity — Fixed

1. **Atomicity bug in conflict resolution** — `MealPlanningService.retargetEntries` saved independently inside a larger transaction, breaking atomicity. Partial state was committed even if the outer operation failed and rolled back. Fixed by removing the independent save; caller now owns the final save.

2. **Conflict resolver deleted recipes with matching sourceURL without checking ingredients** — Two genuinely different recipes sharing a title and sourceURL would be merged destructively. Fixed: always checks ingredient overlap (uses a lower 0.5 threshold with URL match vs 0.8 for title-only).

3. **Empty ingredient list treated as "safe to fold in"** — A recipe with no ingredients was automatically considered a duplicate, deleting in-progress recipes. Fixed: now only considers both-empty as a duplicate; one-empty is treated as not a duplicate.

4. **Rating changes not saved in RecipeDetailView** — Star rating mutations relied entirely on autosave and could be lost if the app was killed. Fixed: explicit `saveRecipeChange()` call added.

5. **Cook count not persisted on CookingModeView finish** — "Mark as Cooked & Close" set properties but never saved before dismissing. Fixed: explicit save before dismiss.

6. **ShoppingListView context menu delete skipped save** — The only delete path that didn't call `saveChanges()`. Fixed.

7. **SettingsView API key confirmation appeared in wrong card** — Save/remove messages went to `exportMessage` which displayed in the data card, not the AI card. Fixed with dedicated `apiKeyMessage` state shown in the AI parsing card.

8. **IngredientLineParser failed on ranges and no-space unicode fractions** — "2-3 cups" produced amount 0, "1½ cups" produced amount 0. Both are extremely common recipe notations. Fixed: ranges now average; unicode fractions normalized before parsing.

### Security — Fixed

9. **`bundledAnthropicAPIKey` field removed** — A tracked constant inviting API key leaks. Removed entirely; app relies on Keychain, Info.plist, and environment variables only.

10. **Analytics logs switched from `.public` to `.private`** — Event lines including metadata were visible in system-wide console logs without redaction.

11. **Notification authorization denial now tracked** — Previously silently ignored; now surfaces `isNotificationDenied` state for UI to act on.

12. **Path traversal in `extract_recipe_keeper.py` image collector** — Crafted `src` attributes could escape the source directory. Fixed with `.resolve()` + prefix check.

13. **Hardcoded personal file path removed from `extract_counter_cookbook.py`** — Replaced with `required=True` argument.

### Data Safety — Fixed

14. **PantryView.saveModelContext missing rollback on failure** — Shopping list could be left in inconsistent in-memory state. Fixed: rollback added on save failure.

15. **PantryItem.absorbStock didn't normalize units** — "cups" vs "cup" failed to merge. Fixed: uses `ShoppingListService.normalizeUnit`.

### Efficiency — Fixed

16. **ShoppingListService.mergeKey compiled regexes on every call** — Thousands of compilations per shopping list generation. Fixed: regexes now compiled once as static constants.

17. **SpotlightIndexingService duplicated attribute-building code** — Extracted shared `makeSearchableItem(for:)` method.

### Polish — Fixed

18. **RecipeDetailView used duplicate `surfaceCard()` instead of Theme.swift `rvCard()`** — Eliminated redundant local card function; all cards now use the shared primitive.

19. **Duplicate notes-empty check in notesCard** — Combined into a single conditional.

20. **AIParsedRecipe case-sensitive category/difficulty matching** — AI output like "Dinner" wouldn't match the enum. Fixed with `.lowercased()`.

21. **Database error alert persisted across launches** — UserDefaults key never cleared after displaying. Fixed.

22. **Hardcoded version "1.0.0"** — Now reads from Bundle.main.

## Remaining Known Issues (Not Fixed in This Review)

### High Priority

1. **OCR path skips multi-recipe splitting** — Scanned cookbooks always produce one recipe. Needs per-page OCR + splitting logic.

2. **Multi-recipe PDF imports saved without review** — All recipes inserted immediately with no per-recipe review step. Should defer insert or flag as pending review.

3. **Manual parser misclassifies long ingredient lines as steps** — Lines > 60 chars or ending with "." are reclassified. Needs smarter heuristics.

4. **AI truncation is silent** — Single recipe: 12,000 chars; batch: 3,000 chars. No warning to user when content is truncated.

5. **Corrupt-store recovery wipes library with no in-app restore** — Archives exist on disk but no UI to browse/restore them.

### Medium Priority

6. **MealPlan entries cannot navigate to recipe detail** — No tap-through from meal plan to RecipeDetailView.
7. **MealPlan entries cannot adjust servings after adding** — Forces delete-and-readd.
8. **PantryView has no inline delete affordance** — Context menu only; no swipe-to-delete.
9. **PantryView has no way to edit item quantities** — Only add-new or mark-out.
10. **Recipe picker has no empty search state** — Blank list when no recipes match.
11. **CookingModeView: no confirmation when closing with active timers** — Timers silently destroyed.
12. **Photo loading has no progress indicator** — Silent loading for large photos.
13. **Photo thumbnails use array offset as ForEach ID** — Can cause view recycling bugs on delete.
14. **RecipeDetailView decodes images from Data on every render** — No caching for full-size images.
15. **Two different fingerprint algorithms for dedupe** — Import uses title+ingredients; conflict resolver uses title+sourceURL.
16. **Recipe UUID not exported** — Re-import always creates duplicates.
17. **RecipeExportService photos/PDFs encoded inline as Base64** — Memory-intensive for large libraries.
18. **MealPlan denormalized recipeTitle never updated on recipe rename**.
19. **CookingModeView fixed font sizes violate Dynamic Type**.

### Low Priority

20. Multiple views duplicate `summaryPill`/`heroHeader` instead of using `RVMetricPill`/`RVHeroBanner`.
21. `RecipeListView` uses hardcoded corner radii instead of `RVDesign` tokens.
22. `RecipeShareView` does not use Theme.swift palette.
23. `RecipeListView.pantrySuggestions` runs O(n*m) on every body.
24. `pantryBackupFingerprint` expensive recalculation on every render.
25. Status messages in PantryView never auto-clear.
26. Various Python script edge cases (mixed-number recursion, no output path validation).
27. Shopping category substring matching can miscategorize (e.g., "watermelon" → beverages).
28. `RecipePhotoViewer` drag gesture conflicts with page swipe at 1x scale.
29. `RecipeListView` scroll indicators hidden, removing position feedback.
30. No certificate pinning on Anthropic API calls (standard for third-party APIs).

## Design Restraint

Do:

- Keep the warm culinary notebook identity.
- Use native SwiftUI controls and predictable iOS behavior.
- Prefer shared primitives: `RVHeroBanner`, `rvCard`, `RVSectionTitle`, `RVStatusBanner`, `RVMetricPill`.
- Make risky actions explain recovery before the tap.
- Keep first viewport useful.

Do not:

- Add decorative complexity to compensate for weak flow logic.
- Copy web component patterns into SwiftUI.
- Add hidden cleanup, hidden auto-repair, or background data mutation.
- Broaden parser changes unless the failing import layer is known.
- Treat a dismissed sheet as proof that data saved.

## Highest-Value Future Work

1. Add per-recipe review step for multi-recipe PDF imports before saving.
2. Add OCR-level multi-recipe splitting for scanned cookbooks.
3. Add MealPlanView navigation to RecipeDetailView and servings editing.
4. Add PantryView swipe-to-delete and quantity editing.
5. Add backup round-trip tests with old and current JSON fixtures.
6. Include recipe UUID in exports for idempotent re-import.
7. Split `RecipeListView` into list state/actions, hero/search/filter surfaces, and card rendering.
8. Profile image thumbnail generation on real device libraries with many photos.

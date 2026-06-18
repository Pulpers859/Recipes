# Recipe Vault App Review Findings

Last reviewed: 2026-06-18

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

## Weaknesses To Keep Fixing

1. Giant SwiftUI files
   - `RecipeListView`, `PantryView`, `ShoppingListView`, `SettingsView`, and `RecipeDetailView` are doing too much.
   - Split only when it removes state/persistence complexity, not for abstract cleanliness.

2. Inconsistent persistence discipline
   - Some flows save and roll back explicitly.
   - Others still rely on autosave or best-effort cleanup.
   - Rule: if a user sees success, the app should already have saved or shown an error.

3. Destructive action consistency
   - Delete flows must be backup-first and save-gated.
   - Spotlight indexing should update only after persistence succeeds.
   - Cleanup of meal-plan/shopping references should commit with the destructive action, not separately.

4. Import quality visibility
   - The app should keep adding cues that help a user decide whether an imported recipe is trustworthy.
   - Avoid hiding parser uncertainty behind cheerful success language.

5. Test coverage is useful but still narrow
   - Parser and shopping heuristics have tests.
   - More coverage is needed around backup import/export compatibility, destructive cleanup, and recipe-list routing.

6. Visual polish is uneven
   - Import and Settings use shared UI primitives well.
   - Some older screens still have one-off hero/card treatments.
   - Do not chase a full redesign until stability and state handling are consistent.

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

1. Add UI tests or lightweight integration tests for opening the first recipe, switching sort orders, and opening pantry suggestion cards.
2. Add backup round-trip tests with old and current JSON fixtures.
3. Split `RecipeListView` into list state/actions, hero/search/filter surfaces, and card rendering.
4. Add a visible import quality checklist before saving imported recipes.
5. Give destructive actions a shared helper for backup, save, rollback, analytics, and user messaging.
6. Review URL import SSRF/host filtering periodically before expanding scraper capability.
7. Profile image thumbnail generation on real device libraries with many photos.


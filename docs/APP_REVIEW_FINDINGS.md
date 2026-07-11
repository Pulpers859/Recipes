# Recipe Vault App Review Findings

Last reviewed: 2026-07-11 (second full-app audit; June findings below preserved for history)

## Second-Pass Audit (2026-07-11)

Four parallel audit lanes (data safety, import/parsing, SwiftUI flows/UX, security/config) re-swept the app after the June fixes. The June fixes held up almost everywhere; this pass found a new layer of silent-wrong-content and trust failures underneath them. Parser behavior was verified by actually executing `IngredientLineParser`, `JSONPayloadExtractor`, and `URLSafetyValidator` on a Linux Swift toolchain (all pre-existing tests plus 8 new regression tests pass).

### High Severity — Fixed

41. **Ingredient parser summed all leading numbers** — "1 400g can chopped tomatoes" parsed as amount **401 g**; "1 28-oz can San Marzano…" as **29**; "2 8-inch tortillas" as **10**. This poisoned the primary URL import path (JSON-LD routes every ingredient through this parser) and propagated into serving scaling and shopping lists. The amount pattern now matches a single quantity token (mixed numbers like "1 1/2" still sum; size qualifiers stay in the name). Also fixed: en/em-dash ranges ("¼–½ tsp"), comma decimals ("1,5 kg"), thousands separators ("1,500 g"), and missing units (pint/quart/gallon/dash/sprig/stalk).

42. **In-flight imports survived Cancel/dismissal and inserted unreviewed recipes** — a slow PDF OCR or URL scrape finished minutes after the user cancelled, silently inserting an unreviewed recipe with no review sheet. Import tasks are now held in state, cancelled on Cancel/onDisappear, and check for cancellation before inserting.

43. **Any selectable text in a PDF disabled OCR for the whole document** — a scanned cookbook with a digital cover page imported the cover text as "the recipe". OCR is now decided per page (pages with under 40 chars of selectable text get OCR'd).

44. **Pantry "Clear All" deleted everything even when its promised recovery snapshot failed to write** — and then overwrote the rolling backup with an empty pantry, destroying both recovery paths. Now aborts with nothing deleted, matching Delete All Recipes.

45. **"Resolve Duplicate Recipes" deleted recipes with no confirmation and no backup** — the only destructive path without either. Now confirms first and writes the safety backup before touching anything.

46. **"Mark as Cooked & Close" swallowed save failures** (`try? save()` then dismiss) — the last remaining `try?`-save in the Views layer. Now surfaces the error with Stay/Close Anyway options.

47. **Batch-import preview could leak an excluded recipe into the library** — previewing a pending recipe in the editor and tapping Save inserted it immediately; excluding it afterwards left it in the library anyway. The preview editor now runs in a preview-only mode; only "Save N Recipes" inserts.

48. **Batch review sheet could be swiped away, discarding an entire cookbook parse** — now `interactiveDismissDisabled` with a confirmation on Cancel, and a failed batch save keeps the sheet open, rolls back the inserts, and shows the error (it used to dismiss looking successful, leaving zombie inserts for a later autosave).

### Medium Severity — Fixed

49. **Stock-to-pantry flows discarded quantities on unit conflicts** — both "Stock Checked Shopping Items" and the row-level stock action ignored `absorbStock`'s failure result and deleted the shopping item anyway ("5 lb flour" vanished against a "2 cup flour" pantry entry). Conflicting items now stay on the list with an explanation. `absorbStock` itself also no longer sums a bare count into a unit ("3" eggs + "2 lb" ≠ "5 lb").

50. **Shopping aggregation silently dropped amounts when units couldn't convert** — "2 cup flour" + "500 g flour" produced a list saying just "2 cup flour". Incompatible units now become separate line items, and pantry coverage is consumed without double-counting.

51. **Same-URL duplicates were never detected** — since fix #36 unified fingerprints, the resolver's similarity thresholds were dead code (group members always had identical ingredient sets), so the most common real duplicate — the same page re-imported with slightly different parsed ingredients — never grouped. A second pass now groups by title + source URL with the 0.5 overlap threshold. Spotlight de-indexing moved to after the successful save.

52. **JSON-LD stub recipes blocked the better AI fallback** — a Recipe node with zero ingredients and steps (carousel entries, single-string `recipeIngredient`, arrays with nulls, legacy `ingredients` key) "succeeded" and stopped strategy 2 from ever running. Ingredient parsing is now shape-tolerant and empty candidates are rejected so scanning/fallback continues.

53. **Fractional ISO durations parsed catastrophically** — `PT1.5H` read as 300 minutes (digits after the decimal matched `(\d+)H`). Now parses fractional components.

54. **Backup import hid unreadable records** — a 100-recipe backup with 40 corrupt records reported "Imported 60 recipes successfully!". The skip count is now reported, and `dateAdded`/`timesCooked` are decode-optional so older backups can't fail wholesale.

55. **Settings maintenance messages appeared in the wrong card with string-sniffed tone** — a failed delete-all rendered as a green success banner in the Data card. Maintenance now has its own banner with an explicit error flag; all Settings banners auto-clear (6 s success / 12 s error).

56. **AI response decoding was all-or-nothing** — a missing `summary` or `"amount": "1/2"` as a string discarded the entire (otherwise good) AI parse and silently fell back to the much weaker manual parser. Decoding is now field-tolerant, single bad ingredients/steps are skipped, and a salvaged-but-empty recipe is treated as a failure so fallback still triggers.

57. **SSRF: expanded IPv6 literals bypassed the blocklist** — `[0:0:0:0:0:0:0:1]` and `[0:0:0:0:0:ffff:127.0.0.1]` passed the string-prefix checks. IPv6 hosts are now parsed to numeric groups and classified by value (loopback, link-local, site-local, ULA, v4-mapped/compatible → dotted-quad rules). Verified against 33 bypass/legit cases.

58. **No response cap on page fetch** — a huge or malicious page could stream hundreds of MB into memory. Fetch is now streamed with a 10 MB ceiling, obvious non-page content types are refused, and the legacy-encoding fallback is Windows-1252 (real curly quotes instead of C1 control bytes).

59. **Info.plist API-key path removed** — the remaining structural key-leak vector (a key wired via build settings ships in plaintext in the IPA). Fallback is now env-var only (dev/simulator); devices use the Keychain.

60. **Editor Cancel discarded work without confirmation** — Cancel now confirms when there are unsaved edits (or the recipe is an unreviewed import). Meal-plan title sync moved before the explicit save so it rides the same transaction.

61. **Import re-entrancy** — PDF/photo/URL buttons are disabled while any parse is in flight (two concurrent parses raced shared parser state and orphaned the first recipe unreviewed).

62. **Cooking-mode contradictions** — the exit warning claimed timers would stop while notifications deliberately kept firing (copy now matches behavior); notification-denied state (tracked since June but never read) now shows a banner explaining timers can't alert a locked phone.

### Low Severity / Polish — Fixed

63. Recipes-tab performance: `filteredRecipes` computed once per render instead of four times; pantry suggestions cached in state instead of re-normalizing every ingredient of every recipe on every render; Settings recovery-card file I/O moved out of body; editor photo thumbnails use the downsampling cache instead of decoding full-res JPEGs per keystroke.
64. Stale import errors no longer greet the next import session; failed photo picks show a message instead of doing nothing (import + editor).
65. URL AI path now warns with the trimmed percentage (parity with the PDF path, fix #26); multi-chunk warnings append instead of clobbering each other.
66. `normalizedList` no longer deletes "("-prefixed ingredients like "(optional) chopped parsley" (only fully-parenthesized notes are dropped).
67. JSON-LD: `recipeCategory` array form recognized; keywords/cuisine entity-decoded.
68. Recipe IDs captured before `modelContext.delete` at every delete site (deleted-model property access is a known crash window); bulk Spotlight removal API added.
69. Pantry single-item delete now confirms (it has no recovery story — the Restore button only covers Clear All); accessibility labels added across pantry rows, meal plan entries, batch review, editor photos, list/detail toolbars, shopping quick-add; haptics on favorite toggle and shopping check-off; photo viewer pan no longer fights the page swipe at 1x; recipe list scroll indicators restored; selection cleared when filters change; recovery archives open read-only (a writable open could mutate the only copy of lost data).
70. `PrivacyInfo.xcprivacy` added (required-reason declarations for UserDefaults and file-timestamp APIs; no tracking, no collected data) — an App Store submission blocker.
71. AI step ordering: ties broken by original position (Swift's sort is not stable); step `order` decode-optional.

### Stress-Test + Self-Review Loop (same day, second pass)

After the fixes above, a real-ingredient-corpus stress run and an independent review of the fix diff itself found and fixed:

72. **"chicken broth" categorized into the meat aisle** — broth/stock/bouillon now always categorize as pantry (found by executing the categorizer against a 40-line real corpus).
73. **Regression in the new amount pattern: leading-dot decimals** — ".5 cup sugar" degraded to name "5 cup sugar". `\.\d+` added to the quantity token; regression test added (23 tests total, all executed and passing).
74. **Unit-scoped shopping lines now scope by unit family** — "500 g flour" and "1 kg flour" merge with each other instead of producing two lines; checked-state restore is limited to the base line so a new unit-variant can never appear pre-checked and get skipped at the store.
75. **Batch-save failure recovery no longer uses `rollback()`** — it deleted-then-retried the same inserted models through an API with undefined semantics and would also have discarded unrelated unsaved changes; the specific inserts are now removed individually so Save can be retried safely.
76. **Notification-denied banner timing** — the fixed 1 s delay missed the first-ever permission prompt; cooking mode now queries live notification settings per timer start (and hides the banner if permission was granted since).
77. **Page-trim advisory no longer renders as a red error** — the URL scraper gained a separate warning channel shown with warning tone after a successful import.
78. **A single unreadable page no longer fails an entire PDF import** — per-page OCR errors degrade to an empty page; whole-document failure still surfaces.
79. **"Resolved N conflict group(s)" no longer double-counts** a canonical that absorbed duplicates in both resolver passes; stale `absorbStock` doc comment corrected before someone "fixes" the code back to the old data-corrupting behavior.

Redundancy noted: `SampleRecipeService` is dead code (never referenced). Left in place in case it's intended for future onboarding; delete it if not.

### Verified Clean (no action needed)

- No secrets in source or any git history (pickaxe across sk-ant/ghp_/AKIA/BEGIN-key patterns).
- Keychain usage correct; analytics metadata contains no recipe content or PII; `.private` redaction in place.
- Python migration scripts free of injection/traversal (June fixes hold).
- Test target correctly wired in pbxproj; no ATS exceptions; app store recovery ladder (AppDataStack) sound.
- June audit fixes verified not regressed (spot-checked ~15 of 40); one reported "unreachable analytics code" finding was a false positive (returns are inside catch blocks).

### Known Remaining (deliberately not fixed)

- **DNS rebinding** is still not defended (documented accepted risk; needs socket-level resolved-address validation).
- **No certificate pinning** on Anthropic API calls (standard posture for third-party APIs).
- **Meal plans and shopping/pantry items are not part of recipe backups**; delete-all copy now says so, but a full-app backup format would be the real fix.
- **PDF chunk splitter heuristics** are still tuned for macro-style cookbooks; recipes whose ingredients and servings land on different pages can merge into a neighbor chunk. Batch review is the mitigation.
- **Whole-library JSON backup (photos included) is written synchronously on the main thread before every delete** — correct but can freeze multi-second on large photo-heavy libraries. Needs an async design with a blocking progress UI.
- `RecipeListView` is still ~1,000 lines and would benefit from decomposition (June "Highest-Value Future Work" #7).
- Batch AI recovery appends recovered recipes after successes (document order lost); `originalPDFData` attaches the whole cookbook to the first recipe only.
- Non-Gregorian calendar day labels in MealPlanView; week bucketing shifts if the user changes first-weekday (display-level).

---

# June 2026 Review (historical)

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

### Fixed in Follow-up (2026-06-28, second pass)

23. **OCR path now splits into recipe chunks** — Scanned cookbooks use per-page OCR and feed through the same splitting logic as selectable-text PDFs. Also adds memory safety via `autoreleasepool` and caps rendering at 150 DPI. Warns when PDFs exceed 20 pages.

24. **Multi-recipe PDF imports now go through batch review** — Recipes are NOT inserted into the database until the user reviews them. A new `BatchImportReviewView` shows each recipe with ingredient/step counts, lets the user exclude bad splits, preview each recipe in the editor, and save only the accepted ones.

25. **Manual parser no longer misclassifies long ingredients as steps** — Replaced the aggressive `line.count > 60 || line.hasSuffix(".")` heuristic with an `looksLikeInstruction` check that requires action verbs + sentence structure. Lines like "1 28-oz can San Marzano whole peeled tomatoes, drained and crushed" now stay as ingredients. Also improved title extraction to skip page numbers and boilerplate.

26. **AI truncation now warns the user** — When text exceeds the 12,000-char single-recipe limit, the user sees exactly what percentage was trimmed and a warning that content may be missing. Batch per-chunk limits increased from 3,000 to a dynamic budget (up to 8,000 per chunk, scaling with chunk count).

27. **Corrupt-store recovery UI added to Settings** — A new "Data Recovery" card in Settings lists archived databases from previous resets. Each archive can be exported as a JSON backup file via the standard share sheet, then re-imported through the normal import flow to restore recipes.

### Medium Priority — Fixed (2026-06-28, third pass)

28. **MealPlan entries now navigate to RecipeDetailView** — Tapping a meal plan entry opens the recipe detail. Entries for deleted recipes show dimmed text without a link.

29. **MealPlan entries now support inline servings adjustment** — Stepper on each entry replaces delete-and-readd workflow. Changes save immediately.

30. **PantryView now has visible delete button and quantity editing** — Each pantry row shows a trash button and a pencil button. Tapping pencil opens an alert to edit amount and unit inline.

31. **Recipe picker shows empty search state** — When no recipes match the search or the library is empty, a clear message appears instead of a blank list.

32. **CookingModeView confirms before closing with active timers** — Tapping Done while timers are running shows an alert explaining how many timers will be stopped.

33. **Photo loading shows progress indicator** — A spinner and "Loading photos…" text appear while photos are being imported; the picker is disabled during load.

34. **Photo ForEach now uses stable IDs** — Both RecipeEditorView and RecipeDetailView use `id: \.element` (Data's Hashable conformance) instead of array offset, preventing view recycling bugs on delete.

35. **RecipeDetailView caches decoded images** — Photos are decoded from Data once and stored in a dictionary, avoiding re-decode on every SwiftUI body evaluation.

36. **Fingerprint algorithms unified** — Conflict resolver now delegates to `RecipeLibraryMaintenance.fingerprint` (title + ingredients), eliminating the divergent title+sourceURL grouping. The sourceURL match is still used in `isConfidentDuplicate` to lower the overlap threshold.

37. **Recipe UUID included in exports** — `ExportableRecipe` now includes `recipeID`. Import skips recipes whose UUID already exists in the library, enabling idempotent re-import. Export version bumped to 3; older backups import fine (UUID is optional).

38. **Large JSON exports now warn about size** — Exports over 25 MB show the file size and a note that photos are embedded inline.

39. **MealPlan recipeTitle synced on recipe rename** — `MealPlanningService.syncTitle(for:modelContext:)` updates denormalized titles in all plans whenever a recipe is saved.

40. **CookingModeView uses Dynamic Type-compliant fonts** — Fixed-size navigation arrows and timer display replaced with `.system(.largeTitle)` text styles that scale with the user's accessibility settings.

## Remaining Known Issues (Not Fixed in This Review)

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

1. ~~Add per-recipe review step for multi-recipe PDF imports before saving.~~ Done (#24).
2. ~~Add OCR-level multi-recipe splitting for scanned cookbooks.~~ Done (#23).
3. ~~Add MealPlanView navigation to RecipeDetailView and servings editing.~~ Done (#28, #29).
4. ~~Add PantryView swipe-to-delete and quantity editing.~~ Done (#30).
5. Add backup round-trip tests with old and current JSON fixtures.
6. ~~Include recipe UUID in exports for idempotent re-import.~~ Done (#37).
7. Split `RecipeListView` into list state/actions, hero/search/filter surfaces, and card rendering.
8. Profile image thumbnail generation on real device libraries with many photos.

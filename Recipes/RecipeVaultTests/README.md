# RecipeVaultTests

Unit tests for the hand-tuned heuristics most likely to regress when tweaked:

- `ShoppingListServiceTests` — ingredient merge keys and unit conversion
- `IngredientLineParserTests` — free-text ingredient line parsing and locale-tolerant number parsing
- `JSONPayloadExtractorTests` — extracting JSON from AI responses (fences, prose, arrays)
- `MealPlanningServiceTests` — week semantics and shopping-list aggregation
- `BackupSnapshotTests` — safety-snapshot filenames, pruning, legacy migration
- `GoldenCorpusTests` — scored regression gate over `GoldenCorpus/` (see below)

## Golden import corpus

`GoldenCorpus/` holds document-level parsing cases: each folder has an
`input.txt` (raw recipe text; split cases delimit pages with `<<<PAGE>>>`
lines) and an `expected.json` with hand-authored ground truth.
`GoldenCorpusTests` runs `RecipeTextHeuristics` over every case and computes
aggregate ingredient F1, step F1, title accuracy, amount accuracy, and
split-boundary accuracy, failing if any drops below the committed baseline.
The baselines are the *measured* performance of the current heuristics — some
cases intentionally score below 1.0 to document known weaknesses (numbered and
bulleted ingredient lists, size-qualifier prefixes, traditional-cookbook
splitting). When you improve a heuristic, raise the affected baseline to just
under the new measurement in the same commit.

To add a real-world case: create a folder, paste the document text into
`input.txt` (for PDFs, the extracted page text; for photos, the OCR output),
write the ground truth into `expected.json`, then re-measure and raise the
baselines if the averages moved.

## Running on Windows (no Xcode)

`python tools/build_windows_test_harness.py --run` generates a SwiftPM package
from preprocessed copies of the pure-logic sources plus this whole test suite
(corpus included) and runs it with the local Swift for Windows toolchain in
about a second. Views and SwiftData persistence stay compile-unverified on
Windows — that is what the GitHub Actions macOS workflow is for.

## Wiring

These tests intentionally live outside `Recipes/Recipes`, because that folder is the app target's file-system-synchronized source root. The `RecipeVaultTests` unit-test target owns this folder. Keeping test files inside the app root or adding them to the app target causes Xcode to compile them into the app, where `XCTest` and `@testable import` are unavailable.

To run them from Xcode:

1. Open `Recipes.xcodeproj`.
2. Select the `RecipeVaultTests` scheme or press **Cmd+U**.
3. The tests use `@testable import Recipes`, matching the current app target/module name.

Do not move this folder under `Recipes/Recipes`, and do not add these files to the `Recipes` app target. That recreates the `unable to find module dependency: 'XCTest'` and stale `@testable import RecipeVault` build failures.

These tests are pure logic — no SwiftData container, no network, no UI — so
they run in milliseconds and are safe in CI.

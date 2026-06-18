# RecipeVaultTests

Unit tests for the hand-tuned heuristics most likely to regress when tweaked:

- `ShoppingListServiceTests` — ingredient merge keys and unit conversion
- `IngredientLineParserTests` — free-text ingredient line parsing and locale-tolerant number parsing
- `JSONPayloadExtractorTests` — extracting JSON from AI responses (fences, prose, arrays)
- `MealPlanningServiceTests` — week semantics and shopping-list aggregation

## Wiring (one-time, once the .xcodeproj exists)

The repo has no Xcode project file yet, so these tests are not yet runnable.
When you create the project:

1. File → New → Target → **Unit Testing Bundle**, name it `RecipeVaultTests`.
2. Add the files in this folder to that target (remove the template file Xcode generates).
3. The tests use `@testable import RecipeVault` — if your app target is named
   differently, update the import line in each file.
4. Run with **⌘U**.

These tests are pure logic — no SwiftData container, no network, no UI — so
they run in milliseconds and are safe in CI.

# RecipeVaultTests

Unit tests for the hand-tuned heuristics most likely to regress when tweaked:

- `ShoppingListServiceTests` — ingredient merge keys and unit conversion
- `IngredientLineParserTests` — free-text ingredient line parsing and locale-tolerant number parsing
- `JSONPayloadExtractorTests` — extracting JSON from AI responses (fences, prose, arrays)
- `MealPlanningServiceTests` — week semantics and shopping-list aggregation

## Wiring

These tests intentionally live outside `Recipes/Recipes`, because that folder is the app target's file-system-synchronized source root. The `RecipeVaultTests` unit-test target owns this folder. Keeping test files inside the app root or adding them to the app target causes Xcode to compile them into the app, where `XCTest` and `@testable import` are unavailable.

To run them from Xcode:

1. Open `Recipes.xcodeproj`.
2. Select the `RecipeVaultTests` scheme or press **Cmd+U**.
3. The tests use `@testable import Recipes`, matching the current app target/module name.

Do not move this folder under `Recipes/Recipes`, and do not add these files to the `Recipes` app target. That recreates the `unable to find module dependency: 'XCTest'` and stale `@testable import RecipeVault` build failures.

These tests are pure logic — no SwiftData container, no network, no UI — so
they run in milliseconds and are safe in CI.

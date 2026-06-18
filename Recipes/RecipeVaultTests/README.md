# RecipeVaultTests

Unit tests for the hand-tuned heuristics most likely to regress when tweaked:

- `ShoppingListServiceTests` — ingredient merge keys and unit conversion
- `IngredientLineParserTests` — free-text ingredient line parsing and locale-tolerant number parsing
- `JSONPayloadExtractorTests` — extracting JSON from AI responses (fences, prose, arrays)
- `MealPlanningServiceTests` — week semantics and shopping-list aggregation

## Wiring

These tests intentionally live outside `Recipes/Recipes`, because that folder is the app target's file-system-synchronized source root. Keeping test files inside the app root causes Xcode to compile them into the app target, where `XCTest` and `@testable import` are unavailable.

To run them from Xcode:

1. File → New → Target → **Unit Testing Bundle**, name it `RecipeVaultTests`.
2. Add the files in this folder to that target (remove the template file Xcode generates).
3. The tests use `@testable import Recipes`, matching the current app target/module name.
4. Run with **⌘U**.

These tests are pure logic — no SwiftData container, no network, no UI — so
they run in milliseconds and are safe in CI.

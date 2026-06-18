# Recipe Vault Agent Instructions

Recipe Vault is a small SwiftUI + SwiftData iOS app. Optimize for recipe correctness, safe user data handling, and small fixes that ship.

## Branch Law

- Work only on `main` tracking `origin/main`.
- Do not use `dev`, PR branches, feature branches, side branches, or temporary reconciliation branches unless Patrick explicitly asks for one in the current conversation.
- If you start on any non-main branch, stop before editing, switch to `main`, fetch, and fast-forward from `origin/main`.
- Commit completed tracked changes directly on `main` and push to `origin/main`.
- Do not create or recreate hooks that block direct commits to `main`.

## Required Start

1. Confirm the repo path is `C:\Dev\Recipes`.
2. Run `git fetch --all --prune`.
3. Ensure the active branch is `main`.
4. Ensure `main` tracks `origin/main`.
5. If clean, run `git pull --ff-only` before editing.

## Product Rules

- Start with the failing user flow, not a broad refactor.
- Prefer the smallest fix that protects recipe quality or data safety.
- When touching models or persistence, trace every read/write edge before editing.
- Preserve backup compatibility unless Patrick explicitly asks for a breaking migration.
- Prefer explicit errors and visible guardrails over silent fallback behavior.
- Be honest about what was validated and what could not be validated.

## Architecture Hotspots

- `Views/`: user flows, especially import, review, save, delete, pantry, meal plan, and shopping list flows.
- `Models/Recipe.swift`: core schema, ingredient normalization, display behavior, duplicate identity.
- `Service/RecipeParserService.swift` and `Service/URLRecipeScraperService.swift`: import correctness and URL safety.
- `Service/RecipeExportService.swift`, `PantryBackupService.swift`, and `RecipeConflictResolverService.swift`: backup/import/export/dedupe safety.
- `Service/AppDataStack.swift`, `AnalyticsService.swift`, `KeychainService.swift`, and `AppConfig.swift`: persistence, crash clues, secrets, app config.

## Avoid

- Working from `dev` or any side branch.
- PR-first workflows for normal work.
- Hidden auto-commits, hidden auto-pushes, or mutating hooks.
- Broad architecture churn without a specific product-quality payoff.
- Touching multiple import layers at once unless the bug clearly spans them.

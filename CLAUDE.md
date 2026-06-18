# Recipe Vault AI Guide

Recipe Vault is a small SwiftUI + SwiftData iOS app. Optimize for recipe correctness, safe user data handling, and small fixes that ship. Do not add AI process for its own sake.

## Repo Workflow

- Use `PROJECT_HANDOFF.md` for repo path, Git workflow, migration, and branch-discipline rules.
- Branch law: work only on `main` tracking `origin/main`. Do not use `dev`, PR branches, feature branches, side branches, or temporary reconciliation branches unless Patrick explicitly asks for one in the current conversation.
- Before edits, fetch and fast-forward `main` from `origin/main`; commit and push completed changes directly to `origin/main`.
- Keep `CLAUDE.md` focused on product architecture and bug-fix behavior; do not duplicate full repo bootstrap instructions here.

## Architecture

- `Views/`: user flows, especially `ImportView`, `RecipeEditorView`, `RecipeListView`, `SettingsView`, `PantryView`, `MealPlanView`, `ShoppingListView`
- `Models/Recipe.swift`: core schema, ingredient normalization, derived display behavior
- `Service/RecipeParserService.swift`: PDF/image OCR, AI/manual parsing, multi-recipe splitting
- `Service/URLRecipeScraperService.swift`: JSON-LD scrape, AI fallback, URL safety rules
- `Service/RecipeExportService.swift`, `PantryBackupService.swift`, `RecipeConflictResolverService.swift`: backup/import/export/dedupe safety
- `Service/MealPlanningService.swift`: week-scoped plan lookup, planned-servings aggregation, meal-plan entry cleanup on recipe delete
- `Service/IngredientLineParser.swift`: shared free-text ingredient parsing used by both URL and PDF fallbacks
- `Service/AppDataStack.swift`, `AnalyticsService.swift`, `KeychainService.swift`, `AppConfig.swift`: persistence, crash clues, secrets, app config
- `RecipeVaultTests/`: unit tests for the parsing heuristics (not yet runnable — needs a test target once the .xcodeproj exists)
- `extract_*.py`: migration/import utilities; treat them as compatibility surfaces, not throwaway scripts

## Real Failure Modes

1. Import succeeds but the saved recipe is wrong: bad ingredient parsing, bad step extraction, weak recipe splitting, or wrong scrape source.
2. Data-layer changes silently break backup/import/export, duplicate resolution, or old migrated data.
3. SwiftUI flow bugs lose edits or create confusing state: import -> review -> save, delete/merge flows, pantry/shopping interactions.
4. Destructive cleanup removes user data without a strong recovery story.
5. Config or secret handling leaks a real API key into source.

## Working Rules

- Start with the failing user flow, not a broad refactor.
- Prefer the smallest fix that protects recipe quality or data safety.
- When touching models or persistence, trace every read/write edge before editing.
- Preserve backup compatibility unless the user explicitly asks for a breaking migration.
- Prefer explicit errors and visible guardrails over silent fallback behavior.
- If local validation is limited, say exactly what remains unverified.

## Project Playbooks

- `@.claude/skills/import-path-triage.md`
- `@.claude/skills/recipe-data-safety.md`
- `@.claude/skills/swiftui-flow-regression.md`
- `@.claude/skills/backup-destructive-check.md`

## Avoid

- hidden auto-commits, auto-pushes, or mutating hooks
- `dev`, PR branches, feature branches, side branches, or hooks that block direct commits to `main`
- generic "improve the AI workflow" refactors
- broad architecture churn without a specific product-quality payoff
- touching multiple import layers at once unless the bug clearly spans them

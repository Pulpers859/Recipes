# Recipe Vault AI Guide

Recipe Vault is a small SwiftUI + SwiftData iOS app. Optimize for recipe correctness, safe user data handling, and small fixes that ship. Do not add AI process for its own sake.

## Repo Workflow

- Use `PROJECT_HANDOFF.md` for repo path, Git workflow, migration, and branch-discipline rules.
- Branch law: work only on `main` tracking `origin/main`. Do not use `dev`, PR branches, feature branches, side branches, or temporary reconciliation branches unless Patrick explicitly asks for one in the current conversation.
- For risky AI-agent experiments, use a detached sandbox worktree via `tools/New-AgentSandbox.ps1`; do not commit or push from the sandbox. See `docs/agent-sandbox-workflow.md`.
- Before edits, fetch and fast-forward `main` from `origin/main`; commit and push completed changes directly to `origin/main`.
- Keep `CLAUDE.md` focused on product architecture and bug-fix behavior; do not duplicate full repo bootstrap instructions here.

## Architecture

- `Views/`: user flows, especially `ImportView`, `RecipeEditorView`, `RecipeListView`, `SettingsView`, `PantryView`, `MealPlanView`, `ShoppingListView`
- `Models/Recipe.swift`: core schema, ingredient normalization, derived display behavior
- `Service/RecipeParserService.swift`: PDF/image OCR, AI/manual parsing, multi-recipe splitting
- `Service/URLRecipeScraperService.swift`: JSON-LD scrape, AI fallback, URL safety rules
- `Service/RecipeExportService.swift`, `PantryBackupService.swift`, `RecipeConflictResolverService.swift`: backup/import/export/dedupe safety
- `Service/MealPlanningService.swift`: week-scoped plan lookup, planned-servings aggregation, meal-plan entry cleanup on recipe delete
- `Service/ShareInboxEnvelope.swift`, `ShareInboxService.swift`: share-extension inbox (dormant until the extension target ships — see `Recipes/ShareExtensionStaging/README.md`)
- `Service/IngredientLineParser.swift`: shared free-text ingredient parsing used by both URL and PDF fallbacks
- `Service/AppDataStack.swift`, `AnalyticsService.swift`, `KeychainService.swift`, `AppConfig.swift`: persistence, crash clues, secrets, app config
- `Recipes/RecipeVaultTests/`: unit tests for parsing heuristics; keep this outside `Recipes/Recipes` unless a dedicated unit-test target owns it
- `tools/extract_*.py`: migration/import utilities (kept outside `Recipes/Recipes` so the file-synchronized app target can't bundle them); treat them as compatibility surfaces, not throwaway scripts

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
- For UI/UX redesigns or visual polish passes, read `docs/UI_UX_FOUNDATION.md` first and use shared primitives from `Extensions/Theme.swift`.
- For external UI/UX resources, use `docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`; adapt or reference resources rather than copying web patterns into SwiftUI.
- If local validation is limited, say exactly what remains unverified.

## Skill-First Workflow

- At the start of a fresh Recipe Vault session, use `@.claude/skills/recipe-handoff/SKILL.md` unless the task is already deep in one known file.
- For older work, mixed context, long logs, or handoff prep, use `@.claude/skills/recipe-context-compact/SKILL.md`.
- For broad reviews, release-readiness checks, or issues spanning multiple subsystems, use `@.claude/skills/recipe-parallel-audit/SKILL.md`.
- For import bugs, data safety, SwiftUI flow bugs, destructive-action changes, or UI/UX resource decisions, use the focused playbook below that matches the task.
- Keep this skill workflow lightweight; do not load every doc or skill when one focused playbook is enough.

## Project Playbooks

- `@.claude/skills/recipe-handoff/SKILL.md`
- `@.claude/skills/recipe-context-compact/SKILL.md`
- `@.claude/skills/recipe-parallel-audit/SKILL.md`
- `@.claude/skills/import-path-triage.md`
- `@.claude/skills/recipe-data-safety.md`
- `@.claude/skills/swiftui-flow-regression.md`
- `@.claude/skills/backup-destructive-check.md`
- `@.claude/skills/ui-ux-resource-eval.md`

## Avoid

- hidden auto-commits, auto-pushes, or mutating hooks
- `dev`, PR branches, feature branches, side branches, or hooks that block direct commits to `main`
- committing or pushing from detached agent sandboxes
- generic "improve the AI workflow" refactors
- broad architecture churn without a specific product-quality payoff
- touching multiple import layers at once unless the bug clearly spans them

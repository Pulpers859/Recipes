---
name: recipe-handoff
description: Orient Claude Code to the real Recipe Vault repo, source-of-truth paths, branch law, stale-copy risk, and product hotspots. Use at the start of a Recipe Vault task, when preparing a handoff, or when a session needs to rebuild the project's operating rules before editing.
---

# Recipe Vault Handoff

Use this skill to rebuild the minimum correct context for Recipe Vault before coding, reviewing, or handing work to another session.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Recipes`.
2. Confirm the active branch is `main`, tracking `origin/main`.
3. Run `git fetch --all --prune`; if the tree is clean, run `git pull --ff-only`.
4. Confirm the app source and project are present:
   - `Recipes/Recipes`
   - `Recipes/Recipes.xcodeproj`
   - `Recipes/RecipeVaultTests`
5. Read the smallest relevant project instruction file:
   - `CLAUDE.md` for normal product work
   - `PROJECT_HANDOFF.md` for repo bootstrap, branch law, or stale-copy questions
   - `AGENTS.md` when another agent or Codex is involved
6. Explicitly call out stale copies if they appear in the task context:
   - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Recipes`
7. State the current task's likely hotspots before editing.

## Product Risk Order

1. Recipe correctness
2. User data safety
3. Backup/import/export compatibility
4. Destructive-action guardrails
5. SwiftUI flow correctness
6. Maintainability

## Rules

- Work from `C:\Dev\Recipes`, not the OneDrive/Desktop copy, unless Patrick explicitly asks to inspect that copy.
- Do not use `dev`, feature branches, PR branches, or temporary reconciliation branches unless Patrick explicitly asks in the current conversation.
- Keep completed tracked changes on `main`, committed and pushed to `origin/main`, unless Patrick says not to.
- Prefer narrow root-cause fixes over broad rewrites.
- Say exactly what was validated and what remains unverified.
- Treat local secrets and ignored config as local-only by default.

## Good Handoff Shape

Include:

1. repo root
2. app source root and Xcode project path
3. current branch and sync state
4. stale-copy warning, if relevant
5. task-specific hotspots
6. validation performed and validation limits

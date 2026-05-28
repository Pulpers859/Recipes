---
argument-hint: [requested model or export change]
description: Safely change recipe schema, import or export behavior, or duplicate logic
---

Use @CLAUDE.md and @.claude/skills/recipe-data-safety.md.

Make or review this data-layer change: $ARGUMENTS

Before editing, trace the impact across:

- `Models/Recipe.swift`
- `Service/RecipeExportService.swift`
- `Views/SettingsView.swift`
- `Service/RecipeConflictResolverService.swift`
- `extract_counter_cookbook.py`
- `extract_recipe_keeper.py`

Prefer additive, backward-compatible changes. If compatibility breaks, call it out explicitly and keep the migration narrow.

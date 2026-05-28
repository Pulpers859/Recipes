# Recipe Data Safety

Use this playbook when changing `Recipe`, `Ingredient`, `RecipeStep`, backup/import/export code, duplicate resolution, or migration scripts.

## Focus

- Preserve user data and backward compatibility by default.
- Treat schema drift as a product risk, not just an implementation detail.

## Workflow

1. Trace every affected surface before editing:
   - `Models/Recipe.swift`
   - `Service/RecipeExportService.swift`
   - `Views/SettingsView.swift` import/export paths
   - `Service/RecipeConflictResolverService.swift`
   - `extract_*.py` if field shape or semantics change
2. Prefer additive changes and safe defaults.
3. Clamp or normalize values at boundaries, not deep inside unrelated UI.
4. If an existing fingerprint, export field, or default changes, call that out explicitly.
5. Keep destructive merges deterministic and understandable.

## Validation

- Check round-trip expectations: exported JSON should import cleanly into a sane `Recipe`.
- Check duplicate logic still preserves the best record.
- Check new defaults do not corrupt older backups or migrated data.

## Avoid

- silent schema breaks
- changing export/import format without naming the compatibility impact
- hiding data-loss risk behind "cleanup" wording

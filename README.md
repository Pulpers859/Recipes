# Recipe Vault

[![iOS](https://github.com/Pulpers859/Recipes/actions/workflows/ios.yml/badge.svg)](https://github.com/Pulpers859/Recipes/actions/workflows/ios.yml)

A SwiftUI + SwiftData iOS app for importing, organizing, and cooking from recipes — PDF/photo/URL import with AI-assisted parsing, pantry and shopping-list management, meal planning, and versioned JSON backups.

- App source: `Recipes/Recipes`
- Xcode project: `Recipes/Recipes.xcodeproj` (scheme `Recipes`)
- Unit tests: `Recipes/RecipeVaultTests` (pure logic, no UI — see `Recipes/RecipeVaultTests/README.md`)
- Contributor / agent guide: `CLAUDE.md`, `PROJECT_HANDOFF.md`

Every push to `main` builds the app and runs the unit-test suite on an iPhone simulator via GitHub Actions (`.github/workflows/ios.yml`). The badge above is the source of truth for whether `main` currently compiles on a Mac.

---
argument-hint: [optional area]
description: Run a lean pre-ship regression review on the highest-risk product flows
---

Use @CLAUDE.md plus:

- @.claude/skills/import-path-triage.md
- @.claude/skills/recipe-data-safety.md
- @.claude/skills/swiftui-flow-regression.md
- @.claude/skills/backup-destructive-check.md

Do a focused pre-ship regression pass for: $ARGUMENTS

Prioritize findings over praise. Check only high-ROI surfaces:

1. import quality and fallback behavior
2. editor save path and data normalization
3. backup, import, export, and duplicate resolution safety
4. destructive actions and recovery clarity

Return:

1. findings ordered by severity with file references
2. unverified areas
3. smallest recommended fixes

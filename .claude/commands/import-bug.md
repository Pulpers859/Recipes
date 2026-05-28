---
argument-hint: [symptom or artifact]
description: Diagnose PDF, photo, or URL import bugs without broad parser churn
---

Use @CLAUDE.md and @.claude/skills/import-path-triage.md.

Investigate this import problem: $ARGUMENTS

Work in this order:

1. Identify the exact failing path: PDF text extraction, PDF OCR, photo OCR, URL JSON-LD, URL AI fallback, or manual fallback.
2. Inspect the smallest useful intermediate artifact before editing.
3. Fix the narrowest layer responsible for the failure.
4. Validate the saved `Recipe` shape after the change.
5. Report root cause, changed files, validation, and residual risk.

Do not rewrite prompts and manual heuristics in the same pass unless the bug clearly spans both.

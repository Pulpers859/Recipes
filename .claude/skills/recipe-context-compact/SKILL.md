---
name: recipe-context-compact
description: Keep Claude Code context lean in Recipe Vault by rebuilding only the project state needed for the current task, choosing the right local playbook, and producing compact handoffs. Use when starting a fresh session, resuming older work, preparing a handoff, or when docs, logs, or diffs may balloon context.
---

# Recipe Vault Context Compact

Use this skill when the session needs enough context to be safe without rereading the whole repository.

## Workflow

1. Start with the current user request and root `CLAUDE.md`.
2. Use `recipe-handoff` for repo orientation when the session is fresh.
3. Choose one deeper playbook first:
   - `import-path-triage.md` for PDF, photo, URL, AI, OCR, or parser bugs
   - `recipe-data-safety.md` for model, backup, import/export, dedupe, or migration work
   - `swiftui-flow-regression.md` for view state, navigation, async, or save-flow bugs
   - `backup-destructive-check.md` for delete, merge, cleanup, backup, restore, or overwrite work
   - `ui-ux-resource-eval.md` for external UI/UX resource decisions
   - `recipe-parallel-audit` for broad reviews across multiple subsystems
4. Open only the files directly needed for the current task.
5. Before editing or ending, summarize state in 5-8 bullets:
   - what was checked
   - what was found
   - what is evidence-backed
   - what is inferred
   - what remains unverified
   - next best move

## Rules

- Do not load all handoff docs by default.
- Do not paste giant logs when a short issue summary will do.
- Prefer targeted searches, line-level reads, and compact recaps.
- Reuse prior conclusions only if branch state and relevant files have not changed.
- Keep Recipe Vault's product priorities ahead of process complexity.

## Common Uses

- "Refresh yourself on Recipe Vault before continuing."
- "Pick up where another session left off."
- "Summarize this work for the next agent."
- "Keep this review light on context."

---
name: recipe-parallel-audit
description: Break broad Recipe Vault investigations into bounded lanes, gather evidence without context sprawl, and finish with one integrated judgment. Use for app reviews, multi-flow regressions, architecture tradeoffs, release checks, or investigations spanning import, persistence, UI, and backup behavior.
---

# Recipe Vault Parallel Audit

Use this skill when one careful pass is not enough, but a repo-wide sweep would waste context.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Recipes`.
2. Restate the real decision or risk in one sentence.
3. Split the work into 2-4 bounded lanes. Good lane types include:
   - import/parsing correctness
   - model, persistence, backup, export, and dedupe safety
   - SwiftUI flow and navigation behavior
   - destructive actions and recovery clarity
   - UI/UX consistency and state coverage
   - tests, build setup, or release readiness
4. For each lane, define:
   - the narrow question
   - exact files or artifacts to inspect
   - evidence needed
   - stop condition
5. After each lane or wave, write a compact recap:
   - checked
   - found
   - uncertain
   - next best move
6. Synthesize only after the evidence passes are done.

## Review Priority

Findings should be ordered by:

1. data loss or destructive-action risk
2. recipe correctness or import trust failures
3. save, navigation, or SwiftUI flow bugs
4. backup/import/export compatibility regressions
5. security or secret-handling concerns
6. maintainability issues likely to compound

## Rules

- Keep one primary session responsible for synthesis and final judgment.
- Prefer small waves over broad file sweeps.
- Separate evidence-backed findings from informed inferences.
- Do not let visual polish distract from trust, persistence, and recovery behavior.
- If one focused pass is enough, keep the task simple.

## Common Uses

- "Do a broad review of Recipe Vault."
- "Check whether recent cleanup created data-safety risks."
- "Audit import, save, backup, and delete flows before release."
- "Prepare a compact handoff after a wide investigation."

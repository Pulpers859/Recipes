# External Agent Reconciliation

Use this when prior work by another AI agent, machine, terminal session, or conversation may have modified this repository.

## Standing Rule

Do not make sync claims, branch decisions, or new edits until outside-agent work has been reconciled against `origin/main`.

## Required Pass

1. Inspect the outside artifact when available: transcript, summary, screenshot, commit list, or claimed fix note.
2. Compare claimed work against:
   - current local files
   - local git history
   - current `origin/main`
3. Classify each claimed fix as:
   - `present`
   - `missing`
   - `partially landed`
   - `overwritten`
4. Only after that comparison decide whether to pull, patch missing work, or leave newer work intact.

## What To Tell Patrick

Say plainly which claimed fixes are still present, missing, partially landed, or overwritten. Do not say the repo is synced or fully assessed until this pass is complete whenever outside-agent work is part of the context.

# Agent Sandbox Workflow

Use a detached agent sandbox when an AI agent needs to explore risky or creative changes without mutating the main checkout.

## Default Rule

Normal work still happens on `main`. This repo remains main-only: do not create side branches, push sandbox commits, or open PRs unless Patrick explicitly asks for that workflow.

For risky experiments, create a detached worktree:

```powershell
.\tools\New-AgentSandbox.ps1 -Name import-safety
```

Review the sandbox diff, then integrate only selected changes back into the main checkout:

```powershell
git -C C:\Dev\.agent-sandboxes\Recipes\import-safety diff
```

Remove the sandbox when finished:

```powershell
.\tools\Remove-AgentSandbox.ps1 -NameOrPath import-safety
```

## Use A Sandbox For

- SwiftData, recipe import, backup/export, dedupe, or destructive-flow experiments.
- Multiple UI or product-flow variants.
- Broad audits where agents inspect independent risk areas.

## Skip A Sandbox For

- Tiny copy changes.
- Narrow bug fixes with an obvious file owner.
- Documentation-only edits that do not change operating rules.

The sandbox is for isolation, not final delivery. Final validation, commit, and push happen from `C:\Dev\Recipes` on `main`.

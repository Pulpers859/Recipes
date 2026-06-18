# Recipe Vault Project Handoff

## Project Identity
- Project name: `Recipe Vault`
- Project type: `iOS app with companion Python import utilities`
- Source-of-truth repo path: `C:\Dev\Recipes`
- Stale/old copies to ignore if applicable: `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Recipes`
- Primary target for normal work if multiple surfaces exist: `Main iOS app`
- GitHub intent/status: `remote attached and active`
- GitHub remote: `https://github.com/Pulpers859/Recipes.git`

## Repo State
- Stable branch: `main`
- Working branch: `main`
- Expected default branch for all normal work: `main`
- Branch law: `Work only on origin/main. Do not use dev, PR branches, feature branches, side branches, or temporary reconciliation branches for normal work unless Patrick explicitly asks for one in the current conversation. All investigation, edits, commits, and pushes should happen on main after syncing origin/main.`
- Sync-first rule: `Before normal work, fetch from the remote first. If the working tree is clean and the active branch tracks the expected upstream, pull with --ff-only before editing. If local changes exist, fetch and reconcile instead of blindly pulling.`
- Current observed local state: `C:\Dev\Recipes is the live Git repo. origin/main is the source-of-truth branch and current GitHub default. Any dev branch is historical/stale unless Patrick explicitly says otherwise. The Desktop/OneDrive copy should be treated as stale unless explicitly needed for recovery.`
- Git bootstrap status: `completed locally with repo config and aliases. Do not install hooks that block commits to main; this project intentionally commits and pushes directly on main.`

## If No Git Exists Yet
If `git rev-parse --is-inside-work-tree` fails in the real project root, the agent should help re-establish the repo using this standard:
1. confirm the real project root
2. migrate the project to `C:\Dev\Recipes` if the current location is still the OneDrive/Desktop copy
3. initialize local Git
4. keep the focused `.gitignore`
5. keep the `.gitattributes` file enforcing LF for code files
6. set repo-local config:
   - `core.autocrlf=false`
   - `core.eol=lf`
   - `pull.ff=only`
   - `fetch.prune=true`
7. add repo-local aliases:
   - `git st` -> `status -sb`
   - `git lg` -> `log --oneline --graph --decorate --all --date=short`
8. create the initial commit from the real app snapshot
9. run a secret scan and remove any live credentials from tracked files before connecting/pushing GitHub
10. connect the GitHub remote if needed
11. push `main`
12. set the local working branch to track `origin/main`
13. do not create `dev` or PR-style working branches unless Patrick explicitly asks
14. do not add a hook that blocks commits to `main`
15. create a dedicated PowerShell shortcut for this project

If the GitHub remote is unknown, the agent should finish local bootstrap first and only ask for the remote when push/setup is actually needed.

## PowerShell / Terminal Standard
- Do not globally pin every PowerShell session to this project.
- A dedicated shortcut should exist:
  - `Recipe Vault PowerShell`
- That shortcut should open directly in the source-of-truth repo path.
- Avoid fragile startup command strings if the path contains apostrophes or quoting hazards.

## How The Agent Should Operate
- Inspect before assuming.
- Work in the source-of-truth repo only.
- Sync from GitHub before normal work so the local repo is not stale.
- Fix root causes, not surface symptoms.
- Be honest and direct.
- Prefer architecture/data-flow fixes over hacks.
- Do not use brittle hardcoded special cases or band-aid fixes unless you explicitly explain why a deeper fix is not practical.
- Be proactive: inspect, diagnose, edit code directly, verify, and then audit nearby weaknesses.
- Do not stop at the first fix if adjacent code is obviously fragile.
- Tell me clearly what is evidence-backed, proven, inferred, or heuristic.
- If validation, linting, or review logic is too rigid and rejects good output, improve the rule when appropriate instead of dumbing down the product.
- Do not silently tolerate poor architecture if it is now a maintenance risk.
- Handle Git operations when appropriate.
- Keep normal work on `main`, tracking `origin/main`.
- Never move normal work to `dev`, PR branches, feature branches, side branches, or temporary branches unless Patrick explicitly requests that branch in the current conversation.
- Before editing on an existing repo, run `git fetch --all --prune`, switch to `main` if needed, verify it tracks `origin/main`, and pull with `--ff-only` when clean.
- Audit adjacent risks after making fixes.
- Run the checks that are realistically available in the current environment.
- Clearly distinguish evidence-backed logic from heuristics.
- Treat secrets as local-only by default: use tracked example files and ignored real config files whenever possible.

## Communication Style
- Warm, collaborative, calm, disciplined
- High-effort and thoughtful
- Short progress updates while working
- Clear reasoning, no fluff, no fake certainty
- If the agent misses something, it should own it directly

## Post-Fix Audit Standard
After making changes, the agent should do another harsh pass focused on:
- root-cause completeness
- adjacent fragility
- architecture quality
- validation or rule correctness
- progression / flow coherence where relevant
- silent failure risk
- wasted retries / wasted cost / wasted work
- maintainability

## What The User Wants By Default
- The user describes the problem in chat.
- The agent syncs `main` from `origin/main` first so local files are current before investigation or edits.
- The agent investigates directly.
- The agent makes code changes directly.
- The agent audits adjacent risks.
- The agent runs local checks where possible.
- The agent handles Git steps when appropriate.
- The user should not need to babysit PowerShell, Git, or GitHub for normal work.

## Before Starting Any New Task
The agent should confirm:
1. current repo path
2. current branch
3. repo status cleanliness
4. remote configuration
5. whether local `main` is behind `origin/main` and needs fetch/pull
6. whether stale copies exist elsewhere
7. whether the active folder is truly the source of truth

## Architecture / Product Notes
- Main product purpose: `Recipe Vault stores recipes, imports them from text/PDF/image/URL sources, and supports pantry, shopping list, meal planning, sharing, and backup flows.`
- Key modules or directories: `Views/`, `Models/`, `Service/`, `Extensions/`, `extract_*.py`, `CLAUDE.md`, `.claude/skills/`
- Known fragile areas: `recipe parsing/import correctness, multi-recipe splitting, backup/import/export compatibility, duplicate resolution, shopping/pantry data flow, destructive cleanup, and config/secret handling`
- Important evidence/product constraints: `recipe correctness and user data safety matter more than broad refactors or AI process churn`
- Runtime environments that matter: `iOS simulator, iOS device, and local Python script execution for import utilities`
- Current packaging gap to verify during bootstrap: `No .xcodeproj file is present in this Desktop snapshot, so the full app container should be verified when migrating to the real repo path.`

## Git / Release Notes
- Preferred everyday flow:
  - `git switch main`
  - `git st`
  - `git fetch --all --prune`
  - `git pull --ff-only`
  - `git diff`
  - `git add .`
  - `git commit -m "..."`
  - `git push origin main`
- There is no normal promotion flow from `dev` to `main`. `dev` is not the working branch for this project.

## Project-Specific Instructions For The Next Agent
```text
Project: Recipe Vault
Active repo path: C:\Dev\Recipes
Observed transitional copy: C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Recipes
GitHub remote: https://github.com/Pulpers859/Recipes.git
Stable branch: main
Working branch: main

Important:
- Treat C:\Dev\Recipes as the source-of-truth repo.
- Do not keep using the Desktop/OneDrive copy as the working repo unless explicitly asked to inspect a stale copy.
- origin/main is the only normal working branch. Do not use dev, PR branches, feature branches, or side branches unless Patrick explicitly asks in the current conversation.
- If you find yourself on dev or any non-main branch, stop before editing, switch to main, fetch, and fast-forward from origin/main.
- Do not recreate local hooks or workflow rules that block direct commits to main.
- The current tracked snapshot still does not include an .xcodeproj file, so verify the full app container if buildable Xcode project files are expected.
- Use the standard workflow: investigate directly, fix root causes, audit adjacent risks, run checks, and handle Git when appropriate.
- Before starting normal work, fetch from origin and sync main from origin/main first when the working tree is clean. If the repo is dirty, fetch and reconcile without switching away from main unless Patrick explicitly directs it.
- Prioritize recipe correctness, import safety, backup compatibility, and user data protection over broad refactors.
```

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
- Working branch: `dev`
- Expected default branch for normal work: `dev`
- Sync-first rule: `Before normal work, fetch from the remote first. If the working tree is clean and the active branch tracks the expected upstream, pull with --ff-only before editing. If local changes exist, fetch and reconcile instead of blindly pulling.`
- Current observed local state: `C:\Dev\Recipes is now the live Git repo, with main and dev pushed to origin. The Desktop/OneDrive copy should be treated as stale unless explicitly needed for recovery.`
- Git bootstrap status: `completed locally with repo config, aliases, and a local hook blocking direct commits to main`

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
12. create and push `dev`
13. add a local hook blocking direct commits to `main`
14. create a dedicated PowerShell shortcut for this project

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
- Keep normal work on `dev`, not `main`.
- Before editing on an existing repo, run a fetch and check ahead/behind state; if clean, pull the tracked branch with `--ff-only`.
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
- The agent syncs from the tracked remote branch first so local files are current before investigation or edits.
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
5. whether the local branch is behind the remote and needs fetch/pull
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
  - `git st`
  - `git diff`
  - `git add .`
  - `git commit -m "..."`
  - `git push`
- Preferred promotion flow from `dev` to `main`:
  - `git checkout main`
  - `git pull --ff-only`
  - `git merge --ff-only dev`
  - `git push`
  - `git checkout dev`

## Project-Specific Instructions For The Next Agent
```text
Project: Recipe Vault
Active repo path: C:\Dev\Recipes
Observed transitional copy: C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Recipes
GitHub remote: https://github.com/Pulpers859/Recipes.git
Stable branch: main
Working branch: dev

Important:
- Treat C:\Dev\Recipes as the source-of-truth repo.
- Do not keep using the Desktop/OneDrive copy as the working repo unless explicitly asked to inspect a stale copy.
- main and dev already exist on origin, and normal work should happen on dev.
- The current tracked snapshot still does not include an .xcodeproj file, so verify the full app container if buildable Xcode project files are expected.
- Use the standard workflow: investigate directly, fix root causes, audit adjacent risks, run checks, and handle Git when appropriate.
- Before starting normal work, fetch from origin and sync the active branch first when the working tree is clean. If the repo is dirty, fetch and reconcile instead of pulling blindly.
- Prioritize recipe correctness, import safety, backup compatibility, and user data protection over broad refactors.
```

# UI/UX Resource Evaluation

Use this skill when external UI/UX resources, component libraries, design systems, visual reference sites, or design-oriented agent skills might influence Recipe Vault.

## Required Reading

1. `docs/UI_UX_FOUNDATION.md`
2. `docs/AI_UI_UX_RESOURCE_EVALUATION_PLAYBOOK.md`

## Workflow

1. Inspect the app first.
2. Identify the user problem, platform constraints, and current screen maturity.
3. Classify the need: product flow, visual direction, component behavior, design-system structure, agent efficiency, or QA.
4. Decide for each outside resource: `Adopt`, `Adapt`, `Reference`, or `Skip`.
5. Use external resources as research input, not implementation authority.
6. Implement with native SwiftUI and the app's shared design primitives in `Extensions/Theme.swift`.
7. Validate empty, loading, error, disabled, selected, and destructive states.

## Rules

- Do not copy web components or translate Tailwind/React patterns literally into SwiftUI.
- Do not reshape Recipe Vault merely to justify a tool.
- Do not add permanent process unless it materially improves recipe correctness, data safety, usability, or design consistency.
- Preserve the app's warm culinary identity unless evidence shows it is the problem.

---
argument-hint: [screen, flow, or bug]
description: Debug a SwiftUI flow by tracing state, persistence, and side effects
---

Use @CLAUDE.md and @.claude/skills/swiftui-flow-regression.md.

Debug or improve this flow: $ARGUMENTS

Trace the path end-to-end:

1. entry view and state ownership
2. async work and main-actor boundaries
3. `modelContext` insert, delete, and save behavior
4. navigation, dismissal, and sheet state
5. success, empty, cancel, and error states

Prefer the smallest fix that preserves the current UX.

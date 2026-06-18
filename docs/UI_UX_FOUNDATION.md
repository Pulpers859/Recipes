# Recipe Vault UI/UX Foundation

Use this as the product-specific design brief for Recipe Vault. It adapts the Procedures UI/UX playbooks to this native iOS app.

## Product Frame

- Purpose: store, import, review, cook from, plan with, and back up personal recipes.
- Primary users: home cooks managing a personal recipe library, often in a kitchen or grocery context.
- Platform: native iOS with SwiftUI and SwiftData.
- Current identity: warm, culinary, paper-and-olive palette with serif headings and card-based workflow surfaces.
- Success standard: calm, trustworthy, polished, and legible. The app should feel like a premium personal kitchen notebook, not a generic CRUD database.

## Critical Workflows

1. Find and open a recipe quickly.
2. Import from PDF, photo, or URL, then review before trusting the result.
3. Edit recipe ingredients and steps without losing work.
4. Turn meal plans into shopping lists with pantry awareness.
5. Export, import, dedupe, and delete data with visible recovery guardrails.

## Design Principles

- Recipe correctness and data safety outrank visual novelty.
- Make the first viewport useful; do not turn app screens into marketing pages.
- Keep native iOS interaction behavior. External web components are inspiration only.
- Use warm paper surfaces, restrained shadows, olive accents, and serif headings consistently.
- Reserve destructive red for irreversible or high-risk actions.
- Use explicit loading, empty, error, disabled, selected, and destructive states.
- Prefer concise support copy near risky actions over hidden assumptions.
- Let controls look tappable: clear hit areas, consistent card padding, and visible disabled states.
- Avoid generic gradients, one-off colors, deeply nested cards, and decorative clutter.

## Component Rules

- `RVHeroBanner`: top-level screen summary with 0-2 meaningful metrics.
- `rvCard()`: primary content container for grouped controls and repeated sections.
- `RVSectionTitle`: card-level heading and optional support text.
- `RVStatusBanner`: user-visible information, warning, success, and danger messages.
- `RVMetricPill`: compact summary counts inside heroes.
- `RVPrimaryButtonLabel`: primary full-width action label.

Prefer these primitives before inventing new card, hero, status, or pill styles.

## Resource Adoption

- Builder.io Skills: reference for agent workflow ideas only.
- UI UX Pro Max: reference/adapt for visual vocabulary, not implementation authority.
- 21st.dev: reference only for selective visual inspiration; do not translate React/Tailwind components literally into SwiftUI.
- UX Components: adapt for component anatomy, states, and accessibility.
- Refero: reference for complete real-product flows, never for direct visual copying.

## UI Review Checklist

- Does the screen make the main action obvious within the first viewport?
- Are risky actions paired with confirmation and recovery language?
- Are empty, loading, error, disabled, and selected states present where relevant?
- Does the screen respect Dynamic Type and avoid cramped fixed-width controls?
- Are repeated surfaces using shared primitives instead of one-off styling?
- Does support copy improve decisions without explaining obvious UI?
- Could a user trust the result without knowing how the parser, backup, or sync works?

## When To Use External Research

Use external UI/UX resources only when deciding design direction, component behavior, flow structure, or redesign standards. Do not trigger external research for routine styling tweaks or narrow bug fixes.

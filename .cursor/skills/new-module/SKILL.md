---
name: new-module
description: Use when adding a new feature module to anysys. Drives the full SDLC pipeline (PO → UX → brainstorm → spec → plan → parallel build → QA → release-eng → tech-lead + code-reviewer) and scaffolds the four navigation areas (Modules / <name>, Settings / <name>, Maintenance / Modules toggle, Maintenance / Platform / Module Settings).
---

# Adding a New Feature Module

Triggers: "add a new module", "scaffold module X", "new feature module".

## The four navigation areas (from AGENTS.md)

Every module MUST have surfaces in all four:

1. **Modules / <name>** — `/:customer_id/modules/<module_key>` — customer-facing entries
2. **Settings / <name>** — `/:customer_id/settings/modules/<module_key>` — per-tenant config (admin)
3. **Maintenance / Modules** — `/:customer_id/maintenance/modules` — enable/disable toggle row for this module
4. **Maintenance / Platform / Module Settings** — `/:customer_id/maintenance/module_settings` — platform-wide config (owner only, customer 81721200)

## SDLC pipeline

Dispatch every Task / SDLC subagent with no `model` argument (or `model: inherit`) so they stay on Grok 4.6.

### Phase 0 — Product owner

Dispatch `anysys-product-owner` with the user's request. Get back a structured requirements brief: user stories (per role: owner / admin / member), acceptance criteria, edge cases, out-of-scope, open questions. Resolve open questions with the user before proceeding.

### Phase 1 — Brainstorm

Run `superpowers:brainstorming` using the PO brief as input. Settle: module key, display name, per-tenant config fields, platform-wide config fields, entry data model, audiences for each surface.

### Phase 2 — Spec

Write `docs/superpowers/specs/YYYY-MM-DD-<module>-design.md`.

### Phase 3 — UX design

Dispatch `anysys-ux-designer`. Get back `docs/superpowers/specs/YYYY-MM-DD-<module>-ux.md` with surface inventory, layout per surface, interaction flow, component reuse map. The UX doc is the contract the frontend developer builds against.

### Phase 4 — Plan

Run `superpowers:writing-plans`. Tasks tagged `independent: true` where lanes don't overlap:
- `T-model`: AR model + migration + plain-Ruby service + Reform contract → `anysys-backend-developer`
- `T-component-modules`: ViewComponents + Stimulus for `Modules / <name>` → `anysys-frontend-developer`
- `T-component-settings`: ViewComponents for `Settings / <name>` → `anysys-frontend-developer`
- `T-component-platform`: ViewComponents for `Maintenance / Platform / Module Settings` → `anysys-frontend-developer`
- `T-routes`: routes + controller skeletons + auth guards for all four surfaces → `anysys-security-engineer`
- `T-toggle`: register the module in the `Maintenance / Modules` toggle list (touches an existing registry; serial)
- `T-qa`: cross-tenant + auth-matrix request specs and a happy-path system spec → `anysys-qa-engineer`

### Phase 5 — Build

Use `superpowers:subagent-driven-development`. Dispatch `T-model`, `T-component-modules`, `T-component-settings`, `T-component-platform`, `T-routes` **in parallel** — their files don't overlap. Then `T-toggle` (serial). Then `T-qa` (parallelize where safe).

### Phase 6 — Verify

Dispatch `anysys-release-engineer` against all four surface URLs. Must return `overall: PASS`.

### Phase 7 — Review (parallel, both gates)

Dispatch `anysys-tech-lead` and `anysys-code-reviewer` **in parallel**. Both must return `overall: PASS`.

### Phase 8 — Hand back to user

Surface the four `## RETURN` blocks (release-engineer, tech-lead, code-reviewer, plus any non-PASS lane reports). User commits manually.

## Common pitfalls

- Forgetting one of the four surfaces. The tech-lead's `Module URL categorization` checklist will catch this; fix before handing back.
- Putting the platform-wide settings page outside customer `81721200`'s scope. The platform settings page is owner-only and only visible under that customer.
- Adding a per-vendor migration when the config blob would do. Per-tenant config goes in a JSON blob on a settings model, not typed columns.
- Skipping the PO phase on a "small" module. Even small modules benefit from explicit acceptance criteria — they make the QA engineer's specs targeted.

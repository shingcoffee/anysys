# Member Portal Visual Refresh — Design

**Date:** 2026-06-12
**Status:** Approved
**Scope:** Whole member portal (visual restyle), anchored on the existing member design system.

## Problem

The member portal already has a distinctive, well-built design language defined in
`app/assets/tailwind/application.css`:

- Cyan accent (`member-accent` `#0891b2`, hover `#0e7490`, active `#155e75`, plus `-subtle/-muted/-soft/-ink/-text`)
- Warm paper background (`member-paper` `#fbfaf6`), white elevated surfaces (`member-paper-elevated`)
- Elevated cards: `card-member-elevated` (16px radius, inset-highlight `--shadow-member-card`)
- `hero-member` radial gradient, `btn-member`, `input-member`, warm borders (`member-border-warm`)
- Smooth motion via `--ease-member` cubic-bezier with `--duration-fast/base/slow`

Dashboards, profiles, security, MFA, surfaces, and auth all use this system. **The one surface
that does NOT is the page-builder render** (`app/views/member/pages/show.html.erb`). It uses the
generic neutral tokens (`card`, `section-header`, `border-border-subtle`) and even pulls
`page_chrome_header_color` — the **per-page public theme color** — for its header. As a result it
looks foreign inside the cyan/warm member portal and is the least polished member surface.

## Goals

1. **Bring the page render into the member design language** so it feels native to the portal —
   the headline change.
2. **Portal-wide consistency + polish** so every member surface shares one cohesive, attractive
   visual system.

## Non-Goals / Constraints

- **Portal-only polish:** the per-page theme must NOT drive the member *wrapper/chrome*. The inner
  page-builder elements (form fields, layout blocks rendered by `PageContentGenerator` +
  `form_fields/*` components via `ThemeResolver`) keep their own per-page theme **untouched**. Only
  the surrounding member chrome changes.
- **No new visual identity.** We consolidate and elevate the *existing* member system; we do not
  introduce a new accent/typography/hero (rejected Approach ②).
- Tailwind only (no custom CSS framework), Stimulus only (no other JS framework), per AGENTS.md.
- All member surfaces remain responsive (mobile / tablet / desktop) per AGENTS.md.
- ViewComponent encapsulation preserved; styling stays in components/ERB.
- No changes to authorization, routes, models, controllers, or the page-builder element rendering
  pipeline. This is a presentation-layer refresh.

## Design

### Single source of truth

The member tokens already in `application.css` become canonical. **No member surface may use the
generic `card` / `section-header` / `border-border-subtle` / per-page `page_chrome_*` helpers.**
Everything routes through the member vocabulary: `card-member-elevated`, `hero-member`, `btn-member`,
`input-member`, `member-border-warm`, `member-accent*`, `ease-member` motion, member focus rings.

### Headline change — page render wrapper

`app/views/member/pages/show.html.erb` is restructured to match every other member page:

- A member-styled header (page name + description) using the member header treatment and member
  colors — **not** `page_chrome_header_color`.
- A `card-member-elevated` / flush `Member::PageSectionComponent` body containing the rendered
  `@content`.
- The empty state ("no content to render yet") uses the member empty-state treatment.

The inner `@content` (page-builder elements) renders exactly as today with its own per-page theme.
A logged-in member sees a page that feels native to the portal, while the configured element theme
is preserved.

### Portal-wide polish pass

Component by component, enforce consistency and add measured refinement (depth, spacing rhythm,
hover/focus micro-interactions, responsive behavior):

- Shell, top nav, user menu
- Hero card, status cards
- Page header / section / layout components
- Detail grid, index table, pagination, empty state
- Surfaces (index + detail)
- Profile, security, MFA, auth views

These already use the member system, so this is refinement and de-duplication, not a rewrite.

## Components Affected

ViewComponents under `app/components/member/` (15) and views under `app/views/member/` (10),
plus possibly small additions to the member `@theme`/component-class layer in
`app/assets/tailwind/application.css` if a shared utility is justified. No backend changes.

## Testing

- Component specs (`spec/components/member/*`) updated/added for any component whose public
  interface or rendered structure changes; assertions on member token classes, not brittle full-DOM.
- Honour the stale-test policy: when a spec fails because the markup intentionally changed, rewrite
  the spec rather than reverting production.
- Release engineer rebuilds assets (`rm -f public/assets/.manifest.json`), restarts with
  `SKIP_AUTH=1`, and smoke-tests representative member URLs (dashboard, a built page, profile,
  surfaces index).

## Execution Pipeline

anysys-ux-designer (refined member design spec + mockups via frontend-design plugin)
→ writing-plans → anysys-frontend-developer (apply across components/ERB)
→ anysys-qa-engineer (component specs)
→ anysys-release-engineer (rebuild + smoke-test)
→ parallel anysys-tech-lead + anysys-code-reviewer.

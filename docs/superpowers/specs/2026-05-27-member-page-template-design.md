# Member Page Template — Unified Width & Layout Design

**Status:** Approved (pending user review)
**Date:** 2026-05-27
**Branch:** `worktree-refactor-member-page-ui`

## Goal

Every member-facing page must render its content at exactly the same content width as the member home page (`/:cid/member`) — even when the page only contains a single word. This is achieved by funnelling every member view through a single unified page template with a fixed 12-column primary/aside split, and by reflowing the two outlier surfaces (`surfaces/index`, `surfaces/show`) onto that template.

## Problem

Today the member UI has a partial template (`Member::PageLayoutComponent`) that 5 pages already use, but the unification is incomplete:

1. **Outliers bypass the template.** `app/views/member/surfaces/index.html.erb` renders `Member::SurfaceIndexComponent` directly; `surfaces/show.html.erb` renders `Member::SurfaceDetailComponent` directly. Both bypass `PageLayoutComponent`, so their effective content width is whatever the inner component chooses — not guaranteed to match home.
2. **The template silently changes width when aside is omitted.** `PageLayoutComponent` collapses primary from `lg:col-span-8` to `lg:col-span-12` when no aside is given. The result: a page with hero+primary+aside (home) and a page with just primary render their primary content at *different* widths. A single-word page on a no-aside view spans the full 12 cols and visually looks wider/different than the home primary column.
3. **No enforcement.** Nothing prevents the next developer from rolling another `surfaces/`-style custom component.

The shell wrapper (`Member::ShellComponent`) already pins the outer container to `max-w-screen-2xl mx-auto px-4 sm:px-6 lg:px-8` for every member page — the outer width is not the problem. The problem is **inner content width consistency**.

## Reference state

- `app/views/layouts/member.html.erb:17` — body wraps every view in `Member::ShellComponent` with `container_width: width` (defaults to `:default` → `max-w-screen-2xl`).
- `app/components/member/shell_component.rb:8-11` — container modes: `default` (max-w-screen-2xl), `narrow` (max-w-3xl), `edge` (w-full).
- `app/components/member/page_layout_component.html.erb:6` — current grid: `grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8`.
- `app/views/member/dashboards/show.html.erb:4` — home page; reference layout (hero + primary + aside).

## Design

### Single mandatory template

`Member::PageLayoutComponent` becomes **the** page template — every member view must render through it. Its contract is widened and tightened:

**Slots**

- `with_hero` (optional, full-bleed inside the grid) — for home-style hero cards or page headers.
- `with_primary` (required) — main content column.
- `with_aside` (optional) — supplementary right-rail content.

**Grid contract (the unification rule)**

```erb
<div data-component="member-page-layout" class="space-y-8">
  <% if hero? %>
    <%= hero %>
  <% end %>

  <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
    <div class="lg:col-span-8 space-y-6 min-w-0"><%= primary %></div>

    <% if aside? %>
      <aside class="lg:col-span-4 space-y-5 min-w-0"><%= aside %></aside>
    <% else %>
      <div class="hidden lg:block lg:col-span-4" aria-hidden="true"></div>
    <% end %>
  </div>
</div>
```

Key rules:

1. **Primary is always `lg:col-span-8`.** Never re-spans to 12 cols.
2. **Aside column is always reserved.** When the page doesn't provide aside content, an empty placeholder `<div class="hidden lg:block lg:col-span-4" aria-hidden="true"></div>` holds the column at large breakpoints. The placeholder is `hidden` below `lg:` so on tablet/mobile it doesn't add a useless empty row.
3. **Hero renders ABOVE the grid (full container width).** It is a sibling of the grid wrapper, not a child of it. The parent `space-y-8` provides vertical rhythm between hero and the grid. This keeps the hero at the full `max-w-screen-2xl` container width (matching the pre-refactor working behaviour of the dashboard) and avoids needing a `lg:col-span-12` wrapper.
4. **No `container_width` override on pages.** All pages stay on the default `max-w-screen-2xl` shell. The `narrow` and `edge` modes remain available only for non-page surfaces (auth shell, etc.) — not for routed member pages.

### Responsive behaviour (mandatory for all member pages)

Below `lg:` (1024px) the grid collapses to a single column via `grid-cols-1`. Hero, primary, and aside (when present) stack vertically. The empty-aside placeholder is `hidden` below `lg:` so mobile/tablet users don't see a wasted slot.

| Breakpoint | Layout |
|---|---|
| `< sm` (mobile) | Single column. Shell `px-4`. Hero → primary → aside. |
| `sm`–`md` (tablet) | Single column. Shell `px-6`. Same vertical stack. |
| `lg`+ (desktop) | 12-col grid. Shell `px-8`. Hero full-bleed, then primary 8 + aside 4 (or 8 + empty placeholder). |
| `2xl` (≥1536) | Outer container caps at `max-w-screen-2xl` (1536px). Grid scales within. |

This satisfies the new "all pages must be responsive" project requirement (now in `AGENTS.md`).

### Outlier reflow

Two views currently bypass `PageLayoutComponent`:

- `app/views/member/surfaces/index.html.erb` — currently `render SurfaceIndexComponent.new(...)`. Reflowed to:
  ```erb
  <%= render Member::PageLayoutComponent.new do |c| %>
    <% c.with_hero { render Member::PageHeaderComponent.new(title: surface.title, …) } %>
    <% c.with_primary { render Member::SurfaceIndexComponent.new(...) } %>
  <% end %>
  ```
- `app/views/member/surfaces/show.html.erb` — same pattern, wraps `SurfaceDetailComponent` as primary.

The inner components (`SurfaceIndexComponent`, `SurfaceDetailComponent`) keep their internal markup but lose any outer width/container concerns; they now render *inside* the primary slot.

### Enforcement

The template is documented as mandatory in the component class comment. A spec at `spec/views/member/_template_compliance_spec.rb` walks every routed member view and asserts the top-level call is `render Member::PageLayoutComponent.new` (or a recognised wrapper that itself uses the template). Catches future bypasses at CI time.

## Components touched

| File | Change |
|---|---|
| `app/components/member/page_layout_component.rb` | Drop `primary_span_class` helper (no longer variable). |
| `app/components/member/page_layout_component.html.erb` | Always-8 primary + always-reserved aside (placeholder when empty). |
| `app/views/member/surfaces/index.html.erb` | Wrap in `PageLayoutComponent`. |
| `app/views/member/surfaces/show.html.erb` | Wrap in `PageLayoutComponent`. |
| `app/components/member/surface_index_component.*` | Strip any outer width/container classes; render as primary content. |
| `app/components/member/surface_detail_component.*` | Same. |
| `spec/components/member/page_layout_component_spec.rb` | Update to assert always-8 primary + placeholder when aside absent. |
| `spec/views/member/_template_compliance_spec.rb` | NEW — asserts every member view uses the template. |

No model, migration, controller, or route changes. No schema impact. No JS. Tailwind classes only.

## Out of scope

- Admin pages, public pages — this spec only governs member.
- Changing the outer container width (`max-w-screen-2xl`) — it stays.
- Auth shell (`AuthShellComponent`) which serves unauthenticated flows.
- Visual restyling of any individual surface or component beyond the grid contract.

## Risks

- **Surface visual regression.** Wrapping `SurfaceIndexComponent` / `SurfaceDetailComponent` in `PageLayoutComponent` may double-pad if they had their own outer container. Mitigation: code review confirms inner components don't add `max-w-*` / `mx-auto`; QA visual smoke.
- **Empty aside on info-light pages looks odd.** User chose the empty-placeholder approach (right column simply blank on desktop). Acceptable per explicit decision.
- **Spec drift.** The compliance spec must keep up with new member views. Mitigation: spec iterates the member route table dynamically rather than hard-coding view paths.

## Testing strategy

1. **Component spec** — `page_layout_component_spec.rb` exercises (a) primary-only renders 8 cols + aside placeholder, (b) primary + aside renders 8/4, (c) hero + primary + aside renders the full home layout, (d) responsive class set is present.
2. **Template compliance spec** — iterates `Rails.application.routes.routes` filtered to member paths, opens the matching view file, and asserts the top-level node is the page template.
3. **Request/system smoke** — `anysys-release-engineer` hits `/:cid/member`, `/:cid/member/profile`, `/:cid/member/security`, `/:cid/member/<surface_key>` with `SKIP_AUTH=1` and confirms 200 + presence of the grid wrapper.

## SDLC pipeline (Agent Teams)

1. **anysys-product-owner** — translates this spec into a brief with explicit user stories + acceptance criteria.
2. **anysys-ux-designer** — (frontend-design plugin) produces mocks of the 8/4 grid at lg / md / sm breakpoints, including empty-aside state.
3. **writing-plans** — converts spec + UX into the implementation plan.
4. **anysys-frontend-developer** (parallel slices) — (a) `PageLayoutComponent` changes, (b) surfaces reflow + inner component cleanup.
5. **anysys-qa-engineer** (parallel) — component spec + template compliance spec.
6. **anysys-release-engineer** — RSpec on touched files + asset rebuild + smoke.
7. **anysys-tech-lead** + **anysys-code-reviewer** — final diff review.

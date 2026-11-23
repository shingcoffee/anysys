# Design: Member Pages Layout Redesign

**Date:** 2026-05-26
**Scope:** Layout refactor — no controller, model, or business logic changes.

---

## Goals

1. Widen the member shell from `max-w-7xl` (1280 px) to `max-w-screen-2xl` (1536 px).
2. Adopt a uniform 12-column primary/aside layout across the five member-facing pages so they no longer feel optically narrower than the dashboard.
3. Remove **Profile** and **Security** from the top-nav (the user-menu dropdown already lists them).
4. Preserve all routes, controllers, and the `Member::Sources::Builtin` surfaces — only nav rendering changes.

## Non-goals

- No content changes to copy, fields, or flows.
- No removal of `:builtin_profile` / `:builtin_security` surface entries from `Builtin#surfaces` (they back the routes via `Member::Surfaces`).
- No changes to admin / auth / module surfaces.

---

## Architecture

### Container width

`Member::ShellComponent::CONTAINER_CLASSES[:default]` becomes `"max-w-screen-2xl mx-auto px-4 sm:px-6 lg:px-8"`. `top_nav_component.html.erb` outer div mirrors this. `:narrow` (forms) stays at `max-w-3xl`. `:edge` stays `w-full`.

### 12-column layout primitive

New `Member::PageLayoutComponent` (slots-based ViewComponent):

```
+---------------------------------------------------------------+
| hero       (full bleed across cols 1–12, optional)            |
+--------------------------------+------------------------------+
| primary    (cols 1–8)          | aside  (cols 9–12)           |
|                                |                              |
| <stack of PageSections>        | <stack of cards / quick acts>|
+--------------------------------+------------------------------+
```

Tailwind: outer `grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8`. `primary` is `lg:col-span-8`, `aside` is `lg:col-span-4`. Below `lg`, both stack to single-column. Hero, when present, is wrapped above the grid (full container width).

Slots:
- `with_hero` (optional) — renders before the grid
- `with_primary` (required, content area)
- `with_aside` (optional) — when omitted, primary expands to `lg:col-span-12`

This keeps every page's primary content at the *same* column width regardless of how much aside content it has.

### Page-by-page application

| Page | Hero | Primary (cols 1–8) | Aside (cols 9–12) |
|---|---|---|---|
| `dashboards/show` (Home) | HeroCardComponent (greeting) | "At a glance" 3-up StatusCardGrid + "Recent activity" PageSection | "Quick links" card (Update profile, Manage security, Sign out) + "Account" mini-card (initials + email) |
| `profiles/show` | — | PageHeader + Avatar/Identity card + DetailGrid (3-col) | "Account actions" (Edit profile, Sign out) + "Security at a glance" (2FA status + link) |
| `profiles/edit` | — | PageHeader + form PageSection (form spans full primary width; inputs cap at `max-w-md` *only inside narrow form rows*) | "Tip" card (e.g., "Email changes require re-confirmation") |
| `securities/show` | — | PageHeader + 3 stacked sections (Password / 2FA / Last sign-in) | "Account safety" tips card + "Recent activity" link → Home |
| `mfa/setup` | — | PageHeader + numbered Step 1 / Step 2 sections | "Need help?" card with recovery-link explainer |

### Nav cleanup

`Member::Navigation.items_for` filters out `:builtin_profile` and `:builtin_security` keys before returning. The surfaces themselves (and routes) remain. Comment the filter as "Hidden from the member top-nav because the user-menu dropdown already exposes them; they remain reachable via direct URL and via the dropdown."

Top-nav after change: **Home** + any module-enabled surfaces (Payments, etc.) + the user menu trigger on the right.

### Spec impact

- `spec/services/member/navigation_spec.rb` — first example asserts `to include(:builtin_home, :builtin_profile, :builtin_security)`. Update to assert it includes `:builtin_home` and excludes `:builtin_profile` and `:builtin_security`.
- `spec/services/member/sources/builtin_spec.rb` — unchanged (surfaces still exist; only the nav filters them).
- `spec/components/member/top_nav_component_spec.rb` — already passes `current_nav: :builtin_profile` for active-state testing; that path is still routable (link via dropdown) so the active-state test still has meaning, but we'll switch the example's `current_nav` to a key that's actually rendered (`:builtin_home`) to keep it semantically honest.
- `spec/components/member/shell_component_spec.rb` — assertion already at `max-w-7xl`; bump to `max-w-screen-2xl`.
- New: `spec/components/member/page_layout_component_spec.rb` — covers slot rendering, primary-only collapse, hero-optional behavior.

### Out of scope

- The four auth views (`mfa_setups`, `mfa_sessions`, `mfa_recoveries`, `registrations/edit`) are full-bleed `AuthShellComponent` and do not use the member shell. No changes.
- Admin pages, module-area surfaces — unchanged.
- Surface-source machinery (`SurfaceSource`, `Surfaces.for`) — unchanged.

---

## Validation

1. `bundle exec rspec spec/components/member spec/services/member` — green.
2. `bundle exec rspec spec/system/member spec/requests/member` — green.
3. Tailwind rebuild succeeds.
4. Smoke test: `/81721200/member`, `/81721200/member/profile`, `/81721200/member/profile/edit`, `/81721200/member/security`, `/81721200/member/security/mfa/setup` — all 200, top-nav contains "Home" only (plus modules), user-menu still shows Profile + Security.
5. Tech-lead + code-review pass.

---

## Parallelization

Three disjoint slices:

- **A — Width + nav filter + PageLayoutComponent scaffold** (single agent; sets the foundation)
- **B — Apply PageLayoutComponent to dashboards/show + profiles/{show,edit}** (parallel after A lands)
- **C — Apply PageLayoutComponent to securities/show + mfa/setup** (parallel after A lands)

Then a single QA pass and release-engineer smoke.

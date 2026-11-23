# Member Portal Visual Refresh — UX / Layout Spec

**Date:** 2026-06-12
**Status:** Ready for frontend developer
**Design doc:** `docs/superpowers/specs/2026-06-12-member-portal-visual-refresh-design.md`

---

## 1. Surface Inventory

| # | Surface | File(s) | Nav area | Priority |
|---|---------|---------|----------|----------|
| S1 | Page render wrapper | `app/views/member/pages/show.html.erb` | member | HEADLINE (broken) |
| S2 | Shell + top nav + mobile sheet | `ShellComponent`, `TopNavComponent` | member | Polish |
| S3 | User menu dropdown | `UserMenuComponent` | member | Polish |
| S4 | Dashboard | `dashboards/show.html.erb` + `HeroCardComponent` + `StatusCardComponent` | member | Polish |
| S5 | Page header | `PageHeaderComponent` | member | Polish |
| S6 | Page section (card wrapper) | `PageSectionComponent` | member | Polish |
| S7 | Page layout (grid) | `PageLayoutComponent` | member | Polish |
| S8 | Detail grid | `DetailGridComponent` | member | Polish |
| S9 | Index table | `IndexTableComponent` | member | Polish |
| S10 | Pagination | `PaginationComponent` | member | Polish |
| S11 | Empty state | `EmptyStateComponent` | member | Polish |
| S12 | Surfaces index | `SurfaceIndexComponent` + `surfaces/index.html.erb` | member | Polish |
| S13 | Surfaces detail | `SurfaceDetailComponent` + `surfaces/show.html.erb` | member | Polish |
| S14 | Profile show + edit | `profiles/show.html.erb`, `profiles/edit.html.erb` | member | Polish |
| S15 | Security | `securities/show.html.erb` | member | Polish |
| S16 | MFA setup | `mfa/setup.html.erb` | member | Polish |
| S17 | Auth shell | `AuthShellComponent` | member | Polish |

---

## 2. Layout Spec per Surface

### S1 — Page Render Wrapper (HEADLINE)

#### Current state (broken)

```erb
<div class="card overflow-hidden">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header <%= page_chrome_header_color(@page) %>">...
```

The outer wrapper uses the generic `card` class (indigo-tinted admin system), the border uses the admin `border-border-subtle`, and the heading color is driven by `page_chrome_header_color` — the per-page public theme color. None of these belong in the member portal.

#### Target design

The wrapper adopts three member building blocks already used by every other member surface:
1. `Member::PageHeaderComponent` for the title + description (member colors, member typography, no page_chrome dependency)
2. `Member::PageSectionComponent` with `density: :flush` for the card body containing `@content`
3. `Member::EmptyStateComponent` for the no-content state (replaces the inline `<p>` fallback)

No `page_chrome_header_color` call. No `card`. No `section-header`. No `border-border-subtle`.

The inner `@content` (page-builder rendered HTML) is rendered verbatim with no class changes — the member chrome sits outside it and does not restyle it.

#### ASCII mockup — mobile (< 640 px)

```
┌─────────────────────────────────────────┐
│  ← Back to Forms              [nav]     │  ← member top nav (unchanged)
├─────────────────────────────────────────┤
│                                         │
│  Page Name                              │  ← PageHeaderComponent
│  Page description text here             │    title: @page.name
│                                         │    subtitle: @page.description
│ ─────────────────────────────────────── │
│                                         │
│ ┌─────────────────────────────────────┐ │  ← PageSectionComponent
│ │                                     │ │    density: :flush
│ │   [[ inner @content renders here ]] │ │    card-member-elevated
│ │   [ page-builder theme untouched ]  │ │    rounded-2xl
│ │                                     │ │    border-member-border-warm
│ │                                     │ │    shadow-member-card
│ └─────────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

#### ASCII mockup — desktop (≥ 1024 px, using PageLayoutComponent grid)

```
┌────────────────────────────────────────────────────────────────┐
│  [logo]  Home  Forms  Profile              [User ▾]           │  ← top nav
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ← Back to Forms                                              │  ← eyebrow
│                                                                │
│  Page Name                                                     │  ← PageHeaderComponent
│  Page description text                                         │
│                                                                │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │                                                          │  │  ← PageSectionComponent :flush
│ │   [[ inner @content — page-builder theme preserved ]]    │  │
│ │                                                          │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

#### Empty state (no content yet)

```
┌────────────────────────────────────────────────────────────────┐
│  Page Name                                                     │
│  Page description text                                         │
│                                                                │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │                                                          │  │
│ │           [○ icon]                                       │  │
│ │      This page has no content yet.                       │  │
│ │      Content will appear here once published.            │  │
│ │                                                          │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

#### Specific class changes in `app/views/member/pages/show.html.erb`

| Element | Remove | Add |
|---------|--------|-----|
| Outer wrapper div | `class="card overflow-hidden"` | Replaced by `Member::PageHeaderComponent` + `Member::PageSectionComponent` |
| Header div | `px-6 py-4 border-b border-border-subtle` | Removed entirely |
| `<h2>` heading | `section-header <%= page_chrome_header_color(@page) %>` | Replaced by `PageHeaderComponent` title prop |
| Description `<p>` | `mt-1 text-body-sm` | Replaced by `PageHeaderComponent` subtitle prop |
| Content container | — | `Member::PageSectionComponent.new(density: :flush)` |
| Empty state `<p>` | Inline `<p class="text-body-sm text-text-muted">` | `Member::EmptyStateComponent` |

#### `content_for` additions required in the view

```
content_for :member_nav  → the surface key for this page (e.g. "forms")
content_for :title       → @page.name + " — ..."
```

The eyebrow back-link (Back to ...) should use the referring surface index path, passed from the controller as `@back_path`.

#### PageHeaderComponent props for S1

```ruby
Member::PageHeaderComponent.new(
  title:    @page.name,
  subtitle: @page.description.presence,
  eyebrow:  @back_path.present? ? { label: "Back to #{@back_label}", path: @back_path } : nil
)
```

#### EmptyStateComponent props for S1

```ruby
Member::EmptyStateComponent.new(
  icon:     :document,       # new icon variant, see S11 notes
  headline: "No content yet",
  body:     "This page has no content to render yet.",
  cta:      false
)
```

---

### S2 — Shell + Top Nav + Mobile Sheet

#### Current state

Generally good. Two inconsistencies:

1. **Nav background**: `bg-surface/85 supports-[backdrop-filter]:backdrop-blur-sm` — uses the admin canvas surface token, not a member token. Should be `bg-member-paper-elevated/90` to stay in the warm-paper family.
2. **Mobile sheet active link**: inline `hover:bg-member-accent-subtle/40` without a matching active class utility. The active state uses an inline string mix (`mobile_link_active_class`) whose definition was not read here — ensure it resolves to `bg-member-accent-subtle text-member-accent-ink font-medium` to match `nav-item-member-active`.
3. **Flash banner**: uses raw Tailwind classes inline in `ShellComponent`; fine but the `rounded-xl` should be `rounded-2xl` to match `card-member-elevated` for visual consistency at full container width on mobile.

#### Refined target

| Element | Current | Target |
|---------|---------|--------|
| Nav background | `bg-surface/85 backdrop-blur-sm` | `bg-member-paper-elevated/90 supports-[backdrop-filter]:backdrop-blur-sm` |
| Nav border | `border-b border-member-border-warm` | Keep as is |
| Mobile sheet active link | ad-hoc class string | `bg-member-accent-subtle text-member-accent-ink font-medium` |
| Flash banner radius | `rounded-xl` | `rounded-2xl` |
| Flash banner animation | none | add `motion-safe:animate-slide-down` on mount |

#### Responsive behavior (no change needed)

- `md:hidden` hamburger is correct.
- Desktop nav links use `nav-item-member` / `nav-item-member-active` — no change.
- Container `max-w-screen-2xl mx-auto px-4 sm:px-6 lg:px-8` — keep as is.

---

### S3 — User Menu Dropdown

#### Current state

Solid. One inconsistency: the dropdown panel uses `rounded-xl` (admin `--radius-xl`) instead of `rounded-2xl` (`--radius-2xl`), which conflicts with the `card-member-elevated` radius.

#### Refined target

| Element | Current | Target |
|---------|---------|--------|
| Panel container radius | `rounded-xl` | `rounded-2xl` |
| Panel shadow | `shadow-[var(--shadow-member-card)]` | Keep — correct |
| Panel ring | `ring-1 ring-member-border-warm` | Keep — correct |
| Menu item hover | `hover:bg-member-accent-subtle/50` | `hover:bg-member-accent-subtle/60 motion-safe:transition-colors motion-safe:duration-[var(--duration-fast)]` — add explicit transition |
| Sign-out hover | `hover:bg-danger-subtle hover:text-danger` | Keep — correct |

#### Focus behavior

Add `focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2` on the trigger button to replace the global indigo focus ring (defined in `@layer base :focus-visible`) with the member cyan ring.

---

### S4 — Dashboard

#### Current state

Structurally clean. Three specific issues:

1. **Status card grid**: `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3` is correct but the wrapping `<section>` has no card treatment — it's bare. This is intentional (the grid items are the cards), but the section tag needs `<section>` → unnamed block with no extra wrapper, not a `PageSectionComponent`.
2. **Recent activity list**: uses negative-margin hack `-mx-6 -mb-6` to bleed the list to card edges inside `PageSectionComponent`. This works but only when `PageSectionComponent` uses default density (which adds `p-6` via `card-member-elevated`'s `padding: 1.5rem`). The spec calls this out: if `density: :default` is used, this bleed is correct. Make explicit in the template comment.
3. **Aside — account avatar**: the 12×12 avatar (`h-12 w-12`) uses `rounded-2xl` but the user-menu avatar is `rounded-full`. Choose one shape. Use `rounded-full` for avatars everywhere (it is the universal identity convention).

#### Refined target

| Element | Current | Target |
|---------|---------|--------|
| Status card section wrapper | bare `<section>` | bare `<div>` (no card, intentional, add `data-region="status-cards"` attribute for test targeting) |
| Recent activity bleed | `-mx-6 -mb-6` | keep; add `<!-- density:default bleed -->` comment so the density coupling is explicit |
| Aside avatar radius | `rounded-2xl` | `rounded-full` — unify with user-menu avatar |
| Aside avatar size | `h-12 w-12` | keep |
| Aside avatar ring | `ring-1 ring-member-accent-muted/60` | keep |

#### ASCII mockup — dashboard desktop

```
┌─────────────────────────────────────────────────────────────────────┐
│  [logo] Home  Forms  Payments  Profile                [User ▾]     │ ← nav
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │ ← hero-member (radial gradient)
│  │  Good morning, Alex.                                        │   │   HeroCardComponent
│  │  Manage your account, payments, and security from here.     │   │
│  │                                                  [Active ●] │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │ ← status card grid (8-col)
│  │ [user icon]  │  │ [card icon]  │  │[shield icon] │             │   StatusCardComponent × 3
│  │ PROFILE      │  │ PAYMENTS     │  │ SECURITY     │             │   card-member-elevated each
│  │ Complete     │  │ View activity│  │ 2FA on       │             │
│  │ Update →     │  │ View all →   │  │ Manage →     │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                     │
│  ┌─────────────────────────────────────┐  ┌──────────────────────┐ │
│  │ Recent activity          (section) │  │ Quick links  (aside) │ │ ← PageSectionComponent each
│  │  Signed in  2 min ago  127.0.0.1  │  │ Update profile       │ │
│  │  [success]                          │  │ Manage security      │ │
│  │ ─────────────────────────────────  │  │ Sign out             │ │
│  │  Signed in  1 hr ago   127.0.0.1  │  ├──────────────────────┤ │
│  │  [success]                          │  │ Account      (aside) │ │
│  └─────────────────────────────────────┘  │ [○] Alex Zhang       │ │
│                                           │    alex@example.com  │ │
│                                           └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

#### ASCII mockup — dashboard mobile

```
┌─────────────────────────────┐
│ [≡] [logo] Customer Name    │ ← nav, hamburger visible
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ Good morning, Alex.     │ │ ← hero, full width
│ │ Manage your account...  │ │
│ │                  [Active]│ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │ ← status cards stack 1-col (sm:2-col)
│ │ [user] PROFILE Complete │ │
│ │ Update profile →        │ │
│ └─────────────────────────┘ │
│ ┌─────────────────────────┐ │
│ │[shield] SECURITY 2FA on │ │
│ │ Manage security →       │ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │ ← Recent activity
│ │ Recent activity         │ │
│ │  Signed in  2 min ago   │ │
│ │  127.0.0.1     [success]│ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │ ← aside (stacks below on mobile)
│ │ Quick links             │ │
│ │ Update profile          │ │
│ │ Manage security         │ │
│ │ Sign out                │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

### S5 — Page Header

#### Current state

Clean and already uses member tokens. One sizing issue: the title uses a raw `text-[1.875rem]` (30 px) / `sm:text-[2.125rem]` (34 px) that is not a token. This should resolve to the design token scale.

#### Refined target

| Element | Current | Target |
|---------|---------|--------|
| Title font-size | `text-[1.875rem] sm:text-[2.125rem]` | `text-3xl sm:text-4xl` (uses `--text-3xl: 1.5rem` / `--text-4xl: 1.875rem`) — slightly tightened; acceptable given the token scale. Alternatively keep custom values if the scale read-out looks too small on actual screens. Preferred: keep current custom values, but annotate with a comment `/* ~3xl/4xl — intentional above scale for display header */` so it is not accidentally normalized away. |
| Eyebrow chevron icon | inline SVG path | keep |
| Eyebrow color | `text-member-accent-text hover:underline` | add `motion-safe:transition-colors motion-safe:duration-[var(--duration-fast)]` |
| Action button | `variant_class(:primary)` resolves to `btn-member` | ensure `btn-member` is the only primary variant used — not `btn-primary` |
| Spacing | `mb-10` | keep |

---

### S6 — Page Section (Card Wrapper)

#### Current state

`section_classes` = `"card-member-elevated"` + density modifier. Correct. No changes needed to the class logic.

One ERB inconsistency: when `title.present?`, the inner header uses `border-b border-member-border-warm` (correct). But when there is no title the content starts at `card-member-elevated`'s intrinsic padding. This is correct behavior — no change.

#### Refinement

| Element | Current | Target |
|---------|---------|--------|
| Section header title | `text-heading` | keep — correct (`--text-xl` semibold) |
| Section header description | `text-body-sm` | keep |
| Section header bottom border | `mb-5 pb-4 border-b border-member-border-warm` | keep |
| Hover / focus | none on the section itself | none needed — sections are not interactive |
| density :flush | `p-0 overflow-hidden` | keep — used by tables |

---

### S7 — Page Layout (Grid)

#### Current state

The 12-column grid with `lg:col-span-8` primary + `lg:col-span-4` aside is good. One gap: when there is no aside, the hidden `lg:col-span-4` div is rendered with `aria-hidden="true"` — this is fine visually but the primary column should fill the available space in that case. The current implementation preserves the 8-col width even without an aside. Whether to go full-width when aside is absent is a product decision; the design doc does not mandate it. Keep 8-col primary as default.

#### Refinement

| Element | Current | Target |
|---------|---------|--------|
| Outer gap | `gap-6 lg:gap-8` | keep |
| Hero slot | direct slot yield | keep |
| Primary col | `lg:col-span-8` | keep |
| Aside col | `lg:col-span-4` | keep |
| `space-y-8` outer | keep | keep |

---

### S8 — Detail Grid

#### Current state

Uses raw `text-[11px] uppercase tracking-[0.06em] font-semibold text-text-tertiary` for the `<dt>` label. This should use the `text-label` utility class (which is `text-xs / font-semibold / uppercase / tracking-[0.04em] / text-text-tertiary`). The raw values are almost identical (`text-[11px]` vs `text-xs: 0.6875rem = 11px`). Consolidate to `text-label`.

| Element | Current | Target |
|---------|---------|--------|
| dt label | `text-[11px] uppercase tracking-[0.06em] font-semibold text-text-tertiary` | `text-label` |
| dd value | `value_class(row)` — component method | keep — component-controlled |
| Grid gap | `gap-x-8 gap-y-6` | keep |
| Responsive columns | `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3` | keep |

---

### S9 — Index Table

#### Current state

Correct member tokens throughout. Two issues:

1. The table is not wrapped in an element that enforces horizontal scroll on mobile — on narrow screens, wide tables cause body overflow. Add a `overflow-x-auto` wrapper div **inside** the `PageSectionComponent :flush` wrapper, surrounding the `<table>`.
2. The table header background uses `bg-member-paper` (warm off-white). On desktop this looks slightly different from the card background `bg-member-paper-elevated` (white). This contrast is intentional — it differentiates the header from rows. Keep it.

| Element | Current | Target |
|---------|---------|--------|
| Mobile scroll | none | wrap `<table>` in `<div class="overflow-x-auto">` |
| Header background | `bg-member-paper` | keep |
| Row hover | `hover:bg-member-accent-subtle/40` | keep + verify `motion-safe:transition-colors` is present (it is) |
| Row-link arrow transition | `motion-safe:group-hover:translate-x-0.5` | keep |
| Dividers | `divide-y divide-member-border-warm` | keep |

---

### S10 — Pagination

#### Current state

Uses member tokens correctly. One gap: no `aria-label` on the `<nav>` element. Add `aria-label="Pagination"`.

| Element | Current | Target |
|---------|---------|--------|
| Nav `aria-label` | missing | `aria-label="Pagination"` |
| Prev/Next buttons | `h-9 px-3 rounded-md` | keep (rounded-md = `--radius-md` = 8 px; intentionally tighter than cards) |
| Hover background | `hover:bg-member-accent-subtle` | add `motion-safe:transition-colors motion-safe:duration-[var(--duration-fast)]` |
| Count text | `text-text-tertiary tabular-nums` | keep |

---

### S11 — Empty State

#### Current state

Good. Uses `card-member-elevated py-14 px-6 text-center`. The icon slot hardcodes a `+` (plus) path, which is fine as a generic "add" affordance but is wrong when the empty state is informational (like S1's "no content yet" case).

The icon needs to be driven by the `icon` prop. Currently the component ERB has the SVG path hardcoded as a plus regardless of the `icon` value. The icon switcher exists in `StatusCardComponent` via `case icon` — apply the same pattern to `EmptyStateComponent`.

#### Additional icon variants needed

Add these icon variants to the component's `case icon` block:

| `icon` value | Path |
|---|---|
| `:plus` (existing default) | `M12 4v16m8-8H4` |
| `:document` | `M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z` |
| `:search` | `M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z` |
| `:inbox` | `M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4` |

| Element | Current | Target |
|---------|---------|--------|
| Icon ring | `ring-8 ring-member-accent-soft/60` | keep |
| Icon container | `rounded-full bg-member-accent-subtle text-member-accent-text` | keep |
| Headline | `text-[1.25rem] font-semibold tracking-[-0.015em] text-text-primary` | keep |
| Body | `text-body-sm max-w-sm mx-auto` | keep |
| CTA button | `btn-member mt-6 justify-center` | keep |
| SVG path | hardcoded plus | `case icon` switcher with `:plus`, `:document`, `:search`, `:inbox` |

---

### S12 — Surfaces Index

#### Current state

Delegates almost entirely to `SurfaceIndexComponent` which delegates to `PageHeaderComponent`, `EmptyStateComponent`, `PageSectionComponent :flush`, `IndexTableComponent`, and `PaginationComponent`. No inconsistencies visible in the composition.

Refinement: `SurfaceIndexComponent` currently has no `row_label` prop — the `IndexTableComponent` is rendered without it, meaning it falls back to whatever the component default is (not visible in the ERB read). Confirm the "View" row-link label is rendered correctly.

| Element | Current | Target |
|---------|---------|--------|
| Composition | clean | keep |
| `container_width` | not set in `surfaces/index.html.erb` | no change (default) |

---

### S13 — Surfaces Detail

#### Current state

`SurfaceDetailComponent` uses `PageHeaderComponent` + `space-y-6` + `PageSectionComponent` (title). Clean, uses member tokens.

One inconsistency: the list section items use `font-mono text-text-primary` for the right-hand value. This should use the `text-mono` utility class instead of bare `font-mono`.

| Element | Current | Target |
|---------|---------|--------|
| List item left | `text-body-sm text-text-secondary` | keep |
| List item right | `text-body-sm font-mono text-text-primary` | `text-body-sm text-mono` (the `text-mono` utility already sets mono font + `text-xs` + `tracking-0`) — but note this changes size to `text-xs` from `text-sm`. If full parity with `text-sm` is needed, use `font-mono tabular-nums text-text-primary` instead. Recommendation: `text-mono` for code/hash values, keep `text-body-sm` for human-readable values. The component method `render_right(item)` should select based on format. |

---

### S14 — Profile Show + Edit

#### Current state

Profile show: uses `rounded-2xl` on the avatar (`h-16 w-16`). As noted in S4 refinement, all avatars should use `rounded-full`.

Profile edit: uses `rounded-xl` on the validation error container (`rounded-xl bg-danger-subtle`). For consistency with `card-member-elevated`, bump to `rounded-2xl`.

| Surface | Element | Current | Target |
|---------|---------|---------|--------|
| Show | Avatar radius | `rounded-2xl` | `rounded-full` |
| Show | DetailGrid | uses `text-label` via cell_class | check component resolution (see S8) |
| Edit | Error container | `rounded-xl bg-danger-subtle ring-1 ring-danger/20 p-3.5` | `rounded-2xl bg-danger-subtle ring-1 ring-danger/20 p-4` |
| Edit | Input fields | `input-member` | keep |
| Edit | Submit button | `btn-member` | keep |
| Edit | Cancel | `btn btn-ghost` | keep (correct — destructive secondary action in admin system; acceptable here as a non-destructive cancel) |

---

### S15 — Security

#### Current state

Two inconsistencies:

1. The "Disable 2FA" `<summary>` button uses `btn btn-ghost text-danger` — this mixes the admin `btn`/`btn-ghost` base with a danger color. In the member portal the ghost button should use `btn-member` variant or a dedicated member ghost. For now keep `btn btn-ghost text-danger hover:bg-danger-subtle hover:text-danger` — it reads clearly as a destructive action and the semantic is correct even with the admin base class.
2. The "Confirm disable" submit uses `btn btn-danger` — admin button class. For member surface consistency prefer native HTML button with explicit `bg-danger text-white rounded-md px-4 py-2 text-sm font-medium` classes, but since `btn btn-danger` is the only danger button variant available and it renders identically, keep it. Flag as tech debt.

| Element | Current | Target |
|---------|---------|--------|
| MFA status icon radius | `rounded-xl` | keep (intentionally tighter than cards) |
| Disable 2FA summary | `btn btn-ghost text-danger` | keep (note tech debt: mixes admin base) |
| Confirm disable button | `btn btn-danger` | keep (note tech debt) |
| Password section `flex justify-end` | keep | keep |
| DetailGrid in Last sign-in section | uses component | keep |

---

### S16 — MFA Setup

#### Current state

Well-composed. Uses member tokens throughout. Three micro-issues:

1. Step number circles use `h-9 w-9 rounded-full` — these are member-accented and look good.
2. QR code container: `bg-white p-6 rounded-2xl ring-1 ring-member-border-warm shadow-[var(--shadow-member-card)]` — this is essentially a manual `card-member-elevated`. Replace with `card-member-elevated inline-block`.
3. Cancel button: `btn btn-ghost justify-center` — same admin/member mixing noted in S14. Keep for now.

| Element | Current | Target |
|---------|---------|--------|
| QR code wrapper | manual `bg-white p-6 rounded-2xl ring-1 ring-member-border-warm shadow-[...]` | `card-member-elevated inline-block` |
| OTP input | `input-otp` | keep |
| Form actions order | `flex-col-reverse sm:flex-row sm:justify-end` | keep (cancel first on mobile, right-aligned on desktop) |

---

### S17 — Auth Shell

#### Current state

Well-implemented. Uses `hero-member` for the brand pane. The form pane uses `bg-member-paper-elevated lg:rounded-l-3xl lg:shadow-[var(--shadow-member-card)]`. One inconsistency: `rounded-l-3xl` is a Tailwind JIT arbitrary value, not a CSS token. This should be `rounded-l-[2rem]` or just `rounded-l-3xl` is fine in Tailwind v4 — keep.

Mobile strip uses `bg-member-accent text-white` — correct.

No changes needed. Auth shell is the most polished member surface.

---

## 3. Interaction Flows

### Flow A — Member views a built page (S1)

```
Starting URL:  /:cid/member/pages/:page_id
User action:   Follow link from surfaces index or direct navigation
Outcome:       Page render wrapper appears with member chrome; inner form content rendered
Next URL:      (stays on same URL)

Failure flows:
  @content blank  → EmptyStateComponent ("No content yet") shown inside PageSectionComponent
  @page not found → Rails 404 / redirect to surfaces index (controller concern, not UX)
```

### Flow B — User opens user menu

```
Starting URL:  any member page
User action:   Click "[User ▾]" button
Outcome:       Dropdown panel slides down (motion-safe:animate-fade-in)
                Panel contains: name, email, Your profile link, Security link, Sign out
User action:   Click outside or press Escape
Outcome:       Panel closes (user-menu Stimulus controller toggle)
```

### Flow C — Mobile nav

```
Starting URL:  any member page (mobile viewport < 768 px)
User action:   Click hamburger icon
Outcome:       Mobile sheet expands below nav bar with transition-duration-[var(--duration-base)]
User action:   Click a nav item
Outcome:       Navigation + sheet closes
User action:   Click hamburger again
Outcome:       Sheet collapses
```

### Flow D — Profile edit

```
Starting URL:  /:cid/member/profile
User action:   Click "Edit profile" (btn-member)
Next URL:      /:cid/member/profile/edit
User action:   Update first name, last name, or email → submit
Happy path:    Redirect to /:cid/member/profile + flash notice
Error path:    Re-render edit form with rounded-2xl error container, errors listed
Cancel:        Link back to /:cid/member/profile (btn btn-ghost)
```

### Flow E — MFA setup

```
Starting URL:  /:cid/member/security
User action:   Click "Set up 2FA"
Next URL:      /:cid/member/security/mfa/setup
User action:   Scan QR code, enter 6-digit OTP in input-otp field
Happy path:    POST → redirect to /:cid/member/security + flash notice "2FA enabled"
Error path:    Re-render with invalid code message
Cancel:        Link back to security page (btn btn-ghost)
```

---

## 4. Component Reuse Map

| Surface | Existing component(s) reused | New component(s) needed | Notes |
|---------|------------------------------|------------------------|-------|
| S1 page render | `Member::PageHeaderComponent`, `Member::PageSectionComponent`, `Member::EmptyStateComponent` | None | View file refactored, no new component |
| S2 shell | `Member::ShellComponent`, `Member::TopNavComponent` | None | Class token swap only |
| S3 user menu | `Member::UserMenuComponent` | None | `rounded-xl` → `rounded-2xl`, add transition |
| S4 dashboard | `Member::PageLayoutComponent`, `Member::HeroCardComponent`, `Member::StatusCardComponent`, `Member::PageSectionComponent` | None | Avatar radius fix |
| S5 page header | `Member::PageHeaderComponent` | None | Comment on custom font-size |
| S6 page section | `Member::PageSectionComponent` | None | No change |
| S7 page layout | `Member::PageLayoutComponent` | None | No change |
| S8 detail grid | `Member::DetailGridComponent` | None | `text-label` consolidation |
| S9 index table | `Member::IndexTableComponent` | None | Add `overflow-x-auto` wrapper |
| S10 pagination | `Member::PaginationComponent` | None | Add `aria-label` |
| S11 empty state | `Member::EmptyStateComponent` | None | Add icon variants to `case icon` |
| S12 surfaces index | `Member::SurfaceIndexComponent` | None | No change |
| S13 surfaces detail | `Member::SurfaceDetailComponent` | None | `font-mono` → `text-mono` for code values |
| S14 profile | `Member::PageHeaderComponent`, `Member::PageSectionComponent`, `Member::DetailGridComponent` | None | Avatar + error container radius |
| S15 security | `Member::PageSectionComponent`, `Member::DetailGridComponent` | None | Keep admin btn classes for danger (tech debt) |
| S16 MFA setup | `Member::PageHeaderComponent`, `Member::PageSectionComponent` | None | QR code → `card-member-elevated` |
| S17 auth | `Member::AuthShellComponent` | None | No changes |

---

## 5. Tailwind & Stimulus Notes

### Token substitution rules (apply uniformly across all member surfaces)

| Anti-pattern (forbidden in member/) | Correct member token |
|--------------------------------------|----------------------|
| `card` | `card-member-elevated` |
| `card-elevated` | `card-member-elevated` |
| `section-header` | `text-heading` (inside member content) or `Member::PageHeaderComponent` |
| `border-border-subtle` | `border-member-border-warm` |
| `bg-surface` | `bg-member-paper-elevated` |
| `bg-canvas` | `bg-member-paper` |
| `page_chrome_header_color(...)` | Remove entirely; use `PageHeaderComponent` title |
| `btn-primary` | `btn-member` |
| `nav-item` / `nav-item-active` | `nav-item-member` / `nav-item-member-active` |
| `input-field` | `input-member` |
| `focus-visible:outline-accent` (global) | `focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2` (override on interactive member elements) |
| `text-accent` / `text-accent-text` | `text-member-accent-text` |
| `bg-accent-subtle` | `bg-member-accent-subtle` |
| `rounded-xl` on cards/panels | `rounded-2xl` |

### Focus ring override

The global `@layer base :focus-visible` rule applies the admin indigo ring (`--color-accent`). In the member portal, interactive elements (buttons, links, inputs, the user-menu trigger) should override this with the cyan member ring. Apply on individual interactive elements:

```
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2
```

Add to: `btn-member` component class definition in `application.css`, `nav-item-member` class, `input-member` focus state (already uses `box-shadow: 0 0 0 3px var(--color-member-accent-soft)` — keep as is, no ring needed).

For the user-menu trigger button, add the classes inline or via a Tailwind utility group.

### Motion conventions

All transitions in member surfaces use `motion-safe:` prefix + `var(--duration-fast/base/slow)` + `var(--ease-member)`.

- Hover color/background changes: `motion-safe:transition-colors motion-safe:duration-[var(--duration-fast)] motion-safe:ease-[var(--ease-member)]`
- Card lift on hover: `motion-safe:transition motion-safe:duration-[var(--duration-base)] motion-safe:ease-[var(--ease-member)] motion-safe:hover:-translate-y-0.5`
- Dropdown/sheet appear: `motion-safe:animate-fade-in` (already defined in `@layer utilities`)
- Do NOT use generic `transition-base` / `transition-fast` utilities (these use the admin easing, not `--ease-member`)

### Spacing rhythm

Use the 4-point scale: `gap-4`, `gap-5`, `gap-6`, `gap-8` (never gap-7). Padding within cards: card intrinsic padding from `card-member-elevated` is `p-6` (1.5rem). Do not add additional `p-*` on direct children unless the density modifier warrants it.

Section vertical separation: `space-y-6` within the primary column; `space-y-5` within the aside column; `space-y-8` at the page layout level.

### Stimulus controllers

No new Stimulus controllers are required for this visual refresh. The existing controllers handle all interactivity:

| Controller | Used by | Notes |
|---|---|---|
| `mobile-nav` | `TopNavComponent` | Handles hamburger toggle + sheet expand/collapse |
| `user-menu` | `UserMenuComponent` | Handles dropdown open/close; add keyboard `Escape` close if not present |
| `flash` | `ShellComponent` flash banners | Auto-dismiss — no change |

Verify that `user-menu` Stimulus controller handles:
- Click-outside dismissal (`data-action="click@window->user-menu#closeIfOutside"`)
- Keyboard Escape dismissal
- `aria-expanded` toggle on trigger button

If either of these is missing from the existing controller, add the missing action. This is the only Stimulus logic change in scope.

---

## 6. Consolidated Design Decisions Table

This table is the single authoritative reference the frontend developer applies uniformly. Any component or template that deviates from these values is a bug.

| Decision | Value | Token / class |
|---|---|---|
| **Card radius** | 16 px | `rounded-2xl` (`--radius-2xl: 1rem`) |
| **Card background** | white | `bg-member-paper-elevated` |
| **Card border** | warm off-white | `border border-member-border-warm` |
| **Card shadow** | inset highlight + soft drop | `shadow-[var(--shadow-member-card)]` |
| **Card hover lift** | -1 px translate | `motion-safe:hover:-translate-y-0.5 motion-safe:hover:shadow-md` |
| **Card padding (default)** | 1.5 rem | intrinsic from `card-member-elevated` (do not add extra) |
| **Page background** | warm paper | `bg-member-paper` |
| **Elevated surface background** | white | `bg-member-paper-elevated` |
| **Section divider** | warm border | `border-member-border-warm` |
| **Header style** | `PageHeaderComponent` | title: `text-[1.875rem] sm:text-[2.125rem]` font-semibold tracking-tight text-text-primary |
| **Section title style** | `text-heading` | `--text-xl` 18 px semibold -0.015em |
| **Label style** | `text-label` | `text-xs uppercase tracking-[0.04em] font-semibold text-text-tertiary` |
| **Body text** | `text-body-sm` | `text-sm` normal text-text-secondary |
| **Primary button** | member cyan | `btn-member` |
| **Ghost/cancel button** | neutral ghost | `btn btn-ghost` (admin base OK for cancel only) |
| **Danger button** | red gradient | `btn btn-danger` (admin base; tech debt) |
| **Input field** | member input | `input-member` |
| **OTP input** | member OTP | `input-otp` |
| **Nav items** | member cyan system | `nav-item-member` / `nav-item-member-active` |
| **Avatar shape** | circle | `rounded-full` |
| **Avatar background** | member accent | `bg-member-accent text-white` |
| **Badge** | system badges | `badge badge-{tone}` (tone: default, success, warning, danger) |
| **Accent color** | cyan-600 | `text-member-accent` / `bg-member-accent` / `#0891b2` |
| **Focus ring** | cyan 3 px | `focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2` |
| **Transition easing** | member cubic-bezier | `ease-[var(--ease-member)]` |
| **Transition duration (hover)** | 150 ms | `duration-[var(--duration-fast)]` |
| **Transition duration (card/motion)** | 220 ms | `duration-[var(--duration-base)]` |
| **Transition prefix** | prefers-reduced-motion safe | `motion-safe:transition-*` |
| **Spacing scale** | 4-point (4/5/6/8) | `gap-4`, `gap-5`, `gap-6`, `gap-8` |
| **Section vertical rhythm (primary)** | 24 px | `space-y-6` |
| **Section vertical rhythm (aside)** | 20 px | `space-y-5` |
| **Page layout vertical rhythm** | 32 px | `space-y-8` |
| **Table scroll on mobile** | horizontal overflow | `overflow-x-auto` wrapper |
| **Empty state icon container** | circle with ring | `rounded-full bg-member-accent-subtle text-member-accent-text ring-8 ring-member-accent-soft/60` |
| **No custom CSS** | Tailwind only | No `<style>` tags, no `.css` changes |
| **No JS frameworks** | Stimulus only | No `import` of external JS |

# Member PageLayoutComponent — Responsive Layout Mockups

**Status:** Ready for frontend implementation
**Date:** 2026-05-27
**Companion spec:** `docs/superpowers/specs/2026-05-27-member-page-template-design.md`
**Component target:** `app/components/member/page_layout_component.*`

---

## Overview

This document shows the visual layout of `Member::PageLayoutComponent` at three
breakpoints, for both layout variants (home-page case with hero+primary+aside, and the
single-column case where aside is empty). The grid contract — always-8 primary,
always-reserved 4-col aside — is the central invariant the mockups illustrate.

The outer container (`max-w-screen-2xl mx-auto px-4 sm:px-6 lg:px-8`) is owned by
`Member::ShellComponent` and is NOT part of `PageLayoutComponent`. Every mockup
shows the region inside that container.

---

## Breakpoint reference

| Token | Range | Shell padding | Grid behaviour |
|---|---|---|---|
| `sm` | < 768 px | `px-4` | 1-column stack |
| `md` | 768–1023 px | `px-6` | 1-column stack |
| `lg` | 1024–1535 px | `px-8` | 12-column grid |
| `2xl` | ≥ 1536 px | `px-8` | 12-column grid, outer container caps at 1536 px |

---

## 1. `lg`+ Desktop (≥ 1024 px)

### 1a. Home page case — Hero + Primary (cols 1–8) + Aside (cols 9–12)

This is the reference layout: `dashboards/show.html.erb` with all three slots filled.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  TOP NAV  (sticky, full-width inside max-w-screen-2xl, h-16)            │
│  [logo + customer name]  [Home | Profile | Security | …]  [user menu]   │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐  ← py-10 lg:py-14
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │  ← data-component="member-page-layout"
│  │  HERO  (lg:col-span-12, mb-8 / space-y-8)                      │   │    space-y-8
│  │  ┌────────────────────────────────────────────────────────────┐ │   │
│  │  │  hero-member  (accent gradient, rounded-2xl)          │ │   │
│  │  │  "Good morning, Jane."          [● Active]                 │ │   │
│  │  │  "Manage your account, payments, and security…"            │ │   │
│  │  └────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌───────────────────────────────────────┐  ┌───────────────────────┐  │  ← grid grid-cols-1 lg:grid-cols-12
│  │  PRIMARY  (lg:col-span-8, space-y-6)  │  │  ASIDE                │  │    gap-6 lg:gap-8
│  │                                       │  │  (lg:col-span-4,      │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐    │  │   space-y-5)          │  │
│  │  │ Status │ │ Status │ │ Status │    │  │                       │  │
│  │  │  card  │ │  card  │ │  card  │    │  │  ┌─────────────────┐  │  │
│  │  │Profile │ │Payment │ │Security│    │  │  │ Quick links     │  │  │
│  │  │Complete│ │View    │ │2FA on  │    │  │  │─────────────────│  │  │
│  │  └────────┘ └────────┘ └────────┘    │  │  │ Update profile  │  │  │
│  │  [grid grid-cols-1 sm:grid-cols-2    │  │  │ Manage security │  │  │
│  │   lg:grid-cols-3 gap-4]              │  │  │ Sign out        │  │  │
│  │                                       │  │  └─────────────────┘  │  │
│  │  ┌───────────────────────────────┐   │  │                       │  │
│  │  │ Recent activity               │   │  │  ┌─────────────────┐  │  │
│  │  │───────────────────────────────│   │  │  │ Account         │  │  │
│  │  │ Signed in  2 min ago · x.x.x  │   │  │  │─────────────────│  │  │
│  │  │ Signed in  1 day ago · y.y.y  │   │  │  │ [avatar] Jane D │  │  │
│  │  └───────────────────────────────┘   │  │  │ jane@example.com│  │  │
│  │                                       │  │  └─────────────────┘  │  │
│  └───────────────────────────────────────┘  └───────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Proportions at lg (1024 px):**
- Grid total width = container width minus shell px-8 on both sides.
- `lg:col-span-8` ≈ 66.7 % of grid width.
- `lg:col-span-4` ≈ 33.3 % of grid width.
- `gap-8` (32 px) gutter between primary and aside.

**Key Tailwind classes on the grid wrapper:**
```
grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8
```

**Hero wrapper:**
```
lg:col-span-12
```
(sits above the primary/aside row; the `space-y-8` on the parent provides vertical gap)

**Primary wrapper:**
```
lg:col-span-8 space-y-6 min-w-0
```

**Aside wrapper (when present):**
```
<aside class="lg:col-span-4 space-y-5 min-w-0">
```

---

### 1b. Single-word / no-aside pages — Primary (cols 1–8) + Empty placeholder (cols 9–12)

Examples: `profiles/show`, `securities/show`, `surfaces/index`, `surfaces/show`.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  TOP NAV  (identical to 1a)                                             │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐  ← py-10 lg:py-14
│                                                                         │
│  (no hero slot rendered — space-y-8 wrapper still present, no gap)     │
│                                                                         │
│  ┌───────────────────────────────────────┐  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌   │  ← grid grid-cols-1 lg:grid-cols-12
│  │  PRIMARY  (lg:col-span-8, space-y-6)  │  ╎  EMPTY PLACEHOLDER  ╎  │    gap-6 lg:gap-8
│  │                                       │  ╎  (lg:col-span-4)    ╎  │
│  │  ┌───────────────────────────────┐   │  ╎  hidden block        ╎  │
│  │  │ ← Back to <Surface>           │   │  ╎  aria-hidden="true"  ╎  │
│  │  │  Profile                [Edit]│   │  ╎                      ╎  │
│  │  │  "Your account information"   │   │  ╎  No visible content  ╎  │
│  │  └───────────────────────────────┘   │  ╎  No spacing chrome  ╎  │
│  │                                       │  ╎  Not in tab order   ╎  │
│  │  ┌───────────────────────────────┐   │  ╎                      ╎  │
│  │  │ [avatar JD]  Jane Doe         │   │  ╎  ← Invisible column ╎  │
│  │  │              jane@example.com │   │  ╎    reserves space    ╎  │
│  │  │ ─────────────────────────────  │   │  ╎    so primary width ╎  │
│  │  │ First name  │ Jane            │   │  ╎    = 8/12 in both   ╎  │
│  │  │ Last name   │ Doe             │   │  ╎    variants (1a+1b) ╎  │
│  │  │ Email       │ jane@…          │   │  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌   │
│  │  │ Member since│ Jan 1, 2025     │   │                          │
│  │  └───────────────────────────────┘   │                          │
│  └───────────────────────────────────────┘                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**The critical invariant:** the primary column in 1b occupies EXACTLY the same horizontal
space as in 1a. A user navigating Home → Profile will NOT see the text reflow or widen.
This is enforced by the empty placeholder:

```html
<div class="hidden lg:block lg:col-span-4" aria-hidden="true"></div>
```

- `hidden` — invisible below lg (avoids a wasted empty row on tablet/mobile).
- `lg:block` — becomes a block element at lg+ (holds the 4-col slot).
- `lg:col-span-4` — claims the column, keeping primary at 8/12.
- `aria-hidden="true"` — screen readers skip it.
- No padding, margin, background, or content inside.

**Profile-specific primary contents (for implementor reference):**

```
PageHeaderComponent(title: "Profile", subtitle: "…", actions: [Edit profile →])
PageSectionComponent (no title)
  [avatar badge]  "Jane Doe"  /  "jane@…"
  DetailGridComponent (rows: first_name / last_name / email / member_since)
```

---

## 2. `md` Tablet (768–1023 px)

Grid collapses to `grid-cols-1`. All slots stack vertically. Shell uses `px-6`.
The empty-aside placeholder is `hidden` (not rendered at this breakpoint).

### 2a. Home page case (hero + primary + aside all present)

```
┌──────────────────────────────────────────┐
│  TOP NAV  (h-16, px-6)                   │
│  [hamburger]  [logo/name]  [user menu]   │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐  ← py-10
│                                          │
│  ┌──────────────────────────────────┐   │  ← space-y-8 outer wrapper
│  │  HERO  (full width / col-span-1) │   │
│  │  "Good morning, Jane."  [Active] │   │
│  │  "Manage your account…"          │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │  ← grid gap-6 (single col)
│  │  PRIMARY                         │   │
│  │  ┌──────────┐  ┌──────────┐     │   │
│  │  │  Status  │  │  Status  │     │   │  ← sm:grid-cols-2 inside primary
│  │  │  Profile │  │  Payment │     │   │
│  │  └──────────┘  └──────────┘     │   │
│  │  ┌──────────┐                   │   │
│  │  │  Status  │                   │   │
│  │  │ Security │                   │   │
│  │  └──────────┘                   │   │
│  │                                  │   │
│  │  ┌──────────────────────────┐   │   │
│  │  │ Recent activity          │   │   │
│  │  │ Signed in  2 min ago …   │   │   │
│  │  └──────────────────────────┘   │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │  ← aside stacks BELOW primary
│  │  ASIDE                           │   │
│  │  ┌──────────────────────────┐   │   │
│  │  │ Quick links              │   │   │
│  │  └──────────────────────────┘   │   │
│  │  ┌──────────────────────────┐   │   │
│  │  │ Account                  │   │   │
│  │  └──────────────────────────┘   │   │
│  └──────────────────────────────────┘   │
│                                          │
└──────────────────────────────────────────┘
```

**Stack order:** Hero → Primary → Aside. This is the natural DOM order; no CSS
reordering needed. The grid collapses to 1 column, so items appear in source order.

### 2b. No-aside pages (placeholder is `hidden` at md)

```
┌──────────────────────────────────────────┐
│  TOP NAV                                 │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│                                          │
│  ┌──────────────────────────────────┐   │  ← no hero → nothing renders here
│  │  PRIMARY (full width at md)      │   │
│  │  ← Profile                       │   │
│  │  Profile              [Edit]     │   │
│  │  "Your account information."     │   │
│  │                                  │   │
│  │  [avatar JD]  Jane Doe           │   │
│  │  …detail grid rows…              │   │
│  └──────────────────────────────────┘   │
│                                          │
│  (empty aside placeholder is `hidden`   │
│   — no wasted row on tablet)            │
│                                          │
└──────────────────────────────────────────┘
```

The empty placeholder `<div class="hidden lg:block lg:col-span-4" aria-hidden="true">`
is not visible at md because the `hidden` base class takes effect and `lg:block` only
kicks in at 1024 px+. The primary column naturally expands to full width inside the
single-column grid.

---

## 3. `sm` Mobile (< 768 px)

Same as `md` but with `px-4` shell padding and the mobile nav sheet instead of
inline desktop nav items.

### 3a. Home page case

```
┌──────────────────────────────┐
│  TOP NAV  (px-4, h-16)       │
│  [☰]  [logo / name]  [user]  │
└──────────────────────────────┘

┌──────────────────────────────┐  ← py-10, px-4
│                              │
│  ┌────────────────────────┐  │
│  │  HERO (full width)     │  │
│  │  "Good morning,        │  │
│  │   Jane."  [Active]     │  │
│  │  "Manage your…"        │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │  ← PRIMARY
│  │  ┌──────────────────┐  │  │
│  │  │  Status: Profile │  │  │  ← grid-cols-1 inside primary at sm
│  │  └──────────────────┘  │  │    (sm:grid-cols-2 doesn't kick in yet)
│  │  ┌──────────────────┐  │  │
│  │  │  Status: Payment │  │  │
│  │  └──────────────────┘  │  │
│  │  ┌──────────────────┐  │  │
│  │  │  Status: Security│  │  │
│  │  └──────────────────┘  │  │
│  │                         │  │
│  │  ┌──────────────────┐  │  │
│  │  │ Recent activity  │  │  │
│  │  └──────────────────┘  │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │  ← ASIDE (stacked)
│  │  Quick links           │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │  Account               │  │
│  └────────────────────────┘  │
│                              │
└──────────────────────────────┘
```

### 3b. No-aside pages at sm

```
┌──────────────────────────────┐
│  TOP NAV                     │
└──────────────────────────────┘

┌──────────────────────────────┐
│                              │
│  ┌────────────────────────┐  │  ← PRIMARY (full width, single col)
│  │  ← Profile             │  │
│  │  Profile     [Edit]    │  │
│  │  ─────────────────────  │  │
│  │  [avatar]  Jane Doe    │  │
│  │  jane@example.com      │  │
│  │  ─────────────────────  │  │
│  │  First name   Jane     │  │
│  │  Last name    Doe      │  │
│  │  Email        jane@…   │  │
│  │  Member since Jan 2025 │  │
│  └────────────────────────┘  │
│                              │
│  (no aside → nothing here)   │
│                              │
└──────────────────────────────┘
```

---

## 4. Component markup (authoritative ERB contract for developer)

The following ERB represents the **exact final markup** the frontend developer must
implement in `app/components/member/page_layout_component.html.erb`. This is the
complete grid contract from the design spec, rendered as markup:

```erb
<div data-component="member-page-layout" class="space-y-8">
  <%# Hero: full-bleed inside the grid (optional) %>
  <% if hero? %>
    <div class="lg:col-span-12">
      <%= hero %>
    </div>
  <% end %>

  <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
    <%# Primary: always col-span-8 — NEVER col-span-12 %>
    <div class="lg:col-span-8 space-y-6 min-w-0">
      <%= primary %>
    </div>

    <%# Aside column: always reserved — either real content or invisible placeholder %>
    <% if aside? %>
      <aside class="lg:col-span-4 space-y-5 min-w-0">
        <%= aside %>
      </aside>
    <% else %>
      <div class="hidden lg:block lg:col-span-4" aria-hidden="true"></div>
    <% end %>
  </div>
</div>
```

**Note on hero placement:** The hero `<div>` is outside the 12-col grid but inside the
`space-y-8` wrapper. The grid div itself contains only the primary + aside row. At
`lg:`, the hero naturally renders full-width above the grid row because it is a sibling
block element, not inside the 12-col grid. The `lg:col-span-12` class on the hero
wrapper is therefore only needed IF the hero is moved inside the same grid div; in the
layout above the hero sits outside the grid and takes full container width automatically.

The implementation MUST match the spec design verbatim. The only change from the current
`page_layout_component.html.erb` is:

1. Remove the `<%= primary_span_class %>` variable in the primary div class → replace
   with hardcoded `lg:col-span-8`.
2. Add the empty-aside placeholder `<div class="hidden lg:block lg:col-span-4"
   aria-hidden="true"></div>` in the `else` branch of `if aside?`.

The `primary_span_class` helper in `page_layout_component.rb` is deleted entirely.

---

## 5. Surfaces reflow — inner component placement

### `surfaces/index.html.erb` (currently bypasses template)

**Before:**
```erb
<%= render Member::SurfaceIndexComponent.new(surface: @surface, …) %>
```

**After:**
```erb
<%= render Member::PageLayoutComponent.new do |c| %>
  <% c.with_hero do %>
    <%# SurfaceIndexComponent renders PageHeaderComponent internally;
        that header must be lifted out as the hero slot OR kept inside primary.
        Decision: keep PageHeaderComponent inside primary (inside SurfaceIndexComponent)
        to avoid splitting the component. The hero slot is left empty on index pages. %>
  <% end %>
  <% c.with_primary do %>
    <%= render Member::SurfaceIndexComponent.new(
          surface:   @surface,
          records:   @records,
          page_meta: @page_meta,
          customer:  current_customer
        ) %>
  <% end %>
<% end %>
```

Alternatively (simpler, avoids empty hero slot):
```erb
<%= render Member::PageLayoutComponent.new do |c| %>
  <% c.with_primary do %>
    <%= render Member::SurfaceIndexComponent.new(
          surface:   @surface,
          records:   @records,
          page_meta: @page_meta,
          customer:  current_customer
        ) %>
  <% end %>
<% end %>
```

The second form is preferred — no empty hero slot, `SurfaceIndexComponent` keeps its
own `PageHeaderComponent` internally, the primary slot holds everything.

The empty-aside placeholder handles the 4-col reservation automatically.

### `surfaces/show.html.erb` (currently bypasses template)

Same pattern:
```erb
<%= render Member::PageLayoutComponent.new do |c| %>
  <% c.with_primary do %>
    <%= render Member::SurfaceDetailComponent.new(
          surface:  @surface,
          record:   @record,
          customer: current_customer
        ) %>
  <% end %>
<% end %>
```

### Inner component cleanup

Both `SurfaceIndexComponent` and `SurfaceDetailComponent` currently render their content
without any outer `max-w-*` or `mx-auto` wrapper (confirmed by reading the templates).
No cleanup of outer width classes is needed. The components are already clean and will
render correctly inside the primary slot.

---

## 6. Visual consistency assertion (width invariant at lg+)

To give the frontend developer a concrete correctness check:

At `lg` (1024 px), with `px-8` shell padding:

```
Available grid width = 1024 − 2 × 32 = 960 px
Gap between primary and aside = 32 px (gap-8)
Primary width (8/12) = (960 − 32) × (8/12) = 928 × 0.667 ≈ 619 px
```

This primary width (≈ 619 px) is IDENTICAL on:
- Home page (hero + primary + aside) — aside present → 8 cols
- Profile page (primary only) — aside absent, placeholder → still 8 cols
- Security page — same
- Surface index/show — same

At `2xl` (1536 px, capped by `max-w-screen-2xl`):
```
Available grid width = 1536 − 2 × 32 = 1472 px
Primary width (8/12) = (1472 − 32) × (8/12) = 1440 × 0.667 ≈ 960 px
```

---

## 7. Empty / loading / error states

`PageLayoutComponent` is a layout primitive — it does not produce its own empty, loading,
or error states. Those are the responsibility of the content rendered inside each slot:

| Slot | Empty state owner |
|---|---|
| `hero` | `HeroCardComponent` — always has content when rendered; hero slot itself is optional |
| `primary` | `SurfaceIndexComponent` renders `EmptyStateComponent` when records empty; `PageSectionComponent` content areas handle their own empty states |
| `aside` | When omitted, placeholder renders invisibly; no error state needed |

---

## 8. Stimulus notes

No Stimulus controller is needed on `PageLayoutComponent` itself. The layout is
pure CSS (Tailwind grid). Existing Stimulus controllers on inner components
(`mobile-nav`, `flash`, any future inline controllers) are unaffected by this change.

---

## 9. Summary of Tailwind classes — cheat sheet for developer

| Element | Classes |
|---|---|
| Outer layout wrapper | `space-y-8` (data-component="member-page-layout") |
| Hero wrapper (when present) | `lg:col-span-12` |
| Grid row | `grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8` |
| Primary | `lg:col-span-8 space-y-6 min-w-0` |
| Aside (when present) | `lg:col-span-4 space-y-5 min-w-0` (as `<aside>`) |
| Aside placeholder (when absent) | `hidden lg:block lg:col-span-4` + `aria-hidden="true"` |

No other Tailwind utilities are added or changed on the template itself. Inner component
classes are unchanged.

# UX Spec: Rendered Views Card
## Page Detail — Audience Links (Pages::AudienceLinksCardComponent)

Date: 2026-06-11
Status: ready for frontend

---

## 1. Surface Inventory

| Surface | Nav area | URL |
|---|---|---|
| Page detail show view — "Rendered Views" card | Maintenance/Modules | `/:cid/admin/maintenance/pages/:id` |

This spec covers one card only. It replaces lines 153–176 of
`app/views/admin/maintenance/pages/show.html.erb` (the "Generated Template" block).
No other surfaces change.

---

## 2. Layout Spec

### Card title

Prefer **"Rendered Views"** over "Audience Links". It communicates the outcome
(you see the page as that audience does) without surfacing the internal term
"audience". The subtitle in the card header reads:
"Open the page as each audience experiences it."

### Desktop mockup (≥ sm breakpoint)

```
┌────────────────────────────────────────────────────────────────────┐
│  Rendered Views                                                    │
│  Open the page as each audience experiences it.                    │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  [●] Admin                                                   │  │
│  │      Dashboard layout · admin chrome, sidebar navigation     │  │
│  │                                          [ ↗ Open ]          │  │
│  ├──────────────────────────────────────────────────────────────┤  │
│  │  [●] Member                                                  │  │
│  │      Member layout · cyan-branded portal experience          │  │
│  │      ⚠ Requires an active member session to open.            │  │
│  │                                          [ ↗ Open ]          │  │
│  ├──────────────────────────────────────────────────────────────┤  │
│  │  [○] Public                                                  │  │
│  │      Public form page · anonymous visitors, no sign-in       │  │
│  │                             ✕ Not visible to public          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

Each audience row is a `div` that spans the full card width. The inner layout
is a two-column flex: left side holds the dot-icon + label + description
stack; right side holds the action (Open button or disabled reason chip).

### Mobile mockup (< sm breakpoint)

On mobile the action moves below the description, left-aligned, so the row
stacks vertically without truncation.

```
┌──────────────────────────────────────┐
│  Rendered Views                      │
│  Open the page as each audience…     │
├──────────────────────────────────────┤
│                                      │
│  [●] Admin                           │
│      Dashboard layout · admin        │
│      chrome, sidebar navigation      │
│      [ ↗ Open ]                      │
│                                      │
│  ──────────────────────────────────  │
│                                      │
│  [●] Member                          │
│      Member layout · cyan-branded    │
│      portal experience               │
│      ⚠ Requires an active member     │
│        session to open.              │
│      [ ↗ Open ]                      │
│                                      │
│  ──────────────────────────────────  │
│                                      │
│  [○] Public                          │
│      Public form page · anonymous    │
│      visitors, no sign-in            │
│      ✕ Not visible to public         │
│                                      │
└──────────────────────────────────────┘
```

### Data per row

| Field | Source |
|---|---|
| Audience label | Static: "Admin" / "Member" / "Public" |
| Surface description | Static one-liner per audience (see copy below) |
| Link enabled? | `@page.published? && @page.visible_to?(audience_key)` |
| Disabled reason | `!@page.published?` → "Not published"; else → "Not visible to [Audience]" |
| Link URL | Admin: `admin_maintenance_page_render_path(cid, @page)` · Member: `member_page_path(cid, @page)` · Public: `public_page_url(customer_id: cid, token: @page.public_token)` |

#### Static copy

- Admin: "Dashboard layout — rendered inside the admin chrome with sidebar navigation."
- Member: "Member layout — rendered inside the cyan-branded member portal."
- Public: "Public form page — accessible to anyone with the link, no sign-in required."

### Audience dot colors (identity colors)

The Visibility card uses no dot colors today; we introduce a small colored dot
before each audience label to give quick at-a-glance orientation. Use Tailwind
inline utilities, not custom tokens:

| Audience | Dot class | Rationale |
|---|---|---|
| Admin | `bg-accent` (`#6366f1` indigo) | Matches the admin accent color used throughout admin chrome |
| Member | `bg-member-accent` (`#0891b2` cyan) | Matches `--color-member-accent` already in the token set |
| Public | `bg-success` (`#059669` emerald) | Neutral positive; "world is open" signal |

Dot is `w-2 h-2 rounded-full flex-shrink-0 mt-1.5` (vertically aligned with first
line of text).

### Disabled state treatment

Two possible disabled states exist. Both use a non-anchor element (a `span`):

**State A — Not published** (takes precedence over visibility):
```
<span class="inline-flex items-center gap-1.5 text-sm text-text-muted">
  <!-- X-circle icon, w-4 h-4 -->
  Not published
</span>
```
Background: none. No pill. Just muted icon + muted text. This keeps the row
visually recessive without adding noise.

**State B — Not visible to [Audience]**:
```
<span class="inline-flex items-center gap-1.5 text-sm text-text-muted">
  <!-- EyeSlash icon, w-4 h-4 -->
  Not visible to Admin  <!-- or Member / Public -->
</span>
```

Both disabled states sit in the same flex slot as the "Open" button (right side
on desktop, below description on mobile).

### Member session caption

The Member row always shows a small informational note regardless of
enabled/disabled state:

```
<p class="text-xs text-text-muted mt-1 flex items-center gap-1">
  <!-- InformationCircle icon, w-3.5 h-3.5 -->
  Requires an active member session to open.
</p>
```

This note appears between the description and the action (or disabled reason),
inset 20px to align under the label text (not the dot).

### Empty / loading / error states

There is no async loading for this card. The three rows are always rendered
server-side. No empty state is needed — there are always exactly three rows.

### Primary / secondary / destructive actions

| Action | Type | Element |
|---|---|---|
| Open (enabled) | Primary navigational | `<a>` with `class="btn btn-ghost"`, `target="_blank" rel="noopener noreferrer"` |
| Disabled reason | No action | `<span>` (non-interactive) |

No destructive actions in this card.

---

## 3. Interaction Flow

### Happy path — all three audiences enabled

1. Admin is on `/:cid/admin/maintenance/pages/:id` (show page).
2. Page is published and visible to all three audiences.
3. All three rows show an active "Open" button.
4. Admin clicks "Open" on any row → new browser tab opens to the rendered view URL.
5. Current tab remains unchanged.

### Failure path — page not published

1. All three rows show State A disabled ("Not published").
2. Admin publishes the page (Publishing card, same page).
3. Turbo reloads the show page; disabled reasons re-evaluate.
4. Rows for visible audiences now show "Open".

### Failure path — audience visibility off

1. Public row shows State B disabled ("Not visible to Public").
2. Admin opens Visibility card, checks "Public", saves.
3. Page reloads; Public row now shows "Open".

### Failure path — member link opened without member session

1. Admin clicks Member "Open" → tab opens to `/:cid/member/pages/:id`.
2. Controller finds no member session → redirects to member sign-in.
3. The admin sees the member sign-in page (correct behavior; no special handling
   needed in this card — the caption has already warned them).

### Failure path — stale link (page unpublished after tab opened)

1. Admin opens the rendered-view tab while page is published.
2. Another admin unpublishes the page.
3. On refresh the rendered-view controller returns 404 (per design doc).
4. The tab shows a Rails 404. This is acceptable; no special card handling.

---

## 4. Component Reuse Map

| Region | Existing component | Notes |
|---|---|---|
| Card shell | `.card` CSS class (not a Ruby component) | Same pattern as Publishing card and Visibility card — plain `div.card` |
| Card header | Plain ERB `div.px-6.py-4.border-b.border-border-subtle` | Same as Visibility card header |
| Audience rows container | `div.divide-y.divide-border-subtle` | Pattern from `flowchart_info_card_component.html.erb` |
| "Open" button | `.btn.btn-ghost` + external-link SVG | Same SVG icon at `show.html.erb:85-88` (arrow-top-right-on-square) |
| Audience dot | Inline `span.w-2.h-2.rounded-full` | New inline element, no component |
| Disabled reason span | Inline `span` with icon + text | No existing component fits; inline ERB |
| Member session caption | Inline `p.text-xs.text-text-muted` | No existing component fits; inline ERB |
| BadgeComponent | Not used in this card | Avoided to keep rows light |

### New component to build

**`Pages::AudienceLinksCardComponent`**

Props:
```ruby
initialize(page:, customer_id:)
```

Helper methods to expose from the Ruby class:
- `rows` → array of three audience structs (key, label, description, dot_class, url)
- `enabled?(key)` → `page.published? && page.visible_to?(key)`
- `disabled_reason(key)` → `"Not published"` | `"Not visible to #{label}"`
- `open_url(key)` → the correct URL helper per audience key

No Stimulus controller is needed for this card (all state is server-rendered,
all links open in new tabs).

---

## 5. Tailwind & Stimulus Notes

### Card shell

```
div.card.overflow-hidden
  div.px-6.py-4.border-b.border-border-subtle          ← header
    h3.section-header                                   ← "Rendered Views"
    p.text-body-sm.text-text-muted.mt-1                 ← subtitle
  div.divide-y.divide-border-subtle                     ← rows wrapper
```

### Per-audience row

Desktop (sm+): single flex row, items between.
Mobile: stacked column.

```
div.px-6.py-4
  div.flex.flex-col.gap-3.sm:flex-row.sm:items-start.sm:justify-between
    div.flex.items-start.gap-3.min-w-0          ← left: dot + text
      span.w-2.h-2.rounded-full.flex-shrink-0.mt-1.5   ← dot (bg-accent / bg-member-accent / bg-success)
      div.min-w-0
        p.text-sm.font-medium.text-text-primary  ← "Admin"
        p.text-sm.text-text-muted.mt-0.5         ← surface description
        p.text-xs.text-text-muted.mt-1.flex.items-center.gap-1   ← member caption only
    div.flex-shrink-0                            ← right: action or reason
```

### Enabled "Open" link

```
a.btn.btn-ghost href=url target=_blank rel="noopener noreferrer"
  svg.w-4.h-4.mr-1.5  ← arrow-top-right-on-square (same path as show.html.erb:85-88)
  "Open"
```

### Disabled reason

```
span.inline-flex.items-center.gap-1.5.text-sm.text-text-muted.py-2
  svg.w-4.h-4.flex-shrink-0   ← icon (see below)
  span  ← reason text
```

### Icons (inline SVG, stroke="currentColor" stroke-width="2" fill="none")

All icons follow the existing app convention: raw `<svg>` tags with Heroicons
v2 outline paths — no icon component, no icon gem.

| Use | Heroicons v2 outline path |
|---|---|
| "Open" button | `arrow-top-right-on-square` — already used at `show.html.erb:85` |
| "Not published" disabled | `x-circle` — `M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z` |
| "Not visible" disabled | `eye-slash` — `M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88` (same SVG already at `show.html.erb:56`) |
| Member session caption | `information-circle` — `M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z` |

### Stimulus

No Stimulus controller required. The card is fully server-rendered with no
interactive state changes (opening a link in a new tab is native browser
behavior). If a future iteration adds copy-URL-to-clipboard, a lightweight
`clipboard` controller would be added then.

### Responsive breakpoint summary

| Property | Mobile (default) | sm+ |
|---|---|---|
| Row layout | `flex-col gap-3` | `flex-row items-start justify-between` |
| Action position | Below description, left-aligned | Right side of row |
| Dot + text block width | Full width | `min-w-0` (shrinks to let action stay right) |

---

## Notes for Frontend Developer

1. Replace lines 153–176 of `app/views/admin/maintenance/pages/show.html.erb`
   with `<%= render Pages::AudienceLinksCardComponent.new(page: @page, customer_id: current_customer_id) %>`.
2. The Public URL helper (`public_page_url`) takes `customer_id:` and `token:` kwargs — match
   the existing call at `show.html.erb:76`.
3. The Admin render URL helper will be `admin_maintenance_page_render_path(cid, page)` once
   the security engineer adds the nested route.
4. The Member URL helper will be `member_page_path(cid, page)` once the security engineer adds
   the member route.
5. Until those routes exist, stub the helpers in the component as `"#"` with a TODO comment so
   the component spec can be written independently.
6. `page.visible_to?(key)` already exists (used by the Visibility card). `page.published?` is
   already used in the Publishing card.

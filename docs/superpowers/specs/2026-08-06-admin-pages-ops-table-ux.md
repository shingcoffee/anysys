# Admin Pages Ops Table — UX Spec

**Date:** 2026-08-06  
**Surface:** `/:cid/admin/pages`, `/:cid/admin/pages/entities/:id`, `/:cid/admin/pages/uncategorized`  
**Audience:** customer `admin` / platform `owner` (ops-only; no create/edit)  
**Status:** Ready for frontend  
**Reference implementations:** `Admin::Entities::EntriesTableComponent`, `Pages::DistributionCardComponent`, project semantic tokens in `app/assets/tailwind/application.css`

---

## 1. Surface inventory

| Surface | Nav area | Role | Notes |
|---------|----------|------|-------|
| Pages ops list (all) | **admin** — chrome sidebar “Pages” | admin / owner | `/:cid/admin/pages` |
| Pages ops list (entity-filtered) | **admin** — sidebar entity child | admin / owner | `/:cid/admin/pages/entities/:id` |
| Pages ops list (uncategorized) | **admin** — sidebar uncategorized | admin / owner | `/:cid/admin/pages/uncategorized` |
| Publishing slide-over | **admin** — overlay on list | admin / owner | Existing `Admin::Pages::PublishingPanelComponent` + `Pages::DistributionCardComponent` — **no visual redesign in this pass**; list must open it unchanged |

Out of scope: page builder create/edit, Maintenance pages CRUD, member/public render UIs, batch checkbox bar (not required for this refactor unless already wired elsewhere).

---

## 2. Design intent (why the current list feels ugly)

Current pain (generic `AdminTableComponent`):

1. **Badge cluster** for hierarchical audiences (Admin + Member + Public) — three loud pills for one scalar.
2. **Competing chrome** — document icon tile + entity subtitle + Entity column + Live/Draft badge + inline “Manage access” + kebab = dense noise.
3. **Duplicate affordances** — name link and “Manage access” both open the same publishing frame.
4. **Mismatched semantics** — Distribution card uses ordered dots (`accent` / `member-accent` / `success`); the table uses warning/purple/info badges.

Goal: a quiet, scannable **ops ledger** — identity first, reach second, launch third, actions last — consistent with the entity entries table density and Distribution audience language.

---

## 3. Overall composition

### Page chrome (unchanged)

Reuse `AdminPageComponent`:

- Breadcrumb: Pages
- Title / description from controller (`@page_title`, `@page_description`)
- No page-level primary CTA (ops-only; no “New page”)

### List shell

Build a **bespoke** table component (do **not** stretch `AdminTableComponent` further), parallel to entries:

- **Name:** `Admin::Pages::OpsTableComponent`
- **Shell:** `<section class="card overflow-hidden">` inside a turbo-frame (e.g. `pages-ops-table`)
- **Density:** comfortable desktop (`py-3.5` cells), matching entries table — not compact ops density unless a density toggle already exists (omit for v1)

### Toolbar (header band)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ [🔍 Search pages…        ]  [Launch status ▾]              12 results   │
│                                                                         │
│ (optional filter chips when launched filter active)                     │
└─────────────────────────────────────────────────────────────────────────┘
```

| Region | Content | Classes / tokens |
|--------|---------|------------------|
| Left | Search + Launch filter select | `px-4 py-3 border-b border-border-subtle`; search `input-field w-full sm:w-64 lg:w-80 pl-9`; filter `input-field shrink-0` |
| Right | Count summary | `text-[13px] text-text-muted tabular-nums` |
| Chips | Active filter remove chips | Same pattern as entries: `bg-accent-subtle text-accent-text ring-1 ring-inset ring-accent-muted` — keep sparse |

Filters: keep existing `launched` filter only. No audience filter in v1.

### Desktop column set (slim)

| # | Column | Width guidance | Data |
|---|--------|----------------|------|
| 1 | **Page** | `min-w-0` flex grow | `page.name` + subtitle |
| 2 | **Audience** | ~9–11rem | hierarchical reach (see §4) |
| 3 | **Status** | ~6–7rem | launched Live / Draft (see §5) |
| 4 | **Updated** | ~7rem | relative `updated_at` |
| 5 | **Actions** | `w-px` right | primary + menu (see §6) |

**Drop from current columns:**

- Leading document icon tile
- Separate **Entity** column (subtitle covers it)
- **Fields** count (low ops value; clutters scan path)
- Multi-badge visibility rendering

**Entity-filtered path:** omit entity subtitle (redundant).  
**All / Uncategorized:** subtitle = `metadata["entity_name"]` or i18n uncategorized label (`admin_misc.pages.uncategorized.row_subtitle`).

### Row anatomy (desktop)

```
| [Name                    ] | [● ● ○  Member] | [● Live ] | [2 days ago] | [Manage access  ⋯] |
|  Entity subtitle (muted)   |                 |           |              |                    |
```

- Row: `table-row` + `divide-y divide-border-subtle`
- Header: `table-header`; Actions header label uses existing micro-label style: `text-[10.5px] uppercase tracking-[0.1em] font-semibold text-text-tertiary/70`
- Name text: `text-sm font-medium text-text-primary`
- Subtitle: `text-xs text-text-muted mt-0.5 truncate`
- Secondary cells: `text-sm text-text-secondary`
- Updated: `text-[13px] text-text-muted tabular-nums` with `<time datetime title=exact>`

**Name click behavior:** Name is **not** a second “Manage access”. Name is plain text (identity only). Opening publishing is only via the Actions primary control. This removes the dual-affordance confusion.

---

## 4. Multi-audience visibility — recommended pattern

### Decision: **Audience reach meter + top-level label** (not badges)

Visibility is a **hierarchy** (`admin` ⊂ `member` ⊂ `public` via `Page#visibility` / `visible_audiences`). Showing N badges repeats implied tiers and creates pill noise.

**Pattern (required):**

1. A horizontal **3-dot meter** for Admin → Member → Public (same order and colors as Distribution).
2. A single **top-level audience label** = the stored `page.visibility` string (Admin / Member / Public), not a joined list.

```
● ● ○  Member
│ │ └── Public off (muted)
│ └──── Member on
└────── Admin on (always when any visibility exists)
```

| Level | Dot on | Dot off | Label shown |
|-------|--------|---------|-------------|
| `admin` | ● ○ ○ | | Admin |
| `member` | ● ● ○ | | Member |
| `public` | ● ● ● | | Public |

**Dot classes (match Distribution exactly):**

| Audience | On | Off |
|----------|----|-----|
| admin | `bg-accent` | `bg-border-subtle` |
| member | `bg-member-accent` | `bg-border-subtle` |
| public | `bg-success` | `bg-border-subtle` |

Layout classes:

```
inline-flex items-center gap-2
  span.inline-flex items-center gap-1   # meter
    span.w-1.5 h-1.5 rounded-full …    # each dot
  span.text-sm text-text-secondary     # top-level label only
```

**Accessibility:**

- Wrap meter in an element with `aria-label` = full i18n sentence, e.g. “Visible to Admin and Member” / idiomatic zh-CN equivalent built from `visible_audiences`.
- Dots are decorative (`aria-hidden="true"`); label text carries the human-readable top level.

**Empty / unknown visibility:** show em dash (`common.labels.em_dash`) with no dots (should not happen for valid pages).

**Sorting:** keep sorting by underlying `visibility` column (scalar), not by badge count.

**New leaf component (recommended):**

`Admin::Pages::AudienceReachComponent`  
Props: `visibility:` (or `audiences:` + `top_level:`)  
Renders meter + label only — reusable if other ops lists need the same language later.

### Rejected alternatives

| Pattern | Why reject |
|---------|------------|
| 1–3 `BadgeComponent`s (current) | Noisy; fights Launch badges |
| Comma-separated plain text only | Loses Distribution color language; harder to scan |
| Segmented pill bar / progress track | Overbuilt; card-like chrome in a cell |
| Icon row / emoji | Violates no-emoji / AI-slop rules |
| Showing all three labels when public | Redundant with hierarchy |

---

## 5. Launch state presentation

**Pattern: status dot + word** — quieter than `BadgeComponent`, still glanceable.

| State | Visual | Classes |
|-------|--------|---------|
| Live (`launched?`) | filled success dot + “Live” | dot `bg-success`; text `text-sm font-medium text-success` |
| Draft (!launched) | muted filled dot + “Draft” | dot `bg-border-strong` or `bg-text-tertiary/40`; text `text-sm text-text-muted` |

Do **not** use `BadgeComponent` success/default in this column — the table already had badge fatigue; keep Status typographic.

Column header: prefer **Status** (new i18n key under `common.labels.status` if missing), values Live/Draft (`common.status.live` / `common.status.draft`). Fallback: keep header `common.labels.launched` if product wants zero new keys.

Toolbar filter continues to filter by launched boolean; chip label should say Live/Draft not raw true/false.

---

## 6. Actions pattern

### Priority

| Priority | Action | Placement | Behavior |
|----------|--------|-----------|----------|
| **Primary** | Manage access | Actions column — text control | Opens publishing slide-over (`turbo_frame: page-publishing`) |
| **Secondary** | Preview | Overflow menu | `target="_blank"` maintenance preview |
| **Secondary** | Launch **or** Take offline | Overflow menu | POST/DELETE launch endpoint with `return_to` |

### Why this split

- Manage access is the **default ops job** on this list → always visible, one click.
- Preview / Launch are less frequent → kebab keeps the row calm.
- Launch stays out of the primary slot so a mis-click does not take a page offline.

### Visual treatment

```
[ Manage access ]  [ ⋯ ]
```

- Manage access: quiet text action —  
  `text-sm font-medium text-accent-text hover:underline decoration-1 underline-offset-[3px] transition-base`
- Kebab: existing pattern —  
  `w-8 h-8 rounded-md text-text-secondary hover:text-text-primary hover:bg-surface-hover`  
  + `menu-placement` Stimulus + panel  
  `absolute right-0 z-20 mt-1 min-w-[11rem] rounded-lg border border-border-subtle bg-canvas-elevated py-1 shadow-md`
- Menu items: `block px-3 py-2 text-sm font-medium text-text-primary hover:bg-surface-hover`
- Take offline: keep neutral label (copy already says “Take offline”); optional `text-danger` only if other admin menus already do so consistently.

**Do not** put Launch as a green `btn-success` in every row — that belongs in the Distribution card header.

### Row click

No full-row click target. Only explicit Manage access (and menu items).

---

## 7. Mobile treatment (`sm:hidden` cards)

Mirror `EntriesTableComponent` mobile stack:

```
┌─────────────────────────────────────┐
│ Page name                           │
│ Entity subtitle                     │
│ ● ● ○ Member · ● Live · 2d ago      │
│                                     │
│ Manage access                   ⋯   │
└─────────────────────────────────────┘
```

- Container: `sm:hidden divide-y divide-border-subtle`
- Card: `p-4 hover:bg-surface-hover transition-base`
- Meta line: `mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[13px] text-text-muted` with middots (`·`) as separators
- Actions row: `mt-3 flex items-center justify-between gap-2`
- Desktop table: `hidden sm:block overflow-x-auto` (same breakpoint as entries)

No batch checkboxes on mobile (or at all for this ops table).

---

## 8. States

| State | Treatment |
|-------|-----------|
| **Empty (no pages)** | Centered empty block like entries: 56px rounded-2xl `bg-surface-active` icon well + `empty_title` / `empty_description` from `admin_misc.pages.*` — **no** create CTA |
| **Empty after search/filter** | “No matches” + clear search / filter hint (`chrome.admin_table.*`) |
| **Loading** | Turbo frame morph / default browser; optional skeleton not required for v1 |
| **Error (launch fail / auth)** | Flash on redirect (existing); slide-over keeps own validation |
| **Permission denied** | Controller-level; list never shown |

Publishing panel empty frame at bottom of page remains:  
`<turbo-frame id="page-publishing"></turbo-frame>`

---

## 9. Interaction flows

### US1 — Scan and open publishing

1. Start: `/:cid/admin/pages` (or entity / uncategorized)
2. User scans Audience meter + Status
3. Clicks **Manage access**
4. Outcome: slide-over loads Distribution card in `page-publishing`
5. User edits visibility / launch inside panel → list refresh on return/frame update as today

### US2 — Preview

1. Open kebab → **Preview**
2. New tab: maintenance preview URL
3. List stays put

### US3 — Launch / take offline from list

1. Open kebab → **Launch** or **Take offline**
2. POST/DELETE with `return_to: request.fullpath`
3. Success: redirect back to list; Status cell updates
4. Failure: flash error; row unchanged

### US4 — Filter to drafts

1. Toolbar Launch status → Draft
2. Table reloads in turbo-frame; chip appears
3. Clear chip → all pages

### Failure flows

| Failure | UX |
|---------|-----|
| Launch endpoint error | Flash; stay on list |
| Unauthorized | 403 / redirect per existing admin guards |
| Slide-over close | Clear frame / close via existing `slide-over` Stimulus |

---

## 10. Component reuse map

| Piece | Reuse | New |
|-------|-------|-----|
| Page shell | `AdminPageComponent` | — |
| Card / table shell / toolbar / empty / pagination | Patterns from `Admin::Entities::EntriesTableComponent` + `Admin::PaginationComponent` | **`Admin::Pages::OpsTableComponent`** |
| Audience cell | Dot colors from `Pages::DistributionCardComponent::DOT_CLASSES` | **`Admin::Pages::AudienceReachComponent`** |
| Status cell | plain markup in ops table | (inline in OpsTable; no BadgeComponent) |
| Actions menu | `menu-placement` Stimulus + details/summary pattern from `AdminTableComponent` | — |
| Publishing overlay | `Admin::Pages::PublishingPanelComponent`, `Pages::DistributionCardComponent`, `slide-over` | — |
| Search icon / filter chips | Copy entries table markup | — |
| Badges for audience/launch in list | **Do not use** | — |

**Deprecate for this surface:** driving the list through generic `AdminTableComponent` + `Admin::Pages::ColumnsBuilder` badge arrays. ColumnsBuilder may shrink to sort/search metadata for `ModuleEntriesResolver`, or OpsTable may own column config — frontend choice, but **rendering** must follow this spec.

---

## 11. Tailwind & Stimulus notes

### Tokens / utilities (prefer these)

```
card
border-border-subtle
bg-surface-hover / bg-surface-active
text-text-primary | text-text-secondary | text-text-muted | text-text-tertiary
text-accent-text
text-success
bg-accent | bg-member-accent | bg-success | bg-border-subtle
input-field
table-header | table-row
transition-base
shadow-md          # menu panel only
```

### Spacing rhythm

- Toolbar / cells: `px-4`, comfortable `py-3.5`
- Flex gaps: `gap-2` / `gap-3` (use `flex gap-*`, not `space-x-*` / `space-y-*`)
- Equal icon buttons: `w-8 h-8` (match entries) or `size-8` if already used nearby

### Stimulus

| Controller | Role |
|------------|------|
| `menu-placement` | Kebab panel reposition (existing) |
| `slide-over` | Publishing panel (existing; unchanged) |
| `page-visibility` | Inside Distribution card only (unchanged) |
| *(none new for table)* | Audience meter is static markup |

No new JS for the list unless frontend extracts a tiny shared helper; Vitest 100% applies if any JS is added.

### I18n

All labels via existing or new keys under `admin_misc.pages.*` / `common.*` / `comp_admin.*` — **en + zh-CN** parity. New strings likely needed:

- Audience `aria-label` templates (interpolation for audience list)
- Optional column header “Status”
- Keep Manage access / Preview / Launch / Take offline keys as today

---

## 12. What NOT to do

- **No** multi-badge audience clusters (Admin/Member/Public pills)
- **No** purple-on-white gradients, glow, glass, neon
- **No** emoji, sticker badges, or floating chips on rows
- **No** multi-layer dramatic shadows on the table card (card uses existing `.card` shadow only; menu may use `shadow-md`)
- **No** leading document icon tiles on every row
- **No** duplicate Entity column + subtitle
- **No** Fields column in the ops list
- **No** full-width colored status bars or “LIVE” screaming uppercase badges
- **No** primary green Launch button per row
- **No** row click + Manage access both doing the same thing
- **No** custom CSS / non-Tailwind / non-Stimulus frameworks
- **No** hard-coded user-facing English in ERB/JS
- **Do not** redesign Distribution card / slide-over in this pass

---

## 13. ASCII — desktop final target

```
AdminPageComponent
  title / description
  ┌─ card ──────────────────────────────────────────────────────────────┐
  │ Toolbar: [search] [Launch ▾]                          N results     │
  ├─────────────────────────────────────────────────────────────────────┤
  │ PAGE                 AUDIENCE           STATUS    UPDATED   ACTIONS │
  ├─────────────────────────────────────────────────────────────────────┤
  │ Membership Intake    ● ● ○  Member      ● Live    2 days ago        │
  │ Entity · Members                              Manage access      ⋯  │
  ├─────────────────────────────────────────────────────────────────────┤
  │ Welcome              ● ○ ○  Admin       ○ Draft   5 hours ago       │
  │ Uncategorized                                 Manage access      ⋯  │
  ├─────────────────────────────────────────────────────────────────────┤
  │ … pagination …                                                      │
  └─────────────────────────────────────────────────────────────────────┘
  <turbo-frame id="page-publishing">
```

---

## 14. Acceptance checklist (for frontend + QA)

- [ ] List uses bespoke ops table visual language aligned with entity entries table
- [ ] Audience shown as 3-dot meter + single top-level label; zero audience badges
- [ ] Launch shown as dot + Live/Draft text; zero status badges in the Status column
- [ ] Actions: Manage access visible; Preview + Launch/Take offline in kebab
- [ ] Name is not a second link to the slide-over
- [ ] Entity column and Fields column gone; subtitle handles entity context
- [ ] Mobile card layout works `< sm`; desktop table `≥ sm`
- [ ] Publishing slide-over still opens and functions
- [ ] All new copy has `en` + `zh-CN`
- [ ] No create/edit affordances introduced

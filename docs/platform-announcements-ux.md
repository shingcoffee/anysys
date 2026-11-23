# Platform announcements — UX

> **As-built note (2026-08-29):** the shipped banner stacks every live notice as an
> independently dismissible strip (critical > warning > info, then newest-first) instead of
> a single primary strip with a `+N more` disclosure, and dismissals are persisted per
> `(user, customer, announcement)` rather than held in the session. See
> `docs/platform-announcements-design.md` for the authoritative as-built spec.


Date: 2026-08-29

Audience: frontend developer. Implement ViewComponent + Tailwind + Stimulus only. Do **not** add four-area module surfaces (Modules / Settings / Maintenance toggle / Platform Module Settings). This is platform-maintenance CRUD plus admin-shell chrome.

Locked product decisions: `docs/platform-announcements-design.md`.

---

## 1. Surface inventory

| # | Surface | Nav area | URL | Audience | Notes |
|---|---|---|---|---|---|
| A | Announcements index | admin | `GET /81721200/admin/maintenance/platform/announcements` | `owner` on customer `81721200` | Sibling of Customers under Maintenance → Platform |
| B | New announcement | admin | `GET /81721200/admin/maintenance/platform/announcements/new` | same | Form create |
| C | Edit announcement | admin | `GET /81721200/admin/maintenance/platform/announcements/:id/edit` | same | Same form, update |
| D | Show announcement | admin | `GET /81721200/admin/maintenance/platform/announcements/:id` | same | Read-only summary |
| E | Customer picker (panel) | admin | lives on B/C | same | Shown only when Audience = Selected |
| F | Admin chrome banner | admin | every admin dashboard page that uses `ShellComponent` | tenant `admin`, or `owner` **only when** `Current.platform_owner_context?` | First child of the shell column, **above** `Platform::ContextBannerComponent`. Members never see it. Owner on `81721200` (not acting-as) never sees it. |

Sidebar leaf (security/routes task wires it): Maintenance → Platform → **Announcements**, immediately after **Customers**. Visible only to owner + customer `81721200`.

Dismiss is **not** a page. It is `POST /:customer_id/admin/platform_announcement_dismissals` from the banner, then redirect back.

Out of scope (no surfaces): member/public chrome, notifications bell, email/SMS, markdown/HTML, images, persisted dismiss.

---

## 2. Layout spec per surface

### Shared chrome (every admin page)

`ShellComponent` column order — do not reorder existing siblings other than inserting the new banner first:

```
┌─────────────────────────────────────────────────────────────┐
│ F  Platform::AnnouncementBannerComponent   (NEW, if render?)│
├─────────────────────────────────────────────────────────────┤
│    Platform::ContextBannerComponent        (existing, if    │
│                                            acting-as)       │
├─────────────────────────────────────────────────────────────┤
│    TopbarComponent                                          │
├─────────────────────────────────────────────────────────────┤
│    MenuBarComponent                                         │
├──────────────┬──────────────────────────────────────────────┤
│ Sidebar      │ <main>  page content (A–D)                   │
└──────────────┴──────────────────────────────────────────────┘
```

Flash alerts stay in the dashboard layout (AdminPageComponent does not render flash).

---

### A. Announcements index

**Wrapper:** `AdminPageComponent` + `AdminTableComponent` — same pattern as `app/views/admin/maintenance/platform/customers/index.html.erb`.

**Header**

| Region | Content | Source |
|---|---|---|
| Breadcrumbs | Maintenance → Announcements | `maint_platform.announcements.breadcrumb.*` |
| Title | Announcements | `maint_platform.announcements.index.title` |
| Description | Publish time-bounded notices to tenant admins. | `maint_platform.announcements.index.description` |
| Primary action | New announcement (`variant: :primary`, `icon: :plus`) | `maint_platform.announcements.index.new_action` → `new_…_announcement_path` |

**Table columns** (map to `platform_announcements`)

| Column key | Type | Label (en) | Cell |
|---|---|---|---|
| `title` | text (primary, row link) | Title | `title` |
| `severity` | badge | Severity | `info` → `BadgeComponent` `:info` “Info”; `warning` → `:warning` “Warning”; `critical` → `:danger` “Critical” |
| `status` | badge | Status | `draft` → `:default` + `common.status.draft`; `published` → `:success` + `common.status.published` |
| `audience` | text | Audience | `all` → “All”; `selected` → “%{count} customers” (`targets.size`) |
| `starts_at` | datetime | Starts | AdminTable datetime (`%Y-%m-%d %H:%M`); blank → “—” |
| `ends_at` | datetime | Ends | same |
| `updated_at` | datetime | Updated | same |

Search: `{ param: :q, placeholder: "Search by title..." }` — searchable on `title` only.

Filters (AdminTable select chips):

- Status: Draft / Published
- Severity: Info / Warning / Critical

**Row click** → show path.

**Row actions**

| Action | Tone | Behavior |
|---|---|---|
| Edit | default | GET edit |
| Delete | danger (`method: :delete`) | `data-turbo-confirm` “Delete "%{title}"? This cannot be undone.” |

No trash. Hard delete.

```
┌─ AdminPage ─────────────────────────────────────────────────┐
│ Maintenance / Announcements                                 │
│                                                             │
│ Announcements                    [ + New announcement ]     │
│ Publish time-bounded notices to tenant admins.              │
│                                                             │
│ ┌─ AdminTable ────────────────────────────────────────────┐ │
│ │ [🔍 Search by title...] [Status ▾] [Severity ▾]  3     │ │
│ │ Title          Sev     Status     Audience  Starts …   │ │
│ │ Q3 downtime    Warning Published  All       09-01 …    │ │
│ │   ↳ Edit  Delete                                        │ │
│ │ Billing note   Info    Draft      2 customers  —    …  │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Empty / loading / error**

| State | Treatment |
|---|---|
| Empty (no rows, no query) | AdminTable empty_state: title “No announcements yet”; description “Create a notice to display on tenant admin dashboards.”; action “New announcement” |
| Empty after search/filter | Built-in AdminTable no-matches copy (`chrome.admin_table.*`) |
| Loading | Full page navigation / turbo-frame advance — no custom skeleton |
| Auth error | Existing platform-owner gate; not a page-level empty state |

**Mobile:** AdminTable already switches to stacked cards under `sm:`. Header actions wrap (`flex-col sm:flex-row` from AdminPage).

---

### B / C. New and Edit form

**Wrapper:** `AdminPageComponent` wrapping `Admin::Maintenance::Platform::AnnouncementFormComponent`.

Match billing plan form density: `mx-auto max-w-3xl`, stacked `card` sections, `space-y-5`, footer Cancel + Submit.

**Header (new)**

- Breadcrumbs: Maintenance → Announcements → New announcement
- Title: New announcement
- Description: Write a bilingual notice and choose who should see it.

**Header (edit)**

- Breadcrumbs: Maintenance → Announcements → `{title}` → Edit
- Title: Edit announcement
- Description: Update the notice content, schedule, or audience.

No header Save button (submit lives in the form footer, same as `Billing::Admin::PlanFormComponent`).

**Validation banner:** if the record/contract has errors, render `AlertComponent` `type: :error` with `errors.full_messages.to_sentence` **or** `FormErrorsComponent` — pick one and use it at the top of the form (plan form uses AlertComponent; SMS templates use FormErrorsComponent). Prefer `AlertComponent` `type: :error` to stay on the semantic Alert mapping.

```
┌─ AdminPage (max-w-3xl) ─────────────────────────────────────┐
│ [Alert error, if invalid]                                   │
│                                                             │
│ ┌─ card: Content ─────────────────────────────────────────┐ │
│ │ Title *          [________________________]  max 120    │ │
│ │ English body *   [________________________]  max 500    │ │
│ │ Chinese body *   [________________________]  max 500    │ │
│ │ Learn more URL   [________________________]  optional   │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ card: Display ─────────────────────────────────────────┐ │
│ │ Severity *  [ Info ▾ ]     Status *  [ Draft ▾ ]        │ │
│ │ Starts at   [ datetime ]   Ends at   [ datetime ]       │ │
│ │ hint: Leave blank for no start or end limit.            │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ card: Audience ────────────────────────────────────────┐ │
│ │ ( ) All customers                                        │ │
│ │     Every tenant, including customers created later.     │ │
│ │ (•) Selected customers                                   │ │
│ │     Only the customers checked below.                    │ │
│ │                                                          │ │
│ │ [ E  Customer picker — visible iff Selected ]            │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│                         [ Cancel ]  [ Create announcement ] │
│                         (edit: [ Save changes ])            │
└─────────────────────────────────────────────────────────────┘
```

**Field → model map**

| UI field | Model | Control | Required | Notes |
|---|---|---|---|---|
| Title | `title` | `text_field`, `form-label-required` | yes | max 120; owner CRUD only — never shown on the banner |
| English body | `body_en` | `text_area` rows 3 | yes | max 500; banner copy when locale is not `zh*` |
| Chinese body | `body_zh` | `text_area` rows 3 | yes | max 500; banner copy when locale is `zh*` |
| Learn more URL | `link_url` | `url_field` / `text_field` | no | `http`/`https` only; max 2048; caption “Optional. Must start with http:// or https://.” |
| Severity | `severity` | `select` | yes | Info / Warning / Critical; default `info` |
| Status | `status` | `select` | yes | reuse `common.status.draft` / `common.status.published`; default `draft` |
| Starts at | `starts_at` | `datetime_field` (`datetime-local`) | no | Live if null or `<= now` |
| Ends at | `ends_at` | `datetime_field` | no | Live if null or `> now`; contract: after `starts_at` when both set |
| Audience | `audience` | two radios | yes | All (`all`) vs Selected (`selected`) |
| Customers | `customer_ids[]` | picker checkboxes | if selected | ≥1 existing visible customer id |

**Audience radios** — reuse the billing plan availability card pattern:

```
label.flex.cursor-pointer.items-start.gap-3.rounded-lg.border.border-border-subtle.p-4
     .hover:bg-surface-hover.has-[:checked]:border-accent-muted.has-[:checked]:bg-accent-subtle
```

Two cards in `grid grid-cols-1 gap-3 sm:grid-cols-2`. Selecting All hides the picker (Stimulus). Selecting Selected shows it. Posted `customer_ids[]` may still be present when All is chosen; the Save activity ignores them.

**Footer**

| Action | Style | Behavior |
|---|---|---|
| Cancel | `btn btn-secondary` | GET index |
| Create announcement / Save changes | `btn btn-primary` submit | POST create / PATCH update |

**Empty / loading / error**

| State | Treatment |
|---|---|
| New (blank) | defaults: severity `info`, status `draft`, audience `all`, picker hidden |
| Edit | fields filled; picker open and boxes checked when `audience == selected` |
| Validation | Alert at top; stay on same URL (render new/edit); do not clear posted values |
| Selected + 0 customers | contract error on `customer_ids` — surface in the Alert; keep picker visible |
| `ends_at` before `starts_at` | same |
| Bad `link_url` | same |

No in-form loading spinner. Turbo full-page submit.

---

### E. Customer picker (panel on B/C)

**Component:** `Platform::AnnouncementCustomerPickerComponent`

**Data:** every **visible** (not soft-deleted) `Customer`, including `81721200`. Sort by `name` then `id`. Each row: checkbox `name="platform_announcement[customer_ids][]"` (or the form scope the form component uses), value = `customer.id`.

Label line: **customer name** (`text-body font-medium text-text-primary`) + mono id chip (`text-mono text-sm bg-surface-active px-1.5 py-0.5 rounded`) — same id chip as customers show.

```
┌─ picker ────────────────────────────────────────────────────┐
│ [🔍 Filter customers...]                    2 selected      │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ☑ Acme Corp          10000001                           │ │
│ │ ☐ Beta LLC           10000002                           │ │
│ │ ☑ Platform           81721200                           │ │
│ └─────────────────────────────────────────────────────────┘ │
│ max-h-72 overflow-y-auto, divide-y divide-border-subtle     │
└─────────────────────────────────────────────────────────────┘
```

Filter is **client-side only**. Match case-insensitive against name **or** id string. Hide non-matching **row** targets (`hidden`). Checked-but-filtered-out boxes stay checked and still submit.

**Empty / no-match**

| State | Treatment |
|---|---|
| No visible customers (should be rare) | “No customers available.” — no checkboxes |
| Filter matches nothing | hide all rows; show “No matching customers” (Stimulus toggles a target) |
| Loading | none — list is server-rendered with the form |

Do **not** add Select all / Clear all (not in the locked design).

---

### D. Show announcement

**Wrapper:** `AdminPageComponent`. Body: two `card`s matching billing plan show (`dl` grid), not the older customers show header.

**Header**

- Breadcrumbs: Maintenance → Announcements → `{title}`
- Title: `title`
- Description: omit, or a one-line computed state (see badge)
- Actions: Edit (`:primary`, `icon: :edit`); Delete is **not** a header button — keep destructive delete on the index row action only, **or** add a header danger action with the same confirm as index. Prefer index-only delete so the show page stays read-only + Edit (matches billing plans show).

**Computed header badge** (not a DB column — derive from `status` + `live?` + window):

| Condition | Badge | Label |
|---|---|---|
| `status == draft` | `:default` | Draft (`common.status.draft`) |
| published, `starts_at` in the future | `:info` | Scheduled |
| published + `live?` | `:success` | Live (`common.status.live`) |
| published, `ends_at` in the past | `:default` | Ended |

**Card 1 — Notice** (`dl` `grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3 text-body-sm`)

| dt (en) | dd |
|---|---|
| Severity | Badge (same mapping as index) |
| Status | Badge |
| Audience | All **or** N customers |
| Learn more | `link_url` as external link (`target=_blank` `rel=noopener`) or “—” |
| Starts at / Ends at / Created / Updated | formatted datetimes or “—” |

Then full-width blocks for English body and Chinese body (`whitespace-pre-wrap text-body text-text-primary`), each under a `form-label` / `dt`.

**Card 2 — Target customers**

- Audience `all`: one line “Every tenant, including customers created later.”
- Audience `selected`: unordered list of name + id chip, same visual as picker rows without checkboxes. Empty join set should not occur (invalid to save); if it does, show “No customers selected.”

**Empty / error:** 404 / not-found uses existing admin not-found. No loading skeleton.

---

### F. Admin chrome banner

**Component:** `Platform::AnnouncementBannerComponent`

**Placement:** first child inside the shell’s outer `h-screen flex flex-col` column — **above** `Platform::ContextBannerComponent`. Not sticky-overlay; it occupies flow like the context banner so topbar/menu stay below both strips.

**`render?`:** Resolver returns ≥1 live undismissed row for `Current.customer_id` **and** viewer is tenant `admin` **or** (`platform_owner?` && `platform_owner_context?`).

**Data (primary = first Resolver row):**

| UI | Source |
|---|---|
| Body | `body_for(I18n.locale)` — data, not an I18n key |
| Icon | severity (reuse AlertComponent SVG paths: info / warning / error-as-critical) |
| Learn more | if `link_url` present |
| +N more | if `remaining.size > 1`; `N = remaining.size - 1` |
| Expanded list | remaining rows **after** the primary; each shows that row’s localized body (plain text, no nested dismiss) |
| Dismiss | `button_to` POST `admin_platform_announcement_dismissals_path` with `platform_announcement_id` = primary id |

**shadcn Alert, composed as chrome — not an in-page Card, not the React package.** Structure:

- `role="status"` for info/warning; `role="alert"` for critical
- Left cluster = Alert icon + AlertDescription (the body). **No AlertTitle** — `title` is CRUD-only
- Right cluster = optional Learn more + `<details>` + Dismiss
- Full-width strip, `px-4 py-2`, `flex flex-wrap items-center justify-between gap-2`

**Severity tokens** (filled chrome, not `AlertComponent`’s subtle in-page styles):

| Severity | Strip | Icon |
|---|---|---|
| `info` | `bg-info text-white` | info-circle (AlertComponent info path) |
| `warning` | `bg-warning text-amber-950` | warning triangle. Project has **no** `text-warning-foreground` token; use `text-amber-950` for contrast on `--color-warning` `#d97706` (same idea as ContextBanner `text-amber-950`) |
| `critical` | `bg-danger text-white` | error X-circle |

Learn more / +N more / Dismiss inherit `currentColor`. Learn more: underline, `font-medium`, `target="_blank"` `rel="noopener"`.

Dismiss control: text button, right-aligned, visually like ContextBanner’s right action but quieter — `text-sm font-medium` + hover opacity, **not** a filled `btn-primary`. Use `common.actions.dismiss` (“Dismiss”). `button_to` so it works without Stimulus.

`+N more`: native `<details>` / `<summary>`. No Stimulus. Summary text: `+%{count} more` (`comp_platform.announcement_banner.more_count`). Open state lists the other bodies in a stacked column under the summary (`mt-2 flex flex-col gap-1 text-sm`). Closing `<details>` is the only collapse.

```
Desktop (one notice):
┌─────────────────────────────────────────────────────────────┐
│ ℹ  English/Chinese body here.  Learn more              [✕] │
└─────────────────────────────────────────────────────────────┘

Desktop (3 live, 1 showing):
┌─────────────────────────────────────────────────────────────┐
│ ⚠  Body of newest.  Learn more   ▸ +2 more            [✕] │
└─────────────────────────────────────────────────────────────┘
  details[open]:
┌─────────────────────────────────────────────────────────────┐
│ ⚠  Body of newest.  Learn more   ▾ +2 more            [✕] │
│      • Second-newest body                                   │
│      • Third body                                           │
└─────────────────────────────────────────────────────────────┘

Mobile (flex-wrap):
┌──────────────────────────────────────┐
│ ℹ  Body wraps onto as many lines     │
│    as needed.                        │
│    Learn more   +2 more        [✕]   │
└──────────────────────────────────────┘
```

Dismiss stays in the first wrap row’s trailing cluster (`ml-auto` on the actions group) so it does not drop off-screen.

**Empty / loading / error**

| State | Treatment |
|---|---|
| `render?` false | component outputs nothing |
| After dismiss | redirect back; session excludes that id; next undismissed row (if any) becomes primary |
| Dismiss unknown / not-targeted id | server ignores (no leak); redirect back; banner unchanged |
| Vendor-down | N/A — no external vendor |

Banner is not dismissible via Escape or click-outside. Session-only: returns on next login.

---

## 3. Interaction flow

Base host: `/81721200/admin/...` for CRUD. Tenant admin URLs use that tenant’s `:customer_id`.

### US-1 Owner lists announcements

1. Start: signed in as owner on `81721200`, URL `/81721200/admin/maintenance/platform/announcements`
2. Sidebar: Maintenance → Platform → Announcements (after Customers)
3. Outcome: index table, newest-updated or default resolver/table sort as implemented (prefer `updated_at desc` or `created_at desc` to match “newest first” mental model)
4. Failure: tenant admin or member hitting this URL → existing platform-owner denial (`common.errors.authorization.platform_owner_required` / access denied). Anonymous → sign-in redirect

### US-2 Owner creates for all tenants

1. Index → **New announcement**
2. URL: `.../announcements/new`
3. Fill title, both bodies, leave Audience = All, Status = Published (optional schedule)
4. **Create announcement**
5. Success → redirect index + flash “Announcement created.”
6. Failure (blank body, bad URL, ends before starts) → re-render new with Alert; no persist

### US-3 Owner creates for selected customers

1. New form → click **Selected customers**
2. Picker appears; type in filter; check ≥1 customer
3. Submit
4. Success → index + flash
5. Failure (zero checked) → Alert; picker stays open; checks preserved
6. Filter-hiding a checked row does **not** uncheck it; submit still includes that id

### US-4 Owner edits / deletes

1. Index row **Edit** or show → **Edit**
2. URL `.../announcements/:id/edit`
3. Change fields / retarget; **Save changes** → show or index + “Announcement updated.”
4. Index **Delete** → confirm → destroy → index + “Announcement deleted.”
5. Switching Selected → All on save clears join rows (activity). Switching All → Selected requires ≥1 id

### US-5 Tenant admin sees and dismisses the banner

1. Start: tenant admin, any admin dashboard URL using `ShellComponent` (e.g. `/:cid/admin`)
2. If live + targeted + not session-dismissed: banner is the top strip
3. Locale `zh*` → `body_zh`; else `body_en`
4. **Learn more** (if URL) → new tab
5. **+N more** → native `<details>` opens; no navigation
6. **Dismiss** → POST `/:cid/admin/platform_announcement_dismissals` `{ platform_announcement_id }`; session append; redirect back
7. Outcome: that id gone; if others remain, next newest is now primary (`+N` decrements)
8. New browser session / re-login → dismissed ids gone; banner returns
9. Failure: POST of an id Resolver would not return → ignore, redirect back, no flash leak
10. Member on member shell → no banner
11. Owner on `81721200` not acting-as → no banner
12. Owner **Act As** customer C (context banner visible) → if C is targeted, announcement banner sits **above** the amber acting-as strip

### US-6 Multiple live notices

1. Resolver order: `created_at DESC, id DESC`, minus session dismissed
2. Primary = first; `+N more` lists the rest
3. Dismiss primary only (expanded rows have no dismiss control)
4. After dismiss + redirect, former #2 is primary

### US-7 Schedule window

1. Published with future `starts_at` → not in Resolver → no banner; show page badge “Scheduled”
2. After `starts_at`, next page load shows it (no cron, no websocket)
3. After `ends_at`, it disappears; show badge “Ended”

### US-8 Permission matrix (no extra UI)

| Actor | Platform CRUD | Dismiss POST | Sees banner |
|---|---|---|---|
| owner on 81721200 | yes | yes (but banner hidden unless acting-as) | only when acting-as a targeted customer |
| owner acting-as C | no (platform prefix still 81721200-gated; they use 81721200 URLs for CRUD) | yes on C’s admin URL | yes if C targeted |
| tenant admin | no | yes | yes if targeted |
| member | no | no (`require_admin_or_owner!`) | no |
| anonymous | redirect sign-in | redirect sign-in | no |

---

## 4. Component reuse map

| Piece | Reuse | New |
|---|---|---|
| Page chrome (A–D) | `AdminPageComponent`, `BreadcrumbsComponent`, `ButtonComponent` | — |
| Index table | `AdminTableComponent` (`type: :badge`, `:datetime`, search, filters, `row_path`, `row_actions`, `empty_state`) | — |
| Severity / status chips | `BadgeComponent` (`:info` / `:warning` / `:danger` / `:success` / `:default`) | — |
| Form errors | `AlertComponent` (`type: :error`) | — |
| Form fields | existing `form-label`, `form-label-required`, `input-field`, `card`, `section-header`, `btn btn-primary` / `btn-secondary` | `Admin::Maintenance::Platform::AnnouncementFormComponent` — props: `announcement:`, `customers:`, `customer_id:` |
| Audience radios | billing plan availability **card-radio** Tailwind pattern | (inside form component) |
| Customer list + filter | — | `Platform::AnnouncementCustomerPickerComponent` — props: `customers:`, `selected_ids:`, `param_name:` (default `platform_announcement[customer_ids][]`) |
| Shell insert | `ShellComponent` ERB — render banner **first** | `Platform::AnnouncementBannerComponent` — props: none required; reads `Current` + session dismissed ids + Resolver |
| Acting-as strip | `Platform::ContextBannerComponent` unchanged, still second | — |
| Dismiss button | Rails `button_to` (no new JS) | — |
| +N more | native `<details>` | — |
| Flash | dashboard layout | — |
| Sidebar leaf | `MaintenanceContributor` (routes/security task) | icon key `:announcements` (megaphone path) |

**Do not** install `@shadcn/alert` / any React package. Map shadcn Alert to this ViewComponent strip: icon + description + optional action cluster, severity variants via the token table above.

**Do not** invent `Dashboard::TableComponent` / `Dashboard::PageHeaderComponent` — this app uses `AdminTableComponent` / `AdminPageComponent`.

Thin views (routes task): `index` / `new` / `edit` / `show` only render the components above, same as billing plans `new.html.erb`.

---

## 5. Tailwind & Stimulus notes

### Tailwind (match siblings)

- Page header: AdminPage already uses `text-subtitle`, `text-body-sm`, `gap-4 mb-6`
- Form width: `mx-auto max-w-3xl`; sections `card overflow-hidden`; headers `border-b border-border-subtle px-6 py-4`; bodies `space-y-5 px-6 py-5`
- Grids: `grid grid-cols-1 gap-4 md:grid-cols-2` for paired fields (severity/status, starts/ends)
- Captions: `mt-1.5 text-caption`
- Footer: `flex items-center justify-end gap-3` — **gap, not space-x**
- Picker list: `max-h-72 overflow-y-auto rounded-lg border border-border-subtle divide-y divide-border-subtle`; rows `px-3 py-2.5 flex items-center gap-3 hover:bg-surface-hover`
- Checkbox: `h-4 w-4 rounded border-border-strong text-accent focus:ring-accent` (plan form)
- Filter input: AdminTable search treatment — `input-field w-full pl-9` + search icon `absolute left-3 … text-text-muted`
- Banner: `w-full px-4 py-2 flex flex-wrap items-center justify-between gap-2`; left `flex items-start sm:items-center gap-2 min-w-0 flex-1`; icon `size-5 shrink-0`; body `text-sm font-medium min-w-0`; actions `flex items-center gap-2 shrink-0 ml-auto`
- Banner is **not** `rounded-lg` / `border` / `mb-6` (those belong to in-page `AlertComponent`). It is a full-bleed chrome strip like ContextBanner (`sticky` is optional and **not** required — ContextBanner uses `sticky top-0 z-50`; the announcement banner sits above it in document order. Do **not** add a second sticky competing for `top-0`. Let both sit in normal column flow so the viewport-locked shell still clips correctly.)
- Show `dl`: `text-text-tertiary` dt / `text-text-primary` dd
- No custom CSS file. No `space-y-*` on new stacks — `flex flex-col gap-*`
- No raw `bg-blue-500` / `bg-red-500` — semantic `info` / `warning` / `danger` tokens only

### Stimulus

**1. `platform_announcement_customer_picker_controller.js` (required, 100% Vitest lines + branches)**

Mount on the picker root (and, if convenient, on the Audience card so radios can hide the list).

| Kind | Name | Role |
|---|---|---|
| target | `filter` | search `<input>` |
| target | `row` | each customer `<label>` / row; each row exposes a searchable string via `data-platform-announcement-customer-picker-label-param` or a child text node the controller reads |
| target | `empty` | “No matching customers” node, `hidden` when any row visible |
| target | `panel` | optional; the checkbox list wrapper |
| target | `count` | optional; “%{count} selected” |
| action | `filter` / `input` | `input->…#filter` — hide rows whose name/id do not include the query (trim, case-insensitive) |
| action | `toggleAudience` | `change->…#toggleAudience` on the two radios — `panel` / picker `hidden` when value is `all` |
| action | `recount` | `change->…#recount` on checkboxes — update selected count (visible or not) |
| value | `filterPlaceholder` | English default `"Filter customers..."`; server `data-*-filter-placeholder-value="<%= t(...) %>"` |
| value | `noMatch` | default `"No matching customers"` |
| value | `selectedCount` | ICU default `"{count} selected"`; `.replace("{count}", n)` — **no** literal UI strings in JS |

If selected-count is omitted to keep branches smaller, that is acceptable; filter + empty + audience toggle are required.

**2. Banner** — **no** Stimulus. `<details>` for expand; `button_to` for dismiss.

**3. Do not** add a form-wide controller unless audience-toggle cannot live on the picker controller.

### I18n (exact English values)

English = the string that would otherwise have been hard-coded. Add matching `zh-CN` in the same files.

**`chrome.sidebar.maintenance.announcements`**

- en: `Announcements`
- zh-CN: `公告`

**`maint_platform.announcements.*`** (CRUD)

| Key | en |
|---|---|
| `breadcrumb.maintenance` | Maintenance |
| `breadcrumb.announcements` | Announcements |
| `index.title` | Announcements |
| `index.description` | Publish time-bounded notices to tenant admins. |
| `index.new_action` | New announcement |
| `index.search_placeholder` | Search by title... |
| `index.empty_title` | No announcements yet |
| `index.empty_description` | Create a notice to display on tenant admin dashboards. |
| `index.empty_action` | New announcement |
| `index.delete_confirm` | Delete "%{title}"? This cannot be undone. |
| `index.columns.title` | Title |
| `index.columns.severity` | Severity |
| `index.columns.status` | Status |
| `index.columns.audience` | Audience |
| `index.columns.starts_at` | Starts |
| `index.columns.ends_at` | Ends |
| `index.columns.updated_at` | Updated |
| `index.audience_all` | All |
| `index.audience_selected` | "%{count} customers" |
| `index.filters.status` | Status |
| `index.filters.severity` | Severity |
| `new.title` | New announcement |
| `new.description` | Write a bilingual notice and choose who should see it. |
| `edit.title` | Edit announcement |
| `edit.description` | Update the notice content, schedule, or audience. |
| `form.content` | Content |
| `form.display` | Display |
| `form.audience` | Audience |
| `form.title` | Title |
| `form.body_en` | English body |
| `form.body_zh` | Chinese body |
| `form.link_url` | Learn more URL |
| `form.link_url_hint` | Optional. Must start with http:// or https://. |
| `form.severity` | Severity |
| `form.status` | Status |
| `form.starts_at` | Starts at |
| `form.ends_at` | Ends at |
| `form.window_hint` | Leave blank for no start or end limit. |
| `form.audience_all` | All customers |
| `form.audience_all_hint` | Every tenant, including customers created later. |
| `form.audience_selected` | Selected customers |
| `form.audience_selected_hint` | Only the customers checked below. |
| `form.create` | Create announcement |
| `form.update` | Save changes |
| `severities.info` | Info |
| `severities.warning` | Warning |
| `severities.critical` | Critical |
| `show.scheduled` | Scheduled |
| `show.ended` | Ended |
| `show.targets` | Target customers |
| `show.targets_all` | Every tenant, including customers created later. |
| `show.targets_empty` | No customers selected. |
| `show.learn_more` | Learn more |
| `picker.filter_placeholder` | Filter customers... |
| `picker.no_match` | No matching customers |
| `picker.none_available` | No customers available. |
| `picker.selected_count` | "{count} selected" |

Reuse: `common.actions.cancel`, `common.actions.edit`, `common.actions.delete`, `common.actions.dismiss`, `common.status.draft`, `common.status.published`, `common.status.live`, `common.labels.status`.

**`maint_platform.flash.announcements.*`**

| Key | en |
|---|---|
| `created` | Announcement created. |
| `updated` | Announcement updated. |
| `deleted` | Announcement deleted. |
| `invalid` | Please fix the errors below. |

**`comp_platform.announcement_banner.*`**

| Key | en |
|---|---|
| `dismiss` | Dismiss |
| `learn_more` | Learn more |
| `more_count` | +%{count} more |

Banner **bodies** are `body_en` / `body_zh` data. Never put tenant-facing notice text in YAML.

Stimulus values use the picker keys via `data-platform-announcement-customer-picker-*-value`.

---

## 6. Frontend implementation notes (non-layout)

- Form `form_with` scope: `:platform_announcement` so params match `Save.call`.
- Datetime fields: submit values the contract can parse; do not invent a timezone picker.
- Title is never rendered in the banner.
- Soft-deleted customers are omitted from the picker (same visibility as Customers index, not trash).
- `81721200` stays in the picker; targeting it only affects a tenant admin of that customer, not the owner home context.
- Vitest: filter show/hide, empty-state toggle, audience panel hide, case-insensitive match, empty-query shows all — 100% lines and branches. No `v8 ignore`.
- Do not wire the topbar notifications bell.

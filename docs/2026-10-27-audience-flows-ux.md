# Audience Flows — UX spec (Plan 2, Task 0)

**Date:** 2026-10-27
**Status:** Ready for frontend
**Behaviour source:** `docs/2026-10-27-audience-flows-design.md` §§3.1, 3.2, 3.8.5, 3.9, 5
**Plan:** `docs/2026-10-27-audience-flows-plan-2-audiences.md` (Tasks 2, 6, 7, 8 build from this)
**Audience roles:** `owner`, `admin`, `member` only. No new roles.

shadcn/ui primitives (Switch, Input, Select, Badge, Alert, Tooltip) are the interaction reference. Delivery is ViewComponent + Tailwind + Stimulus. Do not add React, custom CSS, or a new JS framework.

All copy is I18n (`en` + `zh-CN`). English values are byte-identical to the strings in §6. JS never contains literal UI text: Stimulus Values with English `default:` plus server-passed `data-*-value`.

---

## 1. Surface inventory

| # | Surface | URL | nav_area | Roles |
|---|---|---|---|---|
| A | Distribution card (page show) | `/:cid/admin/maintenance/pages/:id` (and the platform-prefix twin) | admin / Maintenance pages | `admin` or `owner`. Shared-page identity (audiences + action key) is editable only on the platform prefix (`publishing_editable?`). |
| B | Settings / Member hub | `/:cid/admin/settings/member` | Settings | `admin` or `owner` |
| C | Settings / Member · Pages source | `/:cid/admin/settings/member/sources/pages` | Settings | `admin` or `owner` |
| D | Settings / Member · entity surface form (Row action group) | `/:cid/admin/settings/member/sources/entities/surfaces/:key` | Settings | `admin` or `owner` |
| E | Member entity index | `/:cid/member/:surface_key` | member | `member` (admin GET preview unchanged) |
| F | Composite list tile | rendered inside a public or member page | public (or member, when the page is) | whoever can open that page |

Out of scope for this spec: a builder UI for composite `config.row_action` (authored as JSON). Flash strings `public_views.actions.continue_here` / `not_for_your_account` are already fixed in design §5 (Task 3).

---

## 2. Layout spec per surface

### 2.1 Distribution card — `Pages::DistributionCardComponent`

Mount: existing card in the page-show main column (`lg:col-span-2` of `grid grid-cols-1 lg:grid-cols-3 gap-6 items-start`).

**Change from today:** three independent audience switches (admin is no longer locked). Hierarchical member↔public cascade is gone. Last remaining audience cannot be turned off. Action key + siblings list are new.

#### ASCII — desktop / tablet (`sm:` and up)

```
+------------------------------------------------------------------+
| Publishing & access                    [Launched|Not launched]   |
|                                           [Launch|Take offline]  |
+------------------------------------------------------------------+
| Public URL   https://…/…/page/<uuid>                    [Copy]   |  ← only if launched AND public is on
|              (or “Launch this page to generate a public URL.”)   |
+------------------------------------------------------------------+
| Who can open                                         Saving…     |
+------------------------------------------------------------------+
| ● Admin                                                          |
|   Signed-in admins and owners of this organization.              |
|                                              [switch]  [Open]    |
|   URL  https://…/:cid/admin/maintenance/pages/:id/render  [Copy] |  ← only when switch is on
+------------------------------------------------------------------+
| ● Member                                                         |
|   Signed-in members of this organization.                        |
|                                              [switch]  [Open]    |
|   URL  https://…/:cid/member/pages/:id                    [Copy] |  ← only when switch is on
+------------------------------------------------------------------+
| ● Public                                                         |
|   Anyone, including people who aren't signed in.                 |
|                                              [switch]  [Open]    |
|   URL  https://…/:cid/page/<uuid>                         [Copy] |  ← only when switch is on
+------------------------------------------------------------------+
| Action key                                                       |
| [ enroll                                           ]             |
| Start with a letter. Use only lowercase letters, numbers         |
| and underscores.                                                 |
| Action URL  https://…/:cid/actions/enroll                 [Copy] |  ← only when a saved key is present
+------------------------------------------------------------------+
| Other pages in this action                                       |
| Enroll (member)          [Admin] [Member]                        |
| Public enroll            [Public]            Not launched        |
+------------------------------------------------------------------+
```

When only one audience is on, that switch is disabled. Hover/focus shows the last-audience tooltip (server-passed). The other two switches stay enabled.

#### ASCII — mobile (`< sm`)

```
+--------------------------------------+
| Publishing & access     [badge]      |
| [Launch]                             |  full-width secondary/success
+--------------------------------------+
| Public URL                           |
| https://…/page/<uuid>   (break-all)  |
| [Copy]                               |
+--------------------------------------+
| Who can open              Saving…    |
+--------------------------------------+
| ● Admin                              |
|   hint (wraps)                       |
|   [switch]                           |
|   [Open]                             |
|   URL  https://…        [Copy]       |  full-width, stacked
+--------------------------------------+
| ● Member   (same stack)              |
| ● Public   (same stack)              |
+--------------------------------------+
| Action key                           |
| [ enroll                    ]        |
| help (wraps)                         |
| Action URL (break-all)      [Copy]   |
+--------------------------------------+
| Other pages in this action           |
| Enroll (member)                      |
| [Admin] [Member]                     |
+--------------------------------------+
```

#### Regions ↔ data

| Region | Source |
|---|---|
| Header title | `comp_misc.distribution.header_title_html` |
| Launch badge | existing `maint_core.pages.show.launched` / `not_launched` via `BadgeComponent` `:success` / `:default` `:sm` |
| Launch / Take offline | existing `button_to` + `btn btn-success btn-sm` / `btn btn-secondary btn-sm` |
| Top public-URL strip | keep today's block; show only when `page.launched?` and `page.visible_to?("public")` |
| Audience section title | `comp_misc.distribution.audience_section` |
| Saving status | `data-page-visibility-target="status"` + `saving` value |
| Dot | `DOT_CLASSES` unchanged: admin `bg-accent`, member `bg-member-accent`, public `bg-success` |
| Audience label / hint | `comp_misc.distribution.labels.*` / `hints.*` (hints rewritten — exact set, not hierarchy) |
| Switch checked | `page.visible_to?(key)` |
| Switch locked | JS: exactly one of the three is checked. Server initial state must match. |
| Open link | launched **and** that audience is on. Admin → `admin_maintenance_page_render_path`; member → `member_page_path`; public → public UUID URL |
| Per-audience URL row | same href as Open; shown only when the switch is on. Copy uses existing `click-to-copy` + `common.actions.copy` / `copied` |
| Disabled-reason (no Open) | `comp_misc.distribution.not_launched` when the page is offline; omit the URL row when the switch is off (do **not** show today's “Not visible to %{audience}” on an off row — the off switch is the signal) |
| Action key | `page.action_key`. Field name `page[action_key]`. Blank stores nil |
| Action URL | `page_action_path(customer_id:, action_key:)` when a **saved** key is present |
| Siblings | `Pages::ActionResolver.siblings(page)` — other active pages in the same action and owner (launched or not). Each row: `page.name` + `BadgeComponent` `:sm` for each of `sibling.visible_audiences` (admin `:primary`, member `:info`, public `:success`) + optional muted `not_launched` |
| Sibling link | `admin_maintenance_page_path(customer_id, sibling)` so an admin can jump to a colliding page |

#### Switch (shadcn Switch → existing toggle track)

Do **not** keep today's square checkbox. Use the same track as the entity-attribute owner toggle and `FormFields::ToggleFieldComponent`:

```
label.relative.inline-flex.min-h-11.shrink-0.items-center.cursor-pointer
  input.sr-only.peer  type=checkbox  name="page[visible_audiences][]"  value=<key>
  span.relative.h-6.w-11.rounded-full.bg-surface-active.transition-colors
       .peer-checked:bg-accent.peer-focus-visible:ring-2.peer-focus-visible:ring-accent
       .peer-focus-visible:ring-offset-2
       .after:absolute.after:left-0.5.after:top-0.5.after:size-5.after:rounded-full
       .after:bg-white.after:transition-transform.after:content-['']
       .peer-checked:after:translate-x-5
```

No “Visible” / “Always on” caption beside the track. The audience name is the label. Drop `comp_misc.distribution.admin_always_visible_aria` and `always_on`.

Drop the always-posted hidden `<input name="page[visible_audiences][]" value="admin">`. Every checked audience is posted by JS-maintained hidden inputs (see §5) so a disabled last switch still submits.

#### Action key (shadcn Input)

```
label.form-label  → action_key_label
input.input-field.font-mono.text-sm.max-w-md
  name="page[action_key]"
  autocomplete="off" spellcheck="false"
  placeholder = action_key_placeholder
  aria-describedby="page-action-key-help"
p#page-action-key-help.text-caption.text-text-muted.mt-1  → action_key_help
```

Submit on `change` (blur), never on `input`. Format: `/\A[a-z][a-z0-9_]{1,62}\z/`. Invalid key is a server error (below).

#### Siblings list

Render the section only when `page.action_key` is present.

```
h3.text-sm.font-medium.text-text-primary.px-5.pt-4  → siblings_heading
ul.divide-y.divide-border-subtle
  li.px-5.py-3.flex.flex-col.gap-1.5.sm:flex-row.sm:items-center.sm:justify-between
    a.text-sm.font-medium.text-accent.hover:underline.break-words  → sibling.name
    span.flex.flex-wrap.items-center.gap-1.5
      BadgeComponent × visible_audiences
      span.text-caption.text-text-muted  → not_launched (offline only)
p.px-5.pb-4.text-caption.text-text-muted  → siblings_empty   (when the list is empty)
```

#### Empty / loading / error

| State | UI |
|---|---|
| Empty siblings, key set | `siblings_empty` caption. No list. |
| No action key | Hide action URL and the whole siblings section. |
| Saving | Unhide `status` with `saving` value. Existing behaviour. |
| Success | Layout `AlertComponent` `:success` auto-dismiss — existing `maint_core.flash.page_visibilities.updated`. |
| `page_audiences_blank` | Layout `AlertComponent` `:error` via existing `update_failed` (`%{errors}` interpolates `maint_core.errors.validations.page_audiences_blank`). The last-switch lock should make this unreachable from the UI; a crafted request still lands here. Do **not** add a second inline banner. |
| `action_audience_taken` | Same layout flash (`maint_core.errors.page_launch.action_audience_taken` with `%{audience}` / `%{action}`). After the redirect the switches revert to the saved set. The siblings list (now showing the colliding page) is the recovery path. |
| `page_action_key_invalid` | Same layout flash (`maint_core.errors.validations.page_action_key_invalid`). Input reverts to the saved key. |
| Shared page on a tenant URL | Existing `shared_page_readonly` refusal. Card is read-only (`publishing_editable?` false): switches disabled, action key `readonly`, no Launch. |
| Last audience | Switch disabled, `opacity-60 cursor-not-allowed` on the track wrapper, `data-tooltip` + `aria-label` = `last_audience` (see §5). |

#### Actions

| Kind | Control | Where |
|---|---|---|
| Primary | Launch (`btn btn-success btn-sm`) | Header, when offline and editable |
| Secondary | Take offline (`btn btn-secondary btn-sm`); Open (text link `text-sm font-medium text-accent hover:underline`); Copy | Header / URL rows |
| Destructive | none on this card | — |
| Implicit | Audience switch and action-key `change` auto-POST to `admin_maintenance_page_visibility_path` (`page[visible_audiences][]`, `page[action_key]`) | Stimulus `page-visibility#sync` |

---

### 2.2 Settings / Member hub — existing `members#show`

No new chrome. After Task 6 registers `Member::Sources::Pages` (`position` after entities, e.g. `30`), `MembersController` already maps `Member::Surfaces.sources` into hub cards.

Reuse `Admin::Settings::MemberHubCardComponent` + `SettingRowComponent`:

- Label = `settings_people.sources.pages.name`
- Description = `settings_people.sources.pages.description`
- Meta = `settings_people.pages_count` + `visible_count` (same as entities)
- CTA = existing Configure (`comp_admin.member_hub_card.configure`) → `/admin/settings/member/sources/pages`

Mobile: `SettingRowComponent` already stacks (`flex-col gap-4` → `sm:flex-row`). Do not change.

---

### 2.3 Settings / Member · Pages source — `MemberSourceListComponent`

URL: `/:cid/admin/settings/member/sources/pages`

Add a **Pages** tab after Entities. Tab array becomes `%w[builtin modules entities pages]`. Labels stay `t("settings_people.sources.#{key}.name")`. `SectionNavComponent` already horizontal-scrolls on mobile (`overflow-x-auto … min-w-max`).

Each launched page with the member audience is one `Admin::Settings::MemberSourceRowComponent`:

```
+--------------------------------------------------------------+
| Enroll in course                                             |
|   [☑ Visible to members]            [Display settings]       |
+--------------------------------------------------------------+
```

- Label = page name (`BuiltinSurface` label).
- Toggle = existing checkbox + `auto-submit` (do **not** switch this row to the track toggle — keep parity with entity/module rows).
- `default_enabled: false` — first visit shows every page off until an admin turns it on.
- Display settings → Navigation + Advanced only (no List display, Record details, Empty state, Row action). Those sections are entity-surface only.

#### Empty / error

| State | UI |
|---|---|
| No launched member pages | Existing `settings_people.no_pages` (`text-sm text-text-secondary`) |
| Search miss | Existing `list-filter` empty target, same copy |
| Toggle save | Existing `admin_settings.flash.member_sources.saved` |

---

### 2.4 Settings / Member · entity surface form — Row action group

Mount: new `Admin::Settings::SectionComponent` on `Admin::Settings::MemberSurfaceFormComponent`, **only** when `presenter.effective.source_key == :entities`. Place it after **List display** and before **Record details**.

Page-link surfaces (`source_key == :pages`) and builtin/module surfaces never render this group.

#### ASCII — desktop / tablet (`sm:`)

```
+--------------------------------------------------------------+
| Row action                                                   |
| Each list row links to this action with the row id filled    |
| in on the target field.                                      |
+--------------------------------------------------------------+
| Action                         Target field                  |
| [ enroll                 ▾]    [ course                   ]  |
|                                The field slug that receives  |
|                                the row id.                   |
| Button label                                                 |
| [ Open                                        ]              |  placeholder = default label
| Optional. Leave blank to use “Open”.                         |
+--------------------------------------------------------------+
```

#### ASCII — mobile

```
+------------------------------+
| Row action                   |
| help (wraps)                 |
| Action                       |
| [ enroll              ▾]     |
| Target field                 |
| [ course                   ] |
| field help (wraps)           |
| Button label                 |
| [ Open                     ] |
+------------------------------+
```

#### Fields

| Field | Control (shadcn → project) | name= | Rules |
|---|---|---|---|
| Action | native `<select class="input-field">` (same as the icon select on this form) | `member_settings[rows][0][row_action_key]` | Options = action keys that have a launched member page for this customer (Task 7 / `ActionResolver`). First option value `""` labelled `row_action_none` (“None”). |
| Target field | `<input type="text" class="input-field font-mono text-sm">` | `member_settings[rows][0][row_action_field]` | Slug `Pages::FormParams::SLUG` = `[a-zA-Z0-9_]+`. Placeholder `course`. |
| Button label | `<input type="text" class="input-field">` | `member_settings[rows][0][row_action_label]` | Optional, ≤ 60 characters. Placeholder = `t("member.entity_surfaces.row_action_default")` (“Open”). |

Grid: `grid grid-cols-1 sm:grid-cols-2 gap-4` for Action + Target field; Button label is `sm:col-span-2`. Labels use `form-label`. Help uses `text-sm text-text-secondary mt-1` (same as `settings_people.order_hint`).

No Stimulus on this group. Save is the existing form footer (`common.actions.cancel` / `save`).

#### Empty / error

| State | UI |
|---|---|
| No launched member actions | Select contains only “None”. Under the select: `comp_admin.member_surface_form.row_action_empty`. Target field and label stay editable so a later key can be typed against a planned field; Save still requires a real key + field together. |
| `row_action_invalid` | `AlertComponent` `:error` at the **top of the form** (422 re-render). Repeat the same sentence as `text-sm text-danger mt-1` under Action and under Target field (`aria-invalid="true"` + `ring-danger` on those two inputs). Copy: `admin_settings.errors.validations.row_action_invalid`. |
| Label too long | Same alert + field error on the label input (Task 7 contract). |
| Success | Existing `admin_settings.flash.member_surfaces.saved`. |

A row action is the pair (key, field). Clearing Action to “None” and leaving field/label blank is valid (removes the overlay). Filling only one of key/field is invalid.

---

### 2.5 Member entity index — `Member::SurfaceIndexComponent` + `IndexTableComponent`

Pass `row_action:` (`{ action_key:, field:, label: }` or `nil`) from `Member::EffectiveSurface#row_action` through `SurfaceIndexComponent` into `IndexTableComponent`.

Href for a record: `Pages::ActionLink.path(customer_id:, action_key:, prefill: { field => record.id })`.

Do **not** replace the existing View link (`common.actions.view` + chevron). Row action and View are different destinations.

#### Desktop / tablet table (`md:` and up)

Keep the current table. Trailing cell becomes two links, row action first:

```
td.px-5.py-4.text-right
  div.flex.items-center.justify-end.gap-3
    a.chrome.text_link_class.text-site-sm   → row_action.label   (only if row_action present)
    a.chrome.text_link_class.text-site-sm   → View + chevron    (always)
```

Table wrapper: `hidden md:block overflow-x-auto` (today it is always visible).

Empty trailing `<th class="px-5 py-3">` stays empty (both actions are labelled).

#### Mobile stacked cards (`< md`)

New markup in `IndexTableComponent` (no new component):

```
<div class="md:hidden space-y-3">
  <% records.each do |record| %>
    <article class="<%= chrome.card_class(:compact) %> flex flex-col gap-3">
      <!-- first column as title -->
      <p class="text-site-base font-medium break-words"><%= first column value %></p>
      <!-- remaining columns -->
      <dl class="grid grid-cols-1 gap-2">
        <div>
          <dt class="<%= chrome.label_class %>"><%= col[:label] %></dt>
          <dd class="text-site-sm break-words"><%= value %></dd>
        </div>
      </dl>
      <div class="flex flex-col gap-2 border-t pt-3 <%= chrome.hairline_class %>">
        <!-- row action, if present: full-width touch target -->
        <a class="inline-flex min-h-11 w-full items-center justify-center rounded-full
                  px-4 text-site-sm font-medium <%= theme outline / secondary %>">
          <%= label %>
        </a>
        <a class="<%= chrome.text_link_class %> min-h-11 justify-center">
          <%= View + chevron %>
        </a>
      </div>
    </article>
  <% end %>
</div>
```

Use `chrome.secondary_button_class` for the row-action button on cards (`h-12 w-full` is the project’s mobile CTA). View stays a text link under it.

If `row_action` is nil, the card footer is View only.

#### Empty / loading / error

| State | UI |
|---|---|
| No records | Existing `Member::EmptyStateComponent` — no table, no cards, no row action |
| No row action configured | Table and cards render exactly as today (View only) |
| Prefill / 404 on the action | The target page or action router handles it; the index does not flash |

---

### 2.6 Composite list — `PageContentGenerator::CompositeRenderer#render_list_module_html`

No builder UI. When a record’s data includes `row_action_path` (Task 7), append one trailing column.

Header cell (matches existing `th` utilities):

```
th.px-4.py-3.text-left.text-xs.font-medium.text-gray-500.uppercase.tracking-wider
  span.sr-only  → public_views.composite.row_action_default
```

Body cell:

```
td.px-4.py-3.text-sm.whitespace-nowrap
  a.text-sm.font-medium.text-indigo-600.hover:underline
    href = ERB::Util.html_escape(record.data.row_action_path)
    data-action="click->list-module#rowAction"
    data-record-id="<id>"
    data-row-action="open"
    → public_views.composite.row_action_default   (or config.row_action.label if present)
```

`list-module#rowAction` already `stopPropagation()` and does **not** `preventDefault()`, so the browser follows `href` and the row does not fire `selectRow`. No new Stimulus method unless a click still bubbles — then add an early `if (event.target.closest("a")) return` in `selectRow` and cover it in Vitest.

Do not add the column when no record has a path (keeps today’s markup for lists without a row action).

Empty list: existing `public_views.composite.no_records` centered cell — no action column.

---

## 3. Interaction flow

### 3.1 Admin sets exact audiences (user story: enroll has three pages)

1. Start `GET /:cid/admin/maintenance/pages/:id` (admin or owner).
2. Card shows the saved set. Admin is a normal switch.
3. Toggle Member on → `page-visibility#sync` → PATCH `visible_audiences[]=admin&visible_audiences[]=member` + `action_key` → redirect, notice “Visibility updated.”, Member URL row appears, Open works after launch.
4. Toggle Public on independently (Member does **not** auto-check). Public URL strip appears once launched.
5. Uncheck Admin. If Member and Public remain, Admin turns off. If Admin was the last one, the switch does not move and the tooltip explains why.
6. Failure — collision: enable Member on a second live `enroll` page → flash `action_audience_taken` → switches revert → siblings list names the other live page.
7. Failure — blank audiences: only via a crafted request; flash `page_audiences_blank`.
8. Permission: member role never reaches this URL (existing admin guard). Shared page on a tenant URL: card read-only.

### 3.2 Admin assigns an action key

1. Same card. Type `enroll`, tab out (`change`).
2. PATCH includes `page[action_key]=enroll`.
3. Success: Action URL row and siblings section appear.
4. Failure — format: flash `page_action_key_invalid`; input shows the previous saved value.
5. Blank + blur: stores nil; Action URL and siblings hide.

### 3.3 Admin enables a member page in navigation (§3.8.5)

1. `GET /:cid/admin/settings/member` → Pages hub card.
2. Configure → `…/sources/pages`.
3. Each launched member page is a row, toggle off by default.
4. Check “Visible to members” → `auto-submit` PATCH → page appears in `/:cid/member` nav at `…/member/pages/:id`.
5. Empty: “No pages to display.”
6. A member of another tenant never sees the link (Task 6).

### 3.4 Admin configures a Courses row action (§3.9)

1. `GET /:cid/admin/settings/member/sources/entities/surfaces/courses`.
2. Row action group is visible (entity surface).
3. Action = `enroll`, Target field = `course`, Button label blank.
4. Save → notice “Surface saved.”
5. Failure — key without field: 422, `AlertComponent` + field errors with `row_action_invalid`.
6. A member cannot POST this URL (existing guard).

### 3.5 Member uses a row action

1. `GET /:cid/member/courses` (member session).
2. Desktop: last cell shows “Open” then “View”.
3. Mobile: card footer shows full-width “Open”, then “View”.
4. Open → `/:cid/actions/enroll?prefill[course]=<id>` → redirect to the member enroll page with the course filled (Tasks 7–9).
5. View → existing `/:cid/member/courses/:id`.
6. No row action configured: View only, both breakpoints.

### 3.6 Public / member composite list

1. Open a page that contains a list tile with `config.row_action`.
2. Trailing “Open” (or configured label) per row.
3. Click the link: navigation to the action URL; row is not selected.
4. Click elsewhere on the row: existing `selectRow` highlight.

### 3.7 Failure matrix

| Failure | Where it shows |
|---|---|
| `page_audiences_blank` | Layout flash on page show (`update_failed` + maint_core string) |
| `action_audience_taken` | Same flash; siblings list is the recovery UI |
| `page_action_key_invalid` | Same flash; action key reverts |
| Shared identity write on tenant URL | Existing `shared_page_readonly` flash; card stays read-only |
| `row_action_invalid` | `AlertComponent` on the entity surface form + field errors |
| Action router 404 / sign-in | Target surface / Task 3 — not this card |
| Vendor-down | N/A (no vendor on these surfaces) |

---

## 4. Component reuse map

| Piece | Reuse | New |
|---|---|---|
| Distribution card chrome | `Pages::DistributionCardComponent`, `card`, `BadgeComponent` | — |
| Audience switch | Track classes from the owner toggle / `FormFields::ToggleFieldComponent` (inline, not a new component) | — |
| Copy | existing `click-to-copy` | — |
| Tooltip | existing `tooltip` Stimulus on the form (`data-controller="page-visibility tooltip"`) | — |
| Flash | `AlertComponent` in `layouts/dashboard` | — |
| Settings hub card | `MemberHubCardComponent`, `SettingRowComponent`, `SectionComponent`, `PageComponent` | — |
| Pages source tabs / rows | `SectionNavComponent`, `MemberSourceListComponent` (add `pages` to the tab array), `MemberSourceRowComponent` | — |
| Row action group | `SectionComponent`, native `select_tag` + `input-field` / `form-label` | — |
| Member index | `PageHeaderComponent`, `PageSectionComponent`, `EmptyStateComponent`, `PaginationComponent`, `IndexTableComponent` | stacked cards **inside** `IndexTableComponent` — do not add `Member::IndexCardListComponent` |
| Composite list | `CompositeRenderer#render_list_module_html`, existing `list-module` | trailing `<th>`/`<td>` only |

No new ViewComponent classes.

---

## 5. Tailwind & Stimulus notes

### 5.1 Tokens (match siblings)

| Token | Utilities |
|---|---|
| Card | `card overflow-hidden` |
| Section chrome | `border-t border-border-subtle`, `divide-y divide-border-subtle` |
| Padding | `px-5 py-3.5` audience rows; `px-5 py-4` header / action-key / siblings heading; Settings `px-4 py-4 sm:px-6` |
| Title | `text-base font-semibold text-text-primary` (card), `text-sm font-medium text-text-primary` (row label / section) |
| Hint | `text-caption text-text-muted` |
| Body help | `text-sm text-text-secondary mt-1` |
| Accent link | `text-sm font-medium text-accent hover:underline break-all` |
| Field | `form-label` + `input-field` (`max-w-md` on action key) |
| Danger field | `aria-invalid="true"` and `ring-1 ring-danger` |
| Touch | `min-h-11` on switches, settings toggles, mobile card actions |
| Member table | `chrome.table_header_class`, `table_divide_class`, `table_row_class`, `text_link_class` |
| Member cards | `chrome.card_class(:compact)`, `label_class`, `hairline_class`, `secondary_button_class` |

### 5.2 Breakpoints

| Surface | Mobile `< sm` / `< md` | Tablet `sm`–`lg` | Desktop `lg+` |
|---|---|---|---|
| Distribution card | Column stack; switch under hint; URL `break-all`; Launch `flex-shrink-0` wraps | `sm:flex-row sm:items-center` on each audience row and each URL row | Same as tablet; card sits in `lg:col-span-2` |
| Settings hub / source rows | `flex-col gap-3` | `sm:flex-row sm:items-center sm:justify-between` | same |
| Row action group | one column | `sm:grid-cols-2` for Action + Field | same, form `max-w-3xl` |
| Member index | cards `md:hidden space-y-3` | table `hidden md:block` | table |
| Pages tabs | `overflow-x-auto min-w-max` | wrap `sm:flex-wrap` | wrap |
| Composite list | `overflow-x-auto` (unchanged); action column `whitespace-nowrap` | same | same |

### 5.3 `page-visibility` Stimulus

Replace the cascade. Independent switches. Last-on lock.

```
static targets = ["admin", "member", "public", "status"]

static values = {
  saving:       { type: String, default: "Saving…" },
  lastAudience: { type: String, default: "A form needs at least one audience." }
}
```

Server attributes on the `<form>`:

```
data-controller="page-visibility tooltip"
data-page-visibility-saving-value="<%= t("comp_misc.distribution.saving") %>"
data-page-visibility-last-audience-value="<%= t("comp_misc.distribution.last_audience") %>"
```

Each audience checkbox: `data-page-visibility-target="<key>"` and `data-action="change->page-visibility#sync"`.

Action key input: `data-action="change->page-visibility#sync"` only (not `input`).

**Last-audience lock (on connect and after every change, before submit):**

1. Count checked among admin/member/public targets that exist.
2. If count == 1: `disabled = true` on that input; add `opacity-60 cursor-not-allowed` to its track wrapper; set `wrapper.dataset.tooltip = this.lastAudienceValue`; set `aria-label` to `lastAudienceValue` (fallback: the English `default:` when the value is missing).
3. If count != 1: enable all editable switches; delete `dataset.tooltip`; restore `aria-label` to the audience name (pass names as a JSON value only if tests need them — otherwise leave the server-rendered `aria-label` on the input and only overwrite while locked).
4. Rebuild hidden inputs `page[visible_audiences][]` for every **checked** switch (including the disabled last one) so a disabled checkbox still posts.

When `publishing_editable?` is false, do not attach `page-visibility` (static disabled switches, readonly action key). No last-audience JS.

Missing `lastAudience` value → English default (Vitest covers this).

No other new Stimulus controllers. Settings page rows keep `auto-submit`. Composite keeps `list-module`.

---

## 6. Copy table

English is the string that would otherwise have been hard-coded. zh-CN is idiomatic (terse, full-width punctuation, canonical terms), not word-for-word.

### 6.1 Add — `config/locales/comp_misc.{en,zh-CN}.yml`

| Key | en | zh-CN |
|---|---|---|
| `comp_misc.distribution.last_audience` | A form needs at least one audience. | 表单须至少面向一个受众。 |
| `comp_misc.distribution.action_key_label` | Action key | 操作标识 |
| `comp_misc.distribution.action_key_help` | Start with a letter. Use only lowercase letters, numbers and underscores. | 须以字母开头，仅可使用小写字母、数字和下划线。 |
| `comp_misc.distribution.action_key_placeholder` | enroll | enroll |
| `comp_misc.distribution.action_url` | Action URL | 操作链接 |
| `comp_misc.distribution.audience_url` | URL | 链接 |
| `comp_misc.distribution.siblings_heading` | Other pages in this action | 此操作中的其他页面 |
| `comp_misc.distribution.siblings_empty` | No other pages share this action yet. | 暂无其他页面使用此操作。 |

### 6.2 Rewrite in place — same file, same keys, new meaning (exact set)

| Key | en (new) | zh-CN (new) |
|---|---|---|
| `comp_misc.distribution.hints.admin` | Signed-in admins and owners of this organization. | 本组织已登录的管理员和所有者。 |
| `comp_misc.distribution.hints.member` | Signed-in members of this organization. | 本组织已登录的会员。 |
| `comp_misc.distribution.hints.public` | Anyone, including people who aren't signed in. | 所有人，包括未登录的访客。 |

Keep `labels.*`, `header_title_html`, `audience_section`, `open`, `saving`, `not_launched`, `audience`. `not_visible` is unused after this layout (off rows have no caption); leave the key in place so existing specs that mention it can be swept by Task 2, or delete it in Task 2 if no spec remains. Prefer **leave** it until Task 2’s spec sweep.

### 6.3 Remove — `comp_misc`

| Key | Why |
|---|---|
| `comp_misc.distribution.admin_always_visible_aria` | Admin is no longer locked. |
| `comp_misc.distribution.always_on` | Same. |

Task 2 deletes both locales.

### 6.4 Add — `config/locales/admin_settings.{en,zh-CN}.yml` (fixed; Tasks 6 and 7)

| Key | en | zh-CN | Owner |
|---|---|---|---|
| `admin_settings.member.sources.pages.name` | Pages | 页面 | Task 6 |
| `admin_settings.member.sources.pages.description` | Launched pages members can open. | 会员可打开的已上线页面。 | Task 6 |
| `admin_settings.errors.validations.row_action_invalid` | The row action needs an action key and a target field. | 行操作须填写操作标识和目标字段。 | Task 7 |

### 6.5 Add — `config/locales/settings_people.{en,zh-CN}.yml`

Tab, hub card, and section titles live here today (`settings_people.sources.*`, `list_display`, `record_details`).

| Key | en | zh-CN |
|---|---|---|
| `settings_people.sources.pages.name` | Pages | 页面 |
| `settings_people.sources.pages.description` | Choose which launched forms appear in the member navigation. | 选择在会员导航中显示哪些已上线表单。 |
| `settings_people.row_action` | Row action | 行操作 |
| `settings_people.row_action_help` | Each list row links to this action with the row id filled in on the target field. | 每行会打开此操作，并在目标字段填入该行的记录编号。 |

### 6.6 Add — `config/locales/comp_admin.{en,zh-CN}.yml`

Field labels on the entity surface form live next to `member_surface_form.page_size` etc.

| Key | en | zh-CN |
|---|---|---|
| `comp_admin.member_surface_form.row_action_action` | Action | 操作 |
| `comp_admin.member_surface_form.row_action_field` | Target field | 目标字段 |
| `comp_admin.member_surface_form.row_action_field_help` | The field slug that receives the row id. | 用于接收行记录编号的字段标识。 |
| `comp_admin.member_surface_form.row_action_field_placeholder` | course | course |
| `comp_admin.member_surface_form.row_action_label` | Button label | 按钮文字 |
| `comp_admin.member_surface_form.row_action_label_help` | Optional. Leave blank to use “Open”. | 选填。留空则显示“打开”。 |
| `comp_admin.member_surface_form.row_action_none` | None | 无 |
| `comp_admin.member_surface_form.row_action_empty` | Launch a member page with an action key to use it here. | 请先上线带操作标识的会员页面，再在此选择。 |

### 6.7 Add — `config/locales/member.{en,zh-CN}.yml` (fixed + index)

| Key | en | zh-CN |
|---|---|---|
| `member.entity_surfaces.row_action_default` | Open | 打开 |

No extra index key: the button text is the overlay label or this default. View stays `common.actions.view`.

### 6.8 Add — `config/locales/public_views.{en,zh-CN}.yml` (fixed)

| Key | en | zh-CN |
|---|---|---|
| `public_views.composite.row_action_default` | Open | 打开 |

### 6.9 Already specified elsewhere (do not duplicate)

Design §5 / Task 1 / Task 3 own these. They **render** on surfaces in this spec but are not added by Tasks 2 or 8:

| Key | Renders as |
|---|---|
| `maint_core.errors.validations.page_audiences_blank` | Layout flash after a failed visibility PATCH |
| `maint_core.errors.validations.page_action_key_invalid` | Layout flash after a failed visibility PATCH |
| `maint_core.errors.page_launch.action_audience_taken` | Layout flash after a failed visibility PATCH |
| `public_views.actions.continue_here` | Flash on the counterpart page (Task 3) |
| `public_views.actions.not_for_your_account` | Flash on the refused page (Task 3) |

---

## 7. Frontend task mapping

| Task | Implements |
|---|---|
| 2 | Surface A: card layout, independent switches, last-audience lock, action key, siblings, `comp_misc` add/rewrite/remove, `page-visibility` values |
| 6 | Registers Pages source; `admin_settings.member.sources.pages.*` |
| 7 | Overlay keys + `row_action_invalid`; composite records gain `row_action_path` |
| 8 | Surfaces B–F UI: Pages tab + rows, Row action group, member table/cards, composite trailing link; `settings_people` / `comp_admin` / `member` / `public_views` keys above |

---

## 8. Decisions (do not relitigate)

1. **Admin is a real switch.** No lock, no hidden forced `admin` input, no “Always on”.
2. **Last audience is a JS+server lock**, not a fourth state. Tooltip text is `data-page-visibility-last-audience-value`. Hidden inputs keep the disabled switch in the POST.
3. **Per-audience URL rows appear only when that switch is on.** Off = no URL, no “Not visible to …” caption.
4. **Action URL is shown on the card** when a key is saved — that is the shareable `/:cid/actions/:key` router from §3.2.4.
5. **Siblings are read-only** and link to the other page’s admin show. Empty caption when the key is unique.
6. **Errors `page_audiences_blank` and `action_audience_taken` render as the existing layout flash**, not a second inline alert. `row_action_invalid` is inline on the settings form because that POST re-renders.
7. **Row action does not replace View** on the member index.
8. **Mobile member index is stacked cards (`md:` split).** Tablet and desktop share the table.
9. **Composite row action is a real `<a href>`**; `list-module#rowAction` is only the click guard.
10. **No new ViewComponents.** shadcn Switch/Input/Select/Badge/Alert/Tooltip map onto the toggle track, `input-field`, native select, `BadgeComponent`, `AlertComponent`, and `tooltip` Stimulus.

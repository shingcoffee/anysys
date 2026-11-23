# Platform Module Settings — UX spec

Date: 2026-09-03
Audience: frontend developer. ViewComponent + Tailwind + Stimulus only. I18n `en` + `zh-CN` required.

Nav area: **Maintenance / Platform / Module Settings**
Audience: `owner` on customer `81721200` only. Controllers already enforce this — do not add role UI.

shadcn analog (map to project tokens, do not install shadcn JS):

| shadcn | Anysys delivery |
|---|---|
| Card / CardHeader / CardContent | `.card` + `.card-header` + `section-header` |
| Tabs / TabsList / TabsTrigger | existing `tabs` Stimulus + underline tab nav |
| Alert | `AlertComponent` |
| Badge | `BadgeComponent` |
| Button | `ButtonComponent` |
| Empty | `EmptyStateComponent` |
| ToggleGroup (2–7 options) | filter pills on the catalog |
| Input | `.input-field` + `.form-label` |
| Breadcrumb | `BreadcrumbsComponent` via `AdminPageComponent` |

Locked product defaults — do not reopen:

- Visual / layout / IA only. Keep every URL, HTTP method, toggle semantic, and auth guard.
- Unify every page onto `AdminPageComponent` chrome (breadcrumbs + title + description + actions).
- Keep Settings / Technical tabs on the per-module show page (`data-controller="tabs"`, ids `settings` / `technical`).
- Platform-impact warning stays on the module **show** page only (`AlertComponent` warning). Nested leaves do not repeat it.
- Restyle captcha settings onto the same tokens as speech-to-text.
- No new routes, vendors, schema, or billing surfaces.
- Do not design tenant Settings / Modules or billing.

Flash alerts stay in the dashboard layout. `AdminPageComponent` does not render flash. The show view currently duplicates `notice` / `alert` — **remove those two `AlertComponent` calls**. Keep only the platform-impact warning on show.

---

## 1. Surface inventory

| # | Surface | Nav area | URL | Change |
|---|---|---|---|---|
| A | Module catalog (index) | Maintenance / Platform / Module Settings | `GET /81721200/admin/maintenance/platform/module_settings` | Restyle: extract owner hint to Alert, 3-stat row, search + filter pills, divided-row directory |
| B | Per-module show | same | `GET /81721200/admin/maintenance/platform/module_settings/:id` | Wrap in AdminPageComponent; meta row; destination tile grid; keep tabs + controls |
| C | Speech-to-text settings show | same (nested) | `GET …/module_settings/speech_to_text/settings` | Wrap SettingsComponent in AdminPageComponent; header Edit |
| D | Speech-to-text settings edit | same (nested) | `GET …/module_settings/speech_to_text/settings/edit` | Same chrome; no header action; Save/Cancel in form footer |
| E | Captcha settings show | same (nested) | `GET …/module_settings/captcha/settings` | Same chrome as C; restyle raw gray/blue onto tokens + i18n |
| F | Captcha settings edit | same (nested) | `GET …/module_settings/captcha/settings/edit` | Same chrome as D; restyle form onto tokens |
| G | Captcha verifications | same (nested) | `GET …/module_settings/captcha/verifications` | Keep AdminPage + AdminTable; **add working breadcrumb paths** |
| H | SMS credentials index | same (nested) | `GET …/module_settings/sms/credentials` | **Keep as-is** (already AdminPage + AdminTable) |
| I | SMS credentials new / edit | same (nested) | `GET …/sms/credentials/new`, `…/:id/edit` | Switch raw Breadcrumbs + `h1` to AdminPageComponent |
| J | SMS templates index | same (nested) | `GET …/module_settings/sms/templates` | **Keep as-is** |
| K | SMS templates new / edit | same (nested) | `GET …/sms/templates/new`, `…/:id/edit` | Switch to AdminPageComponent |
| L | Email credentials index | same (nested) | `GET …/module_settings/emails/credentials` | **Keep as-is** |
| M | Email credentials new / edit | same (nested) | `GET …/emails/credentials/new`, `…/:id/edit` | Switch to AdminPageComponent |
| N | Payment webhook events | same (nested) | `GET …/module_settings/payments/webhook_events` | New index **view** wrapping the existing table in AdminPageComponent. Controller switches from `render Component` to the view. No new route. |

Out of scope: billing (`…/billing/*`), tenant Settings / Modules, Maintenance / Modules toggle, new vendors, schema/billing features.

---

## 2. Layout spec per surface

### Shared chrome

Every surface in this inventory (except H / J / L which already comply) wraps its body in:

```erb
<%= render AdminPageComponent.new(
  breadcrumbs: [ … ],
  title: …,
  description: …,
  actions: [ … ],   # omit or [] when none
  width: :narrow    # only I / K / M form pages
) do %>
  …body…
<% end %>
```

Breadcrumb trail is always:

1. Maintenance → `admin_maintenance_path(current_customer_id)`
2. Module Settings → `admin_maintenance_platform_module_settings_path(current_customer_id)` (omit `path` when this crumb is the leaf)
3. Parent module show (when nested) → `admin_maintenance_platform_module_setting_path(current_customer_id, feature_module)`
4. Nested collection (when one level deeper) → that collection index
5. Current leaf — no `path`

Resolve the parent `FeatureModules::Module` the same way the matching index already does (`find_by(key: "sms")`, `find_by(key: "emails")`, `find_by(key: "speech_to_text")`, `find_by(key: "captcha")`, `find_by(key: "payment")`). Do not change lookup keys.

---

### A. Module catalog (index)

**Wrapper:** `AdminPageComponent`

| Region | Content | Source |
|---|---|---|
| Breadcrumbs | Maintenance → Module Settings (leaf) | existing `maint_platform.module_settings.breadcrumbs.*` |
| Title | Module Settings | existing `index.title` |
| Description | Platform-wide module configuration and settings | existing `index.description` |
| Header actions | none | — |

**Body, top to bottom:**

```
┌─────────────────────────────────────────────────────────────┐
│ AdminPage: title + description                              │
├─────────────────────────────────────────────────────────────┤
│ AlertComponent warning — owner_access_hint                  │
├──────────────┬──────────────┬───────────────────────────────┤
│ Total   12   │ Active   9   │ Required   3                  │
├─────────────────────────────────────────────────────────────┤
│ [ Search modules…          ]  (All) (Active) (Inactive) (Req)│
├─────────────────────────────────────────────────────────────┤
│ card                                                        │
│  Name  [Required] [Active]                              ›   │
│  Description clamp-2                                        │
│  `key`                                                      │
│  ─────────────────────────────────────────────────────────  │
│  …                                                          │
└─────────────────────────────────────────────────────────────┘
```

**Owner hint.** Extract the current wrapping “owner access” card. Render `AlertComponent` `type: :warning` with `message: t("maint_platform.module_settings.index.owner_access_hint")`. Do not render `owner_access` as a separate heading (AlertComponent is message-only). Keep the `owner_access` key in locale files; do not delete it.

**Stats row.** Three compact cards in `grid grid-cols-1 sm:grid-cols-3 gap-3`.

| Card | Number | Label (new i18n) |
|---|---|---|
| Total | `@available_modules.size` | `index.stats.total` → English `Total` |
| Active | `count(&:active?)` | `index.stats.active` → English `Active` |
| Required | `count(&:required?)` | `index.stats.required` → English `Required` |

Each card: `card p-4`. Number: `text-subtitle text-text-primary tabular-nums`. Label: `text-caption`. Cards are **not** clickable (filtering is the pill row).

**`stats_summary` must still appear in the response body** — `spec/requests/admin/maintenance/platform/module_settings_spec.rb` asserts `include(expected)` on that exact interpolated string. Render it in a `sr-only` element **and** keep the three numbers visually in the stat cards (same interpolations). When the catalog is empty, still render the sr-only summary (`0 total · 0 active · 0 required`) so the assertion stays true; hide the visual stat cards and toolbar, show EmptyState only.

**Toolbar** (only when `@available_modules.any?`):

- Search: `<input type="search" class="input-field">`, placeholder `index.search_placeholder` → English `Search modules…`. Filters already-loaded rows (name, key, description; case-insensitive substring). No server round-trip.
- Filter pills: All / Active / Inactive / Required. shadcn ToggleGroup analog. `inline-flex flex-wrap gap-2`.
  - Selected: `bg-accent text-white`
  - Unselected: `bg-surface-active text-text-primary hover:bg-canvas-elevated`
  - Shape: `rounded-md px-3 py-1.5 text-sm font-medium`
  - `aria-pressed="true"` on the selected pill; `type="button"`
- Layout: `flex flex-col sm:flex-row sm:items-center gap-3`. Search is `w-full sm:max-w-sm sm:flex-1`. Pills wrap; never clip.

Default filter = All. Combining search + filter is AND.

**Directory.** One `card overflow-hidden` with `ul.divide-y.divide-border-subtle`. **Not** a 3-column generator grid.

Each row is the existing `link_to` to `admin_maintenance_platform_module_setting_path`. Row classes: `hover:bg-canvas-elevated transition-colors`.

Desktop (`sm+`):

```
[ Name  [Required?] [Active|Inactive]                         › ]
[ Description (line-clamp-2)                                    ]
[ `key` mono chip                                               ]
```

- First line: `flex items-center gap-2 flex-wrap`. Name `text-body text-text-primary font-medium` (wraps, never `truncate` in a way that clips the status badges).
- Badges: Required → `BadgeComponent` `:warning` `:sm` (`common.labels.required`). Active → `:success` (`common.status.active`). Inactive → `:default` (`common.status.inactive`). Required then status, same order as today.
- Description: `mt-0.5 text-caption line-clamp-2` (upgrade from `line-clamp-1`).
- Key: `text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded`.
- Chevron: existing 20px chevron, `text-text-muted flex-shrink-0`, right-aligned on `sm+`.

Phone: `flex flex-col gap-2 px-4 py-4` (use `px-4` on all breakpoints for consistency with other cards). Name + badges stack/wrap. Chevron sits on the first line’s trailing edge via `flex items-start justify-between gap-3` so the name is never horizontally clipped.

Row data attributes for the catalog controller (not user-visible):

- `data-module-settings-catalog-target="row"`
- `data-name`, `data-key`, `data-description`
- `data-active="true|false"`, `data-required="true|false"`

**Empty catalog (server, no modules):** `EmptyStateComponent` with `title: t("index.empty")` (existing “No modules available”) and `description: t("index.empty_description")` (new; English `No feature modules are registered on this platform.`). No action button. Do not mount the catalog Stimulus controller.

**Empty filter / search (client):** hide the directory card; show a second `EmptyStateComponent` (`data-module-settings-catalog-target="emptyFilter"`, hidden until no rows match). Title `index.filter_empty_title` → `No matching modules`. Description `index.filter_empty_description` → `Try a different search or filter.` No action.

**Loading:** server-rendered. No skeleton.

**Error:** layout flash only (permission denied redirects as today).

**Primary action:** click a directory row → show. No destructive action on the catalog.

Extract the body (alert is in the view; stats + toolbar + directory + filter-empty) into **new** `Admin::Maintenance::Platform::ModuleCatalogComponent` so the index view stays a thin AdminPage wrapper. Props: `modules:` (array of feature modules), `customer_id:`.

---

### B. Per-module show

**Wrapper:** `AdminPageComponent`. Delete the custom header block (icon well + inline `h1` + badges + key/version).

| Region | Content | Source |
|---|---|---|
| Breadcrumbs | Maintenance → Module Settings → **module name** (leaf) | crumbs 1–2 existing keys; leaf = `@feature_module.name` (model field, not a new i18n key) |
| Title | module name | `@feature_module.name` |
| Description | module description | `@feature_module.description` |
| Header actions | none | toggles live in Module Controls |

**Body, top to bottom:**

```
┌─────────────────────────────────────────────────────────────┐
│ AdminPage: name + description                               │
│ `key`   v1.0   [Active] [Required]          ← meta row      │
├─────────────────────────────────────────────────────────────┤
│ AlertComponent warning — platform_warning_html              │
├─────────────────────────────────────────────────────────────┤
│ card  Module Controls                                       │
│  Status     hint…                              [toggle]     │
│  Required   hint…                              [toggle]     │
│  Handoff    hint…                              [toggle]     │
├─────────────────────────────────────────────────────────────┤
│ [ Settings ]  Technical Reference                           │
│                                                             │
│  Settings tab:                                              │
│   destination tile grid (1–2 col)                           │
│   inline toggle cards (auth / payment gateways / captcha)   │
│   schema defaults table                                     │
│   or EmptyState when no settings                            │
│                                                             │
│  Technical tab:                                             │
│   Models table · tokens accordion · ModuleHandoffComponent  │
└─────────────────────────────────────────────────────────────┘
```

**Meta row** (immediately under the AdminPage header strip, before the warning):

`flex flex-wrap items-center gap-2 mb-6`

- Key chip: same `text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded`. Precede with `sr-only` `show.module_key`.
- Version: `text-caption`, value `@feature_module.version || "1.0"`. Precede with `sr-only` `show.version`. Separate from the key with a `text-caption` middot (`aria-hidden`).
- Active / Inactive `BadgeComponent` (same variants as today).
- Required `BadgeComponent` `:warning` only when `required?`.

**Platform warning.** `AlertComponent` `type: :warning`, `message: t("…platform_warning_html")`. Show page **only**. Nested leaves do not repeat this.

**Module Controls card.** Keep the existing grouped card (`controls_title` / `controls_subtitle`). Three setting rows (status / required / handoff). Each row:

- `sm+`: `flex items-start justify-between gap-4`
- mobile: `flex flex-col gap-3` — copy first, `ModuleToggleComponent` under the copy
- Padding: `px-4 sm:px-6 py-4`
- Label line: `text-body text-text-primary font-medium` + status badge (unchanged)
- Hint: existing `*_hint_html` captions
- Locked / mandatory: existing `locked_hint` + `disabled:` on the toggle — **unchanged**
- Confirm on required-on: existing `required_confirm` — **unchanged**
- Toggle field names, URLs, disabled rules — **unchanged**

**Tabs.** Keep `data-controller="tabs"` `data-tabs-active-value="settings"` and the existing active/inactive classes (`border-accent text-accent` / `border-transparent text-text-muted`). Tab ids stay `settings` and `technical`. Nav `aria-label` stays `show.tabs.nav_label`. Default tab is Settings.

Underline tab list: `border-b border-border-subtle`, triggers `-mb-px flex gap-6`, each `whitespace-nowrap border-b-2 px-1 py-3 text-sm font-medium`. On narrow viewports the nav may wrap (`flex-wrap`); do not overflow horizontally.

#### Settings tab

**Destination links** — evolve `SettingsLinkCardComponent` (do not duplicate markup).

Add `layout:` kwarg, default `:grid`.

`:grid` (use for every destination group on this page):

```
section-header + caption
grid grid-cols-1 md:grid-cols-2 gap-3
  tile  tile
  tile  …
```

Each tile is a clickable `card p-4 flex items-start gap-3 hover:bg-canvas-elevated transition-colors` linking to `link.path`:

- Icon well: `size-9 rounded-lg bg-surface-active flex items-center justify-center flex-shrink-0` + existing 16px outline icon
- Title: `text-body text-text-primary font-medium`
- Description: `text-caption line-clamp-1` (one line, as locked)
- Chevron: `w-5 h-5 text-text-muted flex-shrink-0 mt-0.5`

A single destination (Email credentials, STT credentials, Payment webhooks) still uses the 2-col grid — the tile occupies the first column only. Do not stretch a lone tile to full width.

`:list` is no longer used on this page. Keep the kwarg only if the component API needs a fallback; default and only caller is `:grid`.

Add icon `:microphone` to `ICON_PATHS` (existing STT path in show.html.erb). SMS uses `:envelope` + `:document`. Email uses `:envelope`. Payment webhooks uses `:bolt`. Captcha already uses `:lock_closed` + `:clipboard_list`.

Migrate the inline SMS / Email / STT / Payment-webhooks list rows in `show.html.erb` onto `SettingsLinkCardComponent`. Captcha already uses it — switch that call to the new grid layout (no API change for callers other than the default layout).

**Inline toggle cards stay on the show page** (not nested):

- Authentication → existing Customer sign-up card + `allow_customer_signup` toggle. Restyle the row to the same `sm:flex items-start justify-between` / mobile-stack pattern as Module Controls. Header stays `card-header`.
- Payment → existing Available Tenders card (per-gateway `available` toggles). Same row pattern. Gateway name `text-body font-medium`, key as `text-caption` (not a destination tile).
- Captcha → `ProtectedPagesComponent` stays on the show page. **Polish the header only:** replace `px-4 py-3 border-b border-border-subtle` with `card-header` so it matches every other card. Keep throttle picker behavior, grouping, and empty copy. Empty body stays the italic caption (`show.captcha.empty`); do not swap to EmptyStateComponent here (the card is a settings panel, not a page).

**Schema defaults table.** Keep. Wrap the table in `overflow-x-auto`. Footer already uses `ButtonComponent` primary — keep. Footer bar: `px-4 sm:px-6 py-4 border-t border-border-subtle bg-surface-subtle`.

**No-settings.** When the captured `settings_cards` is blank, render `EmptyStateComponent` with `title` and `description` both derived from existing `show.tabs.no_settings` (use that string as `title`; add `show.tabs.no_settings_description` → English `Platform defaults and vendor credentials will appear here when this module defines them.`). No action.

#### Technical tab

Keep Models table, tokens accordion, `ModuleHandoffComponent`. Behavior unchanged.

Polish only:

- Accordion container: `flex flex-col gap-3 p-6` (replace `space-y-4`)
- `<summary>`: `px-5 py-3.5` (was `px-6 py-4`) so the chevron + name + column count breathe evenly
- Inner table wrap stays `overflow-x-auto`

Models empty / tokens empty: keep the existing italic captions inside the card. Do not introduce EmptyStateComponent on this tab.

---

### C / D. Speech-to-text settings (show / edit)

**Wrapper:** `AdminPageComponent` around the existing `SpeechToText::SettingsComponent`. `width` default (not narrow) so the card can sit at `max-w-2xl` inside the body.

| Region | Content | Source |
|---|---|---|
| Breadcrumbs | Maintenance → Module Settings → Speech to text (parent show) → Settings (leaf) | crumbs 1–2 existing module_settings keys; parent label = the feature module’s `name`; leaf `speech_to_text.platform_settings.settings_crumb` → English `Settings` |
| Title | Speech to text — Platform Settings | existing `speech_to_text.platform_settings.title` |
| Description | one line | new `speech_to_text.platform_settings.page_description` → English `Platform-wide Whisper credentials used by every tenant.` (byte-identical to today’s show subtitle meaning) |
| Header actions (show) | Edit, `variant: :primary`, `icon: :edit`, path = existing edit path including `?provider=` | `speech_to_text.platform_settings.edit` |
| Header actions (edit) | **none** | Save / Cancel stay in the form footer |

**SettingsComponent internals:**

- Drop the inner `<h1>` / `section-header` page title (AdminPage now owns it). Card-header becomes: caption `active_provider` + provider pill nav. Keep `aria-labelledby` by pointing it at a visually-hidden heading or at the AdminPage `h1` id — simplest: drop `aria-labelledby` and keep the `<section>` without a duplicate title.
- Provider switcher: already correct. Keep `inline-flex gap-2 flex-wrap`, current = `bg-accent text-white`, others = `bg-surface-active text-text-primary hover:bg-canvas-elevated`, Active `BadgeComponent` on the live vendor, `aria-current="page"` on the current pill. `aria-label` = existing `nav_label`.
- Show mode:
  - `dl` grid `grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3`
  - `dt` = `text-caption`, `dd` = `text-body text-text-primary`
  - Secrets: existing `speech_to_text.platform_settings.masked` / `common.labels.em_dash`
  - Health: `BadgeComponent` (already)
  - Test connection: **`ButtonComponent` secondary** (replace raw `btn btn-secondary`)
  - Remove the in-card Edit button (header owns it)
- Edit mode:
  - `form-label` + `input-field` (already)
  - Keep-existing hint under secrets (already)
  - Make-active checkbox (already)
  - Form footer `.form-actions`: Cancel = `ButtonComponent` secondary link; Save = `ButtonComponent` primary submit. Replace raw `btn` / `<button>`.
- Errors: replace the raw danger box with `AlertComponent` `type: :error`. If multiple messages, join them with a middle-dot + spaces so every Reform error remains visible.

Card stays `card overflow-hidden max-w-2xl`.

---

### E / F. Captcha settings (show / edit)

Same chrome and interaction as C / D. This is the token restyle.

| Region | Content | Source |
|---|---|---|
| Breadcrumbs | Maintenance → Module Settings → Captcha (parent show) → Settings (leaf) | same pattern; leaf `captcha.platform_settings.settings_crumb` → English `Settings` |
| Title | Captcha — Platform Settings | existing `captcha.platform_settings.title` |
| Description | one line | new `captcha.platform_settings.page_description` → English `Vendor credentials, failure policy, and connection test.` |
| Header actions (show) | Edit primary + edit icon | existing `captcha.platform_settings.edit` |
| Header actions (edit) | none | — |

**Captcha::SettingsComponent — replace every raw gray / blue / red utility and hard-coded glyph.**

| Current | Replacement |
|---|---|
| `bg-white shadow rounded-lg p-6` | `card overflow-hidden max-w-2xl` + inner `p-6 flex flex-col gap-5` (match STT) |
| Inner `h1 text-xl` | drop (AdminPage owns title) |
| `text-xs text-gray-500` caption | `text-caption` + existing `active_provider` |
| Provider pills `bg-blue-600` / `bg-gray-100` | same pill classes as STT |
| `●` on the live vendor | `BadgeComponent` `:success` `:sm` with `common.status.active`. **Never** a bullet |
| `bg-red-50 border-red-200` errors | `AlertComponent` `:error` (same join rule as STT) |
| Hard-coded `"—"` | `t("common.labels.em_dash")` |
| Hard-coded `"••••••"` | new `captcha.platform_settings.masked` → English `••••••` (byte-identical to STT’s masked) |
| Hard-coded `"✓"` for active | `BadgeComponent` `:success` `:sm` `common.status.active`; inactive = `em_dash` |
| Gray health `<span>` | `BadgeComponent` with the same variant map as STT (`ok` → `:success`, `configuration_error` → `:danger`, `unreachable` → `:warning`, else `:default`) |
| Raw Test / Edit / Verifications / Save / Cancel buttons | `ButtonComponent` (Test + View verifications = secondary; Save = primary; Cancel = secondary). **Remove in-card Edit** (header owns it). Keep View verifications in the show-mode action row. |
| Raw `w-full border rounded px-2 py-1` inputs / select | `input-field` (select included) |
| `block text-sm font-medium` labels | `form-label` |
| `text-xs text-gray-500` hints | `text-caption mt-1` |
| Footer `flex gap-2` blue Save | `.form-actions` Cancel secondary + Save primary, **Cancel first** (match STT) |

Show-mode `dl` uses the same `grid-cols-1 sm:grid-cols-2` as STT.

Fail-policy `<select>`: `input-field`. Score threshold: `input-field` `type="number"`.

Secret placeholder: existing `comp_admin.captcha_platform_settings.secret_placeholder`. Add a keep-existing caption under secret fields when a secret is already stored, mirroring STT’s `keep_hint` — new `captcha.platform_settings.keep_hint` → English `Leave blank to keep the current secret.`

Make-active checkbox: `h-4 w-4 rounded border-border-subtle text-accent focus:ring-accent` + `text-body` label (match STT).

---

### G. Captcha verifications

Already `AdminPageComponent` + `AdminTableComponent`. **Only change: breadcrumb paths.**

```
Maintenance          → admin_maintenance_path
Module Settings      → admin_maintenance_platform_module_settings_path
Captcha              → admin_maintenance_platform_module_setting_path(…, captcha_module)
Verifications        → leaf (no path)
```

Labels: keep `captcha.verifications.breadcrumbs.maintenance` / `.captcha` / `.verifications`. Insert Module Settings between Maintenance and Captcha using `maint_platform.module_settings.breadcrumbs.module_settings` (do not invent a fourth captcha breadcrumb key). Resolve `captcha_module` with `FeatureModules::Module.find_by(key: "captcha")` — omit the path if the record is missing (same pattern as SMS indexes).

Title, description, search, filters, empty_state: unchanged.

---

### I / K / M. SMS + email new / edit

Already have the right crumbs, title, and description — they just bypass AdminPageComponent.

**Replace** the raw `BreadcrumbsComponent` + `<h1 class="text-heading">` + `<p class="text-body-sm">` with `AdminPageComponent` (`width: :narrow`).

| Page | Title / description keys (keep) | Header actions |
|---|---|---|
| SMS credential new | `maint_platform.sms.credentials.new.*` | none |
| SMS credential edit | `maint_platform.sms.credentials.edit.*` | none |
| SMS template new | `maint_platform.sms.templates.new.*` | none |
| SMS template edit | `maint_platform.sms.templates.edit.*` | none |
| Email credential new | `maint_platform.emails.credentials.new.*` | none |
| Email credential edit | `maint_platform.emails.credentials.edit.*` | none |

Body: unchanged `card p-6` wrapping the existing `CredentialFormComponent` / `TemplateFormComponent`. Forms already own Save / Cancel.

Drop the standalone `content_for :container_width, :narrow` — AdminPage `width: :narrow` sets it.

---

### N. Payment webhook events

**New view** `app/views/admin/maintenance/platform/payments/webhook_events/index.html.erb`. Controller `index` changes from `render WebhookEventTableComponent` to rendering this view (instance variable `@events` stays). No new route. `redrive` redirect unchanged.

| Region | Content | Source |
|---|---|---|
| Breadcrumbs | Maintenance → Module Settings → Payment (parent show) → Webhook Events (leaf) | crumbs 1–2 module_settings keys; parent = payment module `name`; leaf `comp_payments.webhook_events.title` |
| Title | Webhook Events | existing `comp_payments.webhook_events.title` |
| Description | Inspect inbound gateway notifications and redrive stranded events. | reuse `maint_platform.module_settings.show.payment.webhooks_subtitle` |
| Header actions | none | redrive stays per-row |

Body: existing `Payments::Admin::WebhookEventTableComponent`.

Polish the table chrome only:

- Header `px-4 py-3 border-b` → `card-header` (match other cards)
- Hard-coded `"—"` in `event_type` / `processed_at` empty cells → `t("common.labels.em_dash")`
- Empty: when `events.empty?`, replace the empty `<tr>` with `EmptyStateComponent` **inside** the card (`title` from existing `comp_payments.webhook_events.empty`; add `comp_payments.webhook_events.empty_description` → English `Inbound gateway notifications will appear here.`). Hide the table body in that case.
- Redrive: `ButtonComponent` `variant: :secondary` `size: :sm` (replace raw `btn btn-secondary text-xs`)
- Table wrap stays `overflow-x-auto`

---

### H / J / L. Indexes already compliant

SMS credentials, SMS templates, Email credentials — no layout change. They are the reference pattern the other nested pages must match.

---

## 3. Interaction flow

All starting URLs are under customer `81721200`. Actor is platform owner. Non-owner / anonymous keep today’s redirect / 403 — no new denial UI.

### Catalog → show

1. `GET /81721200/admin/maintenance/platform/module_settings`
2. Owner reads the warning + stats.
3. Types in search and/or clicks a filter pill — rows hide/show instantly; URL does **not** change.
4. Clicks a directory row → `GET …/module_settings/:id` (Settings tab visible).
5. Server-empty catalog: EmptyState, no toolbar. Client-empty filter: filter-empty EmptyState, toolbar stays so the owner can clear the query / pill.

### Show → nested destination

1. On show, Settings tab (default).
2. Clicks a destination tile (SMS credentials, SMS templates, Email credentials, STT settings, Captcha settings, Captcha verifications, Payment webhooks) → existing nested GET.
3. Breadcrumb “Module Settings” or the parent module name returns to catalog / show.

### Show → toggles (unchanged semantics)

1. Module Controls / auth signup / payment gateway / captcha throttle / extendable / template-token checkbox — existing PATCH + confirm.
2. Mandatory module: status + required toggles stay disabled; locked hint stays visible.
3. Inactive module: required + handoff stay disabled (existing rules).
4. Validation / update failure: existing flash error via dashboard layout.

### Show → Technical

1. Clicks Technical Reference tab (client-only; no URL change; keep `tabs` controller).
2. Expands a tokens accordion row; checks a token checkbox — existing Stimulus.

### STT / Captcha credentials

**Show → Edit (happy):**

1. `GET …/speech_to_text/settings` or `…/captcha/settings`
2. Clicks header Edit → `GET …/settings/edit?provider=`
3. Edits fields (blank secret = keep existing) → Save → PATCH → redirect to show + existing flash.
4. Cancel → GET show for the same provider (no save).

**Provider switch:**

1. Clicks a non-current pill → GET same action with `?provider=` (existing). Current pill may still navigate to the same URL.

**Test connection:**

1. On show, clicks Test → existing POST `test_connection` → redirect + flash (`ok` / `configuration_error` / `unreachable`). Health badge updates on the next show render.

**Captcha → verifications:**

1. On captcha settings show, clicks View verifications (in-card secondary) → existing verifications index.
2. Or from captcha module show, clicks the Verification log tile.

**Validation error (edit):**

1. PATCH fails → re-render edit with `errors` → `AlertComponent` error above the form. Fields stay filled. Prefer the in-form Alert as the field-level source of truth (today’s pattern).

**Vendor down:** Test flash + health badge `:warning` / `:danger`. No modal.

**Permission denied:** existing redirect. No extra banner.

### SMS / email credential or template

1. From module show tile → index (unchanged).
2. Header New → new form in AdminPage chrome → Save → index + flash. Cancel → index.
3. Row Edit → edit form in AdminPage chrome → Save / Cancel as today.

### Payment webhooks

1. From payment module show, Webhook event ledger tile → new chrome + existing table.
2. Clicks Redrive on a stranded row → existing POST → redirect to the same index + flash. Processed rows have no button.

---

## 4. Component reuse map

| Piece | Reuse / evolve / new |
|---|---|
| Page chrome (every surface) | **Reuse** `AdminPageComponent` + `BreadcrumbsComponent` |
| Owner hint, platform warning, form errors | **Reuse** `AlertComponent` |
| Active / Inactive / Required / health / token type | **Reuse** `BadgeComponent` |
| Header Edit, Test, Save, Cancel, Redrive, View verifications, schema Save | **Reuse** `ButtonComponent` |
| Server-empty catalog, filter-empty, no-settings, webhook empty | **Reuse** `EmptyStateComponent` |
| SMS / email / captcha verification indexes | **Reuse** `AdminTableComponent` (no change) |
| Status / required / handoff / auth / gateway / extendable toggles | **Reuse** `Admin::Maintenance::Platform::ModuleToggleComponent` |
| Destination groups on show | **Evolve** `SettingsLinkCardComponent` — add `layout: :grid` (default), tile markup, `:microphone` icon |
| Captcha protected pages | **Reuse** `ProtectedPagesComponent` — header class → `card-header` only |
| STT credentials card | **Reuse** `SpeechToText::SettingsComponent` — drop inner h1; ButtonComponent + AlertComponent |
| Captcha credentials card | **Reuse** `Captcha::SettingsComponent` — restyle onto STT tokens + i18n |
| Technical handoff | **Reuse** `ModuleHandoffComponent` (no layout change beyond sitting under the polished accordion) |
| SMS / email forms | **Reuse** `Sms::CredentialFormComponent`, `Sms::TemplateFormComponent`, `Emails::CredentialFormComponent` — wrap page only |
| Webhook table | **Reuse** `Payments::Admin::WebhookEventTableComponent` — card-header + EmptyState + ButtonComponent + em_dash |
| Catalog body (stats, toolbar, directory) | **New** `Admin::Maintenance::Platform::ModuleCatalogComponent` |
| Catalog filter / search | **New** Stimulus `module-settings-catalog` |
| Show tabs | **Reuse** existing `tabs` controller — do not fork |
| Tokens accordion | **Reuse** existing `accordion` + `template-token-checkbox` |

Do **not** create a new show-page mega-component. `show.html.erb` stays the composer: AdminPage → meta → warning → controls card → tabs → SettingsLinkCard / toggle cards / schema / EmptyState / Models / accordion / Handoff.

---

## 5. Tailwind & Stimulus notes

### Tokens (use these; never raw `bg-blue-*` / `bg-gray-*` / `text-red-*` on these surfaces)

- Surfaces: `card`, `card-header`, `bg-surface`, `bg-surface-active`, `bg-surface-subtle`, `bg-canvas-elevated`, `border-border-subtle`
- Type: `text-subtitle`, `text-body`, `text-body-sm`, `text-caption`, `text-label`, `text-mono`, `section-header`, `text-text-primary`, `text-text-muted`
- Controls: `input-field`, `form-label`, `form-actions`, `btn` via `ButtonComponent` only
- Accent / status: `bg-accent text-white`, `BadgeComponent` variants, `AlertComponent` types
- Spacing: `flex` + `gap-*` (no new `space-y-*`). Page sections `flex flex-col gap-6`. Cards `p-4` (stats, tiles) or `p-6` (forms).
- Equal boxes: `size-9` for icon wells (not `w-9 h-9` on new markup).
- Hover: directory rows and destination tiles `hover:bg-canvas-elevated transition-colors`.

### Responsive (mobile-first, locked)

- Primary identity (page title, module name, first destination tile, form fields) and primary actions (header Edit, form Save, directory row) stay reachable without horizontal scroll.
- Stats: 1 col → 3 col at `sm`.
- Toolbar: stack; search full width; pills wrap.
- Directory rows: column on phone, row on `sm+`; name/status wrap, never clip.
- Module Controls / auth / gateway rows: stack toggle under copy; `sm:flex-row sm:items-start sm:justify-between`.
- Destination tiles: `grid-cols-1 md:grid-cols-2 gap-3`.
- Tables (schema, models, tokens, webhooks, AdminTable): always `overflow-x-auto`.
- Provider pills: `flex-wrap`.
- AdminPage header already stacks title / actions at `sm`.

### Stimulus `module-settings-catalog`

New file: `app/javascript/controllers/module_settings_catalog_controller.js`.

| | |
|---|---|
| Identifier | `module-settings-catalog` |
| Targets | `searchInput`, `filter`, `row`, `directory`, `emptyFilter` |
| Values | `query` String default `""`; `filter` String default `"all"` (`all` \| `active` \| `inactive` \| `required`) |
| Actions | `search` (input on the search field); `applyFilter` (click on a pill, reads `data-filter` from the button) |

Behavior:

1. `connect` / `search` / `applyFilter` all call a single `apply()`.
2. A row is visible when it matches the filter **and** the query.
   - `all` → no status predicate
   - `active` → `data-active === "true"`
   - `inactive` → `data-active === "false"`
   - `required` → `data-required === "true"`
   - query matches if it is blank or is a case-insensitive substring of `data-name`, `data-key`, or `data-description`
3. Toggle `hidden` on each row. If zero rows visible → hide `directory`, show `emptyFilter`. Else the reverse.
4. Selected pill: set `aria-pressed`, add `bg-accent text-white`, remove `bg-surface-active` (use the Classes API `active` / `inactive` mirroring `tabs_controller`, with the same class strings passed from the view).
5. No debounce required (in-memory). No URL sync.

i18n in JS: none. Placeholder and pill labels are server-rendered. This keeps Vitest at 100% without data-attribute fixtures for copy.

Vitest: `spec/javascript/controllers/module_settings_catalog_controller.test.js` must cover connect defaults, each filter, query against name/key/description, combined filter+query, empty-filter toggle, and pill class / `aria-pressed` updates — **100% lines and branches**.

Mount on a wrapper around stats-optional + toolbar + directory + filter-empty. Stats are not filtered.

### Existing Stimulus — do not fork

- `tabs` — show page, ids `settings` / `technical`
- `accordion` — tokens
- `template-token-checkbox` — token toggles
- Module toggle / captcha throttle pickers — unchanged

### New i18n keys (both `en` and `zh-CN`; English values byte-identical to the strings below)

`config/locales/maint_platform.*.yml` under `module_settings.index`:

| Key | en |
|---|---|
| `stats.total` | `Total` |
| `stats.active` | `Active` |
| `stats.required` | `Required` |
| `search_placeholder` | `Search modules…` |
| `filters.all` | `All` |
| `filters.active` | `Active` |
| `filters.inactive` | `Inactive` |
| `filters.required` | `Required` |
| `filters.aria_label` | `Filter modules` |
| `empty_description` | `No feature modules are registered on this platform.` |
| `filter_empty_title` | `No matching modules` |
| `filter_empty_description` | `Try a different search or filter.` |

`module_settings.show.tabs.no_settings_description` → `Platform defaults and vendor credentials will appear here when this module defines them.`

`speech_to_text.platform_settings.settings_crumb` → `Settings`
`speech_to_text.platform_settings.page_description` → `Platform-wide Whisper credentials used by every tenant.`

`captcha.platform_settings.settings_crumb` → `Settings`
`captcha.platform_settings.page_description` → `Vendor credentials, failure policy, and connection test.`
`captcha.platform_settings.masked` → `••••••`
`captcha.platform_settings.keep_hint` → `Leave blank to keep the current secret.`

`comp_payments.webhook_events.empty_description` → `Inbound gateway notifications will appear here.`

Reuse, do not duplicate: `common.labels.em_dash`, `common.labels.required`, `common.status.active` / `inactive` / `disabled`, existing show / breadcrumb / form keys, existing `stats_summary`.

zh-CN must be idiomatic (terse, full-width punctuation, canonical terms), not word-for-word. `stats_summary` Chinese string stays exactly as it is today.

---

## 6. Explicit non-goals

- No billing screens.
- No tenant Settings / `<module>` or Maintenance / Modules toggle redesign.
- No new routes, query-param filters on the catalog URL, or server-side catalog search.
- No new vendors, schema fields, or webhook columns.
- No platform-impact warning on nested leaves.
- No 3-column catalog grid.
- No raw gray/blue utilities left on captcha settings after this pass.

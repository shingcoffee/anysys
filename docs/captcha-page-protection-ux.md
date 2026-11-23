# Captcha page protection — UX spec

Date: 2026-09-01
Audience: frontend developer. Implement ViewComponent + Tailwind + Stimulus only. There is no React shadcn in the runtime.

Follows: `docs/captcha-page-protection-design.md` (locked).

Visual language: match the platform module-settings show page
(`app/views/admin/maintenance/platform/module_settings/show.html.erb`) and sibling cards under
`app/components/admin/maintenance/platform/`. Use `card`, `card-header`, `section-header`,
`text-body`, `text-caption`, `text-mono`, `text-text-primary`, `text-text-muted`,
`divide-y divide-border-subtle`, `BadgeComponent`, `AlertComponent`, and
`Admin::Maintenance::Platform::ModuleToggleComponent` (instant PATCH, `role="switch"`).

Do **not** restyle nested destinations (vendor credentials, verification log) or the
page-builder “Require captcha” checkbox. Do **not** introduce a search/filter control
(typical lists are well under 20 rows).

All new copy: I18n `en` + `zh-CN`. English value = the string that would otherwise have been
hard-coded. Never bake `t()` into a Ruby constant.

Resolve the Captcha feature module by **key `captcha`**. Never hard-code module id `2`.

---

## 1. Surface inventory

| # | Surface | Nav area | URL | Audience | Change |
|---|---|---|---|---|---|
| A | Captcha platform module settings — **Settings** tab | Maintenance / Platform / Module Settings | `GET /81721200/admin/maintenance/platform/module_settings/:id` where `:id` is `FeatureModules::Module.find_by!(key: "captcha").id` | `owner` on customer `81721200` | Settings tab is currently empty for captcha (`settings_cards` blank → “This module has no additional settings”). Add two cards: **Protected public pages** (grouped switches) and **Configuration** (link rows). |
| B | Vendor credentials (existing) | Maintenance / Platform / Module Settings | `GET /81721200/admin/maintenance/platform/module_settings/captcha/settings` | same | **Link only.** Do not restyle `Admin::Maintenance::Platform::Captcha::SettingsComponent`. |
| C | Verification log (existing) | Maintenance / Platform / Module Settings | `GET /81721200/admin/maintenance/platform/module_settings/captcha/verifications` | same | **Link only.** Do not restyle the ledger. |
| D | Customer Captcha settings | Settings | `GET /:cid/admin/settings/modules/captcha` (sidebar / `entry_path`; implementation today also lives at `.../captcha/status`) | tenant `admin`, or `owner` acting in that tenant | Replace the count-only `StatusComponent` (`max-w-2xl` gray box) with platform-style cards: alerts, provider line, public-page list + switches. |
| E | Page-builder Security → Require captcha (existing) | admin (page editor) | page editor modal | tenant `admin` / `owner` | **No visual change.** Flag stays in lockstep with D’s switch. |

Out of scope (no new surfaces, no restyle):

- Maintenance / Modules enable-disable row (existing toggle)
- Member settings, public form chrome, widget appearance
- Fail-policy / score / vendor credential form
- Shared (`customer_id` NULL) pages — they never appear on D
- Per-tenant overrides of platform `/auth/*` surfaces

Module URL mapping (AGENTS.md four areas):

- **Modules / Captcha** — empty; no entries table
- **Settings / Captcha** — surface D
- **Maintenance / Modules** — existing enable/disable; no change
- **Maintenance / Platform / Module Settings** — surfaces A–C

---

## 2. Layout spec per surface

### Shared chrome (A — already built, do not restyle)

The captcha module show page keeps the existing chrome from
`module_settings/show.html.erb`:

```
Breadcrumbs: Maintenance → Module Settings → {module.name}
Title strip: icon + name + Active/Inactive (+ Required) badges
             description · key chip · version
Alert: platform-warning (existing)
Card: Module Controls (status / required / handoff) — unchanged
Tabs: Settings (default) | Technical Reference
```

Work happens **inside** the Settings tab `settings_cards` capture, gated by
`@feature_module.key == "captcha"` (string key, not id). Once those cards render,
the tab’s empty-state (“This module has no additional settings to configure.”)
must **not** appear.

Card order in the Settings tab:

1. **Protected public pages** (primary)
2. **Configuration** link card (credentials + verifications)

---

### A1. Protected public pages card (NEW)

**Component:** `Admin::Maintenance::Platform::Captcha::ProtectedPagesComponent`

**Data (backend catalog → component props)**

| Prop / field | Source | Shown as |
|---|---|---|
| `group` | catalog group enum | group header label |
| `surface_key` | e.g. `authentication/sessions` | not shown; PATCH body |
| `name` | i18n `captcha.surfaces.*` (fallback: humanized controller) | `text-body font-medium` |
| `path` | catalog display path (placeholders kept: `:customer_id`, `:token`) | `text-mono` chip |
| `enabled` | `Captcha::SurfaceSettings.enabled?(key)` (missing key → catalog `default_enabled?`) | `ModuleToggleComponent` `on:` |
| `protected_count` | count of `enabled == true` | header badge |
| `total_count` | catalog size | header caption |

**ASCII — desktop**

```
┌─ card overflow-hidden ──────────────────────────────────────────────┐
│ card-header                                                         │
│  ┌─────────────────────────────────────┬──────────────────────────┐ │
│  │ section-header                      │ [3 protected]   12       │ │
│  │ Protected public pages              │  Badge :success  caption │ │
│  │ text-caption                        │                          │ │
│  │ Require a captcha on these public   │                          │ │
│  │ platform forms.                     │                          │ │
│  └─────────────────────────────────────┴──────────────────────────┘ │
│                                                                     │
│  ┌ group header (bg-surface-subtle) ──────────────────────────────┐ │
│  │ text-label  Authentication                                     │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  divide-y divide-border-subtle                                      │
│  ┌ row px-6 py-4 ─────────────────────────────────────────────────┐ │
│  │  Sign in                                      [ ========○ ]    │ │
│  │  /auth/sign_in   (text-mono chip)             switch, no label │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ row ───────────────────────────────────────────────────────────┐ │
│  │  Customer sign-up                             [ ========○ ]    │ │
│  │  /auth/sign_up                                                 │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ row ───────────────────────────────────────────────────────────┐ │
│  │  Forgot password                              [ ========○ ]    │ │
│  │  /auth/password/new                                            │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ row ───────────────────────────────────────────────────────────┐ │
│  │  Resend confirmation                          [ ○======== ]    │ │
│  │  /auth/confirmation/new                                        │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ row ───────────────────────────────────────────────────────────┐ │
│  │  Member sign-up                               [ ○======== ]    │ │
│  │  /:customer_id/auth/sign_up                                    │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌ group  Account ────────────────────────────────────────────────┐ │
│  │  Account settings                             [ ○======== ]    │ │
│  │  /auth/edit                                                    │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ group  MFA ────────────────────────────────────────────────────┐ │
│  │  MFA challenge / MFA setup / MFA recovery                      │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ group  Payments ───────────────────────────────────────────────┐ │
│  │  Payment checkout                             [ ○======== ]    │ │
│  │  /:customer_id/payments/checkout                               │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ group  Email ──────────────────────────────────────────────────┐ │
│  │  Email unsubscribe                            [ ○======== ]    │ │
│  │  /unsubscribe/:token                                           │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ group  OAuth ──────────────────────────────────────────────────┐ │
│  │  OAuth authorize                              [ ○======== ]    │ │
│  │  /oauth/authorize                                              │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌ group  Other  (only if catalog has unnamed surfaces) ──────────┐ │
│  │  {humanized name}                             [ ○======== ]    │ │
│  │  {display path}                                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**ASCII — mobile (< `sm`)**

```
┌ row px-6 py-4 flex flex-col items-stretch gap-3 ─┐
│  Sign in                                          │
│  /auth/sign_in                                    │
│  [ ========○ ]     ← switch under name/path       │
└───────────────────────────────────────────────────┘
```

Row layout classes (match Module Controls / payment tender rows, plus the mobile stack):

```
li.px-6.py-4.flex.flex-col.items-stretch.gap-3.sm:flex-row.sm:items-center.sm:justify-between.sm:gap-4
```

Left cluster: `min-w-0` (name + path). Right cluster: `ModuleToggleComponent` with
`show_label: false` (same as module status / required / handoff rows). On `sm+`
the existing `ml-auto` on the toggle keeps it trailing.

**Expected rows (locked catalog)**

Group order is fixed. Omit a group header when that group has zero rows.
“Other” appears only for newly discovered GET+mutate public controllers that
have no i18n name yet (switch **off** by default).

| Group | Surface key | Name (en) | Display path |
|---|---|---|---|
| Authentication | `authentication/sessions` | Sign in | `/auth/sign_in` |
| Authentication | `authentication/customer_registrations` | Customer sign-up | `/auth/sign_up` |
| Authentication | `authentication/passwords` | Forgot password | `/auth/password/new` |
| Authentication | `authentication/confirmations` | Resend confirmation | `/auth/confirmation/new` |
| Authentication | `authentication/registrations#sign_up` | Member sign-up | `/:customer_id/auth/sign_up` |
| Account | `authentication/registrations#account` | Account settings | `/auth/edit` |
| MFA | `authentication/mfa_sessions` | MFA challenge | `/:customer_id/auth/mfa/session` |
| MFA | `authentication/mfa_setups` | MFA setup | `/:customer_id/auth/mfa/setup` |
| MFA | `authentication/mfa_recoveries` | MFA recovery | `/:customer_id/auth/mfa_recovery/new` |
| Payments | `payments/checkouts` | Payment checkout | `/:customer_id/payments/checkout` |
| Email | `emails/unsubscribes` | Email unsubscribe | `/unsubscribe/:token` |
| OAuth | `oauth/authorizations` | OAuth authorize | `/oauth/authorize` |
| Other | *(discovered)* | humanized controller name until i18n exists | route display path |

`authentication/sessions` **merges** `authentication/sign_in_links` — one row, one switch.
Do not show a second “email sign-in link” row.

Display paths keep route placeholders (`:customer_id`, `:token`). Do not substitute a
live tenant id on the platform card.

**Header count badge**

Right side of `card-header`, modeled on the Technical → Models count:

```
flex items-center gap-2 flex-shrink-0
  BadgeComponent variant: :success (count > 0) | :default (count == 0), size: :sm
    → "3 protected"   (i18n count)
  span.text-caption
    → "12"            (total surfaces; no word, like the Models caption number)
```

On wrap (`flex-wrap`), the badge sits under the title on narrow viewports.
`aria-label` on the header cluster: “3 of 12 surfaces protected”.

**Empty / loading / error**

| State | Treatment |
|---|---|
| Loading | Server-rendered. No skeleton. First paint is the list. |
| Empty catalog (should not happen) | Same empty block as Models: `p-6 text-center` + `text-body-sm italic` “No public platform forms were discovered.” |
| Empty group | Hide the group entirely. |
| Toggle success | Full page reload (existing `ModuleToggleComponent` `form_with local: true`). Flash `notice` via dashboard layout. |
| Toggle failure / unknown key | Flash `alert` (error). List unchanged. |
| Provider missing / inactive | Switches stay **enabled**. Widget does not render on public forms (existing fail-open/closed policy). No disabled styling. |
| Permission denied | Existing platform namespace gate (owner / `81721200`). No in-card error. |

**Actions**

| Kind | Control | Where |
|---|---|---|
| Primary | `ModuleToggleComponent` PATCH | Trailing edge of each row |
| Secondary | none on this card | — |
| Destructive | none | — |

No confirm dialog. Last successful write wins.

**Toggle wiring**

```
Admin::Maintenance::Platform::ModuleToggleComponent.new(
  url:           platform_surface_toggle_url,   # nested under captcha module settings
  field:         "enabled",
  on:            surface.enabled?,
  extra_params:  { surface_key: surface.key },
  show_label:    false
)
```

PATCH body: `{ surface_key, enabled }` (`enabled` is `1`/`0` via `next_value`).
Unknown keys → 404, no write.

Add an optional `aria_label:` to `ModuleToggleComponent` if the switch has no
visible On/Off text, and pass
`t("captcha.platform_pages.toggle_aria", name: surface_name)`
(en: “Protect %{name}”). Do not invent a second switch component.

---

### A2. Configuration link card (REUSE, do not invent markup)

**Component:** `Admin::Maintenance::Platform::SettingsLinkCardComponent`

This component already exists for exactly this job (icon + title + description +
chevron). The SettingsComponent / verifications index stay as they are.

```
Admin::Maintenance::Platform::SettingsLinkCardComponent.new(
  title:    t("maint_platform.module_settings.show.captcha.title"),
  subtitle: t("maint_platform.module_settings.show.captcha.subtitle"),
  links: [
    {
      path:        admin_maintenance_platform_module_settings_captcha_settings_path(current_customer_id),
      title:       t("maint_platform.module_settings.show.captcha.credentials"),
      description: t("maint_platform.module_settings.show.captcha.credentials_desc"),
      icon:        :lock_closed
    },
    {
      path:        admin_maintenance_platform_module_settings_captcha_verifications_path(current_customer_id),
      title:       t("maint_platform.module_settings.show.captcha.verifications"),
      description: t("maint_platform.module_settings.show.captcha.verifications_desc"),
      icon:        :clipboard_list
    }
  ]
)
```

Row hover: existing `hover:bg-canvas-elevated`. Do not put switches on this card.

---

### B / C. Nested destinations

No layout work. Deep links from A2 only.

---

### D. Customer Captcha settings

**Canonical URL:** `/:cid/admin/settings/modules/captcha`
(sidebar + `FeatureModules::Captcha::Registration` `entry_path`).

**Implementation home:** `Admin::Settings::Modules::Captcha::StatusController#show`
and `StatusComponent`. Today the dedicated route is
`/:cid/admin/settings/modules/captcha/status` and the sidebar URL hits generic
`module_configs#show`. Security/routes should make the sidebar URL render this
page (alias or redirect). Frontend keeps a single Settings leaf — do not ship
two competing Captcha settings screens.

**Replace** the current `max-w-2xl` gray `bg-white shadow rounded-lg` box and its
count-only line. Wrap the view in `AdminPageComponent` like
`app/views/admin/settings/modules/authentication/sign_up/show.html.erb`.

**ASCII — desktop**

```
AdminPageComponent
  breadcrumbs: Settings → Captcha
  title:       Captcha
  description: Require a captcha on this customer's public pages.

  [ Alert warning ]  This module is disabled. Enable it under Maintenance → Modules to use it.
                     (only when module_enabled == false)

  [ Alert warning ]  Captcha credentials are not configured by the platform owner.
                     (only when !configured?)

  +-- card overflow-hidden --------------------------------------------+
  | card-header                                                        |
  |  section-header  Status                                            |
  |  text-caption    Active provider: Aliyun Captcha                   |
  +--------------------------------------------------------------------+

  +-- card overflow-hidden --------------------------------------------+
  | card-header                                                        |
  |  Public pages                               [2 protected]   5      |
  |  Pages with visibility Public, including unpublished ones.         |
  | divide-y divide-border-subtle                                      |
  | + row px-6 py-4 --------------------------------------------------+ |
  | |  Contact us          [Launched]              [ ========O ]      | |
  | |  /42/page/a1b2c3d4-...                                          | |
  | +-----------------------------------------------------------------+ |
  | + row ------------------------------------------------------------+ |
  | |  Event RSVP          [Not launched]          [ O======== ]      | |
  | |  /42/page/e5f6...                                               | |
  | +-----------------------------------------------------------------+ |
  +--------------------------------------------------------------------+
```

**ASCII — empty**

```
┌─ card ──────────────────────────────────────────────────────────────┐
│ card-header  Public pages   [0 protected]   0                       │
│                                                                     │
│  p-12 text-center                                                   │
│    (muted icon circle, optional — match module_settings index empty)│
│    text-body-sm italic                                              │
│    No public pages yet. Pages set to Public will appear here,       │
│    including unpublished ones.                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Data**

| Region | Field | Source |
|---|---|---|
| Alerts | module disabled | `FeatureModules::Module.enabled?(key: "captcha", customer_id:)` |
| Alerts | credentials missing | `Captcha::ProviderSettings.active&.configured?` |
| Status card | provider name | `Captcha::Providers.for(settings.provider).display_name` or “None” |
| Pages card | page name | `Page#name` |
| Pages card | public path | `/:cid/page/:uuid` with live `customer_id` and `page.public_uuid` |
| Pages card | launched badge | `Page#launched` |
| Pages card | switch | `Page#captcha_enabled?` |

Scope: `Page.for_current_customer.where(visibility: "public")` only.
Customer-owned rows. Shared pages (`customer_id` NULL) never appear.
Include `launched: false` (unpublished) so admins can pre-toggle.

Sort: `Page.by_name` (stable A–Z). No search, no pagination (typically < 20).

**Launched badge**

| State | Badge |
|---|---|
| `launched == true` | `BadgeComponent` `:success` `:sm` — `t("common.status.launched")` → “Launched” |
| `launched == false` | `BadgeComponent` `:default` `:sm` — `t("captcha.customer_status.not_launched")` → “Not launched” |

Place the badge on the **name line** (`flex items-center gap-2 flex-wrap`), not on the path line.

**Public path chip**

Same treatment as the platform key chip / handoff entry path:

```
span.text-mono.text-xs.bg-surface-active.px-1.5.py-0.5.rounded.break-all
```

Value example: `/42/page/7c9e6679-7425-40de-944b-e07fc1f90ae7`
(not a placeholder; this is a tenant-owned URL).

**Provider line**

Keep it. Put it as the Status card subtitle (`text-caption`):
`t("captcha.customer_status.provider", name: provider_name)` → “Active provider: %{name}”.
When no active provider: name = `t("captcha.platform_settings.none")` → “None”.

Do **not** keep the old “N pages have captcha enabled.” sentence — the header badge
replaces that count.

**Alerts**

Replace the raw yellow boxes with `AlertComponent`:

```
<%= render AlertComponent.new(message: t("captcha.customer_status.module_disabled"), type: :warning) unless module_enabled %>
<%= render AlertComponent.new(message: t("captcha.customer_status.credentials_missing"), type: :warning) unless configured? %>
```

Reuse the existing English strings (already keyed). Flash `notice`/`alert` stay
in the dashboard layout (`AdminPageComponent` does not render flash).

Switches stay **enabled** when the module is off or credentials are missing
(flags persist; widget/verify stay off). Alerts explain why the public form
will not show a challenge yet.

**Empty / loading / error**

| State | Treatment |
|---|---|
| Loading | Server-rendered. No skeleton. |
| No public pages | Empty block inside the pages card (above). Status card + alerts still render. |
| Toggle success | Reload + flash notice. |
| Cross-tenant page id | 404 (no write). No in-card error. |
| Member / anonymous | Existing admin route gate. |
| Owner on tenant B | Sees only B’s public pages. |

**Actions**

| Kind | Control | Where |
|---|---|---|
| Primary | `ModuleToggleComponent` PATCH | Trailing edge of each page row |
| Secondary | none | — |
| Destructive | none | — |

```
Admin::Maintenance::Platform::ModuleToggleComponent.new(
  url:          admin_settings_modules_captcha_page_path(current_customer_id, page),
  field:        "enabled",
  on:           page.captcha_enabled?,
  show_label:   false
)
```

(Exact helper name is the security engineer’s; the UX contract is PATCH +
`enabled` `1`/`0` on a tenant-scoped page id.)

**Responsive:** same stack as A1 — name / badge / path above the switch below `sm`.

---

### E. Page-builder toggle (no layout change)

`Captcha::PageEditorToggleComponent` stays in the editor Security section.
Saving the editor or flipping D’s switch writes the same
`configuration["captcha"]["enabled"]` flag. After either write, the other
surface reflects the new state on next render. Do not add a second flag.

---

## 3. Interaction flow

### Story 1 — Owner protects a platform form

1. Owner opens `/81721200/admin/maintenance/platform/module_settings` (index).
2. Clicks the **Captcha** row (resolved by key, not id `2`).
3. Lands on show, Settings tab (default). Sees Protected public pages + Configuration cards.
4. Under Authentication, Sign in is on (default). Resend confirmation is off.
5. Clicks the Resend confirmation switch (`role="switch"`, `aria-checked="false"`).
6. Browser PATCHes `{ surface_key: "authentication/confirmations", enabled: "1" }`.
7. Success → redirect back to the same show URL + flash “Captcha protection updated.”
8. Badge increments (“3 protected” → “4 protected”). Switch is on.
9. Public `GET /auth/confirmation/new` now renders `Captcha::WidgetComponent` (`platform: true`, `surface:` set). POST verifies.

**Failure — unknown key:** PATCH 404. Flash error. No write.

**Failure — not owner / not 81721200:** existing platform gate. No card.

**Failure — vendor down / credentials missing:** toggle still persists. Public form follows
the stored fail policy. Owner can still open Configuration → Credentials (B) to fix keys.

### Story 2 — Owner opens vendor credentials / verification log

1. From A, clicks **Vendor credentials** row.
2. Navigates to B (`.../module_settings/captcha/settings`). Existing page. No restyle.
3. Back (browser or breadcrumbs). Clicks **Verification log**.
4. Lands on C. Existing ledger. No restyle.

### Story 3 — Admin toggles a public page (including unpublished)

1. Tenant admin opens Settings → Captcha (`/:cid/admin/settings/modules/captcha`).
2. Sees alerts (if any), provider line, and this tenant’s public pages.
3. An unpublished “Event RSVP” row is listed with a **Not launched** badge and switch off.
4. Admin flips the switch on (pre-toggle).
5. PATCH tenant-scoped page id. Success flash. Badge increments.
6. Page editor Security checkbox is checked on next open (lockstep).
7. When the page is later launched, the public `/:cid/page/:uuid` form shows the widget
   **only if** the Captcha module is enabled for the tenant **and** credentials exist.

**Failure — module disabled:** switch still saves. Alert remains. Widget stays off.

**Failure — credentials missing:** same as above.

**Failure — cross-tenant page id:** 404.

**Failure — shared page id:** 404 (shared pages are not in the list).

### Story 4 — Empty customer catalog

1. Admin opens Settings → Captcha on a tenant with no `visibility=public` pages.
2. Status card + alerts render. Pages card shows the empty state.
3. No switch. No search. No CTA to create a page (creation lives under Maintenance → Pages).

### Story 5 — Member / anonymous

- Settings and platform URLs: denied by existing controller gates.
- No member Captcha settings surface.

### Story 6 — Concurrent toggles

Last successful PATCH wins. No locking UI. No optimistic client state
(`ModuleToggleComponent` is a real form POST, then reload).

---

## 4. Component reuse map

| Piece | Component | New? |
|---|---|---|
| Platform show chrome, tabs, Module Controls | existing `module_settings/show.html.erb` | no |
| Protected public pages card | `Admin::Maintenance::Platform::Captcha::ProtectedPagesComponent` | **yes** |
| Per-row switch (A and D) | `Admin::Maintenance::Platform::ModuleToggleComponent` | no (optional `aria_label:` prop) |
| Count / launched badges | `BadgeComponent` | no |
| Flash + customer alerts | `AlertComponent` | no |
| Credentials + verifications rows | `Admin::Maintenance::Platform::SettingsLinkCardComponent` | no |
| Vendor credentials page | `Admin::Maintenance::Platform::Captcha::SettingsComponent` | no (do not restyle) |
| Customer page shell | `AdminPageComponent` + `BreadcrumbsComponent` (via AdminPage) | no |
| Customer alerts + provider + page list | rewrite `Admin::Settings::Modules::Captcha::StatusComponent` | rewrite template; keep the class |
| Page-builder checkbox | `Captcha::PageEditorToggleComponent` | no |
| Public widget | `Captcha::WidgetComponent` | no |

Do **not** build a shared row ViewComponent unless the two lists drift into
copy-paste soup. Inline rows (like payment tender rows on the same show page)
are the project vocabulary.

**ProtectedPagesComponent props (suggested)**

```
initialize(groups:, toggle_url:, protected_count:, total_count:)
# groups: [{ key:, label:, surfaces: [{ key:, name:, path:, enabled: }] }]
```

**StatusComponent props (updated)**

```
initialize(settings:, module_enabled:, pages:)
# pages: [{ id:, name:, public_path:, launched:, captcha_enabled: }]
# drop pages_with_captcha integer — derive protected_count from pages
```

---

## 5. Tailwind & Stimulus notes

### Tailwind (match show.html.erb / SettingsLinkCard / Module Controls)

| Token | Use |
|---|---|
| `card overflow-hidden` | both new cards |
| `card-header` | title block |
| `section-header` | card title |
| `text-caption` | subtitle, total count, empty italic companion |
| `text-body text-text-primary font-medium` | row name |
| `text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded` | path chip |
| `text-label` | group header label |
| `bg-surface-subtle` | group header strip (`px-6 py-2`) |
| `divide-y divide-border-subtle` | row list |
| `px-6 py-4` | row padding (same as Module Controls / SMS links) |
| `flex flex-col items-stretch gap-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4` | responsive row |
| `min-w-0` | name/path cluster (truncate-safe) |
| `break-all` | long UUID paths on mobile |
| `flex items-center justify-between gap-3 flex-wrap` | card-header title + badge |
| `space-y-6` | stack of cards in the Settings tab / customer body |

Do **not** use the legacy Captcha settings palette (`bg-white shadow`, `bg-blue-600`,
`text-gray-500`, `max-w-2xl`) on these new cards. That palette stays only on the
unrestyled credentials page (B).

Do **not** add custom CSS or a second JS framework.

### Stimulus

**None for these lists.** Typical size is ~12 platform surfaces and < 20 customer
pages. Skip search, filter, and client-side grouping.

Existing `tabs` controller on the platform show page is unchanged
(`data-controller="tabs"`, Settings default).

`ModuleToggleComponent` is a server PATCH (`form_with`, `local: true`), not a
Stimulus action. Keep it that way.

If a later change adds search, the controller would be `captcha-protection-filter`
with values `query` and targets `row`, `empty` — **do not build it in this slice**.

### I18n keys (en = hard-coded English)

Add matching `zh-CN` for every key. Suggested homes:

**`config/locales/maint_platform.en.yml`** (platform Settings tab, next to `sms:` / `email:`)

```yaml
maint_platform:
  module_settings:
    show:
      captcha:
        title: "Captcha configuration"
        subtitle: "Vendor credentials and the verification audit log."
        credentials: "Vendor credentials"
        credentials_desc: "Active provider, keys, failure policy, and connection test."
        verifications: "Verification log"
        verifications_desc: "Audit captcha attempts across all tenants."
        pages_title: "Protected public pages"
        pages_subtitle: "Require a captcha on these public platform forms."
        protected_count:
          one: "%{count} protected"
          other: "%{count} protected"
        total_count: "%{count}"
        header_aria: "%{protected} of %{total} surfaces protected"
        empty: "No public platform forms were discovered."
```

**`config/locales/captcha.en.yml`** (shared names + customer + flash + aria)

```yaml
captcha:
  surface_groups:
    authentication: "Authentication"
    account: "Account"
    mfa: "MFA"
    payments: "Payments"
    email: "Email"
    oauth: "OAuth"
    other: "Other"
  surfaces:
    authentication_sessions: "Sign in"
    authentication_customer_registrations: "Customer sign-up"
    authentication_passwords: "Forgot password"
    authentication_confirmations: "Resend confirmation"
    authentication_registrations_sign_up: "Member sign-up"
    authentication_registrations_account: "Account settings"
    authentication_mfa_sessions: "MFA challenge"
    authentication_mfa_setups: "MFA setup"
    authentication_mfa_recoveries: "MFA recovery"
    payments_checkouts: "Payment checkout"
    emails_unsubscribes: "Email unsubscribe"
    oauth_authorizations: "OAuth authorize"
  platform_pages:
    toggle_aria: "Protect %{name}"
    flash_updated: "Captcha protection updated."
    flash_failed: "Could not update captcha protection."
  customer_status:
    # keep title, provider, module_disabled, credentials_missing
    description: "Require a captcha on this customer's public pages."
    status_header: "Status"
    pages_title: "Public pages"
    pages_subtitle: "Pages with visibility Public, including unpublished ones."
    not_launched: "Not launched"
    empty: "No public pages yet. Pages set to Public will appear here, including unpublished ones."
    toggle_aria: "Require captcha on %{name}"
    flash_updated: "Captcha protection updated."
    # drop the pages_using count sentence from the UI (keys may remain unused)
```

**`config/locales/admin_settings.*.yml`** breadcrumbs if the customer page uses
`AdminPageComponent`:

```yaml
admin_settings:
  breadcrumbs:
    captcha: "Captcha"
```

Reuse `feature_modules.captcha.settings.status` (“Captcha”) for the sidebar leaf
and page title when the English is identical.

**zh-CN (idiomatic, not word-for-word)** — examples:

| en | zh-CN |
|---|---|
| Protected public pages | 受保护的公开页面 |
| Require a captcha on these public platform forms. | 对这些公开的平台表单启用验证码。 |
| 3 protected | 已保护 3 项 |
| Sign in | 登录 |
| Customer sign-up | 客户注册 |
| Forgot password | 忘记密码 |
| Resend confirmation | 重发确认邮件 |
| Member sign-up | 成员注册 |
| Account settings | 账户设置 |
| MFA challenge | 多重验证挑战 |
| MFA setup | 多重验证设置 |
| MFA recovery | 多重验证恢复 |
| Payment checkout | 支付结账 |
| Email unsubscribe | 邮件退订 |
| OAuth authorize | OAuth 授权 |
| Vendor credentials | 服务商凭证 |
| Verification log | 验证日志 |
| Public pages | 公开页面 |
| Pages with visibility Public, including unpublished ones. | 可见性为公开的页面（含未上线）。 |
| Not launched | 未上线 |
| No public pages yet. Pages set to Public will appear here, including unpublished ones. | 暂无公开页面。将页面可见性设为公开后会显示在此，包括尚未上线的页面。 |
| Captcha protection updated. | 验证码保护已更新。 |
| Protect %{name} | 保护%{name} |
| Active provider: %{name} | 当前服务商：%{name} |

### Accessibility

- Group headers are static `<h3 class="text-label">`, not buttons.
- Each switch: `role="switch"` (already on `ModuleToggleComponent`) + `aria-checked` + `aria-label` with the row name.
- Header count cluster: `aria-label` with “3 of 12 surfaces protected”.
- Path chips are text, not links (the public form is not opened from this admin card).
- Do not wrap the whole row in a `<a>` — the switch must remain a separate control (unlike SettingsLinkCard rows).

### Responsive checklist

- `sm:` breakpoint only (same as existing admin cards).
- Name + path (+ badge on D) stack above the switch.
- Path chip `break-all` so UUIDs do not overflow.
- Card header badge wraps under the title; no fixed min-width.
- Configuration link rows already wrap (`flex` + `min-w-0` + truncate) — leave as-is.

---

## Frontend implementation notes (non-layout)

- Gate the new platform cards with `@feature_module.key == "captcha"` inside the
  existing `settings_cards` capture so the empty-state check stays automatic.
- Do not add captcha cards to the Technical Reference tab.
- Do not restyle B, C, or E.
- No Stimulus controller in this slice.
- No new role, no new nav area, no Modules entries table.

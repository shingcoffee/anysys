---
title: Dashboard Foundation Refactor — Phase 1
status: draft
date: 2026-04-28
scope: phase-1-foundation
---

# Dashboard Foundation Refactor — Phase 1

Refactor the customer dashboard shell to a three-zone architecture (Workspace /
Admin / Platform) with a professional top bar and two-row navigation that
collapses responsively. Phase 1 covers only the **shell and navigation
foundation**; page-level components (headers, tables, forms) and information-
architecture changes ship in later phases.

---

## 1. Goals & Non-Goals

### Goals

- Replace the flat 4-section nav (Entity Entries / Pages / Modules / Settings)
  with a **three-zone** top-level structure: **Workspace**, **Admin**, **Platform**.
- Refactor the top bar into a professional shell: workspace switcher, ⌘K search
  affordance, help, notifications slot, user menu.
- Introduce a **two-row nav** on desktop/laptop (zone tabs above, section
  sub-tabs below); on mobile, the drawer holds both levels as an accordion.
- Treat the **landing page** as a zone-level home (no sidebar); other sections
  keep a tree sidebar.
- Commit to **spacious density** (larger type, generous whitespace) in the
  shell chrome.
- Support responsive breakpoints: desktop ≥1280px, laptop 768–1279px,
  mobile <768px.
- Preserve the contributor pattern for building sidebar trees.
- Stay within the existing stack: TailwindCSS only, StimulusJS only,
  ViewComponent, Rails conventions.

### Non-Goals (deferred)

- **Phase 2** — page-header standardization, Table / FormField / FormGroup
  design-system kit, migration of existing pages to those components.
- **Phase 3** — information-architecture changes: move Users / Customer /
  Module Settings into Admin zone, unify `/feature_modules/*` and
  `/dashboard/settings/modules/*`, surface Flowcharts / Templates in Platform.
- No real search backend — ⌘K opens a palette with a placeholder empty state.
- No notifications backend — bell icon is a visual slot.
- No changes to page-level views outside the shell.

---

## 2. Zone Model

### Zones and role gating

| Zone | Visible to | Default sections (Phase 1) |
|---|---|---|
| **Workspace** | all signed-in users | Home, Entity Entries, Pages, Modules |
| **Admin** | `admin` or `owner` role on the tenant | (empty in Phase 1; populated in Phase 3 — see note) |
| **Platform** | platform owner (see §2.1) | (empty in Phase 1; populated in Phase 3) |

Phase 1 ships the zone **infrastructure** but does NOT relocate existing pages.
Admin and Platform zones render with an empty-state panel ("Coming soon — this
area will house administrative / platform tools") until Phase 3 migrates
content in. This keeps Phase 1 a pure shell refactor that cannot break any
existing page.

When a zone's `sections` array is empty (Admin and Platform in Phase 1), the
**section-tabs row is hidden** for that zone and the **sidebar is omitted** —
only the zone's landing (empty-state) renders in the main content area.

Today's **Settings** section content remains addressable at its current URLs
(`/dashboard/settings/*`) and stays inside the **Workspace** zone under a
"Settings" section, exactly as today. Phase 3 moves it.

### 2.1 Platform-owner role

The current `Authentication::User` model has roles `member / admin / owner`,
all scoped to a single tenant. There is no cross-tenant "platform owner" role
in the schema today.

Phase 1 introduces a single predicate `User#platform_owner?` that returns
`false` by default. Its initial implementation returns `true` only for users
whose email matches a `PLATFORM_OWNER_EMAILS` env var (comma-separated). This
is explicitly temporary — Phase 3 will replace it with a proper schema column
or a separate `PlatformAdmin` model. Downstream gate logic references only
`current_user.platform_owner?`, so the swap is trivial.

### 2.2 Zone root paths

| Zone | Root URL | Controller#action |
|---|---|---|
| Workspace | `/:customer_id/` | `dashboard/landing#show` (unchanged) |
| Admin | `/:customer_id/admin` | `dashboard/admin#show` (new, renders empty-state in Phase 1) |
| Platform | `/:customer_id/platform` | `dashboard/platform#show` (new, renders empty-state in Phase 1) |

Switching zones navigates to the zone root. The active zone is inferred from
the URL prefix.

---

## 3. Layout Shell

### 3.1 Regions (desktop ≥1280px)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ TOPBAR    [logo] [Workspace ▾]    [⌘K search]      [?] [🔔] [👤 ▾]      │  h=56px
├─────────────────────────────────────────────────────────────────────────┤
│ ZONE TABS  ┌──────────┬───────┬──────────┐                               │  h=44px
│            │Workspace │ Admin │ Platform │   (active zone highlighted)  │
│            └──────────┴───────┴──────────┘                               │
├─────────────────────────────────────────────────────────────────────────┤
│ SECTION TABS  [ Home | Entity Entries | Pages | Modules | Settings ]     │  h=40px
├──────────────┬──────────────────────────────────────────────────────────┤
│              │                                                           │
│  SIDEBAR     │  MAIN                                                     │
│   (omitted   │   per-page max-width (see §3.4)                           │
│    on Home)  │                                                           │
│   w=260px    │                                                           │
│              │                                                           │
└──────────────┴──────────────────────────────────────────────────────────┘
```

### 3.2 Regions (laptop 768–1279px)

- Topbar: unchanged (⌘K collapses to an icon-only button at <1024px)
- Zone tabs row: unchanged
- Section tabs row: unchanged
- Sidebar: narrower (`w-56` / 224px)
- Main: fills remaining width

### 3.3 Regions (mobile <768px)

- Topbar: logo + workspace switcher (truncated), right side shows only ⌘K icon
  and user avatar. Hamburger button to the far right opens the drawer.
- Zone tabs row: **hidden**
- Section tabs row: **hidden**
- Sidebar: **hidden**
- Drawer (replaces all three hidden rows): full-height sheet sliding in from
  the left, containing:
  1. Zone switcher (segmented pill control: Workspace / Admin / Platform)
  2. Section list for the active zone (accordion)
  3. Sidebar tree for the active section

Drawer uses Tailwind `transition-transform` + `translate-x-{full|0}` for slide
animation, controlled by a Stimulus `dashboard-drawer` controller.

### 3.4 Per-page max-width

Pages declare their width tier via a layout helper:

```erb
<% content_for :container_width, :narrow %>   # max-w-3xl  (forms, settings)
<% content_for :container_width, :wide %>     # max-w-7xl  (tables, lists) — default
<% content_for :container_width, :full %>     # no max-w    (dashboards, canvases)
```

Helper reads `content_for(:container_width)` and maps to a Tailwind class.
Default is `:wide` if unspecified. This replaces the ad-hoc mix of
`max-w-7xl` / `max-w-[1400px]` / none across existing pages. Phase 1 only
introduces the mechanism; individual page migrations happen in Phase 2.

### 3.5 Spacing & typography (spacious density)

- Topbar height: **56px** (was 48px)
- Zone tab height: **44px**
- Section tab height: **40px**
- Sidebar item height: **36px** (was 28–32px)
- Body text: **14px (`text-sm`)** baseline; chrome labels use `text-sm`
  (was mixed `text-[11px]` / `text-[13px]`)
- Page title (h1) convention: **`text-xl font-semibold`** (Phase 2 enforces)
- Font: keep Inter / system stack already loaded

---

## 4. Components

All new and modified components live under `app/components/dashboard/`.

### 4.1 New components

| Component | Purpose | Slots / inputs |
|---|---|---|
| `Dashboard::ShellComponent` (refactored) | Top-level layout frame | `customer`, `user`, `tree`, `current_zone`, `current_section`, `current_path` |
| `Dashboard::ZoneTabsComponent` | Zone-level tab bar (top row) | `zones:`, `current_zone:`; renders only zones the user can access |
| `Dashboard::SectionTabsComponent` (refactored) | Section tabs inside a zone | `sections:` (from zone definition), `current_section:` |
| `Dashboard::WorkspaceSwitcherComponent` | Topbar workspace label + dropdown | `customer:`, `switchable_customers:`; for non-platform users renders as a static label (no dropdown) |
| `Dashboard::SearchButtonComponent` | ⌘K button + palette trigger | No inputs; opens palette via Stimulus |
| `Dashboard::SearchPaletteComponent` | Modal palette (empty state for Phase 1) | No inputs; Stimulus-controlled |
| `Dashboard::HelpMenuComponent` | Help dropdown (docs, shortcuts, about) | `user:` |
| `Dashboard::NotificationsButtonComponent` | Bell icon (visual only in Phase 1) | No inputs |
| `Dashboard::ZoneDefinition` (POJO, not a component) | Declares a zone's sections and gate | `key`, `label`, `path`, `sections[]`, `permitted_by` |

### 4.2 Refactored components

| Component | Change |
|---|---|
| `Dashboard::ShellComponent` | Adds zone-tabs row between topbar and section-tabs row; adds container-width helper; adds `current_zone` prop. |
| `Dashboard::TopbarComponent` | Replaces static customer-name label with `WorkspaceSwitcherComponent`; inserts `SearchButtonComponent`, `HelpMenuComponent`, `NotificationsButtonComponent` between it and the existing `UserMenuComponent`. |
| `Dashboard::SectionTabsComponent` | No longer hardcodes `TABS` constant; receives sections from the active zone's definition. Mobile variant removed (drawer handles mobile). |
| `Dashboard::DrawerComponent` | Restructured to accordion layout: zone pill → section list → sidebar tree. Uses `transition-transform` for slide animation. |
| `Dashboard::SidebarComponent` | Unchanged behavior; receives `tree` for the currently-active section only (not the whole dashboard). Narrower on laptop breakpoint. |
| `Dashboard::UserMenuComponent` | Minor polish — avatar uses initials-on-indigo-600 consistently; dropdown item heights bumped to 36px for touch. |

### 4.3 Zone & section definitions

Define zones declaratively in a single file:

`app/services/dashboard/zone_registry.rb`

```ruby
module Dashboard
  class ZoneRegistry
    ZONES = [
      ZoneDefinition.new(
        key: :workspace,
        label: "Workspace",
        path: ->(customer) { "/#{customer.id}/" },
        permitted_by: ->(_user) { true },
        sections: [
          { key: :home,           label: "Home",           path: :dashboard_root_path },
          { key: :entity_entries, label: "Entity Entries", path: :dashboard_entity_entries_path },
          { key: :pages,          label: "Pages",          path: :pages_path },
          { key: :modules,        label: "Modules",        path: :dashboard_modules_path },
          { key: :settings,       label: "Settings",       path: :settings_path } # stays in Workspace in Phase 1
        ]
      ),
      ZoneDefinition.new(
        key: :admin,
        label: "Admin",
        path: ->(customer) { "/#{customer.id}/admin" },
        permitted_by: :admin_or_owner?,
        sections: [] # populated in Phase 3
      ),
      ZoneDefinition.new(
        key: :platform,
        label: "Platform",
        path: ->(customer) { "/#{customer.id}/platform" },
        permitted_by: :platform_owner?,
        sections: [] # populated in Phase 3
      )
    ]

    def self.for(user)
      ZONES.select { |z| z.permitted_for?(user) }
    end
  end
end
```

`ZoneDefinition#permitted_for?(user)` accepts `permitted_by` as a Proc (called
with the user) or a Symbol (sent to the user as a predicate method), matching
the existing convention used by `Dashboard::SidebarNode`. Nil means always
permitted.

`Dashboard::SidebarBuilder` is updated to build the tree for the active
**section**, not the whole dashboard — contributors are grouped by section
(existing contributors already map 1:1 onto sections, so this is a rename).

---

## 5. Data Flow

```
request
  │
  ▼
ApplicationController#current_dashboard_zone      (new — reads URL prefix)
ApplicationController#current_dashboard_section   (existing — re-scoped)
  │
  ▼
dashboard.html.erb layout
  │
  ├─ Dashboard::ZoneRegistry.for(current_user)    → zones the user can see
  ├─ Dashboard::SidebarBuilder.build(context)     → sidebar tree for current section
  │
  ▼
Dashboard::ShellComponent(
  customer:, user:,
  zones:, current_zone:,
  sections:, current_section:,
  tree:, current_path:
)
  │
  ├─ TopbarComponent(customer, user, switchable_customers)
  │    ├─ WorkspaceSwitcherComponent
  │    ├─ SearchButtonComponent  →  (click) SearchPaletteComponent
  │    ├─ HelpMenuComponent
  │    ├─ NotificationsButtonComponent
  │    └─ UserMenuComponent
  │
  ├─ ZoneTabsComponent(zones:, current_zone:)
  │
  ├─ SectionTabsComponent(sections:, current_section:)
  │
  ├─ [ SidebarComponent(tree:, current_path:)  |  yield (main) ]
  │
  └─ DrawerComponent(zones, sections, tree, ...)   (mobile only)
```

`current_dashboard_zone` is derived from the request path:

```ruby
# ApplicationController
def current_dashboard_zone
  path = request.path
  return :admin    if path.match?(%r{\A/\d{8}/admin(\z|/)})
  return :platform if path.match?(%r{\A/\d{8}/platform(\z|/)})
  :workspace
end
```

The existing `current_dashboard_section` helper is retained and maps URL
prefixes to section keys; its map grows by `:home` for the zone root.

---

## 6. Stimulus Controllers

| Controller | File | Purpose |
|---|---|---|
| `dashboard-drawer` (refactored) | `app/javascript/controllers/dashboard_drawer_controller.js` | Open/close mobile drawer; switch active zone and section inside the drawer; transition-based slide. |
| `dashboard-zone-tabs` (new) | `app/javascript/controllers/dashboard_zone_tabs_controller.js` | Keyboard navigation (Left/Right arrows) across zone tabs; nothing else — zones are regular links. |
| `dashboard-search` (new) | `app/javascript/controllers/dashboard_search_controller.js` | Toggle search palette on ⌘K / Ctrl+K; focus trap inside palette; close on Escape. |
| `dashboard-workspace-switcher` (new) | `app/javascript/controllers/dashboard_workspace_switcher_controller.js` | Dropdown toggle + click-outside-to-close (only attached when user has >1 switchable workspace). |
| `dashboard-help-menu` (new) | `app/javascript/controllers/dashboard_help_menu_controller.js` | Dropdown toggle + click-outside-to-close. |
| `dashboard-user-menu` (existing) | unchanged | — |

All controllers follow the existing `data-controller` + `data-action` Stimulus
conventions already in the codebase. No new JS dependencies.

---

## 7. Routes

Add two new routes under the existing tenant scope in `config/routes.rb`:

```ruby
scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do
  # ...existing routes...

  get "admin",    to: "dashboard/admin#show",    as: :dashboard_admin_root
  get "platform", to: "dashboard/platform#show", as: :dashboard_platform_root
end
```

Also update `ApplicationController::DASHBOARD_SECTION_BY_PATH_PREFIX` to map
the new zone-root prefixes.

---

## 8. Controllers

Two new controllers for zone roots; each renders an empty-state in Phase 1.

```ruby
# app/controllers/dashboard/admin_controller.rb
class Dashboard::AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_owner!   # existing concern

  def show
    # renders empty-state view in Phase 1; Phase 3 replaces with a real landing
  end
end

# app/controllers/dashboard/platform_controller.rb
class Dashboard::PlatformController < ApplicationController
  before_action :authenticate_user!
  before_action :require_platform_owner!   # new — checks current_user.platform_owner?

  def show
    # renders empty-state view in Phase 1
  end
end
```

The `require_platform_owner!` filter and `User#platform_owner?` predicate are
both introduced in this phase (see §2.1).

---

## 9. Error Handling

- **Unpermitted zone access** (e.g., non-admin hits `/:customer_id/admin`) —
  `require_admin_or_owner!` already raises `Pundit::NotAuthorizedError` (or
  the app's equivalent) and redirects to the dashboard root with a flash.
  Same behavior for `require_platform_owner!`.
- **Zone tab gating** — `ZoneTabsComponent` only renders zones the user can
  access, so unpermitted zones are never shown as links in the first place.
- **Mobile drawer on narrow viewports** — If JavaScript fails to load, the
  drawer degrades to a static `<details>` element (progressive enhancement via
  the `noscript`-friendly Stimulus setup already in use).
- **Workspace switcher with no alternatives** — renders as a non-interactive
  span (no dropdown chevron) when `switchable_customers.size <= 1`.

---

## 10. Testing Strategy

All testing via RSpec + existing helpers. No new test frameworks.

### 10.1 Unit / component specs

- `spec/components/dashboard/shell_component_spec.rb` — renders topbar, zone
  tabs, section tabs, sidebar; respects `current_zone`; omits sidebar on
  `:home` section.
- `spec/components/dashboard/zone_tabs_component_spec.rb` — filters by role,
  highlights active zone, renders nothing when user has only one zone.
- `spec/components/dashboard/workspace_switcher_component_spec.rb` — dropdown
  only renders when `switchable_customers.size > 1`.
- `spec/components/dashboard/search_button_component_spec.rb` + palette spec.
- `spec/components/dashboard/drawer_component_spec.rb` — accordion expand /
  collapse, zone-switch inside drawer.
- `spec/services/dashboard/zone_registry_spec.rb` — `for(user)` returns the
  right zones for member / admin / owner / platform_owner.

### 10.2 Request / system specs

- `spec/requests/dashboard/zone_access_spec.rb` — member gets 403 on
  `/admin`, admin succeeds; non-platform gets 403 on `/platform`.
- `spec/system/dashboard/shell_navigation_spec.rb` — Capybara test: sign in,
  click each zone tab, click each section tab, confirm correct page loads,
  sidebar reflects section.
- `spec/system/dashboard/responsive_spec.rb` — resize viewport to mobile,
  confirm drawer opens, zone pill switches, sections accordion works.
- `spec/system/dashboard/search_palette_spec.rb` — ⌘K opens palette, Escape
  closes, palette shows placeholder empty state.

### 10.3 Non-regression

- Existing dashboard specs (entity_entries, pages, modules index, settings)
  must continue to pass without modification. The shell contract is preserved:
  layout file name, `yield`, flash rendering, breadcrumbs component all
  unchanged from page-author perspective.

---

## 11. Migration & Rollout

Phase 1 has **zero data migrations** and no URL changes to existing pages.
Only two new routes (`/admin`, `/platform`) are added. Rollout:

1. Ship behind no feature flag — this is a pure shell refactor with an
   additive URL surface. The existing flat 4-section tabs are replaced in one
   deploy by the three-zone structure.
2. `PLATFORM_OWNER_EMAILS` env var is set before deploy (initial allowlist).
3. Post-deploy smoke: sign in as each role tier and confirm correct zones
   render.

If regressions are found, revert is a single-branch revert — no data to roll
back.

---

## 12. Open Questions

None blocking Phase 1. Deferred to their respective phases:

- (Phase 2) Exact `PageHeader` slot contract and Table / FormField kit API.
- (Phase 3) Final IA: which settings live in Admin vs Workspace, how module
  settings unify, exact Platform zone contents.
- (Phase 3) Replace `User#platform_owner?` email-allowlist with a schema
  change or dedicated `PlatformAdmin` model.

---

## 13. File-Change Summary (Phase 1)

**New**
- `app/controllers/dashboard/admin_controller.rb`
- `app/controllers/dashboard/platform_controller.rb`
- `app/views/dashboard/admin/show.html.erb` (empty-state)
- `app/views/dashboard/platform/show.html.erb` (empty-state)
- `app/services/dashboard/zone_registry.rb`
- `app/services/dashboard/zone_definition.rb`
- `app/components/dashboard/zone_tabs_component.{rb,html.erb}`
- `app/components/dashboard/workspace_switcher_component.{rb,html.erb}`
- `app/components/dashboard/search_button_component.{rb,html.erb}`
- `app/components/dashboard/search_palette_component.{rb,html.erb}`
- `app/components/dashboard/help_menu_component.{rb,html.erb}`
- `app/components/dashboard/notifications_button_component.{rb,html.erb}`
- `app/javascript/controllers/dashboard_zone_tabs_controller.js`
- `app/javascript/controllers/dashboard_search_controller.js`
- `app/javascript/controllers/dashboard_workspace_switcher_controller.js`
- `app/javascript/controllers/dashboard_help_menu_controller.js`
- Specs for each of the above.

**Modified**
- `config/routes.rb` — add `/admin` and `/platform` zone roots.
- `app/controllers/application_controller.rb` — add `current_dashboard_zone`;
  update `DASHBOARD_SECTION_BY_PATH_PREFIX`; add `require_platform_owner!`.
- `app/models/authentication/user.rb` — add `platform_owner?` predicate
  (env-allowlist implementation).
- `app/components/dashboard/shell_component.{rb,html.erb}` — add zone row;
  accept `current_zone`, `zones`, `sections`.
- `app/components/dashboard/topbar_component.{rb,html.erb}` — swap static
  label for workspace switcher; insert search / help / notifications.
- `app/components/dashboard/section_tabs_component.{rb,html.erb}` — remove
  `TABS` constant; accept `sections:` prop.
- `app/components/dashboard/drawer_component.{rb,html.erb}` — accordion
  layout; slide animation; zone pill.
- `app/components/dashboard/sidebar_component.{rb,html.erb}` — narrower on
  laptop breakpoint (`md:w-56 xl:w-64`).
- `app/services/dashboard/sidebar_builder.rb` — builds for a given section,
  not the whole dashboard.
- `app/views/layouts/dashboard.html.erb` — pass `current_zone`, `zones`,
  `sections` into the shell.
- `spec/components/dashboard/shell_component_spec.rb` and siblings — updated
  for the new prop surface.

**No page-level views are modified in Phase 1.**

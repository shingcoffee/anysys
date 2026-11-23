---
title: Dashboard Flat-Menu Refactor
status: draft
date: 2026-04-28
supersedes: 2026-04-28-dashboard-foundation-refactor-design.md (Phase 1)
---

# Dashboard Flat-Menu Refactor

Replace the Phase-1 three-zone shell (Workspace / Admin / Platform zone tabs +
section tabs below) with a **single flat menu bar**. Introduce a unified
paginated-list ViewComponent reused across the dashboard. Introduce a
`Maintenance` menu item (tenant `owner` only) for CRUD on entity / flowchart /
page **definitions**; plain members and admins see only the read/operate
surfaces (Entities, Pages, Modules, Settings, Account).

---

## 1. Goals & Non-Goals

### Goals

- Delete the Phase-1 zone infrastructure entirely. One flat menu row replaces
  the two-row zone + section nav.
- Menu items: **Home | Entities | Pages | Modules | Settings | Account |
  Maintenance**. Account is visible to all (members see trimmed content);
  Maintenance is visible only to tenant `owner`.
- Top bar is three clean regions: **left** logo + wordmark, **middle** ⌘K
  search, **right** help + notifications + user menu. Workspace switcher
  removed.
- Per-menu sidebars are fed by the existing `SidebarContributor` pattern
  (rekeyed from `section:` to `menu_item:`).
- Unify list behavior across the dashboard with a single
  `Dashboard::PaginatedListComponent` (search, sort, filter, pagination,
  optional batch actions, row actions). Consumers declare columns,
  searchable/sortable fields, and actions.
- Preserve spacious density from Phase 1 (topbar 56px, menu row 44px,
  sidebar items 36px, 14px body, Inter font, gray-50 surface, indigo-600
  accent).
- Stay within the existing stack: TailwindCSS-only, StimulusJS-only,
  ViewComponent, Trailblazer Activity for non-trivial controller flows,
  Reform for contracts, Kaminari for pagination.

### Non-Goals

- No redesign of the existing page-builder, flowchart editor, or entity schema
  form. Maintenance links straight into them for `edit`.
- No real search backend — ⌘K palette stays a placeholder (same as Phase 1).
- No notifications backend — bell stays visual-only.
- No URL changes to existing pages. New URLs are additive.
- No cross-tenant "platform" surface — `User#platform_owner?` (added in
  Phase 1) is **removed**. All menu gating is tenant-scoped.

---

## 2. Role Model

Existing `Authentication::User` roles — `member`, `admin`, `owner` — all
scoped to a single tenant. Each customer has its own `owner`.

Per-role visible menu items:

| Menu item   | member | admin | owner |
|-------------|:------:|:-----:|:-----:|
| Home        |   ✓    |   ✓   |   ✓   |
| Entities    |   ✓    |   ✓   |   ✓   |
| Pages       |   ✓    |   ✓   |   ✓   |
| Modules     |   ✓    |   ✓   |   ✓   |
| Settings    |   ✓    |   ✓   |   ✓   |
| Account     |   ✓    |   ✓   |   ✓   |
| Maintenance |        |       |   ✓   |

The **Account** item is visible to everyone. Inside Account, the `Users` node
is gated by `admin_or_owner?` via the existing `permitted_by:` contract on
`SidebarNode`, so members see only `Customer Profile`.

**Added predicate:** `Authentication::User#owner?` — returns
`role == "owner"`. Straightforward alias over the existing enum accessor; kept
explicit so controller filters and registry gates read cleanly.

**Removed predicate:** `Authentication::User#platform_owner?` and the
`PLATFORM_OWNER_EMAILS` env var reference. No longer used.

---

## 3. Layout Shell

### 3.1 Desktop (≥1280px)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ TOPBAR  [◆ Milestone]          [🔎 Search…    ⌘K]          [?] [🔔] [👤 ▾] │  h=56
├────────────────────────────────────────────────────────────────────────────┤
│ MENU BAR  [Home] [Entities] [Pages] [Modules] [Settings] [Account] [Maint.] │  h=44
├──────────────┬─────────────────────────────────────────────────────────────┤
│              │                                                              │
│  SIDEBAR     │  MAIN                                                        │
│   (omitted   │                                                              │
│    on Home)  │                                                              │
│   w=260px    │                                                              │
│              │                                                              │
└──────────────┴─────────────────────────────────────────────────────────────┘
```

### 3.2 Laptop (768–1279px)

- Topbar unchanged. ⌘K collapses to icon-only button <1024px.
- Menu bar unchanged.
- Sidebar narrows to `w-56` (224px).

### 3.3 Mobile (<768px)

- Topbar: logo | ⌘K icon | user avatar | hamburger.
- Menu bar: hidden.
- Sidebar: hidden.
- Drawer: single accordion — each menu item is a section; expanding shows
  that item's sidebar tree. No zone pill (zones are gone).

### 3.4 Top bar — three regions

`<header>` uses a CSS grid with `grid-cols-[auto_1fr_auto]`.

| Region | Contents |
|--------|---------|
| Left   | Inline SVG logo + wordmark "Milestone" (link → Home). |
| Middle | `SearchButtonComponent` centered, `max-w-lg`. |
| Right  | `HelpMenuComponent`, `NotificationsButtonComponent`, `UserMenuComponent`. |

`WorkspaceSwitcherComponent` is removed. The app's current-customer identity
is implicit in the URL; no per-tenant switcher is rendered.

### 3.5 Menu bar

Single `<nav>` row, pill-tab style from Phase-1 zone tabs:

- Active: `bg-white text-gray-900 ring-1 ring-gray-200 shadow-sm`.
- Idle:   `text-gray-600 hover:text-gray-900 hover:bg-gray-100`.
- Items are filtered via `MenuItem#permitted_for?(user)` before render —
  unauthorized items never reach the DOM.

### 3.6 Per-page max-width

Unchanged from Phase 1. `content_for(:container_width, :narrow|:wide|:full)`
maps to Tailwind max-widths via a helper; default is `:wide`.

---

## 4. Menu Registry

`app/services/dashboard/menu_registry.rb` replaces `zone_registry.rb`.

```ruby
module Dashboard
  class MenuRegistry
    ITEMS = [
      MenuItem.new(key: :home,         label: "Home",
                   path_proc: ->(c) { "/#{c.id}/" },
                   sidebar_contributor: nil),
      MenuItem.new(key: :entities,     label: "Entities",
                   path_proc: ->(c) { "/#{c.id}/dashboard/entities" },
                   sidebar_contributor: EntitiesContributor),
      MenuItem.new(key: :pages,        label: "Pages",
                   path_proc: ->(c) { "/#{c.id}/dashboard/pages" },
                   sidebar_contributor: PagesContributor),
      MenuItem.new(key: :modules,      label: "Modules",
                   path_proc: ->(c) { "/#{c.id}/dashboard/modules" },
                   sidebar_contributor: ModulesContributor),
      MenuItem.new(key: :settings,     label: "Settings",
                   path_proc: ->(c) { "/#{c.id}/dashboard/settings" },
                   sidebar_contributor: SettingsContributor),
      MenuItem.new(key: :account,      label: "Account",
                   path_proc: ->(c) { "/#{c.id}/dashboard/account" },
                   sidebar_contributor: AccountContributor),
      MenuItem.new(key: :maintenance,  label: "Maintenance",
                   path_proc: ->(c) { "/#{c.id}/dashboard/maintenance" },
                   permitted_by: :owner?,
                   sidebar_contributor: MaintenanceContributor)
    ].freeze

    def self.for(user)
      return [] if user.nil?
      ITEMS.select { |i| i.permitted_for?(user) }
    end

    def self.item(key) = ITEMS.find { |i| i.key == key }
  end
end
```

`MenuItem` (POJO, replaces `ZoneDefinition`):

```ruby
module Dashboard
  MenuItem = Struct.new(:key, :label, :path_proc, :permitted_by,
                        :sidebar_contributor, keyword_init: true) do
    def path_for(customer) = path_proc.call(customer)

    def permitted_for?(user)
      return true if permitted_by.nil?
      return permitted_by.call(user) if permitted_by.respond_to?(:call)
      user.public_send(permitted_by)
    end
  end
end
```

---

## 5. Sidebars per Menu Item

All contributors live under `app/services/dashboard/` and share the existing
`SidebarContributor` base.

### 5.1 Home
No sidebar. `ShellComponent#show_sidebar?` returns `false` when
`current_menu_item == :home`.

### 5.2 Entities (renamed from EntityEntriesContributor)

`Dashboard::EntitiesContributor`:

- Builds from `EntityAssociationGraph.build(customer_id)` (unchanged).
- Primaries first; each primary has its non-bridge children as nested nodes.
- Click → right pane renders the entity's entries list via the unified
  paginated list component.

### 5.3 Pages (simplified)

`Dashboard::PagesContributor`:

- Flat list of primary entities (via graph) as sidebar nodes, **plus** a
  synthetic top node `All pages` (default view).
- `All pages` → right pane shows all pages (paginated, batch-enabled,
  filter-enabled).
- Clicking a primary entity → right pane is the same component, pre-filtered
  by `bound_entity`. Batch actions **disabled** in the filtered view (per
  requirement Q12-B), implemented by omitting `batch_actions:` in the filtered
  controller action.

### 5.4 Modules (unchanged)

Unchanged from Phase 1. Each enabled `FeatureModule` is a group; children are
`registration_class.sidebar_contributions(:entries)`. Click → right pane is
the module's own records view (rendered with `PaginatedListComponent` going
forward, per §6).

### 5.5 Settings (trimmed)

`Dashboard::SettingsContributor`:

- No `Customer Profile` node (moved to Account).
- No `Users` node (moved to Account).
- Per-module: every enabled `FeatureModule` appears as a node.
  - Children = `sidebar_contributions(:settings)` if non-empty.
  - Otherwise node is a leaf with `path = /dashboard/settings/modules/:key`
    showing a generic "no settings to configure" empty state (Q7-A/i).

### 5.6 Account (new)

`Dashboard::AccountContributor`:

```ruby
def contribute
  [
    SidebarNode.new(key: "account.customer_profile",
                    label: "Customer Profile",
                    menu_item: :account,
                    path: "/#{customer_id}/dashboard/account/customer"),
    SidebarNode.new(key: "account.users",
                    label: "Users",
                    menu_item: :account,
                    path: "/#{customer_id}/dashboard/account/users",
                    permitted_by: :admin_or_owner?)
  ]
end
```

`Customer Profile` and `Users` routes redirect to the existing
`Dashboard::Settings::CustomerController` and `Dashboard::Settings::UsersController`
endpoints for Phase 1 implementation speed; a follow-up can move those
controllers physically if desired. No URL-level break.

### 5.7 Maintenance (new, owner only)

`Dashboard::MaintenanceContributor`:

```ruby
def contribute
  [
    leaf("Entities",   "/#{customer_id}/dashboard/maintenance/entities"),
    leaf("Flowcharts", "/#{customer_id}/dashboard/maintenance/flowcharts"),
    leaf("Pages",      "/#{customer_id}/dashboard/maintenance/pages")
  ]
end
```

Each leaf's right pane is a Maintenance CRUD index built on
`PaginatedListComponent`.

---

## 6. Unified PaginatedListComponent

`app/components/dashboard/paginated_list_component.{rb,html.erb}`.

### 6.1 Consumer API

```erb
<%= render Dashboard::PaginatedListComponent.new(
  records: @records,                               # Kaminari-paginated relation
  columns: [
    { key: :name,       label: "Name",        sortable: true },
    { key: :status,     label: "Status",      sortable: true,
      cell: ->(r) { render Dashboard::StatusBadgeComponent.new(status: r.status) } },
    { key: :updated_at, label: "Updated",     sortable: true,
      cell: ->(r) { helpers.time_ago_in_words(r.updated_at) } }
  ],
  search:  { param: :q,    placeholder: "Search by name or description" },
  sort:    { param: :sort, default: "updated_at:desc" },
  filters: [
    { key: :bound_entity, label: "Entity",         options: @entity_options },
    { key: :publish,      label: "Publish state",  options: PUBLISH_OPTIONS }
  ],
  row_actions:   ->(r) { [edit_action(r), delete_action(r)] },
  batch_actions: [activate_action, deactivate_action, delete_action], # omit to disable batch
  empty_state:   { title: "No records yet", cta: { label: "New", path: new_path } }
) %>
```

### 6.2 Rendered structure

```
┌──────────────────────────────────────────────────────────────────────┐
│ [🔎 search]   [Filter ▾] [Filter ▾]                          [+ New] │  toolbar
├──────────────────────────────────────────────────────────────────────┤
│ ☐ │ Name ▲ │ Status │ Updated │                        ⋯             │  header
├──────────────────────────────────────────────────────────────────────┤
│ ☐ │   …    │   …    │    …    │                 (Edit · Delete)      │
│ ☐ │   …    │   …    │    …    │                 (Edit · Delete)      │
├──────────────────────────────────────────────────────────────────────┤
│ [2 selected]  [Activate] [Deactivate] [Delete]      ← 1 · 2 · 3 · →  │  footer
└──────────────────────────────────────────────────────────────────────┘
```

- Default page size `per: 25`.
- Search debounced 300ms, submits `GET` preserving all params.
- Sort click on a column header toggles asc/desc/none, submits GET.
- Filter `<select>` submits GET on change.
- Row checkboxes reveal batch bar. Select-all selects visible page only.
- `batch_actions:` omitted → checkboxes + batch bar not rendered.
- No AJAX — full-page turbo-frame reload. Cheap and idiomatic.
- Accessibility: `<table role="grid">`, keyboard sort via Enter/Space on
  header cells, aria-sort on active column.

### 6.3 Server-side concern

`Dashboard::Listable` (mixed into list-type controllers):

```ruby
module Dashboard::Listable
  extend ActiveSupport::Concern

  def listable(scope, search: nil, sort: nil, filters: [], per: 25)
    relation = scope
    relation = apply_search(relation,  search,  params)   if search
    relation = apply_filters(relation, filters, params)
    relation = apply_sort(relation,    sort,    params)   if sort
    relation.page(params[:page]).per(per)
  end
  # ... apply_* helpers
end
```

- `search` applies LIKE over configured fields (OR-joined).
- `sort` parses `"field:dir"` and whitelists against configured fields.
- `filters` each declares `{ key:, column:, values: }` or a custom
  `scope: ->(relation, value) { ... }`.

Whitelisting is mandatory: passing an unknown sort field or search field is
silently ignored (no SQL injection surface).

### 6.4 Author-defined search/sort fields

Per requirement Q9: page authors decide which fields are searchable/sortable.
Default helpers on relevant models:

```ruby
class Entity < ApplicationRecord
  def searchable_field_keys
    property_schema
      .select { |f| f["type"].in?(%w[string text]) }
      .first(3)
      .map { |f| f["key"] }
  end

  def sortable_field_keys
    searchable_field_keys + %w[created_at updated_at]
  end
end
```

Controllers can override per-page if needed.

### 6.5 Stimulus controller

`app/javascript/controllers/dashboard_paginated_list_controller.js`:

- Debounces search input; submits form.
- Tracks row checkboxes; shows/hides batch bar.
- Submits batch-action forms with selected IDs.
- No external dependencies.

---

## 7. Data Flow

```
request
  │
  ▼
ApplicationController#current_dashboard_menu_item    (new — replaces zone+section helpers)
  │
  ▼
dashboard.html.erb layout
  │
  ├─ Dashboard::MenuRegistry.for(current_user)       → menu items the user sees
  ├─ Dashboard::SidebarBuilder.build(menu_item, ctx) → tree for current menu item
  │
  ▼
Dashboard::ShellComponent(
  customer:, user:,
  menu_items:, current_menu_item:,
  tree:, current_path:,
  container_width:
)
  │
  ├─ TopbarComponent(customer, user)
  │    ├─ (left)   logo + wordmark
  │    ├─ (middle) SearchButtonComponent → SearchPaletteComponent
  │    └─ (right)  HelpMenuComponent, NotificationsButtonComponent, UserMenuComponent
  │
  ├─ MenuBarComponent(menu_items:, current_menu_item:)
  │
  ├─ [ SidebarComponent(tree:, current_path:)  |  yield (main) ]
  │
  └─ DrawerComponent(menu_items, tree, current_menu_item, ...)   (mobile)
```

`current_dashboard_menu_item` is derived from the URL prefix via a single
hash in `ApplicationController`:

```ruby
MENU_ITEM_BY_PATH_PREFIX = {
  "/dashboard/entities"      => :entities,
  "/dashboard/entity_entries"=> :entities,   # legacy URL, keeps working
  "/dashboard/pages"         => :pages,
  "/pages"                   => :pages,      # legacy URL
  "/dashboard/modules"       => :modules,
  "/feature_modules"         => :modules,    # legacy URL
  "/dashboard/settings"      => :settings,
  "/dashboard/account"       => :account,
  "/dashboard/maintenance"   => :maintenance
}.freeze
```

Falls back to `:home`.

---

## 8. Controllers & Routes

### 8.1 New controllers

- `Dashboard::EntitiesController` — index (full-width empty hub), show (per-entity
  entries via `PaginatedListComponent`), destroy/batch-destroy (soft).
- `Dashboard::PagesController` — index (all pages, batch-enabled),
  `by_entity` (filtered by entity, no batch), activate/deactivate, publish/
  unpublish. This is the dashboard-namespaced controller; existing top-level
  `PagesController` (`/pages`) is unchanged.
- `Dashboard::AccountController#show` — lands on Customer Profile by default.
  Sub-routes `account/customer`, `account/users` delegate into the existing
  settings views (no URL break for bookmarks).
- `Dashboard::MaintenanceController#show` — landing for `/dashboard/maintenance`,
  prompts user to pick a sub-item.
- `Dashboard::Maintenance::EntitiesController` — index + destroy. Edit link
  → existing `/:customer_id/entities/:id/edit`.
- `Dashboard::Maintenance::FlowchartsController` — index + destroy. Edit link
  → existing flowchart editor.
- `Dashboard::Maintenance::PagesController` — index + destroy. Edit link →
  existing page-builder `/:customer_id/pages/:id/edit`.

All Maintenance controllers: `before_action :require_owner!`.

### 8.2 New filter

`ApplicationController`:

```ruby
def require_owner!
  return if current_user&.owner?
  redirect_to dashboard_root_path(current_customer), alert: "Owner access required."
end
```

### 8.3 Routes (added under existing `/:customer_id` tenant scope)

```ruby
namespace :dashboard do
  get "entities",             to: "entities#index",  as: :dashboard_entities
  get "entities/:id",         to: "entities#show",   as: :dashboard_entity_entries
  delete "entities/:id/entries",              to: "entities#batch_destroy"

  get "pages",                to: "pages#index",     as: :dashboard_pages
  get "pages/entity/:entity_id",              to: "pages#by_entity", as: :dashboard_pages_by_entity
  post "pages/batch",         to: "pages#batch_update"

  get "modules",              to: "modules#index",   as: :dashboard_modules

  namespace :account do
    get  "/",        to: "accounts#show"
    get  "customer", to: "customers#show"
    get  "users",    to: "users#index"
  end

  namespace :maintenance do
    get "/",                  to: "maintenances#show"
    resources :entities,      only: [:index, :destroy]
    resources :flowcharts,    only: [:index, :destroy]
    resources :pages,         only: [:index, :destroy]
  end
end
```

### 8.4 Deleted routes

- `get "admin"`    → `Dashboard::AdminController#show`
- `get "platform"` → `Dashboard::PlatformController#show`

---

## 9. Component Inventory

### 9.1 New

| Component / file | Purpose |
|---|---|
| `Dashboard::MenuBarComponent` | Single-row flat menu (replaces ZoneTabs + SectionTabs) |
| `Dashboard::MenuRegistry` (service) | Ordered list of `MenuItem`, filtered by role |
| `Dashboard::MenuItem` (POJO) | key, label, path_proc, permitted_by, sidebar_contributor |
| `Dashboard::PaginatedListComponent` (+ template) | Unified list frame |
| `Dashboard::Listable` (concern) | Server-side search/sort/filter/paginate helper |
| `Dashboard::AccountContributor` | Customer Profile + Users sidebar |
| `Dashboard::MaintenanceContributor` | Entities / Flowcharts / Pages leaves |
| `Dashboard::EntitiesContributor` (rename) | Was `EntityEntriesContributor` |
| `Dashboard::AccountController` + sub-controllers | |
| `Dashboard::MaintenanceController` + sub-controllers | |
| Stimulus `dashboard-paginated-list` controller | Search debounce, batch selection |

### 9.2 Modified

| Component | Change |
|---|---|
| `Dashboard::ShellComponent` | Drop `zones`, `current_zone`, `current_sections`; add `menu_items`, `current_menu_item`. |
| `Dashboard::TopbarComponent` | Grid-cols-[auto_1fr_auto] layout. Remove `WorkspaceSwitcherComponent` usage and `switchable_customers` prop. |
| `Dashboard::DrawerComponent` | Single accordion of menu items. Remove zone pill. |
| `Dashboard::SidebarBuilder` | Rename `section:` → `menu_item:`. Build for active menu item only. |
| `Dashboard::SidebarNode` | Rename attribute `section:` → `menu_item:`. |
| `Dashboard::PagesContributor` | Simplify to flat primary-entity list + synthetic `All pages` root. |
| `Dashboard::SettingsContributor` | Drop Customer Profile and Users nodes. |
| `Dashboard::LandingController#show` | Drop activity-feed assignment (per §10). |
| `ApplicationController` | Replace `current_dashboard_zone` / `current_dashboard_section` with `current_dashboard_menu_item`. Update path-prefix map. Add `require_owner!`. Remove `require_platform_owner!`. |
| `Authentication::User` | Add `owner?` predicate. Remove `platform_owner?`. |
| `config/routes.rb` | Remove `/admin` + `/platform`. Add `/dashboard/entities`, `/dashboard/pages`, `/dashboard/modules`, `/dashboard/account/*`, `/dashboard/maintenance/*`. |
| `app/views/layouts/dashboard.html.erb` | Pass `menu_items`, `current_menu_item` to shell. |

### 9.3 Deleted

- `Dashboard::ZoneRegistry`, `Dashboard::ZoneDefinition`
- `Dashboard::ZoneTabsComponent` (+ template + Stimulus controller)
- `Dashboard::SectionTabsComponent` (+ template) — functionality subsumed
- `Dashboard::WorkspaceSwitcherComponent` (+ template + Stimulus controller)
- `Dashboard::AdminController` + view
- `Dashboard::PlatformController` + view
- `Dashboard::ActivityFeedComponent` (+ template, per §10)
- `Dashboard::ActivityFeed` (service, per §10)
- Spec files for each of the above
- `PLATFORM_OWNER_EMAILS` env var usage

---

## 10. Home Page Trim

Per requirement Q5-B: Home keeps landing stats cards and quick-action cards;
**activity feed is removed**. Deletions:

- `app/components/dashboard/activity_feed_component.{rb,html.erb}`
- `app/services/dashboard/activity_feed.rb`
- `spec/components/dashboard/activity_feed_component_spec.rb`
- `spec/services/dashboard/activity_feed_spec.rb`
- Removal of `@activity = ActivityFeed.for(...)` from
  `Dashboard::LandingController#show`.
- Removal of the activity-feed render block from
  `app/views/dashboard/landing/show.html.erb`.

`LandingHeaderComponent`, `LandingStatsCardComponent`, and
`QuickActionCardComponent` are retained.

---

## 11. Error Handling

- **Unpermitted Maintenance access** — `require_owner!` redirects to dashboard
  root with an alert flash. Admin and member both hit this path.
- **Unknown sort/search field** — `Dashboard::Listable` whitelists; unknown
  fields are silently ignored (no 500, no SQL injection).
- **Empty sidebar** — `SidebarComponent` renders "Nothing here yet" empty
  state (existing behavior).
- **Batch action with zero selected** — client-side guard: batch bar stays
  hidden until ≥1 checkbox checked.
- **Mobile drawer without JS** — falls back to `<details>` progressive
  enhancement (existing drawer already does this).

---

## 12. Testing Strategy

All tests RSpec. No new frameworks.

### 12.1 Unit / component specs

- `spec/components/dashboard/menu_bar_component_spec.rb`
- `spec/components/dashboard/shell_component_spec.rb` (updated)
- `spec/components/dashboard/topbar_component_spec.rb` (updated)
- `spec/components/dashboard/drawer_component_spec.rb` (updated)
- `spec/components/dashboard/paginated_list_component_spec.rb` — covers:
  renders columns, renders row actions, omits batch bar when no batch_actions,
  renders empty state, handles sort direction indicators, renders filter
  select inputs.

### 12.2 Service specs

- `spec/services/dashboard/menu_registry_spec.rb` — `for(user)` returns
  correct menu items per role (member / admin / owner).
- `spec/services/dashboard/entities_contributor_spec.rb` (renamed)
- `spec/services/dashboard/pages_contributor_spec.rb` (updated to flat shape)
- `spec/services/dashboard/settings_contributor_spec.rb` (updated — no
  Customer Profile / Users)
- `spec/services/dashboard/account_contributor_spec.rb`
- `spec/services/dashboard/maintenance_contributor_spec.rb`
- `spec/concerns/dashboard/listable_spec.rb` — search whitelisting, sort
  whitelisting, filter application, page-size enforcement.

### 12.3 Request specs

- `spec/requests/dashboard/maintenance_access_spec.rb` — member 302,
  admin 302, owner 200 on each Maintenance endpoint.
- `spec/requests/dashboard/account_access_spec.rb` — member sees Customer
  Profile; Users endpoint 302 for member, 200 for admin/owner.

### 12.4 System specs

- `spec/system/dashboard/menu_navigation_spec.rb` — click each menu item as
  each role; confirm sidebar content and right-pane route.
- `spec/system/dashboard/paginated_list_spec.rb` — search, sort, filter,
  batch-action flows on Entities entries page.
- `spec/system/dashboard/pages_filter_vs_batch_spec.rb` — default view has
  batch bar; drill-in view does not.
- `spec/system/dashboard/maintenance_crud_spec.rb` — owner creates, edits
  (redirected to existing editor), and deletes an entity / flowchart / page
  definition.
- `spec/system/dashboard/responsive_spec.rb` — updated drawer accordion has
  menu items but no zone pill.

### 12.5 Deleted specs

- `spec/components/dashboard/zone_tabs_component_spec.rb`
- `spec/components/dashboard/workspace_switcher_component_spec.rb`
- `spec/components/dashboard/section_tabs_component_spec.rb`
- `spec/services/dashboard/zone_registry_spec.rb`
- `spec/requests/dashboard/zone_access_spec.rb`
- `spec/components/dashboard/activity_feed_component_spec.rb`
- `spec/services/dashboard/activity_feed_spec.rb`

### 12.6 Non-regression

All existing page-level specs (Entity schema form, Flowchart editor, Page
builder, module settings pages, Customer Profile, Users) must continue to
pass without modification. The shell contract (layout name, `yield`, flash
rendering, breadcrumbs) is preserved.

---

## 13. Migration & Rollout

- Zero data migrations.
- No URL changes to existing pages; legacy URLs (`/pages`, `/feature_modules`,
  `/dashboard/entity_entries`, `/dashboard/settings/*`) continue to resolve
  and are mapped to the correct menu item via `MENU_ITEM_BY_PATH_PREFIX`.
- Single deploy. No feature flag.
- Rollback = single-branch revert. No data to roll back.
- `PLATFORM_OWNER_EMAILS` env var is removed; operations should drop the
  variable from deployment secrets (no functional impact if left set —
  nothing reads it).

---

## 14. File-Change Summary

### New

- `app/components/dashboard/menu_bar_component.{rb,html.erb}`
- `app/components/dashboard/paginated_list_component.{rb,html.erb}`
- `app/controllers/concerns/dashboard/listable.rb`
- `app/controllers/dashboard/entities_controller.rb`
- `app/controllers/dashboard/pages_controller.rb`
- `app/controllers/dashboard/modules_controller.rb`
- `app/controllers/dashboard/account_controller.rb`
- `app/controllers/dashboard/account/customers_controller.rb`
- `app/controllers/dashboard/account/users_controller.rb`
- `app/controllers/dashboard/maintenance_controller.rb`
- `app/controllers/dashboard/maintenance/entities_controller.rb`
- `app/controllers/dashboard/maintenance/flowcharts_controller.rb`
- `app/controllers/dashboard/maintenance/pages_controller.rb`
- Views for each new controller
- `app/services/dashboard/menu_registry.rb`
- `app/services/dashboard/menu_item.rb`
- `app/services/dashboard/account_contributor.rb`
- `app/services/dashboard/maintenance_contributor.rb`
- `app/javascript/controllers/dashboard_paginated_list_controller.js`
- Specs for each of the above

### Modified

- `app/components/dashboard/shell_component.{rb,html.erb}`
- `app/components/dashboard/topbar_component.{rb,html.erb}`
- `app/components/dashboard/drawer_component.{rb,html.erb}`
- `app/components/dashboard/sidebar_component.{rb,html.erb}` (attribute rename)
- `app/services/dashboard/sidebar_builder.rb`
- `app/services/dashboard/sidebar_node.rb`
- `app/services/dashboard/pages_contributor.rb`
- `app/services/dashboard/settings_contributor.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/dashboard/landing_controller.rb`
- `app/views/dashboard/landing/show.html.erb`
- `app/views/layouts/dashboard.html.erb`
- `app/models/authentication/user.rb`
- `app/models/entity.rb` (add `searchable_field_keys`, `sortable_field_keys`)
- `app/models/page.rb` (add same defaults)
- `config/routes.rb`

### Deleted

- `app/services/dashboard/zone_registry.rb`
- `app/services/dashboard/zone_definition.rb`
- `app/components/dashboard/zone_tabs_component.{rb,html.erb}`
- `app/components/dashboard/section_tabs_component.{rb,html.erb}`
- `app/components/dashboard/workspace_switcher_component.{rb,html.erb}`
- `app/javascript/controllers/dashboard_zone_tabs_controller.js`
- `app/javascript/controllers/dashboard_workspace_switcher_controller.js`
- `app/controllers/dashboard/admin_controller.rb`
- `app/controllers/dashboard/platform_controller.rb`
- `app/views/dashboard/admin/show.html.erb`
- `app/views/dashboard/platform/show.html.erb`
- `app/services/dashboard/entity_entries_contributor.rb` (replaced by `entities_contributor.rb`)
- `app/components/dashboard/activity_feed_component.{rb,html.erb}`
- `app/services/dashboard/activity_feed.rb`
- Specs for each of the above

---

## 15. Open Questions

None blocking.

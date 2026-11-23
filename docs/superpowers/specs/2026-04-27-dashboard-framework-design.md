# Dashboard Framework — Design

**Date:** 2026-04-27
**Branch:** `feature-dashboard`
**Status:** Design (pre-plan)

## 1. Goal

Deliver a professional, tenant-scoped customer dashboard that replaces the current top-header layout for every customer-facing page. The framework must:

- Render four top-level sections: **Entity Entries**, **Pages**, **Modules** (enabled modules expand to their entries), **Settings**.
- Let different customers see different menus based on their data (entities, pages, enabled modules) and, in the future, their permissions.
- Stay module-agnostic: adding or removing a feature module must require zero edits to the framework.
- Ship a real landing page with counts, an activity feed, and quick-action cards.
- Be fully responsive with a mobile drawer and top-dropdown fallback.

Platform-owner-only surfaces (Flowcharts, Code Generators) stay on the existing `application.html.erb` layout and are out of scope.

## 2. Top-level Decisions (locked during brainstorming)

| # | Decision |
|---|---|
| D1 | Primary entity in a group = **source-side** of `Entity.associations` (bridge entities excluded). Targets nest under primary. |
| D2 | Pages sidebar mirrors the primary/associated hierarchy; a page appears under its bound entity. |
| D3 | Modules section lists enabled modules and their **entries** only. Module **configuration** lives in Settings. |
| D4 | Modules contribute via `Registration.sidebar_contributions(controller)` returning a structured hash (entries + settings + metadata). |
| D5 | Per-item `permitted_by:` — every `SidebarNode` carries an optional lambda or symbol; framework evaluates with `current_user` at render. |
| D6 | Fully responsive: <md breakpoint collapses sidebar into a drawer, top section tabs collapse into a dropdown. |
| D7 | Landing page at `/:customer_id` shows greeting, counts, activity feed, quick-action cards. |
| D8 | Landing stats: **counts** (entities, pages, flowcharts, enabled modules, users), **activity feed** (derived from existing timestamps — no new log), **quick actions** (create entity / new page / enable module / invite user). |
| D9 | Dashboard top-right shows a **user dropdown only** (profile, change password, MFA, sign out). No tenant switcher / notifications / global search. |
| D10 | Settings section contains per-enabled-module configs, customer profile (`customers#edit`), user management (`authentication/admin/users#index`). |
| D11 | Module Entries use a **framework-owned standard table view**; modules supply `{ columns:, scope: ActiveRecord::Relation }` via `module.entries_for(entry_key:, params:)`. Framework owns pagination/sorting/search. |
| D12 | Visual style: **enterprise / Linear-like** — dense, low-chrome, monochrome with indigo accent (reuses existing palette). |
| D13 | New `app/components/dashboard/` namespace for framework-specific components; reuse existing atoms (Button, Badge, EmptyState). |
| D14 | Full cut-over: the new `dashboard.html.erb` layout replaces `application.html.erb` for all customer-scoped routes. Platform-owner routes (Flowcharts, Code Generators) stay on the old header. |
| D15 | Sidebar assembly uses the **Contributor pattern** — `Dashboard::SidebarBuilder` iterates registered `SidebarContributor` classes. |

## 3. Architecture

### 3.1 Layout & control flow

```
Request → ApplicationController (sets DashboardContext)
        → dashboard.html.erb layout
            ↳ Dashboard::ShellComponent
                ↳ Dashboard::TopbarComponent       (customer name · user dropdown · mobile hamburger)
                ↳ Dashboard::SectionTabsComponent  (top strip: 5 sections, highlights current)
                ↳ Dashboard::SidebarComponent      (left rail — contextual to current section)
                ↳ Dashboard::MainComponent         (yield)
```

`DashboardContext` is a Struct assembled once per request in `ApplicationController#set_dashboard_context`:

```ruby
DashboardContext = Struct.new(
  :current_user, :current_customer, :current_section, :request_path,
  keyword_init: true
)
```

### 3.2 Sidebar assembly pipeline

```
Dashboard::SidebarBuilder.build(context) → SidebarTree
  for contributor in SidebarContributor.registry:
    tree.merge(contributor.new(context).contribute)
  Dashboard::PermissionFilter.apply(tree, context.current_user)
  tree
```

**Registered built-in contributors (deterministic order):**

1. `EntityEntriesContributor`
2. `PagesContributor`
3. `ModulesContributor`
4. `SettingsContributor`

`SidebarContributor` is an abstract class:

```ruby
class Dashboard::SidebarContributor
  # @param context [DashboardContext]
  def initialize(context) = @context = context

  # @return [Array<SidebarNode>] top-level nodes owned by this contributor
  def contribute = raise NotImplementedError

  # Deterministic registry in DI order
  def self.registry
    [EntityEntriesContributor, PagesContributor, ModulesContributor, SettingsContributor]
  end
end
```

Registry is explicit (not auto-discovered) so order is obvious and testable.

### 3.3 Data model — `SidebarTree` and `SidebarNode`

```ruby
Dashboard::SidebarNode = Struct.new(
  :key,              # stable id, e.g. "entity_entries.customers"
  :label,            # human label
  :path,             # href (nil → group/header only)
  :icon,             # svg_path_d string, optional
  :badge,            # { label:, color: } optional
  :children,         # Array<SidebarNode>
  :permitted_by,     # Proc / Symbol — framework calls with current_user
  :section,          # :entity_entries / :pages / :modules / :settings
  :section_root,     # bool — marks the top of a section
  keyword_init: true
)

class Dashboard::SidebarTree
  def initialize = @sections = Hash.new { |h, k| h[k] = [] }
  def add(section, node) = @sections[section] << node
  def nodes_for(section) = @sections[section]
  def all = @sections
end
```

A section's rendered sidebar = `tree.nodes_for(context.current_section)`.
Section tabs list fixed section labels, each linking to `/:customer_id/<section>`; the active section's nodes render in the rail.

### 3.4 Contributors — responsibilities

#### EntityEntriesContributor

Produces the Entity Entries section tree. Per decision D1:

```
primaries = Entity.for_customer(cid).non_bridge.select { |e| source_side?(e) }
each primary:
  root = SidebarNode(key: "entity_entries.#{primary.name_slug}",
                     label: primary.name,
                     path:  "/:cid/entity_entries/#{primary.id}",
                     children: associated_entities_of(primary).map { |child|
                       SidebarNode(... path: ".../entity_entries/#{child.id}")
                     })
```

**Primary / associated classification:**

```ruby
class EntityAssociationGraph
  def self.build(customer_id)
    entities = Entity.for_customer(customer_id).non_bridge
    target_ids = entities.flat_map { |e| e.associations_list.map { |a| a["target_entity_id"] } }.compact.to_set
    primaries = entities.reject { |e| target_ids.include?(e.id) }
    # An entity is primary when no other entity lists it as an association target.
    # Per D1: the entity that *defines* the association is the source/primary;
    # targets (those listed in someone else's associations) become its children.
    children_of = entities.each_with_object({}) { |e, h|
      h[e.id] = e.associations_list
                  .map { |a| entities.find { |x| x.id == a["target_entity_id"] } }
                  .compact
    }
    new(primaries: primaries, children_of: children_of)
  end
end
```

A standalone entity (no outbound associations, not referenced as a target) is its own primary with an empty child list. Bridge entities never appear at any level.

#### PagesContributor

```
primaries = same as EntityEntriesContributor
each primary:
  pages_of(primary) + pages_of(associated_entities(primary))  # flatten per primary group
  root = SidebarNode(key: "pages.#{primary.name_slug}",
                     label: primary.name,
                     children: grouped_pages.map { |entity, pages|
                       SidebarNode(label: entity.name,
                                   children: pages.map { |p| SidebarNode(path: "/:cid/pages/#{p.id}") })
                     })
```

A page whose bound entity is associated appears under its primary's group.

#### ModulesContributor

```
enabled = FeatureModule.enabled_for_customer(cid)
each fm:
  contributions = fm.registration_class.sidebar_contributions(controller)
  # contributions => { entries: [Contribution], settings: [Contribution], metadata: { order: } }
  entries = contributions[:entries].map(&:to_sidebar_node)  # section: :modules
```

A `Contribution` is a lightweight value object with `label`, `path`, `entry_key` (opaque string, passed back on `entries_for`), `icon`, `badge`, `permitted_by`. Modules never emit HTML or raw nodes — framework converts.

If the contribution omits `path`, framework derives `/:cid/modules/:module_key/entries/:entry_key` (points at `Dashboard::ModuleEntriesController`).

#### SettingsContributor

Fixed top-level sub-tree:

```
Settings
├── Customer Profile   → /:cid/settings/customer
├── Users              → /:cid/settings/users
└── Modules
    ├── Payments       → /:cid/settings/modules/payment
    └── Notifications  → /:cid/settings/modules/notifications
    (one child per enabled module — pulled via sidebar_contributions[:settings])
```

Settings module children come from the same `sidebar_contributions` call as entries; cached on the context so each module's Registration is invoked once per request.

### 3.5 Permission gating

```ruby
class Dashboard::PermissionFilter
  def self.apply(tree, user)
    tree.transform_nodes { |node| visible?(node, user) ? node : nil }
  end

  def self.visible?(node, user)
    return true if node.permitted_by.nil?
    case node.permitted_by
    when Proc   then node.permitted_by.call(user)
    when Symbol then user.respond_to?(node.permitted_by) && user.public_send(node.permitted_by)
    end
  end
end
```

- `permitted_by: nil` means "visible to everyone" (default; v1 short-circuit).
- Each built-in contributor may set `permitted_by:` on nodes it owns (e.g., Settings → Users uses `:admin_or_owner?`).
- Module-contributed items pass through their own `permitted_by` unchanged.
- A parent node with no visible children is suppressed (prevents dangling group headers).

### 3.6 Module entries table (D11)

Framework controller: `Dashboard::ModuleEntriesController#show`

```
params: customer_id, module_key, entry_key, page, sort, dir, q
fm = FeatureModule.find_by!(key: module_key) with enabled check
result = fm.registration_class.entries_for(entry_key: entry_key, params: params)
  # result => { title:, columns: [{key:, label:, type:, sortable:}], scope: AR::Relation, row_path: Proc }
rel = result[:scope]
rel = apply_search(rel, result[:columns], params[:q])
rel = apply_sort(rel, result[:columns], params[:sort], params[:dir])
rel, pagination = paginate(rel, params[:page])
render with Dashboard::EntriesTableComponent(columns:, rows:, pagination:, row_path:, title:)
```

`row_path` is an optional Proc `->(record) { path_to_detail }`. Modules without detail views omit it; table renders non-linked rows.

`BaseModule` receives default implementations:

```ruby
def self.sidebar_contributions(_controller) = { entries: [], settings: [], metadata: {} }
def self.entries_for(entry_key:, params:) = raise NotImplementedError
```

### 3.7 Landing page

Route: `/:customer_id` → `Dashboard::LandingController#show`.

**Stats (D8 — S1 counts):**

```ruby
Dashboard::LandingStats.for(customer).to_h
# => {
#   entities: Entity.for_customer(cid).non_bridge.count,
#   pages: { total:, published:, draft: },
#   flowcharts: Flowchart.for_customer(cid).count,
#   modules_enabled: CustomerFeatureModule.for_customer(cid).enabled.count,
#   users: Authentication::User.for_customer(cid).active.count
# }
```

**Activity feed (D8 — S2, derived, no new log):**

```ruby
class Dashboard::ActivityFeed
  def self.recent(customer, limit: 15)
    events = []
    events += Page.for_customer(cid).recent.limit(limit).map { |p| event(:page_edited, p) }
    events += Flowchart.for_customer(cid).recent.limit(limit).map { |f| event(:flowchart_edited, f) }
    events += EntityEntry.for_customer(cid).order(created_at: :desc).limit(limit).map { |e| event(:entry_created, e) }
    events += FeatureModuleLog.where(customer_id: cid).order(created_at: :desc).limit(limit).map { |l| event(:module_event, l) }
    events.sort_by { |ev| -ev.occurred_at.to_i }.first(limit)
  end
end
```

`event(kind, record)` returns a `Struct` with `kind`, `label`, `path`, `occurred_at`, `actor` (if known). Rendered by `Dashboard::ActivityFeedComponent`.

**Quick actions (D8 — S4):**
Four cards: Create entity, New page, Enable module, Invite user. Each is a `Dashboard::QuickActionCardComponent` with an icon, label, description, path, and `permitted_by:`. Cards filter through the same PermissionFilter as nav.

### 3.8 Responsiveness (D6)

- **≥md:** top `SectionTabsComponent` row + left `SidebarComponent` rail + main.
- **<md:** topbar includes a hamburger that opens a full-height drawer combining section tabs (as a vertical list) and the sidebar nodes of the active section. A Stimulus controller `dashboard_drawer_controller.js` toggles it. Section tabs collapse into a single dropdown button labelled with the current section.
- No horizontal scroll; table components use responsive overflow.

### 3.9 Visual style (D12)

Direction anchor for `frontend-design` invocation in the plan:

- Dense, information-rich. 12–13px base font for nav; 14px for body. Tight line-height.
- Monochrome greys (`gray-50/100/200/600/900`) with indigo-600 accent (already in use).
- Flat surfaces, 1px borders, no drop shadows except on dropdowns/drawers.
- Section tabs: underline-style active indicator.
- Sidebar: left-border-4 indigo-600 active indicator; collapsible groups with subtle chevrons.
- Icons: 16×16 stroked, 1.5 stroke-width (matches current `stroke-width="2"` trend slightly refined).
- Focus states: 2px indigo ring.

All styling uses Tailwind utilities only (per AGENTS.md).

### 3.10 Component inventory (new under `app/components/dashboard/`)

| Component | Responsibility |
|---|---|
| `ShellComponent` | Outer grid; renders Topbar, SectionTabs, Sidebar slot, main slot. |
| `TopbarComponent` | Customer name + user dropdown + mobile hamburger. |
| `SectionTabsComponent` | The 5 top tabs; takes current section key. |
| `SidebarComponent` | Renders a single section's tree from `SidebarTree`. |
| `SidebarNodeComponent` | Recursive node row (expand/collapse, active state, icon, badge). |
| `DrawerComponent` | Mobile drawer wrapper; Stimulus-driven. |
| `EntriesTableComponent` | Columns/rows/pagination/search/sort. |
| `LandingHeaderComponent` | Greeting + customer summary on landing. |
| `LandingStatsCardComponent` | One stat card. |
| `ActivityFeedComponent` | Renders the derived activity event list. |
| `QuickActionCardComponent` | Call-to-action card. |
| `UserMenuComponent` | Avatar + dropdown. |
| `BreadcrumbsComponent` | Section › sub-section > current. |

### 3.11 Routes (final shape)

Inside the existing `scope "/:customer_id", constraints: { customer_id: /\d{8}/ }` block, add:

```ruby
get "/", to: "dashboard/landing#show", as: :dashboard_root

namespace :dashboard do
  resources :entity_entries, only: [:index, :show]
  get "modules/:module_key/entries/:entry_key",
      to: "module_entries#show",
      as: :module_entry
  get "settings",                     to: "settings#show",         as: :settings
  get "settings/customer",            to: "settings#customer",     as: :settings_customer
  get "settings/users",               to: "settings#users",        as: :settings_users
  get "settings/modules/:module_key", to: "settings#module_config", as: :settings_module
end
```

Existing `resources :pages`, `resources :entities`, `resources :feature_modules` remain; their controllers opt into the dashboard layout via a `layout :dashboard_layout` helper defined on `ApplicationController`:

```ruby
def dashboard_layout
  if current_customer_id.present? && platform_owner_controller?
    "application"
  elsif current_customer_id.present?
    "dashboard"
  else
    "application"
  end
end
```

`platform_owner_controller?` returns true for `FlowchartsController`, `Admin::*`, and any future owner-only controllers (registered by name on a class-level allowlist).

## 4. Unit boundaries (isolation check)

Each unit is asked: *what does it do, how is it used, what does it depend on?*

| Unit | Does | Used by | Depends on |
|---|---|---|---|
| `DashboardContext` | Bundles per-request context | Every contributor, filter, component | Nothing app-specific |
| `SidebarBuilder` | Orchestrates contributors → tree → filter | `dashboard.html.erb` layout | `SidebarContributor.registry`, `PermissionFilter` |
| `SidebarContributor` subclasses | Build a section sub-tree from domain data | `SidebarBuilder` | Own domain models only |
| `PermissionFilter` | Drops nodes that fail `permitted_by` | `SidebarBuilder` | `SidebarNode` |
| `Dashboard::ModuleEntriesController` | Turns module's relation into paginated table | routes | `FeatureModule`, `EntriesTableComponent` |
| `EntriesTableComponent` | Renders headers, rows, pagination | Controllers | Columns schema, records |
| `BaseModule.sidebar_contributions` | Module-side adapter | `ModulesContributor` | Module's own data |

Each is individually testable without the rest (pure Ruby structs + seams).

## 5. Testing strategy

- **Unit specs:** each contributor (given fixtures → expected tree), `PermissionFilter`, `SidebarBuilder`, `LandingStats`, `ActivityFeed`.
- **Request specs:** route smoke tests under `/:cid/` for landing, each section, module entries, settings sub-routes.
- **Component specs (ViewComponent):** each `Dashboard::*Component` — snapshot-style DOM assertions (Tailwind classes, responsive classes).
- **System specs (Capybara, headless Chromium):** shell navigation flow, mobile drawer open/close, section tab switching, entries table search/sort/pagination.
- **Permission tests:** `permitted_by: ->(u) { u.admin? }` — node dropped for non-admin; group suppressed when all children hidden.
- **Coverage goal:** match existing repo standard (full coverage of new generated code).

## 6. Migration notes

1. `application.html.erb` stripped to platform-owner-only rendering (Flowcharts + Code Generators).
2. Existing customer-scoped controllers (`pages`, `entities`, `entity_entries`, `feature_modules`, `customers`, `authentication/admin/users`) set `layout "dashboard"` in an `ApplicationController#layout` hook gated on `current_customer_id.present?`.
3. Hard-coded header links in the current `application.html.erb` move into the four built-in contributors; `FeatureModules::NavContributionsComponent` is deleted — its role is absorbed by `ModulesContributor`.
4. `Registration.nav_items_for(controller, section:)` is removed from `BaseModule`; replaced by `sidebar_contributions(controller)`. Any existing module overrides migrate in the same spec (Payment module only, per grep).
5. No data migrations. No backward-compatibility shims — per AGENTS.md "Do NOT take backward compatibility into consideration".

## 7. Out of scope

- Real permission policies (framework only exposes the hook).
- Tenant switcher, global search, notification bell.
- Module-specific detail pages beyond the standard entries table (modules still own their own detail routes).
- Visual refresh of existing `*_list_table_component.rb` styles (table views keep current look unless they embed in a dashboard section, which only the new `EntriesTableComponent` does).
- Platform-owner UI refresh (Flowcharts, Code Generators).

## 8. Risks

- **Activity feed cost.** Pulling 15 per source then sorting is O(n) per request. Keep the `limit` low; add DB-side ordering. If it becomes hot, cache per-customer with a 30s TTL.
- **Contributor request amplification.** Each `ModulesContributor` invocation calls every enabled module's `sidebar_contributions`. Cache results on `DashboardContext` so repeated calls within a request don't re-query.
- **Permission hook performance.** `permitted_by:` lambdas run per node on every request. Keep them cheap (method calls on user, not DB lookups). Document this in the contributor doc.
- **Cut-over regression surface.** Switching every customer-scoped controller to the new layout is a broad touch. Each controller keeps its current action code; only layout changes. Full `rspec` run + system specs guard against regressions.

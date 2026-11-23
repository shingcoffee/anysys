# Remove Dashboard Namespace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `Dashboard` Ruby module namespace, `dashboard/` directory prefix, and `dashboard_` JS controller prefix from all files so the shell/navigation framework sits at the top level.

**Architecture:** The `Dashboard` namespace is purely organizational—it adds no disambiguation value since no other top-level namespace conflicts with these names. All `module Dashboard` wrappers are dropped, `Dashboard::Foo` references become `Foo`, files under `app/controllers/dashboard/`, `app/components/dashboard/`, `app/services/dashboard/`, `app/views/dashboard/`, and their spec counterparts are moved one level up (with `maintenance/` and `search/` subdirs preserved). Routes change from `scope module: :dashboard` to a plain `scope` block. JS Stimulus controllers are renamed from `dashboard_*` to the suffix only (e.g. `dashboard_drawer_controller.js` → `drawer_controller.js`). The layout file and all callers are updated accordingly.

**Tech Stack:** Rails 8.1, ViewComponent, StimulusJS, RSpec

---

## File Moves Summary

### Controllers
| Old | New |
|-----|-----|
| `app/controllers/dashboard/entities_controller.rb` | `app/controllers/entities_controller.rb` |
| `app/controllers/dashboard/entity_entries_controller.rb` | `app/controllers/entity_entries_controller.rb` |
| `app/controllers/dashboard/landing_controller.rb` | `app/controllers/landing_controller.rb` |
| `app/controllers/dashboard/maintenances_controller.rb` | `app/controllers/maintenances_controller.rb` |
| `app/controllers/dashboard/module_entries_controller.rb` | `app/controllers/module_entries_controller.rb` |
| `app/controllers/dashboard/modules_controller.rb` | `app/controllers/modules_controller.rb` |
| `app/controllers/dashboard/pages_controller.rb` | `app/controllers/pages_controller.rb` |
| `app/controllers/dashboard/search_controller.rb` | `app/controllers/search_controller.rb` |
| `app/controllers/dashboard/settings_controller.rb` | `app/controllers/settings_controller.rb` |
| `app/controllers/dashboard/maintenance/*.rb` | `app/controllers/maintenance/*.rb` |
| `app/controllers/dashboard/settings/constants_controller.rb` | `app/controllers/settings/constants_controller.rb` |
| `app/controllers/concerns/dashboard/listable.rb` | `app/controllers/concerns/listable.rb` |

### Components
| Old | New |
|-----|-----|
| `app/components/dashboard/*.rb` + `.html.erb` | `app/components/*.rb` + `.html.erb` |

### Services
| Old | New |
|-----|-----|
| `app/services/dashboard/*.rb` | `app/services/*.rb` |
| `app/services/dashboard/search/*.rb` | `app/services/search/*.rb` |

### Views
| Old | New |
|-----|-----|
| `app/views/dashboard/**/*` | `app/views/**/*` (same relative sub-path, drop `dashboard/` prefix) |
| `app/views/layouts/dashboard.html.erb` | stays at `app/views/layouts/dashboard.html.erb` (layout name unchanged) |

### Helpers
| Old | New |
|-----|-----|
| `app/helpers/dashboard_layout_helper.rb` | `app/helpers/layout_helper.rb` |

### JS Controllers
| Old | New |
|-----|-----|
| `dashboard_drawer_controller.js` | `drawer_controller.js` |
| `dashboard_help_menu_controller.js` | `help_menu_controller.js` |
| `dashboard_paginated_list_controller.js` | `paginated_list_controller.js` |
| `dashboard_section_tabs_controller.js` | `section_tabs_controller.js` |
| `dashboard_user_menu_controller.js` | `user_menu_controller.js` |
| (menu_bar uses `dashboard-menu-bar` from an existing controller file) | check and rename accordingly |

### Specs
Mirror the same moves under `spec/`.

---

## Task 1: Move and update controllers (non-maintenance)

**Files:**
- Move: `app/controllers/dashboard/entities_controller.rb` → `app/controllers/entities_controller.rb`
- Move: `app/controllers/dashboard/entity_entries_controller.rb` → `app/controllers/entity_entries_controller.rb`
- Move: `app/controllers/dashboard/landing_controller.rb` → `app/controllers/landing_controller.rb`
- Move: `app/controllers/dashboard/maintenances_controller.rb` → `app/controllers/maintenances_controller.rb`
- Move: `app/controllers/dashboard/module_entries_controller.rb` → `app/controllers/module_entries_controller.rb`
- Move: `app/controllers/dashboard/modules_controller.rb` → `app/controllers/modules_controller.rb`
- Move: `app/controllers/dashboard/pages_controller.rb` → `app/controllers/pages_controller.rb`
- Move: `app/controllers/dashboard/search_controller.rb` → `app/controllers/search_controller.rb`
- Move: `app/controllers/dashboard/settings_controller.rb` → `app/controllers/settings_controller.rb`
- Move: `app/controllers/concerns/dashboard/listable.rb` → `app/controllers/concerns/listable.rb`

- [ ] **Step 1: Move non-maintenance controller files**

```bash
cd /opt/milestone/anysys
cp app/controllers/dashboard/entities_controller.rb app/controllers/entities_controller.rb
cp app/controllers/dashboard/entity_entries_controller.rb app/controllers/entity_entries_controller.rb
cp app/controllers/dashboard/landing_controller.rb app/controllers/landing_controller.rb
cp app/controllers/dashboard/maintenances_controller.rb app/controllers/maintenances_controller.rb
cp app/controllers/dashboard/module_entries_controller.rb app/controllers/module_entries_controller.rb
cp app/controllers/dashboard/modules_controller.rb app/controllers/modules_controller.rb
cp app/controllers/dashboard/pages_controller.rb app/controllers/pages_controller.rb
cp app/controllers/dashboard/search_controller.rb app/controllers/search_controller.rb
cp app/controllers/dashboard/settings_controller.rb app/controllers/settings_controller.rb
mkdir -p app/controllers/concerns
cp app/controllers/concerns/dashboard/listable.rb app/controllers/concerns/listable.rb
```

- [ ] **Step 2: Remove `module Dashboard` wrapper and update cross-references in each non-maintenance controller**

Edit each file to:
1. Remove the outer `module Dashboard` / `end` wrapper (leaving `module Maintenance` nested wrappers intact in maintenance files)
2. Replace `Dashboard::Foo` references with `Foo`

For `app/controllers/entities_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines
- Change `include Dashboard::Listable` → `include Listable`
- Change `Dashboard::EntityAssociationGraph.build` → `EntityAssociationGraph.build`

For `app/controllers/entity_entries_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines

For `app/controllers/landing_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines
- Change `Dashboard::LandingStats.for` → `LandingStats.for`

For `app/controllers/maintenances_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines

For `app/controllers/module_entries_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines
- Change `Dashboard::ModuleEntriesResolver.call` → `ModuleEntriesResolver.call`

For `app/controllers/modules_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines

For `app/controllers/pages_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines
- Change `include Dashboard::Listable` → `include Listable`

For `app/controllers/search_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines
- Change `Dashboard::SearchQuery.call` → `SearchQuery.call`

For `app/controllers/settings_controller.rb`:
- Remove `module Dashboard` / `end` wrapping lines

For `app/controllers/concerns/listable.rb`:
- Change `module Dashboard` / `module Listable` to just `module Listable`
- The inner `ModuleEntriesResolver.call` reference has no prefix since it's already resolved within the same namespace after the move

- [ ] **Step 3: Move maintenance controllers and settings/constants controller**

```bash
mkdir -p app/controllers/maintenance
mkdir -p app/controllers/settings
cp app/controllers/dashboard/maintenance/customer_profile_controller.rb app/controllers/maintenance/customer_profile_controller.rb
cp app/controllers/dashboard/maintenance/customers_controller.rb app/controllers/maintenance/customers_controller.rb
cp app/controllers/dashboard/maintenance/entities_controller.rb app/controllers/maintenance/entities_controller.rb
cp app/controllers/dashboard/maintenance/feature_modules_controller.rb app/controllers/maintenance/feature_modules_controller.rb
cp app/controllers/dashboard/maintenance/flowcharts_controller.rb app/controllers/maintenance/flowcharts_controller.rb
cp app/controllers/dashboard/maintenance/industry_templates_controller.rb app/controllers/maintenance/industry_templates_controller.rb
cp app/controllers/dashboard/maintenance/module_settings_controller.rb app/controllers/maintenance/module_settings_controller.rb
cp app/controllers/dashboard/maintenance/modules_controller.rb app/controllers/maintenance/modules_controller.rb
cp app/controllers/dashboard/maintenance/pages_controller.rb app/controllers/maintenance/pages_controller.rb
cp app/controllers/dashboard/maintenance/users_controller.rb app/controllers/maintenance/users_controller.rb
cp app/controllers/dashboard/settings/constants_controller.rb app/controllers/settings/constants_controller.rb
```

- [ ] **Step 4: Remove `module Dashboard` wrapper from each maintenance / settings controller**

For every file in `app/controllers/maintenance/*.rb` and `app/controllers/settings/constants_controller.rb`:
- Remove only the outer `module Dashboard` / outer `end` line (keeping `module Maintenance` / `module Settings` wrappers)
- Update any `Dashboard::Listable` → `Listable`

Example diff for `app/controllers/maintenance/entities_controller.rb`:
```ruby
# Before
module Dashboard
  module Maintenance
    class EntitiesController < ApplicationController
      include Dashboard::Listable
      ...
    end
  end
end

# After
module Maintenance
  class EntitiesController < ApplicationController
    include Listable
    ...
  end
end
```

Same pattern for all other maintenance controllers. For flowcharts_controller.rb also change `include Dashboard::Listable` → `include Listable`. For pages_controller.rb also change `include Dashboard::Listable` → `include Listable`.

- [ ] **Step 5: Delete old dashboard controller directories**

```bash
rm -rf app/controllers/dashboard
rm -f app/controllers/concerns/dashboard/listable.rb
rmdir app/controllers/concerns/dashboard 2>/dev/null || true
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/ 
git commit -m "refactor: move controllers out of Dashboard namespace"
```

---

## Task 2: Move and update services

**Files:**
- Move: `app/services/dashboard/*.rb` → `app/services/*.rb`
- Move: `app/services/dashboard/search/*.rb` → `app/services/search/*.rb`

- [ ] **Step 1: Copy service files to new locations**

```bash
mkdir -p app/services/search
# Top-level services
for f in app/services/dashboard/*.rb; do cp "$f" "app/services/$(basename $f)"; done
# Search sub-services
for f in app/services/dashboard/search/*.rb; do cp "$f" "app/services/search/$(basename $f)"; done
```

- [ ] **Step 2: Update each service file — remove `module Dashboard`, drop `Dashboard::` prefixes**

Key changes per file:

**`app/services/dashboard_context.rb`** (was `dashboard/dashboard_context.rb`):
```ruby
# Before
module Dashboard
  DashboardContext = Struct.new(...)
end

# After
DashboardContext = Struct.new(
  :current_user, :current_customer, :current_menu_item, :request_path,
  keyword_init: true
) do
  def customer_id = current_customer&.id
end
```

**`app/services/menu_registry.rb`**:
```ruby
# Before
module Dashboard
  class MenuRegistry
    ITEMS = [
      MenuItem.new(..., sidebar_contributor: EntitiesContributor),
      ...
    ]
    ...
  end
end

# After
class MenuRegistry
  ITEMS = [
    MenuItem.new(..., sidebar_contributor: EntitiesContributor),
    ...
  ].freeze
  ...
end
```

**`app/services/sidebar_contributor.rb`**:
Remove `module Dashboard` wrapper and all `Dashboard::` prefixes in the `registry` array:
```ruby
class SidebarContributor
  def self.registry
    [
      EntitiesContributor,
      PagesContributor,
      ModulesContributor,
      SettingsContributor,
      MaintenanceContributor
    ]
  end
  ...
end
```

**`app/services/sidebar_builder.rb`**:
Remove `module Dashboard` wrapper. No `Dashboard::` prefixes remain (all relative).

**`app/services/search_query.rb`**:
```ruby
# Before
SOURCES = [
  Dashboard::Search::PagesSource,
  Dashboard::Search::EntitiesSource,
  Dashboard::Search::ModulesSource
].freeze

# After
SOURCES = [
  Search::PagesSource,
  Search::EntitiesSource,
  Search::ModulesSource
].freeze
```

**`app/services/module_contribution.rb`**: Remove `module Dashboard` wrapper only. Inner `SidebarNode.new` stays as-is.

**`app/services/search/base_source.rb`**:
```ruby
# Before
module Dashboard
  module Search
    class BaseSource
      ...
    end
  end
end

# After
module Search
  class BaseSource
    ...
  end
end
```

Same pattern for `search/entities_source.rb`, `search/modules_source.rb`, `search/pages_source.rb`.

All other service files (`menu_item.rb`, `entities_contributor.rb`, `pages_contributor.rb`, `modules_contributor.rb`, `settings_contributor.rb`, `maintenance_contributor.rb`, `sidebar_node.rb`, `sidebar_tree.rb`, `permission_filter.rb`, `entity_association_graph.rb`, `landing_stats.rb`, `module_entries_resolver.rb`): remove the outer `module Dashboard` / `end` wrapper only.

- [ ] **Step 3: Update external callers of Dashboard services**

`app/views/layouts/dashboard.html.erb` — change all `Dashboard::` prefixes:
```ruby
# Before
menu_items = Dashboard::MenuRegistry.for(current_user)
dashboard_context = Dashboard::DashboardContext.new(...)
dashboard_tree = Dashboard::SidebarBuilder.build(...)
render Dashboard::ShellComponent.new(...)

# After
menu_items = MenuRegistry.for(current_user)
dashboard_context = DashboardContext.new(...)
dashboard_tree = SidebarBuilder.build(...)
render ShellComponent.new(...)
```

`app/controllers/sms/admin/messages_controller.rb` — change `Dashboard::ModuleEntriesResolver.call` → `ModuleEntriesResolver.call`

`app/services/feature_modules/authentication/registration.rb`, `payment/registration.rb`, `sms/registration.rb` — change `Dashboard::ModuleContribution.new` → `ModuleContribution.new`

`app/services/feature_modules/base_module.rb` — update the comments referencing `Dashboard::*`

- [ ] **Step 4: Delete old service directories**

```bash
rm -rf app/services/dashboard
```

- [ ] **Step 5: Commit**

```bash
git add app/services/ app/views/layouts/dashboard.html.erb app/controllers/sms/
git commit -m "refactor: move services out of Dashboard namespace"
```

---

## Task 3: Move and update components

**Files:**
- Move: `app/components/dashboard/*.rb` + `app/components/dashboard/*.html.erb` → `app/components/*.rb` + `app/components/*.html.erb`

- [ ] **Step 1: Copy component files to new locations**

```bash
for f in app/components/dashboard/*.rb; do cp "$f" "app/components/$(basename $f)"; done
for f in app/components/dashboard/*.html.erb; do cp "$f" "app/components/$(basename $f)"; done
```

- [ ] **Step 2: Remove `module Dashboard` wrappers from all component `.rb` files**

For each `app/components/*_component.rb` that was moved, remove the `module Dashboard` / `end` wrapper. Class names stay the same (e.g. `class ShellComponent < ApplicationComponent`).

Example for `app/components/shell_component.rb`:
```ruby
# Before
module Dashboard
  class ShellComponent < ApplicationComponent
    ...
  end
end

# After
class ShellComponent < ApplicationComponent
  ...
end
```

Apply to all: `BreadcrumbsComponent`, `DrawerComponent`, `EmptyZoneComponent`, `EntriesTableComponent`, `HelpMenuComponent`, `InlineSearchComponent`, `LandingHeaderComponent`, `LandingStatsCardComponent`, `MenuBarComponent`, `NotificationsButtonComponent`, `PaginatedListComponent`, `QuickActionCardComponent`, `ShellComponent`, `SidebarComponent`, `SidebarNodeComponent`, `TopbarComponent`, `UserMenuComponent`.

- [ ] **Step 3: Update all view/controller callers that reference `Dashboard::FooComponent`**

Search for all `Dashboard::` component references and strip the prefix:

```bash
grep -rn "Dashboard::" app/views --include="*.erb" -l
```

Files to update (drop `Dashboard::` prefix):
- `app/views/layouts/dashboard.html.erb` (already done in Task 2 Step 3 for ShellComponent)
- `app/views/authentication/admin/users/*.html.erb` — `Dashboard::BreadcrumbsComponent` → `BreadcrumbsComponent`
- `app/views/dashboard/landing/show.html.erb` → will move in Task 4; update when moving
- `app/views/dashboard/settings/module_config.html.erb` → will move in Task 4
- `app/views/dashboard/settings/constants/*.html.erb` → will move in Task 4
- `app/views/dashboard/entities/show.html.erb` → will move in Task 4

For the authentication views that won't move:
```erb
<%# app/views/authentication/admin/users/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [...]) %>
```
Apply to `index.html.erb`, `show.html.erb`, `new.html.erb`, `edit.html.erb` under `authentication/admin/users/`.

- [ ] **Step 4: Delete old component directory**

```bash
rm -rf app/components/dashboard
```

- [ ] **Step 5: Commit**

```bash
git add app/components/ app/views/authentication/
git commit -m "refactor: move components out of Dashboard namespace"
```

---

## Task 4: Move views

**Files:**
- Move: `app/views/dashboard/**/*` → `app/views/**/*` (drop the `dashboard/` segment)

- [ ] **Step 1: Move view directories**

```bash
# Top-level dashboard views
cp -r app/views/dashboard/entities app/views/entities
cp -r app/views/dashboard/landing app/views/landing
cp -r app/views/dashboard/module_entries app/views/module_entries
cp -r app/views/dashboard/modules app/views/modules
cp -r app/views/dashboard/pages app/views/pages
cp -r app/views/dashboard/maintenances app/views/maintenances
cp -r app/views/dashboard/maintenance app/views/maintenance
cp -r app/views/dashboard/settings app/views/settings
```

- [ ] **Step 2: Strip `Dashboard::` component references in all moved view files**

Run:
```bash
grep -rn "Dashboard::" app/views --include="*.erb" -l
```

For every occurrence of `Dashboard::SomethingComponent` in the newly-moved views, replace with `SomethingComponent`.

Key files: `app/views/landing/show.html.erb`, `app/views/settings/module_config.html.erb`, `app/views/settings/constants/*.html.erb`, `app/views/entities/show.html.erb`.

- [ ] **Step 3: Delete old views/dashboard directory**

```bash
rm -rf app/views/dashboard
```

- [ ] **Step 4: Commit**

```bash
git add app/views/
git commit -m "refactor: move views out of dashboard/ directory"
```

---

## Task 5: Update routes (`scope module: :dashboard`)

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Update the routes module scope**

In `config/routes.rb`, change line 46:
```ruby
# Before
scope module: :dashboard do

# After
scope do
```

Also update the landing controller reference on line 43:
```ruby
# Before
get "/", to: "dashboard/landing#show", as: :dashboard_root

# After
get "/", to: "landing#show", as: :dashboard_root
```

And the maintenance sub-scope controller references (all within the scope block) are now looked up without the `dashboard/` module prefix. Rails will find them in the flat `app/controllers/` tree.

Verify by checking that the scope block controllers no longer need a `dashboard/` prefix:
- `"entities#index"` → resolves to `EntitiesController`
- `"maintenance/customer_profile#show"` → resolves to `Maintenance::CustomerProfileController`
- etc.

- [ ] **Step 2: Verify routes load**

```bash
bin/rails routes 2>&1 | head -5
```
Expected: no errors, routes list prints.

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "refactor: remove dashboard module scope from routes"
```

---

## Task 6: Rename JS Stimulus controllers

**Files:**
- Rename: `app/javascript/controllers/dashboard_drawer_controller.js` → `app/javascript/controllers/drawer_controller.js`
- Rename: `app/javascript/controllers/dashboard_help_menu_controller.js` → `app/javascript/controllers/help_menu_controller.js`
- Rename: `app/javascript/controllers/dashboard_paginated_list_controller.js` → `app/javascript/controllers/paginated_list_controller.js`
- Rename: `app/javascript/controllers/dashboard_section_tabs_controller.js` → `app/javascript/controllers/section_tabs_controller.js`
- Rename: `app/javascript/controllers/dashboard_user_menu_controller.js` → `app/javascript/controllers/user_menu_controller.js`

Also need to find and rename the menu bar controller (check if `dashboard_menu_bar_controller.js` exists).

- [ ] **Step 1: Copy JS controller files to new names**

```bash
cp app/javascript/controllers/dashboard_drawer_controller.js app/javascript/controllers/drawer_controller.js
cp app/javascript/controllers/dashboard_help_menu_controller.js app/javascript/controllers/help_menu_controller.js
cp app/javascript/controllers/dashboard_paginated_list_controller.js app/javascript/controllers/paginated_list_controller.js
cp app/javascript/controllers/dashboard_section_tabs_controller.js app/javascript/controllers/section_tabs_controller.js
cp app/javascript/controllers/dashboard_user_menu_controller.js app/javascript/controllers/user_menu_controller.js
# Check for menu_bar:
ls app/javascript/controllers/dashboard_menu_bar_controller.js 2>/dev/null && \
  cp app/javascript/controllers/dashboard_menu_bar_controller.js app/javascript/controllers/menu_bar_controller.js
```

- [ ] **Step 2: Update all `data-controller` attributes in component ERB templates**

Stimulus derives the controller identifier from the filename: `drawer_controller.js` → `data-controller="drawer"`. Update every reference:

`app/components/drawer_component.html.erb`:
- `data-controller="dashboard-drawer"` → `data-controller="drawer"`
- `data-dashboard-drawer-target="..."` → `data-drawer-target="..."`
- `data-action="click->dashboard-drawer#..."` → `data-action="click->drawer#..."`

`app/components/help_menu_component.html.erb`:
- `data-controller="dashboard-help-menu"` → `data-controller="help-menu"`
- `data-dashboard-help-menu-target="..."` → `data-help-menu-target="..."`
- `data-action="click->dashboard-help-menu#..."` → `data-action="click->help-menu#..."`

`app/components/user_menu_component.html.erb`:
- `data-controller="dashboard-user-menu"` → `data-controller="user-menu"`
- `data-dashboard-user-menu-target="..."` → `data-user-menu-target="..."`
- `data-action="click->dashboard-user-menu#..."` → `data-action="click->user-menu#..."`

`app/components/paginated_list_component.html.erb`:
- `data-controller="dashboard-paginated-list"` → `data-controller="paginated-list"`
- All `data-dashboard-paginated-list-target="..."` → `data-paginated-list-target="..."`
- All `data-action="..->dashboard-paginated-list#..."` → `data-action="..->paginated-list#..."`

`app/components/menu_bar_component.html.erb`:
- `data-controller="dashboard-menu-bar"` → `data-controller="menu-bar"`
- Any `data-dashboard-menu-bar-*` → `data-menu-bar-*`

Also check `app/components/topbar_component.html.erb` for `dashboard-drawer` actions (the open button references it):
- `data-action="click->dashboard-drawer#open"` → `data-action="click->drawer#open"`

And `app/components/drawer_component.html.erb` close button:
- `data-action="click->dashboard-drawer#close"` → `data-action="click->drawer#close"`

Check for any `dashboard-section-tabs` references:
```bash
grep -rn "dashboard-section-tabs" app/components app/views --include="*.erb"
```
Update any found to `section-tabs`.

- [ ] **Step 3: Delete old dashboard JS controller files**

```bash
rm app/javascript/controllers/dashboard_drawer_controller.js
rm app/javascript/controllers/dashboard_help_menu_controller.js
rm app/javascript/controllers/dashboard_paginated_list_controller.js
rm app/javascript/controllers/dashboard_section_tabs_controller.js
rm app/javascript/controllers/dashboard_user_menu_controller.js
rm -f app/javascript/controllers/dashboard_menu_bar_controller.js
```

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/ app/components/
git commit -m "refactor: rename dashboard_ Stimulus controllers, drop prefix"
```

---

## Task 7: Update the layout helper

**Files:**
- Move: `app/helpers/dashboard_layout_helper.rb` → `app/helpers/layout_helper.rb`

- [ ] **Step 1: Copy and update the helper**

```bash
cp app/helpers/dashboard_layout_helper.rb app/helpers/layout_helper.rb
```

Edit `app/helpers/layout_helper.rb` — rename the module:
```ruby
# Before
module DashboardLayoutHelper

# After
module LayoutHelper
```

- [ ] **Step 2: Update any explicit include of DashboardLayoutHelper**

```bash
grep -rn "DashboardLayoutHelper\|dashboard_layout_helper" app --include="*.rb"
```

Rails auto-includes helpers by convention; if nothing explicitly includes `DashboardLayoutHelper`, no other changes are needed. If found, update `DashboardLayoutHelper` → `LayoutHelper`.

- [ ] **Step 3: Delete old helper file**

```bash
rm app/helpers/dashboard_layout_helper.rb
```

- [ ] **Step 4: Commit**

```bash
git add app/helpers/
git commit -m "refactor: rename DashboardLayoutHelper to LayoutHelper"
```

---

## Task 8: Move and update spec files

**Files:**
- Move: all `spec/components/dashboard/*` → `spec/components/*`
- Move: all `spec/concerns/dashboard/*` → `spec/concerns/*`
- Move: all `spec/controllers/dashboard/*` → `spec/controllers/*`  (with `maintenance/` and `settings/` subdirs)
- Move: all `spec/requests/dashboard/*` → `spec/requests/*`  (with subdirs)
- Move: all `spec/services/dashboard/*` → `spec/services/*`  (with `search/` subdir)
- Move: all `spec/system/dashboard/*` → `spec/system/*`
- Move: `spec/helpers/dashboard_layout_helper_spec.rb` → `spec/helpers/layout_helper_spec.rb`
- Move: `spec/routing/dashboard_routes_spec.rb` → `spec/routing/routes_spec.rb`

- [ ] **Step 1: Copy spec files to new locations**

```bash
# Components
for f in spec/components/dashboard/*_spec.rb; do cp "$f" "spec/components/$(basename $f)"; done

# Concerns
mkdir -p spec/concerns
for f in spec/concerns/dashboard/*_spec.rb; do cp "$f" "spec/concerns/$(basename $f)"; done

# Controllers
mkdir -p spec/controllers/maintenance spec/controllers/settings
for f in spec/controllers/dashboard/*_spec.rb; do cp "$f" "spec/controllers/$(basename $f)" 2>/dev/null; done
for f in spec/controllers/dashboard/maintenance/*_spec.rb; do cp "$f" "spec/controllers/maintenance/$(basename $f)"; done
for f in spec/controllers/dashboard/settings/*_spec.rb; do cp "$f" "spec/controllers/settings/$(basename $f)"; done

# Requests
mkdir -p spec/requests/maintenance
for f in spec/requests/dashboard/*_spec.rb; do cp "$f" "spec/requests/$(basename $f)" 2>/dev/null; done
for f in spec/requests/dashboard/maintenance/*_spec.rb; do cp "$f" "spec/requests/maintenance/$(basename $f)"; done

# Services
mkdir -p spec/services/search
for f in spec/services/dashboard/*_spec.rb; do cp "$f" "spec/services/$(basename $f)" 2>/dev/null; done
for f in spec/services/dashboard/search/*_spec.rb; do cp "$f" "spec/services/search/$(basename $f)"; done

# System
for f in spec/system/dashboard/*_spec.rb; do cp "$f" "spec/system/$(basename $f)"; done

# Helpers and routing
cp spec/helpers/dashboard_layout_helper_spec.rb spec/helpers/layout_helper_spec.rb
cp spec/routing/dashboard_routes_spec.rb spec/routing/routes_spec.rb
```

- [ ] **Step 2: Update `RSpec.describe` class names in all moved spec files**

Find and replace `Dashboard::` in all copied spec files:

```bash
# Preview what needs changing
grep -rn "Dashboard::" spec/components spec/concerns spec/controllers spec/requests spec/services spec/system spec/helpers spec/routing --include="*_spec.rb" | grep -v "/dashboard/"
```

For each file, replace `Dashboard::Foo` with `Foo`. Examples:

`spec/components/shell_component_spec.rb`:
```ruby
# Before
RSpec.describe Dashboard::ShellComponent, type: :component do

# After
RSpec.describe ShellComponent, type: :component do
```

`spec/controllers/maintenance/flowcharts_controller_spec.rb`:
```ruby
# Before
RSpec.describe Dashboard::Maintenance::FlowchartsController, type: :controller do

# After
RSpec.describe Maintenance::FlowchartsController, type: :controller do
```

`spec/services/dashboard_context_spec.rb`:
```ruby
# Before
RSpec.describe Dashboard::DashboardContext do

# After
RSpec.describe DashboardContext do
```

`spec/services/maintenance_contributor_spec.rb`:
All `Dashboard::DashboardContext.new(...)` → `DashboardContext.new(...)`

`spec/helpers/layout_helper_spec.rb`:
```ruby
# Before
RSpec.describe DashboardLayoutHelper

# After
RSpec.describe LayoutHelper
```

Apply the same `Dashboard::Foo` → `Foo` pattern exhaustively across all moved spec files.

- [ ] **Step 3: Delete old spec directories**

```bash
rm -rf spec/components/dashboard
rm -rf spec/concerns/dashboard
rm -rf spec/controllers/dashboard
rm -rf spec/requests/dashboard
rm -rf spec/services/dashboard
rm -rf spec/system/dashboard
rm -f spec/helpers/dashboard_layout_helper_spec.rb
rm -f spec/routing/dashboard_routes_spec.rb
```

- [ ] **Step 4: Run the full spec suite to confirm nothing is broken**

```bash
bundle exec rspec --format progress 2>&1 | tail -20
```

Expected: all examples pass (or the same count that passed before this refactor — no new failures).

- [ ] **Step 5: Commit**

```bash
git add spec/
git commit -m "refactor: move specs out of dashboard/ directories, update class names"
```

---

## Task 9: Clean up `dashboard/` directory remnants and verify

- [ ] **Step 1: Confirm no old dashboard directories remain**

```bash
find /opt/milestone/anysys/app -type d -name "dashboard"
find /opt/milestone/anysys/spec -type d -name "dashboard"
```
Expected: no output.

- [ ] **Step 2: Confirm no `module Dashboard` or `Dashboard::` remain in app/ or spec/**

```bash
grep -rn "module Dashboard\b\|Dashboard::" app/ spec/ --include="*.rb" | grep -v "dashboard_layout\|dashboard_root_path\|current_dashboard_menu_item\|PLATFORM_OWNER_CONTROLLERS\|dashboard_menu\|dashboard_layout_helper"
```
Expected: no output (or only legitimate uses like `dashboard_root_path` route helper and `current_dashboard_menu_item` method name — these are route/method names, not module namespacing).

- [ ] **Step 3: Confirm no `dashboard/` in controller string references in routes**

```bash
grep "dashboard" config/routes.rb
```
Expected: only the `as: :dashboard_root` named route (which is fine — it's a route name, not a URL segment) and the layout file name.

- [ ] **Step 4: Restart server and smoke test**

```bash
rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000
```

Navigate to `/:customer_id/` — verify Home, Entities, Pages, Modules, Settings, Maintenance all load without errors.

- [ ] **Step 5: Run full test suite**

```bash
bundle exec rspec --format progress 2>&1 | tail -5
```
Expected: 0 failures.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "refactor: complete removal of Dashboard namespace and directory prefix"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Controllers moved and unwrapped (Task 1)
- ✅ Services moved and unwrapped (Task 2)
- ✅ Components moved and unwrapped (Task 3)
- ✅ Views moved (Task 4)
- ✅ Routes updated (`scope module: :dashboard` removed, landing controller path updated) (Task 5)
- ✅ JS controllers renamed from `dashboard_*` to suffix-only, `data-controller` attrs updated (Task 6)
- ✅ Layout helper renamed `DashboardLayoutHelper` → `LayoutHelper` (Task 7)
- ✅ All specs moved and updated (Task 8)
- ✅ Verification and cleanup (Task 9)

**Placeholder scan:** No TBD/TODO/placeholder steps present. All steps include exact file paths or commands.

**Type consistency:** `DashboardContext` struct → `DashboardContext` (kept name, just removed outer module wrapper, so callers change `Dashboard::DashboardContext` → `DashboardContext`). All cross-references consistent.

**Notes on naming:**
- Route helper `dashboard_root_path` and method `current_dashboard_menu_item` are kept as-is — they are identifiers, not namespace markers.
- The layout file stays at `app/views/layouts/dashboard.html.erb` — it's a layout name, not a namespace.
- The `maintenance/` and `settings/` sub-modules within controllers are kept since they disambiguate controller classes (e.g. `Maintenance::EntitiesController` vs `EntitiesController`).

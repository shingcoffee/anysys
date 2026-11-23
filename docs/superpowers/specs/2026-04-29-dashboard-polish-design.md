# Dashboard Polish: Topbar Refresh, Working Search, Modules-Only Settings

**Date:** 2026-04-29
**Status:** Approved

## Problem

Three user-visible issues in the dashboard shell:

1. The topbar (`app/components/dashboard/topbar_component.html.erb`) and the
   menu bar under it feel dated — dated typography/borders, inconsistent icon
   weights, a cramped Search button, and an overall hard-edged look.
2. The Search button opens a palette that tells the user "Search is coming
   soon." It is an affordance that promises a feature that does not exist.
3. The Settings tab currently lists three concerns — Customer Profile, Users,
   and per-module configuration. The user wants Settings to be strictly the
   customer-specific configuration surface for enabled / required modules.

## Goals

- Ship a visual refresh of the dashboard header that keeps every element in
  place but raises the polish level.
- Make Search actually work: type a query, see real results across Pages,
  Entities, and Modules (customer-scoped), navigate on click or Enter.
- Settings sidebar and routes list only modules that have customer-facing
  configuration. Customer Profile and Users are removed from Settings
  entirely; user management already lives under the User Authentication
  module (Modules tab).

## Non-Goals

- No redesign of the sidebar tree, drawer, or main-content area.
- No fuzzy ranking, typeahead scoring, or full-text engines — plain
  case-insensitive `ILIKE` on name/title columns is enough for this scope.
- No new top-level menu item. We are not relocating Customer Profile / Users
  somewhere else; they are deleted.
- No changes to individual module registrations or their own config UIs.
- No backwards-compatibility shims for the removed settings routes.

## Design

### 1. Topbar visual refresh

The elements stay: logo + mobile menu toggle, centered Search button, Help
menu, Notifications, User menu. Below it, the flat MenuBar with Home /
Entities / Pages / Modules / Settings / Maintenance.

Changes — Tailwind-only, no new JS:

- **Header container.** Height bumps from `h-14` to `h-16` for breathing room.
  Replace the hard `border-b border-gray-200` with a soft separation: white
  surface with `shadow-[0_1px_0_0_rgb(0_0_0/0.04)]` (a one-pixel subtle shadow
  instead of a line). Same treatment on the menu bar so the two bands read as
  one unit.
- **Logo / brand.** Slightly larger mark (`w-7 h-7`), tighter `gap-2.5` to the
  "Milestone" wordmark, bump wordmark weight to `font-semibold
  tracking-tight`. Indigo mark stays as the brand accent.
- **Icon set consistency.** Every SVG in the topbar uses `stroke-width="1.5"`,
  `stroke-linecap="round"`, `stroke-linejoin="round"`, and a shared
  `w-[18px] h-[18px]` size for action icons (search, help, bell). Fixes the
  current mix of weights/sizes.
- **Search button.** Replaces the flat gray pill with a raised input-like
  surface: `bg-white ring-1 ring-gray-200 shadow-sm hover:ring-gray-300
  hover:shadow`. Text becomes `text-gray-500`. The `⌘K` `<kbd>` gets proper
  sizing and `shadow-sm` so it looks like a key, not flat text. The surface
  widens to `min-w-[360px]` on `md:` and caps at `max-w-lg`.
- **Icon buttons (help, bell, avatar).** Uniform `h-9 w-9` circular hit
  target, `hover:bg-gray-100`, `focus-visible:ring-2 focus-visible:ring-indigo-500
  focus-visible:ring-offset-2`. No visible background until hover.
- **Menu bar.** Same soft-shadow band. Active tab keeps its current white
  pill, but gains `ring-1 ring-gray-200/80` and `shadow-sm`. Inactive tabs:
  `text-gray-600 hover:text-gray-900 hover:bg-gray-100/70`. Reduce vertical
  padding from `py-1.5` to `py-2` for symmetry.
- **Body background.** Keep `bg-gray-50`.

Accessibility: keep existing `aria-label`, `aria-current`, and
`focus-visible` rings — only their colors/sizes change.

### 2. Working search

#### Backend

New controller `app/controllers/dashboard/search_controller.rb`:

```ruby
module Dashboard
  class SearchController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def index
      q = params[:q].to_s.strip
      results = q.length < 2 ? [] : Dashboard::SearchQuery.call(
        customer: current_customer, query: q, user: current_user
      )
      render json: { query: q, groups: results }
    end

    private

    def current_dashboard_menu_item = nil
    helper_method :current_dashboard_menu_item
  end
end
```

New service `app/services/dashboard/search_query.rb` — orchestrates
per-source lookups and returns grouped results:

```ruby
module Dashboard
  class SearchQuery
    MAX_PER_GROUP = 5
    SOURCES = [PagesSource, EntitiesSource, ModulesSource].freeze

    def self.call(customer:, query:, user:)
      SOURCES
        .map { |src| src.new(customer: customer, query: query, user: user).to_group }
        .reject { |g| g[:items].empty? }
    end
  end
end
```

Each source is a small PORO in `app/services/dashboard/search/`:

- `PagesSource` — reuses the existing `Page.search_by_name(q)` scope, scoped
  to the current customer. Each item returns
  `{ label: page.name, path: "/#{cid}/dashboard/pages", icon: :page }`. Paths
  go to the Pages index; deep-linking is out of scope.
- `EntitiesSource` — reuses the existing `Entity.search_by_name(q)` scope,
  scoped to the current customer. Each item returns
  `{ label: entity.name, path: "/#{cid}/dashboard/entities/#{entity.id}", icon: :entity }`.
- `ModulesSource` — only modules enabled for the customer (via
  `FeatureModule.enabled_for_customer(customer.id)`), name filtered by
  `arel_table[:name].matches("%...%")` with the query pre-sanitized via
  `ActiveRecord::Base.sanitize_sql_like`. Path = `settings_module_path`.

Each source caps results at `MAX_PER_GROUP`. Group shape:

```ruby
{ key: :pages, label: "Pages", items: [ {label:, path:, icon:}, ... ] }
```

Both existing `search_by_name` scopes already downcase their inputs for a
case-insensitive `LIKE`. For the new `ModulesSource` lookup, pre-sanitize
the query with `ActiveRecord::Base.sanitize_sql_like` before passing it to
`#matches` to guard against `%`/`_` injection.

Route:

```ruby
# routes.rb, inside the dashboard namespace
get "search", to: "search#index", as: :search
```

#### Frontend

`app/components/dashboard/search_palette_component.html.erb` is rewritten:

- Input stays. Below it, a results region (`<div data-dashboard-search-target="results">`)
  that renders groups server-side via a small `search_palette_results_component`
  OR — simpler — a client-rendered template in JS. Choose client-rendered:
  the JSON shape is tiny, no Turbo Stream needed.
- Empty-state ("Type to search…") when query length < 2.
- "No results" state when all groups empty.

`app/javascript/controllers/dashboard_search_controller.js` is upgraded:

- Add a `debounce` around `input` (200ms).
- On input, `fetch("/{customer_id}/dashboard/search?q=...")` with
  `credentials: "same-origin"` and `Accept: application/json`. Customer id
  comes from a `data-customer-id` attribute added to the palette root.
- Render results into the `results` target using a small pure `render(groups)`
  function that returns HTML via `document.createElement` (no innerHTML with
  untrusted text — `textContent` only).
- Arrow Up / Down cycle focus across result links; Enter follows focused
  link; Esc still closes. ⌘K still opens.

### 3. Settings: modules-only

#### Routes (routes.rb)

Remove:

```ruby
get "settings/customer", to: "settings#customer", as: :settings_customer
get "settings/users",    to: "settings#users",    as: :settings_users
```

Keep: `settings#show`, `settings#module_config`, `settings_module_entry`.

#### Controller (`app/controllers/dashboard/settings_controller.rb`)

- Delete actions `customer` and `users`.
- Delete `before_action :require_admin_or_owner!, only: [:users]` and the
  corresponding private method — it has no remaining users.
- `show` stays; view copy is updated (below).

#### Views

- Delete `app/views/dashboard/settings/customer.html.erb`.
- Delete `app/views/dashboard/settings/users.html.erb`.
- `show.html.erb` — new copy:
  > "Configure the modules enabled for your organization. Pick a module from
  > the sidebar."
  >
  > If the sidebar is empty (no modules with settings), show a neutral state:
  > "No configurable modules enabled yet."

#### Sidebar (`app/services/dashboard/settings_contributor.rb`)

Replace entirely. New contract:

- List only modules that (a) are enabled for the customer and (b) have at
  least one customer-facing setting — defined as either:
  - `sidebar_contributions[:settings]` is non-empty, OR
  - `FeatureModule#configuration_schema` is a non-empty hash.
- A module with non-empty `:settings` expands into child nodes (one per
  settings contribution), same as today.
- A module with empty `:settings` but non-empty `configuration_schema`
  becomes a leaf node linking to `settings_module_path(module_key)` (the
  existing `module_config` view).
- Modules with neither do not appear in the Settings sidebar.

#### Specs

- `spec/routing/dashboard_routes_spec.rb`: remove the two route expectations
  for `/settings/customer` and `/settings/users`. Keep the `settings_module`
  and `settings_module_entry` expectations.
- `spec/requests/dashboard/settings_spec.rb`: remove the customer and users
  request examples. Add coverage for the new sidebar contract (a module with
  empty settings and empty schema is not listed; a module with only a
  configuration_schema becomes a leaf link).

## Architecture Notes

- Search is intentionally three independent sources composed by
  `SearchQuery`. Adding a new searchable type means adding one `*Source`
  class and one line to `SOURCES` — no changes to the controller or
  Stimulus controller.
- Settings sidebar filtering is pushed into `SettingsContributor`; the
  `FeatureModule` model is unchanged. No new methods on registrations.
- The topbar refresh is CSS-only. No new components, no new JS.

## Testing

### Unit / request

- `spec/services/dashboard/search_query_spec.rb` — exercises each source
  with a multi-tenant fixture, verifies customer scoping, caps, empty-query
  handling, and special-character escaping (`%`, `_`, single quote).
- `spec/requests/dashboard/search_spec.rb` — authenticated JSON request,
  verifies response shape and tenant scoping (a user for customer A cannot
  see customer B's pages even by passing `q` matching them).
- `spec/services/dashboard/settings_contributor_spec.rb` — module with empty
  settings + empty schema is excluded; module with only schema appears as
  leaf; module with `:settings` entries expands with children; empty customer
  → empty array.
- `spec/components/dashboard/search_palette_component_spec.rb` — renders
  input, results region, `data-customer-id`, empty state.

### System / happy path

- `spec/system/dashboard/search_spec.rb` (Capybara) — open ⌘K, type a query,
  see grouped results, press Enter on first, land on expected page.
- `spec/system/dashboard/settings_navigation_spec.rb` — signed-in user sees
  only module-configuration items in the Settings sidebar; no Customer
  Profile or Users links exist anywhere in the dashboard header.

### Manual

- Visual QA: confirm topbar + menu bar read as one band with soft shadow;
  focus rings consistent; Search button looks like an input, not a button.
- Start the Rails server and spot-check the header on Safari + Chrome.

## Migration / Rollout

One-shot change. No feature flag, no data migration. Removing
`settings/customer` and `settings/users` routes is accepted breakage per
project convention (no backward compatibility).

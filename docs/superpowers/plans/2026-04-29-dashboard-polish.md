# Dashboard Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Visually polish the dashboard header, wire Search to a real backend across Pages/Entities/Modules, and strip Settings down to module configuration only.

**Architecture:** Three independent vertical slices. (1) Settings cleanup — delete routes/actions/views, rewrite `SettingsContributor` to filter modules. (2) Search backend/frontend — new `SearchController`, `SearchQuery` + per-source POROs, rewritten palette component + Stimulus controller. (3) Topbar visual refresh — Tailwind-only tweaks to existing components.

**Tech Stack:** Rails 8.1.2, ViewComponent, Tailwind, StimulusJS, RSpec.

---

## File Structure

**Settings slice:**
- Modify: `config/routes.rb` (remove two routes)
- Modify: `app/controllers/dashboard/settings_controller.rb` (drop two actions)
- Delete: `app/views/dashboard/settings/customer.html.erb`
- Delete: `app/views/dashboard/settings/users.html.erb`
- Modify: `app/views/dashboard/settings/show.html.erb` (copy update + empty state)
- Modify: `app/services/dashboard/settings_contributor.rb` (modules-only filter)
- Modify: `spec/routing/dashboard_routes_spec.rb` (drop old route assertions)
- Modify: `spec/requests/dashboard/settings_spec.rb` (drop old action specs, add empty-state + filtered-sidebar specs)
- Modify: `spec/services/dashboard/settings_contributor_spec.rb` (new contract)

**Search slice:**
- Create: `app/services/dashboard/search/base_source.rb`
- Create: `app/services/dashboard/search/pages_source.rb`
- Create: `app/services/dashboard/search/entities_source.rb`
- Create: `app/services/dashboard/search/modules_source.rb`
- Create: `app/services/dashboard/search_query.rb`
- Create: `app/controllers/dashboard/search_controller.rb`
- Modify: `config/routes.rb` (add search route)
- Modify: `app/components/dashboard/search_palette_component.rb` (accept customer id)
- Modify: `app/components/dashboard/search_palette_component.html.erb` (input, results container)
- Modify: `app/components/dashboard/shell_component.html.erb` (pass customer id)
- Modify: `app/javascript/controllers/dashboard_search_controller.js` (fetch + render)
- Create: `spec/services/dashboard/search/pages_source_spec.rb`
- Create: `spec/services/dashboard/search/entities_source_spec.rb`
- Create: `spec/services/dashboard/search/modules_source_spec.rb`
- Create: `spec/services/dashboard/search_query_spec.rb`
- Create: `spec/requests/dashboard/search_spec.rb`
- Modify: `spec/components/dashboard/search_palette_component_spec.rb`

**Topbar slice:**
- Modify: `app/components/dashboard/topbar_component.html.erb`
- Modify: `app/components/dashboard/search_button_component.html.erb`
- Modify: `app/components/dashboard/menu_bar_component.rb` (class tweaks)
- Modify: `app/components/dashboard/shell_component.html.erb` (if the container styles shift)

---

## Task 1: Remove Settings customer and users routes

**Files:**
- Modify: `config/routes.rb:57-58`
- Modify: `spec/routing/dashboard_routes_spec.rb:24-31`

- [ ] **Step 1: Update the routing spec to reflect the new surface**

Edit `spec/routing/dashboard_routes_spec.rb` — replace the current `it "routes settings and sub-pages"` example with:

```ruby
  it "routes settings and module sub-pages" do
    expect(get: "/12345678/dashboard/settings").to route_to(
      controller: "dashboard/settings", action: "show", customer_id: "12345678"
    )
    expect(get: "/12345678/dashboard/settings/modules/payment").to route_to(
      controller: "dashboard/settings", action: "module_config",
      customer_id: "12345678", module_key: "payment"
    )
    expect(get: "/12345678/dashboard/settings/modules/payment/gateway").to route_to(
      controller: "dashboard/settings", action: "module_config",
      customer_id: "12345678", module_key: "payment", entry_key: "gateway"
    )
  end

  it "does not route removed settings customer/users paths" do
    expect(get: "/12345678/dashboard/settings/customer").not_to be_routable
    expect(get: "/12345678/dashboard/settings/users").not_to be_routable
  end
```

- [ ] **Step 2: Run the routing specs and confirm the new ones fail**

Run: `bundle exec rspec spec/routing/dashboard_routes_spec.rb -fd`
Expected: the "does not route…" example FAILS (routes still exist).

- [ ] **Step 3: Remove the two routes**

Edit `config/routes.rb` — delete lines 57 and 58. The resulting block:

```ruby
      get "settings",                                  to: "settings#show",          as: :settings
      get "settings/modules/:module_key",              to: "settings#module_config", as: :settings_module
      get "settings/modules/:module_key/:entry_key",   to: "settings#module_config", as: :settings_module_entry
```

- [ ] **Step 4: Re-run the routing specs and confirm all pass**

Run: `bundle exec rspec spec/routing/dashboard_routes_spec.rb -fd`
Expected: all examples PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb spec/routing/dashboard_routes_spec.rb
git commit -m "refactor(dashboard): remove settings/customer and settings/users routes"
```

---

## Task 2: Drop customer and users actions + views from the Settings controller

**Files:**
- Modify: `app/controllers/dashboard/settings_controller.rb`
- Delete: `app/views/dashboard/settings/customer.html.erb`
- Delete: `app/views/dashboard/settings/users.html.erb`
- Modify: `spec/requests/dashboard/settings_spec.rb`

- [ ] **Step 1: Update the request spec to drop the deleted actions and expect 404s**

Replace `spec/requests/dashboard/settings_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard settings", type: :request do
  let(:customer) { create(:customer) }
  let(:owner)    { create(:user, customer: customer, role: :owner) }

  before { sign_in owner }

  it "renders the settings index with module-focused empty copy" do
    get "/#{customer.id}/dashboard/settings"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Configure the modules")
  end

  it "returns 404 for the removed customer profile route" do
    expect { get "/#{customer.id}/dashboard/settings/customer" }
      .to raise_error(ActionController::RoutingError).or(change { response.status }.to(404))
  end

  it "returns 404 for the removed users route" do
    expect { get "/#{customer.id}/dashboard/settings/users" }
      .to raise_error(ActionController::RoutingError).or(change { response.status }.to(404))
  end

  it "renders a module config page for an enabled module" do
    fm = FeatureModule.find_or_create_by!(key: "payment") do |m|
      m.name = "Payments"
      m.status = :active
      m.configuration_schema = {}.to_json
    end
    CustomerFeatureModule.find_or_create_by!(customer: customer, feature_module: fm) do |cfm|
      cfm.status = :active
      cfm.configuration = {}.to_json
      cfm.enabled_at = Time.current
    end
    get "/#{customer.id}/dashboard/settings/modules/payment"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payments")
  end
end
```

- [ ] **Step 2: Run the request spec and confirm the new examples fail**

Run: `bundle exec rspec spec/requests/dashboard/settings_spec.rb -fd`
Expected: the "renders the settings index…" example FAILS (copy still says "Pick an item…"); "404 for the removed…" examples may pass or fail depending on route removal status.

- [ ] **Step 3: Remove the two controller actions and helper**

Rewrite `app/controllers/dashboard/settings_controller.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SettingsController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def show
    end

    def module_config
      @feature_module = FeatureModule.find_by!(key: params[:module_key])
      return head :not_found unless FeatureModule.enabled?(
        key: @feature_module.key, customer_id: current_customer.id
      )
      @customer_feature_module = CustomerFeatureModule.find_by!(
        customer_id: current_customer.id, feature_module_id: @feature_module.id
      )
      @entry_key = params[:entry_key]
    end

    private

    def current_dashboard_menu_item = :settings
    helper_method :current_dashboard_menu_item
  end
end
```

- [ ] **Step 4: Delete the two view files**

Run:

```bash
rm app/views/dashboard/settings/customer.html.erb
rm app/views/dashboard/settings/users.html.erb
```

- [ ] **Step 5: Update the settings show view copy**

Rewrite `app/views/dashboard/settings/show.html.erb`:

```erb
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [{ label: "Settings", path: nil }]) %>
<section class="bg-white border border-gray-200 rounded-md p-8 text-center">
  <h1 class="text-base font-semibold text-gray-900">Settings</h1>
  <p class="mt-2 text-sm text-gray-500">
    Configure the modules enabled for your organization. Pick a module from the sidebar.
  </p>
</section>
```

- [ ] **Step 6: Run the request spec and confirm all pass**

Run: `bundle exec rspec spec/requests/dashboard/settings_spec.rb -fd`
Expected: all examples PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/dashboard/settings_controller.rb \
        app/views/dashboard/settings/show.html.erb \
        spec/requests/dashboard/settings_spec.rb
git add -u app/views/dashboard/settings
git commit -m "refactor(dashboard): remove customer/users settings actions and views"
```

---

## Task 3: Rewrite SettingsContributor to list only modules with configurable options

**Files:**
- Modify: `app/services/dashboard/settings_contributor.rb`
- Modify: `spec/services/dashboard/settings_contributor_spec.rb`

- [ ] **Step 1: Write the new contributor spec**

Replace `spec/services/dashboard/settings_contributor_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SettingsContributor do
  let(:customer) { create(:customer) }
  let(:context) do
    Dashboard::DashboardContext.new(
      current_user: nil,
      current_customer: customer,
      current_menu_item: :settings,
      request_path: "/"
    )
  end

  def enable_module(key:, name:, configuration_schema: {}, settings_contributions: [])
    fm = FeatureModule.find_or_create_by!(key: key) do |m|
      m.name = name
      m.status = :active
      m.configuration_schema = configuration_schema.to_json
    end
    fm.update!(configuration_schema: configuration_schema.to_json, name: name)
    CustomerFeatureModule.find_or_create_by!(customer: customer, feature_module: fm) do |cfm|
      cfm.status = :active
      cfm.configuration = {}.to_json
      cfm.enabled_at = Time.current
    end
    allow(fm.registration_class).to receive(:sidebar_contributions)
      .and_return(entries: [], settings: settings_contributions, metadata: {})
    fm
  end

  it "returns an empty list when the customer has no enabled modules" do
    expect(described_class.new(context).contribute).to eq([])
  end

  it "omits modules with empty settings contributions AND empty configuration_schema" do
    enable_module(key: "mod_a", name: "Mod A", configuration_schema: {}, settings_contributions: [])
    expect(described_class.new(context).contribute).to eq([])
  end

  it "lists a module as a leaf when it has a configuration_schema but no settings contributions" do
    enable_module(
      key: "mod_b", name: "Mod B",
      configuration_schema: { "flag" => { "type" => "boolean" } },
      settings_contributions: []
    )
    nodes = described_class.new(context).contribute
    expect(nodes.map(&:label)).to eq(["Mod B"])
    expect(nodes.first.children).to eq([])
    expect(nodes.first.path).to eq("/#{customer.id}/dashboard/settings/modules/mod_b")
    expect(nodes.first.menu_item).to eq(:settings)
  end

  it "expands a module with settings contributions into children" do
    enable_module(
      key: "mod_c", name: "Mod C",
      configuration_schema: {},
      settings_contributions: [
        Dashboard::ModuleContribution.new(label: "Gateway", entry_key: "gateway")
      ]
    )
    nodes = described_class.new(context).contribute
    expect(nodes.map(&:label)).to eq(["Mod C"])
    children = nodes.first.children
    expect(children.map(&:label)).to eq(["Gateway"])
    expect(children.first.path).to eq("/#{customer.id}/dashboard/settings/modules/mod_c/gateway")
  end

  it "orders modules by name" do
    enable_module(key: "mod_z", name: "Zeta", configuration_schema: { "x" => {} })
    enable_module(key: "mod_a", name: "Alpha", configuration_schema: { "x" => {} })
    nodes = described_class.new(context).contribute
    expect(nodes.map(&:label)).to eq(["Alpha", "Zeta"])
  end
end
```

- [ ] **Step 2: Run the new spec and confirm it fails**

Run: `bundle exec rspec spec/services/dashboard/settings_contributor_spec.rb -fd`
Expected: examples FAIL (old contributor still returns Customer Profile + Users nodes).

- [ ] **Step 3: Rewrite the contributor**

Replace `app/services/dashboard/settings_contributor.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SettingsContributor < SidebarContributor
    MENU_ITEM = :settings

    def contribute
      return [] if customer_id.blank?

      FeatureModule.enabled_for_customer(customer_id).by_name.filter_map do |fm|
        settings = Array(fm.registration_class.sidebar_contributions(nil)[:settings])
        schema   = fm.configuration_schema || {}

        next nil if settings.empty? && schema.empty?

        build_node(fm, settings)
      end
    end

    private

    def build_node(fm, settings_contributions)
      if settings_contributions.empty?
        SidebarNode.new(
          key: "settings.modules.#{fm.key}",
          label: fm.name,
          menu_item: MENU_ITEM,
          path: "/#{customer_id}/dashboard/settings/modules/#{fm.key}"
        )
      else
        SidebarNode.new(
          key: "settings.modules.#{fm.key}",
          label: fm.name,
          menu_item: MENU_ITEM,
          children: settings_contributions.map { |c|
            c.to_sidebar_node(menu_item: MENU_ITEM, module_key: fm.key, customer_id: customer_id)
          }
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run the contributor spec and confirm all pass**

Run: `bundle exec rspec spec/services/dashboard/settings_contributor_spec.rb -fd`
Expected: all examples PASS.

- [ ] **Step 5: Run broader dashboard specs for regressions**

Run: `bundle exec rspec spec/services/dashboard spec/components/dashboard spec/requests/dashboard -fd`
Expected: all PASS. If a sidebar builder spec breaks because it asserted "Customer Profile" or "Users", update it.

- [ ] **Step 6: Commit**

```bash
git add app/services/dashboard/settings_contributor.rb \
        spec/services/dashboard/settings_contributor_spec.rb
git commit -m "refactor(dashboard): limit settings sidebar to configurable modules"
```

---

## Task 4: Create search sources — base + pages source (TDD)

**Files:**
- Create: `app/services/dashboard/search/base_source.rb`
- Create: `app/services/dashboard/search/pages_source.rb`
- Create: `spec/services/dashboard/search/pages_source_spec.rb`

- [ ] **Step 1: Write the pages source spec**

Create `spec/services/dashboard/search/pages_source_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Search::PagesSource do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user)           { create(:user, customer: customer, role: :admin) }

  def build(query)
    described_class.new(customer: customer, query: query, user: user).to_group
  end

  it "returns pages for the customer whose name matches the query (case insensitive)" do
    create(:page, customer: customer, name: "Checkout Form")
    create(:page, customer: customer, name: "Onboarding")
    group = build("CHECK")
    expect(group[:key]).to eq(:pages)
    expect(group[:label]).to eq("Pages")
    expect(group[:items].map { |i| i[:label] }).to eq(["Checkout Form"])
    expect(group[:items].first[:path]).to eq("/#{customer.id}/dashboard/pages")
    expect(group[:items].first[:icon]).to eq(:page)
  end

  it "excludes pages belonging to other customers" do
    create(:page, customer: other_customer, name: "Checkout Form")
    expect(build("Checkout")[:items]).to be_empty
  end

  it "caps results at 5" do
    7.times { |i| create(:page, customer: customer, name: "Match #{i}") }
    expect(build("Match")[:items].size).to eq(5)
  end

  it "returns an empty group when the query is blank" do
    create(:page, customer: customer, name: "Anything")
    expect(build("")[:items]).to be_empty
  end

  it "safely handles special LIKE characters" do
    create(:page, customer: customer, name: "100% Good")
    # '%' should be treated literally, not as wildcard
    expect(build("100%")[:items].map { |i| i[:label] }).to eq(["100% Good"])
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/services/dashboard/search/pages_source_spec.rb -fd`
Expected: FAIL with "uninitialized constant Dashboard::Search::PagesSource".

- [ ] **Step 3: Create the base source**

Create `app/services/dashboard/search/base_source.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  module Search
    class BaseSource
      MAX_PER_GROUP = 5
      MIN_QUERY_LENGTH = 2

      def initialize(customer:, query:, user:)
        @customer = customer
        @query    = query.to_s.strip
        @user     = user
      end

      def to_group
        { key: group_key, label: group_label, items: usable_query? ? items : [] }
      end

      protected

      attr_reader :customer, :query, :user

      def usable_query?
        query.length >= MIN_QUERY_LENGTH
      end

      def escaped_like
        ActiveRecord::Base.sanitize_sql_like(query)
      end

      def group_key   = raise NotImplementedError
      def group_label = raise NotImplementedError
      def items       = raise NotImplementedError
    end
  end
end
```

- [ ] **Step 4: Create the pages source**

Create `app/services/dashboard/search/pages_source.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  module Search
    class PagesSource < BaseSource
      protected

      def group_key   = :pages
      def group_label = "Pages"

      def items
        Page.where(customer_id: customer.id)
            .where("LOWER(name) LIKE ?", "%#{escaped_like.downcase}%")
            .order(:name)
            .limit(MAX_PER_GROUP)
            .map { |p| { label: p.name, path: "/#{customer.id}/dashboard/pages", icon: :page } }
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec and confirm all pass**

Run: `bundle exec rspec spec/services/dashboard/search/pages_source_spec.rb -fd`
Expected: all examples PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/dashboard/search/base_source.rb \
        app/services/dashboard/search/pages_source.rb \
        spec/services/dashboard/search/pages_source_spec.rb
git commit -m "feat(dashboard): add search base + pages source"
```

---

## Task 5: Add entities and modules search sources (TDD)

**Files:**
- Create: `app/services/dashboard/search/entities_source.rb`
- Create: `app/services/dashboard/search/modules_source.rb`
- Create: `spec/services/dashboard/search/entities_source_spec.rb`
- Create: `spec/services/dashboard/search/modules_source_spec.rb`

- [ ] **Step 1: Write the entities source spec**

Create `spec/services/dashboard/search/entities_source_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Search::EntitiesSource do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user)           { create(:user, customer: customer, role: :admin) }

  def build(query)
    described_class.new(customer: customer, query: query, user: user).to_group
  end

  it "returns entities for the customer matching the query" do
    entity = create(:entity, customer: customer, name: "Invoice")
    create(:entity, customer: customer, name: "Product")
    group = build("inv")
    expect(group[:key]).to eq(:entities)
    expect(group[:label]).to eq("Entities")
    expect(group[:items].map { |i| i[:label] }).to eq(["Invoice"])
    expect(group[:items].first[:path]).to eq("/#{customer.id}/dashboard/entities/#{entity.id}")
    expect(group[:items].first[:icon]).to eq(:entity)
  end

  it "excludes other customers' entities" do
    create(:entity, customer: other_customer, name: "Invoice")
    expect(build("Invoice")[:items]).to be_empty
  end

  it "caps results at 5" do
    7.times { |i| create(:entity, customer: customer, name: "Row #{i}") }
    expect(build("Row")[:items].size).to eq(5)
  end
end
```

- [ ] **Step 2: Write the modules source spec**

Create `spec/services/dashboard/search/modules_source_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Search::ModulesSource do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }

  def enable(key:, name:)
    fm = FeatureModule.find_or_create_by!(key: key) do |m|
      m.name = name
      m.status = :active
      m.configuration_schema = {}.to_json
    end
    fm.update!(name: name)
    CustomerFeatureModule.find_or_create_by!(customer: customer, feature_module: fm) do |cfm|
      cfm.status = :active
      cfm.configuration = {}.to_json
      cfm.enabled_at = Time.current
    end
    fm
  end

  def build(query)
    described_class.new(customer: customer, query: query, user: user).to_group
  end

  it "returns enabled modules for the customer matching the query" do
    enable(key: "payment", name: "Payments (WeChat + Alipay)")
    enable(key: "sms",     name: "SMS Gateway")
    group = build("pay")
    expect(group[:key]).to eq(:modules)
    expect(group[:label]).to eq("Modules")
    expect(group[:items].map { |i| i[:label] }).to eq(["Payments (WeChat + Alipay)"])
    expect(group[:items].first[:path]).to eq("/#{customer.id}/dashboard/settings/modules/payment")
    expect(group[:items].first[:icon]).to eq(:module)
  end

  it "excludes modules not enabled for the customer" do
    FeatureModule.find_or_create_by!(key: "payment") do |m|
      m.name = "Payments"
      m.status = :active
      m.configuration_schema = {}.to_json
    end
    expect(build("pay")[:items]).to be_empty
  end
end
```

- [ ] **Step 3: Run both specs and confirm they fail**

Run: `bundle exec rspec spec/services/dashboard/search -fd`
Expected: both new files FAIL with "uninitialized constant".

- [ ] **Step 4: Create the entities source**

Create `app/services/dashboard/search/entities_source.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  module Search
    class EntitiesSource < BaseSource
      protected

      def group_key   = :entities
      def group_label = "Entities"

      def items
        Entity.where(customer_id: customer.id)
              .where("LOWER(name) LIKE ?", "%#{escaped_like.downcase}%")
              .order(:name)
              .limit(MAX_PER_GROUP)
              .map { |e| { label: e.name, path: "/#{customer.id}/dashboard/entities/#{e.id}", icon: :entity } }
      end
    end
  end
end
```

- [ ] **Step 5: Create the modules source**

Create `app/services/dashboard/search/modules_source.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  module Search
    class ModulesSource < BaseSource
      protected

      def group_key   = :modules
      def group_label = "Modules"

      def items
        FeatureModule
          .enabled_for_customer(customer.id)
          .where("LOWER(feature_modules.name) LIKE ?", "%#{escaped_like.downcase}%")
          .order(:name)
          .limit(MAX_PER_GROUP)
          .map { |fm|
            {
              label: fm.name,
              path:  "/#{customer.id}/dashboard/settings/modules/#{fm.key}",
              icon:  :module
            }
          }
      end
    end
  end
end
```

- [ ] **Step 6: Run both specs and confirm all pass**

Run: `bundle exec rspec spec/services/dashboard/search -fd`
Expected: all examples PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/dashboard/search/entities_source.rb \
        app/services/dashboard/search/modules_source.rb \
        spec/services/dashboard/search/entities_source_spec.rb \
        spec/services/dashboard/search/modules_source_spec.rb
git commit -m "feat(dashboard): add entities and modules search sources"
```

---

## Task 6: Compose sources in SearchQuery (TDD)

**Files:**
- Create: `app/services/dashboard/search_query.rb`
- Create: `spec/services/dashboard/search_query_spec.rb`

- [ ] **Step 1: Write the SearchQuery spec**

Create `spec/services/dashboard/search_query_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SearchQuery do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }

  it "returns an empty array for a blank query" do
    expect(described_class.call(customer: customer, query: "", user: user)).to eq([])
  end

  it "returns an empty array for a single-character query" do
    expect(described_class.call(customer: customer, query: "a", user: user)).to eq([])
  end

  it "omits groups that have no results" do
    create(:page, customer: customer, name: "Checkout")
    groups = described_class.call(customer: customer, query: "Checkout", user: user)
    expect(groups.map { |g| g[:key] }).to eq([:pages])
  end

  it "returns pages, entities, and modules groups when all match" do
    create(:page, customer: customer, name: "alpha page")
    create(:entity, customer: customer, name: "alpha entity")
    fm = FeatureModule.find_or_create_by!(key: "alpha_mod") do |m|
      m.name = "Alpha Module"; m.status = :active; m.configuration_schema = {}.to_json
    end
    fm.update!(name: "Alpha Module")
    CustomerFeatureModule.find_or_create_by!(customer: customer, feature_module: fm) do |cfm|
      cfm.status = :active; cfm.configuration = {}.to_json; cfm.enabled_at = Time.current
    end

    groups = described_class.call(customer: customer, query: "alpha", user: user)
    expect(groups.map { |g| g[:key] }).to contain_exactly(:pages, :entities, :modules)
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/services/dashboard/search_query_spec.rb -fd`
Expected: FAIL with "uninitialized constant Dashboard::SearchQuery".

- [ ] **Step 3: Create SearchQuery**

Create `app/services/dashboard/search_query.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SearchQuery
    SOURCES = [
      Dashboard::Search::PagesSource,
      Dashboard::Search::EntitiesSource,
      Dashboard::Search::ModulesSource
    ].freeze

    def self.call(customer:, query:, user:)
      SOURCES
        .map { |src| src.new(customer: customer, query: query, user: user).to_group }
        .reject { |g| g[:items].empty? }
    end
  end
end
```

- [ ] **Step 4: Run the spec and confirm all pass**

Run: `bundle exec rspec spec/services/dashboard/search_query_spec.rb -fd`
Expected: all examples PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/search_query.rb spec/services/dashboard/search_query_spec.rb
git commit -m "feat(dashboard): add SearchQuery composing per-source searches"
```

---

## Task 7: Add the search JSON endpoint (TDD)

**Files:**
- Create: `app/controllers/dashboard/search_controller.rb`
- Create: `spec/requests/dashboard/search_spec.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the request spec**

Create `spec/requests/dashboard/search_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard search", type: :request do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }

  before { sign_in user }

  def do_search(q)
    get "/#{customer.id}/dashboard/search",
        params: { q: q },
        headers: { "Accept" => "application/json" }
  end

  it "returns JSON with a groups array" do
    create(:page, customer: customer, name: "Invoice Draft")
    do_search("invoice")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    body = JSON.parse(response.body)
    expect(body["query"]).to eq("invoice")
    expect(body["groups"].map { |g| g["key"] }).to include("pages")
  end

  it "returns empty groups for a short query" do
    create(:page, customer: customer, name: "Invoice Draft")
    do_search("i")
    body = JSON.parse(response.body)
    expect(body["groups"]).to eq([])
  end

  it "scopes results to the current customer" do
    other_customer = create(:customer)
    create(:page, customer: other_customer, name: "Invoice Draft")
    do_search("invoice")
    body = JSON.parse(response.body)
    expect(body["groups"]).to eq([])
  end

  it "requires authentication" do
    sign_out user
    do_search("anything")
    expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/requests/dashboard/search_spec.rb -fd`
Expected: FAIL with "No route matches".

- [ ] **Step 3: Add the route**

Edit `config/routes.rb` — inside the `namespace :dashboard do` block, add above the `scope :maintenance…`:

```ruby
      get "search", to: "search#index", as: :search
```

- [ ] **Step 4: Create the controller**

Create `app/controllers/dashboard/search_controller.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SearchController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def index
      q = params[:q].to_s.strip
      groups = Dashboard::SearchQuery.call(
        customer: current_customer, query: q, user: current_user
      )
      render json: { query: q, groups: groups }
    end

    private

    def current_dashboard_menu_item = nil
    helper_method :current_dashboard_menu_item
  end
end
```

- [ ] **Step 5: Run the spec and confirm all pass**

Run: `bundle exec rspec spec/requests/dashboard/search_spec.rb -fd`
Expected: all examples PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/dashboard/search_controller.rb \
        spec/requests/dashboard/search_spec.rb \
        config/routes.rb
git commit -m "feat(dashboard): add search JSON endpoint"
```

---

## Task 8: Rewrite the search palette component for live results

**Files:**
- Modify: `app/components/dashboard/search_palette_component.rb`
- Modify: `app/components/dashboard/search_palette_component.html.erb`
- Modify: `app/components/dashboard/shell_component.html.erb`
- Modify: `spec/components/dashboard/search_palette_component_spec.rb`

- [ ] **Step 1: Update the component spec for the new structure**

Replace `spec/components/dashboard/search_palette_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SearchPaletteComponent, type: :component do
  it "is hidden by default" do
    render_inline(described_class.new(customer_id: 12345678))
    expect(page).to have_css("[data-dashboard-search-target='panel'].hidden", visible: :all)
  end

  it "exposes the customer id as a data attribute on the root" do
    render_inline(described_class.new(customer_id: 12345678))
    expect(page).to have_css("[data-dashboard-search-customer-id-value='12345678']", visible: :all)
  end

  it "renders a search input with the expected target and placeholder" do
    render_inline(described_class.new(customer_id: 12345678))
    expect(page).to have_css(
      "input[data-dashboard-search-target='input'][placeholder*='Search']", visible: :all
    )
  end

  it "renders an empty-state region and a results region" do
    render_inline(described_class.new(customer_id: 12345678))
    expect(page).to have_css("[data-dashboard-search-target='empty']", visible: :all)
    expect(page).to have_css("[data-dashboard-search-target='results']", visible: :all)
  end

  it "no longer advertises 'coming soon'" do
    render_inline(described_class.new(customer_id: 12345678))
    expect(page).not_to have_text("coming soon")
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/components/dashboard/search_palette_component_spec.rb -fd`
Expected: FAIL (wrong arity / text still present).

- [ ] **Step 3: Update the component Ruby class**

Replace `app/components/dashboard/search_palette_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SearchPaletteComponent < ApplicationComponent
    def initialize(customer_id:)
      @customer_id = customer_id
    end

    attr_reader :customer_id
  end
end
```

- [ ] **Step 4: Rewrite the component template**

Replace `app/components/dashboard/search_palette_component.html.erb`:

```erb
<div class="hidden fixed inset-0 z-50"
     data-controller="dashboard-search"
     data-dashboard-search-target="panel"
     data-dashboard-search-customer-id-value="<%= customer_id %>"
     role="dialog"
     aria-modal="true"
     aria-labelledby="search-palette-title">
  <div class="absolute inset-0 bg-gray-900/40"
       data-action="click->dashboard-search#close"></div>

  <div class="relative mx-auto mt-24 max-w-xl bg-white rounded-lg shadow-xl border border-gray-200 overflow-hidden">
    <div class="flex items-center gap-2 px-4 h-12 border-b border-gray-200">
      <svg class="w-4 h-4 text-gray-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-4.35-4.35m1.5-5.4a6.9 6.9 0 11-13.8 0 6.9 6.9 0 0113.8 0z"/>
      </svg>
      <input type="text"
             placeholder="Search pages, entities, modules…"
             data-dashboard-search-target="input"
             data-action="input->dashboard-search#query keydown->dashboard-search#navigate"
             class="flex-1 bg-transparent border-0 outline-none text-sm text-gray-900 placeholder-gray-400 focus:ring-0"
             aria-label="Search" />
      <kbd class="px-1.5 py-0.5 text-[11px] font-medium rounded border border-gray-200 bg-gray-50 text-gray-500">Esc</kbd>
    </div>

    <div data-dashboard-search-target="empty"
         class="py-10 px-6 text-center text-sm text-gray-500"
         id="search-palette-title">
      Type at least two characters to search pages, entities, and modules.
    </div>
    <div data-dashboard-search-target="results"
         class="hidden max-h-80 overflow-y-auto py-2"></div>
  </div>
</div>
```

- [ ] **Step 5: Update the shell component to pass the customer id**

Edit `app/components/dashboard/shell_component.html.erb` — change the `SearchPaletteComponent.new` line to:

```erb
  <%= render Dashboard::SearchPaletteComponent.new(customer_id: customer.id) %>
```

- [ ] **Step 6: Run the component spec and confirm all pass**

Run: `bundle exec rspec spec/components/dashboard/search_palette_component_spec.rb spec/components/dashboard/shell_component_spec.rb -fd`
Expected: all examples PASS. If `shell_component_spec.rb` breaks because it renders without a customer, update the render call to supply a customer factory.

- [ ] **Step 7: Commit**

```bash
git add app/components/dashboard/search_palette_component.rb \
        app/components/dashboard/search_palette_component.html.erb \
        app/components/dashboard/shell_component.html.erb \
        spec/components/dashboard/search_palette_component_spec.rb
git commit -m "feat(dashboard): rewrite search palette for live results"
```

---

## Task 9: Wire the Stimulus controller to fetch results and navigate

**Files:**
- Modify: `app/javascript/controllers/dashboard_search_controller.js`

- [ ] **Step 1: Replace the Stimulus controller**

Replace `app/javascript/controllers/dashboard_search_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "results", "empty"]
  static values  = { customerId: String }

  connect() {
    this.debounceTimer = null
    this.activeIndex   = -1
    this.currentItems  = []

    this.boundKeydown = (event) => {
      const meta = event.metaKey || event.ctrlKey
      if (meta && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this.open()
      } else if (event.key === "Escape" && this.isOpen) {
        event.preventDefault()
        this.close()
      }
    }
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    clearTimeout(this.debounceTimer)
  }

  get isOpen() {
    return this.hasPanelTarget && !this.panelTarget.classList.contains("hidden")
  }

  open() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.remove("hidden")
    if (this.hasInputTarget) this.inputTarget.focus()
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
    if (this.hasInputTarget) this.inputTarget.value = ""
    this.renderResults([])
  }

  query() {
    clearTimeout(this.debounceTimer)
    const q = this.inputTarget.value.trim()
    this.debounceTimer = setTimeout(() => this.fetchResults(q), 200)
  }

  async fetchResults(q) {
    if (q.length < 2) {
      this.renderResults([])
      return
    }
    const url = `/${this.customerIdValue}/dashboard/search?q=${encodeURIComponent(q)}`
    try {
      const resp = await fetch(url, {
        credentials: "same-origin",
        headers: { "Accept": "application/json" }
      })
      if (!resp.ok) { this.renderResults([]); return }
      const body = await resp.json()
      this.renderResults(body.groups || [])
    } catch (_e) {
      this.renderResults([])
    }
  }

  renderResults(groups) {
    this.currentItems = []
    this.activeIndex  = -1
    this.resultsTarget.innerHTML = ""

    const hasGroups = groups.length > 0
    this.resultsTarget.classList.toggle("hidden", !hasGroups)
    if (this.hasEmptyTarget) {
      const q = this.inputTarget.value.trim()
      if (!hasGroups && q.length >= 2) {
        this.emptyTarget.textContent = `No results for "${q}"`
        this.emptyTarget.classList.remove("hidden")
      } else if (!hasGroups) {
        this.emptyTarget.textContent =
          "Type at least two characters to search pages, entities, and modules."
        this.emptyTarget.classList.remove("hidden")
      } else {
        this.emptyTarget.classList.add("hidden")
      }
    }

    groups.forEach((group) => {
      const heading = document.createElement("div")
      heading.className = "px-4 pt-3 pb-1 text-[11px] uppercase tracking-wide text-gray-500"
      heading.textContent = group.label
      this.resultsTarget.appendChild(heading)

      group.items.forEach((item) => {
        const link = document.createElement("a")
        link.href = item.path
        link.className =
          "flex items-center gap-3 px-4 py-2 text-sm text-gray-800 hover:bg-indigo-50 " +
          "focus:bg-indigo-50 focus:outline-none"
        const label = document.createElement("span")
        label.textContent = item.label
        link.appendChild(label)
        this.resultsTarget.appendChild(link)
        this.currentItems.push(link)
      })
    })
  }

  navigate(event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp" && event.key !== "Enter") return
    if (this.currentItems.length === 0) return

    if (event.key === "Enter") {
      event.preventDefault()
      const target = this.activeIndex >= 0
        ? this.currentItems[this.activeIndex]
        : this.currentItems[0]
      if (target) target.click()
      return
    }

    event.preventDefault()
    const delta = event.key === "ArrowDown" ? 1 : -1
    this.activeIndex =
      (this.activeIndex + delta + this.currentItems.length) % this.currentItems.length
    this.currentItems.forEach((el, i) => {
      el.classList.toggle("bg-indigo-50", i === this.activeIndex)
    })
    this.currentItems[this.activeIndex].focus()
  }
}
```

- [ ] **Step 2: Verify no test regressions on the component and system layer**

Run: `bundle exec rspec spec/components/dashboard -fd`
Expected: all examples PASS.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/dashboard_search_controller.js
git commit -m "feat(dashboard): live search palette — fetch, render, keyboard nav"
```

---

## Task 10: Update the search palette system spec

**Files:**
- Modify: `spec/system/dashboard/search_palette_spec.rb`

- [ ] **Step 1: Replace the system spec**

Replace `spec/system/dashboard/search_palette_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard search palette", type: :system, js: true do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, customer: customer, role: :admin) }

  before do
    skip "headless Chrome not available in this environment" unless system("which google-chrome > /dev/null 2>&1 || which chromium > /dev/null 2>&1")
    sign_in admin
  end

  it "opens, shows live results for a matching query, and navigates on click" do
    create(:page, customer: customer, name: "Checkout Form")
    visit "/#{customer.id}/"
    find("button[aria-label='Open search']", match: :first).click
    expect(page).to have_no_css("[data-dashboard-search-target='panel'].hidden")

    find("[data-dashboard-search-target='input']").set("checkout")
    expect(page).to have_text("Pages")
    expect(page).to have_link("Checkout Form")

    click_link "Checkout Form"
    expect(page).to have_current_path("/#{customer.id}/dashboard/pages", ignore_query: true)
  end

  it "closes the palette on Escape" do
    visit "/#{customer.id}/"
    find("button[aria-label='Open search']", match: :first).click
    expect(page).to have_no_css("[data-dashboard-search-target='panel'].hidden")
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).to have_css("[data-dashboard-search-target='panel'].hidden", visible: :all)
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add spec/system/dashboard/search_palette_spec.rb
git commit -m "test(dashboard): update search palette system spec for live results"
```

---

## Task 11: Topbar and menu bar visual refresh (Tailwind-only)

**Files:**
- Modify: `app/components/dashboard/topbar_component.html.erb`
- Modify: `app/components/dashboard/search_button_component.html.erb`
- Modify: `app/components/dashboard/menu_bar_component.rb`

- [ ] **Step 1: Restyle the topbar container, brand, and icon buttons**

Replace `app/components/dashboard/topbar_component.html.erb`:

```erb
<header class="bg-white shadow-[0_1px_0_0_rgb(0_0_0/0.04)]">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 grid grid-cols-[auto_1fr_auto] items-center gap-4">
    <div class="flex items-center gap-3">
      <button type="button"
              class="md:hidden h-9 w-9 inline-flex items-center justify-center text-gray-700 rounded-full hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
              data-action="click->dashboard-drawer#open"
              aria-label="Open menu">
        <svg class="w-[18px] h-[18px]" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16"/>
        </svg>
      </button>
      <%= link_to "/#{customer.id}/", class: "inline-flex items-center gap-2.5 text-gray-900 font-semibold tracking-tight" do %>
        <svg class="w-7 h-7 text-indigo-600" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2 2 7v10l10 5 10-5V7L12 2Z" opacity=".2"/>
          <path d="m12 4.2 8 4v7.6l-8 4-8-4V8.2l8-4Z"/>
        </svg>
        <span class="text-sm">Milestone</span>
      <% end %>
    </div>

    <div class="hidden md:flex justify-center">
      <div class="w-full max-w-lg">
        <%= render Dashboard::SearchButtonComponent.new %>
      </div>
    </div>

    <div class="flex items-center gap-1 justify-end">
      <div class="md:hidden">
        <%= render Dashboard::SearchButtonComponent.new %>
      </div>
      <%= render Dashboard::HelpMenuComponent.new %>
      <%= render Dashboard::NotificationsButtonComponent.new %>
      <%= render Dashboard::UserMenuComponent.new(user: user, customer: customer) if user %>
    </div>
  </div>
</header>
```

- [ ] **Step 2: Restyle the Search button to look like an input pill**

Replace `app/components/dashboard/search_button_component.html.erb`:

```erb
<button type="button"
        aria-label="Open search"
        class="inline-flex items-center gap-2 h-9 w-full md:min-w-[360px] max-w-lg px-3 rounded-md bg-white ring-1 ring-gray-200 shadow-sm hover:ring-gray-300 hover:shadow text-sm text-gray-500 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2 transition"
        data-action="click->dashboard-search#open">
  <svg class="w-[18px] h-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M21 21l-4.35-4.35m1.5-5.4a6.9 6.9 0 11-13.8 0 6.9 6.9 0 0113.8 0z"/>
  </svg>
  <span class="hidden md:inline">Search</span>
  <span class="hidden lg:inline-flex items-center gap-1 ml-auto">
    <kbd class="px-1.5 py-0.5 text-[11px] font-medium rounded border border-gray-200 bg-gray-50 text-gray-500 shadow-sm">⌘K</kbd>
  </span>
</button>
```

- [ ] **Step 3: Update the menu bar classes for the shadow band and refined active state**

Edit `app/components/dashboard/menu_bar_component.html.erb` — change only the `<nav>` opening tag:

```erb
<nav class="hidden md:block bg-gray-50 shadow-[0_1px_0_0_rgb(0_0_0/0.04)]"
     aria-label="Dashboard menu"
     data-controller="dashboard-menu-bar">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center gap-1 py-2">
```

Edit `app/components/dashboard/menu_bar_component.rb` — update `classes_for` so the active pill has subtle ring + shadow, and the inactive hover softens:

```ruby
    def classes_for(item)
      base = "inline-flex items-center h-11 px-4 text-sm font-medium rounded-md transition-colors " \
             "focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      if item.key == current_menu_item
        "#{base} bg-white text-gray-900 ring-1 ring-gray-200 shadow-sm"
      else
        "#{base} text-gray-600 hover:text-gray-900 hover:bg-gray-100/70"
      end
    end
```

- [ ] **Step 4: Run topbar / menu bar specs for regressions**

Run: `bundle exec rspec spec/components/dashboard/topbar_component_spec.rb spec/components/dashboard/menu_bar_component_spec.rb spec/components/dashboard/search_button_component_spec.rb -fd`
Expected: all examples PASS. (The existing topbar spec asserts links and data attributes, all of which are preserved.)

- [ ] **Step 5: Boot the server and spot-check the header**

Run: `bin/rails server -p 3000` (background) and open the dashboard in a browser. Confirm:
- Topbar and menu bar read as one band with a soft shadow instead of a hard line.
- Search button looks like a white input pill with an inset shadow kbd.
- Icon buttons (help, bell, avatar trigger) have consistent size and hover background.

- [ ] **Step 6: Commit**

```bash
git add app/components/dashboard/topbar_component.html.erb \
        app/components/dashboard/search_button_component.html.erb \
        app/components/dashboard/menu_bar_component.rb \
        app/components/dashboard/menu_bar_component.html.erb
git commit -m "style(dashboard): refresh topbar + menu bar — softer band, polished search pill"
```

---

## Task 12: Full suite verification

**Files:** none (run-only)

- [ ] **Step 1: Run the full dashboard test surface**

Run:
```
bundle exec rspec \
  spec/services/dashboard \
  spec/components/dashboard \
  spec/controllers/dashboard \
  spec/requests/dashboard \
  spec/routing/dashboard_routes_spec.rb \
  -fd
```
Expected: all examples PASS.

- [ ] **Step 2: Run the full suite as a final check**

Run: `bundle exec rspec`
Expected: suite green. If a spec elsewhere referenced `/dashboard/settings/customer` or `/dashboard/settings/users` (unlikely — only the files fixed earlier match), fix it and re-commit.

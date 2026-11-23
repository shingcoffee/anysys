# Dashboard Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a customer-scoped dashboard framework (4 sections: Entity Entries, Pages, Modules, Settings) with a landing page, contributor-pattern sidebar, per-item permission hook, module-agnostic integration, and full responsive shell — cutting over every customer-scoped controller from the current `application.html.erb` header to a new `dashboard.html.erb` layout.

**Architecture:** Contributor pattern (`Dashboard::SidebarBuilder` iterates `EntityEntriesContributor`, `PagesContributor`, `ModulesContributor`, `SettingsContributor`). Modules integrate generically through `Registration.sidebar_contributions(controller)` and `Registration.entries_for(entry_key:, params:)`. ViewComponent atoms live under `app/components/dashboard/`. Layout chooses `dashboard` vs `application` via `ApplicationController#dashboard_layout` based on whether the controller is platform-owner-only.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, Tailwind CSS, StimulusJS, RSpec, FactoryBot, Capybara.

**Spec:** `docs/superpowers/specs/2026-04-27-dashboard-framework-design.md`

---

## File Structure

New files (grouped by responsibility):

```
app/services/dashboard/
  ├── sidebar_node.rb                    # Value struct
  ├── sidebar_tree.rb                    # Per-section node collection
  ├── sidebar_contributor.rb             # Abstract base + registry
  ├── entity_entries_contributor.rb      # Section 1 tree builder
  ├── pages_contributor.rb               # Section 2 tree builder
  ├── modules_contributor.rb             # Section 3 tree builder
  ├── settings_contributor.rb            # Section 4 tree builder
  ├── entity_association_graph.rb        # Primary / children resolver (D1)
  ├── permission_filter.rb               # Drops nodes that fail permitted_by
  ├── sidebar_builder.rb                 # Orchestrator
  ├── dashboard_context.rb               # Per-request context struct
  ├── landing_stats.rb                   # Counts for the landing page
  ├── activity_feed.rb                   # Recent events (derived)
  ├── module_entries_resolver.rb         # Pagination/sort/search for entries
  └── module_contribution.rb             # Value object modules return

app/components/dashboard/
  ├── shell_component.{rb,html.erb}
  ├── topbar_component.{rb,html.erb}
  ├── user_menu_component.{rb,html.erb}
  ├── section_tabs_component.{rb,html.erb}
  ├── sidebar_component.{rb,html.erb}
  ├── sidebar_node_component.{rb,html.erb}
  ├── drawer_component.{rb,html.erb}
  ├── entries_table_component.{rb,html.erb}
  ├── landing_header_component.{rb,html.erb}
  ├── landing_stats_card_component.{rb,html.erb}
  ├── activity_feed_component.{rb,html.erb}
  ├── quick_action_card_component.{rb,html.erb}
  └── breadcrumbs_component.{rb,html.erb}

app/controllers/dashboard/
  ├── landing_controller.rb
  ├── entity_entries_controller.rb
  ├── module_entries_controller.rb
  └── settings_controller.rb

app/views/layouts/dashboard.html.erb
app/views/dashboard/{landing,entity_entries,module_entries,settings}/*.html.erb
app/javascript/controllers/dashboard_drawer_controller.js
app/javascript/controllers/dashboard_user_menu_controller.js
app/javascript/controllers/dashboard_section_tabs_controller.js  # mobile dropdown
```

Modified files:

```
app/controllers/application_controller.rb          # dashboard_layout resolver
app/controllers/concerns/tenant_context.rb          # (no change — read only)
app/services/feature_modules/base_module.rb         # replace nav_items_for with sidebar_contributions + entries_for
app/services/feature_modules/payment/registration.rb # migrate contribution
app/services/feature_modules/nav_item.rb            # DELETE (value object replaced by ModuleContribution + SidebarNode)
app/components/feature_modules/nav_contributions_component.{rb,html.erb} # DELETE (absorbed by ModulesContributor)
app/views/layouts/application.html.erb              # strip customer nav; keep owner-only items
config/routes.rb                                    # add dashboard routes
```

Existing customer-scoped controllers (`PagesController`, `EntitiesController`, `EntityEntriesController`, `FeatureModulesController`, `CustomersController`, `Authentication::Admin::UsersController`, etc.) need **no code change** — the `dashboard_layout` resolver on `ApplicationController` chooses the right layout based on the controller class. Platform-owner controllers (`FlowchartsController`, `Admin::CodeGeneratorsController`) are explicitly listed on an allowlist to keep the old layout.

---

## Task Index

| # | Task | TDD? |
|---|------|------|
| 1 | Dashboard service skeleton: context, node, tree | Y |
| 2 | Permission filter | Y |
| 3 | Entity association graph (primary/children) | Y |
| 4 | SidebarContributor base + registry | Y |
| 5 | EntityEntriesContributor | Y |
| 6 | PagesContributor | Y |
| 7 | ModuleContribution value object + BaseModule API change | Y |
| 8 | ModulesContributor | Y |
| 9 | SettingsContributor | Y |
| 10 | SidebarBuilder orchestrator | Y |
| 11 | LandingStats | Y |
| 12 | ActivityFeed | Y |
| 13 | ModuleEntriesResolver (pagination/sort/search) | Y |
| 14 | Migrate Payment module to new API (remove NavItem/nav_items_for) | Y |
| 15 | Atoms: SidebarNodeComponent, SidebarComponent | Y |
| 16 | UserMenuComponent + SectionTabsComponent + TopbarComponent | Y |
| 17 | DrawerComponent + Stimulus drawer controller | Y |
| 18 | ShellComponent | Y |
| 19 | LandingHeader / LandingStatsCard / ActivityFeed / QuickActionCard components | Y |
| 20 | EntriesTableComponent | Y |
| 21 | BreadcrumbsComponent | Y |
| 22 | `ApplicationController#dashboard_layout` + allowlist | Y |
| 23 | Dashboard layout (`dashboard.html.erb`) | — |
| 24 | Routes (dashboard namespace + root) | Y (request specs) |
| 25 | `Dashboard::LandingController` + view | Y |
| 26 | `Dashboard::EntityEntriesController` + views | Y |
| 27 | `Dashboard::ModuleEntriesController` + view | Y |
| 28 | `Dashboard::SettingsController` + views (modules / customer / users) | Y |
| 29 | Strip customer nav from `application.html.erb` (leave owner-only) | — |
| 30 | Delete `FeatureModules::NavContributionsComponent` + `NavItem` | — |
| 31 | Frontend-design polish pass | — |
| 32 | Full-suite verification + commit | — |

---

## Task 1: Dashboard context, sidebar node, sidebar tree

**Files:**
- Create: `app/services/dashboard/dashboard_context.rb`
- Create: `app/services/dashboard/sidebar_node.rb`
- Create: `app/services/dashboard/sidebar_tree.rb`
- Test: `spec/services/dashboard/dashboard_context_spec.rb`
- Test: `spec/services/dashboard/sidebar_node_spec.rb`
- Test: `spec/services/dashboard/sidebar_tree_spec.rb`

- [ ] **Step 1: Write failing spec — `DashboardContext`**

```ruby
# spec/services/dashboard/dashboard_context_spec.rb
require "rails_helper"

RSpec.describe Dashboard::DashboardContext do
  it "exposes keyword-init fields" do
    ctx = described_class.new(
      current_user: :user, current_customer: :cust,
      current_section: :entity_entries, request_path: "/x"
    )
    expect(ctx.current_user).to eq(:user)
    expect(ctx.current_customer).to eq(:cust)
    expect(ctx.current_section).to eq(:entity_entries)
    expect(ctx.request_path).to eq("/x")
  end

  it "raises on missing keyword" do
    expect { described_class.new(current_user: :u) }.to raise_error(ArgumentError)
  end
end
```

- [ ] **Step 2: Run — expect NameError**

Run: `bundle exec rspec spec/services/dashboard/dashboard_context_spec.rb`
Expected: FAIL, `uninitialized constant Dashboard::DashboardContext`.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/dashboard_context.rb
# frozen_string_literal: true

module Dashboard
  DashboardContext = Struct.new(
    :current_user, :current_customer, :current_section, :request_path,
    keyword_init: true
  ) do
    def customer_id = current_customer&.id
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bundle exec rspec spec/services/dashboard/dashboard_context_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing spec — `SidebarNode`**

```ruby
# spec/services/dashboard/sidebar_node_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SidebarNode do
  let(:leaf) { described_class.new(key: "k", label: "L", path: "/p", section: :modules) }

  it "defaults children to []" do
    expect(described_class.new(key: "k", label: "L", section: :pages).children).to eq([])
  end

  it "is linkable when path is present" do
    expect(leaf.link?).to eq(true)
    expect(described_class.new(key: "k", label: "L", section: :pages).link?).to eq(false)
  end

  it "evaluates permitted_by proc against user" do
    proc_node = described_class.new(
      key: "k", label: "L", section: :settings,
      permitted_by: ->(u) { u == :admin }
    )
    expect(proc_node.permitted_for?(:admin)).to eq(true)
    expect(proc_node.permitted_for?(:member)).to eq(false)
  end

  it "evaluates permitted_by symbol via user predicate" do
    user = double(admin?: true, member?: false)
    admin_node = described_class.new(key: "k", label: "L", section: :settings, permitted_by: :admin?)
    member_node = described_class.new(key: "k", label: "L", section: :settings, permitted_by: :member?)
    expect(admin_node.permitted_for?(user)).to eq(true)
    expect(member_node.permitted_for?(user)).to eq(false)
  end

  it "returns true when permitted_by is nil" do
    expect(described_class.new(key: "k", label: "L", section: :pages).permitted_for?(:anyone)).to eq(true)
  end

  it "returns false when user does not respond to the symbol" do
    user = Object.new
    node = described_class.new(key: "k", label: "L", section: :pages, permitted_by: :nope?)
    expect(node.permitted_for?(user)).to eq(false)
  end
end
```

- [ ] **Step 6: Run — expect FAIL**

Run: `bundle exec rspec spec/services/dashboard/sidebar_node_spec.rb`
Expected: FAIL.

- [ ] **Step 7: Implement `SidebarNode`**

```ruby
# app/services/dashboard/sidebar_node.rb
# frozen_string_literal: true

module Dashboard
  class SidebarNode
    SECTIONS = %i[entity_entries pages modules settings].freeze

    attr_reader :key, :label, :path, :icon, :badge, :section, :children, :permitted_by, :section_root

    def initialize(key:, label:, section:, path: nil, icon: nil, badge: nil,
                   children: [], permitted_by: nil, section_root: false)
      raise ArgumentError, "section must be one of #{SECTIONS}" unless SECTIONS.include?(section)
      @key = key
      @label = label
      @section = section
      @path = path
      @icon = icon
      @badge = badge
      @children = children
      @permitted_by = permitted_by
      @section_root = section_root
    end

    def link?
      !path.nil? && !path.empty?
    end

    def permitted_for?(user)
      case permitted_by
      when nil    then true
      when Proc   then permitted_by.call(user)
      when Symbol then user.respond_to?(permitted_by) && user.public_send(permitted_by)
      else false
      end
    end

    def with_children(new_children)
      SidebarNode.new(
        key: key, label: label, section: section, path: path, icon: icon, badge: badge,
        children: new_children, permitted_by: permitted_by, section_root: section_root
      )
    end
  end
end
```

- [ ] **Step 8: Run — expect PASS**

Run: `bundle exec rspec spec/services/dashboard/sidebar_node_spec.rb`
Expected: PASS.

- [ ] **Step 9: Write failing spec — `SidebarTree`**

```ruby
# spec/services/dashboard/sidebar_tree_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SidebarTree do
  let(:tree) { described_class.new }
  let(:node) { Dashboard::SidebarNode.new(key: "k", label: "L", section: :pages) }

  it "stores nodes per section" do
    tree.add(node)
    expect(tree.nodes_for(:pages)).to eq([node])
    expect(tree.nodes_for(:modules)).to eq([])
  end

  it "preserves insertion order" do
    n1 = Dashboard::SidebarNode.new(key: "a", label: "A", section: :pages)
    n2 = Dashboard::SidebarNode.new(key: "b", label: "B", section: :pages)
    tree.add(n1)
    tree.add(n2)
    expect(tree.nodes_for(:pages).map(&:key)).to eq(%w[a b])
  end

  it "exposes all sections" do
    tree.add(node)
    expect(tree.all.keys).to include(:pages)
  end
end
```

- [ ] **Step 10: Run — expect FAIL**

Run: `bundle exec rspec spec/services/dashboard/sidebar_tree_spec.rb`
Expected: FAIL.

- [ ] **Step 11: Implement `SidebarTree`**

```ruby
# app/services/dashboard/sidebar_tree.rb
# frozen_string_literal: true

module Dashboard
  class SidebarTree
    def initialize
      @sections = SidebarNode::SECTIONS.each_with_object({}) { |s, h| h[s] = [] }
    end

    def add(node)
      @sections[node.section] << node
      self
    end

    def nodes_for(section)
      @sections.fetch(section, [])
    end

    def all
      @sections
    end

    def replace(section, nodes)
      @sections[section] = nodes
      self
    end
  end
end
```

- [ ] **Step 12: Run — expect PASS**

Run: `bundle exec rspec spec/services/dashboard/sidebar_tree_spec.rb`
Expected: PASS.

- [ ] **Step 13: Commit**

```bash
git add app/services/dashboard spec/services/dashboard
git commit -m "Dashboard: context, sidebar node, sidebar tree"
```

---

## Task 2: PermissionFilter

**Files:**
- Create: `app/services/dashboard/permission_filter.rb`
- Test: `spec/services/dashboard/permission_filter_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/permission_filter_spec.rb
require "rails_helper"

RSpec.describe Dashboard::PermissionFilter do
  def node(key, permitted_by: nil, children: [])
    Dashboard::SidebarNode.new(
      key: key, label: key, section: :settings,
      permitted_by: permitted_by, children: children
    )
  end

  let(:user)        { double(admin?: true,  owner?: false) }
  let(:member_user) { double(admin?: false, owner?: false) }

  it "keeps nodes with nil permitted_by" do
    tree = Dashboard::SidebarTree.new.add(node("always"))
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).map(&:key)).to eq(%w[always])
  end

  it "drops nodes whose permitted_by returns false" do
    tree = Dashboard::SidebarTree.new
    tree.add(node("admin_only", permitted_by: :admin?))
    tree.add(node("member_only", permitted_by: :member?))
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).map(&:key)).to eq(%w[admin_only])
  end

  it "recursively drops hidden children" do
    parent = node("parent", children: [
      node("a", permitted_by: :admin?),
      node("b", permitted_by: ->(_u) { false })
    ])
    tree = Dashboard::SidebarTree.new.add(parent)
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).first.children.map(&:key)).to eq(%w[a])
  end

  it "suppresses a parent whose children are all hidden and which has no own path" do
    parent = node("ghost", children: [node("x", permitted_by: ->(_u) { false })])
    tree = Dashboard::SidebarTree.new.add(parent)
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings)).to be_empty
  end

  it "keeps a childless parent when its own permitted_by passes and it has a path" do
    leaf = Dashboard::SidebarNode.new(
      key: "x", label: "X", section: :settings, path: "/x", permitted_by: nil
    )
    tree = Dashboard::SidebarTree.new.add(leaf)
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).map(&:key)).to eq(%w[x])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/permission_filter_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/permission_filter.rb
# frozen_string_literal: true

module Dashboard
  class PermissionFilter
    def self.apply(tree, user)
      filtered = SidebarTree.new
      tree.all.each_key do |section|
        kept = tree.nodes_for(section).filter_map { |n| keep(n, user) }
        filtered.replace(section, kept)
      end
      filtered
    end

    def self.keep(node, user)
      return nil unless node.permitted_for?(user)

      visible_children = node.children.filter_map { |c| keep(c, user) }
      return node.with_children(visible_children) if node.link? || visible_children.any?

      nil
    end
    private_class_method :keep
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/permission_filter_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/permission_filter.rb spec/services/dashboard/permission_filter_spec.rb
git commit -m "Dashboard: PermissionFilter drops hidden nodes and ghost parents"
```

---

## Task 3: EntityAssociationGraph

**Files:**
- Create: `app/services/dashboard/entity_association_graph.rb`
- Test: `spec/services/dashboard/entity_association_graph_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/entity_association_graph_spec.rb
require "rails_helper"

RSpec.describe Dashboard::EntityAssociationGraph do
  let(:customer) { create(:customer) }

  def make_entity(name, associations: [], bridge: false)
    create(:entity,
      customer: customer,
      name: name,
      is_bridge_entity: bridge,
      associations: associations.to_json
    )
  end

  it "primaries = entities that are never targets" do
    customer_entity = make_entity("Customer")
    order          = make_entity("Order")
    customer_entity.update!(associations: [{ "target_entity_id" => order.id }].to_json)

    graph = described_class.build(customer.id)

    expect(graph.primaries.map(&:name)).to contain_exactly("Customer")
    expect(graph.children_of(customer_entity).map(&:name)).to eq(["Order"])
    expect(graph.children_of(order)).to eq([])
  end

  it "excludes bridge entities from primaries and children" do
    primary = make_entity("Post")
    tag     = make_entity("Tag")
    bridge  = make_entity("PostTag", bridge: true)
    primary.update!(associations: [
      { "target_entity_id" => tag.id, "bridge_entity_id" => bridge.id }
    ].to_json)

    graph = described_class.build(customer.id)
    expect(graph.primaries.map(&:name)).to contain_exactly("Post")
    expect(graph.all_entities.map(&:name)).not_to include("PostTag")
    expect(graph.children_of(primary).map(&:name)).to eq(["Tag"])
  end

  it "standalone entity (no associations, not targeted) is its own primary" do
    lone = make_entity("Audit")
    graph = described_class.build(customer.id)
    expect(graph.primaries.map(&:name)).to include("Audit")
    expect(graph.children_of(lone)).to eq([])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/entity_association_graph_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/entity_association_graph.rb
# frozen_string_literal: true

module Dashboard
  class EntityAssociationGraph
    def self.build(customer_id)
      entities = Entity.for_customer(customer_id).non_bridge.to_a
      by_id = entities.index_by(&:id)

      targeted_ids = entities.flat_map { |e|
        e.associations_list.map { |a| a["target_entity_id"].to_i }
      }.compact.to_set

      primaries = entities.reject { |e| targeted_ids.include?(e.id) }

      children_of = entities.each_with_object({}) { |e, h|
        h[e.id] = e.associations_list
                  .map { |a| by_id[a["target_entity_id"].to_i] }
                  .compact
      }

      new(primaries: primaries, children_of: children_of, entities: entities)
    end

    attr_reader :primaries, :entities

    def initialize(primaries:, children_of:, entities:)
      @primaries = primaries
      @children_of = children_of
      @entities = entities
    end

    def children_of(entity)
      @children_of.fetch(entity.id, [])
    end

    def all_entities
      @entities
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/entity_association_graph_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/entity_association_graph.rb spec/services/dashboard/entity_association_graph_spec.rb
git commit -m "Dashboard: EntityAssociationGraph (primary = non-targeted, bridge excluded)"
```

---

## Task 4: SidebarContributor base + registry

**Files:**
- Create: `app/services/dashboard/sidebar_contributor.rb`
- Test: `spec/services/dashboard/sidebar_contributor_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/sidebar_contributor_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SidebarContributor do
  it "requires #contribute to be implemented" do
    ctx = Dashboard::DashboardContext.new(
      current_user: nil, current_customer: nil,
      current_section: :pages, request_path: "/"
    )
    expect { described_class.new(ctx).contribute }.to raise_error(NotImplementedError)
  end

  it "defines a registry in deterministic order" do
    expect(described_class.registry).to eq([
      Dashboard::EntityEntriesContributor,
      Dashboard::PagesContributor,
      Dashboard::ModulesContributor,
      Dashboard::SettingsContributor
    ])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/sidebar_contributor_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/sidebar_contributor.rb
# frozen_string_literal: true

module Dashboard
  class SidebarContributor
    def initialize(context)
      @context = context
    end

    # @return [Array<Dashboard::SidebarNode>] top-level nodes for this contributor
    def contribute
      raise NotImplementedError, "#{self.class} must implement #contribute"
    end

    def self.registry
      [
        Dashboard::EntityEntriesContributor,
        Dashboard::PagesContributor,
        Dashboard::ModulesContributor,
        Dashboard::SettingsContributor
      ]
    end

    private

    attr_reader :context
    def customer    = context.current_customer
    def customer_id = context.customer_id
    def current_user = context.current_user
  end
end
```

Add empty placeholder classes so the registry resolves — implementations land in later tasks:

```ruby
# app/services/dashboard/entity_entries_contributor.rb
module Dashboard
  class EntityEntriesContributor < SidebarContributor
    def contribute = raise NotImplementedError
  end
end

# app/services/dashboard/pages_contributor.rb
module Dashboard
  class PagesContributor < SidebarContributor
    def contribute = raise NotImplementedError
  end
end

# app/services/dashboard/modules_contributor.rb
module Dashboard
  class ModulesContributor < SidebarContributor
    def contribute = raise NotImplementedError
  end
end

# app/services/dashboard/settings_contributor.rb
module Dashboard
  class SettingsContributor < SidebarContributor
    def contribute = raise NotImplementedError
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/sidebar_contributor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/sidebar_contributor.rb app/services/dashboard/{entity_entries,pages,modules,settings}_contributor.rb spec/services/dashboard/sidebar_contributor_spec.rb
git commit -m "Dashboard: SidebarContributor base + registry of 4 sections"
```

---

## Task 5: EntityEntriesContributor

**Files:**
- Modify: `app/services/dashboard/entity_entries_contributor.rb`
- Test: `spec/services/dashboard/entity_entries_contributor_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/entity_entries_contributor_spec.rb
require "rails_helper"

RSpec.describe Dashboard::EntityEntriesContributor do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :owner, customer: customer) }
  let(:ctx) do
    Dashboard::DashboardContext.new(
      current_user: user, current_customer: customer,
      current_section: :entity_entries, request_path: "/"
    )
  end

  def customer_path(entity) = "/#{customer.id}/dashboard/entity_entries/#{entity.id}"

  it "produces a primary node per primary entity with children nested" do
    primary = create(:entity, customer: customer, name: "Customer")
    child   = create(:entity, customer: customer, name: "Order")
    primary.update!(associations: [{ "target_entity_id" => child.id }].to_json)

    nodes = described_class.new(ctx).contribute
    keys = nodes.map(&:key)
    expect(keys).to eq(["entity_entries.customer"])

    parent = nodes.first
    expect(parent.label).to eq("Customer")
    expect(parent.path).to eq(customer_path(primary))
    expect(parent.children.map(&:label)).to eq(["Order"])
    expect(parent.children.first.path).to eq(customer_path(child))
  end

  it "skips bridge entities entirely" do
    primary = create(:entity, customer: customer, name: "Post")
    target  = create(:entity, customer: customer, name: "Tag")
    bridge  = create(:entity, customer: customer, name: "PostTag", is_bridge_entity: true)
    primary.update!(associations: [{
      "target_entity_id" => target.id, "bridge_entity_id" => bridge.id
    }].to_json)

    nodes = described_class.new(ctx).contribute
    all_labels = nodes.flat_map { |n| [n.label] + n.children.map(&:label) }
    expect(all_labels).not_to include("PostTag")
  end

  it "returns empty when customer has no entities" do
    expect(described_class.new(ctx).contribute).to eq([])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/entity_entries_contributor_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/entity_entries_contributor.rb
# frozen_string_literal: true

module Dashboard
  class EntityEntriesContributor < SidebarContributor
    SECTION = :entity_entries

    def contribute
      return [] if customer_id.blank?
      graph = EntityAssociationGraph.build(customer_id)
      graph.primaries.map { |primary| build_node(primary, graph) }
    end

    private

    def build_node(primary, graph)
      children = graph.children_of(primary).map { |child| build_node(child, graph) }
      SidebarNode.new(
        key: "entity_entries.#{primary.name_slug}",
        label: primary.name,
        section: SECTION,
        path: path_for(primary),
        children: children
      )
    end

    def path_for(entity)
      "/#{customer_id}/dashboard/entity_entries/#{entity.id}"
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/entity_entries_contributor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/entity_entries_contributor.rb spec/services/dashboard/entity_entries_contributor_spec.rb
git commit -m "Dashboard: EntityEntriesContributor builds primary-rooted tree"
```

---

## Task 6: PagesContributor

**Files:**
- Modify: `app/services/dashboard/pages_contributor.rb`
- Test: `spec/services/dashboard/pages_contributor_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/pages_contributor_spec.rb
require "rails_helper"

RSpec.describe Dashboard::PagesContributor do
  let(:customer) { create(:customer) }
  let(:ctx) do
    Dashboard::DashboardContext.new(
      current_user: nil, current_customer: customer,
      current_section: :pages, request_path: "/"
    )
  end

  it "groups pages under their primary entity with intermediate per-entity group" do
    primary = create(:entity, customer: customer, name: "Customer")
    child   = create(:entity, customer: customer, name: "Order")
    primary.update!(associations: [{ "target_entity_id" => child.id }].to_json)

    customer_page = create(:page, customer: customer, name: "Customer Intake", entity: primary)
    order_page    = create(:page, customer: customer, name: "Place Order",     entity: child)

    nodes = described_class.new(ctx).contribute
    expect(nodes.map(&:label)).to eq(["Customer"])

    primary_group = nodes.first
    per_entity = primary_group.children
    expect(per_entity.map(&:label)).to eq(["Customer", "Order"])

    customer_entity_group = per_entity.find { |n| n.label == "Customer" }
    expect(customer_entity_group.children.map(&:label)).to eq(["Customer Intake"])
    expect(customer_entity_group.children.first.path).to eq("/#{customer.id}/pages/#{customer_page.id}/edit")

    order_entity_group = per_entity.find { |n| n.label == "Order" }
    expect(order_entity_group.children.map(&:label)).to eq(["Place Order"])
    expect(order_entity_group.children.first.path).to eq("/#{customer.id}/pages/#{order_page.id}/edit")
  end

  it "returns empty when the customer has no primary entities" do
    expect(described_class.new(ctx).contribute).to eq([])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/pages_contributor_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/pages_contributor.rb
# frozen_string_literal: true

module Dashboard
  class PagesContributor < SidebarContributor
    SECTION = :pages

    def contribute
      return [] if customer_id.blank?
      graph = EntityAssociationGraph.build(customer_id)
      pages_by_entity_id = Page.for_customer(customer_id)
        .to_a
        .group_by { |p| p.entity&.id }

      graph.primaries.map { |primary| primary_group(primary, graph, pages_by_entity_id) }
    end

    private

    def primary_group(primary, graph, pages_by_entity_id)
      entities_in_group = [primary] + graph.children_of(primary)
      child_groups = entities_in_group.map { |e| entity_group(e, pages_by_entity_id) }
      SidebarNode.new(
        key: "pages.#{primary.name_slug}",
        label: primary.name,
        section: SECTION,
        children: child_groups
      )
    end

    def entity_group(entity, pages_by_entity_id)
      pages = pages_by_entity_id.fetch(entity.id, [])
      SidebarNode.new(
        key: "pages.#{entity.name_slug}.group",
        label: entity.name,
        section: SECTION,
        children: pages.map { |p| page_node(p) }
      )
    end

    def page_node(page)
      SidebarNode.new(
        key: "pages.#{page.id}",
        label: page.name,
        section: SECTION,
        path: "/#{customer_id}/pages/#{page.id}/edit",
        badge: page.published ? { label: "Live", color: "green" } : nil
      )
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/pages_contributor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/pages_contributor.rb spec/services/dashboard/pages_contributor_spec.rb
git commit -m "Dashboard: PagesContributor mirrors primary/associated hierarchy"
```

---

## Task 7: ModuleContribution + BaseModule API change

**Files:**
- Create: `app/services/dashboard/module_contribution.rb`
- Modify: `app/services/feature_modules/base_module.rb`
- Test: `spec/services/dashboard/module_contribution_spec.rb`
- Test: `spec/services/feature_modules/base_module_spec.rb` (augment existing if present, else create)

- [ ] **Step 1: Write failing spec — ModuleContribution**

```ruby
# spec/services/dashboard/module_contribution_spec.rb
require "rails_helper"

RSpec.describe Dashboard::ModuleContribution do
  it "converts to a SidebarNode in the given section" do
    contrib = described_class.new(
      label: "Transactions", entry_key: "transactions",
      icon: "M3 3h18", badge: { label: "3", color: "gray" },
      path: nil, permitted_by: nil
    )
    node = contrib.to_sidebar_node(section: :modules, module_key: "payment", customer_id: 42)
    expect(node.label).to eq("Transactions")
    expect(node.section).to eq(:modules)
    expect(node.key).to eq("modules.payment.transactions")
    expect(node.path).to eq("/42/dashboard/modules/payment/entries/transactions")
    expect(node.badge).to eq(label: "3", color: "gray")
  end

  it "uses explicit path when provided" do
    contrib = described_class.new(label: "L", entry_key: "k", path: "/custom")
    node = contrib.to_sidebar_node(section: :modules, module_key: "mod", customer_id: 1)
    expect(node.path).to eq("/custom")
  end

  it "propagates permitted_by onto the node" do
    guard = ->(u) { u.admin? }
    contrib = described_class.new(label: "L", entry_key: "k", permitted_by: guard)
    node = contrib.to_sidebar_node(section: :modules, module_key: "mod", customer_id: 1)
    expect(node.permitted_by).to eq(guard)
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/module_contribution_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement ModuleContribution**

```ruby
# app/services/dashboard/module_contribution.rb
# frozen_string_literal: true

module Dashboard
  class ModuleContribution
    attr_reader :label, :entry_key, :path, :icon, :badge, :permitted_by

    def initialize(label:, entry_key:, path: nil, icon: nil, badge: nil, permitted_by: nil)
      @label = label
      @entry_key = entry_key
      @path = path
      @icon = icon
      @badge = badge
      @permitted_by = permitted_by
    end

    def to_sidebar_node(section:, module_key:, customer_id:)
      SidebarNode.new(
        key: "#{section}.#{module_key}.#{entry_key}",
        label: label,
        section: section,
        path: path || default_path(section, module_key, customer_id),
        icon: icon,
        badge: badge,
        permitted_by: permitted_by
      )
    end

    private

    def default_path(section, module_key, customer_id)
      case section
      when :modules  then "/#{customer_id}/dashboard/modules/#{module_key}/entries/#{entry_key}"
      when :settings then "/#{customer_id}/dashboard/settings/modules/#{module_key}/#{entry_key}"
      end
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/module_contribution_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing spec — BaseModule API change**

```ruby
# spec/services/feature_modules/base_module_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::BaseModule do
  let(:klass) { Class.new(described_class) }

  it "returns a default empty contribution set" do
    expect(klass.sidebar_contributions(double("controller"))).to eq(entries: [], settings: [], metadata: {})
  end

  it "raises NotImplementedError for entries_for by default" do
    expect { klass.entries_for(entry_key: "x", params: {}) }
      .to raise_error(NotImplementedError)
  end

  it "no longer responds to nav_items_for" do
    expect(klass).not_to respond_to(:nav_items_for)
  end
end
```

- [ ] **Step 6: Run — FAIL**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: FAIL (nav_items_for still exists; new methods missing).

- [ ] **Step 7: Modify `FeatureModules::BaseModule`**

Remove `nav_items_for` class method and add the two new ones. The full edit:

```ruby
# app/services/feature_modules/base_module.rb — locate the class << self block

# DELETE:
def nav_items_for(controller, section:)
  []
end

# ADD in its place:
def sidebar_contributions(_controller)
  { entries: [], settings: [], metadata: {} }
end

def entries_for(entry_key:, params:)
  raise NotImplementedError, "#{name} must implement .entries_for(entry_key:, params:) to use Dashboard module entries"
end
```

Also update the `NullRegistration` module in `app/models/feature_module.rb`:

```ruby
# app/models/feature_module.rb
module NullRegistration
  def self.provision!(_customer)           = nil
  def self.deprovision!(_customer)         = nil
  def self.entry_path_for(_customer)       = nil
  def self.default_exit_config             = nil
  def self.sidebar_contributions(_ctrl)    = { entries: [], settings: [], metadata: {} }
  def self.entries_for(entry_key:, params:) = raise NotImplementedError

  def self.input_contract_class
    @input_contract_class ||= Class.new(Reform::Form)
  end

  def self.output_contract_class
    @output_contract_class ||= Class.new(Reform::Form)
  end
end
```

- [ ] **Step 8: Run — PASS**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/services/dashboard/module_contribution.rb app/services/feature_modules/base_module.rb app/models/feature_module.rb spec/services/dashboard/module_contribution_spec.rb spec/services/feature_modules/base_module_spec.rb
git commit -m "Dashboard: ModuleContribution + BaseModule.sidebar_contributions/entries_for"
```

---

## Task 8: ModulesContributor

**Files:**
- Modify: `app/services/dashboard/modules_contributor.rb`
- Test: `spec/services/dashboard/modules_contributor_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/modules_contributor_spec.rb
require "rails_helper"

RSpec.describe Dashboard::ModulesContributor do
  let(:customer)       { create(:customer) }
  let(:user)           { create(:user, :owner, customer: customer) }
  let(:ctx) do
    Dashboard::DashboardContext.new(
      current_user: user, current_customer: customer,
      current_section: :modules, request_path: "/"
    )
  end

  before do
    stub_const("FeatureModules::Demo", Module.new)
    stub_const("FeatureModules::Demo::Registration", Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo"
      def self.module_name = "Demo"
      def self.provision!(_c); end
      def self.sidebar_contributions(_c)
        {
          entries: [
            Dashboard::ModuleContribution.new(label: "Transactions", entry_key: "transactions"),
            Dashboard::ModuleContribution.new(label: "Refunds", entry_key: "refunds")
          ],
          settings: [],
          metadata: { order: 10 }
        }
      end
    end)

    fm = create(:feature_module, key: "demo", name: "Demo")
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)
  end

  it "returns a module header node with each entry as a child" do
    nodes = described_class.new(ctx).contribute
    expect(nodes.map(&:label)).to eq(["Demo"])
    children = nodes.first.children
    expect(children.map(&:label)).to eq(["Transactions", "Refunds"])
    expect(children.first.path).to eq("/#{customer.id}/dashboard/modules/demo/entries/transactions")
  end

  it "omits modules that contribute no entries" do
    allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(
      Class.new(FeatureModules::BaseModule) do
        def self.module_key = "silent"
        def self.sidebar_contributions(_c) = { entries: [], settings: [], metadata: {} }
      end
    )
    expect(described_class.new(ctx).contribute).to eq([])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/modules_contributor_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/modules_contributor.rb
# frozen_string_literal: true

module Dashboard
  class ModulesContributor < SidebarContributor
    SECTION = :modules

    def contribute
      return [] if customer_id.blank?

      FeatureModule.enabled_for_customer(customer_id).by_name.filter_map { |fm|
        contributions = fm.registration_class.sidebar_contributions(nil)
        entries = contributions[:entries].to_a
        next if entries.empty?

        children = entries.map { |c|
          c.to_sidebar_node(section: SECTION, module_key: fm.key, customer_id: customer_id)
        }
        SidebarNode.new(
          key: "modules.#{fm.key}",
          label: fm.name,
          section: SECTION,
          section_root: true,
          children: children
        )
      }
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/modules_contributor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/modules_contributor.rb spec/services/dashboard/modules_contributor_spec.rb
git commit -m "Dashboard: ModulesContributor wraps enabled-module entry contributions"
```

---

## Task 9: SettingsContributor

**Files:**
- Modify: `app/services/dashboard/settings_contributor.rb`
- Test: `spec/services/dashboard/settings_contributor_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/settings_contributor_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SettingsContributor do
  let(:customer) { create(:customer) }
  let(:owner)   { create(:user, :owner, customer: customer) }
  let(:ctx) do
    Dashboard::DashboardContext.new(
      current_user: owner, current_customer: customer,
      current_section: :settings, request_path: "/"
    )
  end

  it "always includes Customer Profile, Users, and an enabled-modules group" do
    stub_const("FeatureModules::Billing", Module.new)
    stub_const("FeatureModules::Billing::Registration", Class.new(FeatureModules::BaseModule) do
      def self.module_key = "billing"
      def self.module_name = "Billing"
      def self.sidebar_contributions(_c)
        { entries: [], settings: [Dashboard::ModuleContribution.new(label: "General", entry_key: "general")], metadata: {} }
      end
    end)
    fm = create(:feature_module, key: "billing", name: "Billing")
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)

    nodes = described_class.new(ctx).contribute
    expect(nodes.map(&:label)).to eq(["Customer Profile", "Users", "Modules"])
    modules_group = nodes.last
    expect(modules_group.children.map(&:label)).to eq(["Billing"])
    expect(modules_group.children.first.children.map(&:label)).to eq(["General"])
    expect(modules_group.children.first.children.first.path)
      .to eq("/#{customer.id}/dashboard/settings/modules/billing/general")
  end

  it "guards Users with :admin_or_owner? permission" do
    nodes = described_class.new(ctx).contribute
    users_node = nodes.find { |n| n.key == "settings.users" }
    expect(users_node.permitted_by).to eq(:admin_or_owner?)
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/settings_contributor_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/settings_contributor.rb
# frozen_string_literal: true

module Dashboard
  class SettingsContributor < SidebarContributor
    SECTION = :settings

    def contribute
      return [] if customer_id.blank?

      [
        customer_profile_node,
        users_node,
        modules_group_node
      ].compact
    end

    private

    def customer_profile_node
      SidebarNode.new(
        key: "settings.customer_profile",
        label: "Customer Profile",
        section: SECTION,
        path: "/#{customer_id}/dashboard/settings/customer"
      )
    end

    def users_node
      SidebarNode.new(
        key: "settings.users",
        label: "Users",
        section: SECTION,
        path: "/#{customer_id}/dashboard/settings/users",
        permitted_by: :admin_or_owner?
      )
    end

    def modules_group_node
      children = FeatureModule.enabled_for_customer(customer_id).by_name.filter_map { |fm|
        contributions = fm.registration_class.sidebar_contributions(nil)
        settings = contributions[:settings].to_a
        SidebarNode.new(
          key: "settings.modules.#{fm.key}",
          label: fm.name,
          section: SECTION,
          path: settings.empty? ? "/#{customer_id}/dashboard/settings/modules/#{fm.key}" : nil,
          children: settings.map { |c|
            c.to_sidebar_node(section: SECTION, module_key: fm.key, customer_id: customer_id)
          }
        )
      }

      return nil if children.empty?
      SidebarNode.new(key: "settings.modules", label: "Modules", section: SECTION, children: children)
    end
  end
end
```

- [ ] **Step 4: Add `admin_or_owner?` predicate on `Authentication::User`**

Add to `app/models/authentication/user.rb` (near other display helpers):

```ruby
def admin_or_owner?
  admin? || owner?
end
```

- [ ] **Step 5: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/settings_contributor_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/dashboard/settings_contributor.rb app/models/authentication/user.rb spec/services/dashboard/settings_contributor_spec.rb
git commit -m "Dashboard: SettingsContributor (profile, users, enabled-modules group)"
```

---

## Task 10: SidebarBuilder orchestrator

**Files:**
- Create: `app/services/dashboard/sidebar_builder.rb`
- Test: `spec/services/dashboard/sidebar_builder_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/sidebar_builder_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SidebarBuilder do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :owner, customer: customer) }
  let(:ctx) do
    Dashboard::DashboardContext.new(
      current_user: user, current_customer: customer,
      current_section: :entity_entries, request_path: "/"
    )
  end

  it "walks the registry and merges results into a tree" do
    entity = create(:entity, customer: customer, name: "Customer")

    tree = described_class.build(ctx)
    expect(tree).to be_a(Dashboard::SidebarTree)
    expect(tree.nodes_for(:entity_entries).map(&:label)).to eq(["Customer"])
    expect(tree.nodes_for(:settings).map(&:label)).to include("Customer Profile")
  end

  it "applies the permission filter" do
    member = create(:user, customer: customer, role: :member)
    member_ctx = Dashboard::DashboardContext.new(
      current_user: member, current_customer: customer,
      current_section: :settings, request_path: "/"
    )
    tree = described_class.build(member_ctx)
    expect(tree.nodes_for(:settings).map(&:label)).not_to include("Users")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/sidebar_builder_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/sidebar_builder.rb
# frozen_string_literal: true

module Dashboard
  class SidebarBuilder
    def self.build(context)
      tree = SidebarTree.new
      SidebarContributor.registry.each do |contributor_class|
        contributor_class.new(context).contribute.each { |node| tree.add(node) }
      end
      PermissionFilter.apply(tree, context.current_user)
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/sidebar_builder_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/sidebar_builder.rb spec/services/dashboard/sidebar_builder_spec.rb
git commit -m "Dashboard: SidebarBuilder orchestrator"
```

---

## Task 11: LandingStats

**Files:**
- Create: `app/services/dashboard/landing_stats.rb`
- Test: `spec/services/dashboard/landing_stats_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/landing_stats_spec.rb
require "rails_helper"

RSpec.describe Dashboard::LandingStats do
  let(:customer) { create(:customer) }
  let(:other)    { create(:customer) }

  it "counts customer-scoped resources only" do
    create(:entity, customer: customer, name: "A")
    create(:entity, customer: customer, name: "B_bridge", is_bridge_entity: true)
    create(:entity, customer: other, name: "Other")

    e = create(:entity, customer: customer, name: "EP")
    create(:page, customer: customer, entity: e, published: true)
    create(:page, customer: customer, entity: e, published: false)

    create(:flowchart, customer: customer)

    fm = create(:feature_module, key: "m1")
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)

    create(:user, customer: customer)
    create(:user, :inactive, customer: customer)

    stats = described_class.for(customer).to_h
    expect(stats[:entities]).to eq(2)                 # non-bridge only
    expect(stats[:pages]).to eq(total: 2, published: 1, draft: 1)
    expect(stats[:flowcharts]).to eq(1)
    expect(stats[:modules_enabled]).to eq(1)
    expect(stats[:users]).to eq(1)                    # active only
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/landing_stats_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/landing_stats.rb
# frozen_string_literal: true

module Dashboard
  class LandingStats
    def self.for(customer) = new(customer)

    def initialize(customer)
      @customer = customer
    end

    def to_h
      {
        entities: Entity.for_customer(cid).non_bridge.count,
        pages: page_counts,
        flowcharts: Flowchart.for_customer(cid).count,
        modules_enabled: CustomerFeatureModule.where(customer_id: cid, status: :active).count,
        users: Authentication::User.where(customer_id: cid, status: :active).count
      }
    end

    private

    def page_counts
      total = Page.for_customer(cid).count
      published = Page.for_customer(cid).where(published: true).count
      { total: total, published: published, draft: total - published }
    end

    def cid = @customer.id
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/landing_stats_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/landing_stats.rb spec/services/dashboard/landing_stats_spec.rb
git commit -m "Dashboard: LandingStats (entities/pages/flowcharts/modules/users counts)"
```

---

## Task 12: ActivityFeed

**Files:**
- Create: `app/services/dashboard/activity_feed.rb`
- Test: `spec/services/dashboard/activity_feed_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/activity_feed_spec.rb
require "rails_helper"

RSpec.describe Dashboard::ActivityFeed do
  let(:customer) { create(:customer) }
  let(:other)    { create(:customer) }

  it "returns events sorted newest first, scoped to customer" do
    entity = create(:entity, customer: customer)
    page = create(:page, customer: customer, entity: entity, name: "P")
    page.update!(updated_at: 1.hour.ago)
    flowchart = create(:flowchart, customer: customer, name: "F")
    flowchart.update!(updated_at: 30.minutes.ago)
    entry = create(:entity_entry, customer: customer, entity: entity)
    entry.update!(created_at: 15.minutes.ago)

    # out-of-scope noise
    create(:page, customer: other, entity: create(:entity, customer: other))

    events = described_class.recent(customer, limit: 5)
    expect(events.size).to be_between(3, 5)
    expect(events.first.occurred_at).to be >= events.last.occurred_at
    kinds = events.map(&:kind)
    expect(kinds).to include(:page_edited, :flowchart_edited, :entry_created)
  end

  it "returns [] when no activity exists" do
    expect(described_class.recent(customer)).to eq([])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/activity_feed_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/activity_feed.rb
# frozen_string_literal: true

module Dashboard
  class ActivityFeed
    Event = Struct.new(:kind, :label, :path, :occurred_at, keyword_init: true)

    def self.recent(customer, limit: 15)
      cid = customer.id
      events = []

      Page.for_customer(cid).order(updated_at: :desc).limit(limit).each do |p|
        events << Event.new(kind: :page_edited, label: p.name,
                            path: "/#{cid}/pages/#{p.id}/edit", occurred_at: p.updated_at)
      end

      Flowchart.for_customer(cid).order(updated_at: :desc).limit(limit).each do |f|
        events << Event.new(kind: :flowchart_edited, label: f.name,
                            path: "/#{cid}/flowcharts/#{f.id}/edit", occurred_at: f.updated_at)
      end

      EntityEntry.where(customer_id: cid).order(created_at: :desc).limit(limit).each do |e|
        events << Event.new(kind: :entry_created, label: "#{e.entity&.name} entry created",
                            path: "/#{cid}/entities/#{e.entity_id}/entries", occurred_at: e.created_at)
      end

      FeatureModuleLog.where(customer_id: cid).order(created_at: :desc).limit(limit).each do |l|
        events << Event.new(kind: :module_event, label: l.action,
                            path: nil, occurred_at: l.created_at)
      end

      events.sort_by { |ev| -ev.occurred_at.to_i }.first(limit)
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/activity_feed_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/activity_feed.rb spec/services/dashboard/activity_feed_spec.rb
git commit -m "Dashboard: ActivityFeed derives recent events from existing timestamps"
```

---

## Task 13: ModuleEntriesResolver (pagination/sort/search)

**Files:**
- Create: `app/services/dashboard/module_entries_resolver.rb`
- Test: `spec/services/dashboard/module_entries_resolver_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/dashboard/module_entries_resolver_spec.rb
require "rails_helper"

RSpec.describe Dashboard::ModuleEntriesResolver do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer, name: "E") }

  before do
    @p1 = create(:page, customer: customer, entity: entity, name: "Alpha")
    @p2 = create(:page, customer: customer, entity: entity, name: "Beta")
    @p3 = create(:page, customer: customer, entity: entity, name: "Gamma")
  end

  let(:columns) do
    [
      { key: :name, label: "Name", sortable: true, searchable: true },
      { key: :id,   label: "ID",   sortable: true }
    ]
  end

  it "paginates" do
    scope = Page.for_customer(customer.id).order(:name)
    result = described_class.call(scope: scope, columns: columns, params: { page: 1, per_page: 2 })
    expect(result[:rows].size).to eq(2)
    expect(result[:pagination]).to include(page: 1, per_page: 2, total: 3, total_pages: 2)
  end

  it "applies search over searchable columns" do
    scope = Page.for_customer(customer.id)
    result = described_class.call(scope: scope, columns: columns, params: { q: "alph" })
    expect(result[:rows].map(&:name)).to eq(["Alpha"])
  end

  it "sorts" do
    scope = Page.for_customer(customer.id)
    result = described_class.call(scope: scope, columns: columns, params: { sort: "name", dir: "desc" })
    expect(result[:rows].map(&:name)).to eq(%w[Gamma Beta Alpha])
  end

  it "ignores unknown sort column" do
    scope = Page.for_customer(customer.id).order(:name)
    result = described_class.call(scope: scope, columns: columns, params: { sort: "nope", dir: "asc" })
    expect(result[:rows].map(&:name)).to eq(%w[Alpha Beta Gamma])
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/dashboard/module_entries_resolver_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/dashboard/module_entries_resolver.rb
# frozen_string_literal: true

module Dashboard
  class ModuleEntriesResolver
    DEFAULT_PER_PAGE = 25

    def self.call(scope:, columns:, params:)
      rel = scope
      rel = apply_search(rel, columns, params[:q]) if params[:q].present?
      rel = apply_sort(rel, columns, params[:sort], params[:dir])
      paginate(rel, params[:page], params[:per_page])
    end

    def self.apply_search(rel, columns, query)
      searchable = columns.select { |c| c[:searchable] }.map { |c| c[:key] }
      return rel if searchable.empty?

      clauses = searchable.map { |k| "LOWER(#{rel.table_name}.#{k}) LIKE :q" }
      rel.where(clauses.join(" OR "), q: "%#{query.downcase}%")
    end

    def self.apply_sort(rel, columns, sort_key, dir)
      return rel if sort_key.blank?
      col = columns.find { |c| c[:sortable] && c[:key].to_s == sort_key.to_s }
      return rel unless col
      direction = dir.to_s.downcase == "desc" ? :desc : :asc
      rel.reorder(col[:key] => direction)
    end

    def self.paginate(rel, page, per_page)
      page = [page.to_i, 1].max
      per_page = (per_page.to_i.positive? ? per_page.to_i : DEFAULT_PER_PAGE)
      total = rel.count
      total_pages = (total.to_f / per_page).ceil
      rows = rel.offset((page - 1) * per_page).limit(per_page).to_a
      {
        rows: rows,
        pagination: { page: page, per_page: per_page, total: total, total_pages: total_pages }
      }
    end

    private_class_method :apply_search, :apply_sort, :paginate
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/dashboard/module_entries_resolver_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard/module_entries_resolver.rb spec/services/dashboard/module_entries_resolver_spec.rb
git commit -m "Dashboard: ModuleEntriesResolver (pagination, sort, search)"
```

---

## Task 14: Migrate Payment module + delete old NavItem

**Files:**
- Modify: `app/services/feature_modules/payment/registration.rb`
- Delete: `app/services/feature_modules/nav_item.rb`
- Delete: `app/components/feature_modules/nav_contributions_component.rb`
- Delete: `app/components/feature_modules/nav_contributions_component.html.erb`
- Test: `spec/services/feature_modules/payment/registration_spec.rb` (update)

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/feature_modules/payment/registration_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::Payment::Registration do
  it "exposes a Transactions entry and Settings via sidebar_contributions" do
    result = described_class.sidebar_contributions(double("controller"))
    entry_labels = result[:entries].map(&:label)
    settings_labels = result[:settings].map(&:label)
    expect(entry_labels).to include("Transactions")
    expect(settings_labels).to include("Gateway")
  end

  it "entries_for transactions returns columns + scope shape" do
    customer = create(:customer)
    Current.customer = customer
    result = described_class.entries_for(entry_key: "transactions", params: {})
    expect(result[:columns]).to all(include(:key, :label))
    expect(result[:scope]).to be_a(ActiveRecord::Relation)
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Update Payment Registration**

Replace `app/services/feature_modules/payment/registration.rb` end-to-end:

```ruby
# frozen_string_literal: true

module FeatureModules
  module Payment
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "payment"
      def self.module_name        = "Payments"
      def self.module_description = "Checkout handoff (demo)"

      def self.provision!(_customer); end
      def self.deprovision!(_customer); end

      entry_path   { |customer| "/#{customer.id}/payment/checkout" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :amount,   validates: { presence: true, numericality: { greater_than: 0 } }
        property :currency, validates: { presence: true, inclusion: { in: %w[USD EUR GBP] } }
        property :order_id, validates: { presence: true }
      end

      output_contract do
        property :payment_reference, validates: { presence: true }
        property :status,            validates: { inclusion: { in: %w[succeeded failed] } }
        property :paid_at
      end

      def self.sidebar_contributions(_controller)
        {
          entries: [
            Dashboard::ModuleContribution.new(label: "Transactions", entry_key: "transactions")
          ],
          settings: [
            Dashboard::ModuleContribution.new(label: "Gateway", entry_key: "gateway")
          ],
          metadata: { order: 50 }
        }
      end

      def self.entries_for(entry_key:, params:)
        case entry_key
        when "transactions"
          {
            title: "Transactions",
            columns: [
              { key: :action, label: "Action", sortable: true, searchable: true },
              { key: :status, label: "Status", sortable: true },
              { key: :created_at, label: "At",  sortable: true }
            ],
            scope: FeatureModuleLog.where(feature_module_id: FeatureModule.where(key: "payment")).order(created_at: :desc)
          }
        else
          raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb`
Expected: PASS.

- [ ] **Step 5: Delete obsolete files**

```bash
git rm app/services/feature_modules/nav_item.rb \
      app/components/feature_modules/nav_contributions_component.rb \
      app/components/feature_modules/nav_contributions_component.html.erb
```

If there are specs for those, delete them too:

```bash
git rm spec/components/feature_modules/nav_contributions_component_spec.rb 2>/dev/null || true
git rm spec/services/feature_modules/nav_item_spec.rb 2>/dev/null || true
```

- [ ] **Step 6: Ripgrep for lingering references; fix any**

```bash
grep -rn "FeatureModules::NavItem\|FeatureModules::NavContributionsComponent\|nav_items_for" app/ spec/ config/
```

Expected: empty output. If hits appear, remove them (they are stale after this task).

- [ ] **Step 7: Run full spec suite for FeatureModules**

Run: `bundle exec rspec spec/services/feature_modules spec/components/feature_modules`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Dashboard: migrate Payment module to sidebar_contributions; delete NavItem/NavContributions"
```

---

## Task 15: SidebarNodeComponent + SidebarComponent

**Files:**
- Create: `app/components/dashboard/sidebar_node_component.{rb,html.erb}`
- Create: `app/components/dashboard/sidebar_component.{rb,html.erb}`
- Test: `spec/components/dashboard/sidebar_node_component_spec.rb`
- Test: `spec/components/dashboard/sidebar_component_spec.rb`

- [ ] **Step 1: Write failing SidebarNodeComponent spec**

```ruby
# spec/components/dashboard/sidebar_node_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SidebarNodeComponent, type: :component do
  let(:node) { Dashboard::SidebarNode.new(key: "k", label: "Foo", section: :pages, path: "/foo") }

  it "renders an anchor when path is present" do
    rendered = render_inline(described_class.new(node: node, current_path: "/"))
    expect(rendered.css("a").text).to include("Foo")
    expect(rendered.css("a").attr("href").value).to eq("/foo")
  end

  it "applies active indicator when current_path matches" do
    rendered = render_inline(described_class.new(node: node, current_path: "/foo"))
    expect(rendered.css(".border-l-4.border-indigo-600")).not_to be_empty
  end

  it "renders children as nested list" do
    parent = Dashboard::SidebarNode.new(
      key: "p", label: "Parent", section: :pages,
      children: [Dashboard::SidebarNode.new(key: "c", label: "Child", section: :pages, path: "/c")]
    )
    rendered = render_inline(described_class.new(node: parent, current_path: "/"))
    expect(rendered.css("li li").text).to include("Child")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/sidebar_node_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `SidebarNodeComponent`**

```ruby
# app/components/dashboard/sidebar_node_component.rb
# frozen_string_literal: true

module Dashboard
  class SidebarNodeComponent < ApplicationComponent
    attr_reader :node, :current_path, :depth

    def initialize(node:, current_path:, depth: 0)
      @node = node
      @current_path = current_path
      @depth = depth
    end

    def active?
      node.path.present? && current_path == node.path
    end

    def row_classes
      base = "flex items-center gap-2 px-3 py-1.5 text-sm rounded transition-colors"
      state = if active?
                "bg-indigo-50 text-indigo-900 border-l-4 border-indigo-600 pl-2"
              else
                "text-gray-700 hover:bg-gray-100"
              end
      indent = "ml-#{depth * 3}"
      "#{base} #{state} #{indent}"
    end
  end
end
```

```erb
<%# app/components/dashboard/sidebar_node_component.html.erb %>
<li>
  <% if node.link? %>
    <%= link_to node.path, class: row_classes do %>
      <% if node.icon.present? %>
        <svg class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="<%= node.icon %>" />
        </svg>
      <% end %>
      <span class="truncate"><%= node.label %></span>
      <% if node.badge %>
        <span class="ml-auto inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-gray-100 text-gray-700">
          <%= node.badge[:label] %>
        </span>
      <% end %>
    <% end %>
  <% else %>
    <div class="<%= row_classes %> uppercase text-xs font-semibold tracking-wide text-gray-500">
      <%= node.label %>
    </div>
  <% end %>
  <% if node.children.any? %>
    <ul class="mt-0.5 space-y-0.5">
      <% node.children.each do |child| %>
        <%= render Dashboard::SidebarNodeComponent.new(node: child, current_path: current_path, depth: depth + 1) %>
      <% end %>
    </ul>
  <% end %>
</li>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/sidebar_node_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing SidebarComponent spec**

```ruby
# spec/components/dashboard/sidebar_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SidebarComponent, type: :component do
  it "renders an <aside> with nodes for the current section" do
    tree = Dashboard::SidebarTree.new
    tree.add(Dashboard::SidebarNode.new(key: "e.a", label: "A", section: :pages, path: "/a"))
    rendered = render_inline(described_class.new(tree: tree, section: :pages, current_path: "/"))
    expect(rendered.css("aside")).not_to be_empty
    expect(rendered.text).to include("A")
  end

  it "renders empty-state when the section has no nodes" do
    tree = Dashboard::SidebarTree.new
    rendered = render_inline(described_class.new(tree: tree, section: :pages, current_path: "/"))
    expect(rendered.text).to include("Nothing here yet")
  end
end
```

- [ ] **Step 6: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/sidebar_component_spec.rb`
Expected: FAIL.

- [ ] **Step 7: Implement SidebarComponent**

```ruby
# app/components/dashboard/sidebar_component.rb
# frozen_string_literal: true

module Dashboard
  class SidebarComponent < ApplicationComponent
    attr_reader :tree, :section, :current_path

    def initialize(tree:, section:, current_path:)
      @tree = tree
      @section = section
      @current_path = current_path
    end

    def nodes
      tree.nodes_for(section)
    end
  end
end
```

```erb
<%# app/components/dashboard/sidebar_component.html.erb %>
<aside class="hidden md:flex md:flex-col w-64 bg-white border-r border-gray-200 py-4">
  <% if nodes.empty? %>
    <div class="px-4 py-6 text-sm text-gray-500">Nothing here yet</div>
  <% else %>
    <ul class="space-y-1 px-2">
      <% nodes.each do |node| %>
        <%= render Dashboard::SidebarNodeComponent.new(node: node, current_path: current_path) %>
      <% end %>
    </ul>
  <% end %>
</aside>
```

- [ ] **Step 8: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/sidebar_component_spec.rb`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/components/dashboard/sidebar_node_component* app/components/dashboard/sidebar_component* spec/components/dashboard
git commit -m "Dashboard: SidebarNodeComponent + SidebarComponent"
```

---

## Task 16: TopbarComponent + SectionTabsComponent + UserMenuComponent

**Files:**
- Create: `app/components/dashboard/user_menu_component.{rb,html.erb}`
- Create: `app/components/dashboard/section_tabs_component.{rb,html.erb}`
- Create: `app/components/dashboard/topbar_component.{rb,html.erb}`
- Create: `app/javascript/controllers/dashboard_user_menu_controller.js`
- Create: `app/javascript/controllers/dashboard_section_tabs_controller.js`
- Test: `spec/components/dashboard/user_menu_component_spec.rb`
- Test: `spec/components/dashboard/section_tabs_component_spec.rb`
- Test: `spec/components/dashboard/topbar_component_spec.rb`

- [ ] **Step 1: Write failing UserMenuComponent spec**

```ruby
# spec/components/dashboard/user_menu_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::UserMenuComponent, type: :component do
  let(:user) { build_stubbed(:user, customer: build_stubbed(:customer), email: "jane@acme.test", first_name: "Jane", last_name: "Doe") }

  it "renders the user display name" do
    rendered = render_inline(described_class.new(user: user, customer: user.customer))
    expect(rendered.text).to include("Jane Doe")
  end

  it "links to edit profile, change password, mfa setup, and sign out" do
    rendered = render_inline(described_class.new(user: user, customer: user.customer))
    hrefs = rendered.css("a").map { |a| a.attr("href") }
    expect(hrefs).to include(
      "/#{user.customer.id}/dashboard/settings/users/#{user.id}/edit",
      "/#{user.customer.id}/auth/users/edit",
      "/#{user.customer.id}/auth/mfa/setup"
    )
    expect(rendered.to_html).to include("Sign out")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/user_menu_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement UserMenuComponent**

```ruby
# app/components/dashboard/user_menu_component.rb
# frozen_string_literal: true

module Dashboard
  class UserMenuComponent < ApplicationComponent
    def initialize(user:, customer:)
      @user = user
      @customer = customer
    end

    attr_reader :user, :customer

    def display_name
      [user.first_name, user.last_name].compact.join(" ").presence || user.email
    end

    def profile_path    = "/#{customer.id}/dashboard/settings/users/#{user.id}/edit"
    def password_path   = "/#{customer.id}/auth/users/edit"
    def mfa_path        = "/#{customer.id}/auth/mfa/setup"
    def sign_out_path   = "/#{customer.id}/auth/users/sign_out"
  end
end
```

```erb
<%# app/components/dashboard/user_menu_component.html.erb %>
<div class="relative" data-controller="dashboard-user-menu">
  <button type="button"
          data-action="click->dashboard-user-menu#toggle"
          class="inline-flex items-center gap-2 px-3 py-1.5 rounded hover:bg-gray-100 text-sm text-gray-700">
    <div class="w-7 h-7 bg-indigo-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
      <%= display_name[0].to_s.upcase %>
    </div>
    <span class="truncate max-w-[12rem]"><%= display_name %></span>
  </button>
  <div data-dashboard-user-menu-target="panel"
       class="hidden absolute right-0 mt-2 w-56 bg-white border border-gray-200 rounded-md shadow-lg py-1 z-50">
    <%= link_to "Profile",         profile_path,  class: "block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
    <%= link_to "Change password", password_path, class: "block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
    <%= link_to "MFA setup",       mfa_path,      class: "block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
    <div class="border-t border-gray-100 my-1"></div>
    <%= button_to "Sign out", sign_out_path, method: :delete,
          class: "block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
  </div>
</div>
```

```js
// app/javascript/controllers/dashboard_user_menu_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["panel"]
  toggle()  { this.panelTarget.classList.toggle("hidden") }
  connect() { document.addEventListener("click", this.close.bind(this)) }
  disconnect() { document.removeEventListener("click", this.close.bind(this)) }
  close(e)  {
    if (!this.element.contains(e.target)) this.panelTarget.classList.add("hidden")
  }
}
```

Register the controller in `app/javascript/controllers/index.js`:

```js
import DashboardUserMenuController from "./dashboard_user_menu_controller"
application.register("dashboard-user-menu", DashboardUserMenuController)
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/user_menu_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing SectionTabsComponent spec**

```ruby
# spec/components/dashboard/section_tabs_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::SectionTabsComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 12345678) }

  it "renders 4 tabs with correct hrefs" do
    rendered = render_inline(described_class.new(customer: customer, current_section: :pages))
    labels = rendered.css("a").map(&:text).map(&:strip)
    expect(labels).to eq(["Entity Entries", "Pages", "Modules", "Settings"])
  end

  it "highlights the current section" do
    rendered = render_inline(described_class.new(customer: customer, current_section: :modules))
    active = rendered.css("a.border-indigo-600")
    expect(active.text).to include("Modules")
  end
end
```

- [ ] **Step 6: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/section_tabs_component_spec.rb`
Expected: FAIL.

- [ ] **Step 7: Implement SectionTabsComponent**

```ruby
# app/components/dashboard/section_tabs_component.rb
# frozen_string_literal: true

module Dashboard
  class SectionTabsComponent < ApplicationComponent
    TABS = [
      { key: :entity_entries, label: "Entity Entries" },
      { key: :pages,          label: "Pages" },
      { key: :modules,        label: "Modules" },
      { key: :settings,       label: "Settings" }
    ].freeze

    def initialize(customer:, current_section:)
      @customer = customer
      @current_section = current_section
    end

    attr_reader :customer, :current_section

    def path_for(section)
      case section
      when :entity_entries then "/#{customer.id}/dashboard/entity_entries"
      when :pages          then "/#{customer.id}/pages"
      when :modules        then "/#{customer.id}/feature_modules"
      when :settings       then "/#{customer.id}/dashboard/settings"
      end
    end

    def classes_for(section)
      base = "inline-flex items-center px-4 py-3 text-sm font-medium border-b-2 -mb-px"
      section == current_section ? "#{base} border-indigo-600 text-indigo-900" : "#{base} border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300"
    end
  end
end
```

```erb
<%# app/components/dashboard/section_tabs_component.html.erb %>
<nav class="hidden md:flex border-b border-gray-200 bg-white" aria-label="Dashboard sections">
  <div class="max-w-7xl mx-auto px-4 flex">
    <% TABS.each do |tab| %>
      <%= link_to tab[:label], path_for(tab[:key]), class: classes_for(tab[:key]) %>
    <% end %>
  </div>
</nav>

<div class="md:hidden border-b border-gray-200 bg-white px-4 py-2" data-controller="dashboard-section-tabs">
  <button type="button" class="w-full inline-flex justify-between items-center px-3 py-2 text-sm font-medium text-gray-700 bg-gray-50 rounded"
          data-action="click->dashboard-section-tabs#toggle">
    <span><%= TABS.find { |t| t[:key] == current_section }&.dig(:label) %></span>
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/>
    </svg>
  </button>
  <ul data-dashboard-section-tabs-target="panel" class="hidden mt-2 space-y-1 bg-white border border-gray-200 rounded shadow">
    <% TABS.each do |tab| %>
      <li><%= link_to tab[:label], path_for(tab[:key]), class: "block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100" %></li>
    <% end %>
  </ul>
</div>
```

```js
// app/javascript/controllers/dashboard_section_tabs_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["panel"]
  toggle() { this.panelTarget.classList.toggle("hidden") }
}
```

Register: `application.register("dashboard-section-tabs", DashboardSectionTabsController)` in `app/javascript/controllers/index.js`.

- [ ] **Step 8: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/section_tabs_component_spec.rb`
Expected: PASS.

- [ ] **Step 9: Write failing TopbarComponent spec**

```ruby
# spec/components/dashboard/topbar_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::TopbarComponent, type: :component do
  let(:customer) { build_stubbed(:customer, name: "Acme", id: 12345678) }
  let(:user)     { build_stubbed(:user, customer: customer, first_name: "Jane", last_name: "Doe") }

  it "renders customer name and user menu" do
    rendered = render_inline(described_class.new(customer: customer, user: user))
    expect(rendered.text).to include("Acme")
    expect(rendered.text).to include("Jane Doe")
  end

  it "renders a mobile hamburger" do
    rendered = render_inline(described_class.new(customer: customer, user: user))
    expect(rendered.css("[data-action*='dashboard-drawer#open']")).not_to be_empty
  end
end
```

- [ ] **Step 10: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/topbar_component_spec.rb`
Expected: FAIL.

- [ ] **Step 11: Implement TopbarComponent**

```ruby
# app/components/dashboard/topbar_component.rb
# frozen_string_literal: true

module Dashboard
  class TopbarComponent < ApplicationComponent
    def initialize(customer:, user:)
      @customer = customer
      @user = user
    end
    attr_reader :customer, :user
  end
end
```

```erb
<%# app/components/dashboard/topbar_component.html.erb %>
<header class="bg-white border-b border-gray-200">
  <div class="max-w-7xl mx-auto px-4 h-14 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <button type="button" class="md:hidden p-1 text-gray-700" data-action="click->dashboard-drawer#open" aria-label="Open menu">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16"/>
        </svg>
      </button>
      <%= link_to "/#{customer.id}", class: "flex items-center gap-2" do %>
        <div class="w-7 h-7 bg-indigo-600 rounded-md flex items-center justify-center text-white text-sm font-semibold">
          <%= customer.name[0].to_s.upcase %>
        </div>
        <span class="text-sm font-semibold text-gray-900 truncate max-w-[14rem]"><%= customer.name %></span>
      <% end %>
    </div>
    <%= render Dashboard::UserMenuComponent.new(user: user, customer: customer) if user %>
  </div>
</header>
```

- [ ] **Step 12: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/topbar_component_spec.rb`
Expected: PASS.

- [ ] **Step 13: Commit**

```bash
git add app/components/dashboard/user_menu_component* app/components/dashboard/section_tabs_component* app/components/dashboard/topbar_component* app/javascript/controllers/dashboard_user_menu_controller.js app/javascript/controllers/dashboard_section_tabs_controller.js app/javascript/controllers/index.js spec/components/dashboard
git commit -m "Dashboard: Topbar, SectionTabs, UserMenu components + Stimulus controllers"
```

---

## Task 17: DrawerComponent + drawer Stimulus controller

**Files:**
- Create: `app/components/dashboard/drawer_component.{rb,html.erb}`
- Create: `app/javascript/controllers/dashboard_drawer_controller.js`
- Test: `spec/components/dashboard/drawer_component_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/components/dashboard/drawer_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::DrawerComponent, type: :component do
  it "renders a slot with drawer container and backdrop" do
    tree = Dashboard::SidebarTree.new
    rendered = render_inline(described_class.new(tree: tree, section: :pages, current_path: "/", customer: build_stubbed(:customer, id: 1)))
    expect(rendered.css("[data-controller='dashboard-drawer']")).not_to be_empty
    expect(rendered.css("[data-dashboard-drawer-target='panel']")).not_to be_empty
    expect(rendered.css("[data-dashboard-drawer-target='backdrop']")).not_to be_empty
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/drawer_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/components/dashboard/drawer_component.rb
# frozen_string_literal: true

module Dashboard
  class DrawerComponent < ApplicationComponent
    def initialize(tree:, section:, current_path:, customer:)
      @tree = tree
      @section = section
      @current_path = current_path
      @customer = customer
    end
    attr_reader :tree, :section, :current_path, :customer
  end
end
```

```erb
<%# app/components/dashboard/drawer_component.html.erb %>
<div class="md:hidden" data-controller="dashboard-drawer">
  <div data-dashboard-drawer-target="backdrop"
       data-action="click->dashboard-drawer#close"
       class="hidden fixed inset-0 bg-gray-900/50 z-40"></div>
  <aside data-dashboard-drawer-target="panel"
         class="hidden fixed top-0 left-0 h-full w-72 bg-white border-r border-gray-200 z-50 overflow-y-auto">
    <div class="flex items-center justify-between px-4 h-14 border-b border-gray-200">
      <span class="text-sm font-semibold text-gray-900"><%= customer.name %></span>
      <button type="button" data-action="click->dashboard-drawer#close" aria-label="Close menu" class="p-1 text-gray-700">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>
      </button>
    </div>
    <% Dashboard::SectionTabsComponent::TABS.each do |tab| %>
      <div class="px-4 pt-4 pb-1 text-xs uppercase tracking-wide text-gray-500"><%= tab[:label] %></div>
      <ul class="px-2 pb-2 space-y-0.5">
        <% tree.nodes_for(tab[:key]).each do |node| %>
          <%= render Dashboard::SidebarNodeComponent.new(node: node, current_path: current_path) %>
        <% end %>
      </ul>
    <% end %>
  </aside>
</div>
```

```js
// app/javascript/controllers/dashboard_drawer_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["panel", "backdrop"]
  open()  { this.panelTarget.classList.remove("hidden"); this.backdropTarget.classList.remove("hidden") }
  close() { this.panelTarget.classList.add("hidden");    this.backdropTarget.classList.add("hidden") }
}
```

Register in `app/javascript/controllers/index.js`:

```js
import DashboardDrawerController from "./dashboard_drawer_controller"
application.register("dashboard-drawer", DashboardDrawerController)
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/drawer_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/dashboard/drawer_component* app/javascript/controllers/dashboard_drawer_controller.js app/javascript/controllers/index.js spec/components/dashboard/drawer_component_spec.rb
git commit -m "Dashboard: DrawerComponent + Stimulus drawer controller for mobile"
```

---

## Task 18: ShellComponent

**Files:**
- Create: `app/components/dashboard/shell_component.{rb,html.erb}`
- Test: `spec/components/dashboard/shell_component_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/components/dashboard/shell_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::ShellComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 123, name: "Acme") }
  let(:user)     { build_stubbed(:user, customer: customer, first_name: "Jane", last_name: "Doe") }
  let(:tree)     { Dashboard::SidebarTree.new }

  it "renders topbar, section tabs, sidebar, and yielded content" do
    rendered = render_inline(described_class.new(
      customer: customer, user: user, tree: tree,
      current_section: :pages, current_path: "/"
    )) { "<p class='main-body'>Hello</p>".html_safe }
    expect(rendered.css("header")).not_to be_empty
    expect(rendered.css("nav")).not_to be_empty
    expect(rendered.css("aside")).not_to be_empty
    expect(rendered.css(".main-body").text).to eq("Hello")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/shell_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/components/dashboard/shell_component.rb
# frozen_string_literal: true

module Dashboard
  class ShellComponent < ApplicationComponent
    renders_one :main

    def initialize(customer:, user:, tree:, current_section:, current_path:)
      @customer = customer
      @user = user
      @tree = tree
      @current_section = current_section
      @current_path = current_path
    end
    attr_reader :customer, :user, :tree, :current_section, :current_path
  end
end
```

```erb
<%# app/components/dashboard/shell_component.html.erb %>
<div class="min-h-screen flex flex-col bg-gray-50">
  <%= render Dashboard::TopbarComponent.new(customer: customer, user: user) %>
  <%= render Dashboard::SectionTabsComponent.new(customer: customer, current_section: current_section) %>
  <div class="flex flex-1 overflow-hidden">
    <%= render Dashboard::SidebarComponent.new(tree: tree, section: current_section, current_path: current_path) %>
    <%= render Dashboard::DrawerComponent.new(tree: tree, section: current_section, current_path: current_path, customer: customer) %>
    <main class="flex-1 overflow-auto">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 py-6">
        <%= content %>
      </div>
    </main>
  </div>
</div>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/shell_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/dashboard/shell_component* spec/components/dashboard/shell_component_spec.rb
git commit -m "Dashboard: ShellComponent composes topbar/tabs/sidebar/main"
```

---

## Task 19: Landing page components

**Files:**
- Create: `app/components/dashboard/landing_header_component.{rb,html.erb}`
- Create: `app/components/dashboard/landing_stats_card_component.{rb,html.erb}`
- Create: `app/components/dashboard/activity_feed_component.{rb,html.erb}`
- Create: `app/components/dashboard/quick_action_card_component.{rb,html.erb}`
- Test: one spec file per component under `spec/components/dashboard/`

- [ ] **Step 1: Write failing spec — LandingHeaderComponent**

```ruby
# spec/components/dashboard/landing_header_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::LandingHeaderComponent, type: :component do
  it "greets the user by first name and shows customer name" do
    customer = build_stubbed(:customer, name: "Acme")
    user     = build_stubbed(:user, customer: customer, first_name: "Jane", last_name: "Doe")
    rendered = render_inline(described_class.new(customer: customer, user: user))
    expect(rendered.text).to include("Welcome back, Jane")
    expect(rendered.text).to include("Acme")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/landing_header_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/components/dashboard/landing_header_component.rb
module Dashboard
  class LandingHeaderComponent < ApplicationComponent
    def initialize(customer:, user:)
      @customer = customer
      @user = user
    end
    attr_reader :customer, :user
  end
end
```

```erb
<%# app/components/dashboard/landing_header_component.html.erb %>
<section class="mb-8">
  <h1 class="text-2xl font-semibold text-gray-900">Welcome back, <%= user.first_name %></h1>
  <p class="mt-1 text-sm text-gray-600">Overview for <%= customer.name %></p>
</section>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/landing_header_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing spec — LandingStatsCardComponent**

```ruby
# spec/components/dashboard/landing_stats_card_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::LandingStatsCardComponent, type: :component do
  it "renders a label and numeric value" do
    rendered = render_inline(described_class.new(label: "Entities", value: 7))
    expect(rendered.text).to include("Entities")
    expect(rendered.text).to include("7")
  end

  it "renders a sub-label when provided" do
    rendered = render_inline(described_class.new(label: "Pages", value: 5, sub_label: "2 published"))
    expect(rendered.text).to include("2 published")
  end
end
```

- [ ] **Step 6: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/landing_stats_card_component_spec.rb`
Expected: FAIL.

- [ ] **Step 7: Implement**

```ruby
# app/components/dashboard/landing_stats_card_component.rb
module Dashboard
  class LandingStatsCardComponent < ApplicationComponent
    def initialize(label:, value:, sub_label: nil)
      @label = label
      @value = value
      @sub_label = sub_label
    end
    attr_reader :label, :value, :sub_label
  end
end
```

```erb
<%# app/components/dashboard/landing_stats_card_component.html.erb %>
<div class="bg-white border border-gray-200 rounded-md p-4">
  <div class="text-xs uppercase tracking-wide text-gray-500 font-medium"><%= label %></div>
  <div class="mt-1 text-2xl font-semibold text-gray-900"><%= value %></div>
  <% if sub_label %><div class="mt-0.5 text-xs text-gray-500"><%= sub_label %></div><% end %>
</div>
```

- [ ] **Step 8: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/landing_stats_card_component_spec.rb`
Expected: PASS.

- [ ] **Step 9: Write failing spec — ActivityFeedComponent**

```ruby
# spec/components/dashboard/activity_feed_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::ActivityFeedComponent, type: :component do
  it "renders each event as a list row" do
    events = [
      Dashboard::ActivityFeed::Event.new(kind: :page_edited, label: "Intake", path: "/p", occurred_at: 1.minute.ago),
      Dashboard::ActivityFeed::Event.new(kind: :flowchart_edited, label: "Order", path: "/f", occurred_at: 2.minutes.ago)
    ]
    rendered = render_inline(described_class.new(events: events))
    expect(rendered.text).to include("Intake")
    expect(rendered.text).to include("Order")
    expect(rendered.css("a").length).to eq(2)
  end

  it "renders empty state when there are no events" do
    rendered = render_inline(described_class.new(events: []))
    expect(rendered.text).to include("No recent activity")
  end
end
```

- [ ] **Step 10: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/activity_feed_component_spec.rb`
Expected: FAIL.

- [ ] **Step 11: Implement**

```ruby
# app/components/dashboard/activity_feed_component.rb
module Dashboard
  class ActivityFeedComponent < ApplicationComponent
    def initialize(events:) = @events = events
    attr_reader :events
  end
end
```

```erb
<%# app/components/dashboard/activity_feed_component.html.erb %>
<section class="bg-white border border-gray-200 rounded-md">
  <header class="px-4 py-3 border-b border-gray-200 text-sm font-semibold text-gray-900">Recent activity</header>
  <% if events.empty? %>
    <div class="px-4 py-8 text-sm text-gray-500 text-center">No recent activity</div>
  <% else %>
    <ul class="divide-y divide-gray-100">
      <% events.each do |ev| %>
        <li class="px-4 py-2.5 flex items-center justify-between text-sm">
          <% if ev.path %>
            <%= link_to ev.label, ev.path, class: "text-gray-900 hover:text-indigo-700 truncate" %>
          <% else %>
            <span class="text-gray-900 truncate"><%= ev.label %></span>
          <% end %>
          <span class="text-xs text-gray-500 ml-3 flex-shrink-0"><%= time_ago_in_words(ev.occurred_at) %> ago</span>
        </li>
      <% end %>
    </ul>
  <% end %>
</section>
```

- [ ] **Step 12: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/activity_feed_component_spec.rb`
Expected: PASS.

- [ ] **Step 13: Write failing spec — QuickActionCardComponent**

```ruby
# spec/components/dashboard/quick_action_card_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::QuickActionCardComponent, type: :component do
  it "renders a linked card with label and description" do
    rendered = render_inline(described_class.new(label: "Create Entity", description: "Set up a new data type", path: "/x"))
    expect(rendered.css("a[href='/x']")).not_to be_empty
    expect(rendered.text).to include("Create Entity")
    expect(rendered.text).to include("Set up a new data type")
  end
end
```

- [ ] **Step 14: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/quick_action_card_component_spec.rb`
Expected: FAIL.

- [ ] **Step 15: Implement**

```ruby
# app/components/dashboard/quick_action_card_component.rb
module Dashboard
  class QuickActionCardComponent < ApplicationComponent
    def initialize(label:, description:, path:, icon: nil)
      @label = label
      @description = description
      @path = path
      @icon = icon
    end
    attr_reader :label, :description, :path, :icon
  end
end
```

```erb
<%# app/components/dashboard/quick_action_card_component.html.erb %>
<%= link_to path, class: "block bg-white border border-gray-200 rounded-md p-4 hover:border-indigo-300 transition-colors" do %>
  <div class="flex items-start gap-3">
    <% if icon %>
      <div class="w-8 h-8 rounded bg-indigo-50 text-indigo-700 flex items-center justify-center flex-shrink-0">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="<%= icon %>"/></svg>
      </div>
    <% end %>
    <div>
      <div class="text-sm font-semibold text-gray-900"><%= label %></div>
      <div class="mt-0.5 text-xs text-gray-500"><%= description %></div>
    </div>
  </div>
<% end %>
```

- [ ] **Step 16: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/quick_action_card_component_spec.rb`
Expected: PASS.

- [ ] **Step 17: Commit**

```bash
git add app/components/dashboard/landing_header_component* app/components/dashboard/landing_stats_card_component* app/components/dashboard/activity_feed_component* app/components/dashboard/quick_action_card_component* spec/components/dashboard
git commit -m "Dashboard: landing-page components (header, stats card, activity feed, quick action)"
```

---

## Task 20: EntriesTableComponent

**Files:**
- Create: `app/components/dashboard/entries_table_component.{rb,html.erb}`
- Test: `spec/components/dashboard/entries_table_component_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/components/dashboard/entries_table_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::EntriesTableComponent, type: :component do
  let(:columns) do
    [
      { key: :name, label: "Name", sortable: true },
      { key: :published, label: "Status" }
    ]
  end

  it "renders headers and rows" do
    rows = [
      OpenStruct.new(name: "Alpha", published: true),
      OpenStruct.new(name: "Beta",  published: false)
    ]
    pagination = { page: 1, per_page: 25, total: 2, total_pages: 1 }
    rendered = render_inline(described_class.new(
      title: "Pages", columns: columns, rows: rows,
      pagination: pagination, row_path: nil, params: {}
    ))
    expect(rendered.css("th").map(&:text).map(&:strip)).to include("Name", "Status")
    expect(rendered.css("tbody tr").length).to eq(2)
    expect(rendered.text).to include("Alpha")
  end

  it "renders row links when row_path is provided" do
    rows = [OpenStruct.new(id: 7, name: "Alpha", published: true)]
    rendered = render_inline(described_class.new(
      title: "Pages", columns: columns, rows: rows,
      pagination: { page: 1, per_page: 1, total: 1, total_pages: 1 },
      row_path: ->(r) { "/rows/#{r.id}" }, params: {}
    ))
    expect(rendered.css("a[href='/rows/7']")).not_to be_empty
  end

  it "renders empty-state when there are no rows" do
    rendered = render_inline(described_class.new(
      title: "Pages", columns: columns, rows: [],
      pagination: { page: 1, per_page: 25, total: 0, total_pages: 0 },
      row_path: nil, params: {}
    ))
    expect(rendered.text).to include("Nothing to show")
  end

  it "renders pagination controls when total_pages > 1" do
    rendered = render_inline(described_class.new(
      title: "Pages", columns: columns, rows: [OpenStruct.new(name: "A", published: true)],
      pagination: { page: 1, per_page: 1, total: 2, total_pages: 2 },
      row_path: nil, params: {}
    ))
    expect(rendered.text).to include("Page 1 of 2")
  end

  it "renders a search input" do
    rendered = render_inline(described_class.new(
      title: "Pages", columns: columns, rows: [],
      pagination: { page: 1, per_page: 25, total: 0, total_pages: 0 },
      row_path: nil, params: {}
    ))
    expect(rendered.css("input[type='search']")).not_to be_empty
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/entries_table_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/components/dashboard/entries_table_component.rb
# frozen_string_literal: true

module Dashboard
  class EntriesTableComponent < ApplicationComponent
    def initialize(title:, columns:, rows:, pagination:, row_path:, params:)
      @title = title
      @columns = columns
      @rows = rows
      @pagination = pagination
      @row_path = row_path
      @params = params
    end

    attr_reader :title, :columns, :rows, :pagination, :row_path, :params

    def sort_link(col, label)
      return label unless col[:sortable]
      current = params[:sort].to_s == col[:key].to_s
      next_dir = (current && params[:dir] == "asc") ? "desc" : "asc"
      new_params = params.to_h.symbolize_keys.merge(sort: col[:key], dir: next_dir)
      arrow = current ? (params[:dir] == "desc" ? " ↓" : " ↑") : ""
      helpers.link_to "#{label}#{arrow}", "?#{new_params.to_query}", class: "hover:text-gray-900"
    end

    def cell_value(row, col)
      row.public_send(col[:key])
    end

    def page_link(page)
      new_params = params.to_h.symbolize_keys.merge(page: page)
      "?#{new_params.to_query}"
    end
  end
end
```

```erb
<%# app/components/dashboard/entries_table_component.html.erb %>
<section class="bg-white border border-gray-200 rounded-md">
  <header class="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
    <h2 class="text-sm font-semibold text-gray-900"><%= title %></h2>
    <form method="get" class="flex items-center gap-2">
      <input type="search" name="q" value="<%= params[:q] %>" placeholder="Search"
             class="px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:outline-none">
    </form>
  </header>
  <% if rows.empty? %>
    <div class="px-4 py-12 text-sm text-gray-500 text-center">Nothing to show</div>
  <% else %>
    <table class="w-full text-sm">
      <thead class="bg-gray-50 text-xs uppercase tracking-wide text-gray-600">
        <tr>
          <% columns.each do |col| %>
            <th class="text-left px-4 py-2 font-medium"><%= sort_link(col, col[:label]) %></th>
          <% end %>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% rows.each do |row| %>
          <tr class="hover:bg-gray-50">
            <% columns.each_with_index do |col, i| %>
              <td class="px-4 py-2 text-gray-800">
                <% if row_path && i.zero? %>
                  <%= link_to cell_value(row, col).to_s, row_path.call(row), class: "text-indigo-700 hover:text-indigo-900" %>
                <% else %>
                  <%= cell_value(row, col) %>
                <% end %>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
  <% if pagination[:total_pages].to_i > 1 %>
    <footer class="px-4 py-3 border-t border-gray-200 flex items-center justify-between text-xs text-gray-600">
      <span>Page <%= pagination[:page] %> of <%= pagination[:total_pages] %></span>
      <div class="flex items-center gap-2">
        <% if pagination[:page] > 1 %><%= link_to "Prev", page_link(pagination[:page] - 1), class: "px-2 py-1 border border-gray-200 rounded hover:bg-gray-50" %><% end %>
        <% if pagination[:page] < pagination[:total_pages] %><%= link_to "Next", page_link(pagination[:page] + 1), class: "px-2 py-1 border border-gray-200 rounded hover:bg-gray-50" %><% end %>
      </div>
    </footer>
  <% end %>
</section>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/entries_table_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/dashboard/entries_table_component* spec/components/dashboard/entries_table_component_spec.rb
git commit -m "Dashboard: EntriesTableComponent (columns, rows, search, sort, pagination)"
```

---

## Task 21: BreadcrumbsComponent

**Files:**
- Create: `app/components/dashboard/breadcrumbs_component.{rb,html.erb}`
- Test: `spec/components/dashboard/breadcrumbs_component_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/components/dashboard/breadcrumbs_component_spec.rb
require "rails_helper"

RSpec.describe Dashboard::BreadcrumbsComponent, type: :component do
  it "renders each crumb separated by ›" do
    rendered = render_inline(described_class.new(crumbs: [
      { label: "Entity Entries", path: "/1/dashboard/entity_entries" },
      { label: "Customer",       path: nil }
    ]))
    expect(rendered.text).to include("Entity Entries")
    expect(rendered.text).to include("Customer")
    expect(rendered.text).to include("›")
    expect(rendered.css("a[href='/1/dashboard/entity_entries']")).not_to be_empty
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/components/dashboard/breadcrumbs_component_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/components/dashboard/breadcrumbs_component.rb
module Dashboard
  class BreadcrumbsComponent < ApplicationComponent
    def initialize(crumbs:) = @crumbs = crumbs
    attr_reader :crumbs
  end
end
```

```erb
<%# app/components/dashboard/breadcrumbs_component.html.erb %>
<nav class="text-sm text-gray-500 mb-4" aria-label="Breadcrumb">
  <% crumbs.each_with_index do |crumb, i| %>
    <% if crumb[:path] %>
      <%= link_to crumb[:label], crumb[:path], class: "hover:text-gray-900" %>
    <% else %>
      <span class="text-gray-900"><%= crumb[:label] %></span>
    <% end %>
    <% unless i == crumbs.size - 1 %><span class="px-1.5">›</span><% end %>
  <% end %>
</nav>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/components/dashboard/breadcrumbs_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/dashboard/breadcrumbs_component* spec/components/dashboard/breadcrumbs_component_spec.rb
git commit -m "Dashboard: BreadcrumbsComponent"
```

---

## Task 22: ApplicationController#dashboard_layout + allowlist

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Test: `spec/controllers/application_controller_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/controllers/application_controller_spec.rb
require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index = render plain: "ok"
  end

  let(:customer) { create(:customer) }

  before { Current.customer = customer }

  it "chooses dashboard layout for customer-scoped controllers" do
    expect(controller.send(:dashboard_layout)).to eq("dashboard")
  end

  it "falls back to application when no customer is set" do
    Current.customer = nil
    expect(controller.send(:dashboard_layout)).to eq("application")
  end

  it "chooses application layout for platform-owner controllers (FlowchartsController)" do
    flowcharts = FlowchartsController.new
    flowcharts.request = ActionController::TestRequest.create(flowcharts.class)
    Current.customer = customer
    expect(flowcharts.send(:dashboard_layout)).to eq("application")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/controllers/application_controller_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Modify ApplicationController**

Append to `app/controllers/application_controller.rb` (before the final `end`):

```ruby
# ==========================================================================
# Dashboard Layout Selection
# ==========================================================================

# Platform-owner controllers keep the legacy header-only layout.
# Register each class by name (as a string) to avoid eager-loading issues.
PLATFORM_OWNER_CONTROLLERS = %w[
  FlowchartsController
  Admin::CodeGeneratorsController
].freeze

# Chosen as the default layout for every request. Customer-scoped actions
# use the new dashboard shell; platform-owner controllers keep the legacy look.
layout :dashboard_layout

def dashboard_layout
  return "application" unless Current.customer
  PLATFORM_OWNER_CONTROLLERS.include?(self.class.name) ? "application" : "dashboard"
end
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/controllers/application_controller_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/application_controller.rb spec/controllers/application_controller_spec.rb
git commit -m "Dashboard: dashboard_layout chooser + platform-owner allowlist"
```

---

## Task 23: Dashboard layout (`dashboard.html.erb`)

**Files:**
- Create: `app/views/layouts/dashboard.html.erb`

- [ ] **Step 1: Create the layout**

```erb
<%# app/views/layouts/dashboard.html.erb %>
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Dashboard" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= yield :head %>
    <link rel="icon" href="/icon.png" type="image/png">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-gray-50">
    <%
      dashboard_context = Dashboard::DashboardContext.new(
        current_user:     current_user,
        current_customer: current_customer,
        current_section:  local_assigns.fetch(:current_section, :entity_entries),
        request_path:     request.path
      )
      dashboard_tree = Dashboard::SidebarBuilder.build(dashboard_context)
    %>
    <%= render Dashboard::ShellComponent.new(
      customer: current_customer,
      user: current_user,
      tree: dashboard_tree,
      current_section: dashboard_context.current_section,
      current_path: request.path
    ) do %>
      <% if flash.any? %>
        <% flash.each do |type, message| %>
          <div class="mb-4 <%= type == 'alert' ? 'bg-red-50 border-red-400 text-red-800' : 'bg-green-50 border-green-400 text-green-800' %> border-l-4 p-3 text-sm" role="alert">
            <%= message %>
          </div>
        <% end %>
      <% end %>
      <%= yield %>
    <% end %>
  </body>
</html>
```

Note: `current_section` is set by controllers via `helper_method :current_section` (defaults to `:entity_entries`). Controllers that know their section set it explicitly; see Task 26/27/28.

Add to `app/controllers/application_controller.rb` (inside the class):

```ruby
helper_method :current_dashboard_section

def current_dashboard_section
  :entity_entries
end
```

Subclasses override `current_dashboard_section`. Wire through the layout:

Replace the `local_assigns.fetch(:current_section, :entity_entries)` line with `current_dashboard_section`.

- [ ] **Step 2: Commit**

```bash
git add app/views/layouts/dashboard.html.erb app/controllers/application_controller.rb
git commit -m "Dashboard: dashboard layout + current_dashboard_section hook"
```

---

## Task 24: Routes

**Files:**
- Modify: `config/routes.rb`
- Test: `spec/routing/dashboard_routes_spec.rb`

- [ ] **Step 1: Write failing routing spec**

```ruby
# spec/routing/dashboard_routes_spec.rb
require "rails_helper"

RSpec.describe "Dashboard routing" do
  it "routes GET /:cid to dashboard/landing#show" do
    expect(get: "/12345678").to route_to(
      controller: "dashboard/landing", action: "show", customer_id: "12345678"
    )
  end

  it "routes entity_entries index" do
    expect(get: "/12345678/dashboard/entity_entries").to route_to(
      controller: "dashboard/entity_entries", action: "index", customer_id: "12345678"
    )
  end

  it "routes module entry show" do
    expect(get: "/12345678/dashboard/modules/payment/entries/transactions").to route_to(
      controller: "dashboard/module_entries", action: "show",
      customer_id: "12345678", module_key: "payment", entry_key: "transactions"
    )
  end

  it "routes settings and sub-pages" do
    expect(get: "/12345678/dashboard/settings").to          route_to(controller: "dashboard/settings", action: "show", customer_id: "12345678")
    expect(get: "/12345678/dashboard/settings/customer").to route_to(controller: "dashboard/settings", action: "customer", customer_id: "12345678")
    expect(get: "/12345678/dashboard/settings/users").to    route_to(controller: "dashboard/settings", action: "users", customer_id: "12345678")
    expect(get: "/12345678/dashboard/settings/modules/payment").to route_to(
      controller: "dashboard/settings", action: "module_config", customer_id: "12345678", module_key: "payment"
    )
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/routing/dashboard_routes_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Modify `config/routes.rb`**

Inside the existing `scope "/:customer_id", constraints: { customer_id: /\d{8}/ }` block, **remove** `root "customers#index"` (if present), then add near the top:

```ruby
get "/", to: "dashboard/landing#show", as: :dashboard_root

namespace :dashboard do
  resources :entity_entries, only: [:index, :show]
  get "modules/:module_key/entries/:entry_key",
      to: "module_entries#show", as: :module_entry
  get "settings",                     to: "settings#show",          as: :settings
  get "settings/customer",            to: "settings#customer",      as: :settings_customer
  get "settings/users",               to: "settings#users",         as: :settings_users
  get "settings/modules/:module_key", to: "settings#module_config", as: :settings_module
end
```

The root route (`root "customers#index"` at line 15) is kept at the app-level since it matches `/` not `/:customer_id/`. No change needed there.

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/routing/dashboard_routes_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb spec/routing/dashboard_routes_spec.rb
git commit -m "Dashboard: routes for landing, entity_entries, module_entries, settings"
```

---

## Task 25: Dashboard::LandingController + view

**Files:**
- Create: `app/controllers/dashboard/landing_controller.rb`
- Create: `app/views/dashboard/landing/show.html.erb`
- Test: `spec/requests/dashboard/landing_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/dashboard/landing_spec.rb
require "rails_helper"

RSpec.describe "Dashboard landing", type: :request do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :owner) }

  before { sign_in user }

  it "renders landing with header, stats, activity feed, and quick actions" do
    entity = create(:entity, customer: customer, name: "Customer")
    create(:page, customer: customer, entity: entity, name: "Intake")

    get "/#{customer.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome back")
    expect(response.body).to include("Entities")
    expect(response.body).to include("Pages")
    expect(response.body).to include("Recent activity")
    expect(response.body).to include("New page")
  end
end
```

- [ ] **Step 2: Add Devise request-spec helpers if not present**

Check `spec/rails_helper.rb`:

```bash
grep -n "Devise::Test::IntegrationHelpers" spec/rails_helper.rb
```

If absent, add to `spec/rails_helper.rb` inside `RSpec.configure`:

```ruby
config.include Devise::Test::IntegrationHelpers, type: :request
```

Devise sign-in URL is tenant-scoped; `sign_in user` already handles Warden scope.

- [ ] **Step 3: Run — FAIL**

Run: `bundle exec rspec spec/requests/dashboard/landing_spec.rb`
Expected: FAIL (controller missing).

- [ ] **Step 4: Implement**

```ruby
# app/controllers/dashboard/landing_controller.rb
# frozen_string_literal: true

module Dashboard
  class LandingController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def show
      @stats    = Dashboard::LandingStats.for(current_customer).to_h
      @events   = Dashboard::ActivityFeed.recent(current_customer, limit: 10)
      @actions  = quick_actions
    end

    private

    def current_dashboard_section
      :entity_entries
    end
    helper_method :current_dashboard_section

    def quick_actions
      cid = current_customer.id
      [
        { label: "Create entity", description: "Define a new data type", path: "/#{cid}/entities/new" },
        { label: "New page",      description: "Bind a form to an entity", path: "/#{cid}/pages/new" },
        { label: "Enable module", description: "Turn on a feature module", path: "/#{cid}/feature_modules" },
        { label: "Invite user",   description: "Add a teammate",          path: "/#{cid}/authentication/admin/users/new" }
      ]
    end
  end
end
```

```erb
<%# app/views/dashboard/landing/show.html.erb %>
<%= render Dashboard::LandingHeaderComponent.new(customer: current_customer, user: current_user) %>

<section class="grid grid-cols-2 md:grid-cols-5 gap-3 mb-8">
  <%= render Dashboard::LandingStatsCardComponent.new(label: "Entities",  value: @stats[:entities]) %>
  <%= render Dashboard::LandingStatsCardComponent.new(label: "Pages",     value: @stats[:pages][:total], sub_label: "#{@stats[:pages][:published]} published") %>
  <%= render Dashboard::LandingStatsCardComponent.new(label: "Flowcharts", value: @stats[:flowcharts]) %>
  <%= render Dashboard::LandingStatsCardComponent.new(label: "Modules",    value: @stats[:modules_enabled]) %>
  <%= render Dashboard::LandingStatsCardComponent.new(label: "Users",      value: @stats[:users]) %>
</section>

<div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
  <div class="lg:col-span-2">
    <%= render Dashboard::ActivityFeedComponent.new(events: @events) %>
  </div>
  <div>
    <section class="bg-white border border-gray-200 rounded-md p-4">
      <h2 class="text-sm font-semibold text-gray-900 mb-3">Quick actions</h2>
      <div class="space-y-2">
        <% @actions.each do |qa| %>
          <%= render Dashboard::QuickActionCardComponent.new(label: qa[:label], description: qa[:description], path: qa[:path]) %>
        <% end %>
      </div>
    </section>
  </div>
</div>
```

- [ ] **Step 5: Run — PASS**

Run: `bundle exec rspec spec/requests/dashboard/landing_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/dashboard/landing_controller.rb app/views/dashboard/landing/show.html.erb spec/requests/dashboard/landing_spec.rb spec/rails_helper.rb
git commit -m "Dashboard: LandingController + landing view"
```

---

## Task 26: Dashboard::EntityEntriesController + views

**Files:**
- Create: `app/controllers/dashboard/entity_entries_controller.rb`
- Create: `app/views/dashboard/entity_entries/{index,show}.html.erb`
- Test: `spec/requests/dashboard/entity_entries_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/dashboard/entity_entries_spec.rb
require "rails_helper"

RSpec.describe "Dashboard entity entries", type: :request do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :owner) }
  before { sign_in user }

  it "index redirects to the first primary entity" do
    a = create(:entity, customer: customer, name: "Customer")
    create(:entity, customer: customer, name: "Order")

    get "/#{customer.id}/dashboard/entity_entries"
    expect(response).to redirect_to("/#{customer.id}/dashboard/entity_entries/#{a.id}")
  end

  it "index renders empty state when no primary entities exist" do
    get "/#{customer.id}/dashboard/entity_entries"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No entities defined yet")
  end

  it "show renders the entity's entries via the framework table" do
    e = create(:entity, customer: customer, name: "Customer", property_schema: [
      { name: "Name", name_slug: "name", type: "String" }
    ].to_json)
    entry = create(:entity_entry, customer: customer, entity: e, data: { name: "Alice" }.to_json)

    get "/#{customer.id}/dashboard/entity_entries/#{e.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Alice")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/requests/dashboard/entity_entries_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/entity_entries_controller.rb
# frozen_string_literal: true

module Dashboard
  class EntityEntriesController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def index
      graph = Dashboard::EntityAssociationGraph.build(current_customer.id)
      first = graph.primaries.first
      return redirect_to dashboard_entity_entry_path(current_customer.id, first) if first
      @empty = true
    end

    def show
      @entity = Entity.for_customer(current_customer.id).find(params[:id])
      columns = [
        { key: :id,         label: "ID",         sortable: true },
        { key: :created_at, label: "Created at", sortable: true }
      ]
      result = Dashboard::ModuleEntriesResolver.call(
        scope: EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id),
        columns: columns,
        params: params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
      )
      @columns = columns
      @rows = result[:rows]
      @pagination = result[:pagination]
    end

    private

    def current_dashboard_section = :entity_entries
    helper_method :current_dashboard_section
  end
end
```

```erb
<%# app/views/dashboard/entity_entries/index.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [{ label: "Entity Entries", path: nil }]) %>
<section class="bg-white border border-gray-200 rounded-md p-8 text-center">
  <h1 class="text-base font-semibold text-gray-900">No entities defined yet</h1>
  <p class="mt-1 text-sm text-gray-500">Create an entity first to see entries grouped by associations.</p>
  <div class="mt-4">
    <%= link_to "Create entity", "/#{current_customer.id}/entities/new",
          class: "inline-flex items-center px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 rounded hover:bg-indigo-700" %>
  </div>
</section>
```

```erb
<%# app/views/dashboard/entity_entries/show.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [
  { label: "Entity Entries", path: "/#{current_customer.id}/dashboard/entity_entries" },
  { label: @entity.name, path: nil }
]) %>
<%= render Dashboard::EntriesTableComponent.new(
  title: "#{@entity.name} entries",
  columns: @columns,
  rows: @rows,
  pagination: @pagination,
  row_path: ->(r) { "/#{current_customer.id}/entities/#{@entity.id}/entries/#{r.id}" },
  params: params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/requests/dashboard/entity_entries_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard/entity_entries_controller.rb app/views/dashboard/entity_entries spec/requests/dashboard/entity_entries_spec.rb
git commit -m "Dashboard: EntityEntriesController with empty-state and entries table"
```

---

## Task 27: Dashboard::ModuleEntriesController + view

**Files:**
- Create: `app/controllers/dashboard/module_entries_controller.rb`
- Create: `app/views/dashboard/module_entries/show.html.erb`
- Test: `spec/requests/dashboard/module_entries_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/dashboard/module_entries_spec.rb
require "rails_helper"

RSpec.describe "Dashboard module entries", type: :request do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :owner) }

  before do
    sign_in user
    fm = create(:feature_module, key: "payment", name: "Payments")
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)
  end

  it "renders the standard entries table for an enabled module" do
    get "/#{customer.id}/dashboard/modules/payment/entries/transactions"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Transactions")
  end

  it "404s when the module is not enabled" do
    other = create(:customer)
    user2 = create(:user, customer: other, role: :owner)
    sign_in user2
    get "/#{other.id}/dashboard/modules/payment/entries/transactions"
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/requests/dashboard/module_entries_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/module_entries_controller.rb
# frozen_string_literal: true

module Dashboard
  class ModuleEntriesController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def show
      module_key = params[:module_key]
      raise ActionController::RoutingError, "Not Found" unless FeatureModule.enabled?(
        key: module_key, customer_id: current_customer.id
      )

      registration = FeatureModule.find_by!(key: module_key).registration_class
      result = registration.entries_for(
        entry_key: params[:entry_key],
        params: params.permit(:q, :sort, :dir, :page, :per_page).to_h.symbolize_keys
      )

      resolved = Dashboard::ModuleEntriesResolver.call(
        scope: result[:scope], columns: result[:columns],
        params: params.permit(:q, :sort, :dir, :page, :per_page).to_h.symbolize_keys
      )

      @title = result[:title] || params[:entry_key].humanize
      @columns = result[:columns]
      @rows = resolved[:rows]
      @pagination = resolved[:pagination]
      @row_path = result[:row_path]
    end

    private

    def current_dashboard_section = :modules
    helper_method :current_dashboard_section
  end
end
```

```erb
<%# app/views/dashboard/module_entries/show.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: @title,    path: nil }
]) %>
<%= render Dashboard::EntriesTableComponent.new(
  title: @title, columns: @columns, rows: @rows,
  pagination: @pagination, row_path: @row_path,
  params: params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/requests/dashboard/module_entries_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard/module_entries_controller.rb app/views/dashboard/module_entries spec/requests/dashboard/module_entries_spec.rb
git commit -m "Dashboard: ModuleEntriesController + view (framework-owned table)"
```

---

## Task 28: Dashboard::SettingsController + views

**Files:**
- Create: `app/controllers/dashboard/settings_controller.rb`
- Create: `app/views/dashboard/settings/{show,customer,users,module_config}.html.erb`
- Test: `spec/requests/dashboard/settings_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/dashboard/settings_spec.rb
require "rails_helper"

RSpec.describe "Dashboard settings", type: :request do
  let(:customer) { create(:customer) }
  let(:owner)    { create(:user, customer: customer, role: :owner) }

  before { sign_in owner }

  it "renders the settings index with sections linking to subpages" do
    get "/#{customer.id}/dashboard/settings"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Settings")
    expect(response.body).to include("Customer Profile")
    expect(response.body).to include("Users")
  end

  it "renders customer profile form (reuses Customer data)" do
    get "/#{customer.id}/dashboard/settings/customer"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(customer.name)
  end

  it "renders users list (reuses auth admin data)" do
    get "/#{customer.id}/dashboard/settings/users"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(owner.email)
  end

  it "renders a module config page for an enabled module" do
    fm = create(:feature_module, key: "payment", name: "Payments")
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)
    get "/#{customer.id}/dashboard/settings/modules/payment"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payments")
  end
end
```

- [ ] **Step 2: Run — FAIL**

Run: `bundle exec rspec spec/requests/dashboard/settings_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/settings_controller.rb
# frozen_string_literal: true

module Dashboard
  class SettingsController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!
    before_action :require_admin_or_owner!, only: [:users]

    def show
      @enabled_modules = FeatureModule.enabled_for_customer(current_customer.id).by_name
    end

    def customer
      @customer_record = current_customer
    end

    def users
      @users = Authentication::User.where(customer_id: current_customer.id).by_name
    end

    def module_config
      @feature_module = FeatureModule.find_by!(key: params[:module_key])
      raise ActionController::RoutingError, "Not Found" unless FeatureModule.enabled?(
        key: @feature_module.key, customer_id: current_customer.id
      )
      @customer_feature_module = CustomerFeatureModule.find_by!(
        customer_id: current_customer.id, feature_module_id: @feature_module.id
      )
    end

    private

    def current_dashboard_section = :settings
    helper_method :current_dashboard_section

    def require_admin_or_owner!
      return if current_user.admin_or_owner?
      redirect_to dashboard_settings_path(current_customer.id), alert: "Admin access required."
    end
  end
end
```

```erb
<%# app/views/dashboard/settings/show.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [{ label: "Settings", path: nil }]) %>
<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
  <%= render Dashboard::QuickActionCardComponent.new(label: "Customer Profile", description: "Organization details", path: "/#{current_customer.id}/dashboard/settings/customer") %>
  <% if current_user.admin_or_owner? %>
    <%= render Dashboard::QuickActionCardComponent.new(label: "Users",  description: "Manage teammates",        path: "/#{current_customer.id}/dashboard/settings/users") %>
  <% end %>
  <% @enabled_modules.each do |fm| %>
    <%= render Dashboard::QuickActionCardComponent.new(label: fm.name, description: fm.description.to_s.presence || "Configure #{fm.name}", path: "/#{current_customer.id}/dashboard/settings/modules/#{fm.key}") %>
  <% end %>
</div>
```

```erb
<%# app/views/dashboard/settings/customer.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [
  { label: "Settings", path: "/#{current_customer.id}/dashboard/settings" },
  { label: "Customer Profile", path: nil }
]) %>
<section class="bg-white border border-gray-200 rounded-md p-6">
  <h2 class="text-base font-semibold text-gray-900 mb-4"><%= @customer_record.name %></h2>
  <dl class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
    <div><dt class="text-gray-500">Industry</dt><dd class="text-gray-900"><%= @customer_record.industry.to_s.titleize %></dd></div>
    <div><dt class="text-gray-500">Tier</dt><dd class="text-gray-900"><%= @customer_record.tier.to_s.titleize %></dd></div>
    <div><dt class="text-gray-500">Status</dt><dd class="text-gray-900"><%= @customer_record.status.to_s.titleize %></dd></div>
  </dl>
  <div class="mt-4">
    <%= link_to "Edit", "/#{current_customer.id}/customers/#{current_customer.id}/edit", class: "inline-flex items-center px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 rounded hover:bg-indigo-700" %>
  </div>
</section>
```

```erb
<%# app/views/dashboard/settings/users.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [
  { label: "Settings", path: "/#{current_customer.id}/dashboard/settings" },
  { label: "Users", path: nil }
]) %>
<section class="bg-white border border-gray-200 rounded-md">
  <header class="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
    <h2 class="text-sm font-semibold text-gray-900">Users</h2>
    <%= link_to "Invite user", "/#{current_customer.id}/authentication/admin/users/new", class: "inline-flex items-center px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 rounded hover:bg-indigo-700" %>
  </header>
  <table class="w-full text-sm">
    <thead class="bg-gray-50 text-xs uppercase tracking-wide text-gray-600">
      <tr><th class="text-left px-4 py-2 font-medium">Name</th><th class="text-left px-4 py-2 font-medium">Email</th><th class="text-left px-4 py-2 font-medium">Role</th><th class="text-left px-4 py-2 font-medium">Status</th></tr>
    </thead>
    <tbody class="divide-y divide-gray-100">
      <% @users.each do |u| %>
        <tr class="hover:bg-gray-50">
          <td class="px-4 py-2"><%= u.full_name %></td>
          <td class="px-4 py-2"><%= u.email %></td>
          <td class="px-4 py-2"><%= u.role.to_s.titleize %></td>
          <td class="px-4 py-2"><%= u.status.to_s.titleize %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</section>
```

```erb
<%# app/views/dashboard/settings/module_config.html.erb %>
<%= render Dashboard::BreadcrumbsComponent.new(crumbs: [
  { label: "Settings", path: "/#{current_customer.id}/dashboard/settings" },
  { label: @feature_module.name, path: nil }
]) %>
<section class="bg-white border border-gray-200 rounded-md p-6">
  <h2 class="text-base font-semibold text-gray-900"><%= @feature_module.name %></h2>
  <p class="mt-1 text-sm text-gray-500"><%= @feature_module.description %></p>
  <div class="mt-4">
    <%= link_to "Open full configuration",
          "/#{current_customer.id}/feature_modules/#{@feature_module.id}",
          class: "inline-flex items-center px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 rounded hover:bg-indigo-700" %>
  </div>
</section>
```

- [ ] **Step 4: Run — PASS**

Run: `bundle exec rspec spec/requests/dashboard/settings_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard/settings_controller.rb app/views/dashboard/settings spec/requests/dashboard/settings_spec.rb
git commit -m "Dashboard: SettingsController + index/customer/users/module_config views"
```

---

## Task 29: Strip customer nav from `application.html.erb`

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Replace the header**

Replace lines 22–96 of `app/views/layouts/application.html.erb` (the `<body>` → `<nav>` block) with a minimal owner-only header. Keep the flash rendering and `<%= yield %>`:

```erb
<body class="bg-gray-50 h-screen flex flex-col">
  <header class="bg-white shadow-sm border-b border-gray-200 flex-shrink-0">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex justify-between items-center h-16">
        <%= link_to root_path, class: "flex items-center gap-2 hover:opacity-80" do %>
          <div class="w-8 h-8 bg-indigo-600 rounded-lg flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
            </svg>
          </div>
          <span class="text-xl font-bold text-gray-900">Anysys</span>
        <% end %>
        <nav class="flex items-center gap-2">
          <% if current_customer_id.present? %>
            <%= link_to "Flowcharts", flowcharts_path(current_customer_id), class: "px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md" %>
            <% if user_signed_in? && (current_user.admin? || current_user.owner?) %>
              <%= link_to "Code Generators", admin_code_generators_path, class: "px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md" %>
            <% end %>
          <% end %>
        </nav>
      </div>
    </div>
  </header>

  <main class="flex-1 overflow-auto">
```

Keep the flash messages block and closing tags intact. (Flash block currently at lines 100–153 — keep verbatim.)

- [ ] **Step 2: Confirm the result is valid**

Run: `bundle exec rspec spec/requests/dashboard/landing_spec.rb`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "Dashboard: strip customer nav from application layout (owner-only header)"
```

---

## Task 30: Delete obsolete `feature_modules` nav remnants

(These were deleted in Task 14; this task exists only to catch any missed references. Execution detail:)

- [ ] **Step 1: Grep for lingering references**

```bash
grep -rn "nav_contributions\|NavContributionsComponent\|FeatureModules::NavItem" app/ config/ spec/
```

Expected: empty.

- [ ] **Step 2: If hits appear, remove them and run full suite**

```bash
bundle exec rspec
```

- [ ] **Step 3: Commit if needed (probably nothing to commit).**

---

## Task 31: Frontend-design polish pass

The components built in Tasks 15–21 use deliberately neutral Tailwind styling that matches D12 (enterprise/Linear-like). Before shipping, apply one focused polish pass using the `frontend-design` plugin.

- [ ] **Step 1: Start the Rails dev server and open the dashboard**

```bash
bundle exec rails s
# Visit http://localhost:3000/<customer_id>
```

- [ ] **Step 2: Invoke frontend-design**

From the Copilot CLI, invoke `frontend-design` and ask it to refine only the `app/components/dashboard/*` views. Constraints to pass:

- Tailwind-only. No custom CSS, no new dependencies.
- Preserve all Stimulus targets and data-action attributes (UI interactions must keep working).
- Do not change component public API (initializers, attr_readers).
- Aim for: tighter typography, subtle hover states, consistent spacing scale (4/8/12/16/24), improved focus rings, refined sidebar indentation and active indicator, polished empty-states.
- Keep behavior identical; only visual refinement.

- [ ] **Step 3: After each component refactor, run its spec**

```bash
bundle exec rspec spec/components/dashboard
```

Expected: all PASS. If any fail due to class-list assertions, update the spec assertion minimally (DOM structure changes OK as long as functional assertions hold).

- [ ] **Step 4: Smoke-test in the browser**

Visit:
- `/<cid>` (landing)
- `/<cid>/dashboard/entity_entries`
- `/<cid>/dashboard/settings`
- `/<cid>/pages` (legacy page rendered under new layout)
- Mobile viewport (≤md): drawer opens/closes, section tabs dropdown works.

- [ ] **Step 5: Commit**

```bash
git add app/components/dashboard spec/components/dashboard
git commit -m "Dashboard: frontend-design polish pass (typography, spacing, focus rings)"
```

---

## Task 32: Full-suite verification

- [ ] **Step 1: Run the entire RSpec suite**

```bash
bundle exec rspec
```

Expected: 0 failures. The codegen baseline before this work was 4331 examples (spec/services/code_generators); new suite must not regress that number. New tasks add ~200+ examples.

- [ ] **Step 2: Grep for leftover TODOs or placeholders in new code**

```bash
grep -rn "TODO\|FIXME\|TBD" app/services/dashboard app/components/dashboard app/controllers/dashboard app/views/dashboard
```

Expected: empty output (none in new dashboard code).

- [ ] **Step 3: Boot the app once and hit key routes via curl or browser**

```bash
bundle exec rails server &
SERVER_PID=$!
sleep 4
# Replace 12345678 with a real customer ID from seeds
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/12345678         # expect 200 or 302 (login)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/12345678/dashboard/entity_entries  # expect 200 or 302
kill $SERVER_PID
```

- [ ] **Step 4: Final commit if any loose ends**

```bash
git status
# If nothing to commit, we're done.
```

---

## Self-review (run after plan is drafted; fix issues inline)

**Spec coverage:**

| Spec requirement | Covered by |
|---|---|
| D1 primary-side grouping | Task 3, 5 |
| D2 pages mirror hierarchy | Task 6 |
| D3 Modules = entries; Settings = configs | Tasks 8, 9 |
| D4 sidebar_contributions hook | Task 7 |
| D5 per-item permitted_by | Tasks 1, 2, 9 |
| D6 full responsive | Tasks 16, 17 |
| D7 landing page | Task 25 |
| D8 landing stats incl. activity | Tasks 11, 12, 19, 25 |
| D9 top-right user dropdown only | Task 16 |
| D10 Settings contents | Tasks 9, 28 |
| D11 framework-owned entries table | Tasks 13, 20, 27 |
| D12 visual style | Task 31 |
| D13 Dashboard:: component namespace | Tasks 15–21 |
| D14 full cut-over | Tasks 22, 23, 29 |
| D15 contributor pattern | Tasks 4, 10 |

**Placeholder scan:** No "TBD / TODO / implement later" in plan body; all code blocks are complete.

**Type consistency:** `SidebarNode`, `SidebarTree`, `SidebarBuilder`, `ModuleContribution`, `DashboardContext`, `ModuleEntriesResolver` signatures consistent across tasks. `permitted_for?`/`permitted_by` naming consistent. `admin_or_owner?` predicate defined in Task 9 before it is used in Task 28/22's allowlist.

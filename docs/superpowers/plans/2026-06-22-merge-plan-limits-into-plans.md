# Merge Plan Limits into Plans CRUD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
>
> **WORKING ON `master`: do NOT run `git commit` or `git push`.** Leave all changes in the working tree for the user to review and commit. Where a task says "Commit", instead just ensure the targeted specs pass.

**Goal:** Fold the standalone Plan Limits grid into the plans CRUD — limits show as columns in the list, display on show, and are configured together with pricing on a single edit/new page — and keep the sidebar "Billing" item active across all billing tabs.

**Architecture:** Limits stay in `Billing::PlanLimit` (joined to `Billing::CountableItem.key`); a new `Billing::AssignPlanLimits` service upserts them and is called from `PlansController` create/update. The plans list/show/form components gain an `items:` input. The standalone plan_limits page/controller/route/nav-tab are deleted. Sidebar active-state gains an opt-in `match_prefix` so the Billing leaf matches the whole `…/billing` subtree.

**Tech Stack:** Rails 8.1, RSpec, ViewComponent, Tailwind, Reform.

---

## File Structure

- `app/services/billing/assign_plan_limits.rb` — NEW upsert service.
- `app/controllers/admin/maintenance/platform/billing/plans_controller.rb` — load `@items`; persist limits in create/update.
- `app/components/billing/admin/plan_table_component.{rb,html.erb}` — limit columns.
- `app/components/billing/admin/plan_form_component.{rb,html.erb}` — limit inputs.
- `app/views/admin/maintenance/platform/billing/plans/show.html.erb` — limit section.
- `app/services/sidebar_node.rb` — `match_prefix` attribute.
- `app/components/sidebar_node_component.rb` — prefix-aware `active?`.
- `app/services/maintenance_contributor.rb` — `match_prefix` on Billing leaf.
- DELETE: `plan_limits_controller.rb`, `plan_limits/show.html.erb`, `plan_limits_form_component.{rb,html.erb}`, the route, the nav tab.
- Specs alongside each.

---

## Task 1: `Billing::AssignPlanLimits` service

**Files:**
- Create: `app/services/billing/assign_plan_limits.rb`
- Test: `spec/services/billing/assign_plan_limits_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/billing/assign_plan_limits_spec.rb
require "rails_helper"

RSpec.describe Billing::AssignPlanLimits do
  let(:plan) { Billing::Plan.create!(code: "p1", name: "P1", amount_usd_cents: 0, amount_cny_cents: 0, interval: "monthly") }

  before do
    Billing::CountableItem.find_or_create_by!(key: "flowchart") { |i| i.label = "Flowcharts"; i.enabled = true }
    Billing::CountableItem.find_or_create_by!(key: "page")      { |i| i.label = "Pages";      i.enabled = true }
  end

  it "creates limits for submitted enabled item keys" do
    described_class.call(plan: plan, limits: { "flowchart" => "3", "page" => "5" })
    expect(plan.reload.limit_for("flowchart")).to eq(3)
    expect(plan.limit_for("page")).to eq(5)
  end

  it "treats blank, -1, and 'unlimited' as UNLIMITED" do
    described_class.call(plan: plan, limits: { "flowchart" => "", "page" => "unlimited" })
    expect(plan.reload.limit_for("flowchart")).to eq(Billing::PlanLimit::UNLIMITED)
    expect(plan.limit_for("page")).to eq(Billing::PlanLimit::UNLIMITED)
  end

  it "updates an existing limit instead of duplicating" do
    described_class.call(plan: plan, limits: { "flowchart" => "3" })
    described_class.call(plan: plan, limits: { "flowchart" => "9" })
    expect(plan.reload.plan_limits.where(item_key: "flowchart").count).to eq(1)
    expect(plan.limit_for("flowchart")).to eq(9)
  end

  it "ignores unknown / disabled item keys" do
    described_class.call(plan: plan, limits: { "bogus" => "7" })
    expect(plan.reload.plan_limits.where(item_key: "bogus")).to be_empty
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/billing/assign_plan_limits_spec.rb`
Expected: FAIL (service undefined).

- [ ] **Step 3: Implement the service**

```ruby
# app/services/billing/assign_plan_limits.rb
# frozen_string_literal: true

module Billing
  # Upserts a plan's countable-item limits from a { item_key => raw_value } hash.
  # Blank / "-1" / "unlimited" (case-insensitive) map to PlanLimit::UNLIMITED.
  # Only keys belonging to enabled countable items are accepted.
  class AssignPlanLimits
    def self.call(plan:, limits:)
      new(plan:, limits:).call
    end

    def initialize(plan:, limits:)
      @plan   = plan
      @limits = limits || {}
    end

    def call
      allowed = Billing::CountableItem.enabled.pluck(:key).to_set
      @limits.each do |item_key, raw_value|
        key = item_key.to_s
        next unless allowed.include?(key)

        record = Billing::PlanLimit.find_or_initialize_by(billing_plan_id: @plan.id, item_key: key)
        record.limit_value = parse(raw_value)
        record.save!
      end
      @plan
    end

    private

    def parse(raw)
      return Billing::PlanLimit::UNLIMITED if raw.blank?
      return Billing::PlanLimit::UNLIMITED if raw.to_s.strip.casecmp("unlimited").zero?

      int = raw.to_i
      int == -1 ? Billing::PlanLimit::UNLIMITED : int
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/billing/assign_plan_limits_spec.rb`
Expected: PASS.

---

## Task 2: Sidebar `match_prefix` (Billing active across tabs)

**Files:**
- Modify: `app/services/sidebar_node.rb`
- Modify: `app/components/sidebar_node_component.rb`
- Modify: `app/services/maintenance_contributor.rb`
- Test: `spec/components/sidebar_node_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/sidebar_node_component_spec.rb
require "rails_helper"

RSpec.describe SidebarNodeComponent, type: :component do
  def node(path:, match_prefix: nil)
    SidebarNode.new(key: "k", label: "Billing", menu_item: :maintenance, path: path, match_prefix: match_prefix)
  end

  it "is active on the exact path" do
    c = described_class.new(node: node(path: "/1/admin/maintenance/platform/billing/plans"),
                            current_path: "/1/admin/maintenance/platform/billing/plans")
    expect(c.active?).to be(true)
  end

  it "is active on a sibling billing tab when match_prefix is set" do
    n = node(path: "/1/admin/maintenance/platform/billing/plans",
             match_prefix: "/1/admin/maintenance/platform/billing")
    c = described_class.new(node: n, current_path: "/1/admin/maintenance/platform/billing/coupons")
    expect(c.active?).to be(true)
  end

  it "does not over-activate a non-matching path" do
    n = node(path: "/1/admin/maintenance/platform/billing/plans",
             match_prefix: "/1/admin/maintenance/platform/billing")
    c = described_class.new(node: n, current_path: "/1/admin/maintenance/platform/module_settings")
    expect(c.active?).to be(false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/sidebar_node_component_spec.rb`
Expected: FAIL (`match_prefix` keyword unknown).

- [ ] **Step 3: Add `match_prefix` to `SidebarNode`**

In `app/services/sidebar_node.rb`:
- Add `:match_prefix` to `attr_reader`.
- Add `match_prefix: nil` to `initialize` keywords and `@match_prefix = match_prefix`.
- Add `match_prefix: match_prefix` to the `with_children` rebuild.

```ruby
  attr_reader :key, :label, :path, :icon, :badge, :menu_item, :children,
              :permitted_by, :section_root, :match_prefix

  def initialize(key:, label:, menu_item:, path: nil, icon: nil, badge: nil,
                 children: [], permitted_by: nil, section_root: false, match_prefix: nil)
    unless MENU_ITEMS.include?(menu_item)
      raise ArgumentError, "menu_item must be one of #{MENU_ITEMS}"
    end
    @key = key
    @label = label
    @menu_item = menu_item
    @path = path
    @icon = icon
    @badge = badge
    @children = children
    @permitted_by = permitted_by
    @section_root = section_root
    @match_prefix = match_prefix
  end
```

And in `with_children`:

```ruby
  def with_children(new_children)
    SidebarNode.new(
      key: key, label: label, menu_item: menu_item, path: path, icon: icon,
      badge: badge, children: new_children, permitted_by: permitted_by,
      section_root: section_root, match_prefix: match_prefix
    )
  end
```

- [ ] **Step 4: Make `active?`/`child_active?` prefix-aware**

In `app/components/sidebar_node_component.rb`:

```ruby
  def active?
    path_active?(node)
  end

  def descendant_active?
    node.children.any? { |child| child_active?(child) }
  end
```

Add a private helper and update `child_active?`:

```ruby
  private

  def path_active?(n)
    return true if n.path.present? && current_path == n.path
    prefix = n.match_prefix
    return false if prefix.blank?

    current_path == prefix || current_path.start_with?("#{prefix}/")
  end

  def child_active?(n)
    return true if path_active?(n)
    n.children.any? { |child| child_active?(child) }
  end
```

- [ ] **Step 5: Set `match_prefix` on the Billing leaf**

In `app/services/maintenance_contributor.rb`, change the Billing leaf to pass a match_prefix. First extend `leaf` to accept it:

```ruby
  def leaf(label, path, icon = nil, match_prefix: nil)
    SidebarNode.new(key: "maintenance.#{label.downcase.gsub(' ', '_')}", label: label,
                    menu_item: MENU_ITEM, path: path, icon: icon, match_prefix: match_prefix)
  end
```

Then the Billing node:

```ruby
        leaf("Billing", "/#{customer_id}/admin/maintenance/platform/billing/plans", ICONS[:billing],
             match_prefix: "/#{customer_id}/admin/maintenance/platform/billing"),
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/sidebar_node_component_spec.rb`
Expected: PASS.

---

## Task 3: Plan list — limit columns

**Files:**
- Modify: `app/components/billing/admin/plan_table_component.rb`
- Modify: `app/components/billing/admin/plan_table_component.html.erb`
- Modify: `app/controllers/admin/maintenance/platform/billing/plans_controller.rb` (`index`)
- Modify: `app/views/admin/maintenance/platform/billing/plans/index.html.erb` (pass `items:`)
- Test: `spec/components/billing/admin/plan_table_component_spec.rb`

- [ ] **Step 1: Write the failing component test**

```ruby
# spec/components/billing/admin/plan_table_component_spec.rb
require "rails_helper"

RSpec.describe Billing::Admin::PlanTableComponent, type: :component do
  let(:plan) { Billing::Plan.create!(code: "pro", name: "Pro", amount_usd_cents: 2900, amount_cny_cents: 19900, interval: "monthly") }
  let(:flow) { Billing::CountableItem.create!(key: "flowchart", label: "Flowcharts", enabled: true) }
  let(:page) { Billing::CountableItem.create!(key: "page", label: "Pages", enabled: true) }

  before { Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "flowchart", limit_value: 3) }

  it "renders a column per item with the limit value and ∞ for unlimited" do
    render = render_inline(described_class.new(plans: [plan], items: [flow, page], customer_id: "1"))
    expect(render.to_html).to include("Flowcharts")
    expect(render.to_html).to include("Pages")
    expect(render.to_html).to include("3")    # flowchart limit
    expect(render.to_html).to include("∞")    # page has no limit row → unlimited
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/billing/admin/plan_table_component_spec.rb`
Expected: FAIL (constructor has no `items:`).

- [ ] **Step 3: Add `items` to the component**

In `plan_table_component.rb`:

```ruby
      def initialize(plans:, customer_id:, items: [])
        @plans       = plans
        @customer_id = customer_id.to_s
        @items       = items
      end

      attr_reader :plans, :customer_id, :items

      # Display string for a plan/item limit cell: the integer, or ∞ when unlimited.
      def limit_display(plan, item)
        value = plan.limit_for(item.key)
        value == Billing::PlanLimit::UNLIMITED ? "∞" : value.to_s
      end
```

- [ ] **Step 4: Render the item columns**

In `plan_table_component.html.erb`, add header cells after the `Price (CNY)` header:

```erb
          <% items.each do |item| %>
            <th class="px-4 py-3 text-right"><%= item.label %></th>
          <% end %>
```

And in the body row, after the CNY price `<td>`:

```erb
            <% items.each do |item| %>
              <td class="px-4 py-3 text-right text-body text-text-secondary tabular-nums">
                <%= limit_display(plan, item) %>
              </td>
            <% end %>
```

Also update the empty-state `colspan` from `8` to `8 + items.size`:

```erb
            <td colspan="<%= 8 + items.size %>" class="px-4 py-12 text-center text-body-sm text-text-secondary">
```

- [ ] **Step 5: Load items in the controller + pass to the component**

In `plans_controller.rb#index`:

```ruby
          def index
            @plans = ::Billing::Plan.ordered.includes(:plan_limits)
            @items = ::Billing::CountableItem.enabled.ordered
          end
```

In `plans/index.html.erb`, change the render call:

```erb
    <%= render Billing::Admin::PlanTableComponent.new(plans: @plans, items: @items, customer_id: current_customer_id) %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/billing/admin/plan_table_component_spec.rb`
Expected: PASS.

---

## Task 4: Single-page edit/new — pricing + limits

**Files:**
- Modify: `app/components/billing/admin/plan_form_component.rb`
- Modify: `app/components/billing/admin/plan_form_component.html.erb`
- Modify: `app/controllers/admin/maintenance/platform/billing/plans_controller.rb` (`new`, `create`, `edit`, `update`)
- Modify: `app/views/admin/maintenance/platform/billing/plans/{edit,new}.html.erb` (pass `items:`)
- Test: `spec/requests/admin/maintenance/platform/billing/plans_spec.rb`, `spec/components/billing/admin/plan_form_component_spec.rb`

- [ ] **Step 1: Write the failing request test**

```ruby
# spec/requests/admin/maintenance/platform/billing/plans_spec.rb
require "rails_helper"

RSpec.describe "platform billing plans + limits", type: :request do
  let(:cid) { 81721200 }
  before do
    Billing::CountableItem.find_or_create_by!(key: "flowchart") { |i| i.label = "Flowcharts"; i.enabled = true }
    sign_in_platform_owner # use the codebase's real platform-owner helper
  end

  it "create persists pricing and limits" do
    post "/#{cid}/admin/maintenance/platform/billing/plans", params: {
      billing_plan: {
        code: "starter", name: "Starter", amount_usd_cents: 900, amount_cny_cents: 6900,
        interval: "monthly", trial_days: 0, position: 1, active: "1",
        limits: { "flowchart" => "10" }
      }
    }
    plan = Billing::Plan.find_by!(code: "starter")
    expect(plan.amount_usd_cents).to eq(900)
    expect(plan.limit_for("flowchart")).to eq(10)
  end

  it "update changes limits" do
    plan = Billing::Plan.create!(code: "pro", name: "Pro", amount_usd_cents: 2900, amount_cny_cents: 19900, interval: "monthly")
    patch "/#{cid}/admin/maintenance/platform/billing/plans/#{plan.id}", params: {
      billing_plan: { code: "pro", name: "Pro", amount_usd_cents: 2900, amount_cny_cents: 19900,
                      interval: "monthly", limits: { "flowchart" => "unlimited" } }
    }
    expect(plan.reload.limit_for("flowchart")).to eq(Billing::PlanLimit::UNLIMITED)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/billing/plans_spec.rb`
Expected: FAIL (limits not persisted). Align `sign_in_platform_owner` with the real helper used by the platform request specs in this repo.

- [ ] **Step 3: Persist limits in the controller**

In `plans_controller.rb`, set `@items` for the form actions and assign limits after save:

```ruby
          def new
            @plan  = ::Billing::Plan.new
            @items = ::Billing::CountableItem.enabled.ordered
          end

          def create
            @plan = ::Billing::Plan.new
            @items = ::Billing::CountableItem.enabled.ordered
            contract = ::Billing::Contracts::Plan.new(@plan)
            if contract.validate(plan_params)
              contract.save
              ::Billing::AssignPlanLimits.call(plan: @plan, limits: submitted_limits)
              redirect_to admin_maintenance_platform_billing_plans_path(current_customer_id),
                          notice: "Plan '#{@plan.name}' created."
            else
              @contract = contract
              render :new, status: :unprocessable_entity
            end
          end

          def edit
            @items = ::Billing::CountableItem.enabled.ordered
          end

          def update
            @items = ::Billing::CountableItem.enabled.ordered
            contract = ::Billing::Contracts::Plan.new(@plan)
            if contract.validate(plan_params)
              contract.save
              ::Billing::AssignPlanLimits.call(plan: @plan, limits: submitted_limits)
              redirect_to admin_maintenance_platform_billing_plans_path(current_customer_id),
                          notice: "Plan '#{@plan.name}' updated."
            else
              @contract = contract
              render :edit, status: :unprocessable_entity
            end
          end
```

Add the private helper (leave `plan_params` unchanged — the contract must not receive `limits`):

```ruby
          def submitted_limits
            params.fetch(:billing_plan, {}).permit(limits: {})[:limits] || {}
          end
```

Also set `@items` in `show`:

```ruby
          def show
            @items = ::Billing::CountableItem.enabled.ordered
          end
```

- [ ] **Step 4: Run request test to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/billing/plans_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write the form component test**

```ruby
# spec/components/billing/admin/plan_form_component_spec.rb
require "rails_helper"

RSpec.describe Billing::Admin::PlanFormComponent, type: :component do
  let(:plan) { Billing::Plan.create!(code: "pro", name: "Pro", amount_usd_cents: 2900, amount_cny_cents: 19900, interval: "monthly") }
  let(:flow) { Billing::CountableItem.create!(key: "flowchart", label: "Flowcharts", enabled: true) }

  before { Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "flowchart", limit_value: 7) }

  it "renders a limit input per item pre-filled with the current value" do
    render = render_inline(described_class.new(plan: plan, items: [flow], customer_id: "1"))
    input = render.css('input[name="billing_plan[limits][flowchart]"]').first
    expect(input).to be_present
    expect(input["value"]).to eq("7")
  end
end
```

- [ ] **Step 6: Run it to verify it fails**

Run: `bundle exec rspec spec/components/billing/admin/plan_form_component_spec.rb`
Expected: FAIL (no `items:`).

- [ ] **Step 7: Add limits section to the form component**

In `plan_form_component.rb`:

```ruby
      def initialize(plan:, customer_id:, items: [])
        @plan        = plan
        @customer_id = customer_id.to_s
        @items       = items
      end

      attr_reader :plan, :customer_id, :items

      # Pre-fill value for an item's limit input: blank when unlimited/absent.
      def limit_input_value(item)
        value = plan.limit_for(item.key)
        value == Billing::PlanLimit::UNLIMITED ? "" : value.to_s
      end
```

In `plan_form_component.html.erb`, add a second card before the action buttons (inside the `form_with` block, after the active/default checkboxes `div`):

```erb
    <fieldset class="border-t border-border-subtle pt-5">
      <legend class="text-subheading mb-1">Plan limits</legend>
      <p class="text-caption mb-4">Leave blank for unlimited (∞). Enter a whole number to cap usage.</p>
      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <% items.each do |item| %>
          <div>
            <label class="form-label" for="billing_plan_limits_<%= item.key %>"><%= item.label %></label>
            <input type="number" min="-1" step="1"
                   id="billing_plan_limits_<%= item.key %>"
                   name="billing_plan[limits][<%= item.key %>]"
                   value="<%= limit_input_value(item) %>"
                   placeholder="∞ unlimited"
                   class="mt-1 input-field">
          </div>
        <% end %>
      </div>
    </fieldset>
```

- [ ] **Step 8: Pass `items` from the edit/new views**

In `plans/edit.html.erb` and `plans/new.html.erb`, change the render to:

```erb
  <%= render Billing::Admin::PlanFormComponent.new(
    plan:        @plan,
    items:       @items,
    customer_id: current_customer_id
  ) %>
```

- [ ] **Step 9: Run component test to verify it passes**

Run: `bundle exec rspec spec/components/billing/admin/plan_form_component_spec.rb`
Expected: PASS.

---

## Task 5: Show page — limits section

**Files:**
- Modify: `app/views/admin/maintenance/platform/billing/plans/show.html.erb`
- (controller `show` already sets `@items` from Task 4 Step 3)

- [ ] **Step 1: Add the limits card to show**

Append, inside the `AdminPageComponent` block after the existing details `card`:

```erb
  <div class="card p-6 mt-4">
    <h2 class="section-header mb-3">Plan Limits</h2>
    <dl class="grid grid-cols-1 gap-x-6 gap-y-3 text-body-sm sm:grid-cols-2 lg:grid-cols-4">
      <% @items.each do |item| %>
        <div>
          <dt class="text-text-tertiary font-medium"><%= item.label %></dt>
          <dd class="text-text-primary tabular-nums">
            <% v = @plan.limit_for(item.key) %>
            <%= v == Billing::PlanLimit::UNLIMITED ? "∞" : v %>
          </dd>
        </div>
      <% end %>
    </dl>
  </div>
```

- [ ] **Step 2: Verify render**

Run the request spec covering show, or boot the server and load
`/81721200/admin/maintenance/platform/billing/plans/<id>`; confirm the limits
section renders with ∞ for unlimited.

---

## Task 6: Remove the standalone Plan Limits surface

**Files:**
- Delete: `app/controllers/admin/maintenance/platform/billing/plan_limits_controller.rb`
- Delete: `app/views/admin/maintenance/platform/billing/plan_limits/show.html.erb`
- Delete: `app/components/billing/admin/plan_limits_form_component.rb`
- Delete: `app/components/billing/admin/plan_limits_form_component.html.erb`
- Modify: `config/routes.rb` (remove the `resource :plan_limits` line)
- Modify: `app/components/billing/admin/platform_billing_nav_component.rb` (remove the `:plan_limits` tab)
- Delete/rewrite any spec referencing plan_limits.

- [ ] **Step 1: Remove the route**

In `config/routes.rb`, delete the line:

```ruby
            resource  :plan_limits,     only: %i[show update], controller: "plan_limits"
```

- [ ] **Step 2: Remove the nav tab**

In `platform_billing_nav_component.rb`, delete the TABS entry:

```ruby
        { key: :plan_limits,     label: "Plan Limits",     path_helper: :admin_maintenance_platform_billing_plan_limits_path,     segment: "plan_limits" },
```

- [ ] **Step 3: Delete the controller, view, and component files**

```bash
rm app/controllers/admin/maintenance/platform/billing/plan_limits_controller.rb
rm app/views/admin/maintenance/platform/billing/plan_limits/show.html.erb
rm app/components/billing/admin/plan_limits_form_component.rb
rm app/components/billing/admin/plan_limits_form_component.html.erb
```

- [ ] **Step 4: Find and remove stale references**

Run: `grep -rn "plan_limits\|PlanLimitsForm\|PlanLimitsController" app spec config`
Expected: no remaining references except `Billing::PlanLimit` (the model, kept) and `plan_limits` association usage. Delete or rewrite any spec that targets the removed page/component/route (stale-test policy).

- [ ] **Step 5: Verify the nav + routes load**

Run: `bundle exec rspec spec/components/billing/admin/platform_billing_nav_component_spec.rb 2>/dev/null; bin/rails routes -g billing | grep -i plan`
Expected: only the `plans` resource routes remain (no `plan_limits`); nav spec (if present) green after rewrite.

---

## Task 7: Regression

- [ ] **Step 1: Run the touched suites**

Run:
```
bundle exec rspec \
  spec/services/billing/assign_plan_limits_spec.rb \
  spec/components/sidebar_node_component_spec.rb \
  spec/components/billing/admin/plan_table_component_spec.rb \
  spec/components/billing/admin/plan_form_component_spec.rb \
  spec/requests/admin/maintenance/platform/billing/plans_spec.rb \
  spec/requests/admin/maintenance/platform/billing \
  spec/services/billing
```
Expected: all PASS (rewrite any stale plan_limits specs first).

- [ ] **Step 2: Smoke**

Boot the server and load the plans index, a plan show, a plan edit
(`/81721200/admin/maintenance/platform/billing/plans/<id>/edit`), and another
billing tab (e.g. coupons). Confirm: limit columns on the list, limits section
on show, pricing+limits on one edit page, and the sidebar "Billing" item active
on every billing tab.

---

## Task 8: Customer billing settings — separate pages, no tabs

Context: the customer Settings sidebar (`SettingsContributor`) ALREADY exposes
Billing → Subscription Plan / Payment Method / Invoices as three separate child
nodes, each linking to its own page. The `BillingSettingsNavComponent` tab strip
rendered on top of those pages is redundant. Remove it so each sub-item is purely
its own page, navigated via the sidebar.

**Files:**
- Modify: `app/views/admin/settings/billing/subscriptions/show.html.erb`
- Modify: `app/views/admin/settings/billing/payment_methods/index.html.erb`
- Modify: `app/views/admin/settings/billing/invoices/index.html.erb`
- Modify: `app/views/admin/settings/billing/invoices/show.html.erb`
- Delete: `app/components/billing/admin/billing_settings_nav_component.rb`
- Delete: `app/components/billing/admin/billing_settings_nav_component.html.erb`
- Modify: `app/services/settings_contributor.rb` (Invoices child `match_prefix`)
- Delete/rewrite any spec referencing `BillingSettingsNavComponent`.

- [ ] **Step 1: Remove the tab render from all four views**

In each of the four views, delete the `<%= render Billing::Admin::BillingSettingsNavComponent.new(...) %>`
call (it spans the `render ... .new(` ... `) %>` lines — remove the whole call).
Leave the rest of each page intact.

- [ ] **Step 2: Keep the Invoices sidebar item active on the invoice show page**

The invoice show page is `/…/billing/invoices/:id`, but the sidebar child uses
exact-path matching against `/…/billing/invoices`. Add `match_prefix` (from
Task 2) to the Invoices child in `settings_contributor.rb` so it stays active on
show:

```ruby
        SidebarNode.new(
          key:          "settings.billing.invoices",
          label:        "Invoices",
          menu_item:    MENU_ITEM,
          path:         "/#{customer_id}/admin/settings/billing/invoices",
          match_prefix: "/#{customer_id}/admin/settings/billing/invoices"
        )
```

(Subscription Plan and Payment Method are single pages — exact match already
works; no change needed.)

- [ ] **Step 3: Delete the component**

```bash
rm app/components/billing/admin/billing_settings_nav_component.rb
rm app/components/billing/admin/billing_settings_nav_component.html.erb
```

- [ ] **Step 4: Remove stale references**

Run: `grep -rn "BillingSettingsNavComponent" app spec`
Expected: no matches. Delete/rewrite any spec referencing it (stale-test policy).

- [ ] **Step 5: Verify**

Run: `bundle exec rspec spec/requests/admin/settings/billing 2>/dev/null`
Then boot the server and load each of `/…/admin/settings/billing/subscription`,
`/payment_methods`, `/invoices`, and an invoice show — confirm no tab strip, each
is its own page, and the matching sidebar item is highlighted (including on
invoice show).

---

## Self-Review Notes

- **Spec coverage:** AssignPlanLimits → T1; sidebar active → T2; list columns → T3; single-page edit/new + persistence → T4; show section → T5; remove standalone surface → T6; regression → T7.
- **Type consistency:** `limit_for(item.key)` and `PlanLimit::UNLIMITED` used consistently; component constructors all gain `items:` with a `[]` default so any un-migrated caller still renders. `submitted_limits` reads `params[:billing_plan][:limits]`, matching the form field name `billing_plan[limits][<key>]`.
- **No commits on master:** every "verify" step is a spec run, not a commit. Leave changes for the user.

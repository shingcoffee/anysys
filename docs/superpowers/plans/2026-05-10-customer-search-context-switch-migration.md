# Customer Search & Context Switch — Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the platform-owner customer-search dropdown and Act-As customer-context-switch entry point off the admin top bar and into the existing Maintenance / Platform / Customers index page, with live tokenized search across `id`/`name`/`alias` and a per-row Act-As button.

**Architecture:** Replace `Customer.search_by_name` with a broader `Customer.search` scope (whitespace-tokenized, AND across tokens, OR across `id`/`name`/`alias` per token). Add a new `CustomerSearchFormComponent` (form + Stimulus controller) above the customers table; wrap the table in a Turbo Frame so live keystroke search re-renders only that frame. Add an "Act As" button to each customer row that hits the existing `customer_context#update` endpoint. Delete the topbar `Platform::CustomerSwitcherComponent`, its Stimulus controller, the JSON `customer_context_searches` controller and route, and their specs. Keep `CustomerContextsController` and the amber `Platform::ContextBannerComponent` untouched.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, StimulusJS, TailwindCSS, Turbo Frames, RSpec, SQLite.

**Spec:** `docs/superpowers/specs/2026-05-10-customer-search-context-switch-migration-design.md`

---

## File Map

**Created:**
- `app/components/customer_search_form_component.rb`
- `app/components/customer_search_form_component.html.erb`
- `app/javascript/controllers/customer_search_controller.js`
- `spec/components/customer_search_form_component_spec.rb`

**Modified:**
- `app/models/customer.rb` — replace `search_by_name` with `search`
- `app/controllers/admin/maintenance/platform/customers_controller.rb` — call new scope
- `app/controllers/customers_controller.rb` — call new scope (root-level customer selection)
- `app/views/admin/maintenance/platform/customers/index.html.erb` — render search form + Turbo Frame; branch empty state
- `app/components/customer_list_table_component.rb` — add `act_as_button_visible?`
- `app/components/customer_list_table_component.html.erb` — add Act-As button to Actions column
- `app/components/topbar_component.html.erb` — remove `Platform::CustomerSwitcherComponent` render
- `config/routes.rb` — delete `customer_context_searches` route
- `spec/models/customer_spec.rb` — replace `.search_by_name` describe block with `.search`
- `spec/components/customer_list_table_component_spec.rb` — add Act-As visibility coverage

**Deleted:**
- `app/components/platform/customer_switcher_component.rb`
- `app/components/platform/customer_switcher_component.html.erb`
- `app/javascript/controllers/platform_customer_switcher_controller.js`
- `app/controllers/admin/maintenance/platform/customer_context_searches_controller.rb`
- `spec/components/platform/customer_switcher_component_spec.rb`

---

## Task 1: Replace `Customer.search_by_name` with `Customer.search` (model + tests)

**Files:**
- Modify: `app/models/customer.rb` (scopes block around line 189)
- Modify: `spec/models/customer_spec.rb` (existing `.search_by_name` describe block, lines 232-248)

- [ ] **Step 1: Replace the existing `.search_by_name` describe block with `.search` cases**

In `spec/models/customer_spec.rb`, find the existing block:

```ruby
    describe '.search_by_name' do
      it 'finds customers matching the query' do
        customers = Customer.search_by_name('alpha')
        expect(customers.count).to eq(1)
        expect(customers.first.name).to eq('Alpha Inc')
      end

      it 'returns all customers when query is blank' do
        customers = Customer.search_by_name('')
        expect(customers.count).to eq(3)
      end

      it 'is case insensitive' do
        customers = Customer.search_by_name('ZEBRA')
        expect(customers.count).to eq(1)
      end
    end
```

Replace it with:

```ruby
    describe '.search' do
      let!(:acme) { Customer.create!(valid_attributes.merge(name: 'Acme Corp', alias: 'AC')) }
      let!(:other) { Customer.create!(valid_attributes.merge(name: 'Other Inc', alias: 'globex')) }

      it 'returns all customers when query is blank' do
        expect(Customer.search('').count).to eq(Customer.count)
      end

      it 'returns all customers when query is whitespace only' do
        expect(Customer.search("   \t  ").count).to eq(Customer.count)
      end

      it 'finds customers by name token (case-insensitive)' do
        names = Customer.search('ZEBRA').pluck(:name)
        expect(names).to contain_exactly('Zebra Corp')
      end

      it 'finds customers by alias token' do
        names = Customer.search('globex').pluck(:name)
        expect(names).to contain_exactly('Other Inc')
      end

      it 'finds a customer by exact id when token is all digits' do
        names = Customer.search(acme.id.to_s).pluck(:name)
        expect(names).to include('Acme Corp')
      end

      it 'all-digits token also matches name/alias substrings containing those digits' do
        digit = Customer.create!(valid_attributes.merge(name: 'Route66', alias: 'r66'))
        names = Customer.search('66').pluck(:name)
        expect(names).to include('Route66')
      end

      it 'mixed alphanumeric token does not match by id' do
        names = Customer.search('xyz123').pluck(:name)
        expect(names).to be_empty
      end

      it 'multi-token AND across name and alias' do
        Customer.create!(valid_attributes.merge(name: 'Acme Foo', alias: 'BAR'))
        names = Customer.search('acme bar').pluck(:name)
        expect(names).to contain_exactly('Acme Foo')
      end

      it 'multi-token AND with no row matching every token returns empty' do
        names = Customer.search('alpha zebra').pluck(:name)
        expect(names).to be_empty
      end
    end
```

- [ ] **Step 2: Run the spec to confirm it fails (scope not yet renamed)**

Run: `bundle exec rspec spec/models/customer_spec.rb -e ".search"`
Expected: FAIL — `NoMethodError: undefined method 'search' for Customer` (or similar).

- [ ] **Step 3: Replace the scope in the model**

In `app/models/customer.rb`, find:

```ruby
  scope :search_by_name, ->(query) {
    return all if query.blank?

    where("LOWER(name) LIKE ?", "%#{query.downcase}%")
  }
```

Replace with:

```ruby
  scope :search, ->(query) {
    return all if query.blank?

    tokens = query.to_s.downcase.split(/\s+/).reject(&:blank?)
    return all if tokens.empty?

    tokens.inject(all) do |relation, token|
      pat = "%#{token}%"
      if token.match?(/\A\d+\z/)
        relation.where(
          'LOWER(name) LIKE :pat OR LOWER("alias") LIKE :pat OR id = :id',
          pat: pat, id: token.to_i
        )
      else
        relation.where(
          'LOWER(name) LIKE :pat OR LOWER("alias") LIKE :pat',
          pat: pat
        )
      end
    end
  }
```

- [ ] **Step 4: Run the model spec to confirm it passes**

Run: `bundle exec rspec spec/models/customer_spec.rb`
Expected: PASS — all `.search` cases green; the rest of the file unchanged.

- [ ] **Step 5: Commit**

```bash
git add app/models/customer.rb spec/models/customer_spec.rb
git commit -m "refactor(customer): replace search_by_name with tokenized search across id/name/alias"
```

---

## Task 2: Update both `search_by_name` callers to use the new `search` scope

**Files:**
- Modify: `app/controllers/admin/maintenance/platform/customers_controller.rb:18`
- Modify: `app/controllers/customers_controller.rb:12`

- [ ] **Step 1: Update Maintenance/Platform/Customers index controller**

In `app/controllers/admin/maintenance/platform/customers_controller.rb`, find:

```ruby
      @customers = @customers.search_by_name(params[:search]) if params[:search].present?
```

Replace with:

```ruby
      @customers = @customers.search(params[:search]) if params[:search].present?
```

- [ ] **Step 2: Update root customers selection controller**

In `app/controllers/customers_controller.rb`, find:

```ruby
    @customers = @customers.search_by_name(params[:search]) if params[:search].present?
```

Replace with:

```ruby
    @customers = @customers.search(params[:search]) if params[:search].present?
```

- [ ] **Step 3: Verify no other callers of `search_by_name` exist on `Customer`**

Run: `grep -rn 'Customer.*search_by_name\|@customers.*search_by_name' app spec config`
Expected output: empty (the only `search_by_name` references that remain should be on `Entity` and `Page`, not `Customer`).

- [ ] **Step 4: Run the request spec for Customers index to confirm nothing broke**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/customers_spec.rb` (if file exists; otherwise the broader maintenance request specs).
If no spec exists, run a quick smoke test:
`bundle exec rails runner 'puts Customer.search("a").count'`
Expected: succeeds without error.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/platform/customers_controller.rb app/controllers/customers_controller.rb
git commit -m "refactor: route customer search through new Customer.search scope"
```

---

## Task 3: Create the `customer-search` Stimulus controller

**Files:**
- Create: `app/javascript/controllers/customer_search_controller.js`

- [ ] **Step 1: Write the controller**

Create `app/javascript/controllers/customer_search_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Debounces input changes and submits the wrapping <form>.
// The form has data-turbo-frame=... so Turbo swaps only the frame.
export default class extends Controller {
  static values = { wait: { type: Number, default: 250 } }

  connect() {
    this.timer = null
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  submit() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.element.requestSubmit()
    }, this.waitValue)
  }
}
```

- [ ] **Step 2: Verify Stimulus auto-registers the controller**

Run: `grep -n "eagerLoadControllers\|controllers/index" app/javascript/controllers/index.js 2>/dev/null || ls app/javascript/controllers/index.js`
Expected: an `index.js` exists that auto-loads files in `controllers/` (Stimulus convention with `@hotwired/stimulus-loading`). No manual registration needed.

If you discover the project registers controllers manually, add this single line in the right place:
```javascript
import CustomerSearchController from "./customer_search_controller"
application.register("customer-search", CustomerSearchController)
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/customer_search_controller.js
git commit -m "feat(js): add customer-search stimulus controller for debounced form submit"
```

---

## Task 4: Create `CustomerSearchFormComponent` (failing spec → impl)

**Files:**
- Create: `spec/components/customer_search_form_component_spec.rb`
- Create: `app/components/customer_search_form_component.rb`
- Create: `app/components/customer_search_form_component.html.erb`

- [ ] **Step 1: Write the failing component spec**

Create `spec/components/customer_search_form_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerSearchFormComponent, type: :component do
  let(:tenant_customer) { Customer.create!(name: "Tenant", role: :owner, industry: :technology) }

  it "renders a GET form targeting the customers index" do
    render_inline(described_class.new(customer_id: tenant_customer.id, search: nil))

    form = page.find("form")
    expect(form["method"]).to eq("get")
    expect(form["action"]).to eq("/#{tenant_customer.id}/admin/maintenance/platform/customers")
  end

  it "targets the customers_list Turbo Frame" do
    render_inline(described_class.new(customer_id: tenant_customer.id, search: nil))

    expect(page).to have_css("form[data-turbo-frame='customers_list']")
  end

  it "wires the customer-search Stimulus controller and submit action" do
    render_inline(described_class.new(customer_id: tenant_customer.id, search: nil))

    expect(page).to have_css("form[data-controller='customer-search']")
    expect(page).to have_css("input[name='search'][data-action*='input->customer-search#submit']")
  end

  it "pre-fills the input with the current search value" do
    render_inline(described_class.new(customer_id: tenant_customer.id, search: "acme"))

    expect(page).to have_css("input[name='search'][value='acme']")
  end

  it "renders an empty input when search is nil" do
    render_inline(described_class.new(customer_id: tenant_customer.id, search: nil))

    input = page.find("input[name='search']")
    expect(input["value"].to_s).to eq("")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec rspec spec/components/customer_search_form_component_spec.rb`
Expected: FAIL — `NameError: uninitialized constant CustomerSearchFormComponent`.

- [ ] **Step 3: Create the component class**

Create `app/components/customer_search_form_component.rb`:

```ruby
# frozen_string_literal: true

class CustomerSearchFormComponent < ApplicationComponent
  attr_reader :customer_id, :search

  def initialize(customer_id:, search: nil)
    @customer_id = customer_id
    @search = search
  end

  def form_action
    helpers.admin_maintenance_platform_customers_path(customer_id)
  end
end
```

- [ ] **Step 4: Create the component template**

Create `app/components/customer_search_form_component.html.erb`:

```erb
<form action="<%= form_action %>"
      method="get"
      role="search"
      data-controller="customer-search"
      data-turbo-frame="customers_list"
      class="relative w-full max-w-md">
  <span class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-text-muted">
    <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z"/>
    </svg>
  </span>
  <input type="search"
         name="search"
         value="<%= search %>"
         placeholder="Search customers by name, alias, or ID..."
         autocomplete="off"
         data-action="input->customer-search#submit"
         class="w-full pl-9 pr-3 py-2 text-sm border border-border rounded-md bg-surface placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent">
</form>
```

- [ ] **Step 5: Run the spec to confirm it passes**

Run: `bundle exec rspec spec/components/customer_search_form_component_spec.rb`
Expected: PASS — all 5 examples green.

- [ ] **Step 6: Commit**

```bash
git add app/components/customer_search_form_component.rb \
        app/components/customer_search_form_component.html.erb \
        spec/components/customer_search_form_component_spec.rb
git commit -m "feat(component): add CustomerSearchFormComponent for Maintenance/Platform/Customers"
```

---

## Task 5: Add "Act As" action to `CustomerListTableComponent` (TDD)

**Files:**
- Modify: `spec/components/customer_list_table_component_spec.rb`
- Modify: `app/components/customer_list_table_component.rb`
- Modify: `app/components/customer_list_table_component.html.erb`

- [ ] **Step 1: Add failing tests for the Act-As button visibility**

In `spec/components/customer_list_table_component_spec.rb`, add a new describe block at the bottom of the `describe "rendering"` block (just before its closing `end`):

```ruby
    describe "Act As button" do
      it "renders an Act As button for a normal customer" do
        render_inline(described_class.new(customers: customers, customer_id: tenant_customer.id))
        expect(page).to have_button("Act As")
      end

      it "submits PATCH to customer_context with the target customer id" do
        render_inline(described_class.new(customers: customers, customer_id: tenant_customer.id))
        target = customers.first
        form = page.find(:xpath, "//form[@action='/#{tenant_customer.id}/admin/maintenance/platform/customer_context']", match: :first)
        expect(form.find("input[name='_method']", visible: false)["value"]).to eq("patch")
        expect(form.find("input[name='customer_id']", visible: false)["value"]).to eq(target.id.to_s)
      end

      it "hides Act As when the customer is the platform owner customer (id 81_721_200)" do
        platform = Customer.create!(id: 81_721_200, name: "Platform Owner", role: :owner, industry: :technology)
        render_inline(described_class.new(customers: [platform], customer_id: tenant_customer.id))
        expect(page).not_to have_button("Act As")
      end

      it "hides Act As for the customer currently being acted as" do
        target = customers.first
        allow(Current).to receive(:acting_as_customer).and_return(target)
        render_inline(described_class.new(customers: [target], customer_id: tenant_customer.id))
        expect(page).not_to have_button("Act As")
      end

      it "does not render Act As when show_restore is true (trash view)" do
        customers.each(&:soft_delete)
        render_inline(described_class.new(customers: Customer.only_deleted, show_restore: true, customer_id: tenant_customer.id))
        expect(page).not_to have_button("Act As")
      end
    end
```

- [ ] **Step 2: Run to confirm failure**

Run: `bundle exec rspec spec/components/customer_list_table_component_spec.rb -e "Act As"`
Expected: FAIL — `expected to find button "Act As"`.

- [ ] **Step 3: Add the visibility helper to the Ruby class**

In `app/components/customer_list_table_component.rb`, append before the final `end`:

```ruby
  def act_as_button_visible?(customer)
    return false if show_restore
    return false if customer.id == Authentication::User::PLATFORM_CUSTOMER_ID
    return false if Current.acting_as_customer&.id == customer.id

    true
  end
```

- [ ] **Step 4: Render the Act-As button in the Actions column**

In `app/components/customer_list_table_component.html.erb`, locate the Actions cell. It currently looks like:

```erb
          <td class="px-6 py-4 whitespace-nowrap text-right">
            <% if show_restore %>
              <%= button_to helpers.admin_maintenance_platform_customer_restoration_path(...) %>
              ...
            <% else %>
              <%= link_to helpers.edit_admin_maintenance_platform_customer_path(...) %>
              <%= button_to helpers.admin_maintenance_platform_customer_path(...) %>
            <% end %>
          </td>
```

Insert an Act-As button at the very start of the `<% else %>` branch (before the existing Edit link). The full updated `<% else %>` branch should read:

```erb
            <% else %>
              <% if act_as_button_visible?(customer) %>
                <%= button_to helpers.admin_maintenance_platform_customer_context_path(current_customer_id),
                              method: :patch,
                              params: { customer_id: customer.id },
                              class: "inline-flex items-center px-2.5 py-1 mr-1 text-xs font-medium text-text-secondary border border-border rounded hover:bg-surface-active hover:text-text-primary transition-base",
                              form: { class: "inline" },
                              title: "Act as this customer" do %>
                  Act As
                <% end %>
              <% end %>
              <%= link_to helpers.edit_admin_maintenance_platform_customer_path(current_customer_id, customer),
                  class: "action-icon",
                  title: "Edit" do %>
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
              <% end %>
              <%= button_to helpers.admin_maintenance_platform_customer_path(current_customer_id, customer), method: :delete,
                  class: "action-icon action-icon-danger",
                  title: "Delete",
                  form: { data: { turbo_confirm: "Are you sure you want to delete this customer?" }, class: "inline" } do %>
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              <% end %>
            <% end %>
```

The `<% if show_restore %>` branch above stays exactly as it was — Act-As is only emitted in the non-restore branch.

- [ ] **Step 5: Run the spec to confirm it passes**

Run: `bundle exec rspec spec/components/customer_list_table_component_spec.rb`
Expected: PASS — every example, including the previously-existing ones.

- [ ] **Step 6: Commit**

```bash
git add app/components/customer_list_table_component.rb \
        app/components/customer_list_table_component.html.erb \
        spec/components/customer_list_table_component_spec.rb
git commit -m "feat(customers-table): add Act As action with platform-owner and self-context guards"
```

---

## Task 6: Wire search form + Turbo Frame into the Customers index view

**Files:**
- Modify: `app/views/admin/maintenance/platform/customers/index.html.erb`

- [ ] **Step 1: Replace the index view with the new layout**

Open `app/views/admin/maintenance/platform/customers/index.html.erb` and replace its entire contents with:

```erb
<%# app/views/admin/maintenance/platform/customers/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Settings", path: admin_setting_path(current_customer_id) },
  { label: "Customers", path: nil }
]) %>

<div class="flex items-center justify-between mb-6">
  <div>
    <h1 class="text-subtitle">Customers</h1>
    <p class="mt-1 text-body-sm">Manage tenant accounts</p>
  </div>

  <div class="flex items-center gap-3">
    <%= render ButtonComponent.new(tag: :a, href: trash_admin_maintenance_platform_customers_path(current_customer_id), variant: :ghost, size: :sm) do %>
      <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
      </svg>
      Trash
    <% end %>

    <%= render ButtonComponent.new(tag: :a, href: new_admin_maintenance_platform_customer_path(current_customer_id), variant: :primary, size: :sm) do %>
      <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
      </svg>
      New Customer
    <% end %>
  </div>
</div>

<%# Search form lives OUTSIDE the Turbo Frame so the input keeps focus across swaps. %>
<div class="mb-4">
  <%= render CustomerSearchFormComponent.new(customer_id: current_customer_id, search: params[:search]) %>
</div>

<%= turbo_frame_tag "customers_list" do %>
  <% if @customers.any? %>
    <%= render CustomerListTableComponent.new(customers: @customers, customer_id: current_customer_id) %>
  <% elsif params[:search].present? %>
    <%= render EmptyStateComponent.new(
      title: "No customers match your search",
      description: "Try a different name, alias, or ID.",
      icon_path: "M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z",
      action_path: admin_maintenance_platform_customers_path(current_customer_id),
      action_text: "Clear search"
    ) %>
  <% else %>
    <%= render EmptyStateComponent.new(
      title: "No customers yet",
      description: "Start by adding your first customer.",
      icon_path: "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
      action_path: new_admin_maintenance_platform_customer_path(current_customer_id),
      action_text: "Add First Customer"
    ) %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Run the existing component specs to confirm rendering still works**

Run: `bundle exec rspec spec/components/customer_list_table_component_spec.rb spec/components/customer_search_form_component_spec.rb`
Expected: PASS — all examples green.

- [ ] **Step 3: Smoke-test the route (optional but recommended)**

Run: `bundle exec rails runner 'puts ActionController::Base.helpers.admin_maintenance_platform_customers_path(81_721_200)'`
Expected: prints `/81721200/admin/maintenance/platform/customers`.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/maintenance/platform/customers/index.html.erb
git commit -m "feat(customers-page): add search form and turbo-frame live filtering"
```

---

## Task 6.5: Request spec for Customers index search

**Files:**
- Create: `spec/requests/admin/maintenance/platform/customers_spec.rb`

- [ ] **Step 1: Write the request spec**

Create `spec/requests/admin/maintenance/platform/customers_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Customers", type: :request do
  let!(:platform_customer) { Customer.create!(id: 81_721_200, name: "Platform Owner", role: :owner, industry: :technology) }
  let!(:acme)              { Customer.create!(name: "Acme Corp", alias: "AC", role: :member, industry: :technology) }
  let!(:beta)              { Customer.create!(name: "Beta Inc", alias: "BI", role: :member, industry: :healthcare) }

  let(:platform_owner_user) do
    create(:user, customer: platform_customer, role: :owner, email: "owner-#{SecureRandom.hex(4)}@test.io")
  end

  let(:non_owner_user) do
    other = Customer.create!(name: "Other", role: :member, industry: :technology)
    create(:user, customer: other, role: :member, email: "regular-#{SecureRandom.hex(4)}@test.io")
  end

  let(:index_path) { "/#{platform_customer.id}/admin/maintenance/platform/customers" }

  describe "GET /index as platform owner" do
    before { sign_in platform_owner_user }

    it "returns 200 and lists all customers when search is blank" do
      get index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("Beta Inc")
    end

    it "filters by name token" do
      get index_path, params: { search: "acme" }
      expect(response.body).to include("Acme Corp")
      expect(response.body).not_to include("Beta Inc")
    end

    it "filters by alias token (case-insensitive)" do
      get index_path, params: { search: "BI" }
      expect(response.body).to include("Beta Inc")
      expect(response.body).not_to include("Acme Corp")
    end

    it "filters by exact id when query is all digits" do
      get index_path, params: { search: acme.id.to_s }
      expect(response.body).to include("Acme Corp")
      expect(response.body).not_to include("Beta Inc")
    end

    it "renders the search-empty state when no customer matches" do
      get index_path, params: { search: "zzz-no-match-zzz" }
      expect(response.body).to include("No customers match your search")
    end
  end

  describe "GET /index as a non-platform-owner user" do
    before { sign_in non_owner_user }

    it "is denied" do
      get index_path
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end
end
```

If the project uses a sign-in helper other than Devise's `sign_in` (check `spec/support` for Warden/Devise/custom helpers), substitute the correct helper. If `FactoryBot` factories don't yet include `:user`, fall back to `Authentication::User.create!(...)` with the minimal required attributes inline; do not adjust factories from this task.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/customers_spec.rb`
Expected: PASS — all five "as platform owner" cases plus the deny case green.

If the deny case fails because the controller redirects with status 200 after the redirect resolves, the `.or have_http_status(:forbidden)` allows either; the original controller behavior (`format.html { redirect_to ..., alert: ... }`) gives `:redirect`.

- [ ] **Step 3: Commit**

```bash
git add spec/requests/admin/maintenance/platform/customers_spec.rb
git commit -m "test(customers): add request spec for tokenized search and platform-owner gate"
```

---

## Task 7: Remove the topbar Customer Switcher render call

**Files:**
- Modify: `app/components/topbar_component.html.erb` (line 36)

- [ ] **Step 1: Delete the switcher render line**

In `app/components/topbar_component.html.erb`, find:

```erb
      <%= render Platform::CustomerSwitcherComponent.new(user: user, customer_id: customer.id) %>
```

Delete that single line. The surrounding lines (HelpMenuComponent, NotificationsButtonComponent, UserMenuComponent) stay as they are.

- [ ] **Step 2: Verify topbar tests (if any) still pass**

Run: `bundle exec rspec spec/components/topbar_component_spec.rb 2>/dev/null || echo "no topbar spec"`
Expected: PASS or "no topbar spec".

- [ ] **Step 3: Commit**

```bash
git add app/components/topbar_component.html.erb
git commit -m "refactor(topbar): remove customer switcher (migrated to Customers page)"
```

---

## Task 8: Delete the switcher component, controller, search endpoint, and their specs

**Files:**
- Delete: `app/components/platform/customer_switcher_component.rb`
- Delete: `app/components/platform/customer_switcher_component.html.erb`
- Delete: `app/javascript/controllers/platform_customer_switcher_controller.js`
- Delete: `app/controllers/admin/maintenance/platform/customer_context_searches_controller.rb`
- Delete: `spec/components/platform/customer_switcher_component_spec.rb`
- Modify: `config/routes.rb` (remove the `customer_context_searches` line)

- [ ] **Step 1: Verify no other code references these files**

Run:
```bash
grep -rn "CustomerSwitcherComponent\|platform_customer_switcher\|CustomerContextSearchesController\|customer_context_searches" app spec config lib 2>/dev/null
```

Expected after this task: only the lines we are about to delete should appear. Take note of any other reference; if one exists, stop and surface it before continuing.

- [ ] **Step 2: Remove the `customer_context_searches` route**

In `config/routes.rb`, find:

```ruby
          resources :customer_context_searches, only: :index, controller: "maintenance/platform/customer_context_searches"
```

Delete that line. The `resource :customer_context, ...` line immediately above it stays.

- [ ] **Step 3: Delete the files**

Run:
```bash
rm app/components/platform/customer_switcher_component.rb \
   app/components/platform/customer_switcher_component.html.erb \
   app/javascript/controllers/platform_customer_switcher_controller.js \
   app/controllers/admin/maintenance/platform/customer_context_searches_controller.rb \
   spec/components/platform/customer_switcher_component_spec.rb
```

- [ ] **Step 4: Confirm clean state**

Run:
```bash
grep -rn "CustomerSwitcherComponent\|platform_customer_switcher\|CustomerContextSearchesController\|customer_context_searches" app spec config lib 2>/dev/null
```
Expected: empty output.

Run:
```bash
bundle exec rails routes | grep -i "customer_context"
```
Expected: only the `customer_context` (PATCH/DELETE) routes remain — no `customer_context_searches`.

- [ ] **Step 5: Run the full spec suite**

Run: `bundle exec rspec`
Expected: PASS — green. (If a spec we missed references the deleted symbols, fix it now: either delete the spec or update its references.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "remove: drop customer switcher component, JSON search endpoint, and their specs"
```

---

## Task 9: Verification — assets, routes, manual UI sanity check

**Files:** none modified; verification only.

- [ ] **Step 1: Verify the route table**

Run: `bundle exec rails routes | grep -E 'customer_context|maintenance/platform/customers' | head -20`
Expected: shows `customer_context` (PATCH/DELETE) and `customers` index/show/new/edit/create/update/destroy/trash routes; **no** `customer_context_searches`.

- [ ] **Step 2: Run the full RSpec suite once more**

Run: `bundle exec rspec`
Expected: green.

- [ ] **Step 3: Restart the dev server with a fresh asset manifest**

Run:
```bash
rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000
```

Use `run_in_background: true` if running through a tool harness that supports it.

- [ ] **Step 4: Manual UI check — top bar**

In a browser, log in as a user with customer_id `81721200` and role `owner`. Visit any admin page (e.g. `/81721200/admin/dashboard`).

Expected:
- Top bar shows logo, Cmd+K search, help, notifications, user menu.
- The people-icon "Switch Customer" button is **gone**.

- [ ] **Step 5: Manual UI check — Customers page search**

Navigate to `/81721200/admin/maintenance/platform/customers`.

Expected:
- A search input appears above the table with placeholder "Search customers by name, alias, or ID...".
- Typing a partial name filters the table without a full-page reload (the URL updates with `?search=...`).
- Typing an existing customer's id (e.g. `81721200`) finds that row.
- Clearing the input shows the full list again.
- Empty state when no match: "No customers match your search" with a "Clear search" button.

- [ ] **Step 6: Manual UI check — Act As**

In the customers table:
- A small "Act As" button appears at the start of the Actions column for normal customer rows.
- The platform-owner customer row (id 81721200) has **no** "Act As" button.
- Click "Act As" on a non-platform customer.

Expected:
- Browser navigates to that customer's admin dashboard.
- The amber "Platform Admin Mode — Acting as ..." banner appears at the top.
- Clicking "Return to Platform" on the banner returns to the platform owner's dashboard and the banner disappears.

- [ ] **Step 7: Manual UI check — currently-acting-as guard**

While acting as a customer, navigate back to `/81721200/admin/maintenance/platform/customers` (the URL still uses 81721200 because the platform-owner constraints route there).

Expected:
- The row for the customer you are currently acting as has **no** "Act As" button (it would be a no-op).

- [ ] **Step 8: If anything fails the manual check**

- If the search input loses focus on every keystroke, the input is rendered inside the Turbo Frame by mistake — re-check Task 6 Step 1 and confirm the form's `<div>` sits **before** the `turbo_frame_tag` block.
- If the Act-As button POSTs to the wrong URL, recheck the path helper in Task 5 Step 4 (`admin_maintenance_platform_customer_context_path(current_customer_id)`).
- If `Current.acting_as_customer` blows up in tests, confirm `Current` is the `ActiveSupport::CurrentAttributes` instance the `TenantContext` concern already exposes; the component spec uses `allow(Current).to receive(:acting_as_customer)` which should work without any setup.

- [ ] **Step 9: Final commit (only if any small follow-up fixes were needed)**

If verification surfaced minor fixes, commit them as a single follow-up:

```bash
git add -A
git commit -m "fix: address verification findings for customer search migration"
```

If verification was clean, no commit is needed for this task.

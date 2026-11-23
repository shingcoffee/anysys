# Module Status/Required Toggles + Payment Tenders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the platform owner two per-module toggles (Status default-inactive, Required-requires-active) with User Authentication permanently mandatory; let the owner control which payment tenders are available to all customers; and merge the customer payment "Gateway" stub into the Merchant Accounts page.

**Architecture:** `FeatureModules::Module.status` defaults to inactive and is owner-toggleable; the registration DSL's `mandatory!` replaces `required!` and `register!` stops clobbering owner-set state. Payment tender availability lives in a new on-demand `Payments::PlatformGateway` row per provider (default unavailable), mirroring `Captcha::ProviderSettings.for_provider`. The customer gallery and provisioner filter to available tenders.

**Tech Stack:** Rails 8.1, RSpec, ViewComponent, Tailwind, Stimulus, Trailblazer/Reform (existing patterns).

---

## File Structure

- `app/models/feature_modules/module.rb` — status default inactive, `mandatory?`, hard-gate scopes.
- `app/services/feature_modules/base_module.rb` — `mandatory!`/`mandatory?` DSL, non-clobbering `register!`.
- `app/services/feature_modules/authentication/registration.rb` — `required!`→`mandatory!`.
- `app/services/feature_modules/email/registration.rb` — drop the mandatory declaration.
- `app/controllers/admin/maintenance/platform/module_settings_controller.rb` — list all modules, status+required update guards.
- `app/components/admin/maintenance/platform/module_toggle_component.{rb,html.erb}` — reusable toggle switch (NEW).
- `app/views/admin/maintenance/platform/module_settings/index.html.erb` — status + required badges.
- `app/views/admin/maintenance/platform/module_settings/show.html.erb` — Status card + gated Required card; payment tenders section.
- `db/migrate/<ts>_create_payment_platform_gateways.rb` + `app/models/payments/platform_gateway.rb` — platform tender availability store (NEW).
- `app/controllers/admin/maintenance/platform/payments/platform_gateways_controller.rb` — owner toggle action (NEW).
- `config/routes.rb` — nested route for platform gateway toggle.
- `app/services/feature_modules/payment/provisioner.rb` — seed only available tenders.
- `app/components/payments/admin/gateway_gallery_component.rb` (+ caller) — filter to available tenders.
- `app/services/feature_modules/payment/registration.rb` — remove dead "Gateway" sidebar stub.
- Specs alongside each.

---

## Task 1: Module status defaults to inactive

**Files:**
- Modify: `app/models/feature_modules/module.rb`
- Test: `spec/models/feature_modules/module_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/feature_modules/module_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::Module do
  describe "status default" do
    it "defaults a new module to inactive" do
      fm = described_class.new(key: "demo", name: "Demo")
      expect(fm.status).to eq("inactive")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/feature_modules/module_spec.rb -e "status default"`
Expected: FAIL (status is "active").

- [ ] **Step 3: Change the enum default**

In `app/models/feature_modules/module.rb`:

```ruby
enum :status, { active: 0, inactive: 1 }, default: :inactive
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/feature_modules/module_spec.rb -e "status default"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/feature_modules/module.rb spec/models/feature_modules/module_spec.rb
git commit -m "feat(modules): default feature module status to inactive"
```

---

## Task 2: `mandatory!`/`mandatory?` DSL + non-clobbering `register!`

**Files:**
- Modify: `app/services/feature_modules/base_module.rb`
- Modify: `app/services/feature_modules/authentication/registration.rb:10`
- Modify: `app/services/feature_modules/email/registration.rb:10`
- Modify: `app/models/feature_modules/module.rb` (add `mandatory?`)
- Test: `spec/services/feature_modules/base_module_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/feature_modules/base_module_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::BaseModule do
  def build_registration(key, mandatory:)
    Class.new(described_class) do
      define_singleton_method(:module_key)  { key }
      define_singleton_method(:module_name) { key.titleize }
      mandatory! if mandatory
      def self.provision!(_c) = nil
    end
  end

  describe ".register!" do
    it "seeds a brand-new non-mandatory module as inactive + optional" do
      reg = build_registration("seed_demo", mandatory: false)
      reg.register!
      fm = FeatureModules::Module.find_by!(key: "seed_demo")
      expect(fm.status).to eq("inactive")
      expect(fm.required).to be(false)
    end

    it "forces a mandatory module active + required" do
      reg = build_registration("seed_auth", mandatory: true)
      reg.register!
      fm = FeatureModules::Module.find_by!(key: "seed_auth")
      expect(fm.status).to eq("active")
      expect(fm.required).to be(true)
    end

    it "preserves owner-set status/required on an existing non-mandatory module" do
      reg = build_registration("seed_keep", mandatory: false)
      reg.register!
      FeatureModules::Module.find_by!(key: "seed_keep").update!(status: :active, required: true)
      reg.register! # boot again
      fm = FeatureModules::Module.find_by!(key: "seed_keep")
      expect(fm.status).to eq("active")
      expect(fm.required).to be(true)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: FAIL (`mandatory!` undefined / register! clobbers).

- [ ] **Step 3: Implement DSL + register! in `base_module.rb`**

Replace the `required!`/`required?` methods and `register!`:

```ruby
      # Mark this module permanently active + required for every customer.
      # Mandatory modules are not owner-toggleable (e.g. User Authentication).
      def mandatory!
        @mandatory = true
      end

      def mandatory?
        @mandatory == true
      end

      # Register or update the FeatureModules::Module record WITHOUT clobbering
      # owner-managed status/required on existing rows.
      def register!
        fm = ::FeatureModules::Module.find_or_initialize_by(key: module_key)
        fm.name                  = module_name
        fm.description           = module_description
        fm.configuration_schema  = configuration_schema.to_json

        if mandatory?
          fm.status   = :active
          fm.required = true
        elsif fm.new_record?
          fm.status   = :inactive
          fm.required = false
        end
        # else: preserve persisted owner-set status/required.

        fm.save!
      end
```

- [ ] **Step 4: Update the two registrations**

In `authentication/registration.rb` change `required!` → `mandatory!`.
In `email/registration.rb` **delete** the `required! # Auto-enabled for all customers` line.

- [ ] **Step 5: Add `mandatory?` to the model**

In `app/models/feature_modules/module.rb`:

```ruby
    def mandatory?
      registration_class.respond_to?(:mandatory?) && registration_class.mandatory?
    end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/feature_modules/ app/models/feature_modules/module.rb spec/services/feature_modules/base_module_spec.rb
git commit -m "feat(modules): mandatory! DSL replaces required!; register! preserves owner state"
```

---

## Task 3: Hard-gate inactive modules in enabled scopes

**Files:**
- Modify: `app/models/feature_modules/module.rb` (`enabled_for_customer`, `enabled?`)
- Test: `spec/models/feature_modules/module_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  describe "inactive hard-gate" do
    let(:customer) { Customer.create!(id: 700001, name: "T") }

    it "treats an inactive module as not enabled even with an active assignment" do
      fm = described_class.create!(key: "gate", name: "Gate", status: :active)
      FeatureModules::CustomerAssignment.create!(
        customer: customer, feature_module: fm, status: :active
      )
      expect(described_class.enabled?(key: "gate", customer_id: customer.id)).to be(true)

      fm.update!(status: :inactive)
      expect(described_class.enabled?(key: "gate", customer_id: customer.id)).to be(false)
    end
  end
```

(Adjust `Customer.create!` attrs to the minimal valid set in this codebase.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/feature_modules/module_spec.rb -e "inactive hard-gate"`
Expected: FAIL (inactive module still reports enabled).

- [ ] **Step 3: Add status gate to the scope**

In `app/models/feature_modules/module.rb`, change `enabled_for_customer`:

```ruby
    scope :enabled_for_customer, ->(customer_id) {
      return none if customer_id.blank?

      where(status: :active)
        .joins(:customer_feature_modules)
        .where(customer_feature_modules: { customer_id: customer_id, status: :active })
    }
```

`enabled?` already delegates to `enabled_for_customer`, so it inherits the gate.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/feature_modules/module_spec.rb -e "inactive hard-gate"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/feature_modules/module.rb spec/models/feature_modules/module_spec.rb
git commit -m "feat(modules): hard-gate inactive modules in enabled scopes"
```

---

## Task 4: `ModuleToggleComponent` (reusable switch)

**Files:**
- Create: `app/components/admin/maintenance/platform/module_toggle_component.rb`
- Create: `app/components/admin/maintenance/platform/module_toggle_component.html.erb`
- Test: `spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/admin/maintenance/platform/module_toggle_component_spec.rb
require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleToggleComponent, type: :component do
  def toggle(**opts)
    render_inline(described_class.new(url: "/x", field: "status", on: false, **opts))
  end

  it "renders an off switch as a submittable form" do
    render = toggle(on: false)
    expect(render.css("form").any?).to be(true)
    expect(render.css("button[role=switch][aria-checked=false]").any?).to be(true)
  end

  it "renders a disabled switch without a form when disabled" do
    render = toggle(disabled: true)
    expect(render.css("form").any?).to be(false)
    expect(render.css("button[disabled]").any?).to be(true)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`
Expected: FAIL (component undefined).

- [ ] **Step 3: Implement the component class**

```ruby
# app/components/admin/maintenance/platform/module_toggle_component.rb
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # A single on/off toggle switch that PATCHes `url` with `field`=1/0.
      # When `disabled` it renders a static (non-submitting) switch — used for
      # mandatory modules and for Required while a module is inactive.
      class ModuleToggleComponent < ApplicationComponent
        def initialize(url:, field:, on:, disabled: false, confirm: nil, on_label: "On", off_label: "Off")
          @url = url
          @field = field
          @on = on
          @disabled = disabled
          @confirm = confirm
          @on_label = on_label
          @off_label = off_label
        end

        attr_reader :url, :field, :on, :disabled, :confirm, :on_label, :off_label

        def on? = @on
        def disabled? = @disabled
        def next_value = on? ? "0" : "1"

        def track_classes
          base = "relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
          state = on? ? "bg-accent" : "bg-border"
          cursor = disabled? ? "opacity-50 cursor-not-allowed" : "cursor-pointer"
          "#{base} #{state} #{cursor}"
        end

        def knob_classes
          pos = on? ? "translate-x-5" : "translate-x-0"
          "#{pos} pointer-events-none inline-block h-5 w-5 transform rounded-full bg-surface shadow ring-0 transition duration-200 ease-in-out"
        end

        def label
          on? ? on_label : off_label
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement the template**

```erb
<%# app/components/admin/maintenance/platform/module_toggle_component.html.erb %>
<div class="flex items-center gap-3">
  <% if disabled? %>
    <button type="button" disabled class="<%= track_classes %>" role="switch" aria-checked="<%= on? %>">
      <span class="<%= knob_classes %>"></span>
    </button>
  <% else %>
    <%= form_with url: url, method: :patch, local: true, class: "inline" do %>
      <input type="hidden" name="<%= field %>" value="<%= next_value %>">
      <button type="submit"
              <%= "data-turbo-confirm=#{confirm.inspect}".html_safe if confirm.present? %>
              class="<%= track_classes %>" role="switch" aria-checked="<%= on? %>">
        <span class="<%= knob_classes %>"></span>
      </button>
    <% end %>
  <% end %>
  <span class="text-body-sm text-text-primary"><%= label %></span>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/admin/maintenance/platform/module_toggle_component.rb app/components/admin/maintenance/platform/module_toggle_component.html.erb spec/components/admin/maintenance/platform/module_toggle_component_spec.rb
git commit -m "feat(modules): add reusable ModuleToggleComponent"
```

---

## Task 5: Controller — list all modules + status/required guards

**Files:**
- Modify: `app/controllers/admin/maintenance/platform/module_settings_controller.rb`
- Test: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

- [ ] **Step 1: Write the failing request test**

```ruby
# spec/requests/admin/maintenance/platform/module_settings_spec.rb
require "rails_helper"

RSpec.describe "Platform module settings", type: :request do
  # Use the platform-owner customer 81721200 and an owner user.
  # Reuse existing auth helpers/factories in this codebase (sign_in_as_owner etc.).

  let(:cid) { 81721200 }
  let!(:fm) { FeatureModules::Module.create!(key: "demo", name: "Demo", status: :inactive, required: false) }

  before { sign_in_platform_owner }  # replace with the codebase's owner sign-in helper

  it "activates a module" do
    patch "/#{cid}/admin/maintenance/platform/module_settings/#{fm.id}", params: { status_active: "1" }
    expect(fm.reload.status).to eq("active")
  end

  it "refuses to mark required while inactive" do
    patch "/#{cid}/admin/maintenance/platform/module_settings/#{fm.id}", params: { required: "1" }
    expect(fm.reload.required).to be(false)
  end

  it "forces required false when deactivating" do
    fm.update!(status: :active, required: true)
    patch "/#{cid}/admin/maintenance/platform/module_settings/#{fm.id}", params: { status_active: "0" }
    fm.reload
    expect(fm.status).to eq("inactive")
    expect(fm.required).to be(false)
  end

  it "rejects changes to a mandatory module" do
    auth = FeatureModules::Module.find_by(key: "authentication")
    patch "/#{cid}/admin/maintenance/platform/module_settings/#{auth.id}", params: { status_active: "0" }
    expect(auth.reload.status).to eq("active")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: FAIL (current update only handles `required`).

- [ ] **Step 3: Rewrite `index` and `update`**

```ruby
    def index
      @available_modules = FeatureModules::Module.by_name
    end

    def update
      @feature_module = FeatureModules::Module.find(params[:id])

      if @feature_module.mandatory?
        return redirect_back_with("#{@feature_module.name} is always active and required and cannot be changed.")
      end

      apply_status! if params.key?(:status_active)
      apply_required! if params.key?(:required)

      redirect_to show_path, notice: "#{@feature_module.name} updated."
    rescue StandardError => e
      redirect_to show_path, alert: "Failed to update: #{e.message}"
    end

    private

    def apply_status!
      active = params[:status_active] == "1"
      attrs = { status: active ? :active : :inactive }
      attrs[:required] = false unless active # required implies active
      @feature_module.update!(attrs)
    end

    def apply_required!
      return unless @feature_module.active? # required requires active

      new_required = params[:required] == "1"
      @feature_module.update!(required: new_required)
      provision_required_for_all! if new_required
    end

    def provision_required_for_all!
      Customer.find_each do |customer|
        cfm = FeatureModules::CustomerAssignment.find_or_initialize_by(customer: customer, feature_module: @feature_module)
        next if cfm.persisted? && cfm.active?

        cfm.update!(status: :active, enabled_at: Time.current, configuration: cfm.configuration.presence || {}.to_json)
        @feature_module.registration_class.provision!(customer)
      end
    end

    def show_path
      admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module)
    end

    def redirect_back_with(message)
      redirect_to show_path, alert: message
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: PASS. (If owner sign-in helper differs, align with existing platform request specs first.)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/platform/module_settings_controller.rb spec/requests/admin/maintenance/platform/module_settings_spec.rb
git commit -m "feat(modules): platform owner toggles status + required with guards"
```

---

## Task 6: View — index badges + show Status/Required cards

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/index.html.erb`
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb`

- [ ] **Step 1: Index — already shows both badges**

Confirm `index.html.erb` shows the Required badge (line ~31) and Active/Inactive badge (line ~34). No change needed beyond Task 5's `by_name`. Leave as-is.

- [ ] **Step 2: Show — replace the Required card with Status + gated Required cards**

Replace the "Required Module" card block (lines ~67-104) with:

```erb
<%# Status Setting %>
<div class="card overflow-hidden">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header">Module Status</h2>
  </div>
  <div class="p-6">
    <p class="text-body-sm mb-4">
      When <strong>Active</strong>, this module is available for customers to enable. When <strong>Inactive</strong>, it is hidden and disabled for all customers.
    </p>
    <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
          url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
          field: "status_active",
          on: @feature_module.active?,
          disabled: @feature_module.mandatory?,
          on_label: "Active", off_label: "Inactive"
        ) %>
    <% if @feature_module.mandatory? %>
      <p class="mt-2 text-caption">Locked — this module is always active and required.</p>
    <% end %>
  </div>
</div>

<%# Required Setting (only meaningful when active) %>
<div class="card overflow-hidden">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header">Required Module</h2>
  </div>
  <div class="p-6">
    <p class="text-body-sm mb-4">
      When enabled, this module is activated for <strong>all customers</strong> and cannot be disabled by them. Available only while the module is Active.
    </p>
    <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
          url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
          field: "required",
          on: @feature_module.required?,
          disabled: @feature_module.mandatory? || !@feature_module.active?,
          confirm: @feature_module.required? ? nil : "This will enable the module for ALL existing customers. Continue?",
          on_label: "Required for all customers", off_label: "Optional"
        ) %>
  </div>
</div>
```

NOTE: the Status toggle posts `status_active`=1/0. Update the controller `apply_status!` to read `params[:status_active]` instead of `params[:status]`, OR keep `field: "status"` and map "1"→active in `apply_status!`. Pick ONE and keep controller + view consistent. (Recommended: use `field: "status_active"` and in `apply_status!` do `active = params[:status_active] == "1"`; update the request spec params accordingly.)

- [ ] **Step 3: Manual asset/render check**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` then GET `/81721200/admin/maintenance/platform/module_settings/<id>`; verify Status + Required toggles render and Required is greyed when inactive.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/maintenance/platform/module_settings/ app/controllers/admin/maintenance/platform/module_settings_controller.rb spec/requests/admin/maintenance/platform/module_settings_spec.rb
git commit -m "feat(modules): show Status + gated Required toggles on module settings"
```

---

## Task 7: `Payments::PlatformGateway` store

**Files:**
- Create: `db/migrate/<ts>_create_payment_platform_gateways.rb`
- Create: `app/models/payments/platform_gateway.rb`
- Test: `spec/models/payments/platform_gateway_spec.rb`

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/<ts>_create_payment_platform_gateways.rb
class CreatePaymentPlatformGateways < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_platform_gateways do |t|
      t.string  :provider,  null: false
      t.boolean :available, null: false, default: false
      t.timestamps
    end
    add_index :payment_platform_gateways, :provider, unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Write the failing test**

```ruby
# spec/models/payments/platform_gateway_spec.rb
require "rails_helper"

RSpec.describe Payments::PlatformGateway do
  describe ".for_provider" do
    it "creates an unavailable row on first access" do
      gw = described_class.for_provider("stripe")
      expect(gw.provider).to eq("stripe")
      expect(gw.available).to be(false)
    end
  end

  describe ".available_providers" do
    it "returns only available provider keys" do
      described_class.for_provider("alipay").update!(available: true)
      described_class.for_provider("stripe")
      expect(described_class.available_providers).to include("alipay")
      expect(described_class.available_providers).not_to include("stripe")
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/models/payments/platform_gateway_spec.rb`
Expected: FAIL (model undefined).

- [ ] **Step 4: Implement the model**

```ruby
# app/models/payments/platform_gateway.rb
# frozen_string_literal: true

module Payments
  # Platform-wide availability flag for a payment tender (gateway). One row per
  # provider, created on demand (default unavailable). Mirrors
  # Captcha::ProviderSettings.for_provider — adding a new gateway file needs no
  # migration; its row is created the first time the platform owner views it.
  class PlatformGateway < ApplicationRecord
    self.table_name = "payment_platform_gateways"

    validates :provider, presence: true, uniqueness: true

    def self.for_provider(provider_key)
      find_or_create_by!(provider: provider_key.to_s)
    end

    def self.available_providers
      where(available: true).pluck(:provider)
    end

    def self.available?(provider_key)
      for_provider(provider_key).available?
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/models/payments/platform_gateway_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/payments/platform_gateway.rb spec/models/payments/platform_gateway_spec.rb
git commit -m "feat(payments): platform gateway availability store"
```

---

## Task 8: Platform gateway toggle route + controller

**Files:**
- Modify: `config/routes.rb` (inside `scope :module_settings, as: :module_settings`)
- Create: `app/controllers/admin/maintenance/platform/payments/platform_gateways_controller.rb`
- Test: `spec/requests/admin/maintenance/platform/payments/platform_gateways_spec.rb`

- [ ] **Step 1: Add the route**

Inside the `scope :module_settings, as: :module_settings do` block, add:

```ruby
            namespace :payments, module: "maintenance/platform/payments" do
              resources :platform_gateways, only: :update, param: :provider
            end
```

- [ ] **Step 2: Write the failing request test**

```ruby
# spec/requests/admin/maintenance/platform/payments/platform_gateways_spec.rb
require "rails_helper"

RSpec.describe "Platform gateway availability", type: :request do
  let(:cid) { 81721200 }
  before { sign_in_platform_owner }

  it "enables a tender platform-wide" do
    patch "/#{cid}/admin/maintenance/platform/module_settings/payments/platform_gateways/stripe",
          params: { available: "1" }
    expect(Payments::PlatformGateway.available?("stripe")).to be(true)
  end

  it "disables a tender platform-wide" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    patch "/#{cid}/admin/maintenance/platform/module_settings/payments/platform_gateways/alipay",
          params: { available: "0" }
    expect(Payments::PlatformGateway.available?("alipay")).to be(false)
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/payments/platform_gateways_spec.rb`
Expected: FAIL (controller missing).

- [ ] **Step 4: Implement the controller**

```ruby
# app/controllers/admin/maintenance/platform/payments/platform_gateways_controller.rb
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Payments
        # Platform-owner toggle for whether a payment tender is offered to all
        # customers. Owner-only via RouteAuthorization (platform area). Validates
        # the provider against the gateway registry so unknown keys 404.
        class PlatformGatewaysController < ApplicationController
          dashboard_menu_item :maintenance

          def update
            provider = params[:provider].to_s
            return head :not_found unless ::Payments::Gateways.keys.map(&:to_s).include?(provider)

            ::Payments::PlatformGateway.for_provider(provider)
              .update!(available: params[:available] == "1")

            redirect_to admin_maintenance_platform_module_setting_path(
              current_customer_id,
              ::FeatureModules::Module.find_by!(key: "payment")
            ), notice: "Gateway availability updated."
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/payments/platform_gateways_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/maintenance/platform/payments/platform_gateways_controller.rb spec/requests/admin/maintenance/platform/payments/platform_gateways_spec.rb
git commit -m "feat(payments): platform owner toggles tender availability"
```

---

## Task 9: Payment tenders section on module_settings show

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb`
- Modify: `app/controllers/admin/maintenance/platform/module_settings_controller.rb` (`show` loads gateways for payment)

- [ ] **Step 1: Load gateways in `show` for the payment module**

In `module_settings_controller.rb#show`, after existing assignments:

```ruby
      if @feature_module.key == "payment"
        @platform_gateways = Payments::Gateways.all.map do |gw|
          [gw, Payments::PlatformGateway.for_provider(gw.key)]
        end
      end
```

- [ ] **Step 2: Render the tenders card (payment only)**

In `show.html.erb`, after the SMS-specific block, add an analogous payment block:

```erb
<% if @feature_module.key == "payment" %>
  <div class="card overflow-hidden">
    <div class="px-6 py-4 border-b border-border-subtle">
      <h2 class="section-header">Available Tenders</h2>
      <p class="mt-0.5 text-caption">Control which payment gateways customers may enable.</p>
    </div>
    <ul class="divide-y divide-border-subtle">
      <% @platform_gateways.each do |gw, pg| %>
        <li class="flex items-center justify-between gap-4 px-6 py-4">
          <div>
            <h3 class="text-body text-text-primary font-medium"><%= gw.display_name %></h3>
            <p class="text-caption"><%= gw.key %></p>
          </div>
          <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
                url: admin_maintenance_platform_module_settings_payments_platform_gateway_path(current_customer_id, gw.key),
                field: "available",
                on: pg.available?,
                on_label: "Available", off_label: "Unavailable"
              ) %>
        </li>
      <% end %>
    </ul>
  </div>
<% end %>
```

Verify the route helper name with `bin/rails routes -g platform_gateway` and adjust if needed.

- [ ] **Step 3: Manual render check**

GET `/81721200/admin/maintenance/platform/module_settings/<payment_module_id>`; toggle a tender; confirm persistence.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/maintenance/platform/module_settings/show.html.erb app/controllers/admin/maintenance/platform/module_settings_controller.rb
git commit -m "feat(payments): tender availability toggles on payment module settings"
```

---

## Task 10: Filter customer gallery + provisioner to available tenders

**Files:**
- Modify: `app/services/feature_modules/payment/provisioner.rb`
- Modify: `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb` (`index`)
- Test: `spec/services/feature_modules/payment/provisioner_spec.rb` (create if absent), `spec/requests/.../merchant_accounts_spec.rb`

- [ ] **Step 1: Write the failing provisioner test**

```ruby
# spec/services/feature_modules/payment/provisioner_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::Payment::Provisioner do
  let(:customer) { Customer.create!(id: 700010, name: "P") } # minimal valid attrs

  it "seeds accounts only for platform-available tenders" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    # stripe + wechat_pay left unavailable
    described_class.call(customer)
    providers = Payments::MerchantAccount.unscoped_by_tenant.where(customer_id: customer.id).distinct.pluck(:provider)
    expect(providers).to contain_exactly("alipay")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/feature_modules/payment/provisioner_spec.rb`
Expected: FAIL (all gateways seeded).

- [ ] **Step 3: Filter the provisioner**

In `provisioner.rb`, change the iterated set:

```ruby
      def self.call(customer)
        available = Payments::PlatformGateway.available_providers.map(&:to_s)
        Payments::Gateways.keys.each do |provider|
          next unless available.include?(provider.to_s)

          MODES.each do |mode|
            Payments::MerchantAccount.unscoped_by_tenant.find_or_create_by!(
              customer_id: customer.id, provider: provider.to_s, mode: mode
            ) do |acc|
              acc.merchant_id = "unset-#{provider}-#{mode}-#{customer.id}"
              acc.status      = "disabled"
            end
          end
        end
      end
```

- [ ] **Step 4: Filter the gallery `index`**

In `merchant_accounts_controller.rb#index`, filter the gateways passed to the gallery:

```ruby
          def index
            accounts = ::Payments::MerchantAccount.for_current_customer.order(:provider, :mode)
            accounts_by_provider = accounts.group_by(&:provider).transform_values do |rows|
              rows.find { |r| r.enabled? } || rows.find { |r| r.mode == "sandbox" } || rows.first
            end
            available = ::Payments::PlatformGateway.available_providers.map(&:to_s)
            gateways = ::Payments::Gateways.all.select { |g| available.include?(g.key.to_s) }
            render ::Payments::Admin::GatewayGalleryComponent.new(
              gateways:             gateways,
              accounts_by_provider: accounts_by_provider
            )
          end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/payment/provisioner_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/feature_modules/payment/provisioner.rb app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb spec/services/feature_modules/payment/provisioner_spec.rb
git commit -m "feat(payments): offer only platform-available tenders to customers"
```

---

## Task 11: Remove dead "Gateway" sidebar stub

**Files:**
- Modify: `app/services/feature_modules/payment/registration.rb` (settings contributions)
- Test: existing payment registration spec if present.

- [ ] **Step 1: Remove the stub**

In `registration.rb`, delete the line:

```ruby
            ModuleContribution.new(label: "Gateway", entry_key: "gateway"),
```

so only the "Merchant Accounts" settings contribution remains.

- [ ] **Step 2: Verify no consumers reference the `gateway` entry_key**

Run: `grep -rn '"gateway"' app/ spec/ | grep -i entry`
Expected: no remaining functional references (only the removed line).

- [ ] **Step 3: Run payment registration / sidebar specs**

Run: `bundle exec rspec spec/services/feature_modules/payment`
Expected: PASS (update any spec asserting the old "Gateway" entry per the stale-test policy).

- [ ] **Step 4: Commit**

```bash
git add app/services/feature_modules/payment/registration.rb spec
git commit -m "refactor(payments): merge Gateway into Merchant Accounts (drop dead sidebar stub)"
```

---

## Task 12: Full regression + release smoke

**Files:** none (verification).

- [ ] **Step 1: Run the touched suites**

Run:
```
bundle exec rspec \
  spec/models/feature_modules/module_spec.rb \
  spec/services/feature_modules \
  spec/components/admin/maintenance/platform/module_toggle_component_spec.rb \
  spec/requests/admin/maintenance/platform \
  spec/models/payments/platform_gateway_spec.rb
```
Expected: all PASS.

- [ ] **Step 2: Release smoke**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`, then load module_settings index + payment show + customer merchant_accounts; confirm toggles work and unavailable tenders are hidden from the customer gallery.

- [ ] **Step 3: Commit any spec fixes**

```bash
git add -A && git commit -m "test: regression fixes for module/tender refactor"
```

---

## Self-Review Notes

- **Spec coverage:** Part A → Tasks 1-6; Part B → Tasks 7-9; Part C → Tasks 10-11. Authorization/tenant covered in request specs (Tasks 5, 8).
- **Type consistency:** `mandatory!`/`mandatory?` (DSL) vs model column `required` are distinct and intentional. The Status toggle field name (`status_active`) must match between Task 6 view and Task 5 controller — reconcile to `params[:status_active] == "1"` in `apply_status!` and update the Task 5 spec params from `status: "active"` to `status_active: "1"`.
- **Existing-data note:** brand-new app (no backward compat). On first boot after this change, existing module rows keep their persisted status/required (register! preserves them); only mandatory modules are force-corrected.

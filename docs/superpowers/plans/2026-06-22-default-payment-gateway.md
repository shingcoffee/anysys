# Default Payment Gateway — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Checkbox steps.
>
> **WORKING ON `master`: do NOT `git commit`/`add`/`push`.** Leave changes in the working tree. "Commit" steps = "ensure targeted specs pass" only. For request specs use the codebase's REAL sign-in helpers (inspect existing specs); placeholders like `sign_in_admin` must be replaced with the actual helper/factory.

**Goal:** Let a customer admin pick a default payment gateway (among enabled+configured ones); use it to pre-select/order shopper checkout and as the provider fallback when none is given.

**Architecture:** A dedicated `Payments::DefaultGateway` (one row per customer) set via `Payments::SetDefaultGateway`. Eligibility ("enabled + configured + platform-available") is centralized in `Payments::EligibleGateways` and `MerchantAccount#configured?`. The merchant_accounts gallery gains a Default badge + "Set as default"; the hardcoded checkout becomes a dynamic, default-first gateway list.

**Tech Stack:** Rails 8.1, RSpec, ViewComponent, Tailwind, TenantScoped.

---

## File Structure

- `db/migrate/<ts>_create_payment_default_gateways.rb`, `app/models/payments/default_gateway.rb` — NEW store.
- `app/models/payments/merchant_account.rb` — `configured?`.
- `app/services/payments/eligible_gateways.rb` — NEW eligibility query.
- `app/services/payments/set_default_gateway.rb` — NEW setter.
- `config/routes.rb` — `default_gateway` resource.
- `app/controllers/admin/settings/modules/payments/default_gateways_controller.rb` — NEW.
- `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb` — pass default to gallery.
- `app/components/payments/admin/gateway_gallery_component.{rb,html.erb}`, `gateway_card_component.{rb,html.erb}` — default badge + button.
- `app/components/payments/checkout_component.{rb,html.erb}`, `app/controllers/payments/checkouts_controller.rb` — dynamic gateways.
- Specs alongside.

---

## Task 1: `Payments::DefaultGateway` model + table

**Files:**
- Create: `db/migrate/20260622000002_create_payment_default_gateways.rb`
- Create: `app/models/payments/default_gateway.rb`
- Test: `spec/models/payments/default_gateway_spec.rb`

- [ ] **Step 1: Migration**

```ruby
# db/migrate/20260622000002_create_payment_default_gateways.rb
class CreatePaymentDefaultGateways < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_default_gateways do |t|
      t.bigint :customer_id, null: false
      t.string :provider,    null: false
      t.timestamps
    end
    add_index :payment_default_gateways, :customer_id, unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Failing test**

```ruby
# spec/models/payments/default_gateway_spec.rb
require "rails_helper"

RSpec.describe Payments::DefaultGateway do
  let(:customer) { create(:customer) }

  it "stores one default per customer (unique)" do
    described_class.unscoped_by_tenant.create!(customer_id: customer.id, provider: "alipay")
    dup = described_class.unscoped_by_tenant.new(customer_id: customer.id, provider: "stripe")
    expect(dup).not_to be_valid
  end

  describe ".provider_for" do
    it "returns the stored provider or nil" do
      expect(described_class.provider_for(customer.id)).to be_nil
      described_class.unscoped_by_tenant.create!(customer_id: customer.id, provider: "alipay")
      expect(described_class.provider_for(customer.id)).to eq("alipay")
    end
  end
end
```

- [ ] **Step 3: Run → fail**

Run: `bundle exec rspec spec/models/payments/default_gateway_spec.rb`
Expected: FAIL (model undefined).

- [ ] **Step 4: Implement**

```ruby
# app/models/payments/default_gateway.rb
# frozen_string_literal: true

module Payments
  # One row per customer naming their default payment gateway provider.
  class DefaultGateway < ApplicationRecord
    include TenantScoped

    self.table_name = "payment_default_gateways"

    validates :customer_id, presence: true, uniqueness: true
    validates :provider,    presence: true

    # The stored default provider for a customer, or nil. Bypasses tenant
    # default scope so it works from any context given an explicit id.
    def self.provider_for(customer_id)
      return nil if customer_id.blank?

      unscoped_by_tenant.where(customer_id: customer_id).pick(:provider)
    end
  end
end
```

- [ ] **Step 5: Run → pass**

Run: `bundle exec rspec spec/models/payments/default_gateway_spec.rb`
Expected: PASS. (If `TenantScoped` requires `customer` association or differs, mirror `Payments::MerchantAccount`'s usage.)

---

## Task 2: `MerchantAccount#configured?`

**Files:**
- Modify: `app/models/payments/merchant_account.rb`
- Test: `spec/models/payments/merchant_account_spec.rb`

- [ ] **Step 1: Failing test**

```ruby
# spec/models/payments/merchant_account_spec.rb  (add)
require "rails_helper"

RSpec.describe Payments::MerchantAccount do
  let(:customer) { create(:customer) }

  def acct(status: "active", merchant_id: "M1")
    a = described_class.new(customer_id: customer.id, provider: "alipay", mode: "sandbox",
                            merchant_id: merchant_id, status: status)
    a.write_credentials(private_key_pem: "x", platform_public_key_pem: "y")
    a
  end

  describe "#configured?" do
    it "is true when enabled, real merchant_id, and all credentials present" do
      expect(acct).to be_configured
    end

    it "is false when disabled" do
      expect(acct(status: "disabled")).not_to be_configured
    end

    it "is false for the provisioner placeholder merchant_id" do
      expect(acct(merchant_id: "unset-alipay-sandbox-#{customer.id}")).not_to be_configured
    end

    it "is false when a required credential is missing" do
      a = described_class.new(customer_id: customer.id, provider: "alipay", mode: "sandbox",
                              merchant_id: "M1", status: "active")
      a.write_credentials(private_key_pem: "x") # platform_public_key_pem missing
      expect(a).not_to be_configured
    end
  end
end
```

- [ ] **Step 2: Run → fail**

Run: `bundle exec rspec spec/models/payments/merchant_account_spec.rb -e configured`
Expected: FAIL.

- [ ] **Step 3: Implement** (add to `merchant_account.rb`)

```ruby
    # A gateway is "configured" when it is enabled, has a real (non-placeholder)
    # merchant_id, and every credential field declared by its gateway class has a
    # stored value. Used to decide default-gateway / checkout eligibility.
    def configured?
      return false unless enabled?
      return false if merchant_id.blank? || merchant_id.to_s.start_with?("unset-")

      gateway_class.credential_fields.all? { |f| credential(f[:name]).present? }
    rescue ArgumentError
      false
    end
```

- [ ] **Step 4: Run → pass**

Run: `bundle exec rspec spec/models/payments/merchant_account_spec.rb -e configured`
Expected: PASS.

---

## Task 3: `Payments::EligibleGateways`

**Files:**
- Create: `app/services/payments/eligible_gateways.rb`
- Test: `spec/services/payments/eligible_gateways_spec.rb`

- [ ] **Step 1: Failing test**

```ruby
# spec/services/payments/eligible_gateways_spec.rb
require "rails_helper"

RSpec.describe Payments::EligibleGateways do
  let(:customer) { create(:customer) }

  def configured_account(provider)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: provider, mode: "sandbox",
      merchant_id: "M-#{provider}", status: "active"
    )
    Payments::Gateways.for(provider).credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
    a
  end

  it "returns only platform-available, active, configured gateways" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    Payments::PlatformGateway.for_provider("stripe").update!(available: false)
    configured_account("alipay")
    configured_account("stripe") # configured but NOT platform-available

    keys = described_class.for(customer).map(&:key)
    expect(keys).to include("alipay")
    expect(keys).not_to include("stripe")
  end

  it "excludes disabled or unconfigured accounts" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: "alipay", mode: "sandbox",
      merchant_id: "unset-alipay-sandbox-#{customer.id}", status: "disabled"
    )
    expect(described_class.for(customer).map(&:key)).not_to include("alipay")
  end
end
```

- [ ] **Step 2: Run → fail**

Run: `bundle exec rspec spec/services/payments/eligible_gateways_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/payments/eligible_gateways.rb
# frozen_string_literal: true

module Payments
  # Gateway classes a customer may use right now: platform-available AND backed
  # by an active+configured MerchantAccount for that customer. Registry order.
  class EligibleGateways
    def self.for(customer)
      available = Payments::PlatformGateway.available_providers.map(&:to_s).to_set
      accounts  = Payments::MerchantAccount.unscoped_by_tenant.where(customer_id: customer.id)
      configured_providers = accounts.select(&:configured?).map(&:provider).to_set

      Payments::Gateways.all.select do |gw|
        key = gw.key.to_s
        available.include?(key) && configured_providers.include?(key)
      end
    end
  end
end
```

- [ ] **Step 4: Run → pass**

Run: `bundle exec rspec spec/services/payments/eligible_gateways_spec.rb`
Expected: PASS.

---

## Task 4: `Payments::SetDefaultGateway`

**Files:**
- Create: `app/services/payments/set_default_gateway.rb`
- Test: `spec/services/payments/set_default_gateway_spec.rb`

- [ ] **Step 1: Failing test**

```ruby
# spec/services/payments/set_default_gateway_spec.rb
require "rails_helper"

RSpec.describe Payments::SetDefaultGateway do
  let(:customer) { create(:customer) }

  def make_eligible(provider)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: provider, mode: "sandbox",
      merchant_id: "M-#{provider}", status: "active"
    )
    Payments::Gateways.for(provider).credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
  end

  it "sets an eligible provider as the default" do
    make_eligible("alipay")
    described_class.call(customer: customer, provider: "alipay")
    expect(Payments::DefaultGateway.provider_for(customer.id)).to eq("alipay")
  end

  it "replaces the existing default (single row)" do
    make_eligible("alipay"); make_eligible("wechat_pay")
    described_class.call(customer: customer, provider: "alipay")
    described_class.call(customer: customer, provider: "wechat_pay")
    expect(Payments::DefaultGateway.unscoped_by_tenant.where(customer_id: customer.id).count).to eq(1)
    expect(Payments::DefaultGateway.provider_for(customer.id)).to eq("wechat_pay")
  end

  it "raises for an ineligible (unconfigured) provider" do
    expect { described_class.call(customer: customer, provider: "stripe") }
      .to raise_error(ArgumentError)
  end
end
```

- [ ] **Step 2: Run → fail**

Run: `bundle exec rspec spec/services/payments/set_default_gateway_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/services/payments/set_default_gateway.rb
# frozen_string_literal: true

module Payments
  # Sets a customer's default gateway, but only to a currently-eligible provider
  # (platform-available + active + configured). Upserts the single per-customer row.
  class SetDefaultGateway
    def self.call(customer:, provider:)
      provider = provider.to_s
      eligible = Payments::EligibleGateways.for(customer).map { |gw| gw.key.to_s }
      unless eligible.include?(provider)
        raise ArgumentError, "provider '#{provider}' is not an eligible (enabled + configured) gateway"
      end

      row = Payments::DefaultGateway.unscoped_by_tenant.find_or_initialize_by(customer_id: customer.id)
      row.update!(provider: provider)
      row
    end
  end
end
```

- [ ] **Step 4: Run → pass**

Run: `bundle exec rspec spec/services/payments/set_default_gateway_spec.rb`
Expected: PASS.

---

## Task 5: `default_gateways` route + controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/admin/settings/modules/payments/default_gateways_controller.rb`
- Test: `spec/requests/admin/settings/modules/payments/default_gateways_spec.rb`

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside `namespace :payments do` (the settings one, alongside `resources :merchant_accounts`):

```ruby
            resource :default_gateway, only: :update, controller: "default_gateways"
```

- [ ] **Step 2: Failing request test**

```ruby
# spec/requests/admin/settings/modules/payments/default_gateways_spec.rb
require "rails_helper"

RSpec.describe "default gateway", type: :request do
  let(:customer)    { create(:customer) }
  let(:admin_user)  { create(:user, :admin, customer: customer, password: "password123") }
  let(:member_user) { create(:user, customer: customer, password: "password123") }
  let(:url) { "/#{customer.id}/admin/settings/modules/payments/default_gateway" }

  def make_eligible(provider)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: provider, mode: "sandbox",
      merchant_id: "M-#{provider}", status: "active"
    )
    Payments::Gateways.for(provider).credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
  end

  it "admin sets the default" do
    make_eligible("alipay")
    sign_in admin_user
    patch url, params: { provider: "alipay" }
    expect(Payments::DefaultGateway.provider_for(customer.id)).to eq("alipay")
  end

  it "alerts (no change) for an ineligible provider" do
    sign_in admin_user
    patch url, params: { provider: "stripe" }
    expect(Payments::DefaultGateway.provider_for(customer.id)).to be_nil
    expect(response).to have_http_status(:redirect)
  end

  it "rejects members" do
    sign_in member_user
    patch url, params: { provider: "alipay" }
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    expect(Payments::DefaultGateway.provider_for(customer.id)).to be_nil
  end
end
```

- [ ] **Step 3: Run → fail**

Run: `bundle exec rspec spec/requests/admin/settings/modules/payments/default_gateways_spec.rb`
Expected: FAIL (no controller). Replace `sign_in`/factories with the repo's real admin helpers if different (inspect `merchant_accounts_spec.rb`).

- [ ] **Step 4: Implement controller**

```ruby
# app/controllers/admin/settings/modules/payments/default_gateways_controller.rb
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Payments
        # Sets the tenant's default payment gateway. Admin-scoped (inherits the
        # payments-settings auth guard); tenant-scoped via current_customer.
        class DefaultGatewaysController < ::Admin::Modules::Payments::BaseController
          dashboard_menu_item :settings

          def update
            ::Payments::SetDefaultGateway.call(customer: current_customer, provider: params[:provider])
            redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                        notice: "Default gateway updated."
          rescue ArgumentError => e
            redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                        alert: e.message
          end
        end
      end
    end
  end
end
```

(Confirm the base class — `merchant_accounts_controller.rb` extends
`::Admin::Modules::Payments::BaseController`; match it so auth/tenant guards are
identical.)

- [ ] **Step 5: Run → pass**

Run: `bundle exec rspec spec/requests/admin/settings/modules/payments/default_gateways_spec.rb`
Expected: PASS.

---

## Task 6: Gallery + card UI (Default badge + Set as default)

**Files:**
- Modify: `app/components/payments/admin/gateway_gallery_component.rb` (+ `.html.erb`)
- Modify: `app/components/payments/admin/gateway_card_component.rb` (+ `.html.erb`)
- Modify: `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb` (`index`)
- Test: `spec/components/payments/admin/gateway_card_component_spec.rb`

- [ ] **Step 1: Failing component test**

```ruby
# spec/components/payments/admin/gateway_card_component_spec.rb  (add)
require "rails_helper"

RSpec.describe Payments::Admin::GatewayCardComponent, type: :component do
  let(:gateway) { Payments::Gateways.for("alipay") }
  let(:customer) { create(:customer) }

  def configured_account
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: "alipay", mode: "sandbox",
      merchant_id: "M1", status: "active"
    )
    gateway.credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
    a
  end

  it "shows a Default badge when this provider is the default" do
    html = render_inline(described_class.new(gateway: gateway, account: configured_account, default_provider: "alipay")).to_html
    expect(html).to include("Default")
  end

  it "shows a Set as default control when eligible and not default" do
    html = render_inline(described_class.new(gateway: gateway, account: configured_account, default_provider: nil)).to_html
    expect(html).to include("Set as default")
  end

  it "hides Set as default when not configured" do
    acc = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: "alipay", mode: "sandbox",
      merchant_id: "unset-alipay-sandbox-#{customer.id}", status: "disabled"
    )
    html = render_inline(described_class.new(gateway: gateway, account: acc, default_provider: nil)).to_html
    expect(html).not_to include("Set as default")
  end
end
```

- [ ] **Step 2: Run → fail**

Run: `bundle exec rspec spec/components/payments/admin/gateway_card_component_spec.rb`
Expected: FAIL (no `default_provider:`).

- [ ] **Step 3: Card component — add default awareness**

In `gateway_card_component.rb`, extend the constructor and add helpers:

```ruby
      def initialize(gateway:, account:, default_provider: nil)
        @gateway = gateway
        @account = account
        @default_provider = default_provider.to_s.presence
      end

      attr_reader :gateway, :account, :default_provider

      def default?
        default_provider.present? && default_provider == gateway.key.to_s
      end

      # Eligible to be set as default: enabled + configured (and not already it).
      def default_settable?
        account&.configured? == true && !default?
      end

      def set_default_url
        helpers.admin_settings_modules_payments_default_gateway_path(helpers.params[:customer_id])
      end
```

- [ ] **Step 4: Card template — render badge + button**

In `gateway_card_component.html.erb`, in the header block right after the
`StatusBadgeComponent` render, add the Default badge:

```erb
      <% if default? %>
        <%= render BadgeComponent.new(variant: :primary, size: :sm) do %>Default<% end %>
      <% end %>
```

And in the footer `div` (next to the Configure link), add the Set-as-default
control:

```erb
    <% if default_settable? %>
      <%= button_to "Set as default", set_default_url,
            method: :patch,
            params: { provider: gateway.key },
            class: "btn btn-secondary text-sm shrink-0" %>
    <% end %>
```

- [ ] **Step 5: Gallery passes default down**

In `gateway_gallery_component.rb`:

```ruby
      def initialize(gateways:, accounts_by_provider:, default_provider: nil)
        @gateways             = gateways
        @accounts_by_provider = accounts_by_provider
        @default_provider     = default_provider
      end

      attr_reader :gateways, :accounts_by_provider, :default_provider
```

In `gateway_gallery_component.html.erb`, pass it to each card:

```erb
      <%= render Payments::Admin::GatewayCardComponent.new(
            gateway: gw,
            account: account_for(gw),
            default_provider: default_provider
          ) %>
```

- [ ] **Step 6: Controller index computes the default**

In `merchant_accounts_controller.rb#index`, add and pass `default_provider`:

```ruby
            render ::Payments::Admin::GatewayGalleryComponent.new(
              gateways:             gateways,
              accounts_by_provider: accounts_by_provider,
              default_provider:     ::Payments::DefaultGateway.provider_for(current_customer.id)
            )
```

- [ ] **Step 7: Run → pass**

Run: `bundle exec rspec spec/components/payments/admin/gateway_card_component_spec.rb`
Expected: PASS.

---

## Task 7: Dynamic checkout (default-first + fallback)

**Files:**
- Modify: `app/components/payments/checkout_component.rb` (+ `.html.erb`)
- Modify: `app/controllers/payments/checkouts_controller.rb` (`show`, `create`)
- Test: `spec/components/payments/checkout_component_spec.rb`, `spec/requests/payments/checkouts_spec.rb` (add focused cases)

- [ ] **Step 1: Failing component test**

```ruby
# spec/components/payments/checkout_component_spec.rb  (add/create)
require "rails_helper"

RSpec.describe Payments::CheckoutComponent, type: :component do
  let(:order) { OpenStruct.new(subject: "Order", external_ref: "REF1", amount_cents: 1000, currency: "CNY") }

  it "renders a button per eligible gateway with the default first" do
    gateways = [Payments::Gateways.for("alipay"), Payments::Gateways.for("wechat_pay")]
    html = render_inline(described_class.new(order: order, gateways: gateways, default_provider: "wechat_pay")).to_html
    expect(html).to include('value="wechat_pay"')
    expect(html).to include('value="alipay"')
    # default (wechat_pay) appears before alipay
    expect(html.index('value="wechat_pay"')).to be < html.index('value="alipay"')
  end

  it "renders an empty state when no gateways are eligible" do
    html = render_inline(described_class.new(order: order, gateways: [], default_provider: nil)).to_html
    expect(html).to match(/no payment/i)
  end
end
```

- [ ] **Step 2: Run → fail**

Run: `bundle exec rspec spec/components/payments/checkout_component_spec.rb`
Expected: FAIL (constructor has no `gateways:`).

- [ ] **Step 3: Rewrite the component**

`checkout_component.rb`:

```ruby
# frozen_string_literal: true

module Payments
  # Checkout landing page: renders one submit button per eligible gateway,
  # default first. Receives the gateway list — no registry/DB access here.
  class CheckoutComponent < ApplicationComponent
    def initialize(order:, gateways: [], default_provider: nil, errors: nil)
      @order  = order
      @errors = errors
      @default_provider = default_provider.to_s.presence
      @gateways = order_with_default_first(gateways)
    end

    attr_reader :order, :errors, :gateways, :default_provider

    def any_gateways?
      gateways.any?
    end

    private

    def order_with_default_first(list)
      return list if default_provider.blank?

      default, rest = list.partition { |gw| gw.key.to_s == default_provider }
      default + rest
    end
  end
end
```

`checkout_component.html.erb` — replace the two hardcoded buttons with a loop:

```erb
<section class="mx-auto max-w-md bg-white border border-gray-200 rounded-md p-6">
  <h1 class="text-lg font-semibold text-gray-900"><%= order.subject %></h1>
  <p class="mt-1 text-xs text-gray-500 tabular-nums">Order #<%= order.external_ref %></p>
  <p class="mt-4 text-3xl font-semibold text-gray-900 tabular-nums">¥<%= format('%.2f', order.amount_cents / 100.0) %></p>

  <% if errors&.any? %>
    <div class="mt-3 border-l-4 border-red-400 bg-red-50 px-3 py-2 text-sm text-red-800"><%= errors.full_messages.to_sentence %></div>
  <% end %>

  <% if any_gateways? %>
    <%= form_with url: helpers.request.path, method: :post, class: "mt-6 space-y-3" do |f| %>
      <%= f.hidden_field :ref, value: order.external_ref %>
      <% gateways.each do |gw| %>
        <button type="submit" name="provider" value="<%= gw.key %>"
                class="flex w-full items-center justify-center gap-2 rounded-md border border-gray-300 px-4 py-2.5 text-sm font-medium text-gray-900 hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400">
          <%= gw.display_name %>
        </button>
      <% end %>
    <% end %>
  <% else %>
    <p class="mt-6 text-sm text-gray-500">No payment methods are available for this store.</p>
  <% end %>
</section>
```

- [ ] **Step 4: Controller passes eligible gateways + default**

In `checkouts_controller.rb#show`:

```ruby
    def show
      render Payments::CheckoutComponent.new(
        order:            @order,
        gateways:         Payments::EligibleGateways.for(@customer),
        default_provider: default_provider
      )
    end
```

Add a private helper and update `create` to fall back to the default + re-render
with gateways on validation failure:

```ruby
    def create
      provider = params[:provider].presence || default_provider
      contract = Payments::Contracts::Charge.new(OpenStruct.new)
      attrs = {
        external_ref: @order.external_ref,
        amount_cents: @order.amount_cents,
        currency:     @order.currency,
        subject:      @order.subject,
        provider:     provider,
        openid:       params[:openid]
      }
      unless contract.validate(attrs)
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      end

      result = Payments::Activities::Charge.call(
        customer:  @customer, order: @order, provider: provider, request: request,
        openid: params[:openid], save_card: save_card_requested?, user: current_user
      )
      # ... (unchanged flow rendering below)
```

Add the private helpers:

```ruby
    def eligible_gateways
      @eligible_gateways ||= Payments::EligibleGateways.for(@customer)
    end

    def default_provider
      stored = Payments::DefaultGateway.provider_for(@customer.id)
      keys   = eligible_gateways.map { |gw| gw.key.to_s }
      keys.include?(stored) ? stored : keys.first
    end
```

(Keep the rest of `create` — `flow`/component rendering — as-is. Replace the
existing `provider: params[:provider]` usages in the `attrs`/Charge call with the
local `provider`.)

- [ ] **Step 5: Run component test → pass**

Run: `bundle exec rspec spec/components/payments/checkout_component_spec.rb`
Expected: PASS.

- [ ] **Step 6: Add a checkout request case (fallback)**

Inspect `spec/requests/payments/checkouts_spec.rb` (if present) and add: a `show`
with two eligible gateways renders both with the default first; a `create` with
no `provider` param uses the default (assert via the Charge activity / resulting
payment provider, mirroring existing checkout request specs). Reuse the file's
existing customer/order/gateway setup. If no such spec exists, add a minimal one
modeled on the existing checkout coverage.

Run: `bundle exec rspec spec/requests/payments/checkouts_spec.rb`
Expected: PASS (rewrite stale hardcoded-button assertions per the stale-test policy).

---

## Task 8: Regression

- [ ] **Step 1: Run touched suites**

```
bundle exec rspec \
  spec/models/payments/default_gateway_spec.rb \
  spec/models/payments/merchant_account_spec.rb \
  spec/services/payments/eligible_gateways_spec.rb \
  spec/services/payments/set_default_gateway_spec.rb \
  spec/requests/admin/settings/modules/payments \
  spec/components/payments \
  spec/requests/payments/checkouts_spec.rb
```
Expected: all PASS (rewrite stale checkout-button specs first).

- [ ] **Step 2: Smoke**

Boot a SKIP_AUTH instance (separate pidfile/port) and, for a customer with two
configured+available gateways: load merchant_accounts (Default badge + Set as
default visible), click Set as default (badge moves), then load a checkout URL
(default button first; no-provider POST uses default). Then stop that instance.

---

## Self-Review Notes

- **Spec coverage:** data → T1; configured? → T2; eligibility → T3; setter → T4; route/controller → T5; gallery/card UI → T6; checkout consumption + fallback → T7; regression → T8.
- **Type consistency:** `EligibleGateways.for` returns gateway CLASSES (use `.key`/`.display_name`); `provider_for` returns a string; `default_provider` strings compared as strings throughout. `configured?` lives on MerchantAccount and is reused by EligibleGateways and the card.
- **No commits on master.** Replace any placeholder sign-in/factory with the repo's real helpers before running request specs.

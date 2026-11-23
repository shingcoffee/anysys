# Payment Settings Refactor + Card Gateways (Tokenized) + Card Recurring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the admin Payments settings UI into a gateway-gallery experience and add a tokenized Stripe card gateway (Visa/Mastercard/Amex) with off-session recurring charges, never storing card data.

**Architecture:** Keep the vendor-agnostic gateway registry. Enrich the shared `Gateways::Base` contract once (capabilities, `:card` flow, tokenization API, multi-currency) so card processors are first-class and future ones stay single-file. Add a `Payments::PaymentMethod` vault (tokens + display metadata only) and link it to `Payments::Subscription` for card recurring. Rebuild the admin settings UI as composable ViewComponents and add a lean member self-service surface.

**Tech Stack:** Ruby 3.2.8 / Rails 8.1.2, Trailblazer Activity + Reform, ViewComponent, TailwindCSS, StimulusJS, RSpec. Stripe via raw HTTP through `Base` helpers (no SDK gem), matching the Alipay/WeChat style.

**Spec:** `docs/superpowers/specs/2026-06-21-payment-settings-card-gateways-design.md`

**Execution note:** This plan is built for the AGENTS.md SDLC pipeline. Backend/security/frontend tasks are grouped so the parallel build (anysys-backend-developer / anysys-security-engineer / anysys-frontend-developer) can run them concurrently where marked `[parallel-safe]`. UI markup is produced by anysys-ux-designer (mockups) → anysys-frontend-developer (components); the plan fixes the component boundaries, props, and tests, and the frontend agent fills the Tailwind markup against the mockups.

---

## File Structure

**Backend infra (vendor-agnostic) — `[parallel group: backend]`**
- Modify `app/services/payments/gateways/base.rb` — add `capabilities`, `:card` flow, `supported_currencies`, `zero_decimal_currency?`, tokenization methods (`vault_card`, `detach_token`, `charge_token`).
- Modify `app/services/payments/flow_selector.rb` — flow-aware selection from `supported_flows`.
- Modify `app/services/payments/contracts/charge.rb`, `.../subscribe.rb` — gateway-driven currency validation.
- Create `db/migrate/*_create_payment_methods.rb` + `app/models/payments/payment_method.rb` — the card vault.
- Create `db/migrate/*_add_currency_and_payment_method_to_payment_subscriptions.rb`; modify `app/models/payments/subscription.rb`.
- Create `db/migrate/*_add_default_currency_to_payment_merchant_accounts.rb`.

**Stripe gateway (single file)**
- Create `app/services/payments/gateways/stripe.rb`.

**Activities**
- Create `app/services/payments/activities/vault_card.rb`, `.../charge_token.rb`.
- Modify `app/services/payments/activities/charge.rb` (save-card opt-in), `.../cancel_subscription.rb` (token detach), and the subscriptions cron path.
- Create `app/services/payments/contracts/vault_card.rb`.

**Admin settings UI — `[parallel group: frontend + security]`**
- Create `app/components/payments/admin/status_badge_component.{rb,html.erb}`
- Create `app/components/payments/admin/gateway_card_component.{rb,html.erb}`
- Create `app/components/payments/admin/gateway_gallery_component.{rb,html.erb}`
- Create `app/components/payments/admin/credential_fields_component.{rb,html.erb}` (extracted)
- Create `app/components/payments/admin/gateway_config_component.{rb,html.erb}` (replaces MerchantAccountFormComponent's form role)
- Modify `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb` (gallery index + `test_connection`)
- Modify `config/routes.rb` (gallery + `test_connection` member route)
- Create `app/javascript/controllers/payments/gateway_toggle_controller.js`, `.../gateway_test_connection_controller.js`

**Member surface — `[parallel group: frontend + security]`**
- Modify `config/routes.rb` (member payment_methods + subscriptions)
- Create `app/controllers/member/payments/payment_methods_controller.rb`, `.../subscriptions_controller.rb`
- Create `app/components/payments/member/payment_methods_component.{rb,html.erb}`, `.../subscriptions_component.{rb,html.erb}`
- Create `app/javascript/controllers/payments/stripe_card_controller.js`

---

## Phase A — Backend infra (vendor-agnostic)

### Task 1: Enrich `Gateways::Base` contract `[parallel group: backend]`

**Files:**
- Modify: `app/services/payments/gateways/base.rb`
- Test: `spec/services/payments/gateways/base_spec.rb`

- [ ] **Step 1: Write failing test**

```ruby
# spec/services/payments/gateways/base_spec.rb
require "rails_helper"

RSpec.describe Payments::Gateways::Base do
  let(:klass) { Class.new(described_class) }

  it "defaults capabilities to one-time + refunds + webhooks" do
    expect(klass.capabilities).to match_array(%i[one_time refunds webhooks])
  end

  it "defaults supported_currencies to CNY" do
    expect(klass.supported_currencies).to eq(%w[cny])
  end

  it "knows zero-decimal currencies" do
    expect(klass.zero_decimal_currency?("jpy")).to be(true)
    expect(klass.zero_decimal_currency?("usd")).to be(false)
  end

  it "raises NotImplementedError for tokenization methods by default" do
    inst = klass.new(account: nil)
    expect { inst.vault_card(user: nil, return_url: "x") }.to raise_error(NotImplementedError)
    expect { inst.charge_token(order: nil, payment: nil, payment_method: nil) }.to raise_error(NotImplementedError)
    expect { inst.detach_token(payment_method: nil) }.to raise_error(NotImplementedError)
  end
end
```

- [ ] **Step 2: Run, expect FAIL** — `bundle exec rspec spec/services/payments/gateways/base_spec.rb` → fails (`capabilities` undefined).

- [ ] **Step 3: Implement** — add to the `class << self` block in `base.rb`:

```ruby
# Subset of [:one_time, :recurring, :tokenized_cards, :refunds,
# :reconciliation, :webhooks]. Drives Settings UI badges and feature guards.
def capabilities
  %i[one_time refunds webhooks]
end

# ISO 4217 lowercase codes this gateway can transact in.
def supported_currencies
  %w[cny]
end

ZERO_DECIMAL = %w[bif clp djf gnf jpy kmf krw mga pyg rwf ugx vnd vuv xaf xof xpf].freeze

def zero_decimal_currency?(code)
  ZERO_DECIMAL.include?(code.to_s.downcase)
end
```

Change `supported_flows` doc/comment to mention `:card`; the default value stays `%i[qr h5 jsapi]`. Add instance methods near the other `NotImplementedError` stubs:

```ruby
def vault_card(user:, return_url:);                 raise NotImplementedError; end
def detach_token(payment_method:);                  raise NotImplementedError; end
def charge_token(order:, payment:, payment_method:); raise NotImplementedError; end
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(payments): enrich gateway Base with capabilities, currency, tokenization API"`

---

### Task 2: Flow-aware `FlowSelector` `[parallel group: backend]`

**Files:**
- Modify: `app/services/payments/flow_selector.rb`
- Test: `spec/services/payments/flow_selector_spec.rb`

- [ ] **Step 1: Failing test**

```ruby
# spec/services/payments/flow_selector_spec.rb
require "rails_helper"

RSpec.describe Payments::FlowSelector do
  let(:request) { instance_double(ActionDispatch::Request, user_agent: ua) }

  context "card-only gateway (stripe)" do
    let(:ua) { "Mozilla/5.0 (iPhone)" }
    it "always selects :card regardless of UA" do
      expect(described_class.call(request: request, provider: "stripe")).to eq(:card)
    end
  end

  context "china gateway (alipay) preserves existing heuristic" do
    let(:ua) { "Mozilla/5.0 (Macintosh)" }
    it "selects :qr on desktop" do
      expect(described_class.call(request: request, provider: "alipay")).to eq(:qr)
    end
  end

  context "in-app browser" do
    let(:ua) { "MicroMessenger/8.0" }
    it "selects :jsapi for wechat_pay" do
      expect(described_class.call(request: request, provider: "wechat_pay")).to eq(:jsapi)
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** (stripe gateway not yet defined → this task's stripe case may error; gate it by implementing Task 6 first OR stub. To keep ordering clean, run only the alipay/wechat examples now: `bundle exec rspec spec/services/payments/flow_selector_spec.rb -e "china" -e "in-app"` → these still pass with old code, confirming no regression; the stripe example fails until Task 6.)

- [ ] **Step 3: Implement**

```ruby
module Payments
  class FlowSelector
    MOBILE_UA = /Mobile|Android|iPhone|iPad/i

    def self.call(request:, provider:)
      gateway = Payments::Gateways.for(provider)
      supported = gateway.supported_flows

      # Card processors expose only :card — no UA branching.
      return :card if supported == %i[card]

      ua = request.user_agent.to_s
      pattern = gateway.respond_to?(:jsapi_user_agent_pattern) ? gateway.jsapi_user_agent_pattern : nil
      return :jsapi if pattern && ua.match?(pattern) && supported.include?(:jsapi)
      return :h5    if ua.match?(MOBILE_UA) && supported.include?(:h5)
      supported.include?(:qr) ? :qr : supported.first
    end
  end
end
```

- [ ] **Step 4: Run full file after Task 6 — expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "refactor(payments): make FlowSelector aware of gateway supported_flows"`

---

### Task 3: Multi-currency contracts + `default_currency` column `[parallel group: backend]`

**Files:**
- Create: `db/migrate/<ts>_add_default_currency_to_payment_merchant_accounts.rb`
- Modify: `app/services/payments/contracts/charge.rb`, `app/services/payments/contracts/subscribe.rb`
- Test: `spec/services/payments/contracts/charge_spec.rb` (extend)

- [ ] **Step 1: Migration**

```ruby
class AddDefaultCurrencyToPaymentMerchantAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_merchant_accounts, :default_currency, :string, null: false, default: "cny"
  end
end
```
Run: `bin/rails db:migrate`

- [ ] **Step 2: Failing test** — assert charge contract rejects a currency the chosen gateway does not support and accepts one it does:

```ruby
it "rejects a currency unsupported by the gateway" do
  result = Payments::Contracts::Charge.new(OpenStruct.new).validate(
    external_ref: "r1", amount_cents: 100, currency: "usd",
    subject: "s", provider: "alipay"
  )
  expect(result).to be(false)
end

it "accepts a currency the gateway supports" do
  result = Payments::Contracts::Charge.new(OpenStruct.new).validate(
    external_ref: "r1", amount_cents: 100, currency: "cny",
    subject: "s", provider: "alipay"
  )
  expect(result).to be(true)
end
```

- [ ] **Step 3: Implement** — replace the hard-coded `inclusion: { in: ["CNY"] }` currency check with a gateway-driven validation:

```ruby
validate do
  next if provider.blank? || currency.blank?
  supported = Payments::Gateways.for(provider).supported_currencies rescue []
  errors.add(:currency, :inclusion) unless supported.include?(currency.to_s.downcase)
end
```
Apply the equivalent change in `subscribe.rb`. (Normalize currency to lowercase ISO codes everywhere; update any fixtures that used `"CNY"` to `"cny"`.)

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(payments): gateway-driven multi-currency validation + default_currency column"`

---

### Task 4: `Payments::PaymentMethod` card vault `[parallel group: backend]`

**Files:**
- Create: `db/migrate/<ts>_create_payment_methods.rb`
- Create: `app/models/payments/payment_method.rb`
- Test: `spec/models/payments/payment_method_spec.rb`

- [ ] **Step 1: Migration** (tokens + display metadata ONLY — no PAN/CVV columns)

```ruby
class CreatePaymentMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_methods do |t|
      t.integer :customer_id, null: false
      t.integer :user_id,     null: false
      t.string  :provider,    null: false
      t.string  :psp_customer_id
      t.string  :psp_payment_method_id, null: false
      t.string  :brand
      t.string  :last4
      t.integer :exp_month
      t.integer :exp_year
      t.boolean :is_default, null: false, default: false
      t.string  :status,     null: false, default: "active"
      t.timestamps
    end
    add_index :payment_methods, %i[customer_id user_id]
    add_index :payment_methods, %i[provider psp_payment_method_id], unique: true
  end
end
```
Run: `bin/rails db:migrate`

- [ ] **Step 2: Failing test**

```ruby
require "rails_helper"
RSpec.describe Payments::PaymentMethod do
  it "requires customer_id and user_id" do
    pm = described_class.new(provider: "stripe", psp_payment_method_id: "pm_1")
    expect(pm).not_to be_valid
    expect(pm.errors.attribute_names).to include(:customer_id, :user_id)
  end

  it "exposes a display label" do
    pm = described_class.new(brand: "visa", last4: "4242")
    expect(pm.display_label).to eq("Visa •••• 4242")
  end

  it "NEVER has a column that could hold raw card data" do
    forbidden = %w[pan card_number cardnumber cvv cvc cvv2 security_code]
    expect(described_class.column_names & forbidden).to be_empty
  end

  it "scopes default uniqueness per (customer,user)" do
    # factory/fixtures: two active methods, marking one default unsets the other
  end
end
```

- [ ] **Step 3: Implement model** (thin)

```ruby
module Payments
  class PaymentMethod < ApplicationRecord
    include TenantScoped
    self.table_name = "payment_methods"

    STATUSES = %w[active expired removed].freeze

    validates :customer_id, :user_id, :provider, :psp_payment_method_id, presence: true
    validates :provider, inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }
    validates :status, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active") }
    scope :for_user, ->(uid) { where(user_id: uid) }

    before_save :enforce_single_default

    def display_label = [brand.to_s.titleize.presence, "•••• #{last4}"].compact.join(" ")
    def mark_removed! = update!(status: "removed", is_default: false)

    private

    def enforce_single_default
      return unless is_default? && (new_record? || will_save_change_to_is_default?)
      self.class.where(customer_id: customer_id, user_id: user_id)
        .where.not(id: id).update_all(is_default: false)
    end
  end
end
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(payments): PaymentMethod card vault (tokens + display metadata, no PAN)"`

---

### Task 5: Subscription enrichment for card recurring `[parallel group: backend]`

**Files:**
- Create: `db/migrate/<ts>_add_currency_and_payment_method_to_payment_subscriptions.rb`
- Modify: `app/models/payments/subscription.rb`
- Test: `spec/models/payments/subscription_spec.rb` (extend)

- [ ] **Step 1: Migration**

```ruby
class AddCurrencyAndPaymentMethodToPaymentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_subscriptions, :currency, :string, null: false, default: "cny"
    add_reference :payment_subscriptions, :payment_method, null: true
  end
end
```
Run: `bin/rails db:migrate`

- [ ] **Step 2: Failing test**

```ruby
it "belongs to an optional payment_method" do
  sub = Payments::Subscription.new
  expect(sub).to respond_to(:payment_method)
end

it "is card-recurring when a payment_method is linked" do
  sub = Payments::Subscription.new(payment_method_id: 1)
  expect(sub.card_recurring?).to be(true)
end
```

- [ ] **Step 3: Implement** — add to `subscription.rb`:

```ruby
belongs_to :payment_method, class_name: "Payments::PaymentMethod", optional: true

def card_recurring? = payment_method_id.present?
```
Keep `next_charge_time_from` / `advance_next_charge!` as-is; the cron reuses them.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(payments): link Subscription to vaulted PaymentMethod + currency"`

---

## Phase B — Stripe gateway (single file)

### Task 6: `Payments::Gateways::Stripe`

**Files:**
- Create: `app/services/payments/gateways/stripe.rb`
- Test: `spec/services/payments/gateways/stripe_spec.rb`

- [ ] **Step 1: Failing test** (HTTP stubbed via WebMock — confirm the project's existing gateway specs' stubbing style and match it)

```ruby
require "rails_helper"
RSpec.describe Payments::Gateways::Stripe do
  let(:account) do
    instance_double(Payments::MerchantAccount, mode: "sandbox", merchant_id: "acct_1",
      credential: nil).tap do |a|
      allow(a).to receive(:credential).with(:secret_key).and_return("sk_test_x")
      allow(a).to receive(:credential).with(:publishable_key).and_return("pk_test_x")
      allow(a).to receive(:credential).with(:webhook_signing_secret).and_return("whsec_x")
    end
  end
  subject(:gw) { described_class.new(account: account) }

  it "registers under key 'stripe'" do
    expect(Payments::Gateways.keys.map(&:to_s)).to include("stripe")
  end

  it "declares card capabilities and flows" do
    expect(described_class.supported_flows).to eq(%i[card])
    expect(described_class.capabilities).to include(:tokenized_cards, :recurring)
    expect(described_class.supported_currencies).to include("usd")
  end

  it "charge returns client_secret + publishable_key for the card flow" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: { id: "pi_1", client_secret: "pi_1_secret",
                                      status: "requires_payment_method" }.to_json)
    order   = instance_double(Payments::Order, amount_cents: 500, currency: "usd",
                              external_ref: "r1", subject: "Test")
    payment = instance_double(Payments::Payment, out_trade_no: "ch-1")
    res = gw.charge(order: order, payment: payment, flow: :card)
    expect(res[:prepay_payload]).to include(client_secret: "pi_1_secret", publishable_key: "pk_test_x")
  end

  it "charge_token creates an off-session confirmed PaymentIntent" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: { id: "pi_2", status: "succeeded" }.to_json)
    order   = instance_double(Payments::Order, amount_cents: 500, currency: "usd", external_ref: "r2", subject: "Sub")
    payment = instance_double(Payments::Payment, out_trade_no: "ch-2")
    pm = instance_double(Payments::PaymentMethod, psp_customer_id: "cus_1", psp_payment_method_id: "pm_1")
    res = gw.charge_token(order: order, payment: payment, payment_method: pm)
    expect(res).to include(status: :succeeded, psp_transaction_id: "pi_2")
  end

  it "vault_card creates a SetupIntent and returns its client_secret" do
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_1" }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/setup_intents")
      .to_return(status: 200, body: { id: "seti_1", client_secret: "seti_1_secret" }.to_json)
    user = instance_double("User", id: 7, email: "a@b.com")
    res = gw.vault_card(user: user, return_url: "https://x/return")
    expect(res).to include(client_secret: "seti_1_secret", psp_customer_id: "cus_1")
  end

  it "verify_notification rejects a bad signature" do
    expect {
      gw.verify_notification(headers: { "Stripe-Signature" => "t=1,v1=bad" }, body: "{}")
    }.to raise_error(Payments::Errors::SignatureInvalid)
  end
end
```

- [ ] **Step 2: Run, expect FAIL** (class missing).

- [ ] **Step 3: Implement** — `app/services/payments/gateways/stripe.rb`. Key points: form-encode bodies for Stripe (`application/x-www-form-urlencoded`), amounts respect `zero_decimal_currency?`, stamp `metadata[merchant_id]` on every PaymentIntent/SetupIntent, verify the `Stripe-Signature` HMAC against `webhook_signing_secret` with a 5-minute replay window.

```ruby
# frozen_string_literal: true
require "openssl"

module Payments
  module Gateways
    class Stripe < Base
      API = "https://api.stripe.com"
      REPLAY_WINDOW = 300

      class << self
        def key = "stripe"
        def display_name = "Credit / Debit Card (Stripe)"
        def supported_flows = %i[card]
        def capabilities = %i[one_time recurring tokenized_cards refunds reconciliation webhooks]
        def supported_currencies = %w[usd eur gbp cad aud sgd hkd jpy cny]

        def credential_fields
          [
            { name: :secret_key,             label: "Secret key",            type: :password, encrypted: true },
            { name: :publishable_key,        label: "Publishable key",       type: :string,   encrypted: false },
            { name: :webhook_signing_secret, label: "Webhook signing secret", type: :password, encrypted: true }
          ]
        end

        # Stripe stamps our merchant_id into PaymentIntent/SetupIntent metadata;
        # Connect events also carry `account`. Either routes us to the tenant.
        def extract_merchant_id(_headers, body)
          json = JSON.parse(body) rescue {}
          json.dig("data", "object", "metadata", "merchant_id") ||
            json["account"] ||
            json.dig("data", "object", "metadata", "merchant_account_id")
        end
      end

      def charge(order:, payment:, flow:, openid: nil)
        params = {
          amount: amount_for(order), currency: order.currency.to_s.downcase,
          "automatic_payment_methods[enabled]" => true,
          description: order.subject,
          "metadata[merchant_id]" => account.merchant_id,
          "metadata[out_trade_no]" => payment.out_trade_no
        }
        res = api_post("/v1/payment_intents", params)
        { prepay_payload: { client_secret: res["client_secret"], publishable_key: account.credential(:publishable_key) } }
      end

      def query(payment:)
        res = api_get("/v1/payment_intents/#{payment.psp_transaction_id || payment.out_trade_no}")
        { status: map_status(res["status"]), psp_transaction_id: res["id"], raw: res }
      end

      def refund(payment:, refund:)
        res = api_post("/v1/refunds", { payment_intent: payment.psp_transaction_id, amount: refund.amount_cents })
        { psp_refund_id: res["id"], status: (res["status"] == "succeeded" ? :succeeded : :processing), raw: res }
      end

      def close(payment:)
        api_post("/v1/payment_intents/#{payment.psp_transaction_id}/cancel", {})
        { status: :closed }
      end

      def vault_card(user:, return_url:)
        customer = api_post("/v1/customers", { email: user.email, "metadata[user_id]" => user.id,
                                               "metadata[merchant_id]" => account.merchant_id })
        seti = api_post("/v1/setup_intents", { customer: customer["id"], usage: "off_session",
                                               "metadata[merchant_id]" => account.merchant_id })
        { client_secret: seti["client_secret"], psp_customer_id: customer["id"] }
      end

      def charge_token(order:, payment:, payment_method:)
        res = api_post("/v1/payment_intents", {
          amount: amount_for(order), currency: order.currency.to_s.downcase,
          customer: payment_method.psp_customer_id, payment_method: payment_method.psp_payment_method_id,
          off_session: true, confirm: true,
          "metadata[merchant_id]" => account.merchant_id, "metadata[out_trade_no]" => payment.out_trade_no
        })
        { psp_transaction_id: res["id"], status: map_status(res["status"]), raw: res }
      end

      def charge_subscription(subscription:, payment:)
        charge_token(order: subscription, payment: payment, payment_method: subscription.payment_method)
      end

      def detach_token(payment_method:)
        api_post("/v1/payment_methods/#{payment_method.psp_payment_method_id}/detach", {})
        { status: :removed }
      end

      def subscribe(subscription:);          { status: :pending_sign }; end
      def cancel_subscription(subscription:); { status: :cancelled };   end

      def download_bill(bill_date:, bill_type:)
        raise Payments::Errors::ApiError.new("Stripe reconciliation uses report runs", code: "unsupported", payload: {})
      end

      def verify_notification(headers:, body:)
        sig = headers["Stripe-Signature"] || headers["HTTP_STRIPE_SIGNATURE"]
        parts = sig.to_s.split(",").map { |kv| kv.split("=", 2) }.to_h
        ts = parts["t"].to_i
        raise Payments::Errors::SignatureInvalid, "stale" if ts <= 0 || (Time.zone.now.to_i - ts).abs > REPLAY_WINDOW
        expected = OpenSSL::HMAC.hexdigest("SHA256", account.credential(:webhook_signing_secret), "#{parts['t']}.#{body}")
        raise Payments::Errors::SignatureInvalid, "bad signature" unless secure_compare(expected, parts["v1"].to_s)
        JSON.parse(body)
      end

      private

      def amount_for(order)
        self.class.zero_decimal_currency?(order.currency) ? (order.amount_cents / 100) : order.amount_cents
      end

      def map_status(s)
        case s
        when "succeeded" then :succeeded
        when "processing", "requires_action", "requires_confirmation", "requires_payment_method" then :pending
        when "canceled" then :closed
        else :failed
        end
      end

      def secure_compare(a, b) = a.bytesize == b.bytesize && OpenSSL.fixed_length_secure_compare(a, b)

      def auth_headers
        { "Authorization" => "Bearer #{account.credential(:secret_key)}",
          "Content-Type" => "application/x-www-form-urlencoded" }
      end

      def api_post(path, params)
        safe_json(http_post("#{API}#{path}", body: URI.encode_www_form(params), headers: auth_headers).body)
      end

      def api_get(path)
        safe_json(http_get("#{API}#{path}", headers: auth_headers).body)
      end

      register!
    end
  end
end
```

- [ ] **Step 4: Run, expect PASS.** Then re-run Task 2's full spec (`flow_selector_spec.rb`) — now PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(payments): Stripe card gateway (tokenized, off-session recurring)"`

---

## Phase C — Activities & contracts

### Task 7: VaultCard + ChargeToken activities, save-card opt-in `[parallel group: backend]`

**Files:**
- Create: `app/services/payments/contracts/vault_card.rb`
- Create: `app/services/payments/activities/vault_card.rb`
- Create: `app/services/payments/activities/charge_token.rb`
- Modify: `app/services/payments/activities/charge.rb` (accept `save_card:` for authenticated members → pass `setup_future_usage`)
- Modify: `app/services/payments/activities/cancel_subscription.rb` (detach token when card-recurring and no other use)
- Test: `spec/services/payments/activities/vault_card_spec.rb`, `.../charge_token_spec.rb`

- [ ] **Step 1: Failing tests** — `VaultCard.call(customer:, user:, provider:, return_url:)` persists a `PaymentMethod` row (status active, tokens populated) and returns the SetupIntent `client_secret`; `ChargeToken.call(customer:, order:, payment_method:)` creates a `Payment` and marks it succeeded/failed from the gateway result.

```ruby
# vault_card_spec.rb (sketch)
it "creates a vault row and returns client_secret" do
  gw = instance_double(Payments::Gateways::Stripe,
        vault_card: { client_secret: "seti_secret", psp_customer_id: "cus_1" })
  allow(Payments::Gateway).to receive(:for).and_return(gw)
  res = Payments::Activities::VaultCard.call(customer: customer, user: user,
          provider: "stripe", return_url: "https://x")
  expect(res[:client_secret]).to eq("seti_secret")
  expect(Payments::PaymentMethod.last.psp_customer_id).to eq("cus_1")
end
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the two activities and contract following the Trailblazer style in the existing `charge.rb`/`refund.rb` (read them first; mirror their `step`/`Output` conventions). `VaultCard` writes the vault row with `status: "active"`; the actual card details (brand/last4/exp) are backfilled from the SetupIntent `succeeded` webhook in `HandleWebhook` (extend it to recognize `setup_intent.succeeded` and update the matching `PaymentMethod`). `ChargeToken` reuses `OutTradeNo` + `Payment` state machine.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(payments): VaultCard + ChargeToken activities, save-card opt-in"`

### Task 7b: Card-recurring cron path `[parallel group: backend]`

**Files:**
- Modify: `app/services/payments/cron/charge_due_subscriptions.rb` (read first)
- Test: extend its spec

- [ ] Confirm `due_now` subscriptions with `card_recurring?` route through `gateway.charge_subscription` → `charge_token`; on success call `advance_next_charge!`. Add a spec proving a card subscription is charged off-session and its `next_charge_at` advances. Commit.

---

## Phase D — Admin settings UI refactor

### Task 8: UX mockups (anysys-ux-designer + frontend-design)

- [ ] Dispatch **anysys-ux-designer** with the spec §4. Deliverables: responsive mockups/layout specs for (a) the gateway gallery (grid of gateway cards with status badge, method chips, mode, enable toggle, Configure), (b) the gateway config page (env switcher, credential fields, default currency, test-connection, enable toggle). Save under `docs/superpowers/ux/`. No production code. This output feeds Task 9's markup.

### Task 9: Settings ViewComponents `[parallel group: frontend]`

**Files (each Create with paired `.html.erb` + `spec/components/...`):**
- `app/components/payments/admin/status_badge_component.rb` — `initialize(state:)` where state ∈ `:active|:needs_setup|:disabled`; renders a Tailwind pill (green/amber/gray). Pure, no DB.
- `app/components/payments/admin/gateway_card_component.rb` — `initialize(gateway:, account:)`; shows `gateway.display_name`, capability/method chips from `gateway.capabilities`, `StatusBadgeComponent`, mode, a `gateway_toggle_controller` switch, and a Configure link to the config page.
- `app/components/payments/admin/gateway_gallery_component.rb` — `initialize(gateways:, accounts_by_provider:)`; responsive grid (`grid-cols-1 sm:grid-cols-2 xl:grid-cols-3`) of `GatewayCardComponent`.
- `app/components/payments/admin/credential_fields_component.rb` — extracted from `MerchantAccountFormComponent`; `initialize(account:, fields:)`; renders password/text/string inputs with the existing encrypted-placeholder UX (reuse `encrypted_placeholder`/`field_value` logic verbatim).
- `app/components/payments/admin/gateway_config_component.rb` — `initialize(account:)`; the per-gateway config form: provider (fixed/displayed), env (mode) switch, `merchant_id`, `notify_url_override`, `default_currency` select (from `gateway.supported_currencies`), `CredentialFieldsComponent`, a `gateway_test_connection_controller` button + result region, status toggle. Replaces `MerchantAccountFormComponent`'s single-form role.

- [ ] For each: write a component spec first (e.g. `StatusBadgeComponent` renders the right color/label per state; `GatewayCardComponent` shows "Needs setup" when credentials absent), run FAIL, implement `.rb` + `.html.erb` (Tailwind only, responsive, matching admin layout conventions and the Task 8 mockups), run PASS, commit per component.
- [ ] Delete `MerchantAccountFormComponent` (`.rb` + `.html.erb`) and its references once `GatewayConfigComponent` + gallery replace it. Rewrite its spec rather than leave it stale (stale-test policy).

### Task 10: Settings controller + routes `[parallel group: security]`

**Files:**
- Modify: `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb`

- [ ] **Routes** — keep `resources :merchant_accounts` and add a gallery index + test-connection:

```ruby
namespace :payments do
  resources :merchant_accounts, only: %i[index new create edit update] do
    member { post :test_connection }
  end
end
```
(If a distinct gallery URL reads cleaner, add `get :gateways` collection route → gallery; otherwise render the gallery from `index`.)

- [ ] **Controller** — `index` renders `GatewayGalleryComponent.new(gateways: Payments::Gateways.all, accounts_by_provider: ...)`; `edit` renders `GatewayConfigComponent`; add `test_connection` member action that calls a lightweight gateway ping (Stripe → `GET /v1/account`; Alipay/WeChat → a cheap authenticated call or `:ok` stub) and returns JSON `{ ok:, message:, verified_at: }`. **Preserve** existing `require_admin_or_owner!` guard (inherited from `Admin::Modules::Payments::BaseController`) and tenant scoping (`for_current_customer`). No cross-tenant access.

- [ ] **Tests** — admin-or-owner can load gallery + config + test_connection; a member is forbidden; a different-tenant admin cannot read/update another tenant's account (404/forbidden); test_connection returns JSON. Run, implement, PASS, commit.

### Task 11: Settings Stimulus controllers `[parallel group: frontend]`

**Files:**
- Create: `app/javascript/controllers/payments/gateway_toggle_controller.js` — toggles status active/disabled via `fetch` PATCH, optimistic UI, reverts on error.
- Create: `app/javascript/controllers/payments/gateway_test_connection_controller.js` — POSTs to `test_connection`, shows spinner → success/error in the result region.
- [ ] Add a thin controller spec or system test exercising the toggle + test-connection happy path (use the project's existing Stimulus/system test approach). Implement, verify, commit.

---

## Phase E — Member self-service surface

### Task 12: Member routes + controllers `[parallel group: security]`

**Files:**
- Modify: `config/routes.rb` (inside `namespace :member`)
- Create: `app/controllers/member/payments/payment_methods_controller.rb`
- Create: `app/controllers/member/payments/subscriptions_controller.rb`
- Test: `spec/requests/member/payments/payment_methods_spec.rb`, `.../subscriptions_spec.rb`

- [ ] **Routes**

```ruby
namespace :member do
  namespace :payments do
    resources :payment_methods, only: %i[index new create destroy] do
      collection { post :setup_intent }  # returns SetupIntent client_secret (vault_card)
    end
    resources :subscriptions, only: %i[index show] do
      resource :cancellation, only: :create, controller: "subscription_cancellations"
    end
  end
end
```

- [ ] **Controllers** — member-only. Inherit the member base controller; enforce sign-in + member role. Every record action scoped by BOTH `customer_id == current_user.customer_id` AND `user_id == current_user.id`:

```ruby
def set_payment_method
  @payment_method = Payments::PaymentMethod.for_current_customer
                      .for_user(current_user.id).find(params[:id])
end
```
`setup_intent` calls `Payments::Activities::VaultCard`; `create` confirms/links the returned vault row; `destroy` calls `detach_token` + `mark_removed!`. Subscriptions index/show/cancel scoped to `user_id`.

- [ ] **Tests** — member sees only own cards/subscriptions; cannot reach another member's record (404); cannot reach across tenants; anonymous is redirected to sign-in; admin is NOT admitted to writes (this is not a preview surface). Run, implement, PASS, commit.

### Task 13: Member ViewComponents + Stripe Element Stimulus `[parallel group: frontend]`

**Files:**
- Create: `app/components/payments/member/payment_methods_component.{rb,html.erb}` — lists saved cards (`display_label`, default badge, remove button), an "Add card" panel mounting the Stripe Element.
- Create: `app/components/payments/member/subscriptions_component.{rb,html.erb}` — own subscriptions with linked card + next charge + cancel.
- Create: `app/javascript/controllers/payments/stripe_card_controller.js` — loads Stripe.js with the publishable key, mounts the Payment Element, calls `setup_intent`, confirms the SetupIntent client-side (card never touches our server), POSTs the resulting payment_method id to `create`.
- [ ] Component specs first (render saved cards, empty state, default badge), implement responsive Tailwind markup, verify, commit.

### Task 14: Checkout "save this card" opt-in `[parallel group: frontend + backend]`

**Files:**
- Modify: the card checkout component/flow + `Payments::Activities::Charge`
- [ ] When the gateway has `:tokenized_cards` AND the shopper is an authenticated member, render a "Save this card for future payments" checkbox; when checked, `Charge` passes `setup_future_usage: off_session` + the customer so the card is vaulted on success (vault row created/updated in `HandleWebhook`). Add a request/component test. Commit.

---

## Phase F — QA, release, review

### Task 15: QA sweep (anysys-qa-engineer)
- [ ] Dispatch anysys-qa-engineer to fill RSpec gaps with multi-tenant isolation + authorization focus: gateway, models, flow selector, contracts, activities, cron, components, request specs (admin settings authz + tenant isolation; member self-service authz + user isolation; webhook routing/signature/replay). Honor the stale-test policy.

### Task 16: Release (anysys-release-engineer)
- [ ] `rm -f public/assets/.manifest.json`, rebuild assets, run the touched-scope specs (Tremendous change → full suite per AGENTS.md, since this is a cross-cutting module addition + auth/tenant changes), restart dev server with `SKIP_AUTH=1`, smoke-hit `/81721200/admin/settings/modules/payments/` and `/81721200/member/payments/payment_methods`. Report PASS/FAIL with trimmed output.

### Task 17: Parallel review (anysys-tech-lead + anysys-code-reviewer)
- [ ] Dispatch both in one message: tech-lead checks AGENTS.md conventions (single-file gateway rule honored, four URL areas, tenant `customer_id`/`user_id`, ViewComponent/Tailwind/Stimulus purity, thin models, no PAN columns); code-reviewer checks correctness + security (webhook signature/replay, off-session charge auth, mass-assignment, missing guards, N+1). Address findings (receiving-code-review skill).

---

## Self-Review (against spec)

- Spec §3.1 Base enrichment → Task 1. §3.2 FlowSelector → Task 2. §3.3 Stripe gateway → Task 6. §3.4 vault model + Subscription link → Tasks 4, 5. §3.5 multi-currency → Task 3. §3.6 provisioner → no-op (verified in Task 17). §4 settings UI → Tasks 8–11. §5 member surface → Tasks 12–14. §6 security → enforced in Tasks 4/6/10/12 + reviewed Task 17. §7 testing → woven per task + Task 15. §8 out-of-scope respected (no Connect, no PayPal/Braintree).
- Type/name consistency: `vault_card(user:, return_url:)`, `charge_token(order:, payment:, payment_method:)`, `detach_token(payment_method:)`, `capabilities`, `supported_currencies`, `zero_decimal_currency?` used identically in Base (Task 1), Stripe (Task 6), activities (Task 7). `PaymentMethod#display_label`, `#mark_removed!`, `Subscription#card_recurring?` defined once and reused.
- Placeholder scan: UI markup is intentionally delegated to UX→frontend (Task 8 mockups gate Task 9 markup) — component boundaries, props, and specs are fixed here, which is the codebase's mandated process, not a hidden TODO.

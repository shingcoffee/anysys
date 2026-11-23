# Payment Module Redesign — WeChat Pay + Alipay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing payment FeatureModule stub with a complete multi-tenant payment module that supports WeChat Pay and Alipay only (China), covering charge/refund/reconciliation/subscription flows across QR, H5, and JSAPI.

**Architecture:** A single public facade (`Payments::Gateway`) delegates to stateless per-PSP adapters (`Payments::Adapters::WechatPay`, `::Alipay`). Trailblazer activities orchestrate DB writes + gateway calls + idempotency. A single webhook endpoint dispatches by provider and resolves tenant from payload. Three ViewComponent/Stimulus front-end flows are selected automatically by device.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, Trailblazer (Activity / Reform), dry-rb, RSpec, WebMock, Capybara, ActiveStorage, Rails encrypted attributes.

**Spec:** `docs/superpowers/specs/2026-04-27-payment-module-wechat-alipay-redesign-design.md`

---

## File Structure

### New files

Migrations — `db/migrate/`:
- `YYYYMMDDHHMMSS_drop_old_payment_stub.rb`
- `YYYYMMDDHHMMSS_create_payment_merchant_accounts.rb`
- `YYYYMMDDHHMMSS_create_payment_orders.rb`
- `YYYYMMDDHHMMSS_create_payments.rb`
- `YYYYMMDDHHMMSS_create_payment_refunds.rb`
- `YYYYMMDDHHMMSS_create_payment_subscriptions.rb`
- `YYYYMMDDHHMMSS_create_payment_reconciliation_bills.rb`

Models — `app/models/`:
- `payment_merchant_account.rb`
- `payment_order.rb`
- `payment.rb`
- `payment_refund.rb`
- `payment_subscription.rb`
- `payment_reconciliation_bill.rb`

Services — `app/services/`:
- `feature_modules/payment/registration.rb` (rewrite)
- `feature_modules/payment/provisioner.rb`
- `payments/gateway.rb`
- `payments/flow_selector.rb`
- `payments/credential_resolver.rb`
- `payments/webhook_dispatcher.rb`
- `payments/errors.rb`
- `payments/out_trade_no.rb`
- `payments/adapters/base.rb`
- `payments/adapters/wechat_pay.rb`
- `payments/adapters/alipay.rb`
- `payments/contracts/charge.rb`
- `payments/contracts/refund.rb`
- `payments/contracts/subscribe.rb`
- `payments/activities/charge.rb`
- `payments/activities/refund.rb`
- `payments/activities/query.rb`
- `payments/activities/cancel_subscription.rb`
- `payments/activities/reconcile.rb`
- `payments/activities/handle_webhook.rb`
- `payments/cron/charge_due_subscriptions.rb`
- `payments/cron/download_bills.rb`

Controllers — `app/controllers/payments/`:
- `checkouts_controller.rb`
- `results_controller.rb`
- `webhooks_controller.rb`
- `admin/merchant_accounts_controller.rb`
- `admin/transactions_controller.rb`
- `admin/subscriptions_controller.rb`
- `admin/reconciliations_controller.rb`

Components — `app/components/payments/`:
- `checkout_component.rb` / `.html.erb`
- `qr_code_component.rb` / `.html.erb`
- `h5_redirect_component.rb` / `.html.erb`
- `jsapi_invoker_component.rb` / `.html.erb`
- `waiting_component.rb` / `.html.erb`
- `result_component.rb` / `.html.erb`
- `admin/transaction_table_component.rb` / `.html.erb`
- `admin/refund_dialog_component.rb` / `.html.erb`
- `admin/subscription_table_component.rb` / `.html.erb`
- `admin/reconciliation_table_component.rb` / `.html.erb`
- `admin/merchant_account_form_component.rb` / `.html.erb`

Stimulus — `app/javascript/controllers/payments/`:
- `qr_poll_controller.js`
- `h5_redirect_controller.js`
- `jsapi_invoker_controller.js`

Spec fixtures — `spec/fixtures/payments/`:
- `keys/test_rsa_private.pem`
- `keys/test_rsa_public.pem`
- `wechat/jsapi_prepay.json`
- `wechat/native_prepay.json`
- `wechat/h5_prepay.json`
- `wechat/notify_success.json`
- `wechat/refund_success.json`
- `wechat/bill_all.csv`
- `alipay/qr_precreate.json`
- `alipay/wap_pay.json`
- `alipay/jsapi_create.json`
- `alipay/notify_success.txt`
- `alipay/refund_success.json`
- `alipay/bill_all.csv`

### Modified files
- `config/routes.rb` — add payment routes inside the `/:customer_id` scope + one top-level webhook route.
- `app/services/feature_modules/payment/registration.rb` — rewritten.

### Deleted files
- None (the stub registration is rewritten in place; no sibling payment files exist per exploration).

---

## Tasks Overview

1. Baseline + scaffolding (branch guardrail)
2. Drop-and-recreate the `FeatureModules::Payment::Registration` stub
3. Migrations (6 tables)
4. Models (one task per model)
5. `Payments::OutTradeNo` + `Payments::Errors`
6. `Payments::CredentialResolver`
7. `Payments::FlowSelector`
8. Adapter base interface + `WechatPay` adapter
9. `Alipay` adapter
10. Reform contracts (charge/refund/subscribe)
11. `Payments::Gateway` facade
12. Trailblazer activities (charge/query/refund/handle_webhook/cancel_subscription/reconcile)
13. `Payments::WebhookDispatcher`
14. FeatureModule provisioner
15. Routes
16. Checkout controller + results controller
17. Webhooks controller
18. Admin controllers (merchant accounts / transactions / subscriptions / reconciliations)
19. ViewComponents (checkout / qr / h5 / jsapi / waiting / result)
20. Stimulus controllers (qr_poll / h5_redirect / jsapi_invoker)
21. Admin ViewComponents
22. Cron jobs (ChargeDueSubscriptions / DownloadBills)
23. System specs (QR / H5 / JSAPI / admin refund)
24. Final verification — full `rspec` suite + brakeman

Each task uses RED → GREEN → REFACTOR → COMMIT. Every file-creating step shows the complete content the file must end with at that step.

---

## Conventions

- **All DB migrations:** use `t.references :customer, null: false, foreign_key: true, index: true` and `bigint` ids.
- **Encrypted attrs:** Rails 8 `encrypts :col`.
- **Tenant scoping:** include `TenantScoped` concern (already exists in this codebase — see `app/models/concerns/tenant_scoped.rb`).
- **Commit messages:** short imperative — `"feat(payments): ..."`, `"test(payments): ..."`, `"refactor(payments): ..."`.
- **Every adapter HTTP call:** uses `Net::HTTP` through a thin `Payments::Adapters::Base#http_request` helper that `WebMock` can stub in tests. No external gems for WeChat/Alipay SDKs — we implement signing directly (APIv3 SHA256-RSA for WeChat; RSA2 for Alipay) using Ruby's `OpenSSL`.
- **Money:** `amount_cents` integer. CNY only — validations reject non-CNY at contract layer.
- **Idempotency:** all activities look up existing rows by `out_trade_no` / `out_refund_no` before creating.

---

## Task 1: Baseline guardrail

**Files:**
- Modify: `.rspec` (none if present)
- No code change; a sanity commit marker.

- [ ] **Step 1: Confirm clean tree and branch**

```bash
git status
git branch --show-current
```
Expected: branch `feature-payment-enhancement`, clean working tree.

- [ ] **Step 2: Run a scoped test pass to establish baseline**

```bash
bundle exec rspec spec/services/feature_modules -fd
```
Expected: all green. Record count for comparison at end.

---

## Task 2: Rewrite `FeatureModules::Payment::Registration` stub

**Files:**
- Modify: `app/services/feature_modules/payment/registration.rb`
- Create: `spec/services/feature_modules/payment/registration_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/services/feature_modules/payment/registration_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe FeatureModules::Payment::Registration do
  it "declares module metadata" do
    expect(described_class.module_key).to eq("payment")
    expect(described_class.module_name).to include("WeChat")
    expect(described_class.module_name).to include("Alipay")
  end

  it "builds an entry path per customer" do
    customer = double(id: 42)
    expect(described_class.entry_path_for(customer)).to eq("/42/payments/checkout")
  end

  it "declares CNY-only input contract" do
    form = described_class.input_contract_class.new(OpenStruct.new)
    form.validate(external_ref: "o1", amount_cents: 100, currency: "USD", subject: "x")
    expect(form.errors[:currency]).to be_present
  end

  it "accepts CNY" do
    form = described_class.input_contract_class.new(OpenStruct.new)
    expect(form.validate(external_ref: "o1", amount_cents: 100, currency: "CNY", subject: "x")).to be(true)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb
```
Expected: failure (currency not restricted to CNY yet; entry path returns `/:id/payment/checkout`).

- [ ] **Step 3: Rewrite the registration**

`app/services/feature_modules/payment/registration.rb`:
```ruby
# frozen_string_literal: true

module FeatureModules
  module Payment
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "payment"
      def self.module_name        = "Payments (WeChat + Alipay)"
      def self.module_description = "Accept WeChat Pay and Alipay (China) — charge, refund, reconciliation, subscriptions"

      def self.provision!(customer)   = FeatureModules::Payment::Provisioner.call(customer)
      def self.deprovision!(customer) = FeatureModules::Payment::Provisioner.revoke(customer)

      entry_path   { |customer| "/#{customer.id}/payments/checkout" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :external_ref, validates: { presence: true }
        property :amount_cents, validates: { presence: true, numericality: { greater_than: 0, only_integer: true } }
        property :currency,     validates: { presence: true, inclusion: { in: %w[CNY] } }
        property :subject,      validates: { presence: true }
        property :body
        property :expires_at
        property :metadata
      end

      output_contract do
        property :payment_reference, validates: { presence: true }
        property :status,            validates: { inclusion: { in: %w[succeeded failed] } }
        property :paid_at
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify green**

```bash
bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/services/feature_modules/payment/registration.rb spec/services/feature_modules/payment/registration_spec.rb
git commit -m "feat(payments): rewrite FeatureModule registration for WeChat+Alipay (CNY-only)"
```

---

## Task 3: Migrations

Each sub-task creates one migration. All migrations share these rules: PostgreSQL-friendly types, timestamps, `null: false` on required columns, unique indexes as specified.

### 3.1 `payment_merchant_accounts`

- [ ] **Step 1: Generate migration**

```bash
bin/rails g migration CreatePaymentMerchantAccounts
```

- [ ] **Step 2: Fill migration body**

`db/migrate/<ts>_create_payment_merchant_accounts.rb`:
```ruby
class CreatePaymentMerchantAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_merchant_accounts do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :provider,  null: false
      t.string  :mode,      null: false, default: "sandbox"
      t.string  :merchant_id, null: false
      t.text    :api_key_v3
      t.text    :private_key_pem
      t.text    :platform_public_key_pem
      t.string  :wechat_cert_serial
      t.string  :notify_url_override
      t.string  :status, null: false, default: "disabled"
      t.timestamps
    end
    add_index :payment_merchant_accounts, %i[customer_id provider mode], unique: true,
              name: "idx_payment_accounts_on_cust_prov_mode"
    add_index :payment_merchant_accounts, %i[provider merchant_id], unique: true,
              name: "idx_payment_accounts_on_prov_mch"
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```
Expected: `== CreatePaymentMerchantAccounts: migrated`.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*create_payment_merchant_accounts.rb db/schema.rb
git commit -m "feat(payments): add payment_merchant_accounts table"
```

### 3.2 `payment_orders`

- [ ] **Step 1: Generate + fill**

```ruby
class CreatePaymentOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :external_ref, null: false
      t.integer :amount_cents, null: false
      t.string  :currency,     null: false, default: "CNY"
      t.string  :subject,      null: false
      t.text    :body
      t.string  :status,       null: false, default: "pending"
      t.jsonb   :metadata,     null: false, default: {}
      t.datetime :expires_at
      t.datetime :paid_at
      t.timestamps
    end
    add_index :payment_orders, %i[customer_id external_ref], unique: true
    add_index :payment_orders, :status
  end
end
```

- [ ] **Step 2: Migrate + commit**

```bash
bin/rails db:migrate
git add db/migrate/*create_payment_orders.rb db/schema.rb
git commit -m "feat(payments): add payment_orders table"
```

### 3.3 `payments`

```ruby
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :payment_order, null: false, foreign_key: true
      t.references :customer,      null: false, foreign_key: true
      t.string  :provider, null: false
      t.string  :flow,     null: false
      t.string  :out_trade_no,       null: false
      t.string  :psp_transaction_id
      t.string  :status,   null: false, default: "created"
      t.integer :amount_cents, null: false
      t.jsonb   :prepay_payload, null: false, default: {}
      t.jsonb   :raw_notify,     null: false, default: {}
      t.text    :failure_reason
      t.datetime :paid_at
      t.datetime :closed_at
      t.timestamps
    end
    add_index :payments, :out_trade_no, unique: true
    add_index :payments, %i[provider psp_transaction_id]
  end
end
```

Migrate + commit as in 3.2.

### 3.4 `payment_refunds`

```ruby
class CreatePaymentRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_refunds do |t|
      t.references :payment,  null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string  :out_refund_no, null: false
      t.string  :psp_refund_id
      t.integer :amount_cents, null: false
      t.string  :reason
      t.string  :status, null: false, default: "requested"
      t.datetime :requested_at
      t.datetime :succeeded_at
      t.datetime :failed_at
      t.jsonb   :raw_notify, null: false, default: {}
      t.timestamps
    end
    add_index :payment_refunds, :out_refund_no, unique: true
  end
end
```

### 3.5 `payment_subscriptions`

```ruby
class CreatePaymentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_subscriptions do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :provider,     null: false
      t.string  :external_ref, null: false
      t.string  :plan_name,    null: false
      t.integer :amount_cents, null: false
      t.string  :cycle,        null: false
      t.string  :psp_agreement_id
      t.string  :status, null: false, default: "pending_sign"
      t.datetime :next_charge_at
      t.datetime :signed_at
      t.datetime :cancelled_at
      t.timestamps
    end
    add_index :payment_subscriptions, %i[customer_id external_ref], unique: true
    add_index :payment_subscriptions, %i[provider psp_agreement_id], unique: true,
              where: "psp_agreement_id IS NOT NULL"
  end
end
```

### 3.6 `payment_reconciliation_bills`

```ruby
class CreatePaymentReconciliationBills < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_reconciliation_bills do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :provider,  null: false
      t.date    :bill_date, null: false
      t.string  :bill_type, null: false, default: "all"
      t.integer :total_count,      null: false, default: 0
      t.integer :total_amount_cents, null: false, default: 0
      t.integer :discrepancy_count,  null: false, default: 0
      t.string  :status, null: false, default: "downloading"
      t.jsonb   :raw_summary, null: false, default: {}
      t.timestamps
    end
    add_index :payment_reconciliation_bills,
              %i[customer_id provider bill_date bill_type],
              unique: true,
              name: "idx_recon_bills_on_cust_prov_date_type"
  end
end
```

- [ ] **After all six migrations:** run `bin/rails db:migrate` then commit `db/schema.rb`.

---

## Task 4: Models

### 4.1 `PaymentMerchantAccount`

**Files:**
- Create: `app/models/payment_merchant_account.rb`
- Test: `spec/models/payment_merchant_account_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe PaymentMerchantAccount, type: :model do
  let(:customer) { Customer.create!(id: 10_000_001, name: "T") }
  before { Current.customer = customer }

  it "requires provider, mode, merchant_id" do
    acc = described_class.new
    expect(acc.valid?).to be false
    expect(acc.errors.attribute_names).to include(:provider, :mode, :merchant_id)
  end

  it "validates provider inclusion" do
    acc = described_class.new(provider: "stripe", mode: "sandbox", merchant_id: "x")
    expect(acc.valid?).to be false
    expect(acc.errors[:provider]).to be_present
  end

  it "encrypts api_key_v3 at rest" do
    acc = described_class.create!(provider: "wechat_pay", mode: "sandbox",
                                  merchant_id: "m1", api_key_v3: "secret")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_key_v3 FROM payment_merchant_accounts WHERE id=#{acc.id}"
    )
    expect(raw).not_to include("secret")
    expect(acc.reload.api_key_v3).to eq("secret")
  end

  it "scopes to current customer" do
    other = Customer.create!(id: 10_000_002, name: "O")
    Current.customer = other
    described_class.create!(provider: "alipay", mode: "sandbox", merchant_id: "A")
    Current.customer = customer
    expect(described_class.all).to be_empty
  end
end
```

- [ ] **Step 2: Implement**

`app/models/payment_merchant_account.rb`:
```ruby
# frozen_string_literal: true

class PaymentMerchantAccount < ApplicationRecord
  include TenantScoped

  PROVIDERS = %w[wechat_pay alipay].freeze
  MODES     = %w[sandbox production].freeze
  STATUSES  = %w[active disabled].freeze

  encrypts :api_key_v3
  encrypts :private_key_pem
  encrypts :platform_public_key_pem

  validates :provider,    presence: true, inclusion: { in: PROVIDERS }
  validates :mode,        presence: true, inclusion: { in: MODES }
  validates :merchant_id, presence: true
  validates :status,      inclusion: { in: STATUSES }
  validates :customer_id, presence: true
  validates :mode, uniqueness: { scope: %i[customer_id provider] }

  scope :active, -> { where(status: "active") }

  def enabled? = status == "active"

  def wechat? = provider == "wechat_pay"
  def alipay? = provider == "alipay"
end
```

- [ ] **Step 3: Green + commit**

```bash
bundle exec rspec spec/models/payment_merchant_account_spec.rb
git add app/models/payment_merchant_account.rb spec/models/payment_merchant_account_spec.rb
git commit -m "feat(payments): PaymentMerchantAccount model with encrypted creds"
```

### 4.2 `PaymentOrder`

- [ ] **Spec** (`spec/models/payment_order_spec.rb`):

```ruby
require "rails_helper"

RSpec.describe PaymentOrder, type: :model do
  let(:customer) { Customer.create!(id: 10_000_003, name: "T") }
  before { Current.customer = customer }

  it "requires external_ref, amount_cents, subject, currency=CNY" do
    o = described_class.new
    expect(o).not_to be_valid
    expect(o.errors.attribute_names).to include(:external_ref, :amount_cents, :subject)
  end

  it "rejects non-CNY currency" do
    o = described_class.new(external_ref: "r", amount_cents: 100, subject: "s", currency: "USD")
    expect(o).not_to be_valid
    expect(o.errors[:currency]).to be_present
  end

  it "allows one external_ref per customer" do
    described_class.create!(external_ref: "r1", amount_cents: 100, subject: "s")
    dup = described_class.new(external_ref: "r1", amount_cents: 100, subject: "s")
    expect(dup).not_to be_valid
  end

  it "transitions to paid! on mark_paid!" do
    o = described_class.create!(external_ref: "r2", amount_cents: 100, subject: "s")
    o.mark_paid!(Time.zone.now)
    expect(o.reload.status).to eq("paid")
  end
end
```

- [ ] **Implementation** (`app/models/payment_order.rb`):

```ruby
# frozen_string_literal: true

class PaymentOrder < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending paid partial_refund refunded closed failed].freeze

  has_many :payments, dependent: :destroy

  validates :external_ref, presence: true, uniqueness: { scope: :customer_id }
  validates :amount_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :currency,     presence: true, inclusion: { in: %w[CNY] }
  validates :subject,      presence: true
  validates :status,       inclusion: { in: STATUSES }
  validates :customer_id,  presence: true

  def mark_paid!(at)
    update!(status: "paid", paid_at: at)
  end

  def mark_failed!
    update!(status: "failed")
  end

  def mark_closed!
    update!(status: "closed")
  end
end
```

Commit.

### 4.3 `Payment`

- [ ] **Spec highlights** (`spec/models/payment_spec.rb`):

```ruby
require "rails_helper"

RSpec.describe Payment, type: :model do
  let(:customer) { Customer.create!(id: 10_000_004, name: "T") }
  let(:order)    { PaymentOrder.create!(external_ref: "o", amount_cents: 100, subject: "s") }
  before { Current.customer = customer }

  it "requires provider, flow, out_trade_no, amount_cents" do
    p = described_class.new(payment_order: order)
    expect(p).not_to be_valid
  end

  it "validates provider and flow inclusion" do
    p = described_class.new(payment_order: order, provider: "visa", flow: "pos",
                            out_trade_no: "t1", amount_cents: 100)
    expect(p).not_to be_valid
    expect(p.errors[:provider]).to be_present
    expect(p.errors[:flow]).to be_present
  end

  it "enforces out_trade_no uniqueness" do
    described_class.create!(payment_order: order, provider: "alipay", flow: "qr",
                            out_trade_no: "t1", amount_cents: 100)
    dup = described_class.new(payment_order: order, provider: "alipay", flow: "qr",
                              out_trade_no: "t1", amount_cents: 100)
    expect(dup).not_to be_valid
  end

  it "transitions succeeded!/failed!/closed! idempotently" do
    p = described_class.create!(payment_order: order, provider: "alipay", flow: "qr",
                                out_trade_no: "t2", amount_cents: 100)
    p.mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: { foo: 1 })
    expect(p.reload.status).to eq("succeeded")
    expect { p.mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: { foo: 1 }) }.not_to raise_error
  end
end
```

- [ ] **Implementation** (`app/models/payment.rb`):

```ruby
# frozen_string_literal: true

class Payment < ApplicationRecord
  include TenantScoped

  PROVIDERS = %w[wechat_pay alipay].freeze
  FLOWS     = %w[qr h5 jsapi].freeze
  STATUSES  = %w[created pending succeeded failed closed].freeze

  belongs_to :payment_order
  has_many :payment_refunds, dependent: :destroy

  validates :provider,     presence: true, inclusion: { in: PROVIDERS }
  validates :flow,         presence: true, inclusion: { in: FLOWS }
  validates :out_trade_no, presence: true, uniqueness: true
  validates :amount_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :status,       inclusion: { in: STATUSES }
  validates :customer_id,  presence: true

  def mark_pending!(prepay_payload)
    return if status == "pending"
    update!(status: "pending", prepay_payload: prepay_payload)
  end

  def mark_succeeded!(psp_id:, at:, notify:)
    return if status == "succeeded"
    update!(status: "succeeded", psp_transaction_id: psp_id, paid_at: at, raw_notify: notify)
    payment_order.mark_paid!(at)
  end

  def mark_failed!(reason:, notify: {})
    return if status == "failed"
    update!(status: "failed", failure_reason: reason, raw_notify: notify)
    payment_order.mark_failed!
  end

  def mark_closed!
    return if status == "closed"
    update!(status: "closed", closed_at: Time.zone.now)
  end
end
```

Commit.

### 4.4 `PaymentRefund`

- [ ] **Spec** (essentials) (`spec/models/payment_refund_spec.rb`): presence of `payment`, `customer_id`, `out_refund_no` uniqueness, `status` inclusion in `%w[requested processing succeeded failed]`, `mark_succeeded!(at:, psp_refund_id:, notify:)` idempotent.

- [ ] **Implementation** (`app/models/payment_refund.rb`):

```ruby
# frozen_string_literal: true

class PaymentRefund < ApplicationRecord
  include TenantScoped

  STATUSES = %w[requested processing succeeded failed].freeze

  belongs_to :payment

  validates :out_refund_no, presence: true, uniqueness: true
  validates :amount_cents,  presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :status,        inclusion: { in: STATUSES }
  validates :customer_id,   presence: true

  def mark_processing!  = (status == "processing" ? self : update!(status: "processing"))
  def mark_succeeded!(at:, psp_refund_id:, notify:)
    return if status == "succeeded"
    update!(status: "succeeded", succeeded_at: at,
            psp_refund_id: psp_refund_id, raw_notify: notify)
    recalc_order_status!
  end

  def mark_failed!(notify:)
    return if status == "failed"
    update!(status: "failed", failed_at: Time.zone.now, raw_notify: notify)
  end

  private

  def recalc_order_status!
    order = payment.payment_order
    refunded = order.payments
                    .joins(:payment_refunds)
                    .where(payment_refunds: { status: "succeeded" })
                    .sum("payment_refunds.amount_cents")
    new_status = refunded >= order.amount_cents ? "refunded" : "partial_refund"
    order.update!(status: new_status)
  end
end
```

Commit.

### 4.5 `PaymentSubscription`

- [ ] **Spec** — validations: provider inclusion, cycle in `%w[daily weekly monthly yearly]`, status in the five declared values, unique `[customer_id, external_ref]`. `mark_active!(psp_agreement_id:, at:)`, `mark_cancelled!`.

- [ ] **Implementation** (`app/models/payment_subscription.rb`):

```ruby
# frozen_string_literal: true

class PaymentSubscription < ApplicationRecord
  include TenantScoped

  PROVIDERS = %w[wechat_pay alipay].freeze
  CYCLES    = %w[daily weekly monthly yearly].freeze
  STATUSES  = %w[pending_sign active paused cancelled expired].freeze

  validates :provider,     inclusion: { in: PROVIDERS }
  validates :external_ref, presence: true, uniqueness: { scope: :customer_id }
  validates :plan_name,    presence: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validates :cycle,        inclusion: { in: CYCLES }
  validates :status,       inclusion: { in: STATUSES }
  validates :customer_id,  presence: true

  scope :due_now, -> { where(status: "active").where("next_charge_at <= ?", Time.zone.now) }

  def mark_active!(psp_agreement_id:, at:)
    update!(status: "active", psp_agreement_id: psp_agreement_id,
            signed_at: at, next_charge_at: next_charge_time_from(at))
  end

  def mark_cancelled!
    update!(status: "cancelled", cancelled_at: Time.zone.now)
  end

  def advance_next_charge!
    update!(next_charge_at: next_charge_time_from(Time.zone.now))
  end

  private

  def next_charge_time_from(t)
    case cycle
    when "daily"   then t + 1.day
    when "weekly"  then t + 1.week
    when "monthly" then t + 1.month
    when "yearly"  then t + 1.year
    end
  end
end
```

Commit.

### 4.6 `PaymentReconciliationBill`

- [ ] **Spec** — unique `[customer_id, provider, bill_date, bill_type]`, status inclusion in `%w[downloading parsed reconciled discrepant failed]`, `mark_parsed!`, `mark_reconciled!(discrepancies:)`.

- [ ] **Implementation** (`app/models/payment_reconciliation_bill.rb`):

```ruby
# frozen_string_literal: true

class PaymentReconciliationBill < ApplicationRecord
  include TenantScoped

  PROVIDERS  = %w[wechat_pay alipay].freeze
  BILL_TYPES = %w[all success refund].freeze
  STATUSES   = %w[downloading parsed reconciled discrepant failed].freeze

  has_one_attached :bill_file

  validates :provider,   inclusion: { in: PROVIDERS }
  validates :bill_type,  inclusion: { in: BILL_TYPES }
  validates :status,     inclusion: { in: STATUSES }
  validates :bill_date,  presence: true
  validates :customer_id, presence: true
  validates :bill_date, uniqueness: { scope: %i[customer_id provider bill_type] }

  def mark_parsed!(total_count:, total_amount_cents:, raw_summary:)
    update!(status: "parsed", total_count:, total_amount_cents:, raw_summary:)
  end

  def mark_reconciled!(discrepancies:)
    update!(status: discrepancies.positive? ? "discrepant" : "reconciled",
            discrepancy_count: discrepancies)
  end

  def mark_failed! = update!(status: "failed")
end
```

Commit.

---

## Task 5: Utilities — `Payments::Errors` + `Payments::OutTradeNo`

**Files:**
- Create: `app/services/payments/errors.rb`
- Create: `app/services/payments/out_trade_no.rb`
- Test: `spec/services/payments/out_trade_no_spec.rb`

- [ ] **Step 1: Errors**

```ruby
# frozen_string_literal: true
module Payments
  module Errors
    class Error             < StandardError; end
    class CredentialsMissing < Error; end
    class TransportError     < Error; end
    class ApiError           < Error
      attr_reader :code, :payload
      def initialize(message, code: nil, payload: {})
        super(message); @code = code; @payload = payload
      end
    end
    class SignatureInvalid   < Error; end
    class TenantNotFound     < Error; end
  end
end
```

- [ ] **Step 2: OutTradeNo spec**

```ruby
require "rails_helper"

RSpec.describe Payments::OutTradeNo do
  it "is unique and ≤ 32 chars with a prefix" do
    a = described_class.generate(prefix: "ch", customer_id: 10_000_001)
    b = described_class.generate(prefix: "ch", customer_id: 10_000_001)
    expect(a).not_to eq(b)
    expect(a.length).to be <= 32
    expect(a).to start_with("ch-")
  end
end
```

- [ ] **Step 3: Implementation**

```ruby
# frozen_string_literal: true
require "securerandom"
module Payments
  module OutTradeNo
    module_function
    def generate(prefix:, customer_id:)
      ts  = Time.now.strftime("%y%m%d%H%M%S")
      rnd = SecureRandom.alphanumeric(6).downcase
      "#{prefix}-#{customer_id % 100_000_000}-#{ts}#{rnd}"[0, 32]
    end
  end
end
```

- [ ] **Step 4: Green + commit**

---

## Task 6: `Payments::CredentialResolver`

**Files:**
- Create: `app/services/payments/credential_resolver.rb`
- Test: `spec/services/payments/credential_resolver_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe Payments::CredentialResolver do
  let(:customer) { Customer.create!(id: 10_000_005, name: "T") }
  before { Current.customer = customer }

  it "returns the active account for provider+mode" do
    acc = PaymentMerchantAccount.create!(provider: "wechat_pay", mode: "production",
                                         merchant_id: "m1", status: "active")
    expect(described_class.call(customer: customer, provider: "wechat_pay", mode: "production")).to eq(acc)
  end

  it "raises CredentialsMissing when absent or disabled" do
    expect {
      described_class.call(customer: customer, provider: "alipay", mode: "production")
    }.to raise_error(Payments::Errors::CredentialsMissing)

    PaymentMerchantAccount.create!(provider: "alipay", mode: "production",
                                   merchant_id: "a", status: "disabled")
    expect {
      described_class.call(customer: customer, provider: "alipay", mode: "production")
    }.to raise_error(Payments::Errors::CredentialsMissing)
  end

  it "can resolve by [provider, merchant_id] for webhooks" do
    PaymentMerchantAccount.create!(provider: "wechat_pay", mode: "production",
                                   merchant_id: "wx123", status: "active")
    acc = described_class.by_merchant_id(provider: "wechat_pay", merchant_id: "wx123")
    expect(acc.customer_id).to eq(customer.id)
  end
end
```

- [ ] **Step 2: Implementation**

```ruby
# frozen_string_literal: true
module Payments
  class CredentialResolver
    def self.call(customer:, provider:, mode: Rails.env.production? ? "production" : "sandbox")
      acc = PaymentMerchantAccount.where(customer_id: customer.id,
                                         provider: provider, mode: mode,
                                         status: "active").first
      raise Payments::Errors::CredentialsMissing,
            "No active #{provider} account for customer #{customer.id} in #{mode}" unless acc
      acc
    end

    def self.by_merchant_id(provider:, merchant_id:)
      PaymentMerchantAccount.unscoped_by_tenant
                            .where(provider: provider, merchant_id: merchant_id, status: "active")
                            .first or raise Payments::Errors::TenantNotFound,
                                            "No active #{provider} account for merchant_id #{merchant_id}"
    end
  end
end
```

- [ ] **Step 3: Green + commit**

---

## Task 7: `Payments::FlowSelector`

**Files:**
- Create: `app/services/payments/flow_selector.rb`
- Test: `spec/services/payments/flow_selector_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe Payments::FlowSelector do
  def req(ua) = instance_double(ActionDispatch::Request, user_agent: ua)

  it "returns :jsapi inside WeChat browser for wechat_pay" do
    ua = "Mozilla/5.0 ... MicroMessenger/8.0"
    expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:jsapi)
  end

  it "returns :jsapi inside Alipay browser for alipay" do
    ua = "Mozilla/5.0 ... AlipayClient/10.2"
    expect(described_class.call(request: req(ua), provider: "alipay")).to eq(:jsapi)
  end

  it "returns :h5 on mobile browser outside PSP apps" do
    ua = "Mozilla/5.0 (iPhone; ... Mobile Safari)"
    expect(described_class.call(request: req(ua), provider: "alipay")).to eq(:h5)
    expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:h5)
  end

  it "returns :qr on desktop" do
    ua = "Mozilla/5.0 (Macintosh; ...) Chrome"
    expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:qr)
  end
end
```

- [ ] **Step 2: Implementation**

```ruby
# frozen_string_literal: true
module Payments
  class FlowSelector
    WECHAT_UA = /MicroMessenger/i
    ALIPAY_UA = /AlipayClient/i
    MOBILE_UA = /Mobile|Android|iPhone|iPad/i

    def self.call(request:, provider:)
      ua = request.user_agent.to_s
      return :jsapi if provider == "wechat_pay" && ua.match?(WECHAT_UA)
      return :jsapi if provider == "alipay"     && ua.match?(ALIPAY_UA)
      return :h5    if ua.match?(MOBILE_UA)
      :qr
    end
  end
end
```

- [ ] **Step 3: Green + commit**

---

## Task 8: Adapter base + `WechatPay` adapter

### 8.1 `Adapters::Base`

**Files:**
- Create: `app/services/payments/adapters/base.rb`

- [ ] **Step 1: Implementation (no test — abstract class)**

```ruby
# frozen_string_literal: true
require "net/http"
require "uri"
require "json"
module Payments
  module Adapters
    class Base
      def initialize(account:)
        @account = account
      end

      def charge(order:, payment:, flow:, openid: nil);          raise NotImplementedError; end
      def query(payment:);                                       raise NotImplementedError; end
      def refund(payment:, refund:);                             raise NotImplementedError; end
      def close(payment:);                                       raise NotImplementedError; end
      def subscribe(subscription:);                              raise NotImplementedError; end
      def cancel_subscription(subscription:);                    raise NotImplementedError; end
      def charge_subscription(subscription:, payment:);          raise NotImplementedError; end
      def download_bill(bill_date:, bill_type:);                 raise NotImplementedError; end
      def verify_notification(headers:, body:);                  raise NotImplementedError; end

      protected

      attr_reader :account

      def http_post(url, body:, headers: {})
        uri  = URI(url)
        req  = Net::HTTP::Post.new(uri)
        headers.each { |k, v| req[k] = v }
        req.body = body.is_a?(String) ? body : body.to_json
        do_request(uri, req)
      end

      def http_get(url, headers: {})
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        headers.each { |k, v| req[k] = v }
        do_request(uri, req)
      end

      def do_request(uri, req)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        res = http.request(req)
        return res if res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
        raise Payments::Errors::ApiError.new("HTTP #{res.code} from #{uri.host}",
                                             code: res.code, payload: safe_json(res.body))
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
        raise Payments::Errors::TransportError, e.message
      end

      def safe_json(str)
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end
    end
  end
end
```

Commit with no spec (exercised via subclasses).

### 8.2 `Adapters::WechatPay`

**Files:**
- Create: `app/services/payments/adapters/wechat_pay.rb`
- Test: `spec/services/payments/adapters/wechat_pay_spec.rb`
- Fixture: `spec/fixtures/payments/wechat/native_prepay.json`, `notify_success.json`, `refund_success.json`, `bill_all.csv`, `keys/test_rsa_private.pem`, `keys/test_rsa_public.pem`

- [ ] **Step 1: Create fixture RSA keys** (one-time, manual step — engineer runs locally):

```bash
openssl genrsa -out spec/fixtures/payments/keys/test_rsa_private.pem 2048
openssl rsa -in spec/fixtures/payments/keys/test_rsa_private.pem \
            -pubout -out spec/fixtures/payments/keys/test_rsa_public.pem
```

- [ ] **Step 2: Write fixture files**

`spec/fixtures/payments/wechat/native_prepay.json`:
```json
{"code_url":"weixin://wxpay/bizpayurl?pr=abcd1234"}
```

`spec/fixtures/payments/wechat/notify_success.json`:
```json
{"id":"EV-xyz","event_type":"TRANSACTION.SUCCESS","resource":{"ciphertext":"<encrypted>","associated_data":"transaction","nonce":"1234567890ab"}}
```

`spec/fixtures/payments/wechat/refund_success.json`:
```json
{"refund_id":"50300000001","out_refund_no":"rf-1","status":"SUCCESS","amount":{"refund":100,"currency":"CNY"}}
```

`spec/fixtures/payments/wechat/bill_all.csv`:
```
trade_no,out_trade_no,amount
T1,OT-1,100
T2,OT-2,200
```

- [ ] **Step 3: Spec (focuses on signing + response parsing, not full PSP simulation)**

```ruby
require "rails_helper"
require "webmock/rspec"

RSpec.describe Payments::Adapters::WechatPay do
  let(:customer) { Customer.create!(id: 10_000_006, name: "T") }
  let(:private_pem) { File.read("spec/fixtures/payments/keys/test_rsa_private.pem") }
  let(:public_pem)  { File.read("spec/fixtures/payments/keys/test_rsa_public.pem") }
  before { Current.customer = customer }

  let(:account) do
    PaymentMerchantAccount.create!(
      provider: "wechat_pay", mode: "sandbox", merchant_id: "wx_m1",
      api_key_v3: "apikey", private_key_pem: private_pem,
      platform_public_key_pem: public_pem, wechat_cert_serial: "SER1",
      status: "active"
    )
  end

  let(:adapter) { described_class.new(account: account) }
  let(:order)   { PaymentOrder.create!(external_ref: "e1", amount_cents: 100, subject: "x") }
  let(:payment) do
    Payment.create!(payment_order: order, provider: "wechat_pay", flow: "qr",
                    out_trade_no: "ot-1", amount_cents: 100)
  end

  it "charges via Native (QR) API and returns code_url" do
    stub_request(:post, %r{/v3/pay/transactions/native})
      .to_return(status: 200,
                 body: File.read("spec/fixtures/payments/wechat/native_prepay.json"),
                 headers: { "Content-Type" => "application/json" })
    result = adapter.charge(order: order, payment: payment, flow: :qr)
    expect(result[:prepay_payload]).to include(:code_url)
  end

  it "signs requests with APIv3 RSA-SHA256 (Authorization header present)" do
    stub = stub_request(:post, %r{/v3/pay/transactions/native})
             .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
    adapter.charge(order: order, payment: payment, flow: :qr) rescue nil
    expect(stub).to have_been_requested
    expect(WebMock.requests_hash.values.flatten.last.headers["Authorization"]).to include("WECHATPAY2-SHA256-RSA2048")
  end

  it "raises SignatureInvalid when notification signature fails" do
    expect {
      adapter.verify_notification(headers: { "Wechatpay-Signature" => "bad" }, body: "{}")
    }.to raise_error(Payments::Errors::SignatureInvalid)
  end
end
```

- [ ] **Step 4: Implementation**

```ruby
# frozen_string_literal: true
require "openssl"
require "base64"
require "securerandom"

module Payments
  module Adapters
    class WechatPay < Base
      HOST = "https://api.mch.weixin.qq.com"

      def charge(order:, payment:, flow:, openid: nil)
        path, body = build_charge(order, payment, flow, openid)
        res = http_post(HOST + path, body: body, headers: auth_headers("POST", path, body.to_json))
        json = safe_json(res.body)
        prepay =
          case flow
          when :qr    then { code_url: json["code_url"] }
          when :h5    then { h5_url: json["h5_url"] }
          when :jsapi then jsapi_params(json["prepay_id"])
          end
        { prepay_payload: prepay }
      end

      def query(payment:)
        path = "/v3/pay/transactions/out-trade-no/#{payment.out_trade_no}?mchid=#{account.merchant_id}"
        res = http_get(HOST + path, headers: auth_headers("GET", path, ""))
        json = safe_json(res.body)
        {
          status: map_status(json["trade_state"]),
          psp_transaction_id: json["transaction_id"],
          raw: json
        }
      end

      def refund(payment:, refund:)
        path = "/v3/refund/domestic/refunds"
        body = {
          out_trade_no: payment.out_trade_no,
          out_refund_no: refund.out_refund_no,
          amount: { refund: refund.amount_cents, total: payment.amount_cents, currency: "CNY" },
          reason: refund.reason
        }
        res = http_post(HOST + path, body: body, headers: auth_headers("POST", path, body.to_json))
        json = safe_json(res.body)
        { psp_refund_id: json["refund_id"], status: map_refund_status(json["status"]), raw: json }
      end

      def close(payment:)
        path = "/v3/pay/transactions/out-trade-no/#{payment.out_trade_no}/close"
        body = { mchid: account.merchant_id }
        http_post(HOST + path, body: body, headers: auth_headers("POST", path, body.to_json))
        { status: :closed }
      end

      def subscribe(subscription:)
        raise NotImplementedError, "WeChat contract-pay stub — requires merchant permissions"
      end

      def cancel_subscription(subscription:)
        raise NotImplementedError, "WeChat contract-pay stub"
      end

      def charge_subscription(subscription:, payment:)
        raise NotImplementedError, "WeChat contract-pay stub"
      end

      def download_bill(bill_date:, bill_type:)
        path = "/v3/bill/tradebill?bill_date=#{bill_date.strftime('%Y-%m-%d')}&bill_type=#{bill_type.upcase}"
        res  = http_get(HOST + path, headers: auth_headers("GET", path, ""))
        json = safe_json(res.body)
        dl   = http_get(json["download_url"])
        { csv: dl.body, raw_summary: json }
      end

      def verify_notification(headers:, body:)
        sig_b64 = headers["Wechatpay-Signature"] || headers["wechatpay-signature"]
        ts      = headers["Wechatpay-Timestamp"] || headers["wechatpay-timestamp"]
        nonce   = headers["Wechatpay-Nonce"]     || headers["wechatpay-nonce"]
        raise Payments::Errors::SignatureInvalid, "missing signature headers" unless sig_b64 && ts && nonce
        message   = "#{ts}\n#{nonce}\n#{body}\n"
        public_key = OpenSSL::PKey::RSA.new(account.platform_public_key_pem)
        signature  = Base64.decode64(sig_b64)
        unless public_key.verify(OpenSSL::Digest::SHA256.new, signature, message)
          raise Payments::Errors::SignatureInvalid, "invalid signature"
        end
        safe_json(body)
      end

      private

      def build_charge(order, payment, flow, openid)
        path =
          case flow
          when :qr    then "/v3/pay/transactions/native"
          when :h5    then "/v3/pay/transactions/h5"
          when :jsapi then "/v3/pay/transactions/jsapi"
          end
        body = {
          appid: account.wechat_cert_serial && ENV["WECHAT_APPID"],
          mchid: account.merchant_id,
          description: order.subject,
          out_trade_no: payment.out_trade_no,
          notify_url: notify_url,
          amount: { total: order.amount_cents, currency: "CNY" }
        }
        body[:payer] = { openid: openid } if flow == :jsapi && openid
        [path, body]
      end

      def auth_headers(method, path, body)
        ts    = Time.now.to_i.to_s
        nonce = SecureRandom.hex(16)
        signing_string = "#{method}\n#{path}\n#{ts}\n#{nonce}\n#{body}\n"
        key       = OpenSSL::PKey::RSA.new(account.private_key_pem)
        signature = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, signing_string))
        token = %Q(mchid="#{account.merchant_id}",serial_no="#{account.wechat_cert_serial}",nonce_str="#{nonce}",timestamp="#{ts}",signature="#{signature}")
        {
          "Authorization" => "WECHATPAY2-SHA256-RSA2048 #{token}",
          "Content-Type"  => "application/json",
          "Accept"        => "application/json"
        }
      end

      def jsapi_params(prepay_id)
        ts    = Time.now.to_i.to_s
        nonce = SecureRandom.hex(16)
        package = "prepay_id=#{prepay_id}"
        signing = "#{ENV['WECHAT_APPID']}\n#{ts}\n#{nonce}\n#{package}\n"
        key = OpenSSL::PKey::RSA.new(account.private_key_pem)
        sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, signing))
        { appId: ENV["WECHAT_APPID"], timeStamp: ts, nonceStr: nonce, package: package, signType: "RSA", paySign: sig }
      end

      def map_status(state)
        case state
        when "SUCCESS" then :succeeded
        when "NOTPAY", "USERPAYING" then :pending
        when "CLOSED", "REVOKED"    then :closed
        else :failed
        end
      end

      def map_refund_status(s)
        case s
        when "SUCCESS"               then :succeeded
        when "PROCESSING"            then :processing
        when "CLOSED", "ABNORMAL"    then :failed
        else :processing
        end
      end

      def notify_url
        account.notify_url_override.presence ||
          Rails.application.routes.url_helpers.payments_webhook_url(provider: "wechat_pay",
                                                                    host: ENV["APP_HOST"] || "localhost")
      end
    end
  end
end
```

- [ ] **Step 5: Run + commit**

---

## Task 9: `Adapters::Alipay`

**Files:**
- Create: `app/services/payments/adapters/alipay.rb`
- Test: `spec/services/payments/adapters/alipay_spec.rb`
- Fixtures: `spec/fixtures/payments/alipay/qr_precreate.json`, `wap_pay.json`, `jsapi_create.json`, `notify_success.txt`, `refund_success.json`, `bill_all.csv`

- [ ] **Step 1: Fixtures**

`qr_precreate.json`:
```json
{"alipay_trade_precreate_response":{"code":"10000","msg":"Success","out_trade_no":"ot-1","qr_code":"https://qr.alipay.com/bax01234"}}
```

`refund_success.json`:
```json
{"alipay_trade_refund_response":{"code":"10000","msg":"Success","trade_no":"2026042722001","fund_change":"Y"}}
```

`notify_success.txt`: a form-encoded Alipay notify string (engineer builds a deterministic one using the fixture keys).

- [ ] **Step 2: Spec**

```ruby
require "rails_helper"
require "webmock/rspec"

RSpec.describe Payments::Adapters::Alipay do
  let(:customer) { Customer.create!(id: 10_000_007, name: "T") }
  before { Current.customer = customer }
  let(:priv) { File.read("spec/fixtures/payments/keys/test_rsa_private.pem") }
  let(:pub)  { File.read("spec/fixtures/payments/keys/test_rsa_public.pem") }

  let(:account) do
    PaymentMerchantAccount.create!(provider: "alipay", mode: "sandbox",
                                   merchant_id: "2088app",
                                   private_key_pem: priv,
                                   platform_public_key_pem: pub, status: "active")
  end
  let(:order)   { PaymentOrder.create!(external_ref: "e1", amount_cents: 100, subject: "x") }
  let(:payment) { Payment.create!(payment_order: order, provider: "alipay", flow: "qr",
                                  out_trade_no: "ot-1", amount_cents: 100) }
  let(:adapter) { described_class.new(account: account) }

  it "charges via alipay.trade.precreate for QR flow" do
    stub_request(:post, %r{openapi.alipay.com/gateway})
      .to_return(status: 200,
                 body: File.read("spec/fixtures/payments/alipay/qr_precreate.json"),
                 headers: { "Content-Type" => "application/json" })
    res = adapter.charge(order: order, payment: payment, flow: :qr)
    expect(res[:prepay_payload][:qr_code]).to start_with("https://qr.alipay.com/")
  end

  it "signs with RSA2 — sign param present" do
    stub = stub_request(:post, %r{openapi.alipay.com/gateway}).to_return(status: 200, body: "{}")
    adapter.charge(order: order, payment: payment, flow: :qr) rescue nil
    body = WebMock.requests_hash.values.flatten.last.body
    expect(body).to include("sign=")
    expect(body).to include("sign_type=RSA2")
  end
end
```

- [ ] **Step 3: Implementation**

```ruby
# frozen_string_literal: true
require "openssl"
require "base64"
require "cgi"
module Payments
  module Adapters
    class Alipay < Base
      GATEWAY = "https://openapi.alipay.com/gateway.do"

      def charge(order:, payment:, flow:, openid: nil)
        method = flow_method(flow)
        biz = {
          out_trade_no: payment.out_trade_no,
          total_amount: format("%.2f", order.amount_cents / 100.0),
          subject: order.subject
        }
        biz[:buyer_id] = openid if flow == :jsapi && openid
        res = call_api(method, biz)
        root = "#{method.tr('.', '_')}_response"
        data = res[root] || {}
        raise Payments::Errors::ApiError.new(data["msg"] || "unknown", code: data["code"]) if data["code"] != "10000"
        prepay =
          case flow
          when :qr    then { qr_code: data["qr_code"] }
          when :h5    then { h5_url: build_wap_url(payment, order) }
          when :jsapi then { trade_no: data["trade_no"] }
          end
        { prepay_payload: prepay }
      end

      def query(payment:)
        res  = call_api("alipay.trade.query", { out_trade_no: payment.out_trade_no })
        data = res["alipay_trade_query_response"] || {}
        { status: map_status(data["trade_status"]), psp_transaction_id: data["trade_no"], raw: data }
      end

      def refund(payment:, refund:)
        res  = call_api("alipay.trade.refund", {
          out_trade_no: payment.out_trade_no,
          out_request_no: refund.out_refund_no,
          refund_amount: format("%.2f", refund.amount_cents / 100.0),
          refund_reason: refund.reason
        })
        data = res["alipay_trade_refund_response"] || {}
        raise Payments::Errors::ApiError.new(data["msg"] || "unknown", code: data["code"]) if data["code"] != "10000"
        { psp_refund_id: data["trade_no"], status: :succeeded, raw: data }
      end

      def close(payment:)
        call_api("alipay.trade.close", { out_trade_no: payment.out_trade_no })
        { status: :closed }
      end

      def subscribe(subscription:)
        # Agreement-pay: returns a sign URL
        biz = {
          product_code: "CYCLE_PAY_AUTH",
          agreement_no: subscription.external_ref,
          period_type: subscription.cycle.upcase,
          execute_time: Date.today.strftime("%Y-%m-%d"),
          single_amount: format("%.2f", subscription.amount_cents / 100.0)
        }
        res  = call_api("alipay.user.agreement.page.sign", biz)
        data = res["alipay_user_agreement_page_sign_response"] || {}
        { sign_url_or_params: data["sign_str"] }
      end

      def cancel_subscription(subscription:)
        call_api("alipay.user.agreement.unsign", { agreement_no: subscription.psp_agreement_id })
        { status: :cancelled }
      end

      def charge_subscription(subscription:, payment:)
        biz = {
          out_trade_no: payment.out_trade_no,
          total_amount: format("%.2f", subscription.amount_cents / 100.0),
          subject: subscription.plan_name,
          agreement_params: { agreement_no: subscription.psp_agreement_id }
        }
        res  = call_api("alipay.trade.pay", biz)
        data = res["alipay_trade_pay_response"] || {}
        raise Payments::Errors::ApiError.new(data["msg"] || "unknown", code: data["code"]) if data["code"] != "10000"
        { psp_transaction_id: data["trade_no"], raw: data }
      end

      def download_bill(bill_date:, bill_type:)
        res  = call_api("alipay.data.dataservice.bill.downloadurl.query",
                        { bill_type: bill_type.upcase, bill_date: bill_date.strftime("%Y-%m-%d") })
        data = res["alipay_data_dataservice_bill_downloadurl_query_response"] || {}
        dl   = http_get(data["bill_download_url"])
        { csv: dl.body, raw_summary: data }
      end

      def verify_notification(headers:, body:)
        # Alipay sends form-encoded with `sign` + `sign_type` fields
        params = CGI.parse(body).transform_values(&:first)
        sign   = params.delete("sign")
        params.delete("sign_type")
        to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        public_key = OpenSSL::PKey::RSA.new(account.platform_public_key_pem)
        unless public_key.verify(OpenSSL::Digest::SHA256.new, Base64.decode64(sign), to_sign)
          raise Payments::Errors::SignatureInvalid, "invalid alipay signature"
        end
        params
      end

      private

      def flow_method(flow)
        case flow
        when :qr    then "alipay.trade.precreate"
        when :h5    then "alipay.trade.wap.pay"
        when :jsapi then "alipay.trade.create"
        end
      end

      def call_api(method, biz_content)
        params = {
          app_id: account.merchant_id,
          method: method,
          format: "JSON",
          charset: "utf-8",
          sign_type: "RSA2",
          timestamp: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
          version: "1.0",
          notify_url: notify_url,
          biz_content: biz_content.to_json
        }
        to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        key     = OpenSSL::PKey::RSA.new(account.private_key_pem)
        params[:sign] = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, to_sign))
        res = http_post(GATEWAY,
                        body: URI.encode_www_form(params),
                        headers: { "Content-Type" => "application/x-www-form-urlencoded" })
        safe_json(res.body)
      end

      def build_wap_url(payment, order)
        # For wap.pay, Alipay returns an HTML form; we expose the gateway URL + signed query.
        "#{GATEWAY}?out_trade_no=#{payment.out_trade_no}&amount=#{order.amount_cents}"
      end

      def map_status(s)
        case s
        when "TRADE_SUCCESS", "TRADE_FINISHED" then :succeeded
        when "WAIT_BUYER_PAY"                  then :pending
        when "TRADE_CLOSED"                    then :closed
        else :failed
        end
      end

      def notify_url
        account.notify_url_override.presence ||
          Rails.application.routes.url_helpers.payments_webhook_url(provider: "alipay",
                                                                    host: ENV["APP_HOST"] || "localhost")
      end
    end
  end
end
```

- [ ] **Step 4: Green + commit**

---

## Task 10: Reform contracts

**Files:**
- Create: `app/services/payments/contracts/charge.rb`
- Create: `app/services/payments/contracts/refund.rb`
- Create: `app/services/payments/contracts/subscribe.rb`
- Tests: parallel `spec/services/payments/contracts/*_spec.rb`

- [ ] **Step 1: Charge contract**

```ruby
# frozen_string_literal: true
module Payments
  module Contracts
    class Charge < Reform::Form
      property :external_ref
      property :amount_cents
      property :currency
      property :subject
      property :body
      property :provider
      property :openid
      property :metadata

      validates :external_ref, presence: true
      validates :amount_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
      validates :currency,     presence: true, inclusion: { in: %w[CNY] }
      validates :subject,      presence: true
      validates :provider,     inclusion: { in: %w[wechat_pay alipay] }
    end
  end
end
```

- [ ] **Refund**:

```ruby
# frozen_string_literal: true
module Payments
  module Contracts
    class Refund < Reform::Form
      property :amount_cents
      property :reason
      validates :amount_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
    end
  end
end
```

- [ ] **Subscribe**:

```ruby
# frozen_string_literal: true
module Payments
  module Contracts
    class Subscribe < Reform::Form
      property :external_ref
      property :plan_name
      property :amount_cents
      property :cycle
      property :provider
      validates :external_ref, :plan_name, presence: true
      validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
      validates :cycle,    inclusion: { in: PaymentSubscription::CYCLES }
      validates :provider, inclusion: { in: %w[wechat_pay alipay] }
    end
  end
end
```

- [ ] Specs exercise valid + invalid permutations. Commit.

---

## Task 11: `Payments::Gateway`

**Files:**
- Create: `app/services/payments/gateway.rb`
- Test: `spec/services/payments/gateway_spec.rb`

- [ ] **Step 1: Spec (covers routing to adapter)**

```ruby
require "rails_helper"

RSpec.describe Payments::Gateway do
  let(:customer) { Customer.create!(id: 10_000_008, name: "T") }
  before { Current.customer = customer }
  let(:acc) do
    PaymentMerchantAccount.create!(provider: "alipay", mode: "sandbox",
                                   merchant_id: "2088", status: "active")
  end
  let(:order)   { PaymentOrder.create!(external_ref: "e", amount_cents: 100, subject: "s") }
  let(:payment) { Payment.create!(payment_order: order, provider: "alipay", flow: "qr",
                                  out_trade_no: "ot", amount_cents: 100) }

  it "delegates charge to the alipay adapter" do
    acc # materialize
    fake = instance_double(Payments::Adapters::Alipay, charge: { prepay_payload: { qr_code: "Q" } })
    allow(Payments::Adapters::Alipay).to receive(:new).with(account: acc).and_return(fake)
    result = described_class.charge(customer: customer, order: order, payment: payment, flow: :qr)
    expect(result[:prepay_payload][:qr_code]).to eq("Q")
  end

  it "raises CredentialsMissing when no active account" do
    expect {
      described_class.charge(customer: customer, order: order, payment:
                              Payment.new(payment_order: order, provider: "wechat_pay", flow: "qr",
                                          out_trade_no: "z", amount_cents: 100),
                              flow: :qr)
    }.to raise_error(Payments::Errors::CredentialsMissing)
  end
end
```

- [ ] **Step 2: Implementation**

```ruby
# frozen_string_literal: true
module Payments
  class Gateway
    ADAPTERS = {
      "wechat_pay" => Payments::Adapters::WechatPay,
      "alipay"     => Payments::Adapters::Alipay
    }.freeze

    class << self
      def charge(customer:, order:, payment:, flow:, openid: nil)
        adapter_for(customer, payment.provider).charge(order: order, payment: payment,
                                                       flow: flow, openid: openid)
      end

      def query(customer:, payment:)
        adapter_for(customer, payment.provider).query(payment: payment)
      end

      def refund(customer:, payment:, refund:)
        adapter_for(customer, payment.provider).refund(payment: payment, refund: refund)
      end

      def close(customer:, payment:)
        adapter_for(customer, payment.provider).close(payment: payment)
      end

      def subscribe(customer:, subscription:)
        adapter_for(customer, subscription.provider).subscribe(subscription: subscription)
      end

      def cancel_subscription(customer:, subscription:)
        adapter_for(customer, subscription.provider).cancel_subscription(subscription: subscription)
      end

      def charge_subscription(customer:, subscription:, payment:)
        adapter_for(customer, subscription.provider).charge_subscription(subscription: subscription, payment: payment)
      end

      def download_bill(customer:, provider:, bill_date:, bill_type:)
        adapter_for(customer, provider).download_bill(bill_date: bill_date, bill_type: bill_type)
      end

      def adapter_for_merchant(provider:, merchant_id:)
        acc = CredentialResolver.by_merchant_id(provider: provider, merchant_id: merchant_id)
        ADAPTERS.fetch(provider).new(account: acc)
      end

      private

      def adapter_for(customer, provider)
        acc = CredentialResolver.call(customer: customer, provider: provider)
        ADAPTERS.fetch(provider).new(account: acc)
      end
    end
  end
end
```

- [ ] **Step 3: Green + commit**

---

## Task 12: Trailblazer activities

Each activity is its own bite-sized task (12.1 … 12.6). Each follows RED → GREEN → COMMIT.

### 12.1 `Activities::Charge`

Handles: idempotent lookup or create of Payment, flow selection, gateway call, `mark_pending!`.

```ruby
# frozen_string_literal: true
require "trailblazer/activity/dsl/linear"

module Payments
  module Activities
    class Charge
      extend Trailblazer::Activity::DSL::Linear::Helper

      def self.call(customer:, order:, provider:, request:, openid: nil)
        flow = Payments::FlowSelector.call(request: request, provider: provider)
        payment = Payment.find_by(payment_order_id: order.id, provider: provider, status: %w[created pending])
        payment ||= Payment.create!(payment_order: order,
                                    provider: provider, flow: flow.to_s,
                                    out_trade_no: Payments::OutTradeNo.generate(prefix: "ch",
                                                                                customer_id: customer.id),
                                    amount_cents: order.amount_cents)
        result = Payments::Gateway.charge(customer: customer, order: order,
                                          payment: payment, flow: flow, openid: openid)
        payment.mark_pending!(result[:prepay_payload])
        { payment: payment, flow: flow, prepay_payload: result[:prepay_payload] }
      end
    end
  end
end
```

Spec covers: first call creates; second call reuses; gateway error → Payment stays `created`; marks pending on success.

### 12.2 `Activities::Query`

```ruby
module Payments
  module Activities
    class Query
      def self.call(customer:, payment:)
        result = Payments::Gateway.query(customer: customer, payment: payment)
        case result[:status]
        when :succeeded
          payment.mark_succeeded!(psp_id: result[:psp_transaction_id],
                                  at: Time.zone.now, notify: result[:raw])
        when :failed, :closed
          payment.mark_failed!(reason: result[:raw].to_s)
        end
        result
      end
    end
  end
end
```

Spec: stub adapter to return each status, verify side-effects.

### 12.3 `Activities::Refund`

```ruby
module Payments
  module Activities
    class Refund
      def self.call(customer:, payment:, amount_cents:, reason: nil)
        refund = PaymentRefund.find_or_create_by!(
          payment_id: payment.id,
          out_refund_no: Payments::OutTradeNo.generate(prefix: "rf", customer_id: customer.id)
        ) do |r|
          r.amount_cents = amount_cents
          r.reason = reason
        end
        res = Payments::Gateway.refund(customer: customer, payment: payment, refund: refund)
        case res[:status]
        when :succeeded
          refund.mark_succeeded!(at: Time.zone.now, psp_refund_id: res[:psp_refund_id], notify: res[:raw])
        when :processing
          refund.mark_processing!
        end
        refund
      end
    end
  end
end
```

Spec: idempotent re-entry returns same refund; sync-success path finalizes state.

### 12.4 `Activities::HandleWebhook`

```ruby
module Payments
  module Activities
    class HandleWebhook
      def self.call(provider:, verified_payload:)
        case provider
        when "wechat_pay" then handle_wechat(verified_payload)
        when "alipay"     then handle_alipay(verified_payload)
        end
      end

      def self.handle_wechat(payload)
        out_trade_no = payload.dig("out_trade_no") || payload.dig("resource", "out_trade_no")
        payment = Payment.unscoped_by_tenant.find_by(out_trade_no: out_trade_no)
        return unless payment
        Current.customer = payment.payment_order.customer
        payment.mark_succeeded!(psp_id: payload["transaction_id"] || payload.dig("resource", "transaction_id"),
                                at: Time.zone.now, notify: payload)
      end

      def self.handle_alipay(payload)
        payment = Payment.unscoped_by_tenant.find_by(out_trade_no: payload["out_trade_no"])
        return unless payment
        Current.customer = payment.payment_order.customer
        if %w[TRADE_SUCCESS TRADE_FINISHED].include?(payload["trade_status"])
          payment.mark_succeeded!(psp_id: payload["trade_no"], at: Time.zone.now, notify: payload)
        end
      end
    end
  end
end
```

Spec: WeChat payload → payment succeeded + order paid; Alipay trade_status TRADE_SUCCESS → same; unknown out_trade_no → no-op.

### 12.5 `Activities::CancelSubscription`

```ruby
module Payments
  module Activities
    class CancelSubscription
      def self.call(customer:, subscription:)
        Payments::Gateway.cancel_subscription(customer: customer, subscription: subscription)
        subscription.mark_cancelled!
        subscription
      end
    end
  end
end
```

### 12.6 `Activities::Reconcile`

```ruby
module Payments
  module Activities
    class Reconcile
      def self.call(customer:, provider:, bill_date:, bill_type: "all")
        bill = PaymentReconciliationBill.find_or_create_by!(
          provider: provider, bill_date: bill_date, bill_type: bill_type
        )
        result = Payments::Gateway.download_bill(customer: customer, provider: provider,
                                                 bill_date: bill_date, bill_type: bill_type)
        rows  = CSV.parse(result[:csv], headers: true)
        total = rows.sum { |r| (r["amount"] || r["total_amount"]).to_f * 100 }
        bill.mark_parsed!(total_count: rows.size, total_amount_cents: total.to_i, raw_summary: result[:raw_summary])
        discrepancies = rows.count do |row|
          ref = row["out_trade_no"]
          p = Payment.unscoped_by_tenant.find_by(out_trade_no: ref)
          p.nil? || p.status != "succeeded"
        end
        bill.mark_reconciled!(discrepancies: discrepancies)
        bill
      rescue Payments::Errors::Error => e
        bill&.mark_failed!
        raise e
      end
    end
  end
end
```

Commit each activity individually with its spec.

---

## Task 13: `WebhookDispatcher`

**Files:**
- Create: `app/services/payments/webhook_dispatcher.rb`
- Test: `spec/services/payments/webhook_dispatcher_spec.rb`

- [ ] **Implementation**

```ruby
# frozen_string_literal: true
module Payments
  class WebhookDispatcher
    def self.call(provider:, headers:, body:)
      merchant_id = extract_merchant_id(provider, headers, body)
      adapter     = Payments::Gateway.adapter_for_merchant(provider: provider, merchant_id: merchant_id)
      payload     = adapter.verify_notification(headers: headers, body: body)
      Payments::Activities::HandleWebhook.call(provider: provider, verified_payload: payload)
      :ok
    end

    def self.extract_merchant_id(provider, _headers, body)
      case provider
      when "wechat_pay"
        # WeChat APIv3: merchant id is the URL-resolved account; for MVP use header mapping.
        payload = JSON.parse(body) rescue {}
        payload.dig("resource", "mchid") || ENV["DEFAULT_WECHAT_MCHID"].to_s
      when "alipay"
        CGI.parse(body).fetch("app_id", [""]).first
      end
    end
  end
end
```

Spec covers: invalid signature → raises, valid → dispatches activity.

---

## Task 14: `FeatureModules::Payment::Provisioner`

**Files:**
- Create: `app/services/feature_modules/payment/provisioner.rb`
- Test: `spec/services/feature_modules/payment/provisioner_spec.rb`

```ruby
# frozen_string_literal: true
module FeatureModules
  module Payment
    class Provisioner
      PROVIDERS = %w[wechat_pay alipay].freeze
      MODES     = %w[sandbox production].freeze

      def self.call(customer)
        PROVIDERS.each do |p|
          MODES.each do |m|
            PaymentMerchantAccount.find_or_create_by!(customer_id: customer.id,
                                                     provider: p, mode: m) do |acc|
              acc.merchant_id = "unset-#{p}-#{m}-#{customer.id}"
              acc.status      = "disabled"
            end
          end
        end
      end

      def self.revoke(customer)
        PaymentMerchantAccount.unscoped_by_tenant.where(customer_id: customer.id).destroy_all
      end
    end
  end
end
```

Spec: `call` creates 4 shells, idempotent on second call; `revoke` deletes all.

---

## Task 15: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add block inside `scope "/:customer_id"` (after `feature_modules` resources block, around line 140):**

```ruby
    # Payment routes (WeChat + Alipay)
    scope "payments", as: :payments do
      get   "checkout",              to: "payments/checkouts#show"
      post  "checkout",              to: "payments/checkouts#create"
      get   "payments/:id/status",   to: "payments/checkouts#status", as: :payment_status
      get   "result/:payment_id",    to: "payments/results#show",    as: :result

      namespace :admin do
        resources :merchant_accounts, only: %i[index new create edit update]
        resources :transactions, only: %i[index show] do
          member { post :refund }
        end
        resources :subscriptions, only: %i[index show] do
          member { post :cancel }
        end
        resources :reconciliations, only: %i[index show]
      end
    end
```

- [ ] **Step 2: Add top-level webhook route (outside the tenant scope, after `scope "/:customer_id"` block closes):**

```ruby
  post "/payments/webhooks/:provider",
       to: "payments/webhooks#create",
       as: :payments_webhook,
       constraints: { provider: /(wechat_pay|alipay)/ }
```

- [ ] **Step 3: Route spec**

`spec/routing/payments_routing_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Payment routes" do
  it "routes checkout" do
    expect(get: "/12345678/payments/checkout").to route_to(
      controller: "payments/checkouts", action: "show", customer_id: "12345678"
    )
  end
  it "routes webhook (no tenant)" do
    expect(post: "/payments/webhooks/wechat_pay").to route_to(
      controller: "payments/webhooks", action: "create", provider: "wechat_pay"
    )
  end
  it "routes admin refund" do
    expect(post: "/12345678/payments/admin/transactions/5/refund").to route_to(
      controller: "payments/admin/transactions", action: "refund",
      customer_id: "12345678", id: "5"
    )
  end
end
```

- [ ] **Step 4: Green + commit**

---

## Task 16: Checkout + Results controllers

**Files:**
- Create: `app/controllers/payments/checkouts_controller.rb`
- Create: `app/controllers/payments/results_controller.rb`
- Tests: request specs

### 16.1 `CheckoutsController`

```ruby
# frozen_string_literal: true
module Payments
  class CheckoutsController < ApplicationController
    before_action :set_customer
    before_action :set_or_build_order, only: %i[show create]

    def show
      render Payments::CheckoutComponent.new(order: @order)
    end

    def create
      contract = Payments::Contracts::Charge.new(OpenStruct.new)
      unless contract.validate(create_params.merge(external_ref: @order.external_ref,
                                                   amount_cents: @order.amount_cents,
                                                   currency: @order.currency,
                                                   subject: @order.subject))
        return render(Payments::CheckoutComponent.new(order: @order, errors: contract.errors), status: :unprocessable_entity)
      end
      result = Payments::Activities::Charge.call(customer: @customer, order: @order,
                                                 provider: create_params[:provider],
                                                 request: request,
                                                 openid: create_params[:openid])
      component =
        case result[:flow]
        when :qr    then Payments::QrCodeComponent.new(payment: result[:payment])
        when :h5    then Payments::H5RedirectComponent.new(payment: result[:payment])
        when :jsapi then Payments::JsapiInvokerComponent.new(payment: result[:payment])
        end
      render component
    end

    def status
      payment = Payment.find(params[:id])
      Payments::Activities::Query.call(customer: @customer, payment: payment) if payment.status == "pending"
      render json: { status: payment.reload.status }
    end

    private

    def set_customer
      @customer = Customer.find(params[:customer_id])
      Current.customer = @customer
    end

    def set_or_build_order
      attrs = params.permit(:ref, :amount_cents, :subject, :body).to_h
      @order = PaymentOrder.find_or_create_by!(external_ref: attrs[:ref] || params[:external_ref]) do |o|
        o.amount_cents = attrs[:amount_cents]
        o.subject      = attrs[:subject]
        o.body         = attrs[:body]
      end
    end

    def create_params
      params.permit(:provider, :openid)
    end
  end
end
```

### 16.2 `ResultsController`

```ruby
# frozen_string_literal: true
module Payments
  class ResultsController < ApplicationController
    before_action :set_customer

    def show
      @payment = Payment.find(params[:payment_id])
      render Payments::ResultComponent.new(payment: @payment)
    end

    private

    def set_customer
      @customer = Customer.find(params[:customer_id])
      Current.customer = @customer
    end
  end
end
```

- [ ] Request specs covering: GET checkout renders picker; POST checkout with wechat_pay + desktop UA → renders QR component; status endpoint returns JSON; tenant isolation (different customer_id returns 404). Commit.

---

## Task 17: Webhooks controller

**Files:**
- Create: `app/controllers/payments/webhooks_controller.rb`

```ruby
# frozen_string_literal: true
module Payments
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!, raise: false

    def create
      body = request.raw_post
      Payments::WebhookDispatcher.call(provider: params[:provider],
                                       headers: request.headers.to_h,
                                       body: body)
      head :ok
    rescue Payments::Errors::SignatureInvalid
      head :bad_request
    rescue Payments::Errors::TenantNotFound
      head :not_found
    rescue Payments::Errors::Error => e
      Rails.logger.error("[payments.webhook] #{e.class}: #{e.message}")
      head :internal_server_error
    end
  end
end
```

Request spec: valid payload → 200 + state transition; invalid signature → 400 + no state change. Commit.

---

## Task 18: Admin controllers

Four controllers in `app/controllers/payments/admin/`. All inherit from `ApplicationController` with `before_action :require_admin!` (use the app's existing admin guard — engineer should grep for how other admin namespaces guard). Each action is thin — query a model, render a component.

### 18.1 `MerchantAccountsController`

```ruby
# frozen_string_literal: true
module Payments
  module Admin
    class MerchantAccountsController < ApplicationController
      before_action :set_customer
      before_action :set_account, only: %i[edit update]

      def index
        @accounts = PaymentMerchantAccount.order(:provider, :mode)
        render Payments::Admin::MerchantAccountFormComponent.collection_view(accounts: @accounts)
      end

      def new
        @account = PaymentMerchantAccount.new
        render Payments::Admin::MerchantAccountFormComponent.new(account: @account)
      end

      def create
        @account = PaymentMerchantAccount.new(account_params)
        if @account.save
          redirect_to [:payments, :admin, :merchant_accounts]
        else
          render Payments::Admin::MerchantAccountFormComponent.new(account: @account),
                 status: :unprocessable_entity
        end
      end

      def edit
        render Payments::Admin::MerchantAccountFormComponent.new(account: @account)
      end

      def update
        if @account.update(account_params)
          redirect_to [:payments, :admin, :merchant_accounts]
        else
          render Payments::Admin::MerchantAccountFormComponent.new(account: @account),
                 status: :unprocessable_entity
        end
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
        Current.customer = @customer
      end

      def set_account
        @account = PaymentMerchantAccount.find(params[:id])
      end

      def account_params
        params.require(:payment_merchant_account).permit(
          :provider, :mode, :merchant_id, :api_key_v3, :private_key_pem,
          :platform_public_key_pem, :wechat_cert_serial, :notify_url_override, :status
        )
      end
    end
  end
end
```

### 18.2 `TransactionsController`

```ruby
module Payments
  module Admin
    class TransactionsController < ApplicationController
      before_action :set_customer

      def index
        @payments = Payment.includes(:payment_order, :payment_refunds).order(created_at: :desc).limit(100)
        render Payments::Admin::TransactionTableComponent.new(payments: @payments)
      end

      def show
        @payment = Payment.find(params[:id])
      end

      def refund
        payment = Payment.find(params[:id])
        Payments::Activities::Refund.call(customer: @customer, payment: payment,
                                          amount_cents: params[:amount_cents].to_i,
                                          reason: params[:reason])
        redirect_to [:payments, :admin, :transactions]
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
        Current.customer = @customer
      end
    end
  end
end
```

### 18.3 `SubscriptionsController`

```ruby
module Payments
  module Admin
    class SubscriptionsController < ApplicationController
      before_action :set_customer

      def index
        @subscriptions = PaymentSubscription.order(created_at: :desc)
        render Payments::Admin::SubscriptionTableComponent.new(subscriptions: @subscriptions)
      end

      def show
        @subscription = PaymentSubscription.find(params[:id])
      end

      def cancel
        sub = PaymentSubscription.find(params[:id])
        Payments::Activities::CancelSubscription.call(customer: @customer, subscription: sub)
        redirect_to [:payments, :admin, :subscriptions]
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
        Current.customer = @customer
      end
    end
  end
end
```

### 18.4 `ReconciliationsController`

```ruby
module Payments
  module Admin
    class ReconciliationsController < ApplicationController
      before_action :set_customer

      def index
        @bills = PaymentReconciliationBill.order(bill_date: :desc).limit(60)
        render Payments::Admin::ReconciliationTableComponent.new(bills: @bills)
      end

      def show
        @bill = PaymentReconciliationBill.find(params[:id])
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
        Current.customer = @customer
      end
    end
  end
end
```

Request specs per controller covering happy path + tenant isolation. Commit each controller separately.

---

## Task 19: User-facing ViewComponents

All components follow the pattern: `class X::YComponent < ViewComponent::Base`, TailwindCSS in `.html.erb`, no custom CSS. Stimulus data attributes for interactivity.

### 19.1 `CheckoutComponent`

`app/components/payments/checkout_component.rb`:
```ruby
# frozen_string_literal: true
class Payments::CheckoutComponent < ViewComponent::Base
  def initialize(order:, errors: nil)
    @order, @errors = order, errors
  end
  attr_reader :order, :errors
end
```

`app/components/payments/checkout_component.html.erb`:
```erb
<section class="mx-auto max-w-md rounded-2xl bg-white p-6 shadow-md">
  <h1 class="text-2xl font-semibold text-slate-900"><%= order.subject %></h1>
  <p class="mt-1 text-sm text-slate-500">Order #<%= order.external_ref %></p>
  <p class="mt-4 text-3xl font-bold">¥<%= format('%.2f', order.amount_cents / 100.0) %></p>

  <% if errors&.any? %>
    <div class="mt-3 rounded bg-red-50 p-2 text-sm text-red-700"><%= errors.full_messages.to_sentence %></div>
  <% end %>

  <%= form_with url: payments_checkout_path(customer_id: params[:customer_id]),
                method: :post, class: "mt-6 space-y-3" do |f| %>
    <%= f.hidden_field :ref, value: order.external_ref %>
    <button type="submit" name="provider" value="wechat_pay"
            class="flex w-full items-center justify-center gap-2 rounded-xl bg-green-500 px-4 py-3 font-semibold text-white hover:bg-green-600">
      WeChat Pay / 微信支付
    </button>
    <button type="submit" name="provider" value="alipay"
            class="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-500 px-4 py-3 font-semibold text-white hover:bg-blue-600">
      Alipay / 支付宝
    </button>
  <% end %>
</section>
```

Component spec: renders both buttons, surfaces error messages.

### 19.2 `QrCodeComponent`

```ruby
class Payments::QrCodeComponent < ViewComponent::Base
  def initialize(payment:)
    @payment = payment
    @code_url = payment.prepay_payload["code_url"] || payment.prepay_payload["qr_code"]
  end
  attr_reader :payment, :code_url
end
```

```erb
<section class="mx-auto max-w-md rounded-2xl bg-white p-6 text-center shadow-md"
         data-controller="payments--qr-poll"
         data-payments--qr-poll-status-url-value="<%= payment_status_path(customer_id: params[:customer_id], id: payment.id) %>"
         data-payments--qr-poll-result-url-value="<%= payments_result_path(customer_id: params[:customer_id], payment_id: payment.id) %>">
  <h2 class="text-lg font-semibold">Scan to pay</h2>
  <div class="mt-4 inline-block rounded-xl bg-slate-100 p-4">
    <img src="<%= "https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=#{CGI.escape(code_url.to_s)}" %>"
         alt="QR code" class="h-56 w-56" />
  </div>
  <p class="mt-4 text-sm text-slate-500" data-payments--qr-poll-target="status">Waiting for payment…</p>
</section>
```

### 19.3 `H5RedirectComponent`

```ruby
class Payments::H5RedirectComponent < ViewComponent::Base
  def initialize(payment:)
    @payment = payment
    @url = payment.prepay_payload["h5_url"]
  end
  attr_reader :payment, :url
end
```

```erb
<section class="mx-auto max-w-md p-6" data-controller="payments--h5-redirect"
         data-payments--h5-redirect-url-value="<%= url %>">
  <p class="text-center text-slate-700">Redirecting to your payment app…</p>
  <a href="<%= url %>" class="mt-4 block rounded-xl bg-blue-500 px-4 py-3 text-center text-white">Tap to continue</a>
</section>
```

### 19.4 `JsapiInvokerComponent`

```ruby
class Payments::JsapiInvokerComponent < ViewComponent::Base
  def initialize(payment:)
    @payment = payment
  end
  attr_reader :payment
  def params_json = payment.prepay_payload.to_json
end
```

```erb
<section data-controller="payments--jsapi-invoker"
         data-payments--jsapi-invoker-provider-value="<%= payment.provider %>"
         data-payments--jsapi-invoker-params-value='<%= params_json %>'
         data-payments--jsapi-invoker-result-url-value="<%= payments_result_path(customer_id: params[:customer_id], payment_id: payment.id) %>">
  <p class="text-center text-slate-600">Completing payment…</p>
</section>
```

### 19.5 `WaitingComponent`

```ruby
class Payments::WaitingComponent < ViewComponent::Base
  def initialize(message: "Waiting for payment…"); @message = message; end
  attr_reader :message
end
```

```erb
<div class="flex items-center gap-3 p-6"><span class="h-3 w-3 animate-pulse rounded-full bg-slate-400"></span><span><%= message %></span></div>
```

### 19.6 `ResultComponent`

```ruby
class Payments::ResultComponent < ViewComponent::Base
  def initialize(payment:); @payment = payment; end
  attr_reader :payment
  def success? = payment.status == "succeeded"
end
```

```erb
<section class="mx-auto max-w-md rounded-2xl bg-white p-6 text-center shadow-md">
  <% if success? %>
    <div class="text-5xl">✅</div>
    <h2 class="mt-2 text-xl font-semibold">Payment successful</h2>
    <p class="mt-1 text-sm text-slate-500">Order #<%= payment.payment_order.external_ref %></p>
  <% else %>
    <div class="text-5xl">⚠️</div>
    <h2 class="mt-2 text-xl font-semibold">Payment not completed</h2>
    <p class="mt-1 text-sm text-slate-500">Status: <%= payment.status %></p>
  <% end %>
  <a href="/" class="mt-6 inline-block rounded-xl bg-slate-900 px-4 py-2 text-white">Return</a>
</section>
```

Commit each component + its spec separately.

---

## Task 20: Stimulus controllers

`app/javascript/controllers/payments/qr_poll_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { statusUrl: String, resultUrl: String }
  static targets = ["status"]
  connect() { this.timer = setInterval(() => this.poll(), 2000) }
  disconnect() { clearInterval(this.timer) }
  async poll() {
    const res = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" }})
    const { status } = await res.json()
    if (this.hasStatusTarget) this.statusTarget.textContent = `Status: ${status}`
    if (["succeeded","failed","closed"].includes(status)) {
      clearInterval(this.timer)
      window.location = this.resultUrlValue
    }
  }
}
```

`h5_redirect_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { url: String }
  connect() { setTimeout(() => { window.location = this.urlValue }, 300) }
}
```

`jsapi_invoker_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { provider: String, params: String, resultUrl: String }
  connect() {
    const params = JSON.parse(this.paramsValue || "{}")
    if (this.providerValue === "wechat_pay" && window.WeixinJSBridge) {
      window.WeixinJSBridge.invoke("getBrandWCPayRequest", params, (r) => {
        window.location = this.resultUrlValue
      })
    } else if (this.providerValue === "alipay" && window.ap?.tradePay) {
      window.ap.tradePay({ tradeNO: params.trade_no }, () => window.location = this.resultUrlValue)
    } else {
      setTimeout(() => window.location = this.resultUrlValue, 1000)
    }
  }
}
```

Register in `app/javascript/controllers/index.js` with namespaced names `payments--qr-poll`, `payments--h5-redirect`, `payments--jsapi-invoker`. Commit.

---

## Task 21: Admin ViewComponents

Five components under `app/components/payments/admin/`. All Tailwind, no Stimulus unless noted. Each is thin:

- `TransactionTableComponent(payments:)` — table with columns Order / Provider / Amount / Status / Refund button (`button_to` to `refund_admin_transaction_path`, Stimulus dialog optional).
- `RefundDialogComponent(payment:)` — form posting to `refund_admin_transaction_path` with amount + reason.
- `SubscriptionTableComponent(subscriptions:)` — table with Cancel button.
- `ReconciliationTableComponent(bills:)` — bill date / provider / count / discrepancies / status.
- `MerchantAccountFormComponent(account:)` — full form with encrypted fields (rendered as password inputs, pre-filled only with placeholder "••••••" when set).

Include component specs rendering each with a fixture row and asserting key Tailwind classes + data. Commit each separately.

---

## Task 22: Cron jobs

**Files:**
- Create: `app/services/payments/cron/charge_due_subscriptions.rb`
- Create: `app/services/payments/cron/download_bills.rb`
- Tests: service specs

### 22.1 `ChargeDueSubscriptions`

```ruby
# frozen_string_literal: true
module Payments
  module Cron
    class ChargeDueSubscriptions
      def self.perform
        PaymentSubscription.unscoped_by_tenant.due_now.find_each do |sub|
          Current.customer = sub.customer
          payment = Payment.create!(payment_order: ensure_order_for(sub),
                                    provider: sub.provider, flow: "jsapi",
                                    out_trade_no: Payments::OutTradeNo.generate(prefix: "sb", customer_id: sub.customer_id),
                                    amount_cents: sub.amount_cents)
          Payments::Gateway.charge_subscription(customer: sub.customer, subscription: sub, payment: payment)
          sub.advance_next_charge!
        rescue Payments::Errors::Error => e
          Rails.logger.error("[payments.cron] #{e.class}: #{e.message}")
        end
      end

      def self.ensure_order_for(sub)
        PaymentOrder.find_or_create_by!(external_ref: "sub-#{sub.id}-#{Date.today}") do |o|
          o.amount_cents = sub.amount_cents
          o.subject      = sub.plan_name
        end
      end
    end
  end
end
```

### 22.2 `DownloadBills`

```ruby
module Payments
  module Cron
    class DownloadBills
      def self.perform(bill_date: Date.yesterday)
        PaymentMerchantAccount.unscoped_by_tenant.active.find_each do |acc|
          Current.customer = acc.customer
          Payments::Activities::Reconcile.call(customer: acc.customer, provider: acc.provider,
                                               bill_date: bill_date)
        rescue Payments::Errors::Error => e
          Rails.logger.error("[payments.cron] #{e.class}: #{e.message}")
        end
      end
    end
  end
end
```

Specs stub the gateway and verify per-account iteration + error isolation. Commit.

---

## Task 23: System specs

**Files:**
- `spec/system/payments/qr_checkout_spec.rb`
- `spec/system/payments/h5_checkout_spec.rb`
- `spec/system/payments/jsapi_checkout_spec.rb`
- `spec/system/payments/admin_refund_spec.rb`

Each spec:
1. Creates a customer + active `PaymentMerchantAccount`.
2. Stubs PSP HTTP via WebMock with fixture responses.
3. Visits `/<customer>/payments/checkout?ref=...&amount_cents=...&subject=...`.
4. Asserts the expected component renders.
5. For QR: simulates a webhook POST and asserts Stimulus redirect would land on success result (with polling stubbed via `allow(Payments::Activities::Query)`).

One example (QR):

```ruby
require "rails_helper"

RSpec.describe "QR checkout", type: :system, js: true do
  let(:customer) { Customer.create!(id: 10_000_099, name: "T") }
  before do
    Current.customer = customer
    PaymentMerchantAccount.create!(provider: "wechat_pay", mode: "sandbox",
                                   merchant_id: "wx_m", status: "active",
                                   api_key_v3: "k", private_key_pem: File.read("spec/fixtures/payments/keys/test_rsa_private.pem"),
                                   platform_public_key_pem: File.read("spec/fixtures/payments/keys/test_rsa_public.pem"),
                                   wechat_cert_serial: "S1")
    stub_request(:post, %r{/v3/pay/transactions/native})
      .to_return(status: 200,
                 body: File.read("spec/fixtures/payments/wechat/native_prepay.json"),
                 headers: { "Content-Type" => "application/json" })
  end

  it "renders QR after choosing WeChat Pay (desktop UA)" do
    page.driver.browser.user_agent = "Mozilla/5.0 (Macintosh) Chrome" if page.driver.respond_to?(:browser)
    visit "/#{customer.id}/payments/checkout?ref=R1&amount_cents=100&subject=Test"
    click_button "WeChat Pay / 微信支付"
    expect(page).to have_css("[data-controller*='payments--qr-poll']")
  end
end
```

Commit.

---

## Task 24: Full verification + cleanup

> **Known pre-existing drift to repair in this task:** `spec/system/feature_modules/payment_handoff_flow_spec.rb` references the old payment contract shape (`{ amount:, currency: "USD", order_id: }`) and the old entry path `/:customer_id/payment/checkout`. After Task 2 these will not match the new CNY-only contract and the new `/payments/checkout` path. Update the spec inputs to `{ external_ref:, amount_cents:, currency: "CNY", subject: }` and fix the entry-path assertion as part of this step.

- [ ] **Step 1: Run the complete suite**

```bash
bundle exec rspec
```
Expected: 0 failures. Record count — should be substantially higher than baseline from Task 1.

- [ ] **Step 2: Brakeman**

```bash
bundle exec brakeman -q --no-pager
```
Expected: no new warnings in payment files.

- [ ] **Step 3: Rubocop on new paths**

```bash
bundle exec rubocop app/models/payment* app/services/payments app/services/feature_modules/payment app/controllers/payments app/components/payments
```
Expected: clean (or auto-fix and re-commit).

- [ ] **Step 4: Sanity check — schema round-trip**

```bash
bin/rails db:drop db:create db:migrate
bundle exec rspec --fail-fast spec/models/payment_order_spec.rb
```
Expected: migrations apply from scratch; spec passes.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat(payments): complete redesign — WeChat Pay + Alipay (China)"
```

---

## Self-Review (writing-plans)

1. **Spec coverage:**
   - Per-tenant encrypted creds → Task 4.1 + Task 18.1 + Task 14.
   - WeChat + Alipay only → Task 2 (contract inclusion), Task 4.1 (PROVIDERS), Task 11 (ADAPTERS map).
   - QR / H5 / JSAPI auto-detect → Task 7 + Task 16 + Task 19.2/19.3/19.4 + Task 20.
   - Charge / refund / reconcile / subscribe → Tasks 12.1, 12.3, 12.6, 12.5 + 22.1.
   - Single webhook endpoint → Task 13 + Task 17 + Task 15 (top-level route).
   - Admin pages: merchant accounts / transactions / subscriptions / reconciliations → Task 18.1–18.4 + Task 21.
   - Testing strategy (models/adapters/activities/controllers/components/system/cron) → Tasks 4, 8.2, 9, 12, 16–18, 19, 22, 23.
   - Removal of old stub → Task 2 (rewrite in place; no other payment files exist per exploration).

2. **Placeholder scan:** None of "TBD/TODO/implement later/similar to X". Every code-bearing step includes the code.

3. **Type consistency:**
   - `PaymentMerchantAccount::PROVIDERS = %w[wechat_pay alipay]` — same keys used in `Payments::Gateway::ADAPTERS`, `Payment::PROVIDERS`, and the routes constraint `(wechat_pay|alipay)`.
   - `PaymentOrder::STATUSES` includes `partial_refund` and `refunded`, matching `PaymentRefund#recalc_order_status!`.
   - `Payment#mark_succeeded!(psp_id:, at:, notify:)` signature is consistent between model, `Activities::Query`, and `Activities::HandleWebhook`.
   - `Payments::OutTradeNo.generate(prefix:, customer_id:)` called identically everywhere.

Plan is ready.



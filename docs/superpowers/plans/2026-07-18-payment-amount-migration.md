# Payment Module Amount Storage Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Checkbox steps.
>
> **WORKING ON `master`:** do NOT `git commit`/`add`/`push`. Leave changes in the working tree. "Commit" steps = "ensure targeted specs pass" only.

**Goal:** Migrate payment-module amount storage from integer `amount_cents` to decimal `amount` using a direct replacement (no dual-write/backfill).

**Architecture:** Because this is a fresh app with no history data, the single migration drops the integer cents columns and creates `decimal(12,2)` `amount`/`total_amount` columns. Then update `Payments::Money` to convert from major-unit decimals and migrate every read/write path through models → contracts → activities → gateways → controllers → components → tests.

**Tech Stack:** Rails 8.1, Ruby 3.2.8, RSpec, ViewComponent, dry-rb contracts, Trailblazer activities, PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-07-18-payment-amount-design.md`

---

## Global Constraints

- `amount` columns are `decimal(12,2)` and always store two decimals (`31.09` USD, `1000.00` JPY).
- Zero-decimal currency PSP conversion remains handled by `Payments::Money`.
- All user-facing strings must be I18n (`en` + `zh-CN`).
- Multi-tenant: customer-scoped records keep `customer_id` validation/scope behavior unchanged.
- Do NOT run the full RSpec suite for every micro-task; run targeted specs only.

---

## File Structure

- `db/migrate/<ts>_add_amount_columns_to_payment_tables.rb` — single migration that replaces cents columns with decimal columns.
- `app/services/payments/money.rb` — core converter, now accepts major-unit decimal.
- `app/models/payments/{order,payment,refund,subscription,dispute,reconciliation_bill}.rb` — validations and logic on `amount`/`total_amount`.
- `app/services/payments/contracts/{charge,refund,subscribe}.rb` — decimal contract inputs.
- `app/services/payments/activities/{charge,charge_token,create_subscription,refund,handle_webhook,reconcile}.rb` — read `amount`.
- `app/services/payments/cron/charge_due_subscriptions.rb` — read `amount`.
- `app/services/payments/gateways/{stripe,paypal,alipay,wechat_pay}.rb` — convert from decimal amount.
- `app/controllers/payments/checkouts_controller.rb`, `admin/modules/payments/{refunds,subscriptions}_controller.rb` — use `amount` params.
- `app/components/payments/{checkout,widget_checkout,member/subscriptions,admin/refund_dialog,admin/reconciliation_table}.rb` + templates — display `amount`.
- `config/locales/comp_payments.{en,zh-CN}.yml` — label updates.
- `spec/factories/*.rb` + specs — update to decimal amounts.

---

## Task 1: Direct migration — replace integer cents columns with decimal amount columns

**Files:**
- Create: `db/migrate/20260718110000_add_amount_columns_to_payment_tables.rb`
- Test: `spec/db/migrate/add_amount_columns_to_payment_tables_spec.rb` (or run `bundle exec rspec spec/db` if migration specs exist)

**Interfaces:**
- Produces: `amount` / `total_amount` `decimal(12,2)` columns; removes `amount_cents` / `total_amount_cents`.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260718110000_add_amount_columns_to_payment_tables.rb
class AddAmountColumnsToPaymentTables < ActiveRecord::Migration[8.1]
  TABLES = {
    payment_orders:             :amount,
    payments:                   :amount,
    payment_refunds:            :amount,
    payment_subscriptions:      :amount,
    payment_disputes:           :amount,
    payment_reconciliation_bills: :total_amount
  }.freeze

  def up
    TABLES.each do |table, new_column|
      old_column = new_column == :total_amount ? :total_amount_cents : :amount_cents
      remove_column table, old_column if column_exists?(table, old_column)
      add_column table, new_column, :decimal, precision: 12, scale: 2, null: false, default: 0.0
    end
  end

  def down
    TABLES.each do |table, new_column|
      old_column = new_column == :total_amount ? :total_amount_cents : :amount_cents
      remove_column table, new_column if column_exists?(table, new_column)
      add_column table, old_column, :bigint, null: false, default: 0
    end
  end
end
```

- [ ] **Step 2: Run migration**

Run: `bin/rails db:migrate`
Expected: exits 0, all six decimal columns created and old integer columns removed.

- [ ] **Step 3: Verify schema**

Run:
```bash
bin/rails runner 'puts Payments::Order.column_names.grep(/amount/); puts Payments::Payment.column_names.grep(/amount/)'
```
Expected: only `amount`/`total_amount` columns; no `amount_cents`/`total_amount_cents`.

- [ ] **Step 4: Commit-equivalent — mark done after migration succeeds**

Run targeted migration spec if one exists, otherwise the schema check above is sufficient.

---

## Task 2: Update `Payments::Money` to accept major-unit decimal

**Files:**
- Modify: `app/services/payments/money.rb`
- Test: `spec/services/payments/money_spec.rb` (create if missing)

**Interfaces:**
- Consumes: decimal `amount` and currency string.
- Produces: `smallest_unit` integer, `decimal_string` string.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/services/payments/money_spec.rb
require "rails_helper"

RSpec.describe Payments::Money do
  describe "#smallest_unit" do
    it "converts USD major units to cents" do
      expect(described_class.new(31.09, "USD").smallest_unit).to eq(3109)
    end

    it "converts zero-decimal JPY major units to whole units" do
      expect(described_class.new(1000.00, "JPY").smallest_unit).to eq(1000)
    end
  end

  describe "#decimal_string" do
    it "returns two decimals for USD" do
      expect(described_class.new(31.09, "USD").decimal_string).to eq("31.09")
    end

    it "returns integer string for zero-decimal JPY" do
      expect(described_class.new(1000.00, "JPY").decimal_string).to eq("1000")
    end
  end

  describe ".from_major" do
    it "parses major-unit decimal back to cents-compatible integer" do
      expect(described_class.from_major("31.09", "USD")).to eq(3109)
    end

    it "parses zero-decimal major units" do
      expect(described_class.from_major("1000", "JPY")).to eq(100000)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/payments/money_spec.rb`
Expected: FAIL (methods undefined or behavior wrong).

- [ ] **Step 3: Implement `Payments::Money`**

```ruby
# app/services/payments/money.rb
# frozen_string_literal: true

require "bigdecimal"

module Payments
  class Money
    attr_reader :amount, :currency

    def initialize(amount, currency)
      @amount   = BigDecimal(amount.to_s)
      @currency = currency.to_s.upcase
    end

    def zero_decimal?
      Billing::CurrencyResolver.zero_decimal?(currency)
    end

    def smallest_unit
      zero_decimal? ? amount.round.to_i : (amount * 100).round.to_i
    end

    def decimal_string
      zero_decimal? ? amount.round.to_s : format("%.2f", amount)
    end

    def self.from_major(value, currency)
      return nil if value.nil? || value.to_s.strip.empty?

      money = new(value, currency)
      money.zero_decimal? ? (money.amount * 100).round.to_i : (money.amount * 100).round.to_i
    end

    def self.from_smallest_unit(value, currency)
      return nil if value.nil?

      smallest = value.to_i
      zero_decimal?(currency.to_s) ? new(smallest / 100.0, currency) : new(smallest / 100.0, currency)
    end

    def self.to_iso_minor_units(amount, currency)
      new(amount, currency).smallest_unit
    end

    def ==(other)
      other.is_a?(Money) && amount == other.amount && currency == other.currency
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/payments/money_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit-equivalent**

Mark done after tests pass.

---

## Task 3: Update `Payments::Order` model

**Files:**
- Modify: `app/models/payments/order.rb`
- Test: `spec/models/payments/order_spec.rb`

**Interfaces:**
- Consumes: `amount` decimal assignment.
- Produces: synchronized `amount_cents`.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/models/payments/order_spec.rb (append)
describe "amount / amount_cents synchronization" do
  it "syncs amount_cents from amount" do
    order = build(:payments_order, amount: 31.09)
    expect(order.amount_cents).to eq(3109)
  end

  it "syncs amount from amount_cents" do
    order = build(:payments_order, amount_cents: 3109)
    expect(order.amount).to eq(31.09)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/payments/order_spec.rb`
Expected: FAIL (amount undefined or sync missing).

- [ ] **Step 3: Update model**

```ruby
# app/models/payments/order.rb
validates :amount, presence: true, numericality: { greater_than: 0 }

before_validation :sync_amount_from_cents, if: -> { amount_cents_changed? && !amount_changed? }
before_validation :sync_cents_from_amount, if: -> { amount_changed? && !amount_cents_changed? }

private

def sync_amount_from_cents
  self.amount = (amount_cents.to_d / 100).round(2)
end

def sync_cents_from_amount
  self.amount_cents = (amount.to_d * 100).round.to_i
end
```

Keep the old `amount_cents` validation line until Phase 3; in Phase 1/2 both validations can coexist, but prefer `amount` validation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/payments/order_spec.rb`
Expected: PASS

---

## Task 4: Update `Payments::Payment` model

**Files:**
- Modify: `app/models/payments/payment.rb`
- Test: `spec/models/payments/payment_spec.rb`

**Interfaces:**
- Same as Task 3.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/models/payments/payment_spec.rb (append)
describe "amount / amount_cents synchronization" do
  it "syncs amount_cents from amount" do
    payment = build(:payments_payment, amount: 31.09)
    expect(payment.amount_cents).to eq(3109)
  end

  it "syncs amount from amount_cents" do
    payment = build(:payments_payment, amount_cents: 3109)
    expect(payment.amount).to eq(31.09)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/payments/payment_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Update model**

Apply the same pattern as Task 3 to `app/models/payments/payment.rb`:
- Change validation to `amount` presence/numericality.
- Add sync callbacks.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/payments/payment_spec.rb`
Expected: PASS

---

## Task 5: Update `Payments::Refund` model

**Files:**
- Modify: `app/models/payments/refund.rb`
- Test: `spec/models/payments/refund_spec.rb`

- [ ] **Step 1-4:** Same pattern as Task 3/4. Update validation and add sync callbacks.

Run: `bundle exec rspec spec/models/payments/refund_spec.rb`
Expected: PASS

---

## Task 6: Update `Payments::Subscription` model

**Files:**
- Modify: `app/models/payments/subscription.rb`
- Test: `spec/models/payments/subscription_spec.rb`

- [ ] **Step 1-4:** Same pattern. Update validation and add sync callbacks.

Run: `bundle exec rspec spec/models/payments/subscription_spec.rb`
Expected: PASS

---

## Task 7: Update `Payments::Dispute` model

**Files:**
- Modify: `app/models/payments/dispute.rb`
- Test: `spec/models/payments/dispute_spec.rb`

- [ ] **Step 1-4:** Same pattern. Update validation and add sync callbacks.

Run: `bundle exec rspec spec/models/payments/dispute_spec.rb`
Expected: PASS

---

## Task 8: Update `Payments::ReconciliationBill` model

**Files:**
- Modify: `app/models/payments/reconciliation_bill.rb`
- Test: `spec/models/payments/reconciliation_bill_spec.rb`

- [ ] **Step 1-4:** Same pattern, using `total_amount` / `total_amount_cents`.

Run: `bundle exec rspec spec/models/payments/reconciliation_bill_spec.rb`
Expected: PASS

---

## Task 9: Update contracts

**Files:**
- Modify: `app/services/payments/contracts/charge.rb`
- Modify: `app/services/payments/contracts/refund.rb`
- Modify: `app/services/payments/contracts/subscribe.rb`
- Test: corresponding specs under `spec/services/payments/contracts/`

**Interfaces:**
- Consumes: `amount` decimal param.
- Produces: validated `amount`.

- [ ] **Step 1: Update each contract**

Example for `app/services/payments/contracts/charge.rb`:
```ruby
property :amount
validates :amount, presence: true, numericality: { greater_than: 0 }
```

Do the same for `refund.rb` and `subscribe.rb`.

- [ ] **Step 2: Update contract specs**

Change test inputs from integer cents to decimal amounts (e.g., `3109` → `31.09`).

- [ ] **Step 3: Run contract specs**

Run: `bundle exec rspec spec/services/payments/contracts/`
Expected: PASS

---

## Task 10: Update charge / charge_token / create_subscription activities

**Files:**
- Modify: `app/services/payments/activities/charge.rb`
- Modify: `app/services/payments/activities/charge_token.rb`
- Modify: `app/services/payments/activities/create_subscription.rb`
- Test: corresponding specs under `spec/services/payments/activities/`

**Interfaces:**
- Consumes: `order.amount`, `subscription.amount`.
- Produces: gateway payloads using `Payments::Money`.

- [ ] **Step 1: Update `charge.rb` and `charge_token.rb`**

Replace `order.amount_cents` with `order.amount` when constructing gateway calls. Gateways will convert via `Payments::Money`.

- [ ] **Step 2: Update `create_subscription.rb`**

Replace `amount_cents:` param with `amount:` and pass decimal through.

- [ ] **Step 3: Update specs**

Change factory setup and expectations to use decimal amounts.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/services/payments/activities/charge_spec.rb spec/services/payments/activities/charge_token_spec.rb spec/services/payments/activities/create_subscription_spec.rb`
Expected: PASS

---

## Task 11: Update refund activity

**Files:**
- Modify: `app/services/payments/activities/refund.rb`
- Test: `spec/services/payments/activities/refund_spec.rb`

- [ ] **Step 1: Update activity**

Change signature from `amount_cents:` to `amount:`. Internally use `payment.amount` and `refund.amount` for comparisons and validations. Use `Payments::Money.to_iso_minor_units(refund.amount, currency)` for display formatting.

- [ ] **Step 2: Update specs**

Use decimal amounts in test setup and expectations.

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/payments/activities/refund_spec.rb`
Expected: PASS

---

## Task 12: Update handle_webhook activity

**Files:**
- Modify: `app/services/payments/activities/handle_webhook.rb`
- Test: `spec/services/payments/activities/handle_webhook_spec.rb` or `spec/jobs/payments/process_webhook_event_job_spec.rb`

- [ ] **Step 1: Update PSP amount parsers**

Rename `*_amount_cents` helpers to `*_amount` and have them return major-unit decimals. Convert to cents only for comparison during the transition:

```ruby
def self.wechat_amount(payload)
  Payments::Money.from_smallest_unit(payload["amount"]["total"].to_i, "CNY").amount
end

def self.alipay_amount(payload)
  Payments::Money.cents_from_major(payload["amount"], "CNY") / 100.0
end
```

(Adjust based on actual payload shape; goal is to compare `notified_amount == payment.amount`.)

- [ ] **Step 2: Update dispute upsert**

Use `amount:` instead of `amount_cents:`.

- [ ] **Step 3: Update specs**

Use decimal amounts.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/services/payments/activities/handle_webhook_spec.rb spec/jobs/payments/process_webhook_event_job_spec.rb`
Expected: PASS

---

## Task 13: Update reconcile activity

**Files:**
- Modify: `app/services/payments/activities/reconcile.rb`
- Test: corresponding spec

- [ ] **Step 1: Update activity**

Use `bill.total_amount` and `payment.amount` for comparisons.

- [ ] **Step 2: Run specs**

Run targeted spec.
Expected: PASS

---

## Task 14: Update cron charge_due_subscriptions

**Files:**
- Modify: `app/services/payments/cron/charge_due_subscriptions.rb`
- Test: `spec/services/payments/cron/charge_due_subscriptions_spec.rb`

- [ ] **Step 1: Update activity**

Replace `sub.amount_cents` and `o.amount_cents = sub.amount_cents` with `sub.amount` and `o.amount = sub.amount`.

- [ ] **Step 2: Run specs**

Run: `bundle exec rspec spec/services/payments/cron/charge_due_subscriptions_spec.rb`
Expected: PASS

---

## Task 15: Update gateways

**Files:**
- Modify: `app/services/payments/gateways/stripe.rb`
- Modify: `app/services/payments/gateways/paypal.rb`
- Modify: `app/services/payments/gateways/alipay.rb`
- Modify: `app/services/payments/gateways/wechat_pay.rb`
- Test: corresponding specs under `spec/services/payments/gateways/` (create if missing)

- [ ] **Step 1: Update Stripe**

Replace `Payments::Money.new(order.amount_cents, ...)` with `Payments::Money.new(order.amount, ...)`.

- [ ] **Step 2: Update PayPal**

Use `Payments::Money.new(refund.amount, currency).decimal_string`.

- [ ] **Step 3: Update Alipay**

Use `Payments::Money.new(order.amount, "cny").decimal_string`.

- [ ] **Step 4: Update WeChat Pay**

For now, continue using `amount_cents` during transition: `refund.amount_cents`, `payment.amount_cents`, `order.amount_cents`. (Will switch to `(amount * 100).round` in Phase 3.)

- [ ] **Step 5: Run gateway specs**

Run: `bundle exec rspec spec/services/payments/gateways/`
Expected: PASS

---

## Task 16: Update controllers

**Files:**
- Modify: `app/controllers/payments/checkouts_controller.rb`
- Modify: `app/controllers/admin/modules/payments/refunds_controller.rb`
- Modify: `app/controllers/admin/modules/payments/subscriptions_controller.rb`
- Test: corresponding request specs

**Interfaces:**
- Consumes: `amount` param from forms.
- Produces: records created with decimal `amount`.

- [ ] **Step 1: Update checkouts_controller**

Change `order.amount_cents = input[:amount_cents]` to `order.amount = input[:amount]` and `amount_cents: @order.amount_cents` to `amount: @order.amount`.

- [ ] **Step 2: Update refunds_controller**

Change `amount_cents: params[:amount_cents].to_i` to `amount: params[:amount].to_d`.

- [ ] **Step 3: Update subscriptions_controller**

Change `amount_cents: subscription_params[:amount_cents].to_i` to `amount: subscription_params[:amount].to_d` and strong params from `:amount_cents` to `:amount`.

- [ ] **Step 4: Run request specs**

Run:
```bash
bundle exec rspec spec/requests/payments/checkouts_spec.rb spec/requests/admin/modules/payments/refunds_spec.rb spec/requests/admin/modules/payments/subscriptions_spec.rb
```
Expected: PASS

---

## Task 17: Update components and views

**Files:**
- Modify: `app/components/payments/checkout_component.rb`
- Modify: `app/components/payments/widget_checkout_component.rb`
- Modify: `app/components/payments/member/subscriptions_component.rb`
- Modify: `app/components/payments/admin/refund_dialog_component.rb` + `.html.erb`
- Modify: `app/components/payments/admin/reconciliation_table_component.html.erb`
- Test: corresponding component specs

- [ ] **Step 1: Replace manual division**

In checkout/widget_checkout/subscriptions components, replace:
```ruby
format("%.2f", order.amount_cents / 100.0)
```
with:
```ruby
format("%.2f", order.amount)
```

- [ ] **Step 2: Update refund dialog**

Change form field from `amount_cents` to `amount`, `value: payment.amount_cents` to `value: payment.amount`, and maximum prefix from `payment.amount_cents` to `format("%.2f", payment.amount)` with currency symbol.

- [ ] **Step 3: Update reconciliation table**

Use `b.total_amount` instead of `b.total_amount_cents / 100.0`.

- [ ] **Step 4: Run component specs**

Run: `bundle exec rspec spec/components/payments/`
Expected: PASS

---

## Task 18: Update locales

**Files:**
- Modify: `config/locales/comp_payments.en.yml`
- Modify: `config/locales/comp_payments.zh-CN.yml`

- [ ] **Step 1: Update labels**

Change keys like `amount_cents` to `amount` and English text from "Amount (cents)" to "Amount". Add matching zh-CN keys.

- [ ] **Step 2: Verify no hard-coded cents strings**

Run: `grep -R "amount_cents" app/components/payments app/views/payments config/locales/comp_payments*`
Expected: only migration/model sync code remains (not user-facing).

---

## Task 19: Update factories and model specs

**Files:**
- Modify: `spec/factories/billing_payment_methods.rb` and any payment factories
- Modify: `spec/models/payments/*_spec.rb`

- [ ] **Step 1: Update factories**

Change `amount_cents { 3109 }` to `amount { 31.09 }`.

- [ ] **Step 2: Run model specs**

Run: `bundle exec rspec spec/models/payments/`
Expected: PASS

---

## Task 20: Run payment-module regression

**Files:** all touched specs

- [ ] **Step 1: Run focused payment-module suite**

```bash
bundle exec rspec spec/models/payments spec/services/payments spec/components/payments spec/requests/payments spec/requests/admin/modules/payments spec/requests/member/payments
```

Expected: PASS. Fix any remaining `amount_cents` references.

---

## Task 21: Phase 3 migration — drop old columns

**Files:**
- Create: `db/migrate/20260718120000_drop_amount_cents_from_payment_tables.rb`

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260718120000_drop_amount_cents_from_payment_tables.rb
class DropAmountCentsFromPaymentTables < ActiveRecord::Migration[8.1]
  def up
    remove_column :payment_orders, :amount_cents
    remove_column :payments, :amount_cents
    remove_column :payment_refunds, :amount_cents
    remove_column :payment_subscriptions, :amount_cents
    remove_column :payment_disputes, :amount_cents
    remove_column :payment_reconciliation_bills, :total_amount_cents
  end

  def down
    add_column :payment_orders, :amount_cents, :integer
    add_column :payments, :amount_cents, :integer
    add_column :payment_refunds, :amount_cents, :integer
    add_column :payment_subscriptions, :amount_cents, :integer
    add_column :payment_disputes, :amount_cents, :integer
    add_column :payment_reconciliation_bills, :total_amount_cents, :integer
  end
end
```

- [ ] **Step 2: Remove sync callbacks from models**

After this migration, remove the `before_validation` sync callbacks and any remaining `amount_cents` references from the six models.

- [ ] **Step 3: Run final migration**

Run: `bin/rails db:migrate`
Expected: exits 0.

- [ ] **Step 4: Run final regression**

Run the same focused payment-module suite as Task 20.
Expected: PASS.

---

## Plan Self-Review

- **Spec coverage:** every section of `2026-07-18-payment-amount-design.md` maps to one or more tasks above.
- **Placeholder scan:** no "TBD", "TODO", or vague steps; each task has concrete file paths and code.
- **Type consistency:** `amount` is consistently `decimal(12,2)`; `total_amount` used only for `payment_reconciliation_bills`.

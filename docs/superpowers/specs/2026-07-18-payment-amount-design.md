# Payment Module Amount Storage Migration Design

**Date:** 2026-07-18  
**Status:** Approved  
**Approach:** Dual-write phased migration from integer `amount_cents` to decimal `amount`.

## Goal

Stop representing payment-module amounts as integer cents. Store and display amounts as two-decimal major-unit values (e.g., `3109` cents becomes `$31.09` and is stored as `31.09`). Zero-decimal currencies such as JPY are also stored with two decimals (`1000.00`) for consistency.

## Background

The payment module currently stores every monetary amount as `amount_cents`, an integer equal to `major_units × 100`, even for zero-decimal currencies. Display and PSP integrations then divide or rescale the value. This creates three problems:

1. **User-facing confusion:** admins and members see raw cent values in forms and some UI surfaces.
2. **Inconsistent formatting:** admin tables use `Payments::Admin::CurrencyFormatting`, while checkout / member surfaces divide by 100 manually.
3. **PSP conversion risk:** every gateway must remember whether the integer is cents, smallest units, or major-unit×100.

Storing a currency-aware `decimal(12,2)` `amount` column removes the implicit `/100` math from business logic and makes the stored value match the displayed value.

## Scope

In scope: all payment-module tables that store an amount as integer cents.

| Table | Old column | New column |
|-------|------------|------------|
| `payment_orders` | `amount_cents` | `amount` decimal(12,2) |
| `payments` | `amount_cents` | `amount` decimal(12,2) |
| `payment_refunds` | `amount_cents` | `amount` decimal(12,2) |
| `payment_subscriptions` | `amount_cents` | `amount` decimal(12,2) |
| `payment_reconciliation_bills` | `total_amount_cents` | `total_amount` decimal(12,2) |
| `payment_disputes` | `amount_cents` | `amount` decimal(12,2) |

Out of scope (unless later requested): billing-module tables (`billing_invoices`, `billing_subscriptions`, `billing_plans`, `billing_invoice_line_items`), which also use integer cents but belong to a separate domain.

## Design Decisions

1. **Dual-write migration.** Add decimal columns, backfill them, update code to read from the new columns while keeping the old columns synchronized, then drop the old columns in a later phase. This allows verification and easy rollback.
2. **Always two decimals in storage.** `amount` is `decimal(12,2)`. JPY `1000` is stored as `1000.00`. Conversion to PSP-specific units remains currency-aware via `Payments::Money`.
3. **Rename public read usage to `amount`**, but keep `amount_cents` writable during the transition so dual-write sync is straightforward.
4. `Payments::Money` becomes the single converter from the new decimal major-unit value to each PSP’s expected representation.

## Schema & Data Migration

### Phase 1 migration

For each table, run a single migration that:

1. Adds the new decimal column.
2. Backfills it from the existing integer column divided by `100.0`.
3. Adds a `NOT NULL` constraint after backfill.
4. Adds a database index if the column is queried in listings or reports.

Example for `payment_orders`:

```ruby
add_column :payment_orders, :amount, :decimal, precision: 12, scale: 2
execute <<-SQL.squish
  UPDATE payment_orders
  SET amount = amount_cents / 100.0
  WHERE amount_cents IS NOT NULL
SQL
change_column_null :payment_orders, :amount, false
add_index :payment_orders, :amount
```

The same pattern applies to the other five tables, with `total_amount` used for `payment_reconciliation_bills`.

## Model Layer

### Validations

Replace integer-cent validations with decimal amount validations:

```ruby
validates :amount, presence: true, numericality: { greater_than: 0 }
```

`only_integer: true` is removed. Scale is enforced by the database column.

### Dual-write synchronization

During Phase 1 and Phase 2, both columns must remain in sync. Implement this with overridden setters plus a callback guard:

```ruby
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

New code should write to `amount`; legacy code paths that still write to `amount_cents` continue to work until the column is dropped.

### Public API

Add a convenience reader if needed, but prefer direct `amount` usage:

```ruby
# Preferred
order.amount # => 31.09

# Legacy compatibility during transition
order.amount_cents # => 3109
```

## Services & Gateways

### `Payments::Money`

Change `Payments::Money` so its constructor accepts a major-unit decimal value instead of `major_units × 100`:

- `smallest_unit`: for 2-decimal currencies return `(amount * 100).round`; for zero-decimal return `amount.round`.
- `decimal_string`: for 2-decimal currencies return `"%.2f" % amount`; for zero-decimal return the integer string.

Class helpers `cents_from_major` and `cents_from_smallest_unit` are renamed or replaced to reflect the new canonical unit. Keep old names as aliases during Phases 1–2 and remove them in Phase 4 once `amount_cents` is dropped.

### Services to update

- `Payments::Activities::Charge`
- `Payments::Activities::ChargeToken`
- `Payments::Activities::CreateSubscription`
- `Payments::Activities::Refund`
- `Payments::Activities::HandleWebhook`
- `Payments::Activities::Reconcile`
- `Payments::Cron::ChargeDueSubscriptions`
- `Payments::Contracts::Charge`, `Refund`, `Subscribe`

These should read `amount` from orders/payments/subscriptions and pass decimals to `Payments::Money` where PSP-specific conversion is needed.

### Gateways

- **Stripe:** expects smallest units. Convert via `Payments::Money.new(order.amount, order.currency).smallest_unit`.
- **PayPal:** expects major-unit decimal strings. Use `Payments::Money#decimal_string`.
- **Alipay:** expects major-unit decimal strings for CNY. Use `Payments::Money#decimal_string`.
- **WeChat Pay:** historically expects integer cents for CNY. Continue using the synchronized `amount_cents` during the transition, then switch to `(amount * 100).round` once `amount_cents` is dropped.

## Controllers & UI

### Forms

Change number inputs from `amount_cents` to `amount` with step `0.01`:

```erb
<%= f.number_field :amount, step: 0.01, min: 0.01, class: "input-field" %>
```

Update strong-parameter permits to allow `:amount` instead of `:amount_cents`.

### Components & views

Remove manual `amount_cents / 100.0` formatting in:

- `Payments::CheckoutComponent`
- `Payments::WidgetCheckoutComponent`
- `Payments::Member::SubscriptionsComponent`
- `Payments::Admin::RefundDialogComponent` (maximum prefix)
- `Payments::Admin::ReconciliationTableComponent`

Use `Billing::CurrencyResolver.format_amount(amount, currency)` for display where a formatted string is needed.

### Locales and labels

Update form labels and helper text in `config/locales/comp_payments.en.yml` and `comp_payments.zh-CN.yml` so users see "Amount" instead of "Amount (cents)". Update JavaScript amount references in payment controllers if any client-side validation or display still assumes cents.

## Contracts

Update dry-validation contracts to accept `amount` as a decimal:

```ruby
property :amount
validates :amount, presence: true, numericality: { greater_than: 0 }
```

Controllers must convert string params to decimal (`params[:amount].to_d`).

## Testing

1. **Factories:** update payment-module factories to set `amount` instead of `amount_cents`.
2. **Migration test:** verify backfill accuracy for a representative set of records, including negative refund amounts if applicable.
3. **Model round-trip tests:** assign `amount`, assert `amount_cents` is synchronized; assign `amount_cents`, assert `amount` is synchronized.
4. **Service tests:** update existing specs to pass decimal amounts and assert correct PSP payloads.
5. **Gateway tests:** assert Stripe/PayPal/Alipay/WeChat receive the expected units.
6. **Request tests:** submit forms with `amount` and verify records are created correctly.
7. **Regression test:** run the full payment-module RSpec suite before dropping old columns.

## Rollout Phases

| Phase | Work | Deployable? |
|-------|------|-------------|
| 1 | Schema migrations + model dual-write + backfill | Yes |
| 2 | Migrate all read paths (services, gateways, controllers, components, contracts, tests) | Yes |
| 3 | Verify data parity, monitor for one release cycle | Yes (monitoring) |
| 4 | Drop `amount_cents` / `total_amount_cents` columns and remove sync callbacks | Yes |

## Rollback Plan

- **Before Phase 4:** rollback is a code deploy reverting to `amount_cents` reads; the decimal columns can remain or be removed by a reverse migration.
- **After Phase 4:** rollback requires re-adding integer columns and re-deriving cents from `amount * 100`. Avoid this by completing Phase 3 verification.

## Non-Goals

- Changing how billing-module invoices or subscriptions store amounts.
- Changing the `money` gem or `Billing::CurrencyResolver` formatting behavior.
- Supporting more than two decimal places for any currency.
- Modifying external PSP APIs; we only change how our code maps values to those APIs.

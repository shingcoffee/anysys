# Billing — Industry-Standard Plans + Customer Payment Methods

**Date:** 2026-06-21
**Status:** Approved for implementation (autonomous build)
**Builds on:** `2026-06-21-platform-billing-design.md`

## Problem

Two capabilities to add to the existing Billing module:

1. **Platform owner** (customer `81721200`, under `/81721200/admin/maintenance/platform/module_settings/billing/plans`) configures the **available industry-standard subscription plans**. Plans CRUD already exists; add a one-click **standard-plan seeder** (Free / Starter / Pro / Enterprise, monthly + yearly) so the owner starts from an industry-standard catalog and edits from there.
2. **Customer** (in `/:cid/admin/settings/modules/billing`) chooses a plan (exists) **and configures a payment method** that authorizes the recurring service-fee charge. This is the new core piece — industry-standard "card/mandate on file" billing.

## Industry-standard model (how charging works)

The platform (`81721200`'s merchant account) is the **payee**; each tenant is the **payer**. A tenant's "payment method" is a **signed recurring payment mandate** — the `Payments::Subscription` agreement primitive (e.g. Alipay/WeChat 代扣 withholding agreement, `psp_agreement_id`). The tenant authorizes it once; the daily billing job then pulls each invoice via `Payments::Gateway.charge_subscription` against that mandate. This reuses the Payments module end-to-end (no new PSP code) and mirrors Stripe-style "save a payment method, then auto-charge subscriptions".

## Data model

### `billing_payment_methods` (tenant-scoped, new)
`customer_id` (indexed), `provider` (string — a registered `Payments::Gateways` key that the platform has an active merchant account for), `payments_subscription_id` (bigint → the mandate row under `81721200`), `status` (`pending|active|failed|removed`), `display_label` (string), `is_default` (boolean), `authorized_at` (datetime), timestamps.
**Partial unique index** on `customer_id` where `is_default = true AND status = 'active'` → at most one default active method per tenant.

Model `Billing::PaymentMethod` — `include TenantScoped`; `belongs_to :payments_subscription, class_name: "Payments::Subscription", optional: true`; `STATUSES`; scopes `active`, `default_method`; state methods `mark_active!`, `mark_failed!`, `mark_removed!`.

## Services

- `Billing::Activities::SetUpPaymentMethod.call(customer:, provider:)` — validate provider has an active platform merchant account (under `81721200`); find/reuse-or-create a `Payments::Subscription` mandate under `81721200` (`external_ref: "billing-pm-<customer_id>"`, cycle from the customer's plan interval or default monthly); sign it via `Payments::Gateway.subscribe`; upsert the tenant's `Billing::PaymentMethod` (status active, default), demoting any prior default. Returns the payment method.
- `Billing::Activities::RemovePaymentMethod.call(payment_method:)` — best-effort `Payments::Gateway.cancel_subscription` on the mandate, then `mark_removed!`.
- `Billing::Contracts::PaymentMethod` — `provider` presence + inclusion in the available-provider list.
- `Billing::AvailableProviders.call` — returns registered gateway keys that have an active `Payments::MerchantAccount` under `81721200` (the providers a tenant may choose).
- `Billing::StandardPlans.seed!` — idempotent `find_or_create_by(code:)` for the canonical catalog (free, starter-monthly/yearly, pro-monthly/yearly, enterprise-monthly/yearly) with sensible amounts, `trial_days`, and `features` JSON. Never overwrites edited plans.

### Collector rewiring
`Billing::Collector` gateway path now resolves the **invoice's customer's** active default `Billing::PaymentMethod` and charges its mandate via `charge_subscription` (payee = `81721200`). If the tenant has **no active payment method**, return `{status: :failed, reason: :no_payment_method}` — the invoice stays `open` and dunning/notifier prompts the tenant to add one. (Removes the previous auto-create-mandate-per-subscription behavior; the explicit customer payment method is now the source of truth.)

## URLs (existing four areas)

- **(b) Customer Settings** — add under `namespace :billing` in `settings/modules`:
  `resource :payment_method, only: %i[show create destroy], controller: "payment_methods"`.
  Controller `Admin::Settings::Modules::Billing::PaymentMethodsController` (admin/owner of tenant; record actions tenant-scoped): `show` (current method + provider options), `create` (SetUpPaymentMethod), `destroy` (RemovePaymentMethod).
- **(d) Platform Settings** — add under platform `namespace :billing`:
  `resource :standard_plans, only: :create` → `Maintenance::Platform::Billing::StandardPlansController#create` (owner-only) runs `Billing::StandardPlans.seed!` and redirects to plans index.

## UI (ViewComponent + Tailwind + Stimulus, responsive)

- `Billing::Admin::PaymentMethodComponent` — current method card (provider, status badge, authorized date, "Remove" action) OR empty-state with a provider `<select>` + "Authorize payment method" submit. Rendered as a new **"Payment Method"** section on the area-b subscription show page.
- Platform **plans index** — add a "Seed standard plans" button (POST to `standard_plans`) shown when the catalog is empty or always (idempotent).

## Authorization & tenancy

- Area (b) payment-method actions: admin/owner of the tenant only; every action scoped to `current_customer` (a tenant can only see/modify its own method). Mandates live under `81721200` but are keyed per tenant and never exposed cross-tenant.
- Area (d) seeder + plans: owner-only via the `/platform/` path rule.
- `provider` accepted only if it is in `Billing::AvailableProviders.call` (no arbitrary provider injection).

## Testing (RSpec, multi-tenant focus)

Model spec (states, default-uniqueness index), activity specs (set-up creates+signs mandate & sets default, demotes prior, remove cancels; gateway mocked), contract spec, `AvailableProviders` spec, `StandardPlans.seed!` idempotency spec, collector specs (charges customer method; no-method → failed/open), component spec, request specs (tenant isolation on payment method; member blocked; owner-only seeder).

## Out of scope

- Real PSP redirect/QR signing UX (gateways are sandbox/stubbed in dev) — the mandate-signing call is made but its interactive completion is the gateway's concern.
- Multiple saved methods per tenant (one default active method; model allows history via `removed`).
- Storing raw card data (delegated to the gateway/mandate).

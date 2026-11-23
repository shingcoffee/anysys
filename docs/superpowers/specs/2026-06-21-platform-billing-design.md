# Platform Billing — Design Spec

**Date:** 2026-06-21
**Status:** Approved for implementation (autonomous build)
**Module key:** `billing`

## 1. Problem & Scope

The platform needs to charge its **customers (tenants)** a recurring **service fee** for
using the application. This is *platform → tenant* SaaS subscription billing.

This is a **distinct domain** from the existing Payments module, which is *tenant →
end-user* collection (Alipay / WeChat). Billing gets its own `Billing::` namespace and
**reuses** the Payments gateway abstraction for actual money movement (the platform owner's
merchant account collects from each tenant), rather than re-implementing PSP integration.

### In scope (a functional recurring-billing system)

1. **Plans** — platform-global catalog (Free/Pro/Enterprise style): price, interval, trial, feature limits.
2. **Subscriptions** — one per customer, lifecycle: `trialing → active → past_due → cancelled/expired` (+ `paused`).
3. **Invoices** + **line items** — generated each billing period; totals with discount + tax.
4. **Coupons / discounts** — percent or fixed, with redemption limits & duration.
5. **Proration** — credit/charge line items on mid-cycle plan change.
6. **Trials** — `trial_days` on a plan; first invoice issued at trial end.
7. **Recurring billing job** — daily: renew periods, generate invoices, collect, run dunning.
8. **Dunning / retries** — configurable retry schedule, grace period, escalate to `past_due`, then suspend.
9. **Money collection** — `Billing::Collector` with two strategies: `:gateway` (delegates to `Payments::Gateway`) and `:manual` (platform owner marks paid offline). Manual is the always-available fallback.
10. **Customer self-service** — view current plan, change plan, cancel/resume, view & download own invoices.
11. **Platform admin** — CRUD plans & coupons, oversee all tenant subscriptions & invoices, global billing settings.
12. **Notifications** — email on invoice issued, payment success/failure, trial ending, cancellation, past-due.
13. **Authorization** — customer surfaces scoped to admin/owner of that customer; platform surfaces owner-only.

### Out of scope (YAGNI)

- Usage-based / metered billing (flat recurring only).
- More than one active subscription per customer.
- Storing raw card data / PCI handling (delegated entirely to the gateway).
- Multi-currency *per customer* (single platform currency, configurable in billing settings).
- Pluggable tax engines (single flat platform tax rate).

## 2. Data Model

All money in integer **cents**. Customer-owned tables `include TenantScoped` and carry
`customer_id` (indexed first). Platform-catalog tables (`plans`, `coupons`, `settings`) are
**global** (no `customer_id`) — same pattern as `captcha_provider_settings` — and are managed
only by the platform owner.

### `billing_plans` (global)
`code` (unique), `name`, `description`, `amount_cents`, `currency`, `interval`
(`monthly|yearly`), `trial_days` (int, default 0), `features` (JSON limits blob),
`active` (bool), `is_default` (bool — provisioning target), `position` (int).

### `billing_subscriptions` (tenant)
`customer_id`, `billing_plan_id`, `status`
(`trialing|active|past_due|paused|cancelled|expired`), `current_period_start`,
`current_period_end`, `trial_end`, `cancel_at_period_end` (bool),
`amount_cents` (snapshot of plan price at subscribe time), `interval` (snapshot),
`coupon_id` (nullable), `started_at`, `cancelled_at`, `ended_at`.
**Partial unique index** on `customer_id` where `status IN (trialing,active,past_due,paused)`
→ at most one live subscription per tenant.

### `billing_invoices` (tenant)
`customer_id`, `billing_subscription_id`, `number` (unique, generated `INV-<cid>-<seq>`),
`status` (`draft|open|paid|void|uncollectible`), `period_start`, `period_end`,
`subtotal_cents`, `discount_cents`, `tax_cents`, `total_cents`, `currency`,
`due_at`, `issued_at`, `paid_at`, `attempt_count` (int, default 0), `next_attempt_at`,
`coupon_id` (nullable), `payment_id` (nullable → `Payments::Payment`), `collection_mode`.

### `billing_invoice_line_items` (tenant)
`customer_id`, `billing_invoice_id`, `description`, `quantity`, `unit_amount_cents`,
`amount_cents`, `kind` (`subscription|proration|discount|tax`).

### `billing_coupons` (global)
`code` (unique), `name`, `discount_type` (`percent|fixed`), `percent_off` (int 1–100),
`amount_off_cents`, `currency`, `duration` (`once|repeating|forever`),
`duration_in_cycles` (int, for `repeating`), `max_redemptions`, `times_redeemed`,
`redeem_by` (datetime), `active`.

### `billing_settings` (global singleton)
`currency` (default `CNY`), `tax_rate_bps` (basis points, e.g. 0), `collection_mode`
(`manual|gateway`, default `manual`), `gateway_provider` (used when `gateway`),
`dunning_schedule` (JSON array of day offsets, e.g. `[1,3,7]`), `grace_period_days`,
`trial_ending_notice_days` (default 3). Accessed via `Billing::Settings.current` (find_or_create).

## 3. Domain Services (thin model + Activities + Reform contracts)

Models stay thin (validations, scopes, explicit `mark_*!` state transitions — matching the
Payments convention). Business logic lives in `Billing::Activities::*`; input validation in
`Billing::Contracts::*` (Reform).

### Activities (`app/services/billing/activities/`)
- `Subscribe` — create subscription to a plan; start trial (if `trial_days > 0`) or first period; generate first invoice (immediate if no trial).
- `ChangePlan` — switch plan; compute **proration** (unused-time credit on old plan + prorated charge on new plan) as line items on an immediate invoice; snapshot new amount/interval.
- `CancelSubscription` — `cancel_at_period_end: true` (default, expires at period end) or `immediately: true` (status→cancelled, void open invoices).
- `ResumeSubscription` / `PauseSubscription`.
- `GenerateInvoice` — build draft invoice + subscription line item for a subscription's period.
- `FinalizeInvoice` — draft→open: apply coupon discount, apply tax, compute totals, set `due_at`, assign `number`, notify "issued".
- `CollectInvoice` — dispatch to `Billing::Collector`; on success → `MarkInvoicePaid`; on failure → schedule dunning.
- `MarkInvoicePaid` / `VoidInvoice`.
- `ApplyCoupon` — validate redeemability, attach to subscription/invoice, bump `times_redeemed`.

### Collection (`app/services/billing/collector.rb`)
Strategy facade keyed by `Billing::Settings.current.collection_mode`:
- `:manual` → no-op auto-collect; invoice stays `open` for platform-owner manual settlement. Always the safe default.
- `:gateway` → creates a `Payments::Payment` and calls `Payments::Gateway.charge(...)` using the **platform owner's** active merchant account for `gateway_provider`; links `payment_id`; success/failure routed back to the invoice.

### Cron (`app/services/billing/cron/` + orchestrating job)
A single `Billing::DailyBillingJob < ApplicationJob` (registered in `config/recurring.yml`,
daily) calls, in order, across all tenants (`unscoped_by_tenant`, setting `Current.customer`
per row, errors logged & swallowed per record like the Payments cron):
1. `RenewSubscriptions` — period rolled over: transition `trialing→active`, generate next invoice, advance period; flip `cancel_at_period_end` subscriptions to `expired`.
2. `CollectDueInvoices` — `open` invoices with `due_at <= now` and `next_attempt_at <= now`: attempt collection.
3. `Dunning` — failed invoices: retry per `dunning_schedule`; after grace, mark invoice `uncollectible`, subscription `past_due` → eventually `cancelled`; send notifications.
4. `TrialEndingNotices` — notify subscriptions whose `trial_end` is within `trial_ending_notice_days`.

### Notifications (`app/services/billing/notifier.rb` + `BillingMailer`)
Events: `invoice_issued`, `payment_succeeded`, `payment_failed`, `trial_ending`,
`subscription_cancelled`, `subscription_past_due`. Thin notifier → ActionMailer.

## 4. Feature Module Registration

`app/services/feature_modules/billing/{registration,provisioner}.rb` following the Payments
pattern. `Registration < FeatureModules::BaseModule`:
- `module_key "billing"`, name "Billing", description.
- `provision!(customer)` → `Provisioner.call`: ensure `Billing::Settings` row exists; if a plan
  is `is_default`, subscribe the customer to it (trial if applicable) via `Activities::Subscribe`.
- `deprovision!(customer)` → cancel subscription immediately + void open invoices.
- `sidebar_contributions` → `:entries` (Invoices, Subscription) under area (a); `:settings`
  (Plan & Subscription management) under area (b), both `permitted_by: :admin_or_owner?`.

## 5. URL / Navigation Mapping (the four areas)

- **(a) Entries & Records** — `/:cid/admin/modules/billing/...` (customer admin/owner): read-only
  `invoices` (index/show + `download`), `subscription` (show).
- **(b) Customer Settings** — `/:cid/admin/settings/modules/billing/...` (customer admin/owner):
  `subscription` (show/edit/update — pick/change plan), `cancellation` (create/destroy = cancel/resume),
  apply coupon.
- **(c) Enable/Disable** — centralized `Maintenance / Modules` toggle (no new route; module registers itself).
- **(d) Platform Settings** — `/:cid/maintenance/platform/module_settings/billing/...` (owner only,
  customer `81721200`): `plans` (CRUD), `coupons` (CRUD), `subscriptions` (index/show + admin actions:
  cancel, mark-paid), `invoices` (index/show + actions: mark_paid, void, retry), `settings` (show/edit/update).

Routes added inside the existing `namespace :settings { namespace :modules ... }` block (area b),
the `namespace :modules` block (area a), and the platform `scope :module_settings, as: :module_settings`
block (area d). Controllers inherit auth guards from the path-based `RouteAuthorization` concern;
record-level actions additionally assert `record.customer_id == current_user.customer_id` (tenant) for
areas a/b. Platform controllers are owner-gated by the `/platform/` path rule.

## 6. UI (ViewComponent + Tailwind + Stimulus)

Consistent backend-admin layout, fully responsive. Surfaces:
- **Customer plan picker / subscription page** (b): plan cards, current status badge, change-plan + cancel/resume, apply-coupon field.
- **Customer invoices** (a): table (number, period, total, status, due) + invoice detail (line items, totals) + printable download.
- **Platform plans & coupons CRUD** (d): index tables + forms (component-driven dynamic forms like the merchant-account form).
- **Platform subscriptions & invoices oversight** (d): filterable tables + detail with admin actions.
- **Platform billing settings** (d): currency, tax, collection mode + provider, dunning schedule editor.

All views encapsulated in `Billing::Admin::*Component` ViewComponents with component specs.

## 7. Authorization & Multi-Tenancy

- Areas (a)(b): `RouteAuthorization` admits admin/owner of the tenant; every record action re-checks
  `customer_id == current_user.customer_id`. Cross-tenant access blocked.
- Area (d): owner-only via the `/platform/` path rule; visible only under customer `81721200`.
- Plans/coupons/settings have **no** `customer_id` (global catalog) — mutated only through owner-gated (d) controllers.
- Collection via gateway uses the **platform owner's** merchant account, never a tenant's.

## 8. Testing (RSpec, TDD, multi-tenant focus)

Per slice: model specs (validations, state transitions, scopes, proration math), activity specs
(subscribe/change-plan/finalize/collect/dunning paths), contract specs, collector specs (manual +
gateway, gateway mocked), cron/job specs (renewal, dunning escalation, trial notices), component
specs, and request specs asserting **tenant isolation** (customer A cannot read B's invoices) and
**authorization** (member blocked from admin/settings; non-owner blocked from platform).

## 9. Implementation Phasing

1. **Schema + models** — 6 migrations, 6 thin models, `Billing::Settings` accessor. (backend)
2. **Activities + contracts + collector** — subscription lifecycle, invoicing, proration, coupon, collection. (backend)
3. **Cron + job + notifier + mailer** — daily orchestrator, dunning, trial notices; register in recurring.yml. (backend)
4. **Routes + controllers** — areas a/b/d with guards + tenant checks. (security)
5. **ViewComponents + ERB + Stimulus** — all surfaces. (frontend)
6. **Feature module registration + provisioner + sidebar**. (backend)
7. **RSpec** across all layers, isolation + authz focus. (qa)
8. **Release smoke** (rspec on touched files, assets, SKIP_AUTH server) + **parallel review** (tech-lead + code-reviewer).

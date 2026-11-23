# Platform Billing Implementation Plan

> **For agentic workers:** This plan is executed through the anysys-* SDLC agent team (per AGENTS.md): parallel backend / frontend / security build slices, then QA, release smoke, and parallel tech-lead + code-reviewer. TDD throughout. All paths are relative to the worktree root `/home/ec2-user/anysys/.worktrees/add-customer-billing-setting`.

**Goal:** Add a `Billing::` module so the platform charges each customer (tenant) a recurring service fee — plans, subscriptions, invoices, coupons, proration, trials, dunning, collection, customer self-service, and platform admin.

**Architecture:** Self-contained `Billing::` namespace. Platform-global catalog tables (`billing_plans`, `billing_coupons`, `billing_settings`) have no `customer_id`; tenant tables (`billing_subscriptions`, `billing_invoices`, `billing_invoice_line_items`) `include TenantScoped`. Thin models + `Billing::Activities::*` + `Billing::Contracts::*` (Reform). Money movement delegated to the existing `Payments::Gateway` facade via `Billing::Collector` (modes `:manual` default / `:gateway`). Daily `Billing::DailyBillingJob` (solid_queue recurring) orchestrates renewal, collection, dunning, trial notices.

**Tech Stack:** Rails 8.1, solid_queue, Reform, ViewComponent, TailwindCSS, StimulusJS, RSpec.

**Spec:** `docs/superpowers/specs/2026-06-21-platform-billing-design.md`

---

## File Structure

```
app/models/billing/
  plan.rb  subscription.rb  invoice.rb  invoice_line_item.rb  coupon.rb  settings.rb
app/services/billing/
  collector.rb  notifier.rb
  activities/{subscribe,change_plan,cancel_subscription,resume_subscription,pause_subscription,
              generate_invoice,finalize_invoice,collect_invoice,mark_invoice_paid,void_invoice,apply_coupon}.rb
  contracts/{subscribe,change_plan,plan,coupon,settings}.rb
  cron/{renew_subscriptions,collect_due_invoices,dunning,trial_ending_notices}.rb
  proration.rb            # pure proration math helper
app/jobs/billing/daily_billing_job.rb
app/mailers/billing_mailer.rb + app/views/billing_mailer/*.erb
app/services/feature_modules/billing/{registration,provisioner}.rb
db/migrate/*_create_billing_*.rb            # 6 migrations
config/routes.rb                            # areas a / b / d blocks
config/recurring.yml                        # daily job

# Controllers
app/controllers/admin/modules/billing/{base_controller,invoices_controller,subscriptions_controller}.rb
app/controllers/admin/settings/modules/billing/{base_controller,subscriptions_controller,cancellations_controller,coupon_redemptions_controller}.rb
app/controllers/maintenance/platform/billing/{plans_controller,coupons_controller,subscriptions_controller,invoices_controller,settings_controller}.rb

# ViewComponents (each: .rb + .html.erb + *_spec.rb; Stimulus where interactive)
app/components/billing/admin/{plan_picker,subscription_summary,invoice_table,invoice_detail,
  plan_form,coupon_form,settings_form,subscriptions_table}_component.*
app/javascript/controllers/billing_*_controller.js
```

---

## Phase 1 — Schema + Models (backend slice)

**Migrations** (one per table; integer cents; `customer_id` first + indexed on tenant tables):

- `billing_plans`: `code:string` (unique idx), `name`, `description:text`, `amount_cents:integer`, `currency:string` default "CNY", `interval:string`, `trial_days:integer` default 0, `features:json`, `active:boolean` default true, `is_default:boolean` default false, `position:integer` default 0. Unique index `code`.
- `billing_coupons`: `code` (unique idx), `name`, `discount_type`, `percent_off:integer`, `amount_off_cents:integer`, `currency`, `duration`, `duration_in_cycles:integer`, `max_redemptions:integer`, `times_redeemed:integer` default 0, `redeem_by:datetime`, `active:boolean` default true.
- `billing_settings`: `currency` default "CNY", `tax_rate_bps:integer` default 0, `collection_mode:string` default "manual", `gateway_provider:string`, `dunning_schedule:json`, `grace_period_days:integer` default 7, `trial_ending_notice_days:integer` default 3. (single row)
- `billing_subscriptions`: `customer_id:bigint`, `billing_plan_id:bigint`, `status`, `current_period_start:datetime`, `current_period_end:datetime`, `trial_end:datetime`, `cancel_at_period_end:boolean` default false, `amount_cents:integer`, `interval:string`, `billing_coupon_id:bigint`, `started_at`, `cancelled_at`, `ended_at`, timestamps. Index `customer_id`; **partial unique** index on `customer_id` where `status IN ('trialing','active','past_due','paused')` (Postgres: `where: "status IN (...)"`).
- `billing_invoices`: `customer_id:bigint`, `billing_subscription_id:bigint`, `number:string`, `status` default "draft", `period_start`, `period_end`, `subtotal_cents:integer` default 0, `discount_cents:integer` default 0, `tax_cents:integer` default 0, `total_cents:integer` default 0, `currency`, `due_at:datetime`, `issued_at`, `paid_at`, `attempt_count:integer` default 0, `next_attempt_at:datetime`, `billing_coupon_id:bigint`, `payment_id:bigint`, `collection_mode:string`, timestamps. Index `customer_id`, unique index `number`, index `[:status, :next_attempt_at]`.
- `billing_invoice_line_items`: `customer_id:bigint`, `billing_invoice_id:bigint`, `description`, `quantity:integer` default 1, `unit_amount_cents:integer`, `amount_cents:integer`, `kind:string`, timestamps. Index `customer_id`, `billing_invoice_id`.

**Models** (thin; mirror `Payments::Subscription` style — constants, validations, scopes, `mark_*!`):

- `Billing::Plan` — `INTERVALS=%w[monthly yearly]`; validations on `code` (presence/uniqueness), `amount_cents` (>=0 integer), `interval` inclusion; scopes `active`, `ordered` (position then id); `default_plan` class method (`active.find_by(is_default: true)`); `monthly?`/`yearly?`.
- `Billing::Coupon` — `DISCOUNT_TYPES`, `DURATIONS`; validations; `redeemable?` (active && (max_redemptions nil || times_redeemed < max) && (redeem_by nil || redeem_by.future?)); `discount_for(amount_cents)` → cents (percent or fixed, clamped to amount); `redeem!` (increment times_redeemed).
- `Billing::Subscription` — `include TenantScoped`; `STATUSES=%w[trialing active past_due paused cancelled expired]`; `LIVE_STATUSES=%w[trialing active past_due paused]`; `belongs_to :plan` (class_name "Billing::Plan", fk billing_plan_id), `belongs_to :coupon` optional, `has_many :invoices`; validations (`customer_id` presence, status inclusion, amount_cents); scopes `live`, `due_for_renewal` (`live.where("current_period_end <= ?", now)`), `trial_ending(days)`; state methods: `mark_active!`, `mark_past_due!`, `mark_cancelled!(at:)`, `mark_expired!`, `start_trial!`, `advance_period!` (sets period_start=old end, period_end=`period_end_from(start)` by interval — month/year add), `period_end_from(t)`.
- `Billing::Invoice` — `include TenantScoped`; `STATUSES=%w[draft open paid void uncollectible]`; `belongs_to :subscription`, `has_many :line_items` (dependent destroy), `belongs_to :coupon` optional; scopes `collectible` (`where(status:"open").where("due_at <= ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)", now, now)`); `recompute_totals!` (subtotal = sum of subscription/proration line items, discount = sum discount line items (negative→positive bucket), tax, total = subtotal - discount + tax); state: `finalize!`, `mark_paid!(payment: nil)`, `void!`, `mark_uncollectible!`, `schedule_retry!(at:)` (increment attempt_count, set next_attempt_at). `number` assigned in finalize via `Billing::InvoiceNumber.generate(customer_id:)` (`INV-<cid>-<zero-padded seq>` — seq = count for customer + 1).
- `Billing::InvoiceLineItem` — `include TenantScoped`; `KINDS=%w[subscription proration discount tax]`; `belongs_to :invoice`; validations.
- `Billing::Settings` — single global row; `self.current` = `first_or_create!` with defaults; `COLLECTION_MODES=%w[manual gateway]`; helpers `manual?`/`gateway?`, `dunning_offsets` (parsed array default `[1,3,7]`).

**Tests (Phase 1):** model specs for each — validations, `Coupon#discount_for` (percent & fixed & clamp), `Coupon#redeemable?` edge cases, `Subscription#advance_period!` month/year math, `Invoice#recompute_totals!`, `InvoiceNumber` sequence uniqueness, partial-unique-index enforcement (two live subscriptions for same customer raises). Commit after each model+spec passes.

---

## Phase 2 — Activities + Contracts + Proration + Collector (backend slice, after Phase 1)

- `Billing::Proration.credit_and_charge(subscription:, new_plan:, at:)` → returns `[{description, amount_cents, kind:"proration"}...]`: unused fraction of current period on old plan as **negative** credit line, prorated remainder on new plan as positive charge. Fraction = `(period_end - at) / (period_end - period_start)`. Pure, fully unit-tested (mid-cycle, start, end boundaries).
- `Contracts::Subscribe` (Reform): `plan_code` presence + must resolve to active plan; optional `coupon_code` must be redeemable. `Contracts::ChangePlan`: `plan_code`. `Contracts::Plan`/`Contracts::Coupon`/`Contracts::Settings`: validate platform CRUD inputs (mirror plan/coupon/settings columns + inclusions).
- `Activities::Subscribe.call(customer:, plan:, coupon: nil)` → creates `Billing::Subscription`; if `plan.trial_days > 0` sets `trialing`, `trial_end = now + trial_days.days`, period = now..trial_end, no immediate invoice; else `active`, period = now..plan.period_end, then `GenerateInvoice` + `FinalizeInvoice` + `CollectInvoice`. Snapshots `amount_cents`/`interval`. Attaches coupon + `coupon.redeem!`.
- `Activities::ChangePlan.call(subscription:, new_plan:)` → snapshot new amount/interval, build proration invoice (GenerateInvoice with `Proration` line items + Finalize + Collect), update subscription plan.
- `Activities::CancelSubscription.call(subscription:, immediately: false)` → if immediately: `mark_cancelled!(at: now)`, `VoidInvoice` open invoices, notify; else `update!(cancel_at_period_end: true)`.
- `Activities::ResumeSubscription` (clears cancel_at_period_end / unpauses) and `PauseSubscription` (`status: paused`).
- `Activities::GenerateInvoice.call(subscription:, period_start:, period_end:, extra_line_items: [])` → draft invoice + subscription line item (`unit_amount_cents = subscription.amount_cents`) + extras.
- `Activities::FinalizeInvoice.call(invoice:)` → apply coupon discount line (if subscription.coupon redeemable & within duration), apply tax line (`subtotal * tax_rate_bps / 10000`), `recompute_totals!`, assign number, `status: open`, `issued_at: now`, `due_at: now + grace? (immediate due)`, `Notifier.invoice_issued`. Zero-total invoices auto-`mark_paid!`.
- `Activities::CollectInvoice.call(invoice:)` → `Billing::Collector.collect(invoice)`; success → `MarkInvoicePaid` + `Notifier.payment_succeeded`; failure → `schedule_retry!` + `Notifier.payment_failed`.
- `Activities::MarkInvoicePaid.call(invoice:, payment: nil)`, `VoidInvoice.call(invoice:)`, `ApplyCoupon.call(subscription:, coupon:)`.
- `Billing::Collector.collect(invoice)` → reads `Billing::Settings.current.collection_mode`. `:manual` → returns `{status: :pending_manual}` (invoice stays open). `:gateway` → resolve **platform owner customer (81721200)** merchant account for `settings.gateway_provider`, create `Payments::Payment`, call `Payments::Gateway.charge(...)`, map result to `{status: :succeeded|:failed, payment:}`. Gateway calls mocked in specs.

**Tests (Phase 2):** activity specs (subscribe with/without trial, change-plan proration totals, cancel immediate vs period-end, finalize coupon+tax math, zero-total auto-pay, collect success/failure paths), proration unit spec, collector spec (manual no-op + gateway success/failure with mocked `Payments::Gateway`), contract specs.

---

## Phase 3 — Cron + Job + Notifier + Mailer (backend slice, after Phase 2)

- `Billing::Cron::RenewSubscriptions.perform` — `Subscription.unscoped_by_tenant.due_for_renewal.find_each`; set `Current.customer`; if `cancel_at_period_end` → `mark_expired!` + notify cancelled; elsif `trialing` & trial ended → `mark_active!`, `advance_period!`, generate+finalize+collect first paid invoice; else (`active`) → `advance_period!`, generate+finalize+collect next invoice. Per-row rescue + log (mirror `Payments::Cron::ChargeDueSubscriptions`).
- `Billing::Cron::CollectDueInvoices.perform` — `Invoice.unscoped_by_tenant.collectible.find_each` → set Current.customer → `CollectInvoice`.
- `Billing::Cron::Dunning.perform` — invoices `open` with `attempt_count > 0` and `next_attempt_at <= now`: retry `CollectInvoice`; when `attempt_count` exceeds `dunning_offsets.size` → `mark_uncollectible!`, `subscription.mark_past_due!`, then after grace `mark_cancelled!`; notify `subscription_past_due`. Schedule next attempt from `dunning_offsets`.
- `Billing::Cron::TrialEndingNotices.perform` — `Subscription.unscoped_by_tenant.trial_ending(settings.trial_ending_notice_days)` → `Notifier.trial_ending`.
- `app/jobs/billing/daily_billing_job.rb` — `perform` calls the four crons in order, each guarded so one failing cron doesn't abort the rest.
- `config/recurring.yml` — add under `production:` (and a `development:` block if present pattern) `billing_daily: { class: "Billing::DailyBillingJob", queue: default, schedule: "every day at 3am" }`.
- `Billing::Notifier` — `invoice_issued/payment_succeeded/payment_failed/trial_ending/subscription_cancelled/subscription_past_due` → `BillingMailer.<event>(...).deliver_later`. `BillingMailer` + minimal ERB templates per event (recipient = customer admin email; degrade gracefully if none).

**Tests (Phase 3):** cron specs with travel_to — renewal generates invoice & advances period; trial→active transition; dunning escalation increments attempt_count → uncollectible → past_due → cancelled; trial-ending selects correct subscriptions; job orchestration calls all four; notifier enqueues mailer (ActiveJob/Mailer test helpers). Multi-tenant: crons set Current.customer per row and don't leak.

---

## Phase 4 — Routes + Controllers (security slice, parallel-capable after Phase 1 models exist)

**Routes** (`config/routes.rb`):
- Area (b), inside `namespace :settings { namespace :modules ... }`: add
  ```ruby
  namespace :billing do
    resource  :subscription, only: %i[show edit update], controller: "subscriptions"
    resource  :cancellation, only: %i[create destroy]
    resource  :coupon_redemption, only: :create
  end
  ```
- Area (a), inside `namespace :modules`: add
  ```ruby
  namespace :billing do
    resources :invoices, only: %i[index show] do
      member { get :download }
    end
    resource :subscription, only: :show, controller: "subscriptions"
  end
  ```
- Area (d), inside platform `scope :module_settings, as: :module_settings`: add
  ```ruby
  namespace :billing, module: "maintenance/platform/billing" do
    resources :plans
    resources :coupons
    resources :subscriptions, only: %i[index show] do
      resource :cancellation, only: :create
    end
    resources :invoices, only: %i[index show] do
      member { post :mark_paid; post :void; post :retry }
    end
    resource :settings, only: %i[show edit update]
  end
  ```

**Controllers:** base controllers set `dashboard_menu_item` and inherit `RouteAuthorization` guards (admin/owner for a&b by path; owner-only for d via `/platform/`). Every record action in a/b asserts `record.customer_id == current_customer_id` (tenant ownership) before acting; cross-tenant → 404/redirect. Platform controllers operate `unscoped_by_tenant`. Strong params per contract. Customer subscription update/change-plan/cancel call the corresponding `Billing::Activities::*`.

**Tests (Phase 4 — request specs, QA slice):** tenant isolation (customer A `GET` B's invoice → blocked); authorization (member → admin/settings billing blocked; non-owner → platform billing blocked; owner under 81721200 allowed); happy-path subscribe/change/cancel; platform mark_paid/void/retry.

---

## Phase 5 — ViewComponents + ERB + Stimulus (frontend slice, after routes/controllers stub exist)

Build each surface as `Billing::Admin::*Component` (Tailwind only, responsive, Stimulus only where interactive), each with a component spec:
- `PlanPickerComponent` (plan cards + select), `SubscriptionSummaryComponent` (status badge, next renewal, actions), `InvoiceTableComponent`, `InvoiceDetailComponent` (line items + totals, printable), `PlanFormComponent`, `CouponFormComponent`, `SettingsFormComponent` (collection mode toggles gateway_provider via Stimulus), `SubscriptionsTableComponent`. Match existing admin layout/styling (reference `Payments::Admin::MerchantAccountFormComponent`).

**Tests (Phase 5):** component specs render expected content/states (trial badge, past_due badge, zero-state, totals formatting).

---

## Phase 6 — Feature Module Registration + Provisioner (backend slice)

- `FeatureModules::Billing::Registration < FeatureModules::BaseModule` — `module_key "billing"`, name/description; `provision!`→`Provisioner.call`; `deprovision!`→`Provisioner.revoke`; `sidebar_contributions` with entries (Invoices, Subscription → area a paths) and settings (Subscription/Plan → area b path), `permitted_by: :admin_or_owner?`; `entries_for` for invoices listing.
- `FeatureModules::Billing::Provisioner.call(customer)` — `Billing::Settings.current`; if `Billing::Plan.default_plan` present → `Activities::Subscribe.call(customer:, plan: default_plan)` (idempotent: skip if a live subscription already exists). `revoke(customer)` — cancel live subscription immediately + void open invoices.
- Confirm module auto-registers via the existing initializer that loads `FeatureModules::*::Registration` (follow Payments).

**Tests (Phase 6):** provisioner subscribes to default plan / no-op without default plan; revoke cancels + voids; idempotency.

---

## Phase 7 — QA sweep (qa slice)

Full RSpec for billing (`bundle exec rspec spec/models/billing spec/services/billing spec/jobs/billing spec/components/billing spec/requests/admin/.../billing spec/mailers/billing_mailer_spec.rb`). Emphasis: multi-tenant isolation, authorization matrix (member/admin/owner × area a/b/d), proration & dunning math. Honour stale-test policy.

## Phase 8 — Release smoke + parallel review

- **anysys-release-engineer:** rspec on touched files, rebuild assets (`rm -f public/assets/.manifest.json`), restart `SKIP_AUTH=1 bin/rails server`, smoke-hit platform plans index, customer subscription page, customer invoices.
- **Parallel review:** anysys-tech-lead (AGENTS.md conventions: 4 URL areas, tenant scoping, ViewComponent/Tailwind/Stimulus purity, thin models, Trailblazer convention) + anysys-code-reviewer (correctness/security: mass-assignment, missing customer_id scoping, missing auth guards, proration/dunning edge cases, N+1).

---

## Self-Review

- **Spec coverage:** plans✓(P1,P5,P6) subscriptions✓(P1,P2) invoices+items✓(P1,P2) coupons✓(P1,P2) proration✓(P2) trials✓(P2,P3) recurring job✓(P3) dunning✓(P3) collection✓(P2) self-service✓(P4,P5) platform admin✓(P4,P5) notifications✓(P3) authz/tenancy✓(P4,P7). All 13 in-scope items mapped.
- **Type consistency:** state methods (`mark_active!`, `mark_past_due!`, `mark_cancelled!`, `mark_expired!`, `advance_period!`, `recompute_totals!`, `finalize!`, `mark_paid!`, `void!`, `mark_uncollectible!`, `schedule_retry!`, `redeem!`, `redeemable?`, `discount_for`) defined once in P1, referenced consistently in P2/P3. Collection modes `manual|gateway`, statuses, kinds consistent across phases.
- **No placeholders.** Money always cents. Platform owner customer `81721200` used for gateway collection.

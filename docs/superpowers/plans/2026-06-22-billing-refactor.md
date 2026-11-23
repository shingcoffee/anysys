# Billing Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is sized for one anysys-* SDLC sub-agent; tasks within a phase marked **[parallel]** have no inter-dependencies and may be dispatched together.

**Goal:** Make billing a non-modular, always-on subsystem with platform-configurable countable items + per-plan limits + dual (USD/CNY) pricing, an enforced quota system, and a redesigned customer billing settings area with plan comparison and discoverable payment-method setup.

**Architecture:** Delete billing's FeatureModule registration and provision it instead from `Customer after_create`. Replace the free-form `Plan#features` JSON with a DB-backed countable-items catalog (`Billing::CountableItem`) driven by a code registry, structured `Billing::PlanLimit` rows, and dual price columns. A `Billing::Quota` service reads the customer's live-subscription plan limits and is enforced at each resource create path. Customer surfaces consolidate under first-class `/admin/settings/billing`; platform config under first-class `/admin/maintenance/platform/billing`.

**Tech Stack:** Rails 8.1, Trailblazer Activity + Reform, ViewComponent, Tailwind, Stimulus, RSpec. Multi-tenant via `TenantScoped` (`Current.customer`).

---

## File Structure

### New files
- `app/services/billing/countable/registry.rb` — code source of truth for what can be counted
- `app/services/billing/countable/item_definition.rb` — value object (key, default_label, counter)
- `app/models/billing/countable_item.rb` — platform-global catalog row
- `app/models/billing/plan_limit.rb` — per-plan limit row
- `app/services/billing/currency_resolver.rb` — locale → currency
- `app/services/billing/quota.rb` — usage/limit/allow? per customer
- `app/services/billing/quota/guard.rb` — raises/returns over-limit result for create paths
- `app/services/billing/onboarding.rb` — subscribe-to-default on customer create (replaces provisioner)
- `db/migrate/*` — see Task 1
- Platform controllers under `app/controllers/admin/maintenance/platform/billing/` (countable_items, plan_limits in addition to existing plans/coupons/subscriptions/invoices/settings)
- Customer controllers under `app/controllers/admin/settings/billing/` (subscriptions, payment_methods, invoices, base)
- `app/components/billing/admin/plan_comparison_component.rb` (+ template, spec, Stimulus)
- `app/components/billing/admin/billing_settings_nav_component.rb` (+ template)

### Deleted files
- `app/services/feature_modules/billing/registration.rb`
- `app/services/feature_modules/billing/provisioner.rb`
- old customer controllers under `app/controllers/admin/settings/modules/billing/` and `app/controllers/admin/modules/billing/`
- old platform controllers under `app/controllers/admin/maintenance/platform/billing/` are **moved** namespace (route module changes), not deleted

### Modified files
- `app/models/billing/plan.rb`, `billing/subscription.rb`, `billing/settings.rb`
- `app/services/billing/standard_plans.rb`
- `app/services/billing/collector.rb`, `billing/activities/subscribe.rb`, `billing/cron/renew_subscriptions.rb` (currency snapshot)
- `app/models/customer.rb` (after_create onboarding)
- `app/services/maintenance_contributor.rb`, `app/services/settings_contributor.rb`
- `config/routes.rb`
- create-path controllers: `admin/maintenance/flowcharts_controller.rb`, `pages_controller.rb`, `entities_controller.rb`, `authentication/registrations_controller.rb`

---

## Phase 1 — Data layer & domain services (foundation; build first)

### Task 1: Migrations [backend]

**Files:**
- Create: `db/migrate/<ts>_create_billing_countable_items.rb`
- Create: `db/migrate/<ts>_create_billing_plan_limits.rb`
- Create: `db/migrate/<ts>_dual_currency_billing_plans.rb`
- Create: `db/migrate/<ts>_add_currency_to_billing_subscriptions.rb`
- Create: `db/migrate/<ts>_drop_currency_from_billing_settings.rb`
- Create: `db/migrate/<ts>_remove_billing_feature_module.rb` (data migration)

- [ ] `billing_countable_items`: `key:string null:false`, `label:string null:false`, `enabled:boolean default:false null:false`, `position:integer default:0 null:false`, timestamps; unique index on `key`. (No `customer_id` — platform-global.)
- [ ] `billing_plan_limits`: `billing_plan_id:references null:false index`, `item_key:string null:false`, `limit_value:integer null:false default:-1`, timestamps; unique index on `[billing_plan_id, item_key]`.
- [ ] `billing_plans`: `add_column :amount_usd_cents, :integer, null: false, default: 0`; `add_column :amount_cny_cents, :integer, null: false, default: 0`; `remove_column :amount_cents`; `remove_column :currency`; `remove_column :features`.
- [ ] `billing_subscriptions`: `add_column :currency, :string, null: false, default: "USD"`.
- [ ] `billing_settings`: `remove_column :currency`.
- [ ] Data migration: delete the `FeatureModules::Module` row with `key: "billing"` and its `FeatureModules::CustomerAssignment` rows (guarded `find_by`), so the modules toggle no longer lists billing.
- [ ] Run `bin/rails db:migrate` and confirm `schema.rb` updates. Commit.

### Task 2: Countable registry + item definition [backend]

**Files:**
- Create: `app/services/billing/countable/item_definition.rb`
- Create: `app/services/billing/countable/registry.rb`
- Test: `spec/services/billing/countable/registry_spec.rb`

Interface:
```ruby
# item_definition.rb
module Billing
  module Countable
    ItemDefinition = Struct.new(:key, :default_label, :counter, keyword_init: true) do
      def count_for(customer) = counter.call(customer)
    end
  end
end

# registry.rb
module Billing
  module Countable
    module Registry
      module_function

      def all
        @all ||= [
          ItemDefinition.new(key: "flowchart", default_label: "Flowcharts",
            counter: ->(c) { Flowchart.for_customer(c.id).count }),
          ItemDefinition.new(key: "page", default_label: "Pages",
            counter: ->(c) { Page.for_customer(c.id).count }),
          ItemDefinition.new(key: "entity", default_label: "Entities",
            counter: ->(c) { Entity.for_customer(c.id).count }),
          ItemDefinition.new(key: "member", default_label: "Members",
            counter: ->(c) { Authentication::User.where(customer_id: c.id).count })
        ]
      end

      def keys = all.map(&:key)
      def find(key) = all.find { |d| d.key == key.to_s }
      def count_for(key, customer) = find(key)&.count_for(customer)
    end
  end
end
```
(Storage intentionally omitted — the app has no general file-storage resource today; add later if one appears.)

- [ ] Spec: `keys` returns the four keys; `count_for("flowchart", customer)` reflects created records; unknown key returns nil; multi-tenant — customer A's count excludes customer B's records. Commit.

### Task 3: CountableItem model + catalog sync [backend]

**Files:**
- Create: `app/models/billing/countable_item.rb`
- Test: `spec/models/billing/countable_item_spec.rb`

```ruby
module Billing
  class CountableItem < ApplicationRecord
    self.table_name = "billing_countable_items"
    validates :key, presence: true, uniqueness: true
    validates :label, presence: true
    scope :enabled, -> { where(enabled: true) }
    scope :ordered, -> { order(:position, :key) }

    # Idempotently ensure a row exists for every registry key. Returns ordered enabled+disabled rows.
    def self.sync_from_registry!
      Billing::Countable::Registry.all.each_with_index do |defn, i|
        item = find_or_initialize_by(key: defn.key)
        item.label = defn.default_label if item.label.blank?
        item.position = i if item.new_record?
        item.save!
      end
      ordered
    end

    def usage_for(customer) = Billing::Countable::Registry.count_for(key, customer)
  end
end
```

- [ ] Spec: `sync_from_registry!` is idempotent (running twice creates 4 rows once); preserves owner-edited label; `enabled` scope filters. Commit.

### Task 4: PlanLimit model + Plan refactor (dual price, limits, drop features) [backend]

**Files:**
- Create: `app/models/billing/plan_limit.rb`
- Modify: `app/models/billing/plan.rb`
- Test: `spec/models/billing/plan_limit_spec.rb`, update `spec/models/billing/plan_spec.rb`

```ruby
# plan_limit.rb
module Billing
  class PlanLimit < ApplicationRecord
    self.table_name = "billing_plan_limits"
    belongs_to :plan, class_name: "Billing::Plan", foreign_key: :billing_plan_id
    validates :item_key, presence: true,
      uniqueness: { scope: :billing_plan_id }
    validates :limit_value, numericality: { only_integer: true, greater_than_or_equal_to: -1 }
    UNLIMITED = -1
    def unlimited? = limit_value == UNLIMITED
  end
end
```
Plan changes:
- [ ] `has_many :plan_limits, class_name: "Billing::PlanLimit", foreign_key: :billing_plan_id, dependent: :destroy`
- [ ] Remove `features` usage. Add:
```ruby
def price_cents_for(currency)
  currency.to_s.upcase == "CNY" ? amount_cny_cents : amount_usd_cents
end

def limit_for(item_key)
  pl = plan_limits.find { |l| l.item_key == item_key.to_s }
  pl ? pl.limit_value : Billing::PlanLimit::UNLIMITED # missing = unlimited (fail-open)
end

def free? = amount_usd_cents.zero? && amount_cny_cents.zero?
```
- [ ] Specs: `price_cents_for("USD"/"CNY")`; `limit_for` returns row value or -1 when missing; `free?`. Update existing plan spec to drop `features`/`amount_cents`/`currency`. Commit.

### Task 5: CurrencyResolver [backend]

**Files:**
- Create: `app/services/billing/currency_resolver.rb`
- Test: `spec/services/billing/currency_resolver_spec.rb`

```ruby
module Billing
  module CurrencyResolver
    SYMBOLS = { "USD" => "$", "CNY" => "¥" }.freeze
    module_function

    def for_locale(locale)
      locale.to_s.downcase.start_with?("zh") ? "CNY" : "USD"
    end

    def for_customer(customer)
      for_locale(customer.try(:locale) || I18n.locale)
    end

    def symbol(currency) = SYMBOLS[currency.to_s.upcase] || currency.to_s

    # cents -> "$9.99" / "¥99.00"
    def format(cents, currency)
      "#{symbol(currency)}#{'%.2f' % (cents.to_f / 100)}"
    end
  end
end
```
- [ ] Spec: `for_locale("zh-CN") == "CNY"`, `for_locale("en") == "USD"`; `format(99900,"CNY") == "¥999.00"`; `symbol`. Confirm `Customer` has a `locale` attribute — if not, fall back to `I18n.locale` only (verify during build). Commit.

### Task 6: Quota service + guard [backend]

**Files:**
- Create: `app/services/billing/quota.rb`
- Create: `app/services/billing/quota/guard.rb`
- Test: `spec/services/billing/quota_spec.rb`

```ruby
# quota.rb
module Billing
  class Quota
    PLATFORM_OWNER_CUSTOMER_ID = 81_721_200

    def self.for(customer) = new(customer)
    def initialize(customer) = (@customer = customer)

    def plan
      @plan ||= Billing::Subscription.unscoped_by_tenant
        .where(customer_id: @customer.id).live.order(created_at: :desc).first&.plan
    end

    def limit(item_key)
      return Billing::PlanLimit::UNLIMITED if bypass?
      plan ? plan.limit_for(item_key) : Billing::PlanLimit::UNLIMITED
    end

    def usage(item_key) = Billing::Countable::Registry.count_for(item_key, @customer).to_i
    def unlimited?(item_key) = limit(item_key) == Billing::PlanLimit::UNLIMITED
    def remaining(item_key)
      return Float::INFINITY if unlimited?(item_key)
      [limit(item_key) - usage(item_key), 0].max
    end
    def allow?(item_key, by: 1)
      return true if unlimited?(item_key)
      usage(item_key) + by <= limit(item_key)
    end

    private

    def bypass? = @customer.id == PLATFORM_OWNER_CUSTOMER_ID
  end
end
```
```ruby
# quota/guard.rb — used inside create actions
module Billing
  class Quota
    module Guard
      Result = Struct.new(:allowed, :item_key, :limit, :label, keyword_init: true) do
        def allowed? = allowed
        def message
          "You've reached your plan's limit of #{limit} #{label}. Upgrade your plan to add more."
        end
      end

      def self.check(customer:, item_key:)
        q = Billing::Quota.for(customer)
        item = Billing::CountableItem.find_by(key: item_key.to_s)
        allowed = !item&.enabled? ? true : q.allow?(item_key)
        Result.new(allowed: allowed, item_key: item_key.to_s,
                   limit: q.limit(item_key),
                   label: (item&.label || item_key.to_s.humanize.downcase))
      end
    end
  end
end
```
- [ ] Spec: under-limit allows; at-limit blocks; unlimited (-1) bypasses; platform owner bypasses; disabled CountableItem ⇒ allowed (not enforced); multi-tenant — A's usage doesn't affect B's `remaining`. Commit.

### Task 7: StandardPlans seeder rewrite + Onboarding service [backend]

**Files:**
- Modify: `app/services/billing/standard_plans.rb`
- Create: `app/services/billing/onboarding.rb`
- Test: update `spec/services/billing/standard_plans_spec.rb`, create `spec/services/billing/onboarding_spec.rb`

- [ ] `StandardPlans.call!`: first `Billing::CountableItem.sync_from_registry!` then enable the default set (`flowchart,page,entity,member` enabled). Recreate the catalog with dual prices + `plan_limits` rows instead of `features`. Example free plan: `amount_usd_cents: 0, amount_cny_cents: 0`, limits `{flowchart: 3, page: 10, entity: 5, member: 1}`; starter: usd 2900/cny 29900 (`$29` / `¥299`) monthly with higher limits; pro: usd 9900/cny 99900; enterprise: all `-1`. Keep `is_default` on free, `interval`, `trial_days`. (Set sensible USD prices; CNY from existing catalog.)
- [ ] `Billing::Onboarding.call(customer)`: port provisioner logic — ensure `Billing::Settings.current`; if a default plan exists and customer has no live subscription, `Current.customer = customer; Billing::Activities::Subscribe.call(customer:, plan: default)`. Idempotent.
- [ ] Specs: seeder is idempotent and creates plan_limits + countable items; Onboarding subscribes once, skips when a live sub exists. Commit.

---

## Phase 2 — De-modularization (depends on Phase 1: Onboarding)

### Task 8: Remove billing FeatureModule, wire onboarding into Customer [backend + security]

**Files:**
- Delete: `app/services/feature_modules/billing/registration.rb`, `app/services/feature_modules/billing/provisioner.rb`
- Modify: `app/models/customer.rb`
- Test: update `spec/models/customer_spec.rb`; delete/migrate any `spec/services/feature_modules/billing/*` specs (stale-test policy: rewrite to target `Billing::Onboarding`).

- [ ] Delete the two files. (Auto-discovery globs `registration.rb`; removing it stops `register!`, so billing leaves the modules toggle. The Task 1 data migration removes the stale DB row.)
- [ ] In `Customer`, add `after_create :run_billing_onboarding` (after `enable_required_feature_modules`), private method `def run_billing_onboarding = Billing::Onboarding.call(self)`.
- [ ] Add backfill: a one-off rake task `lib/tasks/billing_backfill.rake` (`billing:backfill_subscriptions`) iterating `Customer.find_each { Billing::Onboarding.call(_1) }`; run it once. (Idempotent.)
- [ ] Spec: creating a Customer subscribes it to the default plan; no billing row appears in `FeatureModules::Module.available`. Commit.

---

## Phase 3 — Routes & controllers reorg (depends on Phase 1)

### Task 9: Routes reorganization [security]

**Files:** Modify `config/routes.rb`

- [ ] **Customer** — remove the `namespace :billing` block under `settings/modules` (lines ~176-181) and the `namespace :modules { namespace :billing }` block (lines ~408-414). Add a first-class block inside `namespace :admin`:
```ruby
namespace :settings do
  namespace :billing do
    resource  :subscription,      only: %i[show update], controller: "subscriptions"
    resource  :cancellation,      only: %i[create destroy]
    resource  :coupon_redemption, only: :create
    resources :payment_methods,   only: %i[index create destroy] do
      member { patch :make_default }
    end
    resources :invoices, only: %i[index show] do
      member { get :download }
    end
  end
end
```
- [ ] **Platform** — move the billing block out of `scope :module_settings` to a sibling under `scope "platform", as: :platform`:
```ruby
namespace :billing, module: "maintenance/platform/billing" do
  resources :plans
  resource  :countable_items, only: %i[show update], controller: "countable_items"
  resource  :plan_limits,     only: %i[show update], controller: "plan_limits"
  resources :coupons
  resources :subscriptions, only: %i[index show] do
    resource :cancellation, only: :create
  end
  resources :invoices, only: %i[index show] do
    member { post :mark_paid; post :void; post :retry }
  end
  resource :settings, only: %i[show edit update]
  resource :standard_plans, only: :create
end
```
- [ ] `bin/rails routes | grep billing` shows new paths; old `settings/modules/billing` + `modules/billing` paths gone. Commit.

### Task 10: Customer billing controllers (consolidated) [security]

**Files:**
- Create: `app/controllers/admin/settings/billing/base_controller.rb` (inherits the admin settings base; `require_admin_or_owner!`; sets a billing-settings layout/active-tab)
- Create: `subscriptions_controller.rb`, `payment_methods_controller.rb`, `invoices_controller.rb`, `cancellations_controller.rb`, `coupon_redemptions_controller.rb` under `app/controllers/admin/settings/billing/`
- Delete: old controllers under `app/controllers/admin/settings/modules/billing/` and `app/controllers/admin/modules/billing/`
- Test: request specs `spec/requests/admin/settings/billing/*_spec.rb`

- [ ] Port logic from the old controllers (subscribe/change/cancel/coupon/payment-method/invoices) to new namespace. Every action: tenant-scoped (`Current.customer`), `require_admin_or_owner!`. Subscriptions `#update` resolves currency via `CurrencyResolver.for_customer` and passes to Subscribe/ChangePlan.
- [ ] Request specs: admin can view/switch plan, list/show invoices, add/remove/make-default payment method; member is forbidden; cross-tenant access blocked; old URLs 404. Commit.

### Task 11: Platform billing controllers (move + 2 new) [security]

**Files:**
- Modify (move namespace `module:` only): existing `app/controllers/admin/maintenance/platform/billing/*` keep working under new route module
- Create: `countable_items_controller.rb` (show/update — toggle enabled, edit labels, reorder), `plan_limits_controller.rb` (show grid / bulk update limit_value per plan×item)
- Modify: `plans_controller.rb` strong params → `amount_usd_cents`, `amount_cny_cents` (drop `amount_cents`, `currency`, `features`)
- Test: request specs under `spec/requests/admin/maintenance/platform/billing/`

- [ ] All actions gated platform-owner-only (reuse existing `base_controller.rb` RouteAuthorization). `countable_items#update` accepts nested attrs `[{key, label, enabled, position}]`; `plan_limits#update` accepts `limits[plan_id][item_key] = value` and upserts `Billing::PlanLimit` rows (`-1`/blank ⇒ unlimited).
- [ ] Request specs: non-owner (admin of 81721200? no — only owner) and other-tenant blocked; owner can toggle items, set grid limits, edit dual prices. Commit.

---

## Phase 4 — UI (depends on Phases 1 & 3) [parallel within, all frontend]

### Task 12: Customer billing settings nav + layout + Subscription compare grid [frontend]

**Files:**
- Modify: `app/services/settings_contributor.rb` (add first-class "Billing" SidebarNode w/ children Subscription Plan / Payment Method / Invoices, paths `/#{cid}/admin/settings/billing/{subscription,payment_methods,invoices}`; remove the old module-contributed billing settings entry — handled by Task 8 deletion)
- Create: `app/components/billing/admin/billing_settings_nav_component.rb` (+ erb) — responsive tab nav
- Create/Replace: `app/components/billing/admin/plan_comparison_component.rb` (+ erb, + `spec`, + Stimulus `billing_plan_compare_controller.js` for confirm-on-switch)
- Create: `app/views/admin/settings/billing/subscriptions/show.html.erb`
- Delete: old `app/views/admin/settings/modules/billing/*`, `app/views/admin/modules/billing/*`, and obsolete `plan_table_component`/`plan_picker_component` (fold into comparison)
- Test: `spec/components/billing/admin/plan_comparison_component_spec.rb`

- [ ] Comparison grid: columns = active plans (localized price via `CurrencyResolver.for_customer` + `format`), rows = enabled `CountableItem` limits (render `∞` for -1) + features; current plan highlighted with status badge; CTA per plan (Current / Switch / Subscribe); coupon form + cancel inline. Tailwind responsive (cards stack on mobile, table/grid on md+).
- [ ] Component spec: renders one column per active plan, localized symbol for zh vs en, `∞` for unlimited, highlights current plan. Commit.

### Task 13: Payment Method tab (discoverable setup) [frontend]

**Files:**
- Create: `app/views/admin/settings/billing/payment_methods/index.html.erb`
- Modify/Create: `app/components/billing/admin/payment_method_component.rb` (+ erb, spec)
- Test: component spec

- [ ] List active mandates (provider label, default badge, authorized date); "Set up payment" lists available Payments gateways (active merchant accounts under 81721200 via existing `Billing::AvailableProviders`) and authorizes a recurring mandate; add / remove / make-default; empty-state CTA that links from the Subscription tab ("Add a payment method to subscribe"). Responsive. No raw card fields.
- [ ] Component spec: empty state CTA; renders active method with default badge. Commit.

### Task 14: Invoices tab [frontend]

**Files:**
- Create: `app/views/admin/settings/billing/invoices/{index,show}.html.erb`
- Reuse/refresh invoice components; localized currency via `CurrencyResolver`
- Test: component spec if a new component is added

- [ ] Index lists invoices (number, status badge, localized total, due/issued dates, download); show renders line items in invoice currency. Responsive table → stacked cards on mobile. Commit.

### Task 15: Platform "Billings" nav + config screens [frontend]

**Files:**
- Modify: `app/services/maintenance_contributor.rb` (add `leaf("Billing", "/#{customer_id}/admin/maintenance/platform/billing/plans", ICONS[:billing])` in the platform section; add a `billing` icon)
- Create: `app/views/admin/maintenance/platform/billing/countable_items/show.html.erb` (enable/label/reorder list)
- Create: `app/views/admin/maintenance/platform/billing/plan_limits/show.html.erb` (plans × enabled-items grid of limit inputs; blank/-1 = unlimited)
- Modify: `app/views/admin/maintenance/platform/billing/plans/_form.html.erb` (dual price fields USD + CNY; remove features/currency)
- Modify any platform billing index/nav that linked to old `module_settings` paths
- Test: component/request coverage via Task 11 specs; add a small Stimulus controller if the grid needs add-row behavior (Tailwind/Stimulus only)

- [ ] Countable-items screen: toggle `enabled`, edit `label`, set `position`. Plan-limits grid: one input per plan×enabled-item; saving upserts PlanLimit. Plans form: USD + CNY price inputs. All responsive, consistent admin styling. Commit.

---

## Phase 5 — Enforcement (depends on Phase 1: Quota) [parallel, security/backend]

### Task 16: Wire quota guard into create paths [security]

**Files (each independent):**
- Modify: `app/controllers/admin/maintenance/flowcharts_controller.rb#create` (item_key `"flowchart"`)
- Modify: `app/controllers/admin/maintenance/pages_controller.rb#create` (`"page"`)
- Modify: `app/controllers/admin/maintenance/entities_controller.rb#create` (`"entity"`)
- Modify: `app/controllers/authentication/registrations_controller.rb#create` (`"member"`)
- Test: request specs per controller

Pattern (insert before `.save`):
```ruby
guard = Billing::Quota::Guard.check(customer: current_customer, item_key: "flowchart")
unless guard.allowed?
  flash.now[:alert] = guard.message
  @flowchart.errors.add(:base, guard.message)
  return render :new, status: :unprocessable_entity
end
```
For the JSON/registration paths, return the message as a 422 with `{ error: guard.message }` (member signup: render `:new` with the flash). Member uses `current_customer` from the signup context.

- [ ] Per-path request specs: create allowed under limit; blocked with friendly message at limit; unlimited plan bypasses; platform-owner bypasses; **multi-tenant** — customer A at limit does not block customer B. Commit each path separately.

---

## Phase 6 — QA, release, review

### Task 17: QA sweep [anysys-qa-engineer]
- [ ] Fill gaps: subscription currency snapshot through renew/collect; CountableItem sync idempotency under concurrency; coupon + dual price interaction; authorization matrix for all new routes (owner/admin/member/cross-tenant). Run touched-layer specs green.

### Task 18: Release smoke [anysys-release-engineer]
- [ ] `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server`; smoke `/81721200/admin/maintenance/platform/billing/plans`, `/81721200/admin/settings/billing/subscription`, plan switch, payment-method setup, an over-limit create. Rebuild assets. Report PASS/FAIL.

### Task 19: Parallel review [anysys-tech-lead + anysys-code-reviewer]
- [ ] Tech-lead: AGENTS.md conventions — three URL categories (billing now `/admin/settings/...` + `/admin/maintenance/platform/...`, not module areas), tenant scoping, ViewComponent/Tailwind/Stimulus purity, thin models. Code-reviewer: correctness/security — mass-assignment on new params, missing guards, N+1 in comparison grid, enforcement bypass holes.

---

## Self-Review notes
- **Spec coverage:** de-modularize → T1(data),T8; platform config a/b/c → T3,T4,T11,T15; customer 3-tab redesign + compare → T9,T10,T12,T13,T14; dual currency locale → T5,T4,T12,T14; enforcement → T6,T16. All spec sections mapped.
- **Type consistency:** `limit_for`/`limit`/`PlanLimit::UNLIMITED`, `price_cents_for(currency)`, `CurrencyResolver.format`, `Quota::Guard.check`/`Result#message` used consistently across tasks.
- **Open verification during build:** confirm `Customer#locale` exists (T5 fallback noted); confirm `Flowchart.for_customer` scope name (Explore confirmed `for_customer`).

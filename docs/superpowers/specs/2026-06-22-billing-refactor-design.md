# Billing Refactor — Design

**Date:** 2026-06-22
**Status:** Approved scope, ready for planning
**Supersedes parts of:** `2026-06-21-platform-billing-design.md`, `2026-06-21-billing-payment-methods-design.md`, `2026-06-21-payment-settings-card-gateways-design.md`

## Problem

The billing system shipped 2026-06-21 has three structural problems the platform owner wants fixed:

1. **Billing is implemented as an optional FeatureModule** (registration + provisioner + Maintenance/Modules toggle). Billing is core platform infrastructure and must apply to *every* customer — it should not be toggleable like SMS or Captcha.
2. **Platform-owner configuration lives under `/module_settings/billing`** and exposes a free-form `features` JSON with no structured notion of "what can be limited." The owner wants to (a) define which app resources count toward plan limits, (b) set per-plan limits for those items, and (c) control pricing currency (USD + RMB only).
3. **The customer billing experience is poor**: scattered across `/admin/modules/billing` and `/admin/settings/modules/billing`, there is *no discoverable place to set up payment*, and plans are not presented for comparison.

## Decisions (locked)

- **Countable items:** DB-backed catalog, **auto-discovered** from real countable resources via a registry. Owner enables / labels / orders.
- **Limits:** **enforced** — over-limit creation is blocked, not merely displayed.
- **Currency:** **per-plan dual pricing** (USD + CNY). Customer sees the price in **their locale's** currency.
- **Payment collection:** **gateway mandate via the Payments module** (no raw card fields stored by us; card-capable gateways like Stripe drop in via the single-file gateway rule).

## Architecture

### Part 1 — De-modularize billing

Billing stops being a `FeatureModules` registration entirely.

- **Delete** `FeatureModules::Billing::Registration` and `FeatureModules::Billing::Provisioner`. Remove the `register!` wiring so billing no longer appears in `FeatureModules::Module`, the **Maintenance / Modules** toggle, or the modules sidebar contributor.
- **Auto-subscribe on customer creation:** move the provisioner's "ensure settings + subscribe to default plan if no live subscription" logic into a `Billing::Onboarding.call(customer)` service invoked from the customer-creation path (alongside / replacing `enable_required_feature_modules` participation). Idempotent. A boot-time/backfill task subscribes any existing customer lacking a live subscription.
- Billing can never be deprovisioned; the revoke path is removed.

### Part 2 — Route reorganization (no backward-compat shims)

| Surface | Old path | New path |
|---|---|---|
| Customer subscription | `/admin/settings/modules/billing/subscription` | `/admin/settings/billing/subscription` |
| Customer payment method | `/admin/settings/modules/billing/payment_method` | `/admin/settings/billing/payment_methods` |
| Customer invoices | `/admin/modules/billing/invoices` | `/admin/settings/billing/invoices` |
| Customer subscription (read entry) | `/admin/modules/billing/subscription` | removed (folded into settings) |
| Platform config | `/admin/maintenance/platform/module_settings/billing/*` | `/admin/maintenance/platform/billing/*` |

All customer surfaces consolidate under a single first-class **`/admin/settings/billing`** area (not under `settings/modules`, since billing is no longer a module). Platform config becomes a first-class **"Billings"** sub-section directly under the PLATFORM maintenance area (not under `module_settings`). All keep their existing `require_admin_or_owner!` / platform-owner guards.

Sidebar/nav: remove billing's module-sidebar contributions; add a static **Billing** settings nav entry (admin) and a **Billings** entry in the PLATFORM maintenance nav (platform owner only).

### Part 3 — Countable items catalog (platform config a)

New platform-global model **`Billing::CountableItem`** (no `customer_id` — platform-wide config):

| Field | Type | Notes |
|---|---|---|
| `key` | string | matches a registry key, e.g. `"flowchart"` |
| `label` | string | owner-editable display label |
| `enabled` | boolean | whether this item participates in plan limits |
| `position` | integer | display order |

**`Billing::Countable::Registry`** — code-side source of truth for *what can be counted*. Each entry declares:
- `key` (stable string)
- `default_label`
- `count_for(customer)` — returns the customer's current usage (e.g. `Flowchart.where(customer_id:).count`; storage returns MB).

Auto-discovery seeds a `CountableItem` row per registry key on first access (idempotent), defaulting `enabled: false` except a sensible starter set. The owner's edit screen lists every registry-backed item with enable toggle + label + order. Initial registry candidates: **flowchart, page, entity, member, storage_mb** (exact set + counters confirmed during planning against real models).

### Part 4 — Per-plan limits (platform config b)

New model **`Billing::PlanLimit`**: `billing_plan_id`, `item_key`, `limit_value` (integer; `-1` = unlimited). Unique on `(billing_plan_id, item_key)`. Replaces `Billing::Plan#features`.

- A missing row for an enabled item = **unlimited** (fail-open; the editor always renders a cell so the owner sets it explicitly).
- Platform plans editor renders a **grid**: rows = plans, columns = enabled countable items, cells = limit inputs (blank/`-1` = unlimited).

### Part 5 — Currency / dual pricing (platform config c)

- `billing_plans`: **add** `amount_usd_cents`, `amount_cny_cents`; **drop** `amount_cents`, `currency`, `features`.
- **Drop** `Billing::Settings#currency`.
- **Locale → currency** helper: `zh` / `zh-CN` (and other `zh-*`) → `CNY` (¥); everything else → `USD` ($). One small `Billing::CurrencyResolver.for(customer_or_locale)`.
- `Billing::Plan#price_cents_for(currency)` and `#display_price(currency)`.
- **Invoices** keep their `currency` + `total_cents` columns as a **snapshot** taken at issue time from the customer's resolved currency. The whole subscription lifecycle (subscribe, renew, collect) resolves currency once at subscribe time and stores it on the subscription so renewals stay consistent — add `currency` to `billing_subscriptions` (snapshot of the currency chosen at subscribe).

### Part 6 — Customer billing settings redesign

Single `/admin/settings/billing` area with a shared layout + 3-tab sub-nav (**Subscription Plan / Payment Method / Invoices**), fully responsive (mobile → desktop).

- **Subscription Plan** — **compare-mode** grid. Every active plan side-by-side as columns; rows = enabled countable-item limits + key features; localized price per plan; current plan highlighted with status; per-plan CTA (Subscribe / Switch / Current / Cancel). Coupon redemption inline. Confirm dialog on plan change.
- **Payment Method** — discoverable setup. Lists active mandate(s) with provider label, default badge, authorized date; "Set up payment" authorizes a recurring mandate through an **available Payments gateway** (filtered to active merchant accounts under platform owner 81721200). Add / remove / set-default. No raw card fields — the gateway handles capture.
- **Invoices** — list / show / download (PDF/HTML), localized currency, status badges.

ViewComponents: a `Billing::Admin::PlanComparisonComponent` (replaces/extends the old `PlanTableComponent`/`PlanPickerComponent`), a billing-settings tab-nav component, refreshed payment-method + invoice components. Tailwind only, Stimulus only.

### Part 7 — Enforcement

New **`Billing::Quota`**: `Billing::Quota.for(customer)` exposes:
- `limit(item_key)` → resolved limit from the customer's live subscription's plan (`-1`/missing = unlimited).
- `usage(item_key)` → `Registry.count_for(customer)`.
- `allow?(item_key, by: 1)` → `unlimited? || usage + by <= limit`.
- `remaining(item_key)`.

Wire a guard into each countable resource's **create path**. Preferred: a reusable Trailblazer step / contract validation (`Billing::Quota::Guard`) added to each create Activity, falling back to a controller `before_action` where no Activity exists. Over-limit ⇒ friendly error ("You've reached your plan's limit of N {items}. Upgrade to add more.") linking to the compare grid; surfaced as a flash + 422 for HTML and JSON-aware for API/JS create paths.

**Blast radius:** flowchart, page, entity, member creation (+ storage on upload). Exact create-paths enumerated in the plan; each gets multi-tenant + over/under-limit spec coverage. Platform owner (81721200) and any unlimited plan bypass cleanly.

## Data / migration summary

- **New:** `billing_countable_items` (`key`, `label`, `enabled`, `position`), `billing_plan_limits` (`billing_plan_id`, `item_key`, `limit_value`, unique `[plan,item]`).
- **Alter `billing_plans`:** add `amount_usd_cents`, `amount_cny_cents`; drop `amount_cents`, `currency`, `features`.
- **Alter `billing_subscriptions`:** add `currency` (snapshot).
- **Alter `billing_settings`:** drop `currency`.
- **Rewrite `Billing::StandardPlans`** seeder: dual prices, structured `PlanLimit` rows, seed the countable-items catalog.

## Testing strategy

- **Model/contract:** CountableItem, PlanLimit (uniqueness, unlimited semantics), Plan dual-price + `price_cents_for`, CurrencyResolver, Quota (`allow?`/`remaining` at, under, over, unlimited).
- **Activity:** Subscribe/ChangePlan currency snapshot; Onboarding idempotency.
- **Enforcement request specs:** each create path — allowed under limit, blocked at limit, unlimited bypass, platform-owner bypass, **multi-tenant isolation** (customer A's usage never affects B).
- **Component:** PlanComparisonComponent renders limits + localized price + current-plan highlight; payment-method states.
- **Request/authorization:** new platform routes are platform-owner-only; new customer routes are admin-or-owner and tenant-scoped; old routes 404.
- **System:** customer can compare plans, switch plan, set up a payment method, view an invoice; platform owner can configure items, the limits grid, and dual prices.

## Out of scope

- Adding a new card PSP (Stripe) gateway implementation — the mandate flow is gateway-agnostic and a card gateway drops in later via the single-file rule.
- Proration redesign, tax engine changes, dunning schedule changes — unchanged from current behavior.
- Migrating historical `features`/`amount_cents` data — per AGENTS.md this is treated as a brand-new app (re-seed standard plans).

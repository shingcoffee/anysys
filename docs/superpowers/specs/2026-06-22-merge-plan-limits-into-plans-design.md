# Merge Plan Limits into Plans CRUD + Sidebar Billing Active

Date: 2026-06-22
Status: Approved

## Summary

On the platform billing plans area
(`/:cid/admin/maintenance/platform/billing/plans`), fold the separate **Plan
Limits** grid into the plans CRUD:

- **List (index)** shows each plan's per-item limits as read-only columns
  alongside pricing.
- **Show (view)** displays the limits alongside pricing/metadata.
- **Edit & New** are a single page with two sections — *Plan details &
  pricing* and *Plan limits* — submitted together.
- The standalone **Plan Limits** page, controller, route, component, and
  billing-nav tab are removed (fully merged). The Countable Items registry page
  stays.

Plus a nav fix: selecting **any** billing tab keeps the **Billing** item under
the sidebar's PLATFORM section active.

No schema change. Brand-new app — no backward-compatibility constraints.

## Data & persistence

- Limits remain `Billing::PlanLimit(billing_plan_id, item_key, limit_value)`
  where `limit_value == -1` (`Billing::PlanLimit::UNLIMITED`) means unlimited.
  Joined to `Billing::CountableItem.key` (the enabled registry items:
  flowchart, page, entity, member).
- New service **`Billing::AssignPlanLimits.call(plan:, limits:)`** — for each
  `{ item_key => raw_value }`, finds-or-initializes the `PlanLimit` for
  `(plan, item_key)` and upserts `limit_value`. Parse rule (moved from the
  deleted `PlanLimitsController`): blank, `-1`, or `"unlimited"`
  (case-insensitive) → `UNLIMITED`; otherwise `to_i`. Only item_keys belonging
  to enabled countable items are accepted. Shared by create and update.

## List (index) — `Billing::Admin::PlanTableComponent`

- Add one read-only column per **enabled** countable item, in
  `CountableItem.enabled.ordered` order. Each cell shows the plan's limit value
  or **∞** (unlimited). Existing pricing/status/action columns remain.
- `PlansController#index` loads `@items = Billing::CountableItem.enabled.ordered`
  and `@plans = Billing::Plan.ordered.includes(:plan_limits)` (no N+1).
- The component takes `items:` in addition to `plans:`/`customer_id:` and renders
  limit cells via `plan.limit_for(item.key)` (returns `UNLIMITED` when absent).

## Show (view) — `plans/show.html.erb`

- Add a "Plan Limits" card/section listing each enabled item → its value
  (∞ for unlimited), alongside the existing pricing/metadata `dl`.
- `PlansController#show` loads `@items = Billing::CountableItem.enabled.ordered`.

## Edit & New (single page) — `Billing::Admin::PlanFormComponent`

- One `form_with` with two sections:
  1. *Plan details & pricing* — existing fields (code, name, description,
     amount_usd_cents, amount_cny_cents, interval, trial_days, position, active,
     is_default).
  2. *Plan limits* — a number input per enabled countable item, named
     `billing_plan[limits][<item_key>]`, pre-filled with the current limit
     (blank when unlimited; placeholder shows ∞).
- The component takes `items:` in addition to `plan:`/`customer_id:`.
- `PlansController`:
  - `plan_params` unchanged for the contract; add a separate `limit_params`
    that permits `billing_plan: { limits: {} }` (or `params.dig(:billing_plan,
    :limits)`).
  - `create`: validate+save the plan via `Billing::Contracts::Plan`; on success
    call `Billing::AssignPlanLimits.call(plan: @plan, limits: submitted_limits)`.
  - `update`: same — save plan, then assign limits.
  - Both wrap plan save + limit assignment so a limits failure surfaces as an
    error (re-render the form). Limits are validated by `PlanLimit` numericality
    (`>= -1`).

## Remove the standalone Plan Limits surface

- Delete:
  - `app/controllers/admin/maintenance/platform/billing/plan_limits_controller.rb`
  - `app/views/admin/maintenance/platform/billing/plan_limits/show.html.erb`
  - `app/components/billing/admin/plan_limits_form_component.{rb,html.erb}`
  - the `resource :plan_limits, ...` route
  - the `:plan_limits` tab entry in `Billing::Admin::PlatformBillingNavComponent::TABS`
- Keep `CountableItem` model, the Countable Items page, and `Plan#limit_for`.

## Sidebar Billing active across billing tabs

- Root cause: `SidebarNodeComponent#active?` is an exact match
  (`current_path == node.path`); the Billing leaf path is `…/billing/plans`, so
  other billing tabs don't activate it.
- Add an opt-in `match_prefix` attribute to `SidebarNode` (default nil), plumbed
  through `MaintenanceContributor#leaf`. Set it on the Billing leaf to
  `/#{customer_id}/admin/maintenance/platform/billing`.
- Update `SidebarNodeComponent#active?` (and the private `child_active?`):
  active when `current_path == node.path`, OR (`node.match_prefix` present AND
  (`current_path == node.match_prefix` OR
  `current_path.start_with?("#{node.match_prefix}/")`)). The `+ "/"` boundary
  prevents false positives (e.g. `modules` vs `module_settings`). Every other
  node keeps exact-match behavior.

## Authorization & Multi-tenancy

- All surfaces stay under `/:cid/admin/maintenance/platform/billing/...`,
  owner-only via the existing `RouteAuthorization` platform gate (customer
  81721200). Plans/limits/countable items are global records (no customer_id) by
  design — unchanged.

## Testing

- **Service**: `AssignPlanLimits` — upsert new, update existing, blank/-1/
  "unlimited" → UNLIMITED, ignores unknown/disabled item_keys.
- **Request**: `create`/`update` persist both pricing and limits; `index` and
  `show` render the limit columns/values (∞ for unlimited); owner-only auth and
  the platform-owner constraint preserved.
- **Component**: `PlanTableComponent` renders one column per enabled item + ∞;
  `PlanFormComponent` renders a limit input per item pre-filled correctly;
  `SidebarNodeComponent` Billing active on `/billing/plans` AND
  `/billing/coupons`, and a non-billing node is not over-activated.
- Remove/rewrite the stale `plan_limits` specs per the stale-test policy.

## Out of scope

- Inline-editing limits directly in the list (configuration is via Edit).
- Changes to how limits are enforced at runtime (`Billing::Quota`).
- Countable Items registry behavior.

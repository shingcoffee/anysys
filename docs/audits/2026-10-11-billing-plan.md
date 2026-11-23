# Billing repair implementation plan — 2026-10-11

## Mandate and evidence boundary

This is an implementation handoff, based on reading `AGENTS.md`, the current route declarations, billing models/services/controllers/components, Payments integrations, schema, scheduler, and locale files. Production application files and data were not changed. No Rails process, provider request, test, or subagent was launched. This document and the adjacent route-audit manifest are planning artifacts, not runtime verification.

Baseline Git revision: `91b89d3e`. The shared working tree was initially clean and changed concurrently during inspection. Later reads found payment/authentication hardening and a companion `docs/audits/2026-10-11-billing-ux.md` written by other work. Their files were not modified by this coordinator. Source line anchors below describe the inspected snapshot; implementation must re-read the current working tree rather than overwrite it from this plan.

**Concrete concurrent integration dependency:** `Payments::Activities::PrepareAttempt` now records `_attempt` merchant/amount/currency/operation context on `Payments::Payment`; Query/provider error taxonomy and webhook account binding are also being hardened. Reuse that committed payment identity alongside the billing attempt ledger, not a second independent PSP request identity. `Payments::Subscription#billing_owned?` currently anticipates `metadata["billing_owned"]`, but schema has no such column. Freeze **one authority: the typed managed_by column below**, and have B adapt the helper/cron to it after the current payment-file owner hands off. Do not add both JSON marker and managed_by as competing state. Preserve incoming signature-account IDs, uncertain-error classification, and monotonic payment/subscription transitions.

The companion UX document is useful for existing component mount chains, layout reuse, and accessibility. This plan supersedes its descriptions of old billing policy: cadence choices become schedulable, unpaid manual upgrades wait for settlement, coupons count redemption-relative eligible cycles, grace is snapshotted, and pending changes can be cancelled safely. Section 7's endpoints/results are the implementation contract; reconcile the companion's proposed `/retry`, `/confirm_setup`, `review_plan_code`, and `contract:` names with those below before frontend work. Do not ship its accurate descriptions of current defects as the desired future behavior.

The broader request is an exhaustive application route audit, excluding the flowchart builder and maintenance-page builder. `2026-10-11-route-audit-manifest.md` inventories every route-declaration area and defines the remaining audit work. Billing and its payment dependencies received source-level behavioral inspection here; other route families are inventoried, not certified functional.

**Delivery objective:** trustworthy platform subscription billing, with persisted intent, one collection owner, immutable issued invoices, working Stripe/Alipay authorization, finite fallback entitlements, complete tenant/owner surfaces, and truthful localized feedback. Retain the current first-class billing namespaces; billing is not a FeatureModule.

## 1. Verified defects and their implementation owners

Paths below are relative to the repository root. “A/B/C/F” refer to the four exclusive file partitions in section 8.

| Finding | Current evidence | Required correction | Owner |
| --- | --- | --- | --- |
| Authorization response disappears | `app/services/billing/activities/set_up_payment_method.rb:71,88` discards `Payments::Gateway.subscribe`; controller redirects without a provider action | Return and render a typed authorization action; persist correlation before provider interaction | B, C, F |
| No agreement-to-billing activation | `app/services/payments/activities/handle_webhook.rb:277` only handles trade notifications, not agreement notifications; Stripe setup backfill at `:430` only changes the Payments token | Verified agreement/setup callbacks activate the exact billing method and mandate, idempotently | B |
| Stripe unavailable despite recurring implementation | `app/services/billing/available_providers.rb:43` requires `:billing_agreements`; Stripe declares `:recurring, :tokenized_cards` and implements `charge_subscription` | Recurring AND (agreement OR tokenized-card) capability check, with an implemented setup adapter | B |
| Availability/currency gates disagree | AvailableProviders ignores `Payments::PlatformGateway`; `Payments::EligibleGateways` honors it. Alipay collector rejects non-CNY, but setup/picker have no currency filter | Reuse EligibleGateways for the platform customer's configured current-mode account and currency; keep subscription currency stable | B, C |
| Display currency can drift | settings subscriptions controller `assign_show` resolves customer locale even when the live subscription already has a currency | Use live subscription currency everywhere; locale only chooses the currency at initial enrollment | C |
| Upgrade intent lost; unpaid resubmits duplicate invoices | `activities/change_plan.rb` keeps `new_plan` only in the stack frame; every pending/failed resubmit builds another invoice | Persist one open PlanChange; stable request and invoice keys; settlement applies its snapshot once | A, B |
| Manual mode grants an unpaid upgrade | `ChangePlan.plan_change_collected?` accepts `:pending_manual` | Immediate paid upgrades require invoice settlement in every collection mode | A |
| Daily cron starves retry exhaustion | CollectDueInvoices selects retries before Dunning; CollectInvoice moves `next_attempt_at` on each failure | Disjoint initial/retry/reconciliation populations; centralized attempt completion and exhaustion | B |
| Transport ambiguity can create another charge | Collector rescues every error as failed; any ApiError from stalled query is interpreted as “unknown trade” | Preserve an ambiguous attempt and its key; query/replay it; only explicit provider not-found/terminal failure permits a new attempt | B |
| Pending/SCA records cannot reliably reconcile | Collector sees `pending` and returns without querying; pending result handling does not explicitly store `psp_transaction_id` | Persist provider reference for all outcomes and reconcile pending/ambiguous attempts; expose SCA recovery | B, C, F |
| Second recurring engine can charge billing mandates | `payments/cron/charge_due_subscriptions.rb` selects every active due Payments subscription; billing uses the same model | Persist mandate `managed_by = billing`; exclude it in both general cron selection and claim | B |
| Cancellation/no subscription grants unlimited access | `billing/quota.rb:17` returns UNLIMITED without a live plan; paused/past_due plans remain eligible indefinitely | Entitlements resolve to finite free limits when pending, ended, paused, or past grace; read-only access and billing recovery remain available | A |
| Claimed quotas are partly fictitious | Registry includes storage/support counters returning zero, `member` counts all users; code search finds guards only for page/entity/member | Publish/enforce core quotas honestly; count member-role users, provide explicit free limits, disable unsupported catalog entries | A, C, F |
| Cadence switch rejected | `contracts/change_plan.rb:15,26` requires same interval; UI offers yearly alternatives | Same-cadence upgrades now; downgrades/equal-price/cadence changes next renewal | A, C, F |
| Coupon duration uses unrelated history | ApplyCoupon rejects once after any invoice; FinalizeInvoice counts all historical/proration/void invoices | Redemption-specific cycle tracking starting at attachment, excluding free/proration cycles | A, B |
| Finalization repeats and renumbers | FinalizeInvoice has no draft guard/transaction; Invoice#finalize! writes open and a new number regardless of status | Atomic one-time finalization, snapshot discount/tax, preserve lines/number/timestamps on repeats | B |
| Invoice count numbering is not a sequence | `billing/invoice_number.rb:22` counts all already-created drafts; two drafts can propose the same number forever; deletion also reuses counts | Durable per-customer sequence allocation with database uniqueness and short transactions | B; schema A |
| Overdue settlement cannot recover subscription | MarkInvoicePaid only changes invoice; refuses uncollectible invoices; webhook billing settlement swallows failure | One idempotent settlement path including recoverable overdue invoices and A's subscription hook | B, A |
| Removal does not terminate local mandate | RemovePaymentMethod calls gateway cancellation but never updates Payments::Subscription; gateway methods only return status | Local charge prohibition committed first; durable provider revocation retries; late auth cannot reactivate removed method | B |
| Catalog deletion breaks history | Plans controller only protects live references; Coupons controller destroys unconditionally; billing FKs mostly absent | Archive catalog entries; protect every historical/pending reference with associations and FKs; keep snapshots | A, C, F |
| Contract errors/values disappear | CRUD controllers set `@contract`; Plan/Coupon/Settings components and views render the AR model and model errors | Carry the submitted contract/form through 422 render, including limits and field errors | A/B contracts, C, F |
| Pagination is a hard truncation | Invoice and subscription lists use `.limit(100)` | Pagy-backed lists with deterministic ordering and shared admin footer | C, F |
| Settings promise a nonexistent provider selection | Settings contract requires `gateway_provider` but Collector uses each tenant's default method and current settings rather than invoice mode | Remove dead global provider field; snapshot policy on invoice issue; explicit retry/mode-transition commands | B; schema A; C, F |
| Notices repeat or precede committed changes | Trial notices have no receipt; callers enqueue inside transactions; settlement can notify repeatedly | Transactional notice/outbox records with stable event keys; deliver after commit | B |

## 2. Product rules to implement

### Currency, catalog, and enrollment

* Initial enrollment supports **USD and CNY only**. Default from CurrencyResolver once, then store on the subscription. No currency migration or implicit FX when locale/provider changes. Alipay is available only for CNY; Stripe uses its declared currency support.
* Preserve platform account ownership: orders, charges, gateway credentials, and recurring mandates belong to customer **81721200**. Billing subscriptions, invoices, methods, changes, and redemptions belong to the purchasing customer. Never expose platform Payments records directly to tenant/member controllers.
* The default/fallback plan must be active, non-archived, zero-priced in both currencies, no trial, and finite for all enabled **enforceable** countable items. Keep existing free seed limits page=10, entity=5, member=1. Missing free limit means **0**, never unlimited. A missing/invalid fallback configuration also means zero new capacity, with a platform configuration error; no GET-side seeding.
* Initially publish page/entity/member quotas only. Existing page/entity guards are reused. Correct member counting to member-role users and ensure admin user creation only consumes this quota when the created user is a member. Other keys must not be presented as enforced entitlements until their authoritative write paths and counters are wired. In particular, storage/support are not “0 usage” production features.
* Paid plan terms are snapshotted on enrollment/change: plan code/name, price, currency, cadence, and limits. Catalog edits affect new enrollments/changes, not existing invoices or silently increase/decrease a customer's purchased limits. New countable keys missing from an old snapshot use a documented conservative value of 0 until explicitly assigned.
* Archive is the normal catalog removal operation (`archived_at`, `active=false`). Existing subscriptions and pending accepted changes retain their snapshots. Do not hard-delete referenced plans/coupons, or turn off the last valid free default. One database-unique default plan.
* Free initial enrollment settles a zero invoice through the ordinary settlement hook and becomes active. A positive-price non-trial initial enrollment is **pending** until paid, including manual mode; it has free fallback entitlements. Extend the live-row unique predicate to include pending.
* Initial invoice dates are fixed at acceptance, not silently rewritten at late payment. Payment within its snapshotted due-date grace grants the remaining accepted period; an unpaid initial request expires at that deadline. A capture after expiry is recorded and flagged for owner reconciliation, not used to resurrect the request. The review displays when service billing begins.
* A trial grants snapshotted trial entitlements until trial_end. Grant a customer's trial at most once (`trial_used_at`), so cancel/resubscribe cannot renew trials indefinitely. Moving from onboarding's free plan to a paid plan is not a new trial in this slice; display that rule accurately.

### Changes, renewal, cancellation, and access

| Request | Effective time | Invoice/entitlement rule |
| --- | --- | --- |
| Same cadence, strictly higher recurring price | Immediately after proration settles | Persist awaiting_payment change; retain current plan until paid; stable positive proration invoice |
| Same cadence, lower/equal recurring price | Next renewal | Persist scheduled change at existing period end; no mid-period credit/refund |
| Monthly ↔ yearly, any price | Next renewal | Persist scheduled change; new interval starts at existing period end; no cross-cadence proration |
| Trial plan change | Next trial end | Schedule target, preserve original trial end, no unused paid-time credit |
| Same plan | No-op | Return unchanged; never generate another invoice |
| Request while past_due/paused/pending | Reject except resolving existing request | Settle/recover first; no new credit on unpaid periods |
| Cancellation scheduled | At current period end | Stop future renewal; cancel safely cancellable pending/scheduled changes; keep paid access to boundary |
| Resume scheduled cancellation | Before boundary | Clear cancellation only; never reinstate a previously cancelled change automatically |
| Immediate owner cancellation | Now | End entitlements; keep genuine debt/history; do not automatically void every open invoice |

Define upgrade by current-currency price for matching cadences, not catalog position. Same-price feature swaps are scheduled; no hand-built tier inference. Reject changes while `cancel_at_period_end` is set; customer resumes first.

One pending/scheduled change per subscription. A repeated request key or same target returns the existing change/invoice. A different target while a change exists returns `pending_change_exists`; explicitly cancel the existing change first. A terminal request key can never be reused for a new charge.

Renewal prepares the **next period invoice without advancing the subscription first**. Its snapshot selects the accepted scheduled target, or the current terms. Advance `current_period_start/end`, apply target terms, clear debt state, and mark the change applied only in settlement. Unpaid recurring renewal does not repeatedly generate new periods/invoices. Anchor arithmetic uses Rails calendar durations, preserves the original day-of-month/end-of-month intent, and resets the anchor on an accepted cadence change.

At the boundary, an unpaid immediate change with no live/ambiguous provider attempt expires and its invoice is safely voided, then renewal uses the old plan. A truly in-flight immediate change is reconciled before generating renewal: do not create a conflicting old-plan renewal invoice. Bound this hold to the normal period-end grace window. Success during that hold applies the stored target, then renewal is prepared from the original boundary; no past service is retroactively granted. At grace expiry end the subscription and flag any later capture for owner reconciliation/refund through the existing Payments refund support. Never silently drop a captured payment or revive an explicitly ended subscription.

Access is computed independently of whether cron ran on time:

* active: purchased snapshot through period end; renewal grace after that boundary;
* trialing: trial snapshot through trial end, then bounded renewal grace;
* past_due renewal: prior purchased snapshot only through the immutable due-date grace deadline;
* pending initial, paused, cancelled, expired, no live subscription, or grace expired: finite free fallback;
* an unpaid **proration** never makes an otherwise paid subscription past_due;
* platform customer 81721200 retains the existing quota bypass. Owning a platform account does not grant unlimited quotas to every tenant URL.

Fallback does not delete data or block reads, account/security, invoice access, authorization, or payment recovery. Over-limit tenants can read/delete existing resources; capped creates are denied. Repairing payment alone does not re-enable an ended subscription: reenrollment is explicit and must not create conflicting live rows.

### Coupons and invoice terms

* Redeem once per subscription in this slice, including after free onboarding invoices. Serialize inventory reservation; repeated attachment of the same code is idempotent. Once means the **next eligible billed cycle after redemption**, not the subscription's first historical invoice.
* Snapshot coupon terms at redemption. `active`, `redeem_by`, and max inventory gate **new** redemption only; archival or expiry does not retroactively revoke accepted discounts.
* An eligible cycle is an initial/renewal invoice with **positive pre-discount recurring subtotal**. Free-price invoices and proration invoices do not consume duration. A 100%-discount billed cycle does consume one cycle and settles at zero. No proration coupon in this slice; explain it in the UI/docs.
* Consume a cycle atomically at finalization with a recorded `coupon_cycle_number`. Repeated finalization/retry never consumes again. Void does not refund coupon inventory/cycles; a future correction workflow must explicitly reuse a cycle rather than minting another benefit.
* Fixed coupons require an explicit supported currency; no blank “same cents in any currency.” Use integer minor-unit discount math, Money for currency boundaries/formatting, and BigDecimal/Rational for time proration. Clamp discount to non-negative recurring subtotal, then apply tax to the discounted amount. No floating-point monetary calculations.
* Finalized invoice lines, plan/coupon/tax policy, currency, amount, issued_at, due_at, and number are immutable. Payment/retry/void transitions do not renumber or recompute them.

## 3. Persistence contract and migration ownership

**A is the only migration/schema author.** B submits all provider/collection column needs against this contract before A writes migrations. C/F never create schema changes. Use Rails 8.1 migrations, SQLite-compatible JSON, partial unique indexes and atomic compare-and-set updates. Do not rely on PostgreSQL sequences, JSONB, SKIP LOCKED, or `with_lock` alone for SQLite concurrency.

Reserve these new migration files (adjust only the timestamp if it conflicts, retaining sole ownership):

1. `db/migrate/20261011000100_add_billing_subscription_lifecycle.rb`
2. `db/migrate/20261011000200_add_billing_invoice_collection_state.rb`
3. `db/migrate/20261011000300_add_billing_payment_authorization_state.rb`
4. `db/migrate/20261011000400_enforce_billing_integrity.rb`

### 3.1 A domain schema

| Table | New columns / constraints |
| --- | --- |
| `customers` | `trial_used_at:datetime` nullable, set only when a paid-plan trial actually begins |
| `billing_plans`, `billing_coupons` | `archived_at:datetime`; plans unique partial index on `is_default` where true; validate default invariants in catalog service |
| `billing_subscriptions` | `request_key:string` with unique `(customer_id, request_key)` across historical and live rows; `plan_snapshot:json` not null `{}`; `billing_anchor_day:integer`, `billing_anchor_month:integer` for calendar cadence; include `pending` in live uniqueness; remove unused `payments_subscription_id` after verifying callers (Collector already uses PaymentMethod) |
| **new `billing_plan_changes`** | customer/subscription IDs; `from_plan_id`, `to_plan_id` (FK to plans); `request_key:string`; `kind:string` immediate/scheduled; `status:string` awaiting_payment/scheduled/applied/cancelled/expired; `effective_at:datetime`; `period_start/end:datetime` for source-period correlation; `from_snapshot`, `target_snapshot:json`; `applied_at`, `cancelled_at:datetime`; timestamps. Unique `(customer_id, request_key)`, unique partial subscription ID where status is awaiting_payment/scheduled. Target snapshot includes price/currency/interval/limits/code/name. |
| **new `billing_coupon_redemptions`** | customer/subscription/coupon IDs; `terms_snapshot:json`; `redeemed_at:datetime`; `cycles_used:integer` default 0; timestamps. Unique subscription ID; retain existing subscription coupon FK as convenient catalog association, not duration authority. |

No pending-target Ruby ivar/JSON-only note is the state authority: PlanChange is a tenant-scoped record with a constrained lifecycle and permanent request identity.

### 3.2 B domain schema, authored by A

| Table | New columns / constraints |
| --- | --- |
| `billing_invoices` | `purpose:string` initial/renewal/proration; `idempotency_key:string`; `billing_plan_change_id`, `billing_coupon_redemption_id:bigint` nullable; `coupon_cycle_number:integer`; `terms_snapshot:json` (plan name/code, amount, currency, interval, limits, tax bps, collection mode, retry day offsets, grace days); `collection_state:string` ready/manual/blocked/pending/requires_action/retry_wait/exhausted/settled/stopped; `first_failed_at`, `collection_claimed_at:datetime`; `failure_code:string`; `settlement_review_code:string` nullable for ended/stale/duplicate-capture anomalies; `settlement_source:string` gateway/manual/zero, `settled_by_id:bigint`, `settlement_reference:string`, `settlement_note:text` for settlement provenance; `collection_override_mode:string`, `collection_override_by_id:bigint`, `collection_override_at:datetime` for explicit owner authorization of outstanding collection. Existing attempt_count counts completed definitive failed attempts only. Unique `(customer_id, idempotency_key)`; unique plan-change ID for proration only (renewal may reference a scheduled change too); unique `(billing_coupon_redemption_id, coupon_cycle_number)` when cycle number present. |
| **new `billing_invoice_sequences`** | customer ID unique; `last_value:bigint` default 0; timestamps. Sequence is allocated on finalization, never from draft counts. |
| **new `billing_collection_attempts`** | customer/invoice IDs; `ordinal:integer`; `payment_id:bigint` nullable until prepared; `billing_payment_method_id:bigint`; `merchant_account_id:bigint`; `state:string` prepared/submitting/pending/requires_action/succeeded/failed/unknown; `request_key:string` unique; `failure_code:string`; `submitted_at`, `completed_at`, `reconcile_at`, `claimed_at:datetime`; timestamps. Unique `(billing_invoice_id, ordinal)`, unique payment ID when present, partial unique invoice ID for prepared/submitting/pending/requires_action/unknown. Do not persist client secrets in this table. |
| `billing_payment_methods` | `request_key:string` with unique `(customer_id, request_key)` including removed history; `merchant_account_id:bigint`; `authorized_by_id:bigint` nullable FK to authentication users; `authorization_reference:string` (SetupIntent ID or exact agreement external ref); `authorization_expires_at:datetime`; `requested_default:boolean` default false; `removed_at:datetime`; `revocation_state:string` none/pending/complete/failed; `revocation_next_attempt_at:datetime`; `revocation_attempt_count:integer` default 0; `failure_code:string`. Unique mandate link when present; authorization reference unique per merchant account when present. Retain existing unique active default index. Allow multiple historical/provider methods; no uniqueness solely on tenant/provider. |
| `payment_subscriptions` | `managed_by:string` not null default payments, billing for invoice-controlled mandates; ordinary due query AND atomic claim must enforce payments ownership. Billing mandates have `next_charge_at=NULL` even when authorized. |
| `payment_methods` | `billing_customer_id`, `billing_authorized_by_id:bigint` nullable; make `user_id` nullable only for platform-owned billing tokens; CHECK/application validation: ordinary tokens require user_id and no billing_customer_id; billing tokens require customer_id=81721200, billing_customer_id and billing_authorized_by_id, user_id NULL. Token still belongs to the platform account, not to the member vault of the authorizing tenant admin. |
| `billing_settings` | Remove `gateway_provider` (no runtime meaning). Keep collection_mode, tax_rate_bps, grace_period_days, trial_ending_notice_days, dunning_schedule. Strict increasing unique positive retry offsets; empty array means no retries, not silent fallback to defaults. |
| **new `billing_notices`** | customer ID; `event_key:string` unique; `kind:string`; `billing_invoice_id`, `billing_subscription_id`, `billing_collection_attempt_id:bigint` nullable as relevant; `state:string` pending/enqueued; `enqueued_at:datetime`; timestamps. Committed outbox, with retryable dispatch. Stable keys include invoice issued/paid, failed attempt ID, trial_end, subscription cancellation event. |

All tenant rows have customer_id and ordinary FKs. Validate agreement/token merchant account, provider, billing customer, and authorizing actor correspondence in B services; a FK by itself does not prove tenant ownership.

### 3.3 Integrity and preflight

* Add restrictive FKs for subscription→plan/coupon/customer, invoice→subscription/customer/coupon/change/redemption/payment, method→customer/mandate/account/actor, and new tables. Remove `dependent: :destroy` from historical billing subscription invoices; issued financial history cannot cascade from catalog/subscription deletion.
* Preserve existing number uniqueness and tenant live/default-method indexes. Add non-negative counters/amount checks and lifecycle-value checks where SQLite supports them.
* Explicit data migration/preflight is needed even though application backward-compatibility shims are out of scope: orphaned plan/coupon FKs, duplicate active/default rows, invoice numbers, unfinished charges, coupons, and cross-provider mandate links may already exist. Report conflicts; do not silently delete or manufacture financial history.
* Backfill snapshots from existing stored subscription amounts/currency/interval and current catalog, marking reconstructed historical facts in migration output. Invoice descriptions are already stored; do not rewrite them from today's plan. Unknown historical coupon consumption cannot be faithfully inferred from current counts: identify affected redemptions for a documented owner decision.
* Populate invoice sequence from the maximum valid existing numeric suffix per customer, **not invoice count**. Allocate future values above that maximum; gaps are acceptable. Preserve existing invoice numbers.
* Backfill managed_by from explicit Billing::PaymentMethod links; examine legacy billing-pm external refs as a report signal. Verify provider/method pairing before attaching. Historical broken links need review, not blanket reassignment.
* A alone owns regenerated `db/schema.rb` and an explicit dry-run/report repair task at `lib/tasks/billing_repair.rake`. It must default to reporting; any apply mode belongs to the later authorized implementation/deployment process, not this audit session. It must not call onboarding/seeding/provider APIs on inspection.

## 4. Stable interfaces — freeze before parallel implementation

Use the existing Rails/Reform/Trailblazer conventions. A owns `app/services/billing/result.rb`: a small immutable result object with `status`, `subscription`, `plan_change`, `invoice`, `payment_method`, `record`, `form`, `action`, `reason`, and `errors`; optional fields are nil, errors is a field-keyed map. `record` is the saved catalog/settings record, and `form` is the submitted Reform contract on form commands. This is a domain envelope, not a serialized AR response. B/C consume it. Unexpected exceptions propagate to normal logging/error handling; expected domain failures use stable reason codes with translated presentation.

### 4.1 A's commands and queries

```ruby
Billing::Activities::Subscribe.call(customer:, plan:, coupon: nil, request_key:)
# Result status: active / trialing / awaiting_payment / unchanged / invalid
# Find a previously accepted request_key before creating/reusing a live row;
# historical replays must never reenroll or recharge a cancelled request.

Billing::Activities::ChangePlan.call(subscription:, new_plan:, request_key:)
# Result status: applied / awaiting_payment / scheduled / unchanged / conflict / invalid
# Returns the permanent PlanChange and its existing invoice when applicable.

Billing::Activities::CancelPlanChange.call(subscription:, plan_change:)
# cancelled / conflict (in-flight attempt must reconcile before void/cancel)

Billing::Activities::CancelSubscription.call(subscription:, immediately: false)
Billing::Activities::ResumeSubscription.call(subscription:)
Billing::Activities::ApplyCoupon.call(subscription:, coupon:)
# Result; resume only undoes a scheduled cancellation, not overdue/ended debt state.

Billing::Renewal.prepare(subscription:, at: Time.current)
# Result: invoice_ready / not_due / blocked / ended.
# Builds/reuses next-period invoice using B's GenerateInvoice interface.
# No HTTP; no premature period advance or entitlement grant.

Billing::Activities::ApplyInvoiceSettlement.call(invoice:, paid_at:)
# Idempotent subscription/change mutation; called inside B settlement transaction.
# Returns Result: applied / recovered / unchanged / review_required.

Billing::Activities::RecordInvoiceDebt.call(invoice:, at:)
# Renewal only: sets past_due_at once from invoice.due_at; proration does not
# revoke a paid plan. No provider call and no retry scheduling here.

Billing::Activities::ExpireOverdueSubscription.call(subscription:, at:)
# Ends pending-initial or live-renewal subscription at its immutable deadline;
# cancels unresolved changes safely through B's cancellation interface.

Billing::Discounts.reserve_for_invoice!(invoice:)
# Called during draft finalization while holding subscription then invoice.
# Returns { redemption_id:, cycle_number:, discount_cents:, description_key:,
#           description_values: } or nil. Reserves the cycle exactly once;
# computes from invoice snapshot and eligible base recurring lines.

Billing::Entitlements.for(customer:, at: Time.current)
# source (:purchased/:trial/:grace/:free/:platform), plan_snapshot,
# expires_at, limits map. Reads only; no onboarding or singleton creation.
# Billing::Quota retains limit/usage/remaining/allow? and delegates plan selection.

Billing::PlanChangePolicy.preview(subscription:, new_plan:, at: Time.current)
# { kind:, effective_at:, currency:, subtotal_cents:, tax_cents:, total_cents:,
#   reason:, allowed: }. Authoritative pricing recomputed on accepted command;
# preview is not a client-authorized amount or a stale charge authorization.
```

Catalog commands owned by A: `Billing::Catalog::SavePlan.call(plan:, params:, limits:)`, `SaveCoupon.call(coupon:, params:)`, `ArchivePlan.call(plan:)`, `ArchiveCoupon.call(coupon:)`, and `UpdateCountableItems.call(items:)`. Save/update returns `Result(status: :saved/:invalid, record:, form:, errors:)`; archive returns `:archived/:unchanged/:invalid`. Plan and limits persist atomically. For default changes, clear the old flag and save the new valid free default in the same transaction before the unique index is checked; replace the current after_save clear-other-defaults callback. Countable updates reject enabling unsupported/unmetered keys and validate finite free limits for every newly enabled key. Code and cadence/price identity cannot be changed on referenced catalog entries in a way that alters accepted snapshots; create a new priced catalog offering when needed.

### 4.2 B's invoice/provider commands

```ruby
Billing::Activities::GenerateInvoice.call(
  subscription:, purpose:, idempotency_key:, period_start:, period_end:,
  terms_snapshot:, plan_change: nil, extra_line_items: []
)
# Billing::Invoice. Reuses existing identity without replacing frozen lines.
# initial/renewal add a base recurring line; proration uses extras only.
# Keys: initial:<subscription_id>, renewal:<subscription_id>:<boundary UTC>,
#       plan-change:<plan_change_id>. Never use wall-clock execution date.

Billing::Activities::FinalizeInvoice.call(invoice:)
# Billing::Invoice; non-draft => unchanged. Zero invoices use MarkInvoicePaid.

Billing::Activities::CollectInvoice.call(invoice:, trigger: :initial, at: Time.current)
# Result status: succeeded / pending / requires_action / pending_manual /
#               retry_scheduled / exhausted / skipped / blocked.
# trigger: initial, retry, recovery (explicit user/owner), reconcile.

Billing::Activities::MarkInvoicePaid.call(
  invoice:, payment: nil, source:, paid_at: Time.current,
  actor: nil, reference: nil, note: nil
)
# Result: paid / unchanged / review_required / invalid.
# source: gateway / manual / zero. Sole invoice→subscription settlement path.
# manual requires a platform-owner actor and nonblank settlement reference;
# it refuses unresolved/captured PSP attempts until reconciliation completes.

Billing::Activities::AuthorizeInvoiceCollection.call(invoice:, actor:, mode:, note:)
# Platform-owner-only override for outstanding manual/gateway collection.
# Preserves financial snapshot; blocked/invalid if an attempt is unresolved.

Billing::Activities::UpdateSettings.call(settings:, params:)
# Result: saved / invalid, with record/form/errors. Settings contract owns
# validation and submitted raw schedule display; controller does not save
# an incomplete global provider configuration or discard the failed form.

Billing::Activities::VoidInvoice.call(invoice:)
# Result: voided / unchanged / conflict. Refuse ambiguous/inflight/captured payment.

Billing::AvailableProviders.call(customer:, currency:)
# Provider descriptors: key, label_key, setup_kind (:redirect/:stripe_setup),
# supported_currencies. Excludes unsupported/disabled/unconfigured/current-mode
# mismatches. customer is the billing customer; credentials resolve on 81721200.

Billing::Activities::SetUpPaymentMethod.call(
  customer:, actor:, provider:, return_url:, request_key:
)
# Result: active / authorization_required / pending / invalid.
# action: { kind: :redirect, url: } OR
#         { kind: :provider_form, action_url:, method: "post", fields: } OR
#         { kind: :stripe_setup, publishable_key:, client_secret: } OR nil.
# Persist method/mandate/correlation first. return_url is server-generated.

Billing::PaymentAuthorization.confirm!(payment_method:, verified_event:)
# Only provider-verified callback/query evidence; no client supplied PSP token.

Billing::Activities::MakeDefaultPaymentMethod.call(customer:, payment_method:)
Billing::Activities::RemovePaymentMethod.call(payment_method:)
# Result. Remove prohibits charges now, even if PSP revocation needs retry.

Billing::InvoicePaymentAction.for(invoice:)
# nil or request-local action descriptor for the exact pending Stripe intent:
# { kind: :stripe_sca, publishable_key:, client_secret: }.
# Server-authorized controller invokes this; no secrets in list JSON/logs/URLs.
```

B owns a thin `Billing::Providers` adapter, backed by existing Payments gateway classes/facade and official Stripe gem. It normalizes setup/charge/query/revocation results and provider error codes. It does not add a vendor or duplicate protocol/signature code. Where account pinning requires it, B extends the existing Gateway facade's billing-used operations with optional `merchant_account:`; validate platform account/provider/mode before dispatch. Existing member/checkout callers retain their normal credential resolution.

Reuse `Payments::Activities::PrepareAttempt.call(customer:, order:, payment:, operation:, attributes:)` before HTTP. Its concurrent version resolves the current active account, so add an optional explicit account argument only after owner handoff if required to match the method's pinned account. The billing attempt's request_key must equal/derive from the same immutable `payment.out_trade_no`, and both records must name the same merchant/account/context. Historical query, verified settlement, and revocation must remain possible for a disabled account; new charge/setup must enforce current availability/readiness. Do not use current global mode/account as a replacement for historical operation identity.

### 4.3 Locking, transactions, and cross-partition calls

* Serialize billing domain transitions in short transactions: subscription first, invoice second, then auxiliary redemption/coupon/sequence/attempt rows. Never take a subscription lock after an invoice lock. Subscription creates also serialize on customer; method-default/activation/removal serialize on purchasing customer.
* SQLite row-lock semantics are insufficient by themselves: use unique identities/partial indexes and conditional state updates, handling the loser by reloading existing records. Sequence allocation uses a SQLite-compatible atomic increment/short transaction with bounded busy retry, wrapped by InvoiceNumber.
* A persists intent/invoice preparation in a transaction and only then requests B collection after commit. B prepares a durable attempt/payment and commits **before HTTP**. It records outcome in a separate transaction. An ambiguous external write must never disappear because a local transaction rolled back.
* All synchronous success, webhook, Query reconciliation, zero settlement, and owner manual settlement call the same MarkInvoicePaid. B locks subscription→invoice, validates payment/order linkage/amount/currency, marks invoice paid, calls A's ApplyInvoiceSettlement, creates notice receipt, commits. A never opens a separate transaction that can commit target entitlement without the paid invoice.
* Payments success is recorded independently first; retry billing projection even when the Payments record already says succeeded. `HandleWebhook` must not swallow projection failure and mark its event processed. Existing redrive/ActiveJob retry and an invoice reconciliation sweep recover the payment→invoice projection gap.
* Batch jobs use `Current.set(customer: ...)` blocks or ensure reset, and explicit unscoped tenant IDs. Provider credential context is platform; settlement/entitlement context is the purchasing tenant. Never leave Current on a different customer after a service returns.

## 5. Safe collection, retry, settlement, and numbering state machines

### Invoice versus collection state

Keep financial status (`draft/open/paid/void/uncollectible`) distinct from collection_state. An open manual invoice is not a provider failure; a pending provider attempt is not an eligible retry. Uncollectible is a stopped debt classification, **not permission to ignore a real late capture**.

| Event/state | Permitted transition / action |
| --- | --- |
| Draft finalization | Under transaction draft→open; reserve eligible coupon cycle; add discount/tax once; allocate number once; set immutable policy/due date; create issued notice |
| Zero total | Same MarkInvoicePaid source=zero; no method, PSP order, attempt, or charge required |
| Manual policy | open/manual; initial paid access and upgrades wait for owner settlement; recurring debt/grace still monitored; no automatic provider attempts |
| Ready gateway invoice | Atomically claim; create attempt ordinal/key and platform order/payment; commit; submit once |
| Definitive provider success | MarkInvoicePaid source=gateway; clear retry/claim/debt as appropriate; collection_state=settled |
| Definitive decline | Complete attempt failed once; increment invoice failed count once; schedule from first_failed_at and snapshotted offsets or exhaust |
| Missing/incompatible method | Record failure_code and a single blocked transition; do not mint fake PSP attempts or send daily identical failure emails; eligible recovery on new method/default change |
| Requires action | Persist PSP intent ID; pending payment/attempt + requires_action; expose existing Stripe recovery controller; do not submit a different charge |
| Processing/unknown transport | pending/unknown attempt, reconcile_at; query provider or replay same documented idempotency key; never treat generic API errors as proof of nonexistence |
| Provider definitively says failed/closed/not found | Retire that attempt safely; next scheduled attempt can get a new payment/key |
| Retry exhaustion | No further scheduled charge; collection_state=exhausted, invoice→uncollectible; notify once. Existing paid plan's proration failure does not affect its subscription. |
| Renewal due but unpaid | A RecordInvoiceDebt: past_due_at fixed to due_at. Entitlements use snapshot grace deadline; successful settlement clears past_due only when blocking renewal debt is resolved |
| Grace expiry | A ExpireOverdueSubscription; fallback free; stop collection attempts from being newly submitted. Retain debt/history. Reconcile outstanding actual provider attempts. |
| Paid/void repeat commands | Unchanged or explicit invalid/conflict; never reopen/renumber |
| Late capture on open/uncollectible | Set paid exactly once and apply valid A intent/recovery hook. Ended subscriptions stay ended; review_required returned when intent is stale/ended. |
| Two different payments really captured | Record anomaly/owner notice with both attempt histories; do not credit twice or hide the second payment. Refund/correction uses existing Payments support. |

For default `[1,3,7]`, first definitive failure at t0 schedules retries at **t0+1d, t0+3d, t0+7d**. The third retry failure exhausts: four total failed submissions, not “repeat last offset forever.” Offsets are absolute from first failure, not cumulatively added to each retry. A late worker executes at most one due retry in a pass and chooses the next still-future offset; it does not burst three charges to catch up. Manual force/recovery is separately authorized and recorded, cannot bypass in-flight or success guards, and does not reset the retry clock automatically.

Blocked renewal and pending initial invoices still expire through their due-date grace, even when no PSP call happened. The batch runs reconciliation/due retries before grace-expiry decisions so a settlement already recorded at the deadline wins. Unknown/pending charges are not blindly retried when the grace clock expires. Failed initial/proration invoices use their own request expiry; A must not mark a paid base subscription past_due just because an upgrade failed.

Collection mode is the issued invoice's snapshot. Changing global Settings affects newly issued invoices only. Switching an outstanding manual invoice to gateway is an explicit owner recovery operation that updates the **collection authorization**, preserves all financial terms, and writes an audit/notice event; no cron-wide silent reinterpretation.

### Job ownership

* A owns `RenewSubscriptions`: prepare/reuse invoices via Renewal; dispatch B finalization/initial collection after domain transaction; free-period settlement included.
* B makes CollectDueInvoices select **only unattempted ready gateway invoices**. Dunning selects **only retry_wait with due next_attempt_at**, and handles blocked/manual overdue/grace through A hooks. Central CollectInvoice/attempt-completion owns retry scheduling and exhaustion, independent of caller ordering.
* B adds `Billing::Cron::ReconcileCollections` for prepared/stale claims, pending, requires_action, unknown, and succeeded Payments whose invoice projection is missing; it never creates a fresh payment merely because a claim expired.
* B adds `Billing::Cron::RevokePaymentMethods` and durable notice dispatch. DailyBillingJob coordinates renewal, disjoint collection/dunning, trial notices, and resets Current. A dedicated collection-maintenance job runs every 15 minutes for reconciliation/revocation/outbox; daily-only SCA/unknown recovery is too slow. `config/recurring.yml` belongs to B.
* B excludes `managed_by=billing` mandates from general Payments due population **and claim/charge_one guards**, including agreement activation (no next_charge_at for billing mandates). Other ordinary Payments subscriptions remain on their existing schedule.

### Numbering interface

`Billing::InvoiceNumber.allocate!(customer_id:)` returns the next durable `INV-<customer_id>-<at-least-five-digit-sequence>`. Called only while finalizing a draft inside the same transaction as number assignment. A duplicate finalization reloads the existing numbered invoice. If a number constraint fails because of legacy conflicts, roll back and report/repair the sequence; do not retry a count-derived identical proposal. Never delete sequence rows on catalog archival/subscription end.

### Notices

Use SolidQueue/ActiveJob and BillingMailer; no new delivery vendor. Notice creation is transactional with state mutation, unique by business event. Dispatch after commit and sweep pending outbox receipts. SMTP delivery cannot guarantee exactly-once across a worker crash: promise durable, deduplicated event/enqueue intent, not impossible exactly-once email transport. Trial notice key includes the actual trial_end; failure notice key includes definitive attempt ID; no notice on each poll. Respect purchasing customer's locale in asynchronous rendering; snapshot invoice identity/price, not current catalog names. Provide links to the correct tenant billing page and an owner action path where relevant.

## 6. Provider setup and removal — concrete implementation

### Stripe

1. AvailableProviders uses `Payments::EligibleGateways.for(platform_customer, currency:)`, then supported recurring setup capability. Stripe qualifies; PayPal/WeChat must not appear solely because some capability exists without a working billing adapter.
2. B creates a pending tenant Billing::PaymentMethod + platform mandate with `managed_by=billing`, currency from subscription, next_charge_at nil, exact unique external ref `billing-pm-<tenant>-stripe-<billing_method_id>`.
3. Reuse existing gateway `vault_card` / official stripe gem; create a **platform-owned billing** Payments::PaymentMethod with pending:<SetupIntent ID>, billing_customer_id/authorizer instead of assigning it to a mismatched member user. Link it to the mandate. Extend the billing-used vault call with a stable request key: Stripe Customer and SetupIntent creation each get distinct deterministic keys derived from the persisted billing method ID. Stamp billing-method/tenant identity in provider metadata for exact early-callback correlation. Repeated/ambiguous setup submissions replay those operations, not create another customer/intent. Persist returned SetupIntent ID as authorization_reference before returning a client secret.
4. F mounts existing `payments--stripe-card` / shared Stripe.js loader. C exposes same-tenant setup endpoint, and a confirmation endpoint that only acknowledges the exact existing method. B verifies via signed setup webhook or server query; never trust browser payment_method_id as proof. If webhook races the initial response before local correlation exists, leave the event retryable or reconcile its exact SetupIntent later.
5. Verified setup fills existing token display metadata, requires `chargeable?`, activates mandate **without next_charge_at**, and activates the linked tenant method. requested_default is applied under the tenant customer serialization boundary. Setup completion for a removed/expired method never resurrects it; queue token revocation.
6. Recurring invoice charges already use Stripe#charge_subscription/#charge_token; preserve invoice total/currency (not mandate ceiling), store pi ID on all results, reuse payment.out_trade_no for idempotency, show SCA via existing `payments--sca-recovery`.

### Alipay

1. CNY only. Keep the existing gateway/signature/OutboundHttp support. `Alipay#subscribe` currently treats `alipay.user.agreement.page.sign` like a server JSON call; B must verify the current vendor-supported page-sign parameter contract and return a real signed redirect/form descriptor using the existing signing helper (as the WAP page flow already does). Do not pass a raw sign string to the UI and assume it is navigable.
2. Correct merchant external-agreement reference versus provider agreement ID, cadence/period parameters, notification URL, and server-generated return URL against current Alipay documentation and merchant product permissions. Read the provider's required ceiling/cadence rules; a yearly mandate or enlarged invoice total cannot be presumed supported just because local enums allow it.
3. Derive authorization ceiling in **CNY only**, including possible tax and accepted cadence; never compare USD and CNY numeric magnitudes. If a plan change exceeds a mandate's permitted amount/frequency, return reauthorization_required before collecting; never silently raise the provider authorization ceiling.
4. Existing public `/payments/webhooks/alipay` remains the single signed ingress. Route verified agreement notifications before the trade branch. Resolve exact merchant/account + external agreement reference + linked method, bind PSP agreement_no, activate both rows, and keep next_charge_at nil. Handle verified revocation/expiry too. Add an agreement query operation inside the existing gateway/facade for confirmation/reconciliation when notifications are delayed.
5. Return callback is a same-tenant admin GET that displays existing status and the exact provider action through B's read query; a browser query string cannot activate a method. Signed callback, background reconciliation, or CSRF-protected confirmation POST performs verified activation. Only generated/allowlisted provider action destinations are accepted for redirects/forms.

### Default and removal

Method setup is allowed before choosing a paid plan; mandate ceiling logic must be independent of free price. Setup remains pending until verification; keep the previous default until the replacement becomes active. If multiple authorizations overlap, one requested_default wins under serialized customer mutation; the database index is the final guard, not a reason to return a false success.

Remove active **or pending/failed** methods. Commit removed/is_default=false and locally cancel its managed mandate (next_charge_at=nil) before external revocation. Choose a compatible active replacement explicitly, otherwise require customer choice; do not automatically default to a different-currency provider. Retry revoke/detach with stable correlation. A pending unknown collection may still settle, but cannot start any new charge from the removed method. Default change must not detach a method already backing a pending payment; reconciliation uses that original attempt's account/method.

## 7. Controller/frontend contract, routes, settings, and locales

### Authorization

Existing controller-layer gates are `ApplicationController` → `TenantContext`, `RouteAuthorization`, `Authentication::EnforcesMfa`. Both billing base controllers inherit them. `RouteAuthorization` guards admin roles and platform paths/controller prefixes; TenantContext rejects cross-tenant admin/member requests and allows platform-owner context switching. Preserve these gates; do not introduce a billing global redirect that hides invoices or payment recovery from delinquent tenants.

C scopes tenant subscription/invoice/method/change IDs through `for_current_customer`; returning a different tenant ID is 404/denial. Platform lists are `unscoped_by_tenant` only inside the owner namespace. New records must correspond to the URL purchasing customer; owner visiting another tenant's settings updates that tenant. Public webhook proof remains signature/account binding. CSRF remains enabled for every browser write. Do not add member-access billing management or expose platform token vault rows through member methods.

### Required route changes, owned only by C

Keep all current billing routes in `config/routes.rb`. Add:

| Verb/path (prefix `/:customer_id/admin/settings/billing`) | Controller/action | Interface |
| --- | --- | --- |
| GET `subscription/plan_change_preview?plan_code=...` | subscriptions#plan_change_preview | A preview, no mutation; amounts/currency/effective time plus eligibility |
| DELETE `subscription/plan_change` | new plan_changes#destroy | A CancelPlanChange for customer's pending change |
| POST `payment_methods/setup_intent` | payment_methods#setup_intent | B SetUpPaymentMethod provider stripe; JSON action/identity |
| GET `payment_methods/:id/authorization` | payment_methods#authorization | F secure setup/status surface; read existing action/intent through B if pending; no activation write |
| POST `payment_methods/:id/confirmation` | payment_methods#confirmation | B verifies/acknowledges exact correlated authorization; client cannot attach arbitrary token |
| POST `invoices/:id/payment` | new invoice_payments#create | B recovery collection for an open/recoverable customer's invoice |

All remain admin URLs and server guarded. Generate request_key on the server/form and submit it as a permitted stable UUID with plan/provider request; same key on Turbo resubmit. Do not accept customer_id, prices, currency, period dates, plan snapshots, merchant account IDs, PSP tokens, or arbitrary return_url from browser params.

Do not need a new public callback or vendor route. Alipay return targets authorization with server-generated method/customer identity. Existing `/payments/webhooks/:provider` handles signed completion. Platform invoice retry/mark_paid/void routes use typed results; mark_paid includes an explicit manual audit reference/reason, and recovery of exhausted debt must be intentional rather than “always succeeded” flash.

Exact added request fields: subscription PATCH permits `billing_subscription[request_key]` alongside plan_code/coupon_code; method create/setup POST permits `billing_payment_method[request_key]` (provider fixed to stripe on setup_intent). Confirmation may receive `setup_intent_id`/`payment_method_id` as untrusted correlation hints, but its route ID is the scoped Billing::PaymentMethod authority. Owner mark_paid permits `settlement[reference]` and `[note]`, passing current_user as actor. Owner retry may explicitly permit `collection[mode]` and `[note]` to invoke AuthorizeInvoiceCollection before recovery; absent override preserves issued mode. No tenant endpoint accepts collection-mode override.

### Rendering and JSON

* HTML successful commands redirect with **303** and localized notice that matches result status: scheduled date, awaiting payment, requires action, applied, revoked locally/pending provider cleanup. A pending request is not “plan changed.”
* Invalid input is **422**, preserving `@contract`/submitted values and limits in the original screen; conflicts **409** (or 409 rendered screen with an actionable message); pending JSON **202**, ready JSON **200/201** as appropriate. Expected errors are stable reason codes with localized field/message rendering.
* JSON setup response: `{ payment_method_id: <billing ID>, confirmation_url: <server-generated scoped POST URL>, client_secret:, status: "authorization_required", action: { kind: "stripe_setup", publishable_key:, client_secret: } }`. **Provide top-level client_secret for the reused controller; action remains the general HTML/domain descriptor.** F narrowly extends shared Stripe vault mode to POST the server-provided stable request_key, use the returned confirmation_url for that method, and retain the same prepared intent across failed submits. Other member-vault consumers retain their existing createUrl behavior. Payment-method IDs in this response are Billing IDs; browser `pm_...` hints sent to confirmation never become a new vault association without provider proof.
* Plan preview JSON: `{ kind: "immediate"|"scheduled", effective_at: <ISO8601>, currency:, subtotal_cents:, tax_cents:, total_cents:, allowed:, reason: }`. UI formats through server/locale conventions; accepted commands recompute and persist authoritative terms. No frontend-only proration math.
* Standard list assignment: `@invoices/@subscriptions/@plans/@coupons/@payment_methods` plus `@pagination = { page:, per_page:, total:, total_pages: }`. Use existing Pagy 9.3, fixed 25-row page size, deterministic `created_at DESC, id DESC` (catalog code/position+id), and `Admin::PaginationComponent` with a page_path proc that preserves valid filters. Paginate subscription detail invoice history too. Invoice filters: `q` literal escaped number substring, allowlisted `status`, `page`; platform invoice/subscription indexes additionally accept `tenant_id` (never override the owner's route customer_id). Subscription `q` matches plan name/code. GET filters must not mutate billing state.
* Form components accept `form:` and use its errors and submitted attributes; default to a fresh contract for GET. Do not `sync` invalid forms onto a persisted AR model to make the template work. Plan limits are part of validated submitted form state, not silently parsed `to_i` outside transaction.
* Overview assignments also include `@entitlements`, `@pending_plan_change`, canonical `@currency`, `@payment_methods` including pending/failed/removed status where relevant, `@provider_options`, and per-invoice action descriptors only on authorized detail/authorization pages.

### Professional UI task

F must first consult the required shadcn skill/MCP during the later UI implementation. Those tools are not available in this planning session; this document defines functional requirements, not a claimed shadcn design consultation. Deliver through existing ViewComponent/Tailwind/Stimulus conventions and shared admin/settings shells.

Subscription: purchased plan/price/cadence/currency; pending or scheduled target/effective date; payment/retry status; trial/cancellation; current usage versus **enforced** limits and fallback source. Upgrade confirmation shows charge-now preview and settlement dependency; downgrade/cadence confirms renewal date and billed interval. Disable conflicting submits but retain server validation. Support cancel pending change and resume scheduled cancellation.

Methods: complete Stripe secure setup and Alipay redirect journey; pending/failed/active/removed states; requested/default readiness; currency/provider availability explanations; pending provider revocation. Invoice details: frozen billing identity/lines/tax/discount, retry/exhaustion/overdue reason and next retry, tenant payment/SCA recovery, owner manual settlement/void/retry eligibility. Retain browser print/PDF; do not falsely promise a generated PDF attachment.

Use responsive cards/tables at phone/tablet/desktop, accessible labels/errors/focus/loading states, and truthful empty/unavailable states. Reuse existing Stripe SDK controllers; a new billing Stimulus coordinator is needed only if the existing secure setup lifecycle cannot mount before first confirmation. Fix that lifecycle in the shared controller rather than layering another card SDK implementation.

### Settings and locale ownership

B changes `Billing::Settings` and `Billing::Contracts::Settings`: remove gateway_provider; tax 0..10000 bps; non-negative grace/notice days; strictly increasing unique integer offsets, with [] meaning no retries. Snapshot these on issue. C removes dead strong params and parses schedule without coercing invalid tokens. F removes provider input/show-hide behavior from settings component/controller, adds field feedback, and explains absolute retry offsets.

**F is the sole locale-file editor** for this slice, including backend/controller error keys. A/B/C send required key+English+zh-CN+interpolation lists before integration. Existing locale areas confirmed:

* `config/locales/comp_billing.{en,zh-CN}.yml`: components, invoice lines, quota, statuses, settings;
* `config/locales/settings_billing.{en,zh-CN}.yml`: customer billing descriptions/readiness/confirmations;
* `config/locales/admin_settings.{en,zh-CN}.yml`: contracts and tenant flashes;
* `config/locales/maint_platform.{en,zh-CN}.yml`: owner billing CRUD/actions;
* `config/locales/billing_mailer.{en,zh-CN}.yml`: notices;
* `config/locales/settings_modules.{en,zh-CN}.yml` and `comp_payments.{en,zh-CN}.yml`: existing gateway/card labels and SDK error values; reuse identical text instead of duplicating;
* existing settings-navigation keys already cover subscription/payment methods/invoices; do not rename navigation without updating both locales and consumers.

New keys include `admin_settings.flash.subscriptions.{plan_change_scheduled,plan_change_pending,plan_change_cancelled,pending_change_exists,subscription_pending}`; `admin_settings.errors.validations.{billing_request_key,change_requires_active_subscription,default_plan_must_be_free,free_limits_required,dunning_schedule_order,coupon_fixed_currency}`; `settings_billing.subscription.{pending_change,scheduled_change,effective_on,free_entitlements,grace_until,charge_now}`; `settings_billing.payment_methods.{confirming,authorization_failed,currency_unavailable,revocation_pending,reauthorization_required}`; `comp_billing.invoice_detail.{next_attempt,collection_exhausted,payment_requires_action,pay_invoice,settlement_review}`; statuses `pending`/plan-change states; archive wording and manual settlement reason. Backend reason codes remain machine identifiers, never raw exception messages displayed to users.

Remove obsolete `plan_interval_mismatch` and `gateway_provider_required`/component provider keys only after searching all consumers. Replace contradictory “immediately”/“any prorated charges” copy with result-specific timing; preserve byte-identical English for unchanged wording and keep en/zh-CN interpolation parity. I18n at call time, never translated Ruby constants. JS values have English defaults and translated server data attributes; no literal JS UI strings.

## 8. Exclusive implementation partitions — exact task briefs

The following ownership list is the edit boundary. A file belongs to exactly one agent. “New” paths are proposed additions. Wildcards refer to a named closed directory subtree, not permission to edit other partitions. Contract/schema changes require coordination through the frozen interface, not opportunistic editing of another agent's file.

### Backend A — subscriptions, entitlements, catalog, coupons, all migrations

**Task:** implement section 2 domain policy, persisted PlanChange/CouponRedemption, finite Entitlements, safe renewal preparation and settlement hooks. Supply the schema for every partition and pure preview/discount/catalog services. No provider HTTP or collection-state mutation outside the agreed B interfaces.

Existing exclusive files:

* `app/models/billing/{subscription,plan,plan_limit,coupon,countable_item}.rb`
* `app/services/billing/activities/{subscribe,change_plan,cancel_subscription,resume_subscription,apply_coupon}.rb`
* `app/services/billing/contracts/{subscribe,change_plan,plan,coupon}.rb`
* `app/services/billing/{quota,proration,onboarding,standard_plans,assign_plan_limits,currency_resolver}.rb`
* `app/services/billing/quota/guard.rb`
* `app/services/billing/countable/{registry,item_definition,catalog_sync}.rb`
* `app/services/billing/cron/renew_subscriptions.rb`
* `app/models/customer.rb` (trial marker/onboarding domain integration only)
* `lib/tasks/billing_backfill.rake` (inspect/update explicit enrollment semantics; never run during audit)
* new migrations listed in section 3, `db/schema.rb`, new `lib/tasks/billing_repair.rake`
* `doc/reference/en/billing.md`, `doc/reference/zh-CN/billing.md` — A assembles B/C/F's agreed sections so one writer owns both complete reference pages.

New exclusive files:

* `app/models/billing/{plan_change,coupon_redemption}.rb`
* `app/services/billing/{result,entitlements,renewal,plan_change_policy,discounts}.rb`
* `app/services/billing/activities/{cancel_plan_change,apply_invoice_settlement,record_invoice_debt,expire_overdue_subscription}.rb`
* `app/services/billing/catalog/{save_plan,save_coupon,archive_plan,archive_coupon,update_countable_items}.rb`

Acceptance handoff: one live row including pending; one outstanding change; no unpaid upgraded quota; late valid settlement applies exactly one target; scheduled cadence/downgrade at next renewal; no repeat trial; coupon cycles independent of past invoices; no missing/ended unlimited quota; all schema/index/FK/migration conflicts reported explicitly.

### Backend B — invoicing, collection/dunning, methods/providers, notices

**Task:** implement sections 3.2, 4.2, 5, and 6 against A's schema/hooks. Own financial/attempt state; one settlement entry point and durable retry/reconciliation. Reuse Stripe/Alipay and existing Payments webhook/event machinery. Supply migration requirements to A; do not edit migrations, subscription/plan/coupon models, Renewal, or A's cron.

Existing exclusive files:

* `app/models/billing/{invoice,invoice_line_item,payment_method,settings}.rb`
* `app/services/billing/activities/{generate_invoice,finalize_invoice,collect_invoice,mark_invoice_paid,void_invoice,set_up_payment_method,remove_payment_method}.rb`
* `app/services/billing/contracts/{settings,payment_method}.rb`
* `app/services/billing/{collector,invoice_number,available_providers,notifier}.rb`
* `app/services/billing/cron/{collect_due_invoices,dunning,trial_ending_notices}.rb`
* `app/jobs/billing/daily_billing_job.rb`, `config/recurring.yml`
* `app/models/payments/{subscription,payment_method}.rb`
* `app/services/payments/gateway.rb`, `app/services/payments/gateways/{stripe,alipay}.rb`
* `app/services/payments/activities/{handle_webhook,query}.rb`
* `app/services/payments/activities/prepare_attempt.rb` — shared hardening integration only after the current external owner hands off; preserve its operation-context invariant.
* `app/services/payments/cron/{charge_due_subscriptions,reap_stale_payment_methods}.rb`
* `app/mailers/billing_mailer.rb`
* `doc/reference/en/payments.md`, `doc/reference/zh-CN/payments.md` — B owns changed gateway/webhook/token ownership documentation; send billing reference text to A.

New exclusive files:

* `app/models/billing/{invoice_sequence,collection_attempt,notice}.rb`
* `app/services/billing/providers.rb` and thin `app/services/billing/providers/{stripe,alipay}.rb`
* `app/services/billing/{payment_authorization,invoice_payment_action}.rb`
* `app/services/billing/activities/make_default_payment_method.rb`
* `app/services/billing/activities/authorize_invoice_collection.rb`
* `app/services/billing/activities/update_settings.rb`
* `app/services/billing/cron/{reconcile_collections,revoke_payment_methods,dispatch_notices}.rb`
* `app/jobs/billing/{collection_maintenance_job,dispatch_notice_job}.rb`

Acceptance handoff: repeated finalize preserves exactly one number/line set; one inflight attempt; unknown writes reuse identity; four failures exhaust `[1,3,7]`; overdue settlement recovers valid live sub through A; removed mandate cannot charge; verified setup activates only exact method; Stripe offered and SCA works; Alipay CNY action and agreement callback work; no billing mandate in general cron; notice event deduplication survives retries.

### Controller agent C — routes, tenant/owner request orchestration, pagination

**Task:** consume A/B commands/results; retain existing authorization/tenant contexts; implement section 7 routes/status/params/forms/list assignments, and the exhaustive non-builder route audit tracking. No business-state writes in controllers (including make-default, catalog destruction, coupon counters, manual payment, and plan snapshots).

Exclusive files:

* `config/routes.rb`
* `app/controllers/admin/settings/billing/{base,subscriptions,cancellations,coupon_redemptions,payment_methods,invoices}_controller.rb`
* `app/controllers/admin/maintenance/platform/billing/{base,plans,coupons,countable_items,settings,subscriptions,cancellations,invoices}_controller.rb`
* new `app/controllers/admin/settings/billing/{plan_changes,invoice_payments}_controller.rb`
* `app/controllers/authentication/registrations_controller.rb` and `app/controllers/admin/modules/authentication/users_controller.rb` — only correct member-role quota invocation if A's counting contract requires it; no builder controllers.
* new `app/controllers/concerns/billing/pagination.rb` — thin Pagy adapter yielding existing PaginationComponent hash, not a new pagination algorithm.
* `docs/audits/2026-10-11-route-audit-manifest.md` during the later audit execution; retain evidence/status per route rather than claiming inferred pass.

Read-only dependencies: `ApplicationController`, `TenantContext`, `RouteAuthorization`, `Authentication::EnforcesMfa`, `Ability`, Payments webhook controller and module gates. If the broader audit finds a non-billing gate defect, record it as a separately owned task; do not concurrently refactor these central files in this billing slice.

Acceptance handoff: every listed billing action reachable and authorized correctly; tenant ID tampering denied; owner cross-tenant list/detail allowed only through platform gate; 422 displays submitted contract errors/values; scheduled/pending feedback truthful; all history reachable through pagination; client never controls PSP token/price/tenant/account; template-builder exclusions preserved in audit.

### Frontend agent F — billing ViewComponents/views, shared secure SDK wiring, all locales

**Task:** consult shadcn first, then implement section 7's functional responsive surfaces using current Rails components. Consume A preview/entitlements and B action/state descriptors; preserve secure provider confirmation and server authority.

Exclusive files:

* `app/components/billing/admin/` — all existing `.rb`/`.html.erb` pairs: `platform_billing_nav`, `countable_items_form`, `plan_catalog`, `plan_form`, `coupon_table`, `coupon_form`, `subscriptions_table`, `subscription_summary`, `plan_comparison`, `customer_subscription`, `payment_method`, `payment_authorization`, `customer_payment_methods`, `invoice_table`, `invoice_detail`, `settings_form` components. This is the complete current billing component subtree.
* `app/views/admin/settings/billing/` — existing subscription show, payment_methods index, invoices index/show/download; add authorization view as needed.
* `app/views/admin/maintenance/platform/billing/` — all current plan/coupon/subscription/invoice/settings/countable-items templates.
* `app/javascript/controllers/billing_{plan_compare,plan_picker,settings,invoice,coupon_form}_controller.js`
* `app/javascript/controllers/payments/{stripe_card,sca_recovery}_controller.js` only where shared setup/recovery lifecycle needs adjustment; reuse `app/javascript/lib/stripe_js_loader.js` without editing unless jointly declared a necessary F-owned change.
* `app/views/billing_mailer/` — existing email templates; B supplies event data/requirements, F owns presentation.
* All paired locale files listed in section 7; `doc/customer/en/billing.md`, `doc/customer/zh-CN/billing.md`.
* New billing components/Stimulus files, only if existing components/controllers cannot express the agreed action lifecycle.

Read-only shared UI: `Admin::PaginationComponent`, `AdminPageComponent`, admin/settings shells and SDK loader. No CSS framework/custom stylesheet, direct JavaScript framework, frontend charge arithmetic, or hardcoded user wording.

Acceptance handoff: complete setup→verification→ready journey; pending changes/scheduled dates visible; correct cadence labels; fallback/grace usage truthful; inline accessible form errors; tenant invoice payment/SCA actions; owner archive/manual recovery; mobile/tablet/desktop layouts; en/zh-CN key/interpolation parity. Later implementation must satisfy AGENTS.md JS coverage/check requirements; no tests are authored/run by this planning task.

## 9. Execution order and integration gates

1. **Contract freeze and current-owner handoff:** A/B/C/F agree Result including `record/form`, exact state enum values, key identities, setup JSON, invoice snapshot shape, and B's migration requirements. Reconcile the concurrent Payments/auth changes and companion UX behavior/endpoints. Existing payment-file authors retain their active edits until an explicit handoff; afterward B is sole billing-integration editor for its listed shared payment files. C's member-quota call-site changes likewise wait for authentication-file handoff. Capture departures by editing this plan before implementation.
2. **A schema foundation:** migrations/models/result/snapshot and entitlement policy first. B can develop provider/error normalization and state transitions against these named columns; C/F can work against frozen descriptors. A alone integrates schema output.
3. **Parallel domain work:** A builds renewal/change/coupon/settlement hooks; B builds generation/finalization/attempts/providers/notices. Neither edits the other's files. C wires request adapters; F builds components with fixtures/mock descriptors during later implementation.
4. **Integrate settlement before opening collection:** prove domain invariants through the future authorized verification process, then wire provider setup and shared webhook/query settlement. Do not deploy a UI that advertises a capability before its callback/recovery path exists.
5. **Integrate routes/forms/locales/pagination:** C/F verify the exact return shapes and correct 422 submitted-state rendering. A assembles billing reference docs from partition notes; B updates payments references; F updates customer docs, both languages in each case.
6. **Complete broad route audit separately:** expand runtime/plugin routes and execute authorized isolated-environment journeys, including every verb/write/error branch, per manifest. Billing code completion does not stand in for an exhaustive routes audit. This session only supplies its scope and evidence ledger.

No tests/subagents are part of the current request. The later implementation acceptance checklist must cover concurrent duplicate enrollment/change/finalize/charge, lost HTTP response, webhook-before-response, replayed/late callbacks, duplicate real capture, manual/zero/SCA settlement, retry exhaustion/grace, cadence boundary, coupon attachment after free history, archive/history, tenant isolation, and pagination beyond 100. These are behavior requirements, not newly written tests or a claimed test run.

## 10. Scope tradeoffs

* Reuse installed **stripe 19.3, money 6.19, pagy 9.3, Reform/Trailblazer, Faraday/OutboundHttp, SolidQueue, and existing Alipay signing/verification**. No new payment vendor or wholesale Stripe Billing migration. The local invoice engine remains the authority; don't add a second PSP subscription engine.
* Ship USD/CNY, flat recurring plans, simple tax bps, one coupon per subscription, same-cadence prorated upgrades, next-renewal downgrades/cadence changes, and finite enforced core quotas. No FX, usage-priced billing, tax-jurisdiction engine, coupon stacking, mid-cycle downgrade credits, or recurring annual/monthly cross-cadence credit calculation.
* Do not promise unsupported storage/support/communication/payment quotas; wiring their distributed authoritative writes/reservations is a separate feature slice. The existing broader route audit must record those reachability/enforcement gaps honestly.
* Archive rather than delete catalog. Print/save-as-PDF remains the invoice download contract. Refund/correction automation, credit-note ledger, advanced pause/resume, and payment-after-ended auto-reenrollment are follow-up work; capture/debt anomalies are persisted and visible, never silently treated as successful entitlement changes.
* No billing feature-module toggle or new reserved role. No builder audit or builder UI rework. A provider product permission/cadence limitation is surfaced as reauthorization/unavailable, not papered over by local state.

**Implementation plan path:** `docs/audits/2026-10-11-billing-plan.md`.

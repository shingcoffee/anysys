# Billing Partition A implementation handoff

## Verification boundary

Implementation follows the complete billing plan and companion UX under the backend-developer role. No tests, migrations, schema dump, provider requests, or subagents were run. `db/schema.rb` regeneration belongs to the later central migration step. Existing email/SMS and speech-to-text migrations are separate and untouched.

## Frozen interfaces

Every section 4.1 command/query and catalog command is implemented with the specified keyword arguments. `Subscribe` and `ChangePlan` require `request_key:`. `Billing::Result` exposes `status`, `subscription`, `plan_change`, `invoice`, `payment_method`, `record`, `form`, `action`, `reason`, and field-keyed `errors`. The envelope and copied errors/action are immutable; saved AR records and Reform contracts remain ordinary domain objects.

An explicit new Subscribe request can expire a logically overdue old row before reenrolling; a historical request replay cannot. The RC-11 follow-up wires C to `Entitlements.current_subscription(customer:, at:)`, preserving latest history separately. Recorded settlements project before expiry, unresolved historical attempts return conflict before any new invoice, and new enrollment requires valid finite fallback. Existing debt is retained. See `2026-10-11-billing-rc11-lifecycle.md` for the source audit and authored checks, including the separate B stale-currency-selection follow-up.

`Entitlements.for` returns readers `source`, `plan_snapshot`, `expires_at`, `limits`, and `reason`. Sources: `purchased`, `trial`, `grace`, `free`, `platform`. Invalid fallback gives zero core capacity and `fallback_configuration_invalid`. Queries do not create settings/catalog/enrollments. Core quotas are enforced even if a catalog row is missing or disabled; unsupported keys are not published as quotas. C must invoke the member quota only when the requested account role is member.

Catalog results preserve submitted raw prices/limits/coupon input on `form`; invalid forms are never synced. `Contracts::Plan#limits` is a virtual hash, and `normalized_limits` is only used after successful validation. `UpdateCountableItems` accepts an array of attribute hashes (the controller's normalized collection), retains it as `form.items`, rejects unsupported enabled keys, and preserves the authoritative core counters' total-period semantics.

## B integration requirements

* `Result.transaction(record)` acquires a SQLite write reservation before loading transition state and retries bounded busy errors outside a caller-owned transaction. Nested commands use savepoints so a rejected enrollment rolls back its own writes. B's subscription → invoice transaction uses this helper. `ApplyInvoiceSettlement` requires an existing transaction and an already-paid invoice; it never commits independently.
* Canonical plan snapshot keys are string keys: `plan_id`, `code`, `name`, `amount_cents`, `currency`, `interval`, `limits`, `grace_period_days`. Invoice terms additionally include `tax_rate_bps`, `collection_mode`, `dunning_schedule`, `due_at` (ISO8601), and, for renewals, `billing_anchor_day`/`billing_anchor_month`. Empty retry arrays are preserved.
* A calls B's exact `GenerateInvoice`, `FinalizeInvoice`, `CollectInvoice`, and `VoidInvoice` signatures. Invoice preparation is transactional; finalization/collection is dispatched with `ActiveRecord.after_all_transactions_commit`. Onboarding is now `after_create_commit` and restores `Current`.
* Initial dates start at acceptance; renewal dates start at the original boundary. Proration source dates stay the original purchased period, but **due_at/request expiry is period_end**, not period_start. A stamps that deadline on the prepared draft so a mid-period upgrade is not already expired. B should honor `terms_snapshot["due_at"]` when generating invoices.
* Added invoice `entitlements_applied_at:datetime` is A's idempotent projection receipt. It is mutable settlement metadata, not a financial attribute. No additional subscription JSON flag or duplicate settlement ledger is needed.
* `PlanChangePolicy.unresolved?` uses B's public `Collector.unresolved?`, including captured Payments awaiting invoice projection. No conflicting old-plan renewal is prepared while an upgrade is unresolved. Expiry/immediate cancellation terminates the intent but preserves unresolved invoice/attempt evidence for reconciliation; it does not claim to void an in-flight capture.
* `Notifier.subscription_cancelled(subscription)` is invoked inside the state transaction; B must implement it as transactional notice/outbox intent, as specified by the plan. Do not enqueue provider/email work inside that transaction.
* The mandate ownership authority is **`payment_subscriptions.managed_by`**. `billing_owned?` is aligned to it. A also supplies `metadata:json` for B's current setup correlation payload (`billing_owned`, method ID, purchasing customer ID); metadata is informational and is never read to decide collection ownership. B stamps `managed_by: "billing"`, keeps `next_charge_at: nil`, and owns activation/scheduler guards and Payments::PaymentMethod validation.

## Schema and preflight

One consolidated Rails 8.1 migration replaces the four proposed schema-only migrations: `20261011000100_add_billing_subscription_lifecycle.rb`. It includes all section 3 A/B tables/columns, platform billing token ownership checks, restrictive history FKs, permanent request identities, one-live/one-change/one-attempt/default/coupon-cycle unique indexes, counters/state checks, and the projection receipt. It does not regenerate schema or modify any other migration.

`billing:repair_report` is read-only and has no apply mode. It reports orphans, live/default duplicates, invoice tenant/currency/line mismatches, invalid monetary/default data, missing period dates, unprojected captures, unfinished charges, ambiguous coupon consumption, legacy subscription mandate links, provider-mismatched/shared mandates, and unmapped billing external references. Migration preflight refuses those conflicts; it never deletes or manufactures financial history. Historical subscription/invoice terms are explicitly marked `reconstructed`; stored amounts and descriptions remain intact. Known untouched coupon redemptions start at zero only when no eligible issued history exists. Trial markers are backfilled from previous trial records. Sequence heads come from the maximum valid `INV-<customer>-<digits>` suffix, never counts.

Historical method account/actor authorization is **not inferred from today's gateway mode**. Methods are marked `historical_authorization_review`, retaining links and debt; B/operator reconciliation must establish exact authorization before charging. Linked mandates are tagged billing-owned and their general scheduler date is cleared.

## Deliberate narrow departures

1. One consolidated migration instead of four reduces SQLite table-rebuild ordering and keeps all cross-partition constraints together. The named schema contract is retained; the only extra financial-domain column is the settlement projection receipt (plus requested mandate correlation metadata).
2. A cancelled scheduled target may already have an immutable renewal invoice. Safe cancellation voids it. A replacement renewal uses the same boundary identity plus `:revision:<voided count>`; repeats do not change that suffix. Reusing the cancelled invoice would overwrite frozen terms or apply a cancelled target. This is the sole additional invoice-key case; wall-clock execution time is never used.
3. Seeding creates missing catalog offerings but preserves explicit edits and archives. It cannot rewrite referenced price identity or reactivate an archive.
4. Schema regeneration is deferred by instruction. No runtime compatibility layer is introduced for unmigrated records.

## F locale handoff

F is the sole locale writer. Add each following key to both locales before integration (no interpolation unless shown). Existing invoice line keys are reused.

| Key under `admin_settings.errors.validations` | English | zh-CN |
| --- | --- | --- |
| `billing_request_key` | must be a valid request UUID | 须为有效的请求 UUID |
| `code_immutable` | cannot be changed after creation | 创建后不可更改 |
| `catalog_terms_immutable` | cannot change the price or cadence of a referenced offering | 已被引用的套餐不可修改价格或计费周期 |
| `limit_invalid` | must be blank, -1, or a nonnegative whole number | 须为空、-1 或非负整数 |
| `default_plan_must_be_free` | must be active, unarchived, free in both currencies, and have no trial | 须启用、未归档、两种币种均免费且不含试用期 |
| `free_limits_required` | must include finite limits for every enforced item | 须为所有受限项目设置有限额度 |
| `default_plan_required` | must retain a valid free default plan | 须保留有效的默认免费套餐 |
| `coupon_fixed_currency` | must be USD or CNY for a fixed discount | 固定金额优惠须使用 USD 或 CNY |
| `countable_item_invalid` | must describe a supported, enforced countable item | 须为支持且已实施限额的可计数项 |

| Key under `comp_billing.countable_items` | English | zh-CN |
| --- | --- | --- |
| `page.label` | Pages | 页面 |
| `page.description` | Pages created in the page builder. | 页面构建器中创建的页面。 |
| `page.unit` | pages | 页 |
| `entity.label` | Entities | 实体 |
| `entity.description` | Custom entity definitions. | 自定义实体定义。 |
| `entity.unit` | entities | 个实体 |
| `member.label` | Members | 会员 |
| `member.description` | Registered member accounts. | 注册会员账户。 |
| `member.unit` | members | 位会员 |

Category accessors reuse `comp_billing.countable_items_form.category.content` / `.platform`. No translated constants.

| Key under `comp_billing.standard_plans` | English | zh-CN |
| --- | --- | --- |
| `free.name` | Free | 免费版 |
| `free.description` | Get started at no cost. Core features included. | 免费起步，包含核心功能。 |
| `starter-monthly.name` | Starter (Monthly) | 入门版（月付） |
| `starter-monthly.description` | For small teams. Billed monthly. | 适合小型团队，按月计费。 |
| `pro-monthly.name` | Pro (Monthly) | 专业版（月付） |
| `pro-monthly.description` | For growing organisations. Billed monthly. | 适合成长型组织，按月计费。 |
| `enterprise-monthly.name` | Enterprise (Monthly) | 企业版（月付） |
| `enterprise-monthly.description` | Unlimited scale for large organisations. Billed monthly. | 适合大型组织，核心用量不限，按月计费。 |

A reason codes for C/F: `validation_failed`, `request_replayed`, `request_key_used`, `live_subscription_exists`, `plan_not_active`, `currency_not_supported`, `change_requires_active_subscription`, `cancellation_scheduled`, `renewal_due`, `pending_change_exists`, `already_applied`, `subscription_ended`, `not_redeemable`, `currency_mismatch`, `plan_change_not_found`, `collection_in_flight`, `resume_blocked`, `subscription_not_renewable`, `change_hold_expired`, `fallback_configuration_invalid`, `default_plan_required`, `settlement_identity_mismatch`, `cancellation_boundary`, `settlement_after_expiry`, `plan_change_ended`, `stale_initial`, `stale_plan_change`, `stale_renewal`, `unknown_invoice_purpose`. Status/reason identifiers are machine values and must be translated at presentation time. Existing replay outcomes also use terminal plan-change status identifiers.

## Specs supplied

Updated A-owned regressions cover persisted pending enrollment/upgrade and historical replay; cancellation/resume; finite fallback and immutable limits; core member counting; calendar anchors; contract input retention; catalog archives/default swaps; and renewal preparation. New integrated specs cover valid uncollectible settlement recovery, late captures after expiry, immutable enrollment dates, scheduled cadence settlement, repeated unpaid renewals, ambiguous upgrade hold/cancellation, proration isolation, redemption-relative zero/free/proration/void discount cycles, and real two-connection enrollment/change races. These specs are authored, not executed. B-owned invoice/method factories and specs remain B's responsibility.

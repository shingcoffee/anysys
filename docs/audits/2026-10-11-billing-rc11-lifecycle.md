# Billing RC-11 lifecycle follow-up — 2026-10-11

## Boundary

Source-only audit and implementation of current A/B/C subscription selection, expiry, settlement projection and explicit reenrollment. No Rails boot, tests, migrations, schema dump, provider calls, or subagents were run. Ruby syntax and whitespace checks are the permitted verification. UI components receive the corrected existing controller facts; this pass adds no component, route, locale key or schema field.

## RC-11 resolution

The stored `Subscription.live` scope intentionally remains unchanged because the partial unique index and workers use it. New read-only `Entitlements.current_subscription(customer:, at:)` filters its row using `PlanChangePolicy.expiration_at`. Tenant BaseController and subscription preview now use that query; latest history remains separately scoped. A logically ended row no longer forces ChangePlan or highlights a current/future scheduled plan. A valid pending/paused request still remains current despite free fallback, and a normally renewable overdue base remains current throughout immutable grace.

`Subscribe` still checks permanent request replay first. For a fresh request, it serializes on customer then subscription, invokes the domain expiration path, and rechecks stored live state before inserting. Expiry first projects already-recorded capture/paid-invoice evidence through B's `MarkInvoicePaid`, without provider HTTP. A valid on-time renewal projection may advance the base and make reenrollment unchanged; late/ended capture is retained as owner review. Known projection failures return conflict rather than expiring/recharging around invalid evidence. Unknown historical attempts block a new enrollment even after the old parent has ended. Repeated/different concurrent requests cannot prepare two new live enrollments.

Cancellation boundaries, actual trial_end, immutable renewal/initial grace and explicitly voided unpaid initial invoices determine logical end. Trial boundary remains canonical until paid-period start reaches it. The ordinary zero-grace exact-boundary renewal exception preserves preparation before expiry. Expiry terminates pending targets through A's CancelPlanChange/B's VoidInvoice; an in-flight void conflict preserves its financial/attempt evidence and terminalizes only the expired intent. Genuine base debt is not automatically voided. Notices remain transactional/deduplicated through B.

Missing or invalid finite fallback now rejects a new initial enrollment with `fallback_configuration_invalid`, the submitted contract, and no new subscription/invoice. Missing plan input is a normal contract failure. Query fallback stays finite zero and reports the configuration reason; it never seeds on GET. Existing live subscription recovery is evaluated before the new-enrollment gate.

## Current A/B/C source audit

| Chain | Source conclusion |
| --- | --- |
| Tenant show/update/preview → logical current query | RC-11 source-remediated. GET only reads; nil is memoized per request, result rendering invalidates the memo, history stays separate and URL-tenant scoped. Existing F enrollment surface activates when current is nil. |
| Subscribe → customer/subscription serialization → expiry/projection | UUID replay precedes transition, local settlements use B's sole paid entry point, then live uniqueness is rechecked. Projection can advance a valid renewable base; no blind cancellation merely because a period ended. |
| Historical unknown/processing/SCA/prepared/captured attempts | New initial invoice is blocked until B reconciles the existing payment identity. Already-recorded captures are projected or reviewed locally; no HTTP is performed under domain locks. |
| Expiry → pending target cancellation → B VoidInvoice | Safe void results are used; a conflict retains evidence for reconciliation. Catalog/plan/coupon snapshots, debt, numbers and issued amounts remain historical facts. |
| Renewal → projection/expiry → preparation → settlement | Renewal sees the post-projection parent before choosing ended/not_due/invoice_ready. Actual trial boundary is shared with RecordInvoiceDebt and ApplyInvoiceSettlement, not reconstructed from current catalog or execution date. |
| Finite fallback / admission | Missing default gives zero query capacity and controlled invalid initial admission, never unlimited capacity or an exception from nil plan. |
| B default-method currency gate | The standalone guard exists now: MakeDefaultPaymentMethod calls Providers.readiness_reason, which checks mandate currency against invoice/live-subscription/resolved initial currency. It is not still missing. |
| B setup/readiness after logical end | Separate B follow-up: SetUpPaymentMethod, AvailableProviders cadence discovery, and Providers.readiness_reason still select stored `.live` when no invoice is provided, whereas C now selects logical current. Before explicit reenrollment closes that stale row, setup/default readiness and provider discovery can disagree with C's initial resolved currency/cadence. B should consume the shared logical query and revalidate selection at its customer write boundary. No B-owned files changed here. |

## Migration/source parity

Read all 19 billing migration files, the report task, B's integration handoff, and the current used fields/state contracts. This follow-up requires **no new schema field/table/index**. Existing trial marker, subscription snapshots/anchors/request keys, plan-change states, invoice projection receipt/review fields, attempts, notices, mandate ownership metadata and method/token customer/authorizer fields cover it. Restrictive FKs and one-live/request/attempt indexes remain the final guards. The schema source changed concurrently during this pass: version `2026_10_11_184517` now includes these fields, indexes, checks and FKs. Its billing/token/mandate definitions were re-read and match the migration; this pass did not edit/regenerate that file or execute a migration. Source dump parity is not live-DB verification.

The report-only repair task remains the deployment preflight. No live migration state was queried and no migration/report task was executed. Legacy financial/account/coupon conflicts still require explicit reconciliation; the patch adds no identity-guessing compatibility layer.

### Release preflight gaps found in source

The column/state contracts match; migration **data safety is not certified**. Two legacy shapes admitted by the old billing flow need release-owner review before applying the migration:

| ID | Evidence / missing report |
| --- | --- |
| MIG-L1 | Old nontrial Subscribe made positive-price subscriptions active before manual settlement. Consolidated `report` detects unfinished PSP charges but not an active positive subscription whose only initial manual invoice remains open/uncollectible and has no verified capture. `backfill` retains active status and purchased limits. Such a row can keep unpaid paid-plan entitlements after migration. Report it and require an explicit evidence-based owner decision; do not infer payment or silently rewrite history. No claim is made that these rows exist in the current DB. |
| MIG-L2 | Old ChangePlan had no permanent target record and could grant manual unpaid upgrades. Consolidated backfill labels legacy proration lines as purpose=proration but creates no PlanChange, while preflight does not report open/uncollectible manual proration without a target or PSP attempt. Later settlement cannot reconstruct the intent and correctly produces stale_plan_change review, but the old already-upgraded snapshot can still grant unearned limits. Require explicit legacy intent/access reconciliation rather than accepting this as a fully repaired migration. |

No migration file was changed during this release-preparing follow-up. These are reported data-preflight gaps, not requests for additional columns or a runtime compatibility layer.

## Authored regression checks

* Existing Subscribe specs: missing fallback, nil plan, submitted contract retention, renewable within-grace preservation, expired initial reenrollment and UUID replay.
* New logical_lifecycle specs: valid pending/paused versus free entitlement source, actual trial deadline, read-only queries, zero-grace exact renewal boundary, issued-policy grace, and voided initial intent.
* Real A/B lifecycle specs: on-time captured renewal projection before reenrollment/renewal expiry; actual pending Payments plus unknown attempt blocking; late capture recorded/reviewed before a separate request can proceed.
* Tenant request specs: read-only expired-history display, actual PATCH through Subscribe, trial-used enforcement, current-within-grace/pending preservation, no preview schedule on an ended request, controlled missing-default 422.
* Existing concurrency harness uses committed fixtures, two actual connection-pool worker threads, a three-party barrier, manual collection and bounded joins. Added a distinct-key race over one expired initial request, asserting one new live row/invoice and unchanged old issued financial fields. These are authored SQLite races, not a claim that they have executed.

Both developer reference locales describe the logical query, conflict result, projection ordering and admission gate. Existing paired locale keys are reused.

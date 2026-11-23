# Billing Partition B integration handoff — 2026-10-11

## Evidence and verification boundary

Read A's `2026-10-11-billing-partition-a-handoff.md`, the consolidated migration, the current A/B/C/F implementations, Payments integration hooks, and both mail locales. This is a source-level integration check. No application boot, tests, migrations, schema dump, provider requests, or subagents were run. The existing `db/schema.rb` intentionally remains the pre-central-migration snapshot; it is not evidence of a missing migration column.

## Required migration change list for A

**None.** B uses the consolidated `db/migrate/20261011000100_add_billing_subscription_lifecycle.rb` and the existing base tables. No additional B column, state, table, constraint, or migration is requested by this integration pass. A owns central migration execution and schema regeneration.

| Table | B field verification |
| --- | --- |
| `billing_invoices` | Existing financial/date/payment fields remain. Added `purpose`, `idempotency_key`, `billing_plan_change_id`, `billing_coupon_redemption_id`, `coupon_cycle_number`, `terms_snapshot`, `collection_state`, `first_failed_at`, `collection_claimed_at`, `failure_code`, `settlement_review_code`, `settlement_source`, `settled_by_id`, `settlement_reference`, `settlement_note`, `collection_override_mode`, `collection_override_by_id`, `collection_override_at`, and A's `entitlements_applied_at` all match. |
| `billing_invoice_line_items` | Existing `customer_id`, `billing_invoice_id`, `description`, `kind`, `quantity`, `unit_amount_cents`, `amount_cents`, and timestamps match. No extra line properties are persisted. |
| `billing_invoice_sequences` | `customer_id`, `last_value`, timestamps; unique customer index supports `InvoiceNumber.allocate!`'s atomic increment. |
| `billing_collection_attempts` | `customer_id`, `billing_invoice_id`, `ordinal`, `payment_id`, `billing_payment_method_id`, `merchant_account_id`, `state`, `request_key`, `failure_code`, `submitted_at`, `completed_at`, `reconcile_at`, `claimed_at`, timestamps all match. No client secrets are stored here. |
| `billing_payment_methods` | Existing provider/status/display/default/mandate fields remain. `request_key`, `merchant_account_id`, `authorized_by_id`, `authorization_reference`, `authorization_expires_at`, `requested_default`, `removed_at`, `revocation_state`, `revocation_next_attempt_at`, `revocation_attempt_count`, `failure_code` match. Historical nullable merchant/actor fields are intentional. New methods require a merchant; historical unbound methods remain locally removable and never resolve cleanup through current credentials. |
| `payment_subscriptions` | `managed_by` is the ownership authority; `metadata` contains informational correlation only. Billing writes `next_charge_at = NULL`, consistent with the migration check. Existing currency/cycle/agreement/token fields match. |
| `payment_methods` | `billing_customer_id`, `billing_authorized_by_id`, nullable `user_id` match the ownership CHECK and B validation. Ordinary tokens retain required users. Billing tokens are platform-owned, user-less, and tied to the purchasing customer and accepted authorizer. |
| `billing_settings` | `tax_rate_bps`, `collection_mode`, `dunning_schedule`, `grace_period_days`, `trial_ending_notice_days`, `singleton_guard` remain. `gateway_provider` is removed by A's migration and absent from B model/contract/command and current settings form/params. |
| `billing_notices` | `customer_id`, `event_key`, `kind`, `billing_invoice_id`, `billing_subscription_id`, `billing_collection_attempt_id`, `state`, `enqueued_at`, timestamps all match. |

### State and identity parity

* Invoice financial statuses: `draft/open/paid/void/uncollectible`.
* Collection states: `ready/manual/blocked/pending/requires_action/retry_wait/exhausted/settled/stopped`.
* Attempt states: `prepared/submitting/pending/requires_action/succeeded/failed/unknown`; the five nonterminal states exactly match A's one-inflight partial index.
* Method states: `pending/active/failed/removed`; revocation states: `none/pending/complete/failed`.
* Notice states: `pending/enqueued`; mandate ownership: `payments/billing`.
* Permanent invoice/method request indexes, proration-change uniqueness, coupon-cycle uniqueness, ordinal/payment uniqueness, authorization account/reference uniqueness, and restrictive FKs match B's callers. A's user FKs target `users`, matching `Authentication::User`.

## Resolved A/B invoice and settlement semantics

* `GenerateInvoice` returns an Invoice and reuses its immutable identity. It consumes the full accepted string-keyed snapshot; it does not fill missing policy from current settings. Required plan keys are A's `PlanChangePolicy::PLAN_KEYS`, plus `tax_rate_bps`, `collection_mode`, `dunning_schedule`, and ISO8601 `due_at`. New renewals additionally require both calendar anchors.
* Initial/renewal invoices add one recurring line; proration uses only A's extra lines. A's proration source dates stay the purchased period, while its due date is the original period end. B does not substitute period start or collection execution time.
* `FinalizeInvoice` takes subscription then invoice inside `Result.transaction`; A's `Discounts.reserve_for_invoice!` owns persisted coupon/cycle reservation. Discount and tax lines are added once, integer tax uses the discounted subtotal, number allocation occurs once, and invoice-issued receipt is transactional. Repeated finalization cannot change policy, lines, dates, or number. Zero settlement uses the same settlement hook.
* `MarkInvoicePaid` records the financial transition and calls A's `ApplyInvoiceSettlement` in the same transaction, including void-capture review. A's `entitlements_applied_at` is mutable projection metadata. A paid invoice lacking this receipt is redriven rather than incorrectly returning unchanged. Gateway, manual, and zero projection gaps are swept.
* Gateway paid time comes from the verified Payments record. Real late money is recorded; A decides target application/recovery versus stale/ended review. A receipt prevents a second entitlement application. Duplicate captures keep the original primary payment and produce a durable owner review notice.
* Provider preparation/outcome transactions use persisted rows, not transient target/default/authorization properties. Stable request keys equal the Payments merchant trade identity. Prepared attempts are rechecked against financial terminal status before submission. A secondary unresolved attempt is still queried after an older late capture pays the invoice.

## Provider/readiness and read-only authorization contract

* `AvailableProviders.call(customer:, currency:)` returns the frozen descriptor fields and only implemented, platform-available, configured current-mode providers. Stripe qualifies through tokenized recurring support. Alipay requires CNY and a live monthly cadence; it is not advertised as an annual authorization.
* Readiness/default eligibility uses the live stored subscription currency, or initial currency resolution when there is no live row. Invoice collection uses the invoice's frozen currency/cadence. An incompatible completed setup does not demote the prior compatible default. Nondefault methods are never silently selected for collection.
* Alipay fields are normalized to string keys/string values so C's strict provider-form validator accepts them without changing the signature. Page-sign uses the external agreement reference, stable first execution date, monthly rule, CNY ceiling, and exact method-specific server return. Sandbox billing setup/query/charge/revocation/refund/close use the sandbox endpoint; production uses the production endpoint. Ordinary nonbilling API behavior is preserved.
* Alipay ceiling includes accepted outstanding same-currency/same-cadence invoice totals; it never compares USD and CNY magnitudes. Existing authorizations are not silently increased. Frequency checks follow the mandate's accepted calendar anchor, rather than a floating 30-day assumption. Annual or incompatible ceiling/frequency collection returns `reauthorization_required`.
* `PaymentAuthorization.action_for(payment_method:, return_url:)` is a read query: Stripe retrieves only the exact existing correlated intent/customer and returns an interactive action if appropriate. It cannot create/replay setup, save references/tokens, or activate. Alipay signs a read-only handoff. Neither GET activates a method.
* Confirmation and signed callbacks validate account/provider/method/customer/token/agreement correspondence, suppress general recurring scheduling, and never resurrect removed/expired methods. Trade notifications merely carrying `agreement_no` are not misclassified as agreement lifecycle events.

## Payments facade and callback integration

`Payments::Gateway` remains B-owned. The Payments agent's new `fetch_payment_method(customer:, provider:, psp_pm_id:, merchant_account: nil, historical: false)` implementation was preserved. Historical fetch can use the exact disabled signing account.

Query/refund/close accept an optional explicit merchant and reject disagreement with the committed payment account/context; they never replace it with current mode/account. Billing setup/agreement/token cleanup require the pinned platform account. New subscription collection validates both account availability and the committed payment merchant. Historical reads/revocation remain possible with a disabled account.

The Payments agent now invokes:

```ruby
Billing::PaymentAuthorization.handle_verified_event!(account:, payload:)
Billing::PaymentAuthorization.sync_payment_method!(payment_method:, verified_event:)
Billing::PaymentAuthorization.verified_event(account:, payload:)
Billing::Activities::MarkInvoicePaid.call(invoice:, payment:, source: :gateway)
```

Agreement/setup routing precedes the trade branch. `nil` means nonbilling authorization; transient `authorization_unknown/authorization_unavailable` remains retryable. B copies/freezes the verified event payload. C confirmation uses the scoped Billing method without trusting browser token hints.

## Mail, settings, and presentation integration

The generic `BillingMailer#notice` is intentional for `collection_blocked`, `collection_exhausted`, `collection_authorized`, and `settlement_review`: paired F keys exist under `billing_mailer.<kind>.subject/body`. Both locales use `number` in subjects and `number/url` in bodies. These messages use translated plain-text bodies, with owner review pointing to the owner invoice URL. Existing six notice kinds use their existing templates. Failed-attempt subject and template both use the definitive failed-attempt count; trial pricing and plan labels use stored terms. Mail locale is the purchasing customer's locale.

Current C/F code supplies compatible `charge_ready`, `ready`, `reason_key`, provider `enabled`, collection eligibility, and action descriptors. C's setup JSON preserves top-level `client_secret` and the exact scoped confirmation URL; secrets are confined to authorized no-store responses. No additional transient model properties are required.

### F-owned dead-setting cleanup still required

The actual settings component, model, contract, command, and strong params contain no provider field. To complete removal of stale dead code/copy, F must remove:

1. `app/javascript/controllers/billing_settings_controller.js` (unused former gateway-provider visibility controller) and its mirrored `spec/javascript/controllers/billing_settings_controller.test.js`, after checking registration/consumers.
2. `admin_settings.errors.validations.gateway_provider_required` from both `admin_settings` locale files.
3. `comp_billing.settings_form.gateway_provider_{label,placeholder,hint,show}` from both `comp_billing` locale files.

Historical migration/schema/audit references describe the removed field and are not runtime consumers. B does not edit F-owned JS/locales or A's deferred schema dump.

## Remaining central integration work

* A: no B migration changes requested; execute the consolidated migration and regenerate schema only during the authorized central step.
* Payments integration: verified in current source that `payments_managed` filters ordinary due selection and atomic claim; direct charge, pause/reactivation, and advancement guard `managed_by == "payments"`; billing activation writes `next_charge_at = NULL`. No remaining hook/recurring-exclusion request is open. The migration's ownership CHECK provides the final guard.
* F: complete dead-setting cleanup listed above. No new mail interpolation keys are requested.
* Historical authorization-review rows need explicit owner reconciliation; B refuses to guess their merchant/actor and never falls back to current credentials for cleanup.
* Central verification: execute the authored invoice/settlement/collector/provider/authorization specs, C/F request/component/JS suites, and provider journeys when authorized. No runtime/test/migration pass is claimed here.

Ruby syntax checks passed for this pass's 28 changed Ruby source/spec files, and `git diff --check` passed. These checks do not boot Rails or execute specs.

Matching developer billing/payments docs should reflect these settled interfaces in both locales; A/F retain their exclusive reference/customer-doc ownership.

## Final A/B deadline and recovered-disposition closure

`Billing::Invoice#collection_deadline` now delegates to A's `PlanChangePolicy.request_deadline`. Access grace remains distinct: zero-grace initial/renewal requests stay payable through their immutable period end, but pending/unpaid service still uses fallback. No accepted dates, price, state enum or schema column were added.

B's `ReconcileCollections` uses A's shared accepted-intent predicate inside subscription → invoice serialization. Only the winning draft finalization registers `Result.collect_after_commit`, which enqueues the existing `Billing::FinalizeInvoiceJob` after the outer commit. It does not introduce a second collection job or move HTTP into the callback. A's existing job already finalizes, expires overdue intent, and invokes initial collection outside transactions; unchanged repeated finalization cannot recursively enqueue itself. Zero invoices settle locally without a disposition enqueue. Daily collection may win before a queued job, but existing invoice/attempt/payment guards permit one capture in either order.

Final targeted verification used the existing schema-prepared test database at migration version `190000`:

```bash
RAILS_ENV=test TEST_DATABASE=storage/billing_b_verify.sqlite3 bundle exec rspec spec/services/billing/collection_commit_safety_spec.rb spec/services/billing/cron/reconcile_collections_spec.rb spec/models/billing/invoice_spec.rb spec/services/billing/providers/error_classification_spec.rb spec/jobs/billing/finalize_invoice_job_spec.rb spec/jobs/billing/daily_billing_job_spec.rb
```

**PASS: 23 examples, 0 failures** (15.06s). This includes a zero-grace positive initial capture two seconds after acceptance applying the original purchased period, overdue job expiry with zero payments, queueing only after a real finalization commit and not rollback, one queue event across repeated recovery, and one capture with queued-job-first and daily-batch-first execution. Existing uncertain/decline safety and A's committed finalization job regressions also passed. No full suite or subagents were run.

## Targeted full-suite failure follow-up

The original full-suite report remains a failed historical run; it was not rerun here. B's isolated follow-up fixes the shared rejection-classification bug, transaction semantics, committed-draft recovery, and financial/owner fixtures without weakening invoice immutability or authorization.

* `Collector.submit` calls `Payments::Activities::AttemptSafety.definitive_rejection?`; uncertain ApiError preserves unknown/payment/key and cannot start another capture. Query not-found also requires authoritative classification.
* Only provider-writing collection is rejected inside a caller transaction. Local unpaid manual/zero commands remain transactional; A's existing after-commit callbacks no longer fail under the nonjoinable RSpec root for manual invoices. A's Result/intent implementation was not edited.
* Draft recovery is restricted to accepted current initial/renewal/proration intent populations and idempotent finalization. Terminal and stale drafts are retained without issue or PSP submission.
* Billing fixtures enable the actual platform Stripe tender. Alipay signing uses a CNY fixture and real local RSA2 verification with unexpected HTTP blocked by WebMock; no removed `post_json` partial double is mocked.
* Settlement fixtures reuse `find_or_create_platform_owner`, retaining the owner/email uniqueness invariant. Invoice download/print fixtures establish money/currency/lines before issue, rather than modifying issued rows.
* F's invoice doubles now supply actual `Billing::Invoice.new.errors`; B did not alter model safety or F's Reform presentation implementation. ActiveModel namespace fixes remain A-owned.

### Preparation and passing evidence

Verified `storage/` before creating the isolated database. `config/database.yml` routes `TEST_DATABASE` to the named SQLite file.

```bash
RAILS_ENV=test TEST_DATABASE=storage/billing_b_verify.sqlite3 bin/rails db:schema:load
```

The broad targeted run explicitly selected 35 B/settlement/callback/invoice-fixture spec files and passed **155 examples, 0 failures** (26.86s). It did not select the full suite. The first callback run exposed eight duplicate-owner fixture failures; canonical owner reuse fixed them, and the five-file safety/callback rerun passed **36 examples, 0 failures**.

During the final focused run, another agent added the data-only `20261011190000_backfill_payment_historical_bindings.rb` while the schema snapshot retained version `184517`. The test loader stopped before examples with a pending migration. The isolated schema was reloaded; after asserting the exact test database and absence of Payments/Invoice history, its metadata was marked at that data-only version. No historical data repair or development/production migration was executed:

```bash
RAILS_ENV=test TEST_DATABASE=storage/billing_b_verify.sqlite3 bin/rails runner 'abort "unexpected database" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == "storage/billing_b_verify.sqlite3"; abort "historical rows present" if Payments::Payment.exists? || Billing::Invoice.exists?; migration = ActiveRecord::Base.connection_pool.schema_migration; migration.create_version("20261011190000") unless migration.versions.include?("20261011190000")'
```

The final focused verification passed **12 examples, 0 failures** (4.77s):

```bash
RAILS_ENV=test TEST_DATABASE=storage/billing_b_verify.sqlite3 bundle exec rspec spec/services/billing/providers/error_classification_spec.rb spec/services/billing/collection_commit_safety_spec.rb spec/services/billing/collector_spec.rb spec/services/billing/cron/reconcile_collections_spec.rb
```

The three committed-collection examples disable transactional fixtures and verify no HTTP under a caller-owned transaction, durable submitting identity visible from another connection, uncertain API recovery without a second capture, and one new recovery capture following a definitive decline. Their committed test rows are cleaned up while preserving schema/suite seeds and the prior platform availability flag. Central full-suite/PSP acceptance remains a separate gate.

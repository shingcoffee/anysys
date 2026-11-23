# Billing and historical-payment migration QA — 2026-10-11

## Result

**58 examples: 51 passed, 7 failed (exit 1).** The failures reproduce billing migration safety defects and are returned to **backend A**. They require production preflight changes; this QA lane edits specs and documentation only.

| Scope | Passed | Failed |
| --- | ---: | ---: |
| Billing lifecycle migration, actual old schema | 33 | 7 |
| Historical payment-binding migration, actual old schema | 5 | 0 |
| Existing payment-binding service/evidence matrix | 13 | 0 |

Each failing example expects `ActiveRecord::MigrationError` before schema/data mutation. The actual migration completes without raising. No failures are skipped, marked pending, or changed to accept the unsafe behavior.

## Harness and provenance

Read the existing `spec/migrate/rewrite_entity_attribute_type_rollup_to_computed_spec.rb`, the separate email/SMS migration spec and the payment agent's `spec/services/payments/historical_binding_backfill_spec.rb` before implementing the coverage.

`spec/migrate/support/legacy_migration_database.rb` reads `git show 91b89d3e:db/schema.rb` into memory, then evaluates only the 18 relevant original table definitions and their existing FKs on an independent ActiveRecord SQLite adapter. It does not evaluate the global `ActiveRecord::Schema.define` wrapper. The pinned revision has schema version `2026_10_10_130000` and predates both tested migrations. Its Git object must be present; there is no fallback to the current schema.

Each example creates and cleans up a private file under `tmp/anysys-migration-*`. Billing runs the real `exec_migration(connection, :up)` in that connection's DDL transaction. Both migration groups disable Rails transactional fixtures to prevent fixture subscription/pinning of the short-lived pool. Cleanup asserts that the RSpec application's Base pool and DB configuration retain object identity.

The payment data repair's private row classes and transaction inherit `ActiveRecord::Base`. Its exact migration code therefore runs in a forked child process connected to the same private file. Only the child's Base connection changes; the parent test process never reconnects Base. The parent observes the committed file and compares old rows/schema. No database methods are mocked. Raw inserts avoid current model validations, onboarding callbacks and authorization/provider operations; WebMock's existing network prohibition remains in force.

The two factory-based migration examples were moved out of the existing payment service spec and replaced with the stronger old-schema migration cases. The existing 13-example provider/evidence matrix is reused rather than duplicated.

The duplicate-number anomaly test deliberately removes the old invoice-number unique index before inserting imported duplicate history, then verifies preflight preserves that exact anomalous schema and rows. The ordinary old schema already rejects duplicate numbers. The sequence test deletes an **interior** numbered invoice; it does not claim an already-deleted maximum can be recovered without surviving evidence.

## Passing evidence

* Every legacy subscription financial/period/status field survives, except the intentionally removed unused mandate column. Invoice financial fields, number, payment FK and historical lines survive byte/value comparison, including signed discount and tax lines.
* Purchased USD monthly / CNY yearly amount and cadence are used even when the current catalog price/cadence differs. Reconstructed snapshots are marked; accepted service dates remain fixed.
* Sequence heads use each customer's highest surviving correctly prefixed numeric suffix, including numbered drafts. Unnumbered drafts, deleted interior numbers, gaps and another customer's prefix do not replace the maximum.
* Only explicitly linked platform mandates become Billing-owned. Their next-charge/claim fields are cleared while ordinary Payments mandates retain schedules, identity and money. Historical authorizations stay unbound and marked for review.
* Referenced archived plans/coupons retain history; real SQLite FKs reject hard deletion.
* Orphans, tenant/subscription/line mismatches, negative invoice/catalog money, unsupported currency, invalid periods, duplicate live enrollment/numbers, foreign/provider-mismatched/shared/unmapped mandates, unknown coupon cycles, unfinished collections and unprojected captures are rejected with recorded IDs and unchanged old rows/schema.
* Real SQLite constraints reject duplicate live/request identities, invoice sequences, defaults, outstanding changes, proration identities, in-flight attempts, attempt keys/ordinals, redemptions/cycles and mandate ownership links. Installed FKs are restrictive and protect new intent/authorization/attempt/notice tables.
* An exact already-paid platform capture remains linked without rewriting payment, order or invoice financial fields.
* Historical payment repair maps original verified signer/operation evidence to the retained disabled production account, adds only identity envelopes and is repeat-apply stable. Money/status/user attribution/order/trade/refund IDs/timestamps/original payloads/schema remain unchanged. Missing, ambiguous and foreign evidence reject the entire plan before partially binding a deterministic event. Both migrations refuse destructive rollback.

## Backend A handoff: required fixes

Production source: `db/migrate/20261011000100_add_billing_subscription_lifecycle.rb`.

### MIG-L1 — unpaid initial access is admitted (2 failures)

* Specs: `spec/migrate/add_billing_subscription_lifecycle_spec.rb:276–280`, examples `[1:31]` and `[1:33]`.
* Fixture: subscription **20**, purchaser **4001**, positive purchased amount **1234 USD minor units**, status `active`, nontrial; only initial invoice **30**, manual, positive total **1207**, status `open` or `uncollectible`, no paid time/payment/capture evidence.
* Actual: `report` returns `{}`; `up` succeeds. `backfill` at lines 224–254 retains active purchased snapshot/limits without settlement evidence.
* Required: report the unresolved subscription ID and refuse before DDL. Reconcile the original financial/access intent with authoritative evidence; an open manual invoice is not proof of payment. Proposed finding key: `unpaid_active_initial_intents`.
* This is the existing A audit's MIG-L1, now reproduced on the pre-migration schema.

### MIG-L2 — unpaid proration without a target is admitted (2 failures)

* Specs: `spec/migrate/add_billing_subscription_lifecycle_spec.rb:282–287`, examples `[1:32]` and `[1:34]`.
* Fixture: paid base invoice **30** plus manual invoice **31**, positive total **1207**, status `open` or `uncollectible`, with a `proration` line; the legacy schema contains no permanent PlanChange/target intent.
* Actual: `report` returns `{}`; `up` succeeds. Backfill at lines 242–254 identifies purpose `proration` but creates no target/PlanChange.
* Required: report invoice **31** and refuse before DDL. Preserve financial evidence and require explicit target/access reconciliation, rather than inferring an upgrade or a paid entitlement. Proposed finding key: `unresolved_proration_intents`.
* This is the existing A audit's MIG-L2, now reproduced on the pre-migration schema.

### MIG-FK1 — existing financial FKs are mistaken for valid settlement evidence (3 failures)

* Specs: `spec/migrate/add_billing_subscription_lifecycle_spec.rb:264–274`, examples `[1:28]`, `[1:29]`, `[1:30]`.
* Fixture: paid invoice **30** (`USD`, total **1207**) explicitly links payment **90** / order **80** / reference `billing-inv-30`. Each negative case changes one fact: payment and order belong to **4002**, not platform **81721200**; or captured/order amount is **99.99**, not **12.07**; or order currency is **CNY**, not **USD**. All old parent FKs still resolve.
* Actual: `report` returns `{}`; `up` succeeds. The orphan check at lines 13–23 verifies existence only; `unprojected_captures` at line 45 excludes already-paid invoices; backfill at line 253 gives the paid invoice an entitlement projection receipt.
* Required: validate the existing link's platform payment/order ownership, exact order-to-invoice correlation, captured minor-unit amount and order currency. Unknown or contradictory evidence must be reported by invoice/payment ID and refused, not repaired by guessing another payment. Proposed finding key: `invoice_payment_mismatch` (invoice **30**). Keep the exact valid binding positive case passing.

These fixtures are synthetic reproductions. QA makes no claim that any of these records/shapes exist in a live customer database. Source line numbers refer to the migration read for this run.

## Commands and actual results

Parent `storage/` and `tmp/` were verified before database creation. The isolated Rails test schema was loaded with:

```bash
RAILS_ENV=test TEST_DATABASE=storage/migration_verify.sqlite3 bundle exec rails db:schema:load
```

Exit **0**. This loads the ordinary Rails test DB; legacy migration examples independently reconstruct the pinned old schema in private files.

Final targeted run:

```bash
TEST_DATABASE=storage/migration_verify.sqlite3 bundle exec rspec \
  spec/migrate/add_billing_subscription_lifecycle_spec.rb \
  spec/migrate/backfill_payment_historical_bindings_spec.rb \
  spec/services/payments/historical_binding_backfill_spec.rb \
  --format documentation --order random --seed 81721200
```

Exit **1**; **58 examples, 7 failures**, in **63.88 seconds** (load: **4.22 seconds**). All seven failures are the three backend findings above; actual failure text is `expected ActiveRecord::MigrationError ... but nothing was raised`.

Ruby compilation check:

```bash
bundle exec ruby -e 'ARGV.each { |path| RubyVM::InstructionSequence.compile_file(path); puts "Syntax OK: #{path}" }' \
  spec/migrate/support/legacy_migration_database.rb \
  spec/migrate/add_billing_subscription_lifecycle_spec.rb \
  spec/migrate/backfill_payment_historical_bindings_spec.rb \
  spec/services/payments/historical_binding_backfill_spec.rb
```

Exit **0**; all four files compile.

`git diff --check -- <QA spec/documentation paths>` exited **0**. Temporary migration database files were absent after the final run.

During harness development, the first run failed at Rails fixture teardown because it tried to reconnect a deleted temporary database. Disabling transactional fixtures on these isolated groups fixed that test-harness defect. A subsequent 50-example run had only the four MIG-L1/L2 failures; adding financial-FK coverage produced seven genuine failures, retained in the final run. These intermediate failures are not release verification results.

Paired English / Simplified Chinese Billing and Payments reference pages describe the harness, verified boundaries and unresolved preflight findings. Production fixes belong to backend A; this targeted QA result does not certify deployment migration safety.

## Backend A production fix and follow-up verification

The **58 examples / 7 failures** above remains the original QA evidence. Backend A fixed the production migration without changing any QA test or legacy fixture:

* `unpaid_active_initial_intents`: bulk-query active positive-price nontrial subscriptions lacking a paid non-proration base invoice. Paid manual/zero base history is valid evidence; draft default zero and absent history are not. Pending initial drafts are not promoted to active or given a paid receipt by this check.
* `unresolved_proration_intents`: refuse draft/open/uncollectible proration rows when no corresponding permanent target exists. On the post-migration report path, explicit matching change/customer/subscription/period identity is recognized; no legacy target is reconstructed from translated descriptions.
* `invoice_payment_mismatch`: bulk explicit invoice → payment → order join. Refuse missing parents, foreign payment/order ownership, wrong operation reference/currency, mismatching payment or order major-unit amounts, and paid invoices linked to nonsuccessful captures. A separate evidence entry retains invoice/payment/order IDs and reason codes. Missing PSP links on historically paid manual/zero invoices remain allowed. Decimal amounts are compared exactly in BigDecimal, with no rounding/unit conversion guess and no data repair.

`up` still calls this read-only report and raises `ActiveRecord::MigrationError` before any DDL/backfill. Existing snapshot backfill and financial columns/rows are unchanged. No runtime compatibility logic, application callbacks, guessed provider/account binding, migration schema field, or financial mutation was introduced.

After verifying `storage/` and `tmp/`, isolated setup exited **0**:

```bash
TEST_DATABASE=storage/migration_verify.sqlite3 RAILS_ENV=test bin/rails db:schema:load
```

Final migration/backfill run on the production fix:

```bash
TEST_DATABASE=storage/migration_verify.sqlite3 RAILS_ENV=test bundle exec rspec spec/migrate/add_billing_subscription_lifecycle_spec.rb spec/migrate/backfill_payment_historical_bindings_spec.rb spec/services/payments/historical_binding_backfill_spec.rb --format documentation --order random --seed 81721200
```

**Exit 0: 58 examples, 0 failures**, **66.16 seconds**, load **4.30 seconds**. Breakdown: Billing actual-old-schema **40/0**, historical payment-binding migration **5/0**, payment-binding service/evidence matrix **13/0**. The unchanged seven refusal tests now pass alongside all existing history preservation, exact valid binding, archive, uniqueness and restrictive-FK tests. An earlier follow-up run also passed 58/0 before tightening absent-history refusal; the result above is on the final code.

Then A quota/lifecycle samples ran in the same isolated Rails DB:

```bash
TEST_DATABASE=storage/migration_verify.sqlite3 RAILS_ENV=test bundle exec rspec spec/services/billing/quota_spec.rb spec/services/billing/logical_lifecycle_spec.rb spec/services/billing/lifecycle_integration_spec.rb spec/services/billing/activities/subscribe_spec.rb spec/services/billing/activities/apply_coupon_spec.rb spec/jobs/billing/finalize_invoice_job_spec.rb
```

**Exit 0: 42 examples, 0 failures**, **10.91 seconds**, load **2.68 seconds**. Independent temporary migration connections and parent pool identity assertions remain intact. No full suite, subagent, provider operation, or development/production migration was run by this follow-up. These are targeted regression results, not proof that production data contains no preflight conflicts.

## HIGH follow-up — advanced unpaid renewal window (2026-10-12)

The prior **58/0** result did not cover this reviewer finding. Source proof before this follow-up:

* `AddBillingSubscriptionLifecycle.report` accepted **any** paid non-proration invoice, with no comparison to the subscription's current period, and exempted every nonnil `trial_end` indefinitely.
* The pinned old `Billing::Cron::RenewSubscriptions.renew_active` and `renew_trialing` called `advance_period!` **before** `generate_collect`. A paid September 1–October 1 base can therefore coexist with active October 1–November 1 dates and an open manual October renewal.
* `backfill` preserved the active status/current dates and reconstructed purchased limits. `Billing::Entitlements.for` grants purchased access before `PlanChangePolicy.period_boundary`; the advanced end is November 1. `RecordInvoiceDebt` requires the renewal's start to equal that boundary, so the October 1 invoice is skipped. Runtime behavior must not compensate for this unproven migrated state.

Applied production fix: the separate read-only `unpaid_active_current_periods` finding requires a containing paid recurring interval or an exactly adjoining paid recurring chain over the **entire** stored current window, with matching subscription/tenant/currency. A partially overlapping legacy chain without intent fails closed; a proration alone cannot buy a base. Explicit current-schema purpose limits evidence to initial/renewal. Settled manual/zero cycles, paid prorations alongside paid bases, contained target windows and historical states are preserved. Both active-price checks exempt only an ongoing original trial with matching started/start and trial/end dates; retained trial history, expired original trials and not-yet-started active trials do not exempt unpaid access.

New regressions use the same pinned original schema and raw rows. The previous-paid/current-open/uncollectible/draft cases include explicitly linked Billing and ordinary Payments mandates, expired grace, absent current invoices and retained trial history. Every refusal captures executed SQL to prove **zero attempted DDL/data writes**, then compares all old rows/schema, including schedules; transaction rollback alone is not the proof. Positive cases preserve every legacy financial/date/state field and recheck the report on the migrated schema.

### Repair report instructions

Run `RAILS_ENV=production bin/rails billing:repair_report` against the intended deployment database. Save its subscription IDs and inspect stored dates/amount/trial history, same-subscription/tenant/currency invoice intervals/status/lines and explicit payment links. For `unpaid_active_current_periods`, older or partially covering payments are insufficient; unpaid advanced access is not authorized even within grace. Reconcile the original settlement/access intent from owner-reviewed authoritative evidence, preserving debt/history. There is no apply mode, automatic date rollback, status/financial rewrite or guessed provider/account/target. Resolve all report findings and rerun before migration; `up` repeats preflight before mutation. The paired Billing reference pages carry the same procedure.

### Single targeted verification and precise evidence

Verified `storage/`, `tmp/` and `/tmp/opencode/` before creation and rejected a symlink at the target database path. Setup exited **0**:

```bash
test ! -L storage/migration_final_verify.sqlite3 && env \
  -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER \
  -u SETTINGS_BROWSER_FIXTURES -u EXPORT_CUSTOMER_SETTINGS_FIXTURES \
  -u E2E_STUB_ASSISTANT -u COVERAGE -u ACTIVE_STORAGE_ROOT \
  -u APP_HOST -u APP_PORT -u PORT -u E2E_BASE_URL \
  RAILS_ENV=test TEST_DATABASE=storage/migration_final_verify.sqlite3 \
  bin/rails db:schema:load
```

The Rails probe confirmed test environment, exact `storage/migration_final_verify.sqlite3`, schema version **20261011190000**, test storage root `/home/ec2-user/anysys/tmp/storage`, and no DATABASE_URL/SKIP_AUTH/worker/browser-fixture override. An initial overly strict probe rejected Ruby's normal Bundler-generated RUBYOPT; the follow-up output confirmed its only value was the standard `-r.../bundler/setup`, not the inherited browser SQLite preload. Inherited RUBYOPT was unset at process launch. No storage-root cleanup or browser environment/server mutation was performed.

Exactly one targeted RSpec invocation:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER \
  -u SETTINGS_BROWSER_FIXTURES -u EXPORT_CUSTOMER_SETTINGS_FIXTURES \
  -u E2E_STUB_ASSISTANT -u COVERAGE -u ACTIVE_STORAGE_ROOT \
  -u APP_HOST -u APP_PORT -u PORT -u E2E_BASE_URL \
  RAILS_ENV=test TEST_DATABASE=storage/migration_final_verify.sqlite3 \
  bundle exec rspec \
  spec/migrate/add_billing_subscription_lifecycle_spec.rb \
  spec/migrate/backfill_payment_historical_bindings_spec.rb \
  spec/services/payments/historical_binding_backfill_spec.rb \
  --format documentation --format json \
  --out /tmp/opencode/billing-migration-final-20261012.json \
  --order random --seed 81721200
```

**Exit 0: 90 examples, 0 failures**, **2 minutes 46.3 seconds**, load **5.13 seconds**. Billing lifecycle **72/0** (original 40 + new 32), historical payment-binding migration **5/0**, existing payment evidence matrix **13/0**. The original 58-example cohort and financial-FK refusal tests remain present. JSON artifact: `/tmp/opencode/billing-migration-final-20261012.json`.

Main HIGH fixture: subscription **20**, customer **4001**, **1234 USD minor units**, active October 1–November 1; recurring invoice **30** paid September 1–October 1; manual invoice **31** covering October 1–November 1, due October 1, open/uncollectible or unissued zero-total draft. At October 12, immutable three-day grace has expired. Report output is exactly `{"unpaid_active_current_periods":[20]}`: the original initial-intent finding is absent because September was paid, while the new current-period check rejects. The real migration raises `ActiveRecord::MigrationError`; captured attempted DDL/DML statements are **[]** and all **18** legacy tables and SQLite schema definitions remain identical. Linked Billing and ordinary Payments next-charge/claim schedules remain unchanged. A separate October 2 case confirms grace itself does not authorize advanced unpaid purchased access.

Valid paid current manual/zero windows, settled proration plus paid base, contained target periods, exactly adjoining chains, ongoing original trials, paid post-trial windows, free subscriptions and historical non-active states all migrate with original financial/period/state fields retained. Partial coverage, gaps, ambiguous partial overlaps, future-only/foreign paid windows, retained trial markers, expired/not-yet-started active trials and paid-proration-only bases are refused. Positive cases also recheck the report on the actual migrated schema; explicit proration purpose is respected when imported lines omit the kind.

Ruby compilation of the migration/spec and the owned-path whitespace check passed. No full suite or subagents were used. The production fix is confined to migration/report preflight; it introduces no runtime compatibility shim.

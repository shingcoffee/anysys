# Billing A targeted verification fixes

## B coordination contract

* A supplies `Billing::PlanChangePolicy.request_deadline(invoice)`: for zero-grace initial/renewal invoices it is the accepted fixed `period_end`; otherwise immutable due-date grace. `grace_deadline` remains the **access** deadline. B's `Invoice#collection_deadline` must use `request_deadline`, so initial/renewal collection, recovery and reconciliation do not require timestamp equality when grace=0. No schema/JSON field is added.
* A's `Billing::FinalizeInvoiceJob` queues after acceptance commits, finalizes using B's exact command, resolves local expiry/projection, then calls B `CollectInvoice(trigger: :initial)` outside any transaction. The collector's production transaction prohibition remains intact.
* `Billing::Cron::FinalizeDraftInvoices.perform` is A's durable draft recovery population. It finalizes drafts synchronously (local DB only), then queues collection after commit using the original invoice/request identity. It is called before A renewal. B's 15-minute maintenance/collection orchestration should also invoke it before reconciliation/dunning, so initial/proration drafts are not dependent on subscription period-end selection. B retains sole ownership of attempts/uncertain provider operations.
* Accepted Subscribe/ChangePlan draft replays re-enqueue the same job/invoice; terminal requests never generate another charge. No queue-success marker is authoritative: committed draft rows are the recovery source.
* Shared `PlanChangePolicy.accepted_invoice?(invoice:, subscription:)` validates tenant/currency, accepted source period and outstanding target state for scanner/job/expiry finalization. B's draft reconciliation can call this same query rather than independently reconstructing intent eligibility. B still owns its financial/provider identity validation.

## Verification boundary

This pass uses only `TEST_DATABASE=storage/billing_a_verify.sqlite3`, loaded from the current schema after verifying the storage parent. Targeted runs/evidence will be appended below. The earlier 25,053-example / 442-failure full-suite report remains historical evidence; this pass will not rerun that suite.

## Implemented fixes and reviewers

* Reform-nested type coercion uses explicit `::ActiveModel::Type`; no fallback to `Reform::Form::ActiveModel::Type`.
* Coupon attachment uses the subscription's has-one creation API, updating its cached redemption as part of inventory reservation. Existing redemption inventory/cycle snapshots remain authoritative.
* Missing default catalog uses read-only deterministic `StandardPlans.starter_limits`: page=50/entity=25/member=5. A configured finite-zero default is honored. Purchased snapshots retain conservative missing-key zero and are never reloaded from edited catalog limits.
* H2: delayed zero-grace ordinary renewal can prepare at its original boundary through the next period's fixed end. Zero grace grants no unpaid access. Access deadline, positive-payment request lifetime and zero-total settlement are distinct; manual/zero regression tests avoid timestamp equality and keep accepted dates unchanged.
* H3: acceptance dispatch only queues a job, preserving the collector's real transaction guard. Committed initial/proration drafts are scanned independently of period-end renewal; accepted replay resumes the same identity. Real-commit job tests cover lost dispatch, duplicate execution, stale draft rejection and no provider collection inside a real domain transaction.
* Fixtures count actual reserved members and provisioning-owned entities, accept limits into snapshots, use the canonical owner, and construct complete PlanChange source-period snapshots. Invalid platform outer URLs remain rejected before command invocation (404); no production guard was relaxed.

## Isolated setup and concurrent migration prerequisite

```bash
ls -ld storage
TEST_DATABASE=storage/billing_a_verify.sqlite3 RAILS_ENV=test bin/rails db:schema:load
```

Both exited 0. A concurrently introduced data-only migration `20261011190000` then blocked one targeted run during `maintain_test_schema!`, before examples. The isolated database alone was synchronized, with any dump redirected outside the workspace:

```bash
ls -ld /tmp/opencode
TEST_DATABASE=storage/billing_a_verify.sqlite3 RAILS_ENV=test SCHEMA=/tmp/opencode/billing_a_verify_schema.rb bin/rails db:migrate:up VERSION=20261011190000
```

Exited 0; migration reported payments_scanned=0, events_scanned=0, unresolved=0. This was test setup, not migration behavior coverage; that lane retains migration coverage. No application migration/schema source was edited by this dispatch.

## Actual targeted evidence

All runs below use `TEST_DATABASE=storage/billing_a_verify.sqlite3 RAILS_ENV=test bundle exec rspec`. Intermediate failures are retained as evidence, not hidden or skipped.

| Run | Examples | Failures | Result |
| --- | ---: | ---: | --- |
| Initial A scope after source fixes | 226 | 4 | Old zero-fallback expectations, missing-default admission expectation, and entity factory baseline |
| A scope plus real-commit job/H2 tests | 233 | 1 | Remaining page backing-entity fixture baseline |
| Quota-root initial run | 157 | 23 | Fresh schema lacked authentication-module fixture; page/version/service examples passed |
| Quota-root after self-contained module/member fixtures | 176 | 0 | PASS |
| A-only confirmation | 233 | 0 | PASS |
| A request consumers | 141 | 1 | Invalid platform outer CID expected 403, actual protected-route 404 |
| Entity/AI root plus corrected countable request | 90 | 0 | PASS |
| **Final A + A request consumers, including strengthened job eligibility regression** | **375** | **0** | **PASS** |

Final A/consumer command (exit 0):

```bash
TEST_DATABASE=storage/billing_a_verify.sqlite3 RAILS_ENV=test bundle exec rspec spec/models/billing/{subscription,plan,plan_limit,coupon,countable_item}_spec.rb spec/services/billing/{assign_plan_limits,currency_resolver,proration,quota,onboarding,standard_plans,discounts,logical_lifecycle,lifecycle_integration,concurrent_intents}_spec.rb spec/services/billing/activities/{subscribe,change_plan,apply_coupon,cancel_subscription}_spec.rb spec/services/billing/contracts/{subscribe,change_plan,plan,coupon}_spec.rb spec/services/billing/catalog/commands_spec.rb spec/services/billing/countable/{registry,catalog_sync}_spec.rb spec/services/billing/cron/renew_subscriptions_spec.rb spec/jobs/billing/finalize_invoice_job_spec.rb spec/models/customer_spec.rb:459 spec/requests/admin/settings/billing/{subscriptions,presentation}_spec.rb spec/requests/admin/maintenance/platform/billing/{presentation,plans,coupons,countable_items}_spec.rb spec/requests/admin/settings/modules/billing/{cancellations,coupon_redemptions}_spec.rb
```

Quota-root command (exit 0, 176 examples):

```bash
TEST_DATABASE=storage/billing_a_verify.sqlite3 RAILS_ENV=test bundle exec rspec spec/requests/authentication/registrations_spec.rb:44:56:70:83:95:377 spec/requests/authentication/admin/users_spec.rb:218:224:236:242:248:653 spec/requests/admin/maintenance/entities_spec.rb:599 spec/services/pages/activities/create_from_entity_version_spec.rb spec/requests/maintenance/entity_versions_spec.rb spec/requests/admin/maintenance/pages_spec.rb
```

Entity/AI-root command (exit 0, 90 examples):

```bash
TEST_DATABASE=storage/billing_a_verify.sqlite3 RAILS_ENV=test bundle exec rspec spec/services/entity_definitions/{persist_spec.rb,assistant/processor_spec.rb} spec/services/ai_assistant/activities/reply_spec.rb:512:533:742:782:852:862 spec/services/ai_assistant/assistant/generate_page_spec.rb spec/services/ai_assistant/assistant/tools/session_spec.rb spec/requests/admin/maintenance/platform/billing/countable_items_spec.rb
```

These scopes overlap (not a full-suite aggregate). No example was skipped/deleted, no full suite/subagent was run, and gateway/provider/browser verification remains separately owned. `git diff --check` passed.

## Remaining B integration handoff

At this dispatch's final source check, B `Invoice#collection_deadline` still used due_at + grace, and B's new draft loop finalized without scheduling immediate initial collection. Required integration is the exact delegation to `PlanChangePolicy.request_deadline`, and either invocation of A's draft scanner before maintenance expiry or equivalent shared accepted-invoice validation plus job scheduling for each recovered draft. A's targeted settlement/manual/zero/job tests pass; this report does **not** claim zero-grace positive gateway collection is integrated until that B change is present and verified. B owns provider uncertainty/retry correctness.

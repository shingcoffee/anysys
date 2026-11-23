# Test Suite Speedup: 6 min → ≤3 min

**Date:** 2026-07-15
**Status:** Approved design, pending implementation plan

## Goal

Reduce the full-suite wall time of `bin/rails parallel:spec` from ~6 minutes to
**≤3:00**, deterministically green, with software-only changes on the current
4-core box (parallelism is already maxed at 4 workers).

## Acceptance criteria

- `bin/rails parallel:spec` completes in ≤3:00 wall clock.
- 0 failures, verified by **two consecutive green runs** at the final phase.
- No new order dependencies: the single-process order-dependent failure count
  (~22 known, pre-existing) does not grow.
- All measurements taken from real timed runs, serialized (never two spec runs
  at once — worker 1 shares `storage/test.sqlite3`).

## Measured problem profile (2026-07-15)

- ~86% of suite wall time is `factory.create` (EventProf, 2026-07).
- Each `create(:customer)` costs **~163 ms**. Rollback-wrapped benchmark
  breakdown per call:
  - `seed_reserved_roles_for_self`: **154.7 ms** — of which the
    `seed_admin_grants` loop is ~149 ms (158 `role_permissions` rows inserted
    one `create!` at a time), 3 roles `find_or_create_by!` is 5.4 ms.
  - `enable_required_feature_modules`: 8.8 ms (only `authentication` is
    required).
  - `run_billing_onboarding`: 0.6 ms (no default plan in test → no-op).
  - Bare insert without callbacks: 1.5 ms.
- Batched replacement measured: catalog build + single `insert_all!` of the
  same 158 rows = **~23 ms** → customer creation lands at ~40 ms (−75%).
- `let_it_be` adoption is incomplete: components 19/203 files,
  services 94/403, requests 65/158; **502 explicit per-example
  `create(:customer)` sites** remain, plus implicit customer creates via
  factory associations (e.g. `create(:user)`).

## Design: three phases, each gated by a timed full run

Stop at the first phase whose gate lands ≤3:00 (confirmed by a second
consecutive green run). Never apply more risk than the stopwatch justifies.

### Phase 0 — Baseline

Run `parallel:spec` once; record total wall time and per-tier times. All
subsequent gains are measured against this run, not remembered numbers.

### Phase 1 — Batch `seed_admin_grants` via `insert_all!` (production fix)

Rewrite `Roles::Operation::SeedReserved.seed_admin_grants`
(`app/concepts/roles/operation/seed_reserved.rb`) to build all grant tuples in
memory and issue **one `RolePermission.insert_all!`** instead of ~158
individual `create!` calls.

Behavior preserved exactly:

- Idempotency guard: `return if admin_role.role_permissions.exists?`.
- Platform-group skip: `group[:key] == "platform"` and
  `group[:key].start_with?("admin.maintenance.platform")`.
- `ensure Current.access_points_catalog = nil` reset.
- The exact same grant row set (subject_type, subject_key, subject_id, action
  per catalog descriptor). Existing SeedReserved specs verify content; add an
  assertion comparing the produced row set to the catalog expansion if
  coverage is thin.
- Timestamps set explicitly on the tuples.

Safety argument for bypassing validations: `RolePermission` has **no
callbacks**, only inclusion/shape validations, and the seeded rows come from
the AccessPoints catalog — the same trusted source those validations mirror.
The batched path is safe by construction; the spec assertion above pins it.

Side benefit: real customer signup/provisioning in production gets ~4× faster.

**Gate 1:** full `parallel:spec` green + timed. Expected ~3.5–4.5 min.

### Phase 2 — `let_it_be` sweep on under-covered tiers

Extend the proven conversion (model tier: 2:42 → 1:13, −55%) to the remaining
tiers, in this order (biggest file counts first):

1. `spec/services` (94/403 converted)
2. `spec/components` (19/203)
3. `spec/requests` (65/158)
4. Stragglers: `spec/models` remainder (50/77), `spec/jobs`, `spec/contracts`

Conversion rules (same as the model-tier pass):

- `let(:customer) { create(:customer, ...) }` → `let_it_be(:customer) { ... }`
  **only when the record is used read-only** as a parent/scope.
- If the shared record is mutated in place → `let_it_be(..., reload: true)`.
- Skip files that assert creation side effects or depend on per-example
  freshness.
- Where obviously safe, hoist other read-only parents in the same file
  (`user`, `entity`) too.

Process: tier-by-tier, with a green `parallel:spec` run after each tier. A
file that flakes under parallel gets its conversion **reverted individually**
— per-file granularity means a bad conversion never blocks the phase.

**Gate 2:** full `parallel:spec` green + timed. If ≤3:00 → confirm with a
second consecutive green run (this gate becomes the final one) and stop;
Phase 3 is not built.

### Phase 3 — Contingency only: per-worker shared default customer (AnyFixture)

Built **only if Gate 2 lands >3:00**, with the measurement proving it is
needed.

- `spec/support/any_fixtures.rb` seeds one fully provisioned default customer
  per worker before the suite (TestProf `AnyFixture`).
- Convert only the highest-traffic files whose `let_it_be(:customer)` is
  read-only to the shared fixture, largest first, until the gate passes.
- Random ordering stays **off**. The known state-leak gotchas (boot-time
  module seeder rows, class-level rate-limit stores) are why this is last
  resort: cross-file shared state is exactly where this suite has historically
  bitten.

**Gate 3:** full `parallel:spec` green + timed, ≤3:00, twice consecutively.

## Error handling & risks

- Any failure during a phase is triaged against the known false-failure
  catalog **before** assuming regression:
  - seeded `feature_modules` rows vs `find_or_create_by!` create-only blocks
    (check `sqlite3 storage/test.sqlite3 "select key,status from feature_modules"`),
  - rate-limit 429s leaking across request specs,
  - `SQLite3::BusyException` from accidentally concurrent runs.
- All spec runs serialized; never run `rspec` while `parallel:spec` is going.
- SimpleCov/coverage runs stay single-process (existing shim).
- If Phase 1's `insert_all!` surfaces a subtle grant-content difference, the
  pinning spec fails loudly — fix the tuple builder, not the spec.

## Out of scope

- Hardware scaling, CI sharding (software-only per user decision).
- Mocking/stubbing changes — boundary mocking is already correct, and blanket
  DB mocking would weaken the multi-tenant isolation guarantees AGENTS.md
  requires.
- Changing `enable_required_feature_modules` or `run_billing_onboarding`
  (8.8 ms + 0.6 ms — not worth the risk).
- Vitest/Playwright JS suites (not part of the 6-minute RSpec wall time).

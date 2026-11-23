# Test Suite Speedup (6 min → ≤3 min) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut `bin/rails parallel:spec` wall time from ~6 minutes to ≤3:00, deterministically green, software-only.

**Architecture:** Three measure-gated phases. Phase 1 batches the `seed_admin_grants` hot loop (158 per-row `create!` → one `insert_all!`), cutting every `create(:customer)` from ~163 ms to ~40 ms. Phase 2 sweeps `let_it_be` across the under-covered spec tiers (services, components, requests, stragglers). Phase 3 (TestProf AnyFixture per-worker shared customer) is built ONLY if the Phase 2 gate still lands >3:00. Stop at the first gate that lands ≤3:00, confirmed by a second consecutive green run.

**Tech Stack:** RSpec + parallel_tests (4 workers, SQLite per worker), test-prof (`let_it_be` already required in `spec/rails_helper.rb`), FactoryBot.

**Spec:** `docs/superpowers/specs/2026-07-15-test-suite-speedup-design.md`

---

## ⚠️ Ground rules for every task (read first)

1. **NEVER run two spec commands at once.** Worker 1 of `parallel:spec` shares `storage/test.sqlite3` with single-process `rspec`; concurrent runs cascade into `SQLite3::BusyException: database is locked` failures that look real but aren't. Wait for every run to finish before starting another.
2. **`parallel:spec` is the green signal.** Single-process full-suite runs have ~22 KNOWN order-dependent failures (platform-owner/global-registry state) — those are pre-existing, not regressions.
3. **Triage failures against the known false-failure catalog before assuming regression:**
   - Seeded `feature_modules` rows vs create-only `find_or_create_by!` blocks — check `sqlite3 storage/test.sqlite3 "select key,status from feature_modules"`.
   - Rate-limit 429s leaking across request specs (handled by `spec/support/rate_limit_reset.rb`).
   - `SQLite3::BusyException` → you violated rule 1.
4. **Do NOT `git commit`.** The user reviews the diff and commits themselves. Leave all changes in the working tree. (This overrides the usual commit-per-task pattern.)
5. Full `parallel:spec` runs take ~5–6 min — use a Bash timeout of 600000 ms.

---

### Task 0: Phase 0 — Baseline timed run

**Files:** none (measurement only)

- [ ] **Step 0.1: Ensure per-worker DBs exist**

Run: `ls storage/test.sqlite3 storage/test2.sqlite3 storage/test3.sqlite3 storage/test4.sqlite3`
If any are missing: `bin/rails parallel:prepare`

- [ ] **Step 0.2: Timed baseline run**

Run: `bin/rails parallel:spec` (timeout 600000)
Expected: final aggregate line like `12918 examples, 0 failures` and a `Took MM:SS` per tier.
Record: total wall time (the command's real elapsed time) and each tier's `Took` line into `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md`:

```markdown
# Timing log — test suite speedup

| Gate | Wall time | Failures | Notes |
|------|-----------|----------|-------|
| Phase 0 baseline | M:SS | 0 | tier times: ... |
```

If the baseline is NOT green, stop and triage per the ground rules before proceeding — the plan assumes a green start.

---

### Task 1: Phase 1 — Characterization (pin) spec for the admin grant set

Pins the exact grant tuples the current per-row implementation produces, so the `insert_all!` rewrite in Task 2 must reproduce them byte-for-byte.

**Files:**
- Modify: `spec/concepts/roles/operation/seed_reserved_spec.rb`

- [ ] **Step 1.1: Add the pin spec**

Append inside the existing `RSpec.describe Roles::Operation::SeedReserved do` block (after the last existing example):

```ruby
  it "seeds exactly the catalog's non-platform grant tuples for the admin role" do
    roles = described_class.call(customer: customer)
    admin_role = roles.find { |r| r.key == "admin" }

    Current.access_points_catalog = nil
    catalog = AccessPoints::Catalog.for(customer_id: customer.id)
    expected = catalog.groups.flat_map do |group|
      next [] if group[:key] == "platform" || group[:key].start_with?("admin.maintenance.platform")

      group[:descriptors].flat_map do |d|
        d.actions.map { |action| [d.subject_type, d.subject_key, d.subject_id, action.to_s] }
      end
    end
    Current.access_points_catalog = nil

    actual = admin_role.role_permissions.pluck(:subject_type, :subject_key, :subject_id, :action)
    expect(actual.size).to eq(expected.size)
    expect(actual.sort_by(&:to_s)).to eq(expected.sort_by(&:to_s))
    expect(admin_role.role_permissions.where(created_at: nil).count).to eq(0)
  end
```

- [ ] **Step 1.2: Run the spec file — must PASS against the CURRENT implementation**

Run: `bundle exec rspec spec/concepts/roles/operation/seed_reserved_spec.rb`
Expected: 5 examples, 0 failures. (This is a characterization test — it passes before AND after the rewrite. If it fails now, the expected-tuple builder doesn't mirror the production loop; fix the spec, not production.)

---

### Task 2: Phase 1 — Rewrite `seed_admin_grants` with one `insert_all!`

**Files:**
- Modify: `app/concepts/roles/operation/seed_reserved.rb` (the `seed_admin_grants` method, currently lines 38–59)
- Test: `spec/concepts/roles/operation/seed_reserved_spec.rb` (from Task 1)

- [ ] **Step 2.1: Replace the method body**

Replace the entire `self.seed_admin_grants` method with:

```ruby
      # Seed grants for admin role from the access-points catalog.
      # Idempotent — skips if grants already exist.
      #
      # Grants are bulk-inserted in a single statement: the catalog is the
      # trusted source the RolePermission validations mirror, and the model
      # has no callbacks, so bypassing per-row AR instantiation is safe and
      # ~6x faster (the dominant cost of provisioning a customer).
      #
      # @param customer [Customer]
      # @param admin_role [Role]
      def self.seed_admin_grants(customer, admin_role)
        return if admin_role.role_permissions.exists? # idempotent

        Current.access_points_catalog = nil
        catalog = AccessPoints::Catalog.for(customer_id: customer.id)
        now = Time.current
        rows = catalog.groups.flat_map do |group|
          next [] if group[:key] == "platform" || group[:key].start_with?("admin.maintenance.platform") # skip platform-only routes

          group[:descriptors].flat_map do |d|
            d.actions.map do |action|
              {
                role_id:      admin_role.id,
                subject_type: d.subject_type,
                subject_key:  d.subject_key,
                subject_id:   d.subject_id,
                action:       action.to_s,
                created_at:   now,
                updated_at:   now
              }
            end
          end
        end
        RolePermission.insert_all!(rows) if rows.any?
      ensure
        Current.access_points_catalog = nil
      end
```

Notes for the implementer:
- Keep the method under the same `class << self`-style definition as now (it is `def self.seed_admin_grants`).
- `insert_all!` bypasses validations by design; the DB check constraint (`subject_key IS NOT NULL OR subject_id IS NOT NULL`) plus the Task 1 pin spec guard content. Timestamps are set explicitly because `insert_all!` does not run AR timestamping callbacks.
- The `if rows.any?` guard matters: `insert_all!([])` raises `ArgumentError`.

- [ ] **Step 2.2: Run the pinned spec file — must PASS**

Run: `bundle exec rspec spec/concepts/roles/operation/seed_reserved_spec.rb`
Expected: 5 examples, 0 failures. If the pin spec fails, fix the tuple builder in production code — do NOT loosen the spec.

- [ ] **Step 2.3: Benchmark — confirm the ~4× customer-creation win**

Write `/tmp/copilot-1000/-home-ec2-user-anysys/bb274f38-49b4-4b7c-9548-7b1e7aa2e839/scratchpad/bench_after.rb`:

```ruby
require "benchmark"
ActiveRecord::Base.transaction do
  FactoryBot.create(:customer) # warm-up
  n = 10
  t = Benchmark.realtime { n.times { FactoryBot.create(:customer) } }
  puts format("create(:customer): %.1f ms/call", t / n * 1000)
  raise ActiveRecord::Rollback
end
```

Run: `RAILS_ENV=test bin/rails runner /tmp/copilot-1000/-home-ec2-user-anysys/bb274f38-49b4-4b7c-9548-7b1e7aa2e839/scratchpad/bench_after.rb`
Expected: ≤ ~50 ms/call (baseline was 163.1 ms/call). If it's still >100 ms, the batched path isn't being hit — debug before proceeding.

- [ ] **Step 2.4: Run the adjacent role specs**

Run: `bundle exec rspec spec/concepts/roles spec/concepts/role_grants spec/concepts/role_permissions spec/concepts/user_roles spec/models/role_spec.rb`
Expected: 0 failures.

---

### Task 3: Gate 1 — timed full run

**Files:**
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (append row)

- [ ] **Step 3.1: Full timed run**

Run: `bin/rails parallel:spec` (timeout 600000)
Expected: 0 failures. Record wall time in the timing log as `Gate 1`.

- [ ] **Step 3.2: Evaluate the gate**

- If wall time ≤3:00 → run `bin/rails parallel:spec` once more (confirmation run); if green and ≤3:00, record it, SKIP Tasks 4–8, and go to Task 9 (wrap-up).
- If >3:00 → proceed to Task 4.
- If failures appear: triage per ground rules; genuine regressions from the Phase 1 diff must be fixed before proceeding.

---

## Phase 2 — `let_it_be` sweep

**The conversion recipe (applies to Tasks 4–7).** For each candidate spec file:

1. Candidate = file has `let(:customer) { create(:customer` (or other parent records — `user`, `entity` — created per-example and used read-only).
2. Verify the record is **read-only** in the file: no `customer.update`/`update!`/`destroy`/attribute-write, no `expect { ... }.to change { Customer.count }` (or the equivalent for the hoisted record), no reliance on per-example creation side effects (e.g. asserting provisioning callbacks fired).
3. Convert:

```ruby
# BEFORE
let(:customer) { create(:customer) }
let(:user)     { create(:user, customer: customer) }

# AFTER
let_it_be(:customer) { create(:customer) }
let_it_be(:user)     { create(:user, customer: customer) }
```

   `let_it_be` blocks run in declaration order inside a `before_all` transaction, so dependent records may reference earlier ones exactly as with `let`.
4. If the record IS mutated in place by some examples but per-example freshness is otherwise unneeded → `let_it_be(:customer, reload: true) { create(:customer) }` (reloads between examples, keeps the single INSERT).
5. If in doubt → SKIP the file. A skipped file costs ~163→40 ms per example (already improved by Phase 1); a wrong conversion costs a flake hunt.
6. Nested-context overrides (`let(:customer) { create(:customer, :enterprise) }` inside a `context`) are fine to leave as `let` — only hoist the top-level shared parent.
7. After converting a batch, run exactly the converted files: `bundle exec rspec <file1> <file2> ...` — 0 failures required. A file that fails or flakes gets its conversion **reverted individually** (restore just that file), not debugged endlessly.

**Finding candidates in a tier:**

```bash
grep -rl "let(:customer) { create(:customer" spec/<tier> | xargs grep -L "let_it_be" | sort
```

---

### Task 4: Phase 2a — sweep `spec/services` (94/403 files converted today)

**Files:**
- Modify: candidate files under `spec/services/**/*_spec.rb` (per recipe above)
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (append row)

- [ ] **Step 4.1: List candidates** (grep command from the recipe, tier = `services`)
- [ ] **Step 4.2: Convert in batches of ~20 files**, running each batch's files after conversion (`bundle exec rspec <batch files>`), reverting any failing file individually
- [ ] **Step 4.3: Tier-complete check** — run the whole tier: `bundle exec rspec spec/services` — expected 0 failures
- [ ] **Step 4.4: Full run** — `bin/rails parallel:spec` (timeout 600000), 0 failures, record wall time in the timing log as `Phase 2a`

---

### Task 5: Phase 2b — sweep `spec/components` (19/203 files converted today)

**Files:**
- Modify: candidate files under `spec/components/**/*_spec.rb` (per recipe above)
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (append row)

- [ ] **Step 5.1: List candidates** (grep command from the recipe, tier = `components`)
- [ ] **Step 5.2: Convert in batches of ~20 files**, running each batch's files after conversion, reverting any failing file individually
- [ ] **Step 5.3: Tier-complete check** — `bundle exec rspec spec/components` — expected 0 failures
- [ ] **Step 5.4: Full run** — `bin/rails parallel:spec` (timeout 600000), 0 failures, record wall time as `Phase 2b`

---

### Task 6: Phase 2c — sweep `spec/requests` (65/158 files converted today)

Request specs deserve extra care: sign-in helpers may mutate the user (session tokens, `last_sign_in_at`). If a converted file starts failing on second examples, apply `reload: true` to the mutated record or revert.

**Files:**
- Modify: candidate files under `spec/requests/**/*_spec.rb` (per recipe above)
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (append row)

- [ ] **Step 6.1: List candidates** (grep command from the recipe, tier = `requests`)
- [ ] **Step 6.2: Convert in batches of ~20 files**, running each batch's files after conversion, reverting any failing file individually
- [ ] **Step 6.3: Tier-complete check** — `bundle exec rspec spec/requests` — expected 0 failures (rate-limit 429s → see ground rule 3)
- [ ] **Step 6.4: Full run** — `bin/rails parallel:spec` (timeout 600000), 0 failures, record wall time as `Phase 2c`

---

### Task 7: Phase 2d — stragglers: `spec/models` remainder, `spec/jobs`, `spec/contracts`, `spec/concepts`

**Files:**
- Modify: candidate files under `spec/models`, `spec/jobs`, `spec/contracts`, `spec/concepts` (per recipe above)
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (append row)

- [ ] **Step 7.1: List candidates** (grep command from the recipe, one run per directory)
- [ ] **Step 7.2: Convert**, running each batch's files after conversion, reverting any failing file individually
- [ ] **Step 7.3: Tier-complete check** — `bundle exec rspec spec/models spec/jobs spec/contracts spec/concepts` — expected 0 failures
- [ ] **Step 7.4: Full run** — `bin/rails parallel:spec` (timeout 600000), 0 failures, record wall time as `Phase 2d`

---

### Task 8: Gate 2 — evaluate, and confirm if passing

**Files:**
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (append rows)

- [ ] **Step 8.1: Evaluate the latest full-run time (Phase 2d row)**

- If ≤3:00 → run `bin/rails parallel:spec` once more. If green and ≤3:00 again, record as `Gate 2 confirm`, SKIP Task 8.5 (Phase 3), go to Task 9.
- If >3:00 → proceed to Step 8.5.

- [ ] **Step 8.5 (CONTINGENCY — only if Gate 2 failed): Phase 3 — AnyFixture shared default customer**

**Files:**
- Create: `spec/support/any_fixture_customer.rb`
- Modify: highest-traffic converted spec files (largest example counts first)

Create `spec/support/any_fixture_customer.rb`:

```ruby
# frozen_string_literal: true

# One fully provisioned customer per worker process, created once before the
# suite and shared (read-only) across spec files that opt in with the
# :shared_customer tag. Last-resort speed lever — see
# docs/superpowers/specs/2026-07-15-test-suite-speedup-design.md (Phase 3).
require "test_prof/recipes/rspec/any_fixture"

RSpec.shared_context "shared customer", :shared_customer do
  before(:all) do
    @shared_customer_id = TestProf::AnyFixture.register(:default_customer) do
      FactoryBot.create(:customer, name: "Shared Default Customer")
    end.id
  end

  let(:customer) { Customer.find(@shared_customer_id) }
end

RSpec.configure do |config|
  config.after(:suite) { TestProf::AnyFixture.reset }
end
```

Opt-in conversion, highest-traffic read-only files first:

```ruby
# BEFORE
RSpec.describe Some::Thing do
  let_it_be(:customer) { create(:customer) }

# AFTER
RSpec.describe Some::Thing, :shared_customer do
```

Rules: only files where `customer` is provably read-only (stricter than `let_it_be` — leaks now cross FILES, not just examples). Convert ~20 files, run them plus a full `parallel:spec`; repeat until the run lands ≤3:00, then a confirmation run (`Gate 3` + `Gate 3 confirm` rows in the log). AnyFixture rows live OUTSIDE transactions; if a run crashes mid-suite, stale rows persist in the worker DBs — recover with `bin/rails parallel:prepare`.

---

### Task 9: Wrap-up

**Files:**
- Modify: `docs/superpowers/plans/2026-07-15-test-suite-speedup-timings.md` (final summary)
- Delete: nothing (scratchpad benchmarks are outside the repo)

- [ ] **Step 9.1: Final timing summary** — append a one-line conclusion to the timing log: which gate passed, final wall time vs the 6:00 baseline.
- [ ] **Step 9.2: Verify working tree is review-ready** — `git status` and `git diff --stat`; confirm only intended files changed (production: `seed_reserved.rb`; specs: pin spec + converted files; support file only if Phase 3 ran; docs: spec/plan/timing log). Do NOT commit — report the diff summary to the user for their review.

---

## Self-review notes (spec → plan coverage)

- Spec Phase 0 baseline → Task 0. Phase 1 batching + pin spec + preserved guards → Tasks 1–2. Gate 1 → Task 3. Phase 2 tier order services→components→requests→stragglers, per-tier green runs, per-file revert → Tasks 4–7. Gate 2 + double-run confirmation → Task 8. Phase 3 contingency-only AnyFixture → Step 8.5. Error-handling/triage catalog → ground rules. Two-consecutive-green acceptance → Steps 3.2 / 8.1 / 8.5.
- No placeholders: all code steps carry complete code; conversion recipe is fully specified once and referenced with its rules repeated per-task where they differ (Task 6's mutation caveat).
- Naming consistent: `seed_admin_grants`, `RolePermission.insert_all!`, `:shared_customer` tag, timing log path identical across tasks.
- Deviation from the skill's commit-per-task pattern is deliberate: the user's standing instruction is that they review and commit themselves (ground rule 4).

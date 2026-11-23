# RSpec Suite Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply RSpec best practices and simplify the entire spec suite (870 files, ~115k LOC) — cut duplication, improve readability, remove redundant tests, speed it up, and simplify the spec infra — without touching production code or losing coverage.

**Architecture:** Adopt `rubocop-rspec` as the objective standard + permanent guardrail. Build a shared-infra leverage layer first (auth/tenant shared contexts, factory traits, route shared examples, consolidated helpers). Then a mechanical autocorrect sweep, then an area-by-area semantic sweep, each area gated on its own specs going green. Final gate is full `parallel:spec` + coverage comparison + clean `rubocop`.

**Tech Stack:** RSpec, rspec-rails, factory_bot, rubocop + rubocop-rails-omakase + rubocop-rspec, SimpleCov (branch), parallel_tests.

**Safety invariant (applies to EVERY task):** No file under `app/`, `lib/`, `config/`, or `db/` is modified. Only `spec/**`, `Gemfile`, `Gemfile.lock`, `.rubocop.yml` change. If a spec fails because production behavior genuinely differs from the assertion, fix the spec to match production — never change production.

---

## Task 0: Tooling + coverage baseline

**Files:**
- Modify: `Gemfile` (`:development, :test` group)
- Modify: `.rubocop.yml`
- Create: `docs/superpowers/plans/coverage-baseline.txt` (artifact, git-ignored is fine but commit it for the record)

- [ ] **Step 1: Add rubocop-rspec to the Gemfile**

In `Gemfile`, inside the existing `group :development, :test do` block, after the `rubocop-rails-omakase` line, add:

```ruby
  # RSpec-specific cops [https://github.com/rubocop/rubocop-rspec]
  gem "rubocop-rspec", require: false
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: `Bundle complete`. `Gemfile.lock` now lists `rubocop-rspec`.

- [ ] **Step 3: Extend `.rubocop.yml` with the curated cop set**

Append to `.rubocop.yml` (the file already has `inherit_gem`/`inherit_mode`/`AllCops` blocks — add `require` at the top after `inherit_gem`, and the cop config at the bottom):

At the top, immediately after the `inherit_gem:` block, add:

```yaml
require:
  - rubocop-rspec
```

At the bottom of the file, add:

```yaml
# --- RSpec cops (curated; see docs/superpowers/specs/2026-06-25-rspec-suite-simplification-design.md) ---
RSpec:
  Include:
    - "spec/**/*_spec.rb"
    - "spec/support/**/*.rb"

# Lint-only, hand-fixed
RSpec/NestedGroups:
  Max: 4
RSpec/MultipleExpectations:
  Max: 4   # prefer aggregate_failures; this is a soft ceiling
RSpec/ExampleLength:
  Max: 25
RSpec/MultipleMemoizedHelpers:
  Max: 12

# Disabled to avoid thousands of cosmetic-only changes (matches existing house style)
RSpec/ContextWording:
  Enabled: false
RSpec/ExampleWording:
  Enabled: false
RSpec/MessageSpies:
  Enabled: false
RSpec/VerifiedDoubles:
  Enabled: false
RSpec/DescribeClass:
  Enabled: false   # many specs describe behavior strings ("Admin full-width default")
RSpec/SpecFilePathFormat:
  Enabled: false   # request/system specs describe URL strings, not classes
RSpec/MultipleDescribes:
  Enabled: false
```

- [ ] **Step 4: Verify rubocop loads the rspec cops without erroring**

Run: `bundle exec rubocop --only RSpec/DescribedClass spec/requests --no-color 2>&1 | tail -5`
Expected: rubocop runs and reports offenses (or none) — NOT a "unrecognized cop" / load error.

- [ ] **Step 5: Capture coverage baseline (line + branch)**

Run: `COVERAGE=1 bundle exec rspec 2>&1 | tail -20`
Then capture the SimpleCov summary:

Run: `cat coverage/.last_run.json`
Expected: JSON like `{"result":{"line":NN.N,"branch":NN.N}}`.

Save it: copy that JSON plus the example/failure counts into `docs/superpowers/plans/coverage-baseline.txt`.

> Note: this single-process full run is slow (one-time). It is the apples-to-apples baseline for the final comparison in Task 15. If pre-existing failures exist, record their count — the final run must not exceed it.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock .rubocop.yml docs/superpowers/plans/coverage-baseline.txt
git commit -m "Add rubocop-rspec + curated cop set; capture coverage baseline"
```

---

## Task 1: Shared infra — auth/tenant contexts

**Files:**
- Create: `spec/support/auth_contexts.rb`
- Test: `spec/support/auth_contexts_spec.rb` (a tiny self-test that the contexts work)

- [ ] **Step 1: Write a failing self-test for the shared contexts**

Create `spec/support/auth_contexts_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "auth shared contexts", type: :request do
  describe "as admin" do
    include_context "as admin"

    it "provides a signed-in admin and a customer" do
      aggregate_failures do
        expect(customer).to be_a(Customer)
        expect(admin.customer).to eq(customer)
        expect(admin).to be_admin
      end
    end
  end

  describe "as member" do
    include_context "as member"

    it "provides a signed-in member and a customer" do
      aggregate_failures do
        expect(member.customer).to eq(customer)
        expect(member).to be_member
      end
    end
  end

  describe "as platform owner" do
    include_context "as platform owner"

    it "provides the pinned platform owner" do
      aggregate_failures do
        expect(owner.email).to eq(::Authentication::User::PLATFORM_OWNER_EMAIL)
        expect(owner.customer_id).to eq(::Authentication::User::PLATFORM_CUSTOMER_ID)
      end
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails (contexts undefined)**

Run: `bundle exec rspec spec/support/auth_contexts_spec.rb`
Expected: FAIL — `Could not find shared context "as admin"`.

- [ ] **Step 3: Implement the shared contexts**

Create `spec/support/auth_contexts.rb`:

```ruby
# frozen_string_literal: true

# Shared contexts that replace the ~200x repeated auth/tenant boilerplate
# (`let(:customer) { create(:customer) }` + `create(:user, :role)` + `sign_in`).
#
# Usage:
#   include_context "as admin"           # => customer, admin (signed in)
#   include_context "as member"          # => customer, member (signed in)
#   include_context "as platform owner"  # => customer (platform), owner (signed in)
#
# `sign_in` is only available in request/system/controller specs (Devise test
# helpers). In other spec types the contexts still expose the records but skip
# sign-in.
RSpec.shared_context "as admin" do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  before { sign_in admin if respond_to?(:sign_in) }
end

RSpec.shared_context "as member" do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, customer: customer) }

  before { sign_in member if respond_to?(:sign_in) }
end

RSpec.shared_context "as platform owner" do
  let(:owner)    { find_or_create_platform_owner }
  let(:customer) { owner.customer }

  before { sign_in owner if respond_to?(:sign_in) }
end
```

- [ ] **Step 4: Run the self-test to confirm it passes**

Run: `bundle exec rspec spec/support/auth_contexts_spec.rb`
Expected: PASS (3 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add spec/support/auth_contexts.rb spec/support/auth_contexts_spec.rb
git commit -m "Add shared auth/tenant contexts for specs"
```

---

## Task 2: Shared infra — route authorization shared examples

**Files:**
- Create: `spec/support/shared_examples/authorized_routes.rb`

- [ ] **Step 1: Implement the shared examples**

Create `spec/support/shared_examples/authorized_routes.rb`:

```ruby
# frozen_string_literal: true

# Collapses the repeated auth-guard assertions in request specs.
#
# Usage (the including group must define `let(:path)`):
#
#   it_behaves_like "requires authentication", "/123/admin/maintenance/constants"
#   it_behaves_like "a tenant-scoped admin route", "/%<cid>s/admin/maintenance/constants"
#
# For "a tenant-scoped admin route" the path is a format string taking a
# `cid` keyword so the example can substitute another customer's id.

RSpec.shared_examples "requires authentication" do |path|
  it "redirects anonymous users to sign in" do
    get path
    expect(response).to have_http_status(:found).or have_http_status(:unauthorized)
  end
end

RSpec.shared_examples "a tenant-scoped admin route" do |path_template|
  let(:other_customer) { create(:customer) }
  let(:admin)          { create(:user, :admin, customer: create(:customer)) }

  before { sign_in admin }

  it "blocks access to another tenant's resource" do
    get format(path_template, cid: other_customer.id)
    expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
  end
end

RSpec.shared_examples "a member-only route" do |path_template|
  let(:admin) { create(:user, :admin, customer: customer) }

  it "rejects an admin on a member-only write path" do
    sign_in admin
    get format(path_template, cid: customer.id)
    expect(response).to have_http_status(:not_found)
      .or have_http_status(:forbidden)
      .or have_http_status(:found)
  end
end
```

- [ ] **Step 2: Smoke-test the new examples against one existing area**

Run: `bundle exec rspec spec/requests/admin --no-color 2>&1 | tail -5`
Expected: existing admin request specs still PASS (the new file only adds shared examples; nothing uses them yet, so this just confirms it loads without error).

- [ ] **Step 3: Commit**

```bash
git add spec/support/shared_examples/authorized_routes.rb
git commit -m "Add route authorization shared examples"
```

---

## Task 3: Shared infra — consolidate support helpers

**Files:**
- Modify: `spec/support/*.rb`

- [ ] **Step 1: Inventory and consolidate**

Review each file in `spec/support/`. Apply:
- Keep `platform_owner_helpers.rb`, `feature_module_helpers.rb`, `feature_module_registrations.rb`, `auth_view_helpers.rb`, `invocation_helpers.rb`, `webmock.rb`, `devise.rb`, `config_schemas.rb` (generated — leave as-is, excluded from rubocop).
- Ensure each helper module has a one-line purpose comment at the top (most already do).
- Delete any helper module that is no longer referenced. Verify before deleting:

Run (per candidate, e.g. InvocationHelpers): `grep -rl "stash_invocation" spec | grep -v support/ | head`
Expected: if zero references → safe to delete that helper; otherwise keep.

- [ ] **Step 2: Run the full support self-tests + a representative slice**

Run: `bundle exec rspec spec/support/auth_contexts_spec.rb spec/requests/admin --no-color 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/support
git commit -m "Consolidate spec support helpers"
```

---

## Task 4: Mechanical autocorrect sweep

**Files:**
- Modify: many `spec/**/*_spec.rb` (autocorrect only)

- [ ] **Step 1: Run safe autocorrect for the mechanical cops**

Run:
```bash
bundle exec rubocop -A --only \
  RSpec/DescribedClass,RSpec/ExpectActual,RSpec/ImplicitSubject,RSpec/ReturnFromStub,RSpec/LeadingSubject,RSpec/HooksBeforeExamples,RSpec/ScatteredLet,RSpec/EmptyLineAfterHook,RSpec/EmptyLineAfterSubject,RSpec/EmptyLineAfterExampleGroup \
  spec 2>&1 | tail -20
```
Expected: `N files inspected, M offenses corrected`.

- [ ] **Step 2: Verify the suite still passes after autocorrect**

Run: `bin/rails parallel:spec 2>&1 | tail -25`
Expected: same pass/fail count as the baseline (Task 0, Step 5). The known-flaky JS drawer system spec is the only allowed failure.

- [ ] **Step 3: If any spec broke from autocorrect, fix it**

For each new failure, inspect the autocorrected diff (`git diff <file>`) and correct by hand. `RSpec/DescribedClass` occasionally rewrites a class reference inside a string or a `described_class` where the group describes a string — revert those individual hunks.

- [ ] **Step 4: Commit**

```bash
git add -A spec
git commit -m "Mechanical rubocop-rspec autocorrect sweep"
```

---

## Tasks 5–16: Per-area semantic sweep

Each area is one task. **For every area task, follow this identical procedure** (the checklist is the spec — it is not a placeholder):

**Per-area procedure:**

1. Dispatch the `anysys-qa-engineer` sub-agent scoped to the area directory with this exact instruction set:
   - Apply the §3 checklist from the design doc: `described_class` + `subject`; `let`/`let!` over `before do @x =`; one logical assertion or wrap multiple in `aggregate_failures`; `build_stubbed`/`build` over `create` when persistence is NOT needed; nesting ≤ 4; replace inline `let(:customer) { create(:customer) }` + `create(:user, :role)` + `sign_in` with `include_context "as admin" | "as member" | "as platform owner"`; replace hand-rolled cross-tenant/auth-guard assertions with the `authorized_routes` shared examples; delete tests that only re-assert Rails/framework behavior (e.g. testing that a validation macro exists rather than its effect); flatten redundant single-child `context` wrappers.
   - HARD CONSTRAINT: do not modify any file outside `spec/`. If a spec asserts behavior that production no longer has, rewrite the spec to match production (stale-test policy).
   - When replacing `create` with `build_stubbed`, only do so where the test does not hit the DB through the record (no association reload, no querying back). When unsure, keep `create`.
2. Gate: run the area's specs.
3. Gate: run rubocop on the area.
4. Commit the area.

**Gate commands (substitute `<AREA>`):**
```bash
bundle exec rspec <AREA> --no-color 2>&1 | tail -8
bundle exec rubocop <AREA> --no-color 2>&1 | tail -8
git add -A <AREA> && git commit -m "Simplify specs: <AREA>"
```
Expected each gate: specs PASS (matching baseline for that area), rubocop reports no NEW offenses for the lint-only cops.

The areas, in dependency order:

- [ ] **Task 5:** `spec/models` (incl. `spec/models/concerns`)
- [ ] **Task 6:** `spec/concerns` + `spec/contracts` + `spec/concepts`
- [ ] **Task 7:** `spec/services/code_generators` (largest services subtree; the `"a code generator"` shared example already exists — ensure every generator spec uses `it_behaves_like "a code generator"` instead of re-asserting the interface inline)
- [ ] **Task 8:** `spec/services` (everything under services NOT in code_generators)
- [ ] **Task 9:** `spec/helpers` + `spec/lib` + `spec/config` + `spec/scripts` + `spec/migrations`
- [ ] **Task 10:** `spec/components/page_builder` + `spec/components/form_fields` + `spec/components/property_editor` (the heavily-nested component subtrees)
- [ ] **Task 11:** `spec/components` (all remaining component areas)
- [ ] **Task 12:** `spec/routing` + `spec/controllers`
- [ ] **Task 13:** `spec/requests/admin` (incl. maintenance/platform/settings/modules)
- [ ] **Task 14:** `spec/requests` (member, payments, authentication, sms, platform, email_campaigns — everything not under admin)
- [ ] **Task 15:** `spec/views` + `spec/mailers` + `spec/jobs`
- [ ] **Task 16:** `spec/system` + `spec/integration` (apply the JS-flaky exception from memory; do NOT aggressively refactor JS-driven system specs per memory `js-eslint-and-test-coverage` — limit to readability + shared contexts, no behavioral changes)

---

## Task 17: Final verification gate

- [ ] **Step 1: Full suite**

Run: `bin/rails parallel:spec 2>&1 | tail -30`
Expected: pass/fail count == baseline (Task 0). Only the known-flaky JS drawer spec may differ.

- [ ] **Step 2: Coverage comparison**

Run: `COVERAGE=1 bundle exec rspec 2>&1 | tail -5 && cat coverage/.last_run.json`
Expected: `line` and `branch` percentages are **>=** the values in `docs/superpowers/plans/coverage-baseline.txt`. If lower, a real test was deleted — investigate the diff for the offending area and restore the dropped assertion.

- [ ] **Step 3: Rubocop clean**

Run: `bundle exec rubocop spec --no-color 2>&1 | tail -10`
Expected: `no offenses detected` (or only intentionally-disabled cops).

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "Finalize RSpec suite simplification"
```

---

## Self-review notes

- **Spec coverage:** §1 cops → Task 0; §2 infra → Tasks 1–3; §3 checklist → Tasks 4–16; §4 coverage safety → Task 0 baseline + Task 17 compare; §5 staging → Tasks 5–16 ordering + Task 17 final gate. All design sections mapped.
- **No production edits:** enforced by the safety invariant header and the per-area HARD CONSTRAINT.
- **Naming consistency:** shared contexts `"as admin"`/`"as member"`/`"as platform owner"` and shared examples `"requires authentication"`/`"a tenant-scoped admin route"`/`"a member-only route"` are used with identical strings in Tasks 1, 2, and 5–16.

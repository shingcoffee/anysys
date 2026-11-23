# RSpec Suite Simplification — Design

**Date:** 2026-06-25
**Status:** Approved (autonomous execution)

## Goal

Apply RSpec best practices and simplify the entire spec suite (870 files, ~115k LOC)
across four dimensions: cut duplication, improve readability, remove redundant tests,
speed up the suite — plus refactor the spec infrastructure/helpers themselves.

Production code is NOT in scope. No behavior coverage may be lost.

## Decisions (locked)

- Adopt `rubocop-rspec` as the objective best-practices standard and permanent guardrail.
- Whole-suite sweep, executed area-by-area with per-area green gates.
- Final verification: full `bin/rails parallel:spec` + coverage comparison + clean `rubocop`.
- One known-flaky JS drawer system spec is the allowed exception under parallel load.

## 1. Objective standard — rubocop-rspec

Add `rubocop-rspec` to the `:development, :test` Gemfile group. Extend the existing
`.rubocop.yml` (already inherits `rubocop-rails-omakase`) with `require: rubocop-rspec`.

Curated cop set (tuned to this codebase, following the precedent of disabling cosmetic
cops already set in `.rubocop.yml`):

- **Autocorrectable (safe sweep):** `RSpec/DescribedClass`, `RSpec/ExpectActual`,
  `RSpec/ImplicitSubject`, `RSpec/ReturnFromStub`, `RSpec/EmptyLineAfterHook`,
  `RSpec/EmptyLineAfterSubject`, `RSpec/EmptyLineAfterExampleGroup`,
  `RSpec/LeadingSubject`, `RSpec/HooksBeforeExamples`, `RSpec/ScatteredLet`.
- **Lint-only (hand-fixed):** `RSpec/NestedGroups` (Max 4),
  `RSpec/MultipleExpectations` (allow via `aggregate_failures`),
  `RSpec/ExampleLength`, `RSpec/MultipleMemoizedHelpers`, `RSpec/LetSetup`.
- **Disabled (avoid cosmetic churn):** `RSpec/ContextWording`, `RSpec/MessageSpies`,
  `RSpec/ExampleWording`, `RSpec/VerifiedDoubles` (initially), and any cop that would
  rewrite thousands of lines for pure style.

## 2. Shared infra refactor (leverage layer — done FIRST)

- **`spec/support/auth_contexts.rb`** — shared contexts replacing ~200× repeated
  auth/tenant boilerplate:
  - `"as admin"` → `customer` + admin user + `sign_in`
  - `"as member"` → `customer` + member user + `sign_in`
  - `"as platform owner"` → builds on existing `PlatformOwnerHelpers`
  - Build on existing `PlatformOwnerHelpers` / `FeatureModuleHelpers`, do not replace.
- **Factory traits** to kill inline attribute hashes; extend the existing trait pattern
  (`users.rb` `:admin`/`:member`/`:platform_owner`) to `customers`, `roles`, and the
  billing/payment factories where inline hashes repeat.
- **Consolidate support helpers** — fold tiny single-purpose modules into coherent files,
  delete dead helpers, one-line purpose comment on each. `config_schemas.rb` stays
  excluded (generated).
- **Shared examples for repeated behavior:** `"a tenant-scoped admin route"`
  (cross-tenant 403/404), `"a member-only route"`, `"requires authentication"`.

## 3. Per-area sweep checklist

`described_class` + `subject`; `let`/`let!` over `before do @x =`; one logical assertion
or `aggregate_failures`; `build_stubbed`/`build` over `create` when persistence is not
needed; nesting ≤ 4; replace inline auth/tenant setup with §2 shared contexts; delete
tests that only re-assert framework/Rails behavior; flatten redundant `context` wrappers.

## 4. Coverage safety net

SimpleCov is already present. Capture a baseline line+branch coverage report BEFORE any
change. A refactor is "safe" only if: production code untouched, the area's specs stay
green, and line/branch coverage does not drop. This is the objective guard against
deleting a test that actually covered something.

## 5. Execution staging & verification gates

1. Infra (§2) + rubocop-rspec (§1) first, with a smoke run.
2. Sweep in dependency order, each area gated on its own specs going green:
   `models → concerns → contracts → services → helpers → components → routing →
   controllers → requests → views → mailers/jobs → system/integration`.
3. Final gate: full `bin/rails parallel:spec` + coverage comparison + `rubocop` clean.

## Out of scope

- Any change to production (`app/`, `lib/`, `config/`) code.
- Renaming examples purely for wording.
- `spec/support/config_schemas.rb` and `app/services/page_layout_templates/templates/**`.

# Targeted Simplification Refactor — Design

**Date:** 2026-07-09
**Branch:** `refactor/targeted-simplification`
**Status:** Approved

## Context

A request to "simplify the application broadly and aggressively, especially source
code that looks not professional." A two-agent survey plus direct investigation
(rubocop clean; complexity cops mapped; largest files triaged) concluded that the
codebase is **already professional** — well-factored Trailblazer/dry-rb/ViewComponent,
security-aware controllers, consistent gateway/provider hierarchies, 100% JS coverage
discipline. A broad rewrite would be net-negative churn.

The value is a **targeted set of genuine smells**, delivered behavior-preserving with
specs green in the same step. No public API changes.

### Explicitly NOT done (and why)

- **`pages/formula_evaluator/*` → dentaku:** the Ruby evaluator is a deliberate
  byte-for-byte parity mirror of `app/javascript/lib/formula_engine.js` (same 31
  Math/Logic/Text/Date functions, `{field}` token syntax, nil-on-malformed coercion).
  Dentaku's different syntax/function-set/coercion would require reimplementing all 31
  functions as custom Dentaku functions plus a `{field}` preprocessor — more code, and
  it reintroduces the exact JS↔Ruby divergence risk the mirror exists to prevent. The
  sibling evaluators use dentaku precisely because they do NOT need JS parity, so the
  "inconsistency" is justified. Hand-rolled is the correct call here.
- Large-but-clean files left untouched: `activity_generator`, `theme_resolver`,
  `customer` behavior, `versionable`, `dynamic_controller`, the payment gateways.

## Scope

### Group 1 — Correctness / security (highest value, do first)

1. **`app/services/code_generators/element_types/process/data_operations/map_value_generator.rb`**
   — replace `eval(_rule[:pattern])` emitted into generated runtime code with a safe
   `"lo..hi"` range parser (split on `..`, numeric coerce). Removes a config-supplied
   code-injection footgun. Update the paired generator spec and any golden generated-output
   fixture in the same change.

2. **`app/models/concerns/bridge_entity_management.rb`** — replace the
   `payload LIKE "%\"target_entity_id\":..%"` JSON scans with `json_extract`-based queries
   (the established pattern used in 7 other files). Split the concern into a query object
   (`BridgeEntityQuery`) + a bridge-schema builder; leave the concern as thin lifecycle glue.

3. **`app/services/condition_evaluator.rb`** — delete the dead `OPERATORS` constant,
   replace the manual `each_with_index` left-fold with `reduce`, drop the redundant bare
   `rescue` around `.to_f`.

### Group 2 — De-duplication / single source of truth

4. **`app/models/customer.rb`** — move the 130-key industry taxonomy to
   `config/industries.yml`; derive BOTH the `industry` enum and `INDUSTRY_GROUPS` from it,
   so there is one source of truth that cannot drift.

5. **`app/services/flowchart_runtime/transform_applier.rb`** — collapse the parallel
   `apply` case + `nil_passthrough?` name lists into one registry hash keyed by transform
   name (value carries the nil-passthrough flag + the transform lambda).

6. **Generator `OPERATORS` duplication** — the verbatim
   `%w[eq ne gt lt gte lte includes blank present]` in `find_in_collection_generator`,
   `partition_collection_generator`, `any_all_none_check_generator`,
   `filter_collection_generator` (plus the duplicated validation block) → one shared
   constant/mixin under `code_generators/shared`.

7. **Generator `validate_config` DSL (Tier B)** — add a small declarative validation
   helper on `BaseGenerator` (e.g. `requires "x"`, `enum "y", IN, message:`), migrate the
   generators onto it. Each generator's exact error strings and specs are preserved.

### Group 3 — Structure / readability

8. **`app/controllers/admin/maintenance/pages_controller.rb#create`** — extract the
   ~50-line template/theme/config orchestration into a `Pages::CreatePage` operation
   (Trailblazer Activity); the controller becomes thin dispatch.

9. **`app/services/dynamic_class_loader.rb`** — collapse the 6 near-identical `Class.new`
   stub builders (entity/blueprint/fallback × model/contract) into one parameterized
   stub-builder.

10. **`app/models/entity_entry.rb` (Tier B)** — collapse the 4 overlapping attribute-access
    mechanisms (runtime subclass methods, `attribute_accessor` DSL, `[]`/`[]=`,
    `method_missing`) down to one canonical path, removing the redundant ones.

## Testing & risk control

- Each item runs its **targeted specs** green before moving on (per AGENTS.md scoping).
- Cross-cutting items (#1, #7 generators; #10 entity_entry) run the broader model/generator
  spec sets; the **full suite** runs at the end via `bin/rails parallel:spec`.
- Generated-code changes (#1, #7) update generator + spec/golden output **together** — never
  one without the other (flowchart JSON compiles to Ruby via these generators).
- Execution routes through the `anysys-*` SDLC agents: backend-developer for
  models/services/generators, security-engineer for the controller extraction, qa-engineer
  for specs, then tech-lead + code-reviewer review.

## Sequencing

Group 1 → Group 2 → Group 3. Each item is independently committable so work can stop or
redirect at any boundary.

## Success criteria

- All targeted specs green; full suite green at the end.
- No behavior change observable to callers (same public methods, same error strings, same
  generated-code semantics).
- rubocop stays clean; the flagged smells are gone (no `eval` in generated code, no JSON
  `LIKE` scans, no duplicated taxonomy/operator lists, thin `#create`).

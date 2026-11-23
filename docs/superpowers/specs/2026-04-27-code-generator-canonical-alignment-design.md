# Code Generator Canonical Alignment — Design Spec

**Date:** 2026-04-27
**Author:** Copilot (with user)
**Status:** Draft for review

---

## 1. Goal

Align every code generator under `app/services/code_generators/` with the Trailblazer Railway shape demonstrated by the reference `User::Activity::Create` example. Do the same for their paired UI property-editor schemas, so the user-facing surface matches the generator contract with minimal drift.

**Canonical reference (north star):**

```ruby
module User::Activity
  class Create < Trailblazer::Activity::Railway
    step :model
    step :contract
    step :validate
    step :save

    def model(ctx, **)
      ctx[:model] = User.new
    end

    def contract(ctx, **)
      ctx[:contract] = User::Contract::Create.new(ctx[:model])
    end

    def validate(ctx, **)
      ctx[:contract].validate(ctx[:params])
    end

    def save(ctx, **)
      ctx[:contract].save
    end
  end
end
```

Every generated step method must match this shape: `(ctx, **)` signature, one responsibility per step, bracket-notation ctx reads/writes only, no inline orchestration of other steps, no build-time metadata baked into the step body.

---

## 2. Scope

### 2.1 What's in scope

All ~130 Ruby files under `app/services/code_generators/` and their 1:1 UI pairs in `app/javascript/flowchart/constants/action_configs/*.js` (17 files) + `app/javascript/flowchart/constants/schemas.js` (element-type schemas).

Four review buckets, each with its own level of change:

| Bucket | Files | Change level |
|---|---|---|
| (A) Canonical-flow step generators | `new_model`, `build_contract`, `validate_contract`, `save_model` | **Semantic rewrite** — bodies must match the canonical example; keep a small set of knobs |
| (B) Other model_operations | `update_model`, `destroy_model`, `find_model`, `query_models`, `upsert_model`, `soft_delete_model`, `clone_model`, `count_records`, `check_existence`, `pluck_fields`, `transition_state`, `batch_operation`, `bulk_import`, `aggregate_query`, `raw_sql_query` | **Semantic reshape + hygiene** — re-shape to Trailblazer-style per-step single-responsibility; remove duplicated contract/params branching (belongs in the canonical 4 steps, not here) |
| (C) Non-model step actions | ~100 files across `background`, `caching`, `communication`, `concurrency`, `data_operations`, `file_operations`, `human_workflow`, `realtime`, `resilience`, `response`, `scheduling_time`, `security`, `service_invocation`, `utility`, `validation` (other than `build_contract`/`validate_contract`) | **Hygiene sweep** — no semantic rewrite, but all checklist rules that apply to step-action generators are enforced (legacy aliases, `fetch_enum`, dead branches) |
| (D) Element-type generators | `decision`, `fork`, `join`, `loop`, `parallel_for_each`, `saga`, `signal_wait`, `start`, `end`, `subflow`, `switch`, `timer`, `transaction` | **Subset hygiene** — only rules that transfer (no legacy aliases, `fetch_enum`, validated config); signature rules don't apply (they emit class skeletons, not step methods) |

### 2.2 What's explicitly out of scope

- Runtime modules: `FlowchartRuntime::*`, `EntityEntry`, `ActivitySteps::*` — these are runtime services the generated code calls. Generators may or may not continue to emit calls into them per the checklist, but the services themselves aren't touched.
- Generator infrastructure: `BaseGenerator`, `GeneratorInterface`, `GeneratorRegistry`, `SourceAssembler`, `CodeIntrospector`, `EmissionRewriter`, `ConflictResolver`, `IoExtractor`, `MetadataDSL`, `TestRunner`, `GeneratorValidator`. The infrastructure is fine; what drifted is the content of individual generator files.
- Shared mixins under `code_generators/shared/` stay as-is **except** that `ModelAssignmentBuilder` shrinks: once the canonical 4 do their work separately, the "if ctx[:contract] ... else ... assign_attributes" fragment shouldn't be used by `update_model`/`upsert_model` anymore. It may be deleted or retained for callers that still need it — decided during the model_operations phase on the basis of who still calls it.
- Files under `app/services/page_layout_templates/templates/` — per AGENTS.md, these are ignored.

---

## 3. Non-goals / explicit anti-patterns

- **No backwards-compatibility shims.** Per AGENTS.md: "Do NOT take backward compatibility into consideration." When we remove a config key, we remove both the generator reader and the UI field in the same phase. No deprecation warnings, no silent fall-through to removed aliases.
- **No dead branches left behind** to "preserve behavior." If an enum value is removed from the UI schema, the generator's case branch for it is also removed.
- **No introduction of new legacy paths.** If a generator currently reads `config["foo"] || config["bar"]`, pick the canonical name, rename the UI field, delete the alias.

---

## 4. Audit checklist — the rubric

This is the evaluation rubric every in-scope generator is checked against. Rules marked **(M)** are machine-checkable by the audit script (Section 5); rules marked **(H)** require human judgment.

### 4.1 Step-action generator rules (applies to buckets A, B, C)

1. **(M) Signature shape.** Generated step methods have signature `def <name>(ctx, **)` — parity with the canonical example. The `generate_step_method` wrapper in `GeneratorInterface` already enforces this via template; the check is that no individual generator produces a method header outside this shape.
2. **(M) Bracket-notation ctx access.** Step body reads ctx via `ctx[:key]` or `ctx.dig(...)` only. Forbidden tokens inside `generate_body` output: `ctx.foo.bar` (dotted reads that aren't `ctx.dig`), keyword args to step methods. Writes must use `ctx[:key] = ...`.
3. **(H) Single responsibility.** Each step body does one conceptual thing. Examples of violations that will be fixed:
   - `new_model` currently creates the model AND runs contract-or-params attribute assignment (two steps of the canonical flow fused into one).
   - `save_model` currently does save + optional `touch` + optional `reload` in one step.
   - `update_model` currently emits four different full-flow shapes depending on `updateStrategy`; the "save" shape is a separate concern from the "update_columns" shape.
4. **(M) No inline multi-step orchestration.** A generated step body must not contain **more than one** `ActivitySteps::X.call(ctx, ...)` invocation, and must not mix `ActivitySteps::X.call(ctx, ...)` with other non-trivial statements in the same body. A thin-wrapper generator whose entire body is exactly `ActivitySteps::X.call(ctx, ...)` + `\ntrue` is allowed — such a generator IS the "one step = one service invocation" shape. The violation is fusing multiple orchestration calls or mixing a call with additional logic. Current violations (confirmed by repo grep):
   - `save_model_generator.rb:42` emits `ActivitySteps::SaveAll.call(ctx)` under `saveAll` strategy — fused into a `save_model` that also emits `save`/`save!`/`saveOnly` via a strategy switch, plus optional `touch`/`reload` post-ops. Violates because the body does more than delegate.
   - `validate_contract_generator.rb:68, 69, 83` emits three `ActivitySteps::*` calls in one body — routing + populate-primary + populate-associations — which is three responsibilities fused.
   If `ActivitySteps::PopulatePrimary` (or similar) is still needed after Phase 2, it becomes a dedicated narrow generator (e.g. `populate_primary_generator`) whose entire body is one call.
5. **(M) No legacy alias reads.** A generator must not read two different config keys that mean the same thing. Current violations (confirmed by grep):
   - `save_model_generator.rb:56` — `cfg["strategy"] || cfg["saveStrategy"]`
   - `destroy_model_generator.rb:57` — `cfg["strategy"] || cfg["destroyStrategy"]`
   - `batch_operation_generator.rb:41, 71` — `operationType || operation`
   - `hash_manipulate_generator.rb:72, 91, 130` — `keys || targetKeys`, `otherHashVariable || mergeSourceKey`
   - `transition_state_generator.rb:23` — `targetState || toState`
   - `acquire_lock_generator.rb:156` — `modelVariable || lockRecord`
   - `retry_with_backoff_generator.rb:140, 148` — `maxRetries || maxAttempts`, `initialDelay || baseDelay`
   - `deadline_check_generator.rb:30` — `deadlineVariable || deadlineKey`
   - `timezone_convert_generator.rb:30-32` — `sourceTimeVariable || sourceKey`, `sourceTimezone || fromTimezone`, `targetTimezone || toTimezone`
   - `barcode_generate_generator.rb:55-57` — `dataVariable || dataKey`, `barcodeFormat || symbology`, `outputFormat || format`
   - `generate_file_generator.rb:27, 50` — `fileType || format`
   - `raw_sql_query_generator.rb:30` — `outputKey || resultVar`
   - `hash_data_generator.rb:67, 143` — `salt || saltVariable`
   - `upsert_model_generator.rb:28` — `createdKey || capturedCreatedVar`
   - `authenticate_generator.rb:83` — `tokenAlgorithm || algorithm`
   - `schedule_job_generator.rb:173` — `runAt || scheduledAt`
   - `generate_id_generator.rb:110, 120` — `length || size`, `size || length`
   - `business_hours_check_generator.rb:31` — `timeVariable || timeKey`
   - `transform_generator.rb:89` — `format || dateFormat || format`
6. **(M) No build-time knobs in step bodies.** Config keys that represent author-time / build-time metadata (contract caching strategy, validate-on-build, strict-mode key filtering) must not be part of a generated step body. Current violations (in `build_contract_generator.rb` and `validate_contract_generator.rb`):
   - `cachePerClass`, `cacheContract`, `validateOnBuild` — generator emits runtime `Rails.cache.fetch(...)` lookups for what is really compile-time memoization.
   - `strictMode`, `includeWarnings`, `integratePermission` — these conflate orchestration, validation, and permission checking in one step. Under the canonical shape each is its own step (or doesn't exist).
7. **(M) Enum validation uses `fetch_enum`.** Any `%w[...].include?(...)` check that governs `generate_body` branch selection must go through `Shared::ConfigFieldReader#fetch_enum` or explicitly live in `validate_config`. Hand-rolled enum gates inside `generate_body` are forbidden.
8. **(M) `dependencies` reflects actual ctx reads.** If a generator emits `ctx[:contract]` or `ctx[:model]`, it must declare `:build_contract` or `:new_model` in `dependencies`. Script will flag bodies that reference a ctx key whose writing generator isn't in the declared dependencies.
9. **(H) Multi-tenancy: `customer_id` scoping.** Queries against `EntityEntry.build_for(ctx[:bound_entity])` must apply `.where(customer_id: ctx[:customer_id])`. New model instances must set `customer_id = ctx[:customer_id]`. Writes through contracts inherit via `contract.sync`. Human review because exceptions exist (e.g., `SanitizeInputGenerator` works on raw strings that aren't multi-tenant).

### 4.2 Element-type generator rules (bucket D)

Only a subset of 4.1 applies:

- Rule 5 (no legacy aliases) — applies.
- Rule 7 (`fetch_enum`) — applies.
- Rule 8 (`dependencies`) — applies where the element type declares `dependencies` (most don't; some do for subflow).
- Rules 1, 2, 3, 4, 6, 9 don't apply — element types emit class skeletons and branching routers, not per-step method bodies.

### 4.3 UI property-editor schema rules (applies to all buckets)

These enforce the "1:1 mirror + minimal presentational fields" contract (user choice B in brainstorming):

10. **(M) Every generator config key read corresponds to a UI field.** If the generator reads `config["foo"]`, there's a UI schema entry with `key: "foo"`. Already enforced by `scripts/audit_generator_ui.rb` — this audit continues to be the source of truth.
11. **(M) Every UI field drives a generator config key.** After cleanup, no orphan UI fields. Exception: **UI-only presentational fields** may exist: `label`, `description` (already handled at the element root via `COMMON_PROPERTIES` in `schemas.js`), plus any field whose `type` is `"display_only"` or a future marker. The audit script will treat a dedicated allowlist of presentational keys as expected orphans; everything else is a gap.
12. **(M) No legacy enum values in UI options.** If the generator's enum is `%w[strategy1 strategy2]`, the UI `options` list must not contain a third legacy value. Current example: `save_model` UI exposes `strategy: saveAll|saveOnly|save|save!` plus a legacy **text** field `saveStrategy` — both the legacy field and any stale options go.
13. **(M) `visibleWhen` references live keys/values.** After removing enum values, any `visibleWhen: { field: "X", value: "removed_value" }` is orphaned — the audit will flag these.

---

## 5. The audit script

### 5.1 Scope

New file: `scripts/audit_generators.rb`. Purpose: mechanically check rules 1, 2, 4, 5, 7, 8, 10, 11, 12, 13. Complements the existing `scripts/audit_generator_ui.rb` (which covers 10 already and provides the UI-side baseline). The two scripts coexist; `audit_generators.rb` extends the coverage to the generator-body rules.

### 5.2 Implementation approach

- Walks every file under `app/services/code_generators/element_types/`.
- For each file, loads the generator class, instantiates it with a minimal sample element (using `klass.sample_input` when available), calls `generate_body`, and analyzes the returned string.
- Rule 1 (signature): we don't need to check this per-generator — `GeneratorInterface#generate_step_method` wraps every body in `def <name>(ctx, **)`. The script asserts this wrapper is used (not that each generator produces a method header of its own).
- Rule 2 (bracket-notation ctx): scan the emitted body string for forbidden patterns. Regex for `ctx\.(?!dig\b|\[)[a-z]` matches dotted ctx reads that aren't `ctx.dig` or `ctx.[] =`. Flag matches.
- Rule 4 (no `ActivitySteps::` in bodies): simple string match for `ActivitySteps::` in the emitted body.
- Rule 5 (no legacy aliases): parse the generator source via Ripper (already a dependency used by `audit_generator_ui.rb`). Look for `config["X"] || config["Y"]` and `cfg["X"] || cfg["Y"]` patterns where both sides are string literals; flag as candidate alias. Human confirms in spec — but any generator that still has this pattern after the refactor is a violation.
- Rule 7 (`fetch_enum`): detect `%w[...].include?(...)` patterns inside methods whose name starts with `generate_` or `build_`. Flag — but allow under `validate_config` methods.
- Rule 8 (dependencies reflect ctx reads): scan emitted body for `ctx[:contract]`, `ctx[:model]`, `ctx[:routed_params]`, `ctx[:bound_entity]`, etc.; compare against `dependencies` return value. Flag mismatches.
- Rule 11 (orphan UI fields): delegate to `audit_generator_ui.rb`'s existing gap types `missing_field` (generator reads X, UI lacks X) and a new `orphan_ui_field` gap type (UI has X, generator doesn't read X), minus an allowlist. The allowlist contains UI-only presentational keys that the user accepted in brainstorming: for now, start empty; when the audit flags a legitimate presentational field, we add it to the allowlist with a comment explaining why.
- Rule 12 (no legacy enum values): for each UI `options: [...]` array, the audit script reads the generator's `fetch_enum(key, %w[...], default: ...)` call or validate_config constants and compares. Any option value not in the generator-side allowed list is flagged.
- Rule 13 (visibleWhen targets are live): cross-check each UI field's `visibleWhen.field` against other UI fields (not dangling) and `visibleWhen.value(s)` against the resolved allowed values on the target field.

### 5.3 Outputs

- Writes a YAML report to `docs/superpowers/specs/2026-04-27-generator-audit-data.yml` — same pattern as the existing audit.
- Exits with non-zero status if any actionable gap exists.
- Wired into the repo as a rake task `audit:generators` so CI can run it.

### 5.4 Baseline

The script is written in Phase 1 (before any refactor). The first run produces a baseline report showing every violation across the codebase. This baseline is checked in alongside the spec to track progress.

---

## 6. Refactor shape — what each canonical generator becomes

### 6.1 `new_model_generator.rb`

**Before:** creates the model, runs `build_model_assignment(mode: :assign, ...)`, sets `customer_id`, references `_model_class`.

**After:**
```ruby
def generate_body
  result_var = config["resultVar"] || "model"
  <<~RUBY.chomp
    ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
    true
  RUBY
end
```

Knobs kept: `resultVar`.
Knobs removed: everything else. Attribute assignment happens via the contract in `build_contract` + `validate_contract`; `new_model` doesn't run assign anymore.
`dependencies`: `[]` (this is the first step; `build_contract` depends on it, not the other way around).

**Important fix:** `new_model_generator.rb:32` currently declares `dependencies [:build_contract]`, which is **backwards** relative to the canonical example — `new_model` should come first, and `build_contract` depends on `new_model` (as it does in the canonical example where `contract` runs after `model`). `new_model_generator#dependencies` becomes `[]`, and `build_contract_generator#dependencies` becomes `[:new_model]` (which it already is — confirmed at `build_contract_generator.rb:77`). This inversion fix is part of Phase 2.

### 6.2 `build_contract_generator.rb`

**Before:** 200+ lines with `cachePerClass`, `cacheContract`, `validateOnBuild`, `typeCoercion`, `attributeMappings`, `defaultValues`.

**After:**
```ruby
def generate_body
  contract_class = fetch_with_default("contractClass", "EntityEntryContract")
  target         = fetch_with_default("resultVar", "contract")
  model_var      = fetch_with_default("modelVariable", "model")
  <<~RUBY.chomp
    ctx[:#{target}] = #{contract_class}.build_for(ctx[:bound_entity]).new(ctx[:#{model_var}])
    true
  RUBY
end
```

Knobs kept: `contractClass`, `resultVar`, `modelVariable`.
Knobs removed: `cachePerClass`, `cacheContract`, `validateOnBuild`, `typeCoercion`, `attributeMappings`, `defaultValues`. If caching or mapping is truly needed at runtime, it belongs in the `EntityEntryContract.build_for` factory, not in the generated step.
`dependencies`: `[:new_model]`.

### 6.3 `validate_contract_generator.rb`

**Before:** 170+ lines; emits `DetectAndRouteParams` + `PopulatePrimary` + `PopulateAssociations` calls; `strictMode`, `includeWarnings`, `integratePermission`, `permissionType`, two completely different body shapes for `"permission"` sub-option vs contract validation.

**After:**
```ruby
def generate_body
  contract_ref = fetch_with_default("contractRef", "contract")
  <<~RUBY.chomp
    ctx[:#{contract_ref}].validate(ctx[:params])
  RUBY
end
```

Knobs kept: `contractRef`.
Knobs removed: `strictMode`, `includeWarnings`, `integratePermission`, `permissionType`, `permissionCheck`, `policyAction`, `userExpression`, `recordExpression`, `errorVar`, `subOption`. The "permission" sub-option is **not** a validate_contract concern — it becomes a separate step-action generator if it's used (we'll check usage during the refactor phase; if unused, it's deleted).
The `ActivitySteps::DetectAndRouteParams` / `PopulatePrimary` / `PopulateAssociations` orchestration is dropped from the step body. If that routing is still needed for some flows, it becomes its own step action (`route_params`, `populate_primary`, `populate_associations`) with its own generator and its own place in the Activity composition — not fused into `validate`.
`dependencies`: `[:build_contract]`.

### 6.4 `save_model_generator.rb`

**Before:** `save`, `save!`, `saveOnly`, `saveAll` strategies; `validate`, `touch`, `returnUpdated`, `context`; `saveAll` delegates to `ActivitySteps::SaveAll.call(ctx)`; `touch` and `returnUpdated` post-ops jammed into the same step body.

**After:**
```ruby
def generate_body
  contract_ref = fetch_with_default("contractRef", "contract")
  bang         = fetch_enum("bang", %w[true false], default: "false") == "true"
  method       = bang ? "save!" : "save"
  <<~RUBY.chomp
    ctx[:#{contract_ref}].#{method}
  RUBY
end
```

Knobs kept: `contractRef`, `bang` (true → `save!`).
Knobs removed: `strategy`, `saveStrategy` (legacy), `saveAll` branch (if users still need "save all including associations," that's the separate narrow generator `save_all_model` whose entire body is `ActivitySteps::SaveAll.call(ctx)` — Phase 2 decides whether to create it based on whether `SaveAll` has actual callers), `touch` (separate `touch_model` step if needed), `returnUpdated`/`reload` (separate `reload_model` step if needed), `context` (validation context belongs in `validate_contract`, not `save`), `modelVariable` (save goes through contract, not model directly, matching the example).
`dependencies`: `[:validate_contract]`.

**Non-contract save flows:** Flows that don't use a contract (rare but possible — e.g., a save after a raw `find_model` + in-place mutation in a separate step) are served by a different narrow generator `save_raw_model` whose body is `ctx[:model].save` / `ctx[:model].save!`. Whether this generator is created in Phase 2 depends on actual usage — decided at the start of Phase 2 via `grep`.

### 6.5 Rewrite patterns for bucket B (other model_operations)

Applied consistently:

- **`update_model`.** Drop the four-way strategy split. An "update" step goes through `ctx[:contract].save` like the canonical example — the update vs create distinction is a `find_model` vs `new_model` distinction upstream, not a per-step split. Variants like `update_columns` and `update_all` become separate narrow generators (`update_columns_model`, `update_all_model`) because they bypass the contract and have a fundamentally different shape.
- **`upsert_model`.** Shrink to one method per intent: `find_or_initialize_model` (narrow), `upsert_model` (narrow, always uses Rails `.upsert`). Drop the inline "if ctx[:contract] ... else assign_attributes ... end" block — the contract-sync case goes through `validate_contract` → `save_model`, the non-contract case shouldn't need a separate upsert step. `find_or_create_by` is just `find_or_initialize` + `save`.
- **`destroy_model`.** Drop legacy `strategy`/`destroyStrategy` fallback (pick one). Drop cascade/dependent/foreignKey knobs — Rails associations already declare `dependent:` at the model level; we don't need a runtime knob to override it from a step.
- **`soft_delete_model`.** Drop the `paranoia|discard|custom` three-strategy split — pick one (custom timestamp is the most general). Drop the `deletedValueType: boolean|literal|timestamp` variant — timestamp-only.
- **`find_model`.** Drop some knobs: `lock` and `readonly` stay (they're actual Rails query knobs). `includes` stays. `where_first`/`where_many`/`find_by_bang` aliases of `find_by!` collapse to canonical names.
- **`query_models`.** Shrink drastically. `queryType: where|scope|sql` with SQL inline-execution is a footgun — SQL goes through `raw_sql_query_generator`. Scope goes through a narrow `scope_model` generator. `where` stays as the base case.
- **`batch_operation`.** Five operation types (`find_each|in_batches|each_batch|update_all|destroy_all`) become five narrow generators. One step = one thing.
- **`bulk_import`.** Keep `onDuplicateKey: skip|update`. Drop legacy `skipDuplicates` alias.
- **`clone_model`.** Keep `excludeFields`, `overrideFields`, `sourceKey`, `outputKey`. Drop `cloneAssociations`, `depth`, `deepClone`, `overrideAttributes` — over-featured.
- **`aggregate_query`.** Drop legacy dual keys (`aggregations` hash vs `aggregateFunction`+`aggregateField`) — keep the hash, delete the scalar pair.
- **`transition_state`.** Drop legacy `toState`/`targetState` alias, pick `targetState`. Drop `useStateMachine` (always use AASM if available, detect at runtime).
- **`pluck_fields`, `count_records`, `check_existence`, `raw_sql_query`, `transition_state`** — hygiene only per rules 5, 7, 8.

### 6.6 Rewrite patterns for bucket C (non-model step actions)

Per-generator detail is deferred to each phase's plan, but the pattern is uniform:

- Remove every legacy alias (rule 5 list from Section 4.1). Pick the canonical name, rename the corresponding UI field, delete the fallback.
- Replace any hand-rolled `%w[...].include?(...)` enum gate inside `generate_body` with `fetch_enum` (rule 7).
- Verify `dependencies` reflects actual ctx reads (rule 8).
- No semantic rewrite — if the generator produces 40 lines today and all the logic is legitimately one responsibility, it stays at 40 lines.

### 6.7 Element-type generators (bucket D)

Review each against rules 5, 7, 8. The Explore subagent's survey found no legacy-alias drift in this bucket; hygiene work is expected to be light. `saga_generator` will get the most review attention because it has the most config enum surface.

---

## 7. UI-side cleanup

For every generator whose config surface changes:

1. Delete UI schema entries that correspond to removed config keys.
2. Rename UI fields where the canonical name won the alias fight.
3. Prune `options` lists of removed enum values.
4. Prune `visibleWhen` clauses that reference removed keys/values.

Two UI schema sources to edit:

- `app/javascript/flowchart/constants/action_configs/*.js` (17 files) — step-action config schemas.
- `app/javascript/flowchart/constants/schemas.js` — element-type schemas.

Plus the mirror file `spec/support/config_schemas.rb` regenerates via `rake config_schemas:mirror` — re-run after each phase.

Presentational-field allowlist (per user choice B): starts empty; extended during the refactor only if a genuine UI-only convenience appears that doesn't belong in the generator contract (e.g. a help tooltip field, collapsed-group label). Each allowlisted field gets a one-line comment justifying the exception.

---

## 8. Testing strategy

- Per user choice **A1** in brainstorming: specs stay green after every phase. Each phase updates the specs for generators it touches, assertions reflecting the new canonical output. No snapshot/fixture approval workflow.
- Current baseline: **3802 examples, 0 failures** (verified 2026-04-27 via `bundle exec rspec spec/services/code_generators/ --dry-run`). Memory note `spec/services/code_generators/ has 4331 examples` is out of date and should be updated to reflect the 3802 baseline.
- When a phase removes behavior (e.g. `save_model.saveAll` strategy), the specs covering that behavior get deleted, not "relaxed." A removed feature is a removed test.
- When a phase adds a new narrow generator (e.g. splitting `batch_operation` into `find_each_model`, `in_batches_model`, etc.), the new generators get fresh specs modeled on the shape of existing ones in the same category.
- Integration-level: `spec/services/code_generators/generator_registry_spec.rb` (or equivalent) should continue to verify that every generator file under `element_types/` is discovered and registered.

---

## 9. Rollout — phase plan

C′ cadence (user choice). Each phase: generator-side refactor → UI mirror cleanup for the same generators → specs updated → audit scripts green for that slice → `rake config_schemas:mirror` re-run → commit (user reviews, manual commit).

| # | Phase | Generators / files | Estimated size |
|---|---|---|---|
| 1 | Audit script + checklist docs | write `scripts/audit_generators.rb`, write `docs/code-generators/AUTHORING_CHECKLIST.md` (mechanical rules section references the script; judgment rules in prose), emit baseline report | S |
| 2 | Canonical 4 | `new_model`, `build_contract`, `validate_contract`, `save_model` (+ UI pairs + specs) | **L** (biggest behavioral change) |
| 3 | model_operations rest | `update_model`, `destroy_model`, `upsert_model`, `soft_delete_model`, `find_model`, `query_models`, `batch_operation` (split into narrow gens), `bulk_import`, `clone_model`, `count_records`, `check_existence`, `transition_state`, `pluck_fields`, `aggregate_query`, `raw_sql_query` | **L** |
| 4 | data_operations (~25 files) | all generators under `data_operations/` (hygiene only, but highest legacy-alias density per audit) | M |
| 5 | security + resilience + concurrency | `security/*` (9), `resilience/*` (4), `concurrency/*` (2) | M |
| 6 | caching + communication + realtime + response + background + service_invocation | (~18 files) | M |
| 7 | file_operations + scheduling_time + human_workflow + utility + validation-other | (~25 files) | M |
| 8 | element_types | `decision`, `fork`, `join`, `loop`, `parallel_for_each`, `saga`, `signal_wait`, `start`, `end`, `subflow`, `switch`, `timer`, `transaction` (subset checklist) | S |
| 9 | Final gate | re-run `scripts/audit_generator_ui.rb` + `scripts/audit_generators.rb`; confirm 0 actionable gaps; update memory (3802 → final) | S |

Phases 4–7 can run in any order; they're independent categories. Phases 2 and 3 must be sequential (bucket B depends on bucket A's canonical shape being in place). Phase 1 gates everything — baseline report drives subsequent phases.

---

## 10. Risks and mitigations

- **Risk.** Silent regressions in flows that relied on build-time knobs we're deleting (e.g., a real page in use relies on `validateOnBuild: true`).
  **Mitigation.** The spec suite + manual review catches generated-code changes. For user-facing behavior, the page builder UI won't expose the removed knobs, so users can't set them — a saved value on an existing element becomes a no-op, not a crash. Any persisted config that references a removed key is silently ignored (matches AGENTS.md "do NOT take backward compatibility into consideration" — users update their flow).
- **Risk.** `ActivitySteps::SaveAll` / `DetectAndRouteParams` / `PopulatePrimary` / `PopulateAssociations` become orphaned after we stop emitting calls to them.
  **Mitigation.** They stay as runtime services (out of scope per Section 2.2). If the split into separate step-action generators (`save_all_model`, `route_params`, `populate_primary`, `populate_associations`) is needed, those generators get written in Phases 2–3 and those runtime services remain callable from the new generators' bodies. Decision is per-service: is this service actually useful? Made during the relevant phase based on current callers.
- **Risk.** Legacy-alias removal breaks persisted flowchart JSON in the DB that stores the old key names.
  **Mitigation.** Per "no backward compatibility" rule, persisted configs with legacy keys produce no-op (the generator reader simply no longer looks for them, so the value is ignored). Users resave the element and the UI writes the canonical key. No migration required.
- **Risk.** Audit script is too aggressive and flags legitimate patterns as violations.
  **Mitigation.** Rule-by-rule allowlist, documented with justification. The first baseline run is the calibration point — rules get refined before Phase 2 starts.

---

## 11. Open questions deferred to implementation phases

- Does `ActivitySteps::SaveAll` have usage outside the generator? Scan `grep -rn SaveAll app/ spec/` during Phase 2 before deleting the call site from `save_model_generator`.
- Same question for `DetectAndRouteParams`, `PopulatePrimary`, `PopulateAssociations` before Phase 2 for `validate_contract_generator`.
- Does `ModelAssignmentBuilder` have any caller left after Phase 2 and Phase 3? If not, delete the mixin. If `upsert_model_generator` still calls `build_model_assignment(mode: :payload)` for its upsert payload, the mixin stays.
- For each narrow-generator split (e.g. `batch_operation` into five), final per-generator names and directory placement are decided during Phase 3 planning.
- UI audit: are there existing presentational fields that should be grandfathered into the allowlist? First baseline run answers this.

---

## 12. Acceptance criteria

- `scripts/audit_generator_ui.rb` run produces `0 actionable gaps`.
- `scripts/audit_generators.rb` run produces `0 violations`.
- `bundle exec rspec spec/services/code_generators/` produces `0 failures` with a spec count within ±10% of the 3802 baseline (count change is expected because some generators split into narrower ones with their own specs, and some removed behaviors lose their specs).
- Spot-check: pick any model-flow page in the app, publish it, inspect the generated Ruby. Each step method is ≤ 6 lines, uses `(ctx, **)`, bracket notation, no `ActivitySteps::` calls.
- No file under `app/services/code_generators/element_types/` matches the regex `config\[".+"\]\s*\|\|\s*config\[".+"\]` (no legacy aliases remain).
- No file under `app/services/code_generators/element_types/` has an emitted body that matches rule 4's violation pattern — i.e., multiple `ActivitySteps::` invocations fused into one body, or `ActivitySteps::X.call(ctx, ...)` mixed with additional non-trivial logic in the same body. Thin-wrapper generators whose entire body is a single `ActivitySteps::` call are allowed.

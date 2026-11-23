# Flowchart Generator Deep Semantic Conformance Pass — Design

**Date:** 2026-08-05
**Status:** Approved
**Repository:** `/home/ec2-user/anysys`
**Branch:** `master`
**Entry point under review:** `/81721200/admin/maintenance/flowcharts/1/edit`

## Problem

The flowchart builder's property editor exposes configuration for every element
and every step action. A matching Ruby generator turns that configuration into
executable Activity source. The requirement is that **no gap exists between what
the property editor offers and what the generator actually honors**.

A prior refactor (Tasks 1–8, committed through `63cde76`) reported all three
audits at zero defects:

```
bundle exec ruby scripts/audit_generator_ui.rb      # 0 defects
bundle exec ruby scripts/audit_step_action_config.rb # 0 defects
bundle exec rake audit:generators                    # 0 actionable gaps
```

Those audits are **structural only**. They verify that a field declared in the
JavaScript config is referenced somewhere in the Ruby generator, and vice versa.
They cannot detect:

- a field that is read but does not change the emitted source;
- an enum option that emits identical or non-compiling source;
- emitted behavior that is wrong, unsafe, or not tenant-scoped;
- hand-rolled logic that should be a maintained gem.

Evidence that real defects survive the audits, found by reading a single
generator (`app/services/code_generators/element_types/process/caching/cache_write_generator.rb`):

- **Cross-tenant cache leakage.** `namespaced_key_literal` emits the cache key
  as a static string literal with no `customer_id` scoping. In a multi-tenant
  application every tenant shares one cache key.
- **Hand-rolled tag index with a race.** `build_tags_write` emits a
  read-modify-write cycle over `"<tag>:keys"` with no locking, so concurrent
  writes silently drop entries.
- **String gymnastics instead of a builder.** `build_write_code` ends with
  `.sub(/\n\z/, "\n").chomp + "\n"`, which is a no-op dressed up as logic.

The audits report this file as clean. Therefore the audits are not a sufficient
completion criterion, and a fresh pass must add an evidence layer they lack.

## Scope

| Surface | Count |
|---|---|
| Step-action generators | 104 across 16 categories |
| Element-type generators | 6 (`start`, `end`, `decision`, `loop`, `subflow`, `timer`) |
| Total registered generators | 110 |
| Property-editor config JS | ~8,900 lines across 16 `action_configs/*.js` files |

Category sizes: `data_operations` 32, `model_operations` 17, `security` 9,
`utility` 8, `file_operations` 7, `communication` 5, `caching` 4,
`human_workflow` 4, `resilience` 4, `scheduling_time` 3, `background` 2,
`concurrency` 2, `realtime` 2, `response` 2, `validation` 2,
`service_invocation` 1.

## Non-Goals

- No change to the flowchart canvas, connection, or layout engines.
- No change to element types already rejected by the registry (`fork`, `join`,
  `saga`, `transaction`, `parallel_for_each`, `signal_wait`, `switch`). Their
  leftover directories stay untouched unless a track proves an active code path
  reaches them.
- No backward compatibility for previously generated Activity source. Per
  `AGENTS.md`, this is treated as a brand-new application; flowcharts are
  regenerated from their definitions.
- No commits. All work is left in the worktree for human review.

## Architecture

Three phases: an evidence harness, then parallel per-category repair, then
integration and verification.

### Phase 0 — Semantic Conformance Harness

New files:

- `spec/support/generator_conformance.rb` — the harness library
- `spec/services/code_generators/generator_conformance_spec.rb` — the spec that
  drives it across the registry

The harness builds on `CodeGenerators::TestRunner`, which already compiles and
executes real emitted source, so it exercises the production emission path
rather than a parallel mock.

Four checks, each applied to every registered generator:

**1. Field-delta proof.** For each declared config field, emit source twice: once
with the field absent, once with a non-default value. Byte-identical output means
the field is decorative and is reported as a defect.

Some fields legitimately produce no source delta — for example a field that only
selects among behaviors already covered by another field, or a field consumed at
validation time rather than emission time. These must be registered in an
explicit allow-list with a written justification. The allow-list is a declared
exception, never a silent skip.

**2. Enum coverage.** Every option of every `select` in the JavaScript config
must emit compilable source, options must be mutually distinct, and any value
outside the declared set must be rejected by server-side validation before
emission.

**3. Tenant-scoping assertion.** Any emitted cache key, lock key, model query,
or filesystem path must carry customer scoping. This is the check that would
have caught the `cache_write` leak.

**4. Execution matrix.** Extends the current eight representative cases in
`spec/services/code_generators/generated_activity_execution_spec.rb` to one
success path plus one operational-failure path per category, asserting
fail-closed behavior on failure — never a success-shaped placeholder.

Phase 0 output is a defect inventory per category, which becomes each track's
work queue. Phase 0 is expected to fail loudly on first run; that failure is the
deliverable.

### Phase 1 — Seventeen parallel repair tracks

One track per action category (16), plus one for element types.

**Each track exclusively owns:**

- `app/services/code_generators/element_types/process/<category>/**`
- the matching spec directory
- `app/javascript/flowchart/constants/action_configs/<category>_actions.js`
- that file's Vitest spec

**Integrator-owned files, which no track may edit:**

- `app/services/code_generators/base_generator.rb`
- `app/services/code_generators/shared/**`
- existing `app/services/flowchart_runtime/**` facades
- `config/locales/flowchart_actions.en.yml` and `flowchart_actions.zh-CN.yml`
- `spec/support/config_schemas.rb`
- audit baseline YAML under `docs/superpowers/specs/`

Tracks **may** create new `FlowchartRuntime::*` facade files, since additive
files do not conflict.

**Request protocol.** A track needing a shared-file change — a locale key, a
modification to an existing facade, a `shared/` helper — appends a request to
`.superpowers/sdd/track-<category>-requests.md` with the exact key or diff it
needs. The integrator applies every request in Phase 2. Locale files stay
monolithic and all locale edits are serialized through the integrator; tracks
never edit them directly.

Because a track cannot add its own locale keys, it writes the intended `t(...)`
call in place and records the required `en` and `zh-CN` values in its request
file. The integrator adds the keys before verification runs.

### Phase 2 — Integration and verification

1. Integrator applies all track requests: locale keys, shared facade changes,
   `shared/` helpers.
2. Regenerate the three audit baselines.
3. Run each category's targeted specs.
4. Run the full suite: `bin/rails parallel:prepare && bin/rails parallel:spec`.
5. `npm run lint` and `npx vitest run --coverage`, requiring 100% lines and
   branches on all touched JavaScript.
6. `DRY_RUN=1 CUSTOMER_ID=81721200 bundle exec rake flowcharts:regenerate_activities`.
7. All three audits exit zero.
8. Phase 0 conformance spec passes with every remaining exception justified in
   the allow-list.

## Per-Action Review Checklist

Every action in every track is held to all nine items:

1. **Bidirectional field parity.** Every property-editor field is read by the
   generator; every field the generator reads is declared in the editor.
2. **Conditional parity.** `showIf` and visibility rules in the JavaScript match
   the generator's branching, so a hidden field never silently drives emission.
3. **Enum parity.** The editor's option list matches the generator's allow-list
   constant, with server-side rejection of out-of-range values.
4. **Semantic honoring.** Proven by the Phase 0 field-delta harness, not by
   inspection.
5. **Multi-tenancy.** Customer scoping on every cache key, lock key, query, and
   path.
6. **Injection safety.** No unsanitized interpolation into emitted Ruby; all
   identifiers pass through `IdentifierSanitizer` or an equivalent.
7. **Gems over hand-rolled code.** Hand-rolled protocol, crypto, parsing, or
   retry logic is replaced by a maintained gem behind a thin `FlowchartRuntime::*`
   facade exposing a single public interface, per `AGENTS.md`.
8. **I18n.** No hard-coded user-facing strings in Ruby or JavaScript. JavaScript
   strings are Stimulus Values with English defaults, populated from server-side
   `t(...)`. English values are byte-identical to the string they replace.
9. **Tests.** Generator spec, execution spec, and 100% Vitest lines and branches
   on touched JavaScript.

## Error Handling Policy

- Generators reject invalid configuration **before** emitting source; a partial
  or invalid activity is never persisted.
- Emitted code fails closed. An operational failure sets `_last_error` and
  returns a false outcome; it never returns a success-shaped placeholder hash.
- Validation errors surface in the property editor through localized messages in
  both `en` and `zh-CN`.

## Testing Strategy

| Layer | Command |
|---|---|
| Conformance harness | `bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb` |
| Per-category generators | `bundle exec rspec spec/services/code_generators/element_types/process/<category>` |
| Execution matrix | `bundle exec rspec spec/services/code_generators/generated_activity_execution_spec.rb` |
| Property-editor JS | `npx vitest run --coverage` |
| Full suite (Phase 2 only) | `bin/rails parallel:prepare && bin/rails parallel:spec` |

Per `AGENTS.md`, tracks run only their own targeted specs. The full suite runs
once, in Phase 2, because the change is cross-cutting.

## Risks

| Risk | Mitigation |
|---|---|
| 17 tracks collide on shared files | Strict ownership list plus the request protocol; integrator holds all shared files |
| Allow-list used to hide real defects | Every entry requires a written justification and is reviewed in Phase 2 |
| Locale serialization becomes a bottleneck | Tracks write `t(...)` calls immediately and batch key requests; integrator applies them in one pass |
| Removing a config option breaks existing flowcharts | Removal is a last resort; enrichment is the default disposition. Activities are regenerated from definitions, so no migration is required |
| Full suite regressions discovered late | Targeted specs gate every track before Phase 2 begins |

## Execution Constraints

- **Model:** Claude Opus 5 for this session and every subagent. No switching.
- **Git:** direct work on `master`. No commits; the human reviewer commits.
- **Disposition default:** enrich the generator so the option genuinely works.
  Remove an option only when the Activity architecture cannot support it, and
  document why.

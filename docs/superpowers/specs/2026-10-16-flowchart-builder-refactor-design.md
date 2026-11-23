# Flowchart builder refactor — design overview

Date: 2026-10-16
Scope: the platform-owner flowchart builder (`/81721200/admin/maintenance/flowcharts/:id/edit`), its
element and step-action property editors, the step-action code generators, and whole-flowchart code
generation (`ActivityGenerator`).

## 1. Why

A Playwright simulation of the full build journey plus five code reviews (canvas, element editors,
step-action configs, step generators, activity generation) found that simple linear flows work, but:

- **Safety holes.** `upsert_model` looks records up without customer/entity filters and re-stamps
  `customer_id` (cross-tenant write). Contract-less `update_model` lets params set internal columns.
  Eighteen config fields in seven actions plus the per-step guard condition reach emitted Ruby without
  `ExpressionSafety`. The editor's Elements tab interpolates labels into `innerHTML`.
- **Workflow-breaking editor bugs.** Template choice is ignored and the default graph has no End;
  restoring a version never reloads the canvas; every save creates a version (a fresh `created_at` in
  metadata defeats the content hash); platform-prefix saves of shared flowcharts write a tenant
  override; paste aliases properties; decision branch match values are renumbered; opening and
  cancelling the property panel marks the flowchart dirty; Backspace with a sidebar button focused
  deletes the selected element.
- **Runtime correctness.** Public submissions pass string-keyed params while generated readers use
  symbol keys; labels such as "Initialize" generate method names that crash every run; contracts for
  entities with length validators raise (`:maximum` given as Float).
- **Generated code uses Trailblazer only as a sequential runner.** Lambdas inside one step per element,
  `ctx[:_route_N]` guard lines instead of wiring (untaken branches trace as success), no-op End steps,
  no failure track, errors never surfaced, misleading header.
- **Step actions mostly fail with defaults.** Model actions treat JSON-backed entity attributes as
  columns; defaults live in four places and drifted; ~100 actions with heavy overlap; 50 generator
  I18n keys missing.

## 2. Decisions (owner, 2026-10-16)

1. **One action per Process box** (today's editor rule). Templates, the AI assistant, server
   validation and stored data are brought in line so nothing else breaks.
2. **Consolidate the step-action catalog**: merge duplicates, drop broken/inert/niche actions
   (roughly 100 → 60) and add the missing business actions.
3. **Remove the Timer element**; delayed work uses the background-job action.
4. **Cadence**: the phase plan is approved; each phase gets a written spec and plan, is implemented,
   and is summarized at the phase boundary.

## 3. Phases

| Phase | Theme | Outcome |
|---|---|---|
| 1 | Safety and correctness | Verified critical/high bugs fixed with specs; one action per box enforced end to end; templates and default graph valid; Playwright builder journey as a regression suite. |
| 2 | Generated activity | One Railway step per process box (no lambdas); real Trailblazer wiring for decisions (`Output(...) => Id(...)`, route signals), Ends (`End(:success)`, no no-op steps) and subflows (plain `Subprocess`); `fail :collect_errors` with `ctx[:errors]` surfaced to the submitter; clean header and names; correct merge data; embedded step→element map for the tracer; Timer removed; loops via back-edge wiring as a follow-up slice. |
| 3 | Step-action platform | One declarative config schema per generator (type, default, role input/output/expression/literal/enum/flag, conditional rules, I18n keys) as the single source the editor renders from; emission helpers (`read`, `assign`, `fail_with`); `FlowchartRuntime::{Step, Entries, Retry, …}`; model actions on entity JSON data; safe retry/timeout; catalog consolidation and new business actions, category by category. |
| 4 | Element property editor | Primary settings on the main tab; dead fields removed (End HTTP mode, decision branch description/index, loop accumulator on while); defaults that validate; condition builder without magic operands; simplified Decision/Loop/End/Subflow; Cancel that restores. |
| 5 | Canvas polish | Predictable placement and insert-on-edge, navigation guard everywhere, canvas-scoped shortcuts, read-only enforcement, readable nodes, de-duplicated validation, concurrency conflict (409) on save. |

Order rationale: Phase 1 removes hazards and makes the existing builder trustworthy. Phase 2 fixes
the generated-code shape and defines the error contract (`ctx[:errors]`) that Phase 3 generators
emit into. Phase 3 introduces the schema single source before consolidating the catalog, so each
action is migrated once. Phase 4 builds on the schema-driven editor. Phase 5 is polish.

## 4. Target architecture (end state)

- **Canvas → activity mapping.** Each canvas element is one Railway step (`step :<element_name>`);
  decisions are wired with explicit outputs; terminal Ends map to `End(:success)`; one
  `fail :collect_errors` step copies contract and step errors into `ctx[:errors]`. The generated class
  embeds `CANVAS = { steps: {...} }` so traces map to elements without re-running the generator.
- **Generators.** `config_schema` declares each field once; `sample_input`, editor JSON and
  validation derive from it. Generators read config only through `read(:field)` and write outputs
  only through `assign(:field, expr)`. Expected failures go through `fail_with(:code, **details)`,
  which emits a call to `FlowchartRuntime::Step.fail`.
- **Runtime helpers.** `FlowchartRuntime::Entries` owns tenant + entity scoping and JSON-aware
  entity attribute reads/writes; long inline algorithms move into small runtime modules.
- **Editor.** Element and step forms render from server-provided schema with translated labels in
  both locales, single-column layout and inline field errors.

## 5. Cross-cutting rules for every phase

- No hard-coded user-facing strings; every key in `en` and `zh-CN`; JS text via Stimulus values with
  English defaults.
- No backward-compatibility shims; stored flowcharts are migrated with a task when a format changes.
- Multi-tenant: every emitted lookup is scoped by `customer_id` and the bound entity.
- Docs: `doc/reference/{en,zh-CN}/flowchart-builder.md`, `code-generators.md` and
  `flowchart-runtime.md` updated in the same change.
- Tests: targeted RSpec per touched layer, full parallel suite for cross-cutting phases,
  `npx vitest run --coverage` at 100% lines/branches for touched JS, Playwright builder journey.
- Do not commit (project rule); changes stay in the working tree for the owner's review.

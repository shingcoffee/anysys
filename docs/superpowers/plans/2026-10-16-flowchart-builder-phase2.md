# Flowchart Builder Phase 2 (Generated Activity) Implementation Plan

**Goal:** Compile flowcharts into idiomatic Trailblazer activities: one Railway step per canvas box,
real wiring for decisions, Ends, subflows and loops, a failure track that surfaces `ctx[:errors]`,
correct merge data, and traces/diagrams driven by an element map embedded in the generated class.

**Spec:** `docs/superpowers/specs/2026-10-16-flowchart-builder-phase2-design.md` (ids A1–F below).
**Base:** working tree after Phase 1 (uncommitted, HEAD a565ed16). Phase 1 ledger:
`.superpowers/sdd/2026-10-16-flowchart-phase1/progress.md`.

**Tech stack:** Ruby 3.2.8, Rails 8.1.2, trailblazer-activity 0.17.0, dsl-linear 1.2.6,
trailblazer-developer 0.1.0, Reform 2.6.2, Stimulus, RSpec, Vitest (happy-dom), Playwright.

## Global constraints (every task)

- Do NOT run `git commit`, `git stash`, `git checkout -- <file>` or `git reset`. Other agents edit
  the same working tree in parallel. `git add -N <new file>` is allowed.
- Edit only files your task owns. Shared YAML locale files: targeted `StrReplace` edits of your own
  keys only; never rewrite a whole locale file. Re-read a shared file right before editing it.
- No hard-coded user-facing strings: new keys in `en` and `zh-CN` (identical key sets and `%{}`
  variables, idiomatic zh-CN with full-width punctuation). JS text: Stimulus Value with English
  `default:` plus server-passed `data-*-value`. Generated Ruby source (comments in emitted code) is
  locale-independent English and is not UI text.
- No backward-compatibility shims, aliases or dual code paths. Stored artifacts are regenerated
  (Task 10), so nothing reads the old generated shape.
- TDD: write or rewrite the failing spec first, watch it fail for the right reason, then implement.
  Stale specs that pinned the old generated text are rewritten to the new behaviour (never deleted
  to go green unless the behaviour is gone).
- RSpec: `TEST_ENV_NUMBER=<your number> bundle exec rspec <files>` (databases 41–49 are prepared).
- Vitest: `npx vitest run --config config/javascript/vitest.config.js <spec files>`; coverage for
  touched files: add `--coverage --coverage.include=<app file> --coverage.reporter=text`. Touched
  `app/javascript/**` files stay at 100% lines, branches and functions; no `v8 ignore` pragmas.
- Never claim tests pass without pasting real command output in the report. Report file:
  `.superpowers/sdd/2026-10-16-flowchart-phase2/task-<n>-report.md` (status DONE /
  DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT, files changed, commands with trimmed output,
  failures outside your ownership with the reason).

## Waves and ownership

| Wave | Task | Agent | TEST_ENV_NUMBER |
|---|---|---|---|
| 1 | 1 Generator core (A1–A9, D validator line) | anysys-backend-developer | 41 |
| 1 | 4 Timer removal (D) | anysys-frontend-developer | 44 |
| 1 | 6 Merge data flow (B1 Ruby, B2) | anysys-backend-developer | 46 |
| 2 | 2 Errors to the submitter + traces JSON (C4, C3 server) | anysys-security-engineer | 42 |
| 2 | 3 Tracer, diagram, class loading (C1, C2, C5) | anysys-backend-developer | 43 |
| 2 | 5 Test panel, overlay, rename parity (C3, B1 JS) | anysys-frontend-developer | — |
| 2 | 7 Loops via back-edge wiring (E1–E4) | anysys-backend-developer | 47 |
| 3 | 8 Reference docs (F) | anysys-backend-developer | 48 |
| 3 | 9 Playwright journey (F) | anysys-qa-engineer | 49 |
| 3 | 10 Verification, regeneration, release (F) | anysys-release-engineer + controller | — |

Each task is reviewed (spec compliance + code quality) before its wave closes. Final whole-branch
reviews (correctness/security and conventions) follow Wave 3.

---

### Task 1 — Generator core (A1–A9; D: `timer` unsupported in StructureValidator)

**Owns:** `app/services/activity_generator.rb`;
`app/services/activity_generator/{header_builder,name_deriver,structure_validator,graph_builder,loop_method_builder}.rb`;
new `app/services/activity_generator/wiring_planner.rb`; `app/services/flowchart_topology_analyzer.rb`;
`app/services/code_generators/element_types/{decision,end,subflow}/*_generator.rb`;
`app/services/code_generators/element_types/loop/loop_generator.rb` (interim loop path only);
new `app/services/flowchart_runtime/errors.rb`;
`app/services/flowchart_server_validator/config_validator.rb` (decision context only);
`config/locales/maint_core.{en,zh-CN}.yml` key `maint_core.flowcharts.structure_errors.multiple_outgoing`
only. Specs: `spec/services/activity_generator_*_spec.rb` (all, including loop specs for the interim
path), `spec/services/activity_generator/{header_builder,name_deriver,structure_validator,graph_builder}_spec.rb`,
new `spec/services/activity_generator/wiring_planner_spec.rb`, `spec/services/flowchart_topology_analyzer_spec.rb`,
`spec/services/code_generators/element_types/{decision,end,subflow,loop}/**`,
`spec/integration/query_count_branching_spec.rb`,
`spec/services/code_generators/{test_runner,unprobeable_field_conformance}_spec.rb` (decision examples),
`spec/requests/admin/maintenance/platform/code_generators/previews_spec.rb` (decision preview),
`spec/services/flowchart_server_validator/config_validator_spec.rb`, `spec/services/flowchart_server_validator_spec.rb`,
new `spec/services/flowchart_runtime/errors_spec.rb`, plus other specs that pin the old generated text
(`spec/models/flowchart_spec.rb`, `spec/services/flowchart_definitions/**`, `spec/tasks/**`).
Not yours: tracer, diagram, traces controller and their specs (Task 3/2) — keep
`ActivityGenerator#node_element_index` working; Task 3 removes it.

**Produces (interfaces other tasks rely on):**
- Generated shape exactly as spec A1–A9 (header text, `CANVAS` keys `steps`/`routes`/`ends` with
  symbol step keys and string element/connection ids, `Routes::<Decision>::<Branch>` signals,
  `fail :collect_errors`).
- `FlowchartRuntime::Errors.collect(ctx) → Array<String>` (spec A7).
- DecisionGenerator context: `flowchart_topology: { outgoing_branches: [{ "signal" =>
  "Routes::IsLargeOrder::Yes", "semantic" => "yes", "matchValue" => "true" }, …] }` in connection
  order; `generate_body` returns an expression evaluating to the taken signal; without topology it
  returns the condition value (boolean) or the subject value (`.to_s`). `route_index` and `_route_N`
  are gone everywhere (generator, analyzer, ConfigValidator, LoopIoPlan regex may stay for Task 7).
- `FlowchartTopologyAnalyzer#analyze` → `Result(branch_groups:)` (branches with `connection_id`,
  `label`, `match_value`; `merge_node_id`); no `node_guards`, no `decision_indices`.

**Wiring planner (A3)** — a small pure class: input = ordered step descriptors
`{ id:, element_id:, kind: :step|:decision|:subflow|:loop|:end_response, successors: [...] }`,
decision branches `{ semantic:, signal:, target:, connection_id: }`, the set of stepless End ids, and
(for the interim loop path) the scope's terminal targets; output = per step `magnetic: true|false`
and explicit outputs `[["Output(:success)", "Id(:x)"], ["Output(Routes::D::Yes, :yes)", "End(:success)"]]`,
plus the `CANVAS` `routes` / `ends` maps. Rules exactly as spec A3.

**Interim loop path:** keep nested `LoopBody<N>` classes and the loop `step task:` method until
Task 7, but apply the planner per scope: the outer scope excludes body ids and wires the loop step's
single exit successor; a body scope treats edges back to its loop header as terminal (the body
class's End.success). Decisions inside a body use the same `Routes` constants (lexical lookup).
`LoopMethodBuilder#build` loses its guard argument.

**Specs to write first:**
1. `wiring_planner_spec.rb` — linear; decision with both branches to a merge; nested decisions;
   non-nested merge (cross edge); branches ending at two different Ends; decision branch straight to
   a stepless End; empty branch straight to the merge node; terminal step that is not last; End
   with response as last and not last; subflow in a branch.
2. A circuit-equality helper in `activity_generator_spec.rb` (or a new
   `activity_generator_wiring_spec.rb`): compile each graph above through `ActivityGenerator`,
   introspect `klass.to_h[:circuit]`, and assert the set of (from, to) edges between steps/termini
   equals the canvas edges mapped to step ids (stepless Ends → `End.success`), plus every step's
   failure edge to `collect_errors`, ignoring only each decision's unused default success output.
3. Behaviour: order-approval style sample — each input runs only the taken branch's steps (assert
   via a probe key per step); composition behaviours (false Validate stops Save; guard skip; retry
   and timeout around one action; Subprocess failure ends on failure with the child's errors kept).
4. Decision generator: signal names table from spec A2 (true/false/empty/high/value_3/"1"/Chinese/
   "success"/duplicates); boolean and value-switch bodies; no-topology bodies.
5. Header (A8) for saved, unsaved, shared, unbound and with subflows; no Trigger/Multi-source/Model/
   Contract lines; locale-independent (generate under `I18n.with_locale(:"zh-CN")` → identical text).
6. `CANVAS` content (A9) for the samples above; `NameDeriver` reserves `collect_errors`.
7. `StructureValidator`: `multiple_outgoing` for a process with two outgoing connections (en + zh-CN
   message names the element); Start with two outgoing; Decision and Loop exempt; `timer` element →
   unsupported type message.
8. `FlowchartRuntime::Errors.collect`: contract errors, AR model errors, pre-existing `ctx[:errors]`
   first and de-duplicated, `_last_error` ignored, empty ctx → `[]`.
9. Flowchart 14 shape (spec A9 target) generated from the Phase 1 split chain; with an entity whose
   attribute is required, a traced run with empty params ends on failure with `ctx[:errors]` set
   (use `ActivityClassBuilder#build_activity_class` + `Trailblazer::Activity::TaskWrap.invoke` or the
   plain `call` — do not depend on Task 3's tracer changes).

**Run:** `TEST_ENV_NUMBER=41 bundle exec rspec spec/services/activity_generator_*_spec.rb spec/services/activity_generator spec/services/flowchart_topology_analyzer_spec.rb spec/services/code_generators/element_types spec/integration/query_count_branching_spec.rb spec/services/code_generators/test_runner_spec.rb spec/services/code_generators/unprobeable_field_conformance_spec.rb spec/services/flowchart_server_validator spec/services/flowchart_server_validator_spec.rb spec/services/flowchart_runtime/errors_spec.rb spec/requests/admin/maintenance/platform/code_generators/previews_spec.rb spec/models/flowchart_spec.rb spec/services/flowchart_definitions spec/tasks`

---

### Task 4 — Timer removal (D)

**Owns:** `app/components/flowcharts/element_palette_component.html.erb`;
`app/components/flowchart_elements/{timer_element_component.rb,timer_element_component.html.erb,base_element_component.rb}`;
`app/components/platform/code_generators/sidebar_component.rb` (timer only);
`app/views/admin/maintenance/flowcharts/_editor.html.erb` (timer data attributes only);
`app/javascript/flowchart/constants/{elements,schemas}.js`, `app/javascript/flowchart/{element_config,element_renderer,validation_service,validation_autofix,validation_navigation}.js`,
`app/javascript/flowchart/validation/element_rules.js`,
`app/javascript/controllers/flowchart_canvas_controller.js` (timer values only),
`app/javascript/controllers/property_editor/{form_builder,tab_manager,label_derivation}.js` (timer only),
any other `app/javascript/**` reference to the Timer element (not `setTimeout`-style timers);
`app/services/code_generators/element_types/timer/**` (delete);
`app/services/code_generators/generator_registry.rb` (`SUPPORTED_ELEMENT_TYPES`);
`app/services/flowchart_definitions/{palette.rb,structure_schema.json,structure_schema.prompt.txt}`;
`lib/code_generators/config_schemas.rb` (regenerate the mirror with the existing rake task);
timer keys in `config/locales/{flowchart_elements,comp_misc,maint_core}.{en,zh-CN}.yml` (targeted
removals; Task 1 adds a maint_core key in the same wave). Specs: the mirrored Vitest files, component
specs, generator/registry/palette/structure-schema/assistant-prompt specs that mention Timer.
Not yours: `structure_validator.rb` (Task 1 adds `timer` to the unsupported types).

**Checks:** palette renders no Timer; `rg -n -i "timer" app/javascript/flowchart app/javascript/controllers/property_editor app/javascript/controllers/flowchart_canvas_controller.js app/components/flowchart* app/services/flowchart_definitions app/services/code_generators lib/code_generators config/locales/flowchart_elements* config/locales/maint_core* config/locales/comp_misc*`
shows no Timer-element reference; `GeneratorRegistry` has no timer generator; config-schema parity
specs and locale parity specs green; Vitest 100% on touched files; the assistant structure schema has
no `timer` element type and its prompt no timer guidance.

---

### Task 6 — Merge data flow (B1 Ruby, B2)

**Owns:** `app/services/code_generators/conflict_resolver.rb`,
`app/services/activity_generator/element_io_index.rb`,
`app/services/code_generators/emission_rewriter.rb`,
`app/services/activity_generator/element_body_rewriter.rb` (ordinary path; keep the loop path
working), new `app/services/flowchart_runtime/outputs.rb`, every other caller of
`ConflictResolver` / `EmissionRewriter.call_element`. Specs: `spec/services/code_generators/{conflict_resolver,emission_rewriter}_spec.rb`,
`spec/services/activity_generator/element_io_index_spec.rb`, element body rewriter specs, new
`spec/services/flowchart_runtime/outputs_spec.rb`, new `spec/services/activity_generator_merge_dataflow_spec.rb`.
Not yours: loop specs and generator specs (Task 1) — run them and report regressions you cause.

**Produces:** `ConflictResolver.call(descriptors, topo_order:, ancestors:)` (rename only when an
ancestor writes the same pin); `ElementIoIndex#build` also returns `dominators`
(`element_id → Set`, on the forward dataflow graph rooted at Start) and the topological index used
for ordering; `EmissionRewriter.call_element(..., dominators:, topo_index:)`;
`FlowchartRuntime::Outputs.latest(ctx, *keys)` → value of the first key with `ctx.key?`, else nil.
A selection read replaces the `ctx[:pin]` span with `FlowchartRuntime::Outputs.latest(ctx, :k1, :k2)`;
op-assign spans stay writes to the element's own key.

**Specs first:** resolver (exclusive writers keep the key; ancestor writer renames; three writers
with an upstream one; Ends share `response`); dominators (diamond, nested diamond, branch to End);
rewriter (single candidate direct; dominating latest candidate direct; non-dominating → selection
call with keys latest first; self-writer reads upstream before its own write; explicit override and
tombstone precedence unchanged); end-to-end values through `ActivityGenerator` for the three B2
checks (order approval; value set before a decision and overwritten on one branch; self read).
The end-to-end spec asserts runtime values only, so it is valid against both the old and the new
generator shape.

---

### Task 2 — Errors to the submitter and the traces JSON (C4, C3 server side)

**Owns:** `app/services/pages/public_submission.rb`, `app/controllers/public_pages_controller.rb`,
`app/controllers/admin/maintenance/flowchart_traces_controller.rb`, their specs
(`spec/services/pages/public_submission_spec.rb`, public page submission request specs,
`spec/requests/maintenance/flowchart_traces_spec.rb`,
`spec/requests/admin/maintenance/flowcharts/phase1_endpoints_spec.rb` trace examples).
**Produces:** `Pages::PublicSubmission::Result#message` set on `:failed` from `ctx[:errors]`
(`to_sentence`, request locale) when the run ended on the failure track without an exception;
the public flash uses it inside `public_views.flash.response_save_error` and falls back to
`common.errors.dynamic.activity_execution_failed`; traces JSON gains `errors: Array<String>`
(`result.ctx[:errors]`, strings only). Specs: a submission whose contract rejects a blank required
field shows the field message in the flash (en and zh-CN); a raised step keeps the generic text and
never shows exception text; traces JSON includes `errors` on failure and `[]` on success; existing
auth examples unchanged.

---

### Task 3 — Tracer, diagram and class loading (C1, C2, C5)

**Owns:** `app/services/activity_tracer.rb`, `app/services/activity_diagram_generator.rb`,
`app/services/concerns/activity_class_builder.rb`, `app/services/dynamic_class_loader.rb`,
`app/services/flowchart_server_validator/codegen_validator.rb` (remove dead `todo_problems` and
helpers only it uses), `app/services/activity_generator.rb` (targeted removal of
`node_element_index` only; Task 7 edits loop code in the same file), new keys
`flowchart_elements.trace.*` (en + zh-CN), specs: `spec/services/activity_tracer*_spec.rb`,
`spec/services/activity_diagram_generator_spec.rb`, `spec/services/dynamic_class_loader_spec.rb`,
class-builder and codegen-validator specs. The loop spec example that calls `node_element_index`
belongs to Task 7.

**Produces — trace node:** `{ id:, element_id:, label:, status: "success"|"failure"|"unknown",
signal:, branch: (decision only), ctx_snapshot: (optional) }`. Start node carries the Start element
id and the translated label; the success End node carries the reached End element id and its label
(or the translated terminal label); the failure End node has no element id and a translated label;
`collect_errors` and child-flow terminals are omitted.

---

### Task 5 — Test panel, overlay and rename parity (C3, B1 JS)

**Owns:** `app/javascript/flowchart/canvas/trace_overlay.js`, `app/javascript/flowchart/test_runner_manager.js`,
`app/javascript/controllers/property_editor/element_io/{override_computer,reachability}.js`,
`app/javascript/controllers/flowchart_canvas_controller.js` (new values only),
`app/views/admin/maintenance/flowcharts/_editor.html.erb` (new data attributes only), new
`maint_core.flowcharts.editor.*` keys (en + zh-CN), mirrored Vitest specs, editor view specs that list
canvas data attributes. **Consumes:** trace node fields (Task 3) and `errors` (Task 2).
**Checks:** order badges count distinct elements in first-execution order; colour = last status;
decision rows show the branch (format value with `{step}`/`{branch}` tokens); failure banner lists
`errors`; `override_computer` renames a pin only when another emitter is an ancestor on the graph
without loop back-edges; Vitest 100% on touched files.

---

### Task 7 — Loops via back-edge wiring (E1–E4)

**Owns:** loop code in `app/services/activity_generator.rb` (targeted edits),
`app/services/activity_generator/{wiring_planner,loop_method_builder,loop_io_plan,loop_state,executed_outputs,loop_topology,element_body_rewriter}.rb`,
`app/services/code_generators/element_types/loop/loop_generator.rb`, new runtime helpers under
`app/services/flowchart_runtime/` for loop state and execution provenance, and the loop specs
(`spec/services/activity_generator_loop*_spec.rb`, `spec/services/activity_generator/{executed_outputs,loop_state,loop_io_plan,loop_topology}_spec.rb`,
loop generator specs, planner loop cases). **Checks:** spec E1–E4; the loop integration scenarios keep
their expected values; three-item for_each trace order; generated code has no `ActivityGenerator::`,
no `LoopBody`, no `task:`, no 64-hex keys; B2 merge reads keep working when the flowchart contains a
loop.

---

### Tasks 8–10 (Wave 3)

- **8 Docs** — `doc/reference/{en,zh-CN}/{flowchart-builder,code-generators,flowchart-runtime}.md`
  updated per spec F; key code excerpts copied from the final source; developer-docs specs green.
- **9 Playwright** — extend `spec/e2e/flowchart_builder_journey.app.spec.js` (+ helpers): decision
  flow test run highlights only the taken branch and shows the branch in the steps list; a failing
  validation shows the collected error in the failure banner; Timer absent from the palette.
- **10 Verification** — full parallel RSpec, `npx vitest run --coverage` (100/100/100/100),
  Playwright journey, `bin/rails flowcharts:regenerate_activities` dry run then apply on development,
  dev server restart with `SKIP_AUTH=1`, smoke of flowchart 14 edit page and a test run.

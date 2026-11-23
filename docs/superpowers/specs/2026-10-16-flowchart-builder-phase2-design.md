# Flowchart builder — Phase 2: generated activity

Date: 2026-10-16 · Parent: `2026-10-16-flowchart-builder-refactor-design.md` · Builds on Phase 1
(one action per Process box is enforced end to end).

Phase 2 makes compiled flowcharts use Trailblazer as intended: one Railway step per canvas box, real
wiring for branches, Ends, subflows and loops, a failure track that tells the submitter what went
wrong, and traces and diagrams that show exactly what ran. Each item states the requirement and the
check that proves it. Verified on the installed gems (trailblazer-activity 0.17.0, dsl-linear 1.2.6):
forward and backward `Id()` references, custom signal outputs, `magnetic_to: nil`,
`Output(:success) => End(:success)`, traced back-edge loops and wired `Subprocess` steps
(probe: `/home/ec2-user/fc_review/phase2/dsl_probe.rb`).

## A. Generated class shape

**A1 One step per box, no lambdas.** A Process box compiles to `step :<name>` and
`def <name>(ctx, **)` whose body is the action's emitted code with its timeout / retry / guard
wrappers. No `-> do … end.call`, no `return false unless`, no trailing `true` after the action.
An empty Process box emits `true`.
Check: the composition behaviour (a false Validate stops Save; guard skip; retry and timeout around
one action) passes against the new shape.

**A2 Decisions route with signals.** For every decision the class declares one signal per outgoing
connection:

```ruby
module Routes
  module IsLargeOrder
    Yes = Class.new(Trailblazer::Activity::Signal)
    No = Class.new(Trailblazer::Activity::Signal)
  end
end

step :is_large_order,
  Output(Routes::IsLargeOrder::Yes, :yes) => Id(:manual_review),
  Output(Routes::IsLargeOrder::No, :no) => Id(:auto_approve)
```

The decision method returns the taken branch's signal (`if/else` for a boolean condition,
`case/when` for a value switch). Default-branch rules are unchanged (`defaultBranchIndex`, else the
first connection with an empty match value, else the last connection). No `ctx[:_route_N]`, no guard
lines, no `FlowchartTopologyAnalyzer` guards or route indices.
- Branch names: `true` → `Yes`/`:yes`, `false` → `No`/`:no`, empty → `Otherwise`/`:otherwise`;
  any other match value → its ASCII words camelized (`high` → `High`/`:high`,
  `value_3` → `Value3`/`:value_3`); a leading digit gets a `Value` prefix; no ASCII letters or digits →
  `Branch<n>`/`:branch_<n>` (1-based position); the semantics `success` and `failure` become
  `success_branch` / `failure_branch`; duplicates within a decision get a numeric suffix. Decision
  module names are the camelized step names, unique within `Routes`.
- Without flowchart topology (code-generator preview, standalone test run, I/O extraction) the
  decision body returns the evaluated condition (boolean) or the subject value (`.to_s`).

Check: compiled circuit edges equal the canvas edges; branches that were not taken never run.

**A3 Wiring planner.** Steps are declared in DFS order (a decision's branches before its merge
node). Rules, applied per declared step:
- A step's success edge to its single successor is implicit only when the successor is the next
  declared step and is attracted by it; otherwise it is explicit `Output(:success) => Id(:<next>)`,
  or `Output(:success) => End(:success)` when the successor is an End without a step.
- A declared step whose previous declaration is a decision, or whose previous declaration does not
  flow into it implicitly, gets `magnetic_to: nil`.
- A terminal step (no successor, or only a stepless End) that is not the last declaration gets
  `Output(:success) => End(:success)`.
- Failure outputs keep the default failure track, which ends in `fail :collect_errors`.
- Every element except Decision and Loop has at most one outgoing connection (A6).

Check: for linear chains, nested decisions, non-nested merges, branches ending at different Ends,
a decision branch straight to an End, an empty branch straight to the merge node, and subflows, the
introspected circuit (`activity.to_h[:circuit]`) contains exactly the canvas edges plus the failure
track, and nothing else except each decision's unused default success output.

**A4 Ends.** An End with response type `none` has no step; edges into it wire to `End(:success)`.
An End with a response (`value`, `http_response`) is a step that writes its keys and is wired to
`End(:success)`. Every End is a success terminus.

**A5 Subflows.** `step Subprocess(<ChildActivity>), id: :<name>` with the same wiring rules; no
hand-written circuit method and no route-key snapshot. Two references to one child get distinct ids.

**A6 One outgoing connection.** `StructureValidator` rejects an element other than Decision or Loop
with more than one outgoing connection (translated message naming the element, en + zh-CN).

**A7 Failure track and errors contract.** Every class ends with `fail :collect_errors`:

```ruby
def collect_errors(ctx, **)
  ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
end
```

`FlowchartRuntime::Errors.collect(ctx)` returns the unique messages already in `ctx[:errors]` (a
child flow's errors) followed by the full messages of every top-level ctx value that responds to
`errors.full_messages` (Reform contracts, Active Model records). `ctx[:_last_error]` stays
diagnostic and is not copied, because it can carry internal exception text; Phase 3 turns expected
step failures into `ctx[:errors]` entries. Check: flowchart 14's chain with empty params ends on the
failure track with `ctx[:errors]` holding the contract's "can't be blank" messages (translated in
zh-CN).

**A8 Header, names and layout.**
- Header: `# frozen_string_literal: true`, then
  `# Generated from flowchart #<id> "<name>". Do not edit; regenerate it from the flowchart editor.`
  (no `#<id>` when unsaved), then `# Bound entity: <label>`, or
  `# Bound entity: supplied at runtime (shared flowchart)`, or `# No bound entity`, then
  `# Subflows: <Class> (#<id> "<name>"), …` when present. No Trigger, Multi-source, Model class or
  Contract class lines. User text keeps the existing comment sanitizing.
- Generated source is locale-independent English: it is Ruby source, and the stored artifact must not
  change with the saving user's locale.
- Every step method is preceded by `# <element label>`; methods are separated by one blank line; no
  blank-line runs, no trailing whitespace.
- `NameDeriver` also reserves `collect_errors`.

**A9 Element map.** The class embeds

```ruby
CANVAS = {
  steps: { is_large_order: "d1", manual_review: "p1" },
  routes: { is_large_order: { yes: "c2", no: "c3" } },
  ends: { notify_team: { success: "end_2" }, is_large_order: { no: "end_3" } }
}.freeze
```

`steps` maps every step id to its element id; `routes` maps each decision step's output semantic to
its connection id; `ends` maps a step's output semantic to the stepless End element it reaches.
`routes` and `ends` are omitted when empty. The tracer reads this map from the code it runs.

Target shape for flowchart 14 after the Phase 1 split:

```ruby
# frozen_string_literal: true
#
# Generated from flowchart #14 "Create Student Profile". Do not edit; regenerate it from the flowchart editor.
# Bound entity: Student Profiles
class CreateStudentProfileActivity < Trailblazer::Activity::Railway
  CANVAS = {
    steps: { new_model: "el_a", build_contract: "el_b", validate: "el_c", save_model: "el_d" },
    ends: { save_model: { success: "end_1" } }
  }.freeze

  step :new_model
  step :build_contract
  step :validate
  step :save_model
  fail :collect_errors

  # New Model
  def new_model(ctx, **)
    ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])
    true
  end

  # … build_contract, validate and save_model follow the same pattern …

  def collect_errors(ctx, **)
    ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
  end
end
```

## B. Data flow at merges

**B1 Writers on exclusive branches share a key.** `ConflictResolver` renames an element's output only
when another writer of the same key is upstream of it (an ancestor in the dataflow graph, loop
back-edges excluded). Writers on mutually exclusive branches, and terminal Ends, keep the original
key. The editor's computed overrides (`override_computer.js`) apply the same rule.

**B2 Reads pick the producer that actually ran.** For a read of `ctx[:pin]` without an explicit input
override or tombstone, the candidate producers are the reader itself when it writes the pin, then the
upstream writers of the pin, latest first (topological order). With one candidate the read uses that
candidate's effective key (unchanged). With several, the read uses the latest candidate's key directly
when that candidate always runs before the reader (it dominates the reader and is not the reader);
otherwise the read compiles to `FlowchartRuntime::Outputs.latest(ctx, :key_a, :key_b, …)`, which
returns the value of the first key present in ctx. In an acyclic flow each step runs at most once,
so the first present key is the most recent write that actually happened.
Check: the order-approval sample yields `pending/manager`, `pending/team` and `approved/`; a value
set before a decision and overwritten on one branch reads correctly on both paths; an element that
reads and writes the same key reads the upstream value.

## C. Tracing, diagram, test panel, public submission

**C1 Tracer reads the embedded map.** `ActivityTracer` maps node ids to elements through
`<ActivityClass>::CANVAS` (no generator re-run; `ActivityGenerator#node_element_index` and the dead
`CodegenValidator#todo_problems` are removed). Status: Right → success, Left → failure, a route
signal → success with `branch` (the connection label, else the semantic), a subprocess → its End's
semantic. The `collect_errors` node and a child flow's own terminals are not listed. The Start node
carries the canvas Start element id; the End node carries the reached End element id (via `ends`, or
the last step when it is an End-with-response step). Labels are canvas element labels; terminal
labels are translated (en + zh-CN).

**C2 Diagram.** `ActivityDiagramGenerator` labels decision edges with the branch label, omits a
decision's unused default success/failure edges, draws route-signal edges as normal edges (not
failure), and labels nodes with element labels.

**C3 Test panel.** The traces JSON includes `errors` (`ctx[:errors]`); the failure banner lists them.
Order badges number distinct elements (1, 2, 3 …) in first-execution order; an element's colour is its
last status; a decision row shows the branch taken. New UI text arrives as Stimulus values with
English defaults and server-passed translations.

**C4 Public submission shows why it failed.** A run that ends on the failure track redirects with
`public_views.flash.response_save_error` filled with the collected errors (`to_sentence` in the
request locale). With no collected errors, or when the run raised, the generic
`common.errors.dynamic.activity_execution_failed` stays. Exception text never reaches the flash.

**C5 Class loading is quiet.** `DynamicClassLoader` does not redefine constants that already exist in
the namespace (no "already initialized constant" warnings when subflows load).

## D. Timer removed

The Timer element is removed from the palette, element components, editor constants / schemas /
config / renderer / validation / autofix / navigation, property editor, Stimulus values and editor
data attributes, generator registry and `TimerGenerator`, the assistant palette, structure schema and
prompt, the config-schema mirror, and both locales. `StructureValidator` reports a stored `timer`
element as an unsupported type. Delayed work uses the background-job action.

## E. Loops via back-edge wiring (follow-up slice)

**E1** A loop header is an ordinary step:
`step :<loop>, Output(Routes::<Loop>::Done, :done) => Id(:<exit>)` (or `End(:success)`); the body
follows it and each body tail wires `Output(:success) => Id(:<loop>)`. No nested `LoopBody` classes,
no `task:` steps, no `loop.io.initialize` step.

**E2** Header behaviour is preserved: for_each (collection, item and index variables, iteration cap,
skip and break conditions, accumulator), while (pre-check), do_while (first pass unconditional),
iteration caps. Iteration state lives under one short ctx key that is removed on exit.

**E3** Loop data flow keeps execution-provenance semantics (a value read after or inside a loop is
the most recent write that actually ran). Helpers live under `FlowchartRuntime`; generated code
references no `ActivityGenerator::` constant; generated keys are short (no 64-character digests);
rewriting is limited to the loop region and the readers that depend on it.

**E4** Body steps appear in traces, once per iteration.

Check: the loop integration scenarios keep their expected values in the new shape; a three-item
for_each trace lists header, body ×3, header, exit.

## F. Rollout, docs and verification

- `bin/rails flowcharts:regenerate_activities` (dry run, then apply on development) regenerates every
  stored artifact; the deploy note says regeneration is part of the same deploy.
- Docs, en and zh-CN in lockstep: `flowchart-builder.md`, `code-generators.md`,
  `flowchart-runtime.md` (generated shape, wiring rules, errors contract, element map, tracing, merge
  reads, Timer removal, loop shape, deploy note).
- Tests: targeted specs per layer; full parallel RSpec (generation is cross-cutting); Vitest at
  100% lines and branches on touched JS; the Playwright builder journey extended with a decision
  flow (only the taken branch is highlighted) and a failing validation that shows the collected
  error in the test panel.

## Out of scope

Config-schema single source, emission helpers and catalog consolidation (Phase 3, including turning
`_last_error` failures into translated `ctx[:errors]` entries); element editor redesign, End HTTP
mode and `defaultBranchIndex` removal (Phase 4); canvas polish (Phase 5).

# Flowchart builder refactor — remaining work (handoff)

Last updated: 2026-10-19 08:30 UTC. Nothing is committed: Phases 1 and 2 sit in the working tree on
`main` (HEAD `6d9824b1`). Phase 2 is complete (§3 is kept as the record of what shipped; its closing
state is in `.superpowers/sdd/2026-10-16-flowchart-phase2/progress.md`). Phases 3–5 are next; the owner
decisions they needed are answered in §8.

## 1. Where things stand

**Original request (2026-10-16)** for the flowchart builder (e.g. `/81721200/admin/maintenance/flowcharts/14/edit`):
(a) review the build process and UI/UX and fix defects; (b) review every element's and every step
action's configuration, give fields working defaults, simplify the property-editor layout and remove
unnecessary fields; (c) refactor all code generators to professional Trailblazer Activity + Reform
conventions; (d) review and refactor whole-flowchart code generation; (e) add step-action categories and
items, and code generators, where the business needs them.

**Owner decisions (2026-10-16):** one action per Process box; consolidate the step-action catalog
(about 100 to about 60) and add the missing business actions; remove the Timer element; work in phases,
each with a written spec and plan, with a summary at each phase boundary.

| Phase | Theme | Status |
|---|---|---|
| 1 | Safety and correctness | Complete and verified (uncommitted) |
| 2 | Generated activity | Complete and verified 2026-10-19 (uncommitted) — §3 |
| 3 | Step-action platform | In progress (resumed 2026-10-19) — §4, spec/plan `docs/superpowers/*/2026-10-19-flowchart-builder-phase3*` |
| 4 | Element property editor | After Phase 3 — §5, spec/plan `…phase45*` (Phase 4 part) |
| 5 | Canvas polish | After Phase 4 — §6, spec/plan `…phase45*` (Phase 5 part) |

**Environment right now**
- Dev server (port 3000) and the isolated Playwright server (port 3001) are stopped.
- Dev database: Phase 1's split task was applied (flowchart 14 is now Start, four single-action boxes,
  End). Phase 2's
  regeneration has **not** run, so stored activity code on dev still has the Phase 1 shape until
  Task 10 (§3.6) runs. The new tracer needs the regenerated code to map trace steps to canvas elements.
- Isolated RSpec databases 41–49 are prepared (`TEST_ENV_NUMBER=41…49`); there were no migrations in
  Phases 1–2.

## 2. How to resume

### 2.1 Documents
- Parent design (phases, decisions, target architecture):
  `docs/superpowers/specs/2026-10-16-flowchart-builder-refactor-design.md`
- Phase 1: `docs/superpowers/specs/2026-10-16-flowchart-builder-phase1-design.md`,
  `docs/superpowers/plans/2026-10-16-flowchart-builder-phase1.md`, ledger and task reports in
  `.superpowers/sdd/2026-10-16-flowchart-phase1/`.
- Phase 2: `docs/superpowers/specs/2026-10-16-flowchart-builder-phase2-design.md` (requirements A1–F),
  `docs/superpowers/plans/2026-10-16-flowchart-builder-phase2.md` (tasks, file ownership, interfaces),
  ledger `.superpowers/sdd/2026-10-16-flowchart-phase2/progress.md`, task reports `task-<n>-report.md`
  and review diffs `task-<n>-review-package.diff` in the same folder.
- `docs/superpowers/**` and `.superpowers/**` are listed in `.cursorignore`: AI tools cannot open them
  with the Read tool; use `cat` in a shell.
- Scratch outside the repo (may not survive a machine reset): `/home/ec2-user/fc_review/` — original
  findings (`findings.md`), the Trailblazer DSL probe (`phase2/dsl_probe.rb`), the trace snapshot probe,
  the id/label collision probe, the drafted Task 7 brief (`phase2/t7_prompt.txt`) and the review-diff
  helper (`phase2/review_pkg.sh`). Everything needed to continue is repeated in this file.

### 2.2 Rules every task follows (AGENTS.md + plan constraints)
- No commits (the owner commits after review). No `git stash` / `checkout -- <file>` / `reset` while
  other work is in the tree.
- No hard-coded user-facing strings: keys in `en` and `zh-CN` with identical key sets and `%{}`
  variables, idiomatic zh-CN. JS text arrives as Stimulus values with English `default:` plus
  server-passed `data-*-value`. Generated Ruby source is locale-independent English (it is code, not UI).
- No backward-compatibility shims: stored data is migrated by a rake task whenever a format changes.
- Every emitted lookup is scoped by `customer_id` and the bound entity (`FlowchartRuntime::Entries.scope`).
- TDD: failing spec first; stale specs that pinned old output are rewritten, never weakened.
- `app/javascript/**` stays at 100% lines, branches and functions (Vitest).
- Developer docs (`doc/reference/{en,zh-CN}/…`) change in the same change as the code.

### 2.3 Workflow that worked
One implementer subagent per task (anysys-backend-developer / -frontend-developer /
-security-engineer) with an exclusive list of owned files, a report file with real command output, then
a reviewer (anysys-code-reviewer for correctness and security, anysys-tech-lead for conventions) on a
review diff, then fix rounds until the review passes. Tasks that run in parallel never share files;
shared YAML locale files are edited only with targeted replacements.

### 2.4 Commands
```bash
# targeted specs (isolated DB)
TEST_ENV_NUMBER=41 bundle exec rspec <spec files>

# full suite (known pre-existing order-dependent flake: sync_entity_domain_spec.rb:139, passes alone)
bin/rails parallel:prepare && bin/rails parallel:spec

# JavaScript, per touched file and in full
npx vitest run --config config/javascript/vitest.config.js <specs> --coverage --coverage.include=<app file> --coverage.reporter=text
npm run coverage

# editor schema mirror (JS -> Ruby today)
bundle exec rake config_schemas:mirror && bundle exec rake config_schemas:check

# Playwright builder journey on an isolated database and server
export E2E_DATABASE_PATH="$PWD/storage/e2e_flowchart_builder.sqlite3" \
       DATABASE_URL="sqlite3:$PWD/storage/e2e_flowchart_builder.sqlite3" \
       RAILS_ENV=development APP_HOST=127.0.0.1 APP_PORT=3001
node spec/e2e/helpers/bootstrap.js check        # `create` for a new database
SKIP_AUTH=1 bin/rails server -b 127.0.0.1 -p 3001 -P tmp/pids/e2e-flowchart-builder.pid   # second shell, same env
APP_BASE_URL=http://127.0.0.1:3001 PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright \
  npx playwright test --config config/javascript/playwright.config.js spec/e2e/flowchart_builder_journey.app.spec.js
unset E2E_DATABASE_PATH DATABASE_URL            # never let these leak into dev-database commands

# dev server
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Review diffs for Phase 2 are taken against the Phase 1 end state, captured as git tree object
`3ddc6f2c8f732f6ea7d9f3d66fa1b1b85e2e8907` (no commit, no ref) with
`/home/ec2-user/fc_review/phase2/review_pkg.sh <task> <paths…>`.

### 2.5 Deploy checklist (when this ships)
In the same deploy, before serving traffic:
1. `bin/rails flowcharts:split_multi_action_processes APPLY=1` (Phase 1: one action per box).
2. `DRY_RUN=1 bin/rails flowcharts:regenerate_activities`, then without `DRY_RUN` (Phase 2: the
   generated shape changed; the tracer reads the embedded element map).

## 3. Phase 2 — generated activity (finish these first)

**Goal.** Compile flowcharts into idiomatic Trailblazer: one Railway step per canvas box, real wiring
for decisions, Ends, subflows and loops, a failure step that surfaces `ctx[:errors]`, correct values at
merges, and traces/diagrams driven by an element map embedded in the generated class.

**Finished and reviewed**
- Task 1 — generator core: one method per box (no lambdas); decisions return
  `Routes::<Decision>::<Branch>` signals wired with `Output(signal, :semantic) => Id(…)`, plus
  `Output(:success) => Track(:failure)` so a decision that picks no branch fails loudly; a pure
  `ActivityGenerator::WiringPlanner`; Ends without a response have no step; plain `Subprocess` steps;
  `fail :collect_errors` with `FlowchartRuntime::Errors.collect`; clean header; `CANVAS` map; rule
  "only Decision and Loop may have more than one outgoing connection".
- Task 2 — a failed public submission shows the collected messages in the flash (generic text when the
  run raised); the test-run JSON has `errors`.
- Task 4 — Timer element removed everywhere (stored timers get a translated "unsupported" problem).
- Task 5 — test panel: badges number distinct elements in first-execution order, colour = last status,
  decision rows show the branch, failure banner lists `errors`; the editor's rename rule matches the
  server.

Current generated shape (decision sample):
```ruby
class TwoLevelActivity < Trailblazer::Activity::Railway
  CANVAS = {
    steps: { is_vip: "outer", is_rush: "inner", fast_path: "fast", slow_path: "slow", standard_path: "standard" },
    routes: { is_vip: { yes: "c2", no: "c3" }, is_rush: { yes: "c4", no: "c5" } },
    ends: { fast_path: { success: "end_ok" }, slow_path: { success: "end_ok" }, standard_path: { success: "end_other" } }
  }.freeze

  module Routes
    module IsVip
      Yes = Class.new(Trailblazer::Activity::Signal)
      No = Class.new(Trailblazer::Activity::Signal)
    end
    # …
  end

  step :is_vip,
    Output(Routes::IsVip::Yes, :yes) => Id(:is_rush),
    Output(Routes::IsVip::No, :no) => Id(:standard_path),
    Output(:success) => Track(:failure)
  # …
  step :standard_path, magnetic_to: nil
  fail :collect_errors
  # one method per box, each preceded by "# <element label>", then collect_errors
end
```

### 3.1 Task 6 — merge data flow: final re-review (implementation done)
- **Status.** Implemented and fixed twice after review; last run 392 examples, 0 failures. Needs one
  final focused re-review.
- **What it does.** (B1) A writer is renamed only when an upstream element writes the same key, so writers
  on exclusive branches share one key. (B2) A read with several possible producers compiles to
  `FlowchartRuntime::Outputs.latest(ctx, :key_a, :key_b)` (or `Outputs.view(ctx, :pin, …).dig(…)` for
  `ctx.dig`/`fetch`/`key?` reads) unless the latest producer always runs first. Saved author renames are
  honoured.
- **Last fix to verify.** Byte offsets: `Splicer#apply_edits` now splices on `body.b`, and
  `BodyAnalyzer#byte_offset` now treats Ripper columns as bytes. Before, Chinese text earlier in a method
  shifted every rewrite (`SyntaxError` / spans parked at end of file). `BodyAnalyzer` also feeds
  `IoExtractor`, so I/O pins for bodies containing Chinese changed too (they were wrong before).
- **Re-review checklist.** Chinese literal before `ctx[:pin]` and `ctx.dig` reads in rename and selection
  modes; IoExtractor pins for a CJK body; hostile author `renamed_to` dropped and not blocking the
  automatic rename; loop specs green.
- **Files.** `app/services/code_generators/{conflict_resolver,emission_rewriter}.rb`,
  `app/services/code_generators/io_extractor/body_analyzer.rb`,
  `app/services/activity_generator/{element_io_index,element_body_rewriter}.rb`,
  `app/services/flowchart_runtime/outputs.rb` and their specs.

### 3.2 Task 3 — tracer, diagram, class loading: fix round (review failed)
- **Status.** Implemented: the tracer reads `CANVAS` (no generator re-run), uses the non-printing
  `Trailblazer::Developer::Trace.invoke` (nothing printed to the log), hides `collect_errors` and child
  terminals, keeps a partial trace when a step raises; public submissions run untraced
  (`ActivityTracer#call(input, trace: false)`); diagram labels decision edges and omits unused decision
  outputs; class loading no longer redefines constants. 352 examples pass. The review failed on two gaps.
- **Fix 1 — End-with-response.** When the last executed step is an End that writes a response, the
  `End.success` trace node has no element id and the generic label, because `CANVAS[:ends]` only lists
  Ends without a step. Proposed solution: when the `ends` lookup misses and the last executed step's
  element (via `CANVAS[:steps]`) is an `end` element, use that element id and label. Specs: End-with-response
  as the last step, and a decision branch straight to an End-with-response.
- **Fix 2 — Mermaid newlines.** `escape_label` strips brackets, quotes and pipes but keeps newlines, so a
  label with a line break splits the diagram. Proposed solution: collapse `\r`/`\n` into spaces and
  squeeze whitespace; spec a hostile label.
- **Also add specs** for a decision branch straight to a stepless End, two references to one subflow, and
  the untraced timeout path (currently only probed).
- **Files.** `app/services/activity_tracer.rb`, `app/services/activity_diagram_generator.rb`,
  `spec/services/activity_tracer_spec.rb`, `spec/services/activity_diagram_generator_spec.rb`.

### 3.3 Task 7 — loops via back-edge wiring (not started)
- **Why.** Loops still use the interim path: a nested `LoopBody<N>` class called from a `step task:`
  circuit method. Loops work and all loop specs pass, but body steps never appear in traces (a `task:`
  method gets empty circuit options), generated code calls `ActivityGenerator::ExecutedOutputs` /
  `ActivityGenerator::LoopState`, keys are 64-character digests, and the loop-provenance rewriting is
  applied to every element of a flowchart that contains any loop.
- **Design (spec E1–E4).**
  - The loop header is an ordinary step:
    `step :<loop>, Output(Routes::<Loop>::Done, :done) => Id(:<exit>)` (or `End(:success)`).
  - The body is declared right after the header (the DFS already visits it first); every body tail wires
    `Output(:success) => Id(:<loop>)`. Verified on the installed gems: back-edges trace each iteration.
  - The header method keeps today's semantics: for_each (collection, item and index names, cap, skip and
    break conditions, accumulator), while (check before each pass), do_while (first pass unconditional),
    the 10,000 cap, `ctx[:_loop_iteration_count]`. Iteration state lives under one short key
    (e.g. `ctx[:_each_item_loop]`) removed on exit and never leaking into a reused ctx.
  - Loop data flow keeps execution provenance (a read inside or after a loop returns the most recent
    write that actually ran), with helpers moved under `FlowchartRuntime`, short readable keys, and
    rewriting limited to the loop region and the readers that depend on it. Outside loops the B2
    `Outputs.latest` reads stay.
- **Proposed solution.** Extend `WiringPlanner` with back-edges (an edge into a loop header from its body
  is always explicit) and the header's two successors (body head = implicit success, exit = Done signal);
  generate the header method in `LoopGenerator`, optionally through a small runtime helper; move
  `LoopState` / `ExecutedOutputs` into `FlowchartRuntime` (new facade files need `class Error` or a
  justified exemption in `facade_contract_spec.rb`); delete `LoopBody` classes, the `task:` step,
  `LoopMethodBuilder` and the `loop.io.initialize` step; add `routes` for the header's `:done`
  connection to `CANVAS`. Illustrative shape:
  ```ruby
  step :init_total
  step :each_item, Output(Routes::EachItem::Done, :done) => Id(:report)
  step :add_item, Output(:success) => Id(:each_item)
  step :report, magnetic_to: nil
  fail :collect_errors
  ```
- **Files.** Loop code in `app/services/activity_generator.rb`;
  `app/services/activity_generator/{wiring_planner,loop_method_builder,loop_io_plan,loop_state,executed_outputs,loop_topology,element_body_rewriter}.rb`;
  `app/services/code_generators/element_types/loop/loop_generator.rb`; new `app/services/flowchart_runtime/*`;
  loop specs.
- **Done when.** Every scenario in `spec/services/activity_generator_loop_integration_spec.rb` and
  `activity_generator_loop_spec.rb` keeps its expected values (rewrite only shape assertions); the circuit
  equals the canvas edges including back-edges; a three-item for_each trace lists header, body ×3,
  header, exit; generated code contains no `ActivityGenerator::`, `LoopBody`, `task:` or 64-hex keys.
- **Risks.** The provenance machinery is subtle (the loop integration spec pins it). Traces grow with
  every iteration: public submissions are already untraced (Task 3); consider capping `trace_nodes` in
  owner test runs. If time is short, Phase 2 can ship without this task: loops work on the interim path.
- **Brief.** A ready dispatch prompt is in `/home/ec2-user/fc_review/phase2/t7_prompt.txt`.

### 3.4 Task 8 — reference docs (not started)
Update `doc/reference/en/` and `doc/reference/zh-CN/` in lockstep:
- `flowchart-runtime.md`: generated class shape (one step per box, `Routes` signals and wiring,
  `Track(:failure)` on decisions, Ends, Subprocess, `CANVAS`), the errors contract (`collect_errors`,
  `FlowchartRuntime::Errors.collect`, what is and is not shown to submitters), merge reads
  (`Outputs.latest` / `Outputs.view`), the tracer (embedded map, trace node fields, untraced public runs),
  the loop shape from Task 7.
- `flowchart-builder.md`: Timer removed; one outgoing connection except Decision/Loop; test panel
  (errors list, branch per decision, badges); deploy note (split + regenerate in the same deploy).
- `code-generators.md`: decision generator contract with and without topology, End/Subflow handling,
  header, `NameDeriver` reserved names and branch naming, `ConflictResolver` rule, `EmissionRewriter`
  B2 resolution, `WiringPlanner`.
Copy code excerpts from the final source. Done when the developer-docs specs pass
(`spec/services/developer_docs`, `spec/components/developer_docs`, `spec/helpers/developer_docs`).

### 3.5 Task 9 — Playwright journey (not started)
Extend `spec/e2e/flowchart_builder_journey.app.spec.js` (helpers `spec/e2e/helpers/builder_fixtures.{js,rb}`:
UUID-named records, exact cleanup, trusted input only):
1. Build Start → Decision (on a params field) → two process boxes → End; run the test panel once per
   branch: only the taken branch's elements are highlighted, badges count 1, 2, 3…, the decision row
   shows the branch label.
2. `crud_create` template on an entity with a required attribute; test run with empty params: the
   failure banner lists "<Field> can't be blank".
3. The palette has no Timer.
4. The existing journey scenarios stay green.

### 3.6 Task 10 — verification, regeneration, release (not started)
1. Full parallel RSpec; `npm run coverage` at 100/100/100/100; the Playwright journey.
2. `DRY_RUN=1 bin/rails flowcharts:regenerate_activities` on dev. Expect every flowchart to regenerate
   except the two pre-existing invalid probe drafts (#6 ExecProbe, #7 PersistProbe: "Target variable is
   required"). The task regenerates everything it can, then lists the failures and exits non-zero; fix or
   delete those two drafts with the owner's approval if a clean exit is wanted. Then run it without
   `DRY_RUN`. Also confirm no stored flowchart contains a Timer.
3. Restart the dev server; smoke `/81721200/admin/maintenance/flowcharts/14/edit` (200, chain renders,
   validation clean), a test run with valid params (success, badges) and empty params (errors in the
   banner), and the flowchart document page (diagram renders).

### 3.7 Close Phase 2 (not started)
Whole-change reviews on the Phase 2 diff (correctness/security with anysys-code-reviewer, conventions
with anysys-tech-lead), one combined fix round, a final verification run, then the phase summary for
the owner (what changed, deploy steps, follow-ups).

## 4. Phase 3 — step-action platform (not started)

### 4.1 Problems it solves
- Defaults live in four places (JS action configs, the Ruby mirror, `sample_input`, inline `||`
  fallbacks) and drift; 83 of 102 actions fail `validate_config({})`; selects without an empty option
  silently take their first option.
- Input/output names are inconsistent: `resultVar` / `outputKey` / `targetVariable` / `targetKey` /
  `targetField` for outputs, `sourceVariable` / `sourceKey` / `collectionKey` / `modelVariable` /
  `dataVariable` for inputs; 14 actions default to `ctx[:result]` and overwrite each other.
- Five failure conventions; `rescue => e; ctx[:_last_error] = e.message; false` in 38 files; expected
  failures never reach the submitter (Phase 2 surfaces only contract/model errors).
- Model actions treat JSON-backed entity attributes as columns in several places (soft delete needs a
  missing `deleted_at`, `transition_state` calls a missing `publish!`).
- Retry rescues everything and re-runs side effects (a second email); `Timeout.timeout` wraps database
  writes inside the submission transaction; default timeouts (30–120 s) exceed the 10 s run cap.
- About 100 actions with heavy overlap; the Response category does nothing at runtime; several actions
  do not work; about 2,450 English literals in the JS catalog, 52 missing generator I18n keys and 333
  stale keys.

### 4.2 Design
1. **One field declaration per generator — the single source.** `config_schema` declares every field
   once with a role, default, options, conditional rules and I18n keys; the editor renders from JSON
   exported from it (reversing today's JS → Ruby mirror), and `sample_input` and validation derive from
   it. Generators read config only through `value(:name)`.
   ```ruby
   config_schema do
     input  :sourceVariable, required: true
     enum   :operation, %w[sum avg min max count], default: "sum"
     flag   :skipNil, default: true
     output :resultVar, default: "calculation"
     requires :fixedRate, when: { rateSource: "fixed" }
   end
   ```
   Roles: `input` (emitted as a ctx read), `output` (validated key with an action-specific default),
   `expression` (ExpressionSafety + single-statement Prism check), `literal` (always `.inspect`),
   `template`, `enum`, `flag` (real boolean), `integer min:/max:`. Labels, help text, placeholders and
   option labels come from `flowchart_actions.<action>.…` keys in both locales.
2. **Emission helpers on `BaseGenerator`.** `read(:field)` is the only way config reaches emitted code;
   `assign(:resultVar, expr)` writes the output; `fail_with(:code, **details)` emits
   `return FlowchartRuntime::Step.fail(ctx, :code, **details)`. Bodies end with the operation's own
   success value; a literal `true` only when nothing can fail; `generate` asserts the body parses.
3. **Runtime helpers.**
   - `FlowchartRuntime::Step.fail(ctx, code, **details)` appends the translated message
     (`flowchart_runtime.errors.<code>`) to `ctx[:errors]` — keeping Phase 2's `Array<String>` contract,
     so `collect_errors`, the flash and the test panel work unchanged — records structured detail under
     `ctx[:error_details]` for the test panel, and returns false. `Step.attempt` wraps calls that may
     raise expected exceptions.
   - `Entries`: JSON-aware `find_by` / `where` on entity attributes, `assign`, `upsert` under `Lock`,
     `destroy` returning success plus errors.
   - Retry only for transport errors on actions the schema marks idempotent; no sleeping inside the
     submission transaction. Timeouts become library options (OutboundHttp open/read timeouts, database
     statement timeout) validated to fit the 10 s cap; `Timeout.timeout` disappears from emitted code.
   - Move long inline algorithms into helpers: `Idempotency.claim` (atomic), `RateLimiter.allow?`,
     `BusinessHours.open?`, `CacheKey.scoped(tenant, *parts)` validated at generation, `Json.parse`.
4. **Conventions for emitted code.** Standard keys `:params`, `:model`, `:contract`, `:errors`;
   action-specific output names (never a shared `:result`); one output shape per action; bodies of about
   12 lines at most (longer logic goes into a runtime helper).
5. **Runtime ctx contract.** Document the keys a run receives (`params`, `bound_entity`, `customer_id`,
   `authentication`, `current_user_id`, `current_user_role`, `audience`, `device_type`) and add the ones
   defaults expect (request IP and user agent for audit) so defaults read only seeded keys.

### 4.3 Catalog consolidation (proposed survivors)
- Email: `send_email`, `send_template_email`, `notify` (email channel) → `send_template_email` with a
  template picker; SMS becomes a new `send_sms`.
- Cache: `cache_read` fetch mode duplicates `cache_fetch`; `cache_write`'s delete duplicates
  `cache_delete`.
- Crypto and tokens: `encrypt_data` with action=decrypt duplicates `decrypt_data`; `authenticate` with
  JWT duplicates `verify_token`.
- `transform`: six of eight modes duplicate other actions (rename/remove fields → `hash_manipulate`,
  convertType → `type_cast`, formatDate → `date_time_calc`, custom/computed → `assign_value`,
  mapFields → `hash_manipulate`); keep the rest or remove the action.
- Aggregation: `calculate` vs `reduce_collection` (keep one); `aggregate_query` stays as the database
  version; counting via `count_records` / `check_existence` / `aggregate_query` count.
- Collections: `filter_collection`, `partition_collection`, `find_in_collection`, `any_all_none_check`
  share one filter block (one helper; consider merging).
- Serialization: `serialize_data` csv, `generate_csv` and `generate_file` csv overlap; `parse_data` csv
  duplicates `parse_csv`.
- Text: `format_string`, `template_render`, `i18n_translate` interpolation and parts of
  `string_manipulate` overlap.
- Jobs: merge `enqueue_job` and `schedule_job` into "Run background job" with a When choice.
- Remove (inert or broken): `render_response` and `redirect_response` (replaced by "Set submission
  outcome"), `transition_state`, `retry_with_backoff` (step-level transport retry replaces it), `notify`
  in-app channel, `deadline_check` signal mode, `soft_delete_model` (no `deleted_at`; or make it an
  "Archive" option of `destroy_model`), `circuit_breaker` as a standalone step (fold into HTTP actions as
  an advanced option), `publish_event` / `broadcast` until a live-update feature exists.
- Drop the alias names `API_call` and `validate`; rename the model-side `pluck_fields_generator.rb`
  (two files share that name).
- Owner decision needed: keep `raw_sql_query` (owner-authored, token-presence tenant guard)?

### 4.4 New business actions (priority order)
1. Set record fields (entity attributes on `ctx[:model]` from a mapping, through `Entries.assign`).
2. Load the current user or member into ctx (from `current_user_id` / `authentication`).
3. Set submission outcome (translated success message, flash type, redirect target);
   `PublicPagesController` honours it (replaces the response pair).
4. Fail with a business error (translated message → `ctx[:errors]` → failure track).
5. Send SMS (template, recipient from an entity field, variables; wraps `FlowchartRuntime::Sms`).
6. Related-record find / create / update (another entity through its associations, tenant-scoped).
7. Read a Constant or customer setting (with per-customer overrides).
8. Per-tenant sequence number (locked counter for invoice/order numbers).
9. Payments: create order and charge, refund (through `Payments::Activities`).
10. Persisted audit event (tenant-scoped table).
11. Approval / wait for a person (persisted task with assignee and resume token; the largest item —
    consider a separate project; pairs with the handoff/Invocation mechanism).
12. Persisted in-app notification.
13. Document from a template, as PDF, attached to the record.

### 4.5 Step form UX
Picker groups expanded and searchable with visible descriptions (not hover-only); help text per field;
an empty option on optional selects; Change/Remove visible on touch; list and toggle field types;
field-level server errors (the generator reports which field failed); the per-step guard becomes a
structured condition (or is removed in favour of a Decision before the box — owner decision); retry
opt-in only for transport errors; show the effective timeout; no "insert variable" picker on output-name
fields; output auto-suggest never renames `model` / `contract`.

### 4.6 I18n
Render the catalog from keys in both locales (send the overlay for `en` too, or render keyed), walk the
key/value placeholders (146 today), add the 38 missing JS keys and 52 generator keys, delete the 333
stale keys, translate `ConfigValidator`'s message wrappers and fix hints, and set
`raise_on_missing_translations` in the test environment with a spec that every referenced key exists in
both locales.

### 4.7 Stored data
A rake task (`flowcharts:migrate_step_actions`, dry run by default, `APPLY=1` saves a new version and
regenerates) maps removed and merged actions and renamed config keys to their survivors. No aliases.

### 4.8 Proposed task breakdown
- Wave 1: schema DSL + editor export + parity specs (the editor's defaults satisfy the validator); emission
  helpers and runtime helpers (`Step`, `Entries`, retry/timeout rework).
- Waves 2–4: migrate the catalog category by category (model + validation; data; communication +
  background; security + utility; file + caching + concurrency + scheduling + realtime + resilience +
  response + service), applying the schema, helpers, consolidation, I18n and behaviour specs per category.
- Wave 5: new business actions in priority order, step form UX, the migration task, docs, verification.
- Tests: behaviour specs run emitted code against real `EntityEntry` rows of two tenants; a fuzz spec over
  every expression field and the guard; a lint rejecting a literal `true` after a side-effect call.

## 5. Phase 4 — element property editor (not started)

Phase 1 already fixed: Cancel/close restore the snapshot and never dirty the flowchart, the stale
property cache is gone, subflow properties open on double-click, condition rows start empty (no phantom
`signal` operand), step defaults chain.

### 5.1 Remaining problems
- Primary settings sit on the Advanced tab (Loop, End, Subflow); empty tabs render; Advanced is a fixed
  two-column grid with no mobile breakpoint; condition builders get half width; 10–11 px type.
- Dead fields: End `http_response` mode with `httpStatus` / `responseBody`; decision branch
  `description` / `branchKey` / `matchValue` copies (routing reads the connection's match value);
  `defaultBranchIndex` duplicates "empty match value = Otherwise"; loop `accumulatorVariable` on while
  loops (collects 1..N); connection `priority`; leftover Start-trigger code and fix hints.
- Confusing fields: three loop types where do_while is "while, checked after"; `iterations` means max
  passes (default 10) for while but first N items (default 100) for for_each; the break condition is raw
  Ruby while the main condition is structured; decision mode is implicit (a blank operator means value
  matching) and switching mode silently breaks match values; "true (boolean)" / "false (boolean)" /
  "null" options generate strings; duplicate match values are not flagged while duplicate labels are;
  the subflow target is free text that must be a numeric id.
- Round-trip bugs: cleared numbers display the default while nothing is stored; mode switches lose values
  after close; legacy keys can never be removed from the editor; the zh-CN default label is compared with
  the English type name, so automatic labels misfire.
- No inline validation (only native browser bubbles); removing a branch deletes its target element
  without confirmation.
- Dead code: `app/views/shared/_property_editor_modal.html.erb`, `CanvasBridge`, `_showFieldError`,
  `_validateBeforeSave`, `buildInlineCondition`, `buildSegmentedControl`, `branchFallbackNameFormat`;
  hard-coded English in `branch_manager.js`, `canvas_operations.js`, `renderers.js`,
  `condition_builder.js`, `label_derivation.js`, `form_builder.js`; English validation messages in the
  End/Subflow/Start/Decision generators; AI-assistant seeding defaults that ignore visibility rules
  (`ui_config_schema.rb`).

### 5.2 Design — editor-wide
1. Tabs: General (label, the element's main settings, Notes), Steps or Branches (Process, Decision), I/O,
   Advanced only when the type has advanced fields; open on Steps/Branches or General.
2. One-column layout; condition builders and segmented controls full width; two columns only for explicit
   pairs and only from `sm:`.
3. Description becomes a collapsed Notes section.
4. Inline errors under each field with `aria-invalid`, reusing the `element_rules.js` checks; client and
   server severities aligned.
5. Normalization drops non-schema keys except `io_overrides`, `steps`, `branches` and `condition`.
6. Condition builder: no magic operands or literal true/false/null options (use "is true / is false /
   is empty" operators); left operands from entity fields, upstream outputs and a free ctx path.

### 5.3 Design — per element
| Element | Fields (default) | Removed or changed |
|---|---|---|
| Start | Label ("Start"), Notes | no Advanced tab; trigger code removed |
| End | Label; Result: Nothing \| Return a value (`none`); Return value (shown for value, required, default `ctx.result`, help text); Notes | HTTP mode, `httpStatus`, `responseBody` removed from UI and generator |
| Process | Label (auto from the action), Steps tab, Notes | no Advanced tab |
| Decision | Label (auto, unique); Route by: Value \| Yes/No; Value mode: one operand; Yes/No mode: condition rows with required operator and AND/OR; Branches: Name (= connection label), Match value, one "Otherwise" choice (= empty match value); rules: ≥ 2 branches, unique match values, Yes/No needs Yes plus No or Otherwise; warn and offer remapping on mode switch | `defaultBranchIndex`, branch description and `branchKey` removed; match value stored only on the connection |
| Loop | Label (auto); Type: Repeat while \| For each item, plus "Run once before checking" (→ do_while); While: condition required (error, not warning); For each: Collection (required, validated ctx path), Item name (`item`); Max iterations 1–10,000 (default 100 for all types, help text per type); Advanced: Stop early when, Skip item when (for each), Index name, Collect items into (for each only) | accumulator on while removed; defaults unified |
| Subflow | Label; Target flowchart (required, searchable picker of accessible launched flowcharts, stores the numeric id); Notes | free-text id removed |
| Connection | Label, Notes | `priority` removed |

### 5.4 Server side and stored data
Update the End, Decision and Loop generators and validators (translated messages); a migration task
converts stored data (`defaultBranchIndex` → an Otherwise branch, End `http_response` → `none` or
`value`, while-loop accumulators dropped, unified iteration defaults) with versions and regeneration.

### 5.5 Proposed task breakdown
Editor shell (tabs, layout, Notes, inline errors, normalization); condition builder; Decision; Loop;
End; Subflow picker; cleanup (dead code, hard-coded strings, zh-CN label derivation, assistant seeding
defaults); migration task; Playwright scenarios for each editor; docs. Vitest stays at 100%.

## 6. Phase 5 — canvas polish (not started)

Phase 1 already fixed: restore reloads the canvas, one version per real change, platform-aware URLs,
paste copies are independent, decision branches are not renumbered, insert-between keeps decision edge
data, drags need an 8 px threshold and keep tracking outside the SVG, stale undo stacks are discarded,
in-app navigation asks before leaving with unsaved edits, shortcuts are canvas-scoped, connections into
Start / out of End are rejected, A→B and B→A may coexist, test runs do not save, the Elements tab
escapes HTML, the unsaved dot is accurate after a save.

### 6.1 Remaining items and proposed solutions
- **Placement and layout.** Load and multi-drag end call `alignAllElements()`; dragging an element moves
  everything downstream (including shared merge points); repeated paste stacks copies at a fixed 30 px
  offset; the drop animation uses canvas coordinates as screen pixels; the viewBox is recalculated only on
  zoom/pan (coordinates drift after a resize). Proposed: drop exactly where released, never auto-align on
  load or drag; move only the selection; cascade paste offsets; use a `ResizeObserver`; add "+" buttons on
  edges to insert a box, and an undoable "Tidy layout" command.
- **Saving.** No concurrency check — two tabs overwrite each other silently. Proposed: send the expected
  head version id with each save; the controller answers `409 Conflict` with a translated message when the
  head moved; the client offers reload or overwrite. Also: in version-edit mode `based_on_version_id` is
  never updated (return the new version id); non-JSON error responses show "Network error" (check the
  content type and show the server status); add Ctrl+S; the restore confirmation still promises a
  snapshot that is never taken (fix the text or take the snapshot).
- **Undo/redo.** Connection edits in the sidebar bypass undo and the unsaved state; undo resets zoom,
  re-aligns and wipes metadata; snapshots sort elements by random id; every 100 ms typing pause is a
  separate undo entry (one paragraph can evict the 50-entry history). Proposed: route connection edits
  through `onBeforeChange`/`onchange`; restore graphs without resetting the view; stable snapshot order;
  coalesce typing into one entry per field focus.
- **Expanded subflows.** Expanding adds no undo entry; `clear()` keeps `expandedSubflows`, so the next
  save re-inserts the original element; edits inside an expansion are silently dropped on save;
  validation checks the expanded inner elements. Proposed: make expansion a read-only preview (or persist
  edits to the child explicitly), reset state in `clear()`, validate the collapsed graph.
- **Read-only (launched) flowcharts.** Align, distribute, inline label edit and autofix still mutate them.
  Proposed: one read-only guard checked by every mutating command.
- **Validation UX.** The same problem appears up to three times (client rules, server config validator,
  codegen dry run); every new element of a type gets the same default label, which is then flagged as a
  duplicate; the "Add an End" autofix may connect from the wrong element; the "Rename branch" autofix
  changes only the label while routing uses the match value; the badge shows a red "0" when clean.
  Proposed: de-duplicate problems by element and type with the most specific message; unique default
  names ("End 2"); correct autofixes; a neutral badge when clean; block Launch on errors.
- **Readability and I18n.** Node text is tiny and truncated; truncation assumes Latin character widths,
  so zh-CN labels overflow; English in toasts (`toolbar_controller.js`), `" at "` in version dates, raw
  type keys and "in / out" in the Elements tab, `STEP_ACTION_LABELS` and "Step" in tooltips, autofix
  writing "Element"/"Branch" into labels; the minimap is clipped on small screens; test-run overlays drift
  after edits; only the label is redrawn after an edit. Proposed: measure text with real glyph widths,
  larger node typography, Stimulus-value translations, a responsive minimap, clear overlays on edit,
  redraw the whole element.
- **Shortcuts and selection.** Shortcuts fail with Caps Lock; no Shift+click multi-select, Ctrl+A or arrow
  nudging; jumping to a problem leaves a selected connection that Delete then removes; resize handles stay
  after Delete; a new decision branch ignores the dragged port. Proposed: case-insensitive keys, the
  missing shortcuts, clear connection selection on jump, hide handles on delete, honour the dragged port.
- **Cleanup.** Leaked listeners (`flowchartStructureChanged`, palette drop zone, overflow menu document
  handler), uncleared debounce timer, documented-but-ignored parameters, `CanvasBridge` (if Phase 4 has
  not removed it).

### 6.2 Proposed task breakdown
Placement and layout; saving and conflicts (controller + client); undo/redo; expanded subflows;
read-only guard; validation de-duplication and autofix; readability and I18n; shortcuts and selection;
cleanup; Playwright coverage for each (geometry belongs in Playwright, logic in Vitest at 100%).

## 7. Backlog of small follow-ups
- The editor resolves its server URLs from the first flowchart canvas on the page when no controller is
  passed (`app/javascript/flowchart/urls.js`).
- `entity_selector_controller.js` hard-codes `/admin/maintenance/flowcharts.json`.
- One SMS spec fails only in some test orders (`sync_entity_domain_spec.rb:139`).
- `find_model` validation messages use flat `flowchart_actions.*` keys that never resolve (Phase 3).
- Dev database probe flowcharts #6 and #7 are invalid ("Target variable is required").
- Clicking a stored Timer box leaves the previous property form visible (no crash; validation flags it).
- `FlowchartRuntime::Errors.collect` ignores `ctx[:_last_error]` on purpose until Phase 3's `fail_with`
  produces translated messages.
- `IoExtractor` does not detect `ctx.dig(:x)` reads as inputs, so decision operands have no input pins
  (Phase 3's `read` helper fixes this).
- Decision methods use a ternary; long compound conditions would read better as `if/else`.
- A flowchart's first stored activity lacks the `#<id>` in its header (the id is unknown before insert);
  it appears on the next save or regeneration.
- Mermaid edge labels "success" / "failure" are English (pre-existing).

## 8. Owner decisions (answered 2026-10-19)
1. Per-step guard condition: **remove it**. The `flowcharts:migrate_step_actions` task inserts a Decision
   before each box that had a guard.
2. Generic per-step retry: **transport errors only, on HTTP-style actions** that the schema marks
   idempotent.
3. Catalog removals (§4.3) — delegated to the implementer; decided:
   - Replace `render_response` / `redirect_response` with "Set submission outcome": **yes** (both are
     inert at runtime today).
   - `raw_sql_query`: **remove**. Its tenant guard only checks that a token is present in the SQL, which
     cannot prove scoping; `query_models`, `aggregate_query`, `count_records` and `pluck_fields` cover
     the business reads through `FlowchartRuntime::Entries.scope`.
   - `circuit_breaker`: **fold into the HTTP actions** as an advanced option (state in `Rails.cache` under
     a tenant-scoped key); no standalone step.
   - `publish_event` / `broadcast`: **remove** until a live-update feature exists.
   - The other §4.3 removals and merges: **approved** as listed.
4. Approval / wait-for-person: **separate project**, not in Phase 3.
5. Contract key: **keep `ctx[:contract]`**.

6. Phases 4 and 5 (answered 2026-10-19): run **together** from one combined spec and plan, parallel
   tasks with disjoint files, while Phase 3 is paused. An expanded subflow is a **read-only preview**
   (edit the child in its own editor). The restore confirmation text is **fixed**: restoring creates a
   new head version and the old head stays in history (no extra snapshot).

7. Phase 3 resumed 2026-10-19 ("start from Phase 3 until the work is done"); Phases 4 and 5 follow it.
   Superseding the "together" part of item 6, the owner then asked for **Phase 3 → Phase 4 → Phase 5
   strictly in sequence**; the combined `phase45` spec/plan is executed as its Phase 4 tasks first, then
   its Phase 5 tasks, each re-checked against the code left by the previous phase.
   The open questions Q1–Q14 of `docs/superpowers/specs/2026-10-19-flowchart-builder-phase3-design.md`
   take their recommended defaults (Q1: the extra merges are applied, so the catalog is 66 consolidated
   actions + 12 new = 78).

Dev data: the owner will delete all existing flowcharts on the development database manually, so
Task 10 skips `flowcharts:regenerate_activities` on dev (the dry run on 2026-10-19 regenerated 9/11;
#6 and #7 were the known invalid probes). The deploy checklist in §2.5 still applies to other
environments.

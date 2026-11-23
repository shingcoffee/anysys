# Generator QA inventory and execution contracts

Final inventory and verification recorded on 2026-09-09 from the coordinated
release results. There are no task-related test failures; the full RSpec run retains
one independently confirmed baseline announcement-date failure. Inventory is executable in
`spec/services/code_generators/generator_inventory_spec.rb`; the discovery/mapping
implementation is `GeneratorConformance.inventory` in
`spec/support/generator_conformance.rb`.

## What is counted

| Catalog | Count | Identity rule |
| --- | ---: | --- |
| Action implementations | 100 | Unique classes under `element_types/process/` |
| Structural implementations | 6 | Start, End, Decision, Loop, Subflow, Timer |
| Total implementations / dedicated spec paths | 106 | Independent filesystem discovery |
| Registered names | 108 | 106 implementations plus two aliases |
| Live selectable actions | 100 | Actual JS `action_registry.getAllActions()` |
| Editor element types | 7 | Six structural types plus the `process` container |

Aliases are `API_call` / `api_call` for
`CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator`, and
`validate` / `validate_contract` for
`CodeGenerators::ElementTypes::Process::Validation::ValidateContractGenerator`.
The palette selects `API_call` and `validate` respectively. Model
`pluck_model_fields` and data `pluck_fields` are **different implementations**, not
aliases. `process` has no standalone generator: ActivityGenerator composes its
ordered action list.

The inventory discovers `app/services/code_generators/element_types/**/*_generator.rb`
without using the registry's supported-type filter, resolves each Rails constant,
and compares the resulting class set to registration. A missing registration,
duplicate/overwritten name, or unregistered implementation cannot disappear from
the count by being omitted from `GeneratorRegistry.all`.

## Dedicated spec mapping

There is no second hand-maintained list of 106 names. For **each discovered file**:

1. Strip `app/services/` and `.rb`, then Rails-camelize to get its class identity.
2. Replace the leading `app/` with `spec/` and `.rb` with `_spec.rb` to get its
   independently runnable dedicated spec.
3. Require that spec to exist and contain an executable
   `RSpec.describe Fully::Qualified::Generator` declaration naming that class.
   Ripper parses the spec; comments, string mentions, syntax errors, and a
   declaration of another class do not satisfy identity coverage.

All category paths below are relative to
`spec/services/code_generators/element_types/process/`. Each contains the same
number of dedicated `*_generator_spec.rb` files as implementations:

| Backend category directory | Implementations | Frontend context in `actions.test.js` |
| --- | ---: | --- |
| `background/` | 2 | `action configs / background` |
| `caching/` | 4 | `action configs / caching` |
| `communication/` | 5 | `action configs / communication` |
| `concurrency/` | 2 | `action configs / concurrency` |
| `data_operations/` | 32 | `action configs / data` |
| `file_operations/` | 7 | `action configs / file` |
| `model_operations/` | 17 | `action configs / model` |
| `realtime/` | 2 | `action configs / realtime` |
| `resilience/` | 4 | `action configs / resilience` |
| `response/` | 2 | `action configs / response` |
| `scheduling_time/` | 3 | `action configs / scheduling` |
| `security/` | 9 | `action configs / security` |
| `service_invocation/` | 1 | `action configs / service` |
| `utility/` | 8 | `action configs / utility` |
| `validation/` | 2 | `action configs / validation` |

The six structural paths are
`spec/services/code_generators/element_types/{start,end,decision,loop,subflow,timer}/<type>_generator_spec.rb`.

Print **all 106 exact class → dedicated spec path mappings**, with assertions:

```sh
bundle exec rspec spec/services/code_generators/generator_inventory_spec.rb --format documentation
```

Examples of independent dedicated runs (including the basename collision):

```sh
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/pluck_fields_generator_spec.rb
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb
bundle exec rspec spec/services/code_generators/element_types/decision/decision_generator_spec.rb
```

Inventory proves identity and presence, **not** that each dedicated spec has deep
runtime coverage. The execution layers below address different guarantees.

## Backend ↔ editor test identity

The frontend behavior files live in
`spec/javascript/controllers/property_editor/behavior/`. The cross-mapping is:

`getAllActions().value` → Ruby `GeneratorRegistry.find_step_action(value)` →
the discovered class and dedicated spec above. `generator_inventory_spec.rb`
asserts that the 100 actual palette values resolve one-to-one to the 100 action
implementations. `actions.test.js` independently asserts 100 unique palette values
and generates `describe` groups from the same live registry, grouped by category.
Thus every action has a separately selectable frontend identity as well as its
dedicated backend spec; aliases do not inflate implementation coverage.

| UI action | Frontend full context prefix | Backend dedicated spec relative to `spec/services/code_generators/element_types/process/` |
| --- | --- | --- |
| `API_call` | `action configs / communication API_call` | `communication/api_call_generator_spec.rb` |
| `validate` | `action configs / validation validate` | `validation/validate_contract_generator_spec.rb` |
| `pluck_fields` | `action configs / data pluck_fields` | `data_operations/pluck_fields_generator_spec.rb` |
| `pluck_model_fields` | `action configs / model pluck_model_fields` | `model_operations/pluck_fields_generator_spec.rb` |
| Every other action | `action configs / <category.key> <action.value>` | Disk-derived dedicated spec for its resolved class |

For structural editors, the class namespace prefix is `CodeGenerators::ElementTypes::`
and backend paths below are relative to `spec/services/code_generators/element_types/`:

| Editor | Frontend context in `editors.test.js` | Backend identity / dedicated spec | Behavioral focus |
| --- | --- | --- | --- |
| `start` | `start property editor` | `Start::StartGenerator` / `start/start_generator_spec.rb` | Label and description edit, canvas render, reopen |
| `process` | `process property editor` | ActivityGenerator composition; each step maps to its action generator | Step removal, empty collection, picker reopening; all action configs in `actions.test.js` |
| `decision` | `decision property editor` | `Decision::DecisionGenerator` / `decision/decision_generator_spec.rb` | Structured/unary conditions, branch deletion, default destination and port reindexing |
| `loop` | `loop property editor` | `Loop::LoopGenerator` / `loop/loop_generator_spec.rb` | Three segmented modes, conditional required fields, stale-property pruning, cleared iteration value |
| `subflow` | `subflow property editor` | `Subflow::SubflowGenerator` / `subflow/subflow_generator_spec.rb` | Required target and collect/canvas/reopen |
| `timer` | `timer property editor` | `Timer::TimerGenerator` / `timer/timer_generator_spec.rb` | Unit-dependent native limits and numeric persistence in canvas state |
| `end` | `end property editor` | `End::EndGenerator` / `end/end_generator_spec.rb` | Response-mode requirements and removal of inactive HTTP/value properties |

Process composition has independently runnable backend paths
`spec/services/activity_generator_composition_spec.rb` and
`spec/services/code_generators/unprobeable_field_conformance_spec.rb`.
Loop orchestration additionally has `spec/services/activity_generator_loop_spec.rb`
and `spec/services/activity_generator_loop_integration_spec.rb`. Final correctness
review passed, including explicit overrides and merges selected by runtime-executed
branches.

### Focused helper responsibilities and supported loop topology

The implementation keeps orchestration, dataflow planning and runtime state in
small, focused helpers under `app/services/activity_generator/`:

| Helper | Responsibility |
| --- | --- |
| `LoopTopology` | Validate loop regions and provide forward, routing and one-iteration dataflow graph views |
| `ElementIoIndex` / `LoopIoPlan` | Index producers and plan loop slots, initializers, reads, publications and exports |
| `ElementBodyRewriter` | Resolve each original access once; explicit override targets remain terminal snapshot keys |
| `LoopState` | Use Prism source locations to rewrite reads/writes while preserving Ruby assignment semantics |
| `ExecutedOutputs` | Track per-invocation writes and select the latest eligible producer that actually executed, preserving absent/nil/false distinctions |
| `LoopMethodBuilder` | Emit the circuit adapter, initialize incoming state and export only selected, successful loop results, including zero-trip results |

Supported modes are `while`, `do_while` and `for_each`. A nonempty loop has one
header-to-body entry, body backedge(s) to that header and one header-to-exit
continuation. A header directly connected to End may have an empty body. Nested or
overlapping loops, external body entries and body-to-exit shortcuts are rejected.
The execution tests cover the supported topology; this is not arbitrary cyclic-graph
or nested-loop support.

### Frontend behavioral suites and exact selectors

| File under the behavior directory | Implemented coverage |
| --- | --- |
| `actions.test.js` | For every action/schema variant: render/edit/collect/canvas/reopen; clear stored fields; stable step ID; actual picker commit/defaults; initial visibility and every controlling-select option's dependent visibility/required state |
| `editors.test.js` | Seven named editor contexts listed above |
| `read_only.test.js` | `launched property editors`: all seven types stay byte-identical; asynchronous producer controls; delayed read-only transitions; stale I/O responses; draft producer override reopening |
| `validation.test.js` | `native invalid controls in collapsed editor sections`: entity-column dropdown/manual applicability; reveal collapsed step/Advanced section; invalid-event handling and cleanup |

These mount the real Stimulus PropertyEditorController, production managers,
schemas, collectors and SVG FlowchartCanvas. The happy-dom helper normalizes
initial parsed select state from rendered HTML attributes and supplies a `:scope`
selector compatibility shim. Chromium uses the production markup without these
shims. DOM/canvas reopening is not a database save/reload assertion, and the
schema-generated action values are transport probes, not necessarily valid
backend action configurations.

Run the behavior directory, or select one of the **actual declared editor names**:

```sh
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'start property editor'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'process property editor'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'decision property editor'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'loop property editor'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'subflow property editor'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'timer property editor'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/editors.test.js --testNamePattern 'end property editor'
```

Per-action examples use the actual category/action group names. The trailing space
after an action key keeps the selector distinct from longer keys. The optional
`default` group selects the default schema variant; picker tests sit directly
under the action group.

```sh
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/actions.test.js --testNamePattern 'action configs / communication API_call '
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/actions.test.js --testNamePattern 'action configs / validation validate '
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/actions.test.js --testNamePattern 'action configs / data pluck_fields '
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/actions.test.js --testNamePattern 'action configs / model pluck_model_fields '
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/actions.test.js --testNamePattern 'action configs / model find_model default updates findStrategy dependent visibility and required validation for every option'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/read_only.test.js --testNamePattern 'launched property editors decision remains byte-identical'
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/property_editor/behavior/validation.test.js --testNamePattern 'validates only the active entity-column widget'
```

The complete JS coverage command is
`npx vitest run --config config/javascript/vitest.config.js --coverage`.
The final run passed **6283 tests in 278 files**. All **11 touched production JS
files** reached **100% lines, branches and functions**. Repository-wide measured
coverage was **99.96% lines / 99.95% branches**, not 100%; targeted behavior results
alone are not a substitute for that coverage run.

### Browser native submit and save/reload verification

`spec/e2e/flowchart_editors/native_submit.selfcontained.spec.js` has the suite
`native property-editor submit / real production modules`. Its six cases cover:
entity-column selection with an inactive manual input; invalid Subflow target
reveal/focus/correction; Loop mode switching and pruned serialization; End None
with inactive required fields; `find_model` strategy changes plus reopening; and
`aggregate_query` manual-field required validation with `external_amount` reaching
the serialized save payload.
It mounts both production Stimulus controllers and checks the actual PATCH payload
and save-success UI. Only the HTTP save response is supplied by the test: this is
native browser submit/serialization coverage, not Rails persistence coverage.

```sh
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/native_submit.selfcontained.spec.js --config config/javascript/playwright.config.js
```

`spec/e2e/flowchart_editors/action_rendering.selfcontained.spec.js` adds **15
category tests with named Playwright steps for all 100 actual registry actions**.
Tests are named `native action rendering / <category>`. They exercise native select
defaults, every select option, collection/re-render round trips, conditional
visibility and required/optional entity-column dropdown/manual transitions using
the production StepManager and mounted PropertyEditorController, without happy-dom
shims. This rendering-only suite asserts zero fetch/XHR requests; it does not save
diagram state or execute generated Ruby.

```sh
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/action_rendering.selfcontained.spec.js --config config/javascript/playwright.config.js
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/action_rendering.selfcontained.spec.js --config config/javascript/playwright.config.js --grep 'native action rendering / model'
```

`spec/e2e/flowchart_editors/native_submit.app.spec.js` has the suite
`property editor / deployed Rails form and persistence` and the case
`native End submit persists a cleared response configuration across reload`.
Against a disposable editable draft it adds an End node, changes HTTP response to
None, submits through the real form, requires a successful Rails PATCH and saved
indicator, then reloads the page. It locates the persisted node by ID and asserts
`responseType: "none"` with no `httpStatus`, `responseBody`, or `returnValue`.

```sh
APP_BASE_URL=http://127.0.0.1:3001 \
FLOWCHART_EDIT_PATH=/81721200/admin/maintenance/flowcharts/RELEASE_FIXTURE_ID/edit \
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright \
npx playwright test spec/e2e/flowchart_editors/native_submit.app.spec.js --config config/javascript/playwright.config.js
```

Both app environment variables are required; otherwise the Rails-backed case is
explicitly skipped. A skipped run does not verify persistence. The suite does not
start Rails; release supplies the server, editable fixture and refreshed assets
per AGENTS.md. The final Chromium run passed **22 tests, 0 skipped**: six native
submit tests, fifteen action-category tests and the real Rails End save/reload
test. Database round trips are not claimed for every editor or all 100 actions.

Run that combined browser scope with a disposable editable fixture:

```sh
APP_BASE_URL=http://127.0.0.1:3000 \
FLOWCHART_EDIT_PATH=/81721200/admin/maintenance/flowcharts/RELEASE_FIXTURE_ID/edit \
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright \
npx playwright test spec/e2e/flowchart_editors/ --config config/javascript/playwright.config.js --workers=2
```

Evidence: `/tmp/opencode/anysys-final-browser.log` and
`/tmp/opencode/anysys-final-fixture-verification.log`. Fixture cleanup passed;
record 8's attributes, configuration and versions remained unchanged, with no
override heads. Supplemental responsive checks at **390×844, 768×1024 and
1440×900** passed during the initial release verification. Both release target URLs
returned HTTP 200; the verified server was PID **1092976**, port **3000**.

## Independently runnable QA layers

Prefix each path with `bundle exec rspec` (all paths relative to the repository):

| Spec path under `spec/services/code_generators/` | Guarantee |
| --- | --- |
| `generator_inventory_spec.rb` | Disk/registry/spec identity, aliases, actual palette coverage, 7 editor types, mirror parity without writes |
| `contract_parity_spec.rb` | UI contract gaps, complete phase metadata, nonempty category population, negative injected defect/extractor checks |
| `generator_conformance_spec.rb` | Field deltas, explicit validation rejection, accepted enum compilation/collisions, hidden-field behavior, harness negative controls |
| `branch_emission_spec.rb` | Sample plus enumerated single-enum variants; accepted configs must emit compilable source; truncation and all-rejected sweeps fail |
| `unprobeable_field_conformance_spec.rb` | Nested field inventory; executed loop conditions and limits; decision value/boolean routing; ordered process dataflow |
| `catalog_execution_contract_spec.rb` | All 106 sample contracts, 104 callable method definitions, 2 explicit shells, required-field removal, concrete runtime fixtures |
| `generated_activity_execution_spec.rb` | Existing representative facade success/failure and invalid-config persistence contracts |
| `tenant_scoping_spec.rb` | Existing structural tenant-scoping audit over samples and enumerated branches; not a runtime isolation proof |

### New catalog execution coverage

The catalog uses independent disk discovery. Every implementation gets a named
sample example validating, compiling and loading its emitted method into an
isolated anonymous class. It checks the `ctx`/keyword interface and that generation
does not mutate sample configuration. Only Start and Subflow may return no body
or method. Required declarative fields are also removed individually and must be
rejected. These checks do not invoke arbitrary production samples.

The new runtime fixtures invoke full generated methods for **31 distinct actions**
and check concrete output values/side effects:

- Data operations: `any_all_none_check`, `base64_encode_decode`, `calculate`,
  `chunk_collection`, `coalesce_value`, `compare_data`, `date_time_calc`,
  `filter_collection`, `find_in_collection`, `flatten_collection`, `format_string`,
  `generate_id`, `group_collection`, `hash_manipulate`, `log`, `map_value`,
  `math_operation`, `merge_data`, `parse_data`, `partition_collection`,
  `pluck_fields`, `reduce_collection`, `regex_extract`, `serialize_data`,
  `sort_collection`, `string_manipulate`, `type_cast`, `uniq_collection`,
  `zip_collections`.
- Realtime: `broadcast`, `publish_event`, including propagation of a publication
  boundary failure.

Entropy and clock are fixed; logging, Turbo and Notifications use explicit
expected boundary calls/arguments. No database mocks are added. No arbitrary
sample HTTP, job, SQL, or filesystem operation is executed. The process composition
fixture uses an unsaved real Flowchart and an anonymous generated Railway class.

Existing semantic coverage was inspected before adding this catalog. In particular,
`generated_activity_execution_spec.rb` already executes assign-value, HTTP, crypto,
archives, query models, cache/locks, jobs and response payloads; dedicated transform
and map-collection specs already execute those bodies. Utility semantic specs
execute barcode and currency conversion. Dedicated crypto, notification, background
and resilience specs have additional execution cases. The new fixtures emphasize
previously source-oriented data operations and exact realtime boundary arguments,
rather than duplicating those existing scenarios. This is **not** a claim of full
runtime branch coverage for all 106 implementations.

The backend follow-up also added dedicated execution regressions for the seven
resolved contract findings below, plus real-relation batch/upsert cases and
format-string/hash/map-value cases. Those tests complement the catalog's 31-action
fixture list; they do not change its count or imply every action is executed there.

Select a single generator's catalog sample or runtime fixture:

```sh
bundle exec rspec spec/services/code_generators/catalog_execution_contract_spec.rb --example 'CodeGenerators::ElementTypes::Process::DataOperations::SortCollectionGenerator'
bundle exec rspec spec/services/code_generators/catalog_execution_contract_spec.rb --example 'executes sort_collection'
```

## Harness methodology and negative controls

- Validation calls `validate_config` directly, without emitting first. Exceptions
  propagate and non-array validation results fail. Rejected configs are not
  digested as empty source.
- Emission exceptions and syntax errors fail the example. They are never converted
  to strings that could compare different from a successful baseline. Missing
  action source also fails.
- `:changed` means two accepted configurations emitted distinct compilable source.
  `:rejected` means an explicit validation error. `:validation_changed` means an
  invalid conditional baseline became valid when the field was set; the accepted
  variant must still compile. It is not credited as a source delta.
- Hidden-field probes choose a valid hidden mode and remove sibling fields hidden
  by that switch. The probe must either leave emitted source unchanged or be
  explicitly rejected. No valid hidden baseline is an error, not a pass.
- Nested `condition`, `branches`, `steps` fields have explicit execution coverage.
  A new unknown editor type raises instead of silently joining the skipped set.
- Enum sweeps vary one option at a time with visibility anchors, not the Cartesian
  product. Rejected configurations are excluded from source uniqueness checks;
  this does not prove every enum combination has a valid runtime fixture.
- The audit preserves `phase` when flattening gaps; unregistered UI actions have
  phase `unregistered`. Category specs assert a nonempty category before inspecting
  defects. An injected data-category gap proves the filter actually sees defects.
- Live UI extraction is read-only: the existing schema extractor supplies field
  definitions, while Node's module linker evaluates the actual action registry for
  palette identity. Node failures fail the audit. Inventory checks the tracked
  mirror against live extraction without replacing Ruby constants or writing files.

The initial negative-control run reproduced the old failures (8 examples failed).
The corrected controls now pass, including crashing emission, throwing/malformed
validation, invalid Ruby, missing source, and category-loss cases. Run them alone:

```sh
bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb --example 'failure transparency'
bundle exec rspec spec/services/code_generators/contract_parity_spec.rb --example 'preserves category identity' --example 'extractor fails'
```

## Current verification and resolved contract findings

**All seven previously reported contract findings are resolved.** The backend lane
reports **2017 examples, 0 failures** for `generator_conformance_spec.rb` plus the
seven affected dedicated generator specs. This is the supplied backend verification
result, not a new run performed for this documentation-only update. It supersedes
the earlier seven-failure snapshot; those findings are not current blockers.

| Resolved action.field | Dedicated regression spec relative to `spec/services/code_generators/element_types/process/` |
| --- | --- |
| `aggregate_query.groupByFields` | `model_operations/aggregate_query_generator_spec.rb` |
| `clone_model.overrideAttributes` | `model_operations/clone_model_generator_spec.rb` |
| `business_hours_check.holidays` | `scheduling_time/business_hours_check_generator_spec.rb` |
| `compress_files.entries` | `file_operations/compress_files_generator_spec.rb` |
| `download_file.headers` | `file_operations/download_file_generator_spec.rb` |
| `generate_csv.columns` | `file_operations/generate_csv_generator_spec.rb` |
| `ai_inference.tools` | `utility/ai_inference_generator_spec.rb` |

Independently rerun that regression scope:

```sh
bundle exec rspec \
  spec/services/code_generators/generator_conformance_spec.rb \
  spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb \
  spec/services/code_generators/element_types/process/model_operations/clone_model_generator_spec.rb \
  spec/services/code_generators/element_types/process/scheduling_time/business_hours_check_generator_spec.rb \
  spec/services/code_generators/element_types/process/file_operations/compress_files_generator_spec.rb \
  spec/services/code_generators/element_types/process/file_operations/download_file_generator_spec.rb \
  spec/services/code_generators/element_types/process/file_operations/generate_csv_generator_spec.rb \
  spec/services/code_generators/element_types/process/utility/ai_inference_generator_spec.rb
```

### Final integrated verification

These are the supplied final release results, recorded without rerunning tests
for this documentation-only update:

| Scope | Final result |
| --- | --- |
| Full parallel RSpec | **1263 files, 4 workers, 19542 examples: 19475 passed, 1 failure, 66 pending; 329 seconds** |
| Whole code-generator scope | **6754 passed** |
| Combined loop scope | **905 passed** |
| Vitest | **6283 passed / 278 files**; all 11 touched production files at 100% lines/branches/functions; overall 99.96% lines / 99.95% branches |
| Chromium | **22 passed, 0 skipped**, including all 100 actions as named steps and real Rails End persistence |
| Correctness review | **PASS**, including explicit overrides and runtime-executed branch/loop merging |
| Convention review | **PASS**, no introduced lint offenses |
| Scoped Ruby lint | **94 files**, only three baseline offenses: `config/routes.rb:780`, `scripts/audit_generator_ui.rb:312,314` |

Full-suite command and isolated failure rerun:

```sh
bin/rails parallel:prepare && bin/rails parallel:spec
TEST_DATABASE=/tmp/opencode/anysys-generator-final.sqlite3 bundle exec rspec spec/models/platform_announcement_spec.rb:254
```

The full command exits nonzero because of the **one baseline failure**, not a
task-related regression. The remaining example is
`spec/models/platform_announcement_spec.rb:254`, assertion line 259: its intended
future September 1 start is past under the September 9 clock. The isolated rerun
also reports **1 example, 1 failure**. Pristine-HEAD reproduction and the passing
frozen-clock control are documented in [QA_BASELINE_TRIAGE.md](QA_BASELINE_TRIAGE.md).
The prior SQLite `page_size` locks and modal timing failure did **not recur** in
the final run. No task-related failures remain.

Raw evidence:

- `/tmp/opencode/anysys-final-current-parallel-prepare.log`
- `/tmp/opencode/anysys-final-current-parallel-spec.log`
- `/tmp/opencode/anysys-final-current-announcement-rerun.log`

The earlier sections provide independently runnable generator, editor, Vitest and
Chromium commands. The 905-example combined-loop result is the release-reported
combined scope, not the count of any one loop spec file.

The earlier parity runs left no diff in `lib/code_generators/config_schemas.rb`,
`spec/support/config_schemas.rb`, or the prior audit YAML report. The audit CLI
still intentionally writes its documented YAML report; the RSpec entry points call
the read-only report methods instead.

## Coverage limits and future depth

The task is verified with no task-related failures. These boundaries describe the
coverage honestly; they are not unresolved task defects:

- Sample validation/compilation covers all 106 implementations, while the new
  catalog executes 31 distinct actions. Dedicated runtime cases add depth, but
  there is no claim of full runtime branch coverage across all generators.
- Further useful execution fixtures include authentication/JWT rejection outcomes,
  tenant-record bulk import/raw SQL, and email/webhook/service argument and failure
  behavior. Source assertions and facade tests alone do not prove generated wiring.
- All 100 action renderers are checked in Chromium; only the End browser case
  proves Rails save/reload. Generic editor transport probes are not necessarily
  server-valid configs and do not constitute 100 end-to-end Ruby execution fixtures.
- Single-option emission sweeps are not a Cartesian product. Broader data-runtime
  cases could cover null/stable sorting, divide-by-zero policies, malformed and
  alternate serialization formats, accumulator choices and DST transitions.
- Nested loops are explicitly unsupported. Repository-wide JS coverage remains
  below 100%, despite complete measured coverage for every touched production file.

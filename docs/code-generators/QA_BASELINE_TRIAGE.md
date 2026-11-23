# Isolated QA baseline triage — 2026-09-09

This records the isolated baseline investigation and spec-lint cleanup. The final
release result is now recorded in `QA_INVENTORY.md`: **19542 examples, 19475 passed,
1 baseline failure, 66 pending**, with no task-related failures. The diagram
regression is fixed; only the preexisting announcement-date example remains.

## Isolation and baseline

- Pristine commit: `5f4d95ca9a1dff386480bcbdd97127dd0d93f26e`
  (`module setting ui/ux refactor`).
- Detached worktree: `/tmp/opencode/anysys-qa-head-5f4d95ca`.
- Baseline DB: `/tmp/opencode/anysys-qa-head-20260909.sqlite3`.
- Current-tree QA DB: `/tmp/opencode/anysys-qa-current-20260909.sqlite3`.
- Both databases were loaded with `RAILS_ENV=test TEST_DATABASE=<path> bundle exec
  rails db:schema:load`. No shared test database was used.
- After baseline execution, `git status --porcelain` was empty and
  `git diff --exit-code` returned 0 in the detached worktree. No stash/reset or
  source changes were applied to the baseline.

Baseline command, run in the detached worktree:

```sh
TEST_DATABASE=/tmp/opencode/anysys-qa-head-20260909.sqlite3 bundle exec rspec spec/models/platform_announcement_spec.rb:254 spec/services/activity_diagram_generator_spec.rb:132
```

Result: **exit 1; 2 examples, 1 failure**. Only the announcement example failed;
the subprocess double-bracket diagram example passed. The equivalent current-tree
examples, before the diagram fix, both failed. The five lint-edited spec files were
included in that current-tree run: **242 examples, 2 failures**, with all 240
lint-scope examples passing.

## Announcement: confirmed preexisting clock-dependent spec

`spec/models/platform_announcement_spec.rb:254` sets `starts_at` to the local
`now + 1.day`, where `now` is fixed at `2026-08-31 12:00:00`, but calls
`discard_or_destroy!` without `travel_to(now)`. Its supposedly future start is
therefore September 1, already past at the September 9 execution time.

`PlatformAnnouncement#live?` uses the actual `Time.current`; a published row with
that start and no end is live, so `discard_or_destroy!` soft-deletes it and retains
the record. The assertion at line 259 expecting `find_by` to return nil fails on
pristine HEAD as well as the current tree. The production behavior follows its
existing live-announcement retention contract.

Control experiment on the **same pristine HEAD**, changing only the in-process
test clock (no spec/model file edits):

```sh
TEST_DATABASE=/tmp/opencode/anysys-qa-head-20260909.sqlite3 bundle exec ruby -I spec -r rspec/core -r rails_helper -e 'RSpec.configure { |config| config.around(:each) { |example| travel_to(Time.zone.parse("2026-08-31 12:00:00")) { example.run } } }; exit RSpec::Core::Runner.run(["spec/models/platform_announcement_spec.rb:254"])'
```

Result: **exit 0; 1 example, 0 failures**. Announcement production code and its spec
remain unchanged by this QA task; this is baseline evidence, not a suppressed failure.

The final `bin/rails parallel:prepare && bin/rails parallel:spec` run reproduced
this as its sole failure across **1263 files / 4 workers**, completing in **329
seconds**. A final isolated rerun also produced **1 example, 1 failure**. Evidence:
`/tmp/opencode/anysys-final-current-parallel-spec.log` and
`/tmp/opencode/anysys-final-current-announcement-rerun.log`.

## Diagram: active-change regression, fixed

`spec/services/activity_diagram_generator_spec.rb:132` passes on pristine HEAD.
The active ActivityGenerator changes use
`Subprocess(child).merge(task: :method_name, id: :method_name)` to wrap child execution
with guards and parent-routing preservation. This replaces the activity-class task
with a circuit method while preserving the child's `Trailblazer::Activity::End`
output signals. ActivityDiagramGenerator previously recognized subprocesses only
when the task itself was an activity class, so it rendered the guarded child with
single brackets and ordinary-step styling.

The fix in `app/services/activity_diagram_generator.rb` also inspects the node's
output signals for wrapped child activities. It preserves native activity-class
detection and does not infer semantics from user-controlled labels. The existing
double-bracket assertion now passes; an added integration assertion checks actual
subprocess style assignment while retaining ordinary-step styling. ActivityGenerator
and loop execution code were not changed by this fix.

## Lint cleanup and targeted verification

The requested seven offenses were fixed with narrow `apply_patch` edits:

- `loop_generator_spec.rb`: quoted-symbol hash label syntax only.
- `format_string_generator_spec.rb`: two numeric-leading symbol hash labels.
- `test_runner_spec.rb`: quoted locale-symbol hash label syntax.
- `io_params_spec.rb`: blank lines after two `let` groups.
- `generator_inventory_spec.rb`: `contain_exactly` for the literal alias list.

Current-tree verification after the diagram fix:

```sh
TEST_DATABASE=/tmp/opencode/anysys-qa-current-20260909.sqlite3 bundle exec rspec \
  spec/services/activity_diagram_generator_spec.rb \
  spec/services/activity_generator_composition_spec.rb \
  spec/services/code_generators/element_types/loop/loop_generator_spec.rb \
  spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb \
  spec/services/code_generators/test_runner_spec.rb \
  spec/requests/admin/maintenance/flowcharts/io_params_spec.rb \
  spec/services/code_generators/generator_inventory_spec.rb
```

Result: **exit 0; 263 examples, 0 failures**.

```sh
bundle exec rubocop \
  app/services/activity_diagram_generator.rb \
  spec/services/activity_diagram_generator_spec.rb \
  spec/services/code_generators/element_types/loop/loop_generator_spec.rb \
  spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb \
  spec/services/code_generators/test_runner_spec.rb \
  spec/requests/admin/maintenance/flowcharts/io_params_spec.rb \
  spec/services/code_generators/generator_inventory_spec.rb
```

Result: **exit 0; 7 files inspected, no offenses**. `git diff --check` also passed.
Final convention review passed with no introduced offenses. The broader 94-file
Ruby lint scope retained only three baseline offenses at `config/routes.rb:780`
and `scripts/audit_generator_ui.rb:312,314`. Correctness review also passed,
including explicit overrides and runtime-executed branch/loop merging.

The earlier SQLite `page_size` lock failures and modal timing issue did **not
recur** in the final full suite. Final focused results were **6754 code-generator
passes** and **905 combined-loop passes**. Full JS/browser results, fixture cleanup
and coverage limits are recorded in `QA_INVENTORY.md`.

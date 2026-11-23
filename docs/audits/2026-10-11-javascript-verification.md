# JavaScript QA and release verification — 2026-10-11

**Latest completed full unit result: 6,956 passed, 0 failed, with 100% configured-scope coverage**, read from the 2026-10-12 [preview lifecycle evidence](#2026-10-12--preview-lifecycle-completed-evidence-6956-tests). Earlier full runs, intermittent failures and executed lint/helper checks remain below. Final combined RSpec/Playwright outcomes are pending in their execution lanes; this report's JS pass does not supply those gates.

## Initial verification result

**Verification is failing.** The full Vitest suite has two failed assertions, lint has one error and one warning, and the full browser suite has two environment-dependent failures plus 287 skips. All four touched JavaScript files have measured **100% lines, branches, and functions** in a subsequent narrow coverage run; this does not make the failing tests pass or establish whole-application coverage.

| Check | Observed result |
| --- | --- |
| Full Vitest | 290 files: 288 passed, 2 failed; 6,937 tests: 6,935 passed, 2 failed, 0 skipped; 426.46 seconds |
| Four-file coverage diagnostic | 4 files: 3 passed, 1 failed; 295 tests: 294 passed, 1 failed, 0 skipped; 16.32 seconds |
| Four-file coverage | Lines/statements 1,898/1,898; branches 711/711; functions 148/148: all 100% |
| Full lint | 2 problems: 1 error, 1 warning |
| Full Playwright | 318 tests using 2 workers: 29 passed, 2 failed, 287 skipped; 58.4 seconds |
| Existing server health | Port 3000 listening; initial five-second health request timed out; subsequent `/up` request returned HTTP 500 |

Instructions read: `AGENTS.md` and `spec/javascript/AGENT_GUIDE.md`. Verification ran in `/home/ec2-user/anysys`, using the explicit JavaScript configs from `package.json`. The full Vitest and Playwright suites each ran once. The only additional test run was the four-file coverage diagnostic described below. The only authored workspace change in this verification is this audit report.

## Full Vitest run

Command:

```bash
npx vitest run --config config/javascript/vitest.config.js --coverage
```

Exact summary output:

```text
 Test Files  2 failed | 288 passed (290)
      Tests  2 failed | 6935 passed (6937)
   Start at  16:39:53
   Duration  426.46s (transform 7.11s, setup 9.27s, collect 31.77s, tests 331.46s, environment 377.98s, prepare 114.94s)
```

Vitest reported version `2.1.9` and `Coverage enabled with v8`, but emitted no coverage summary or report artifacts for this failing full run. The config does not enable `coverage.reportOnFailure`. Immediately after the run, `coverage/javascript` did not exist. **Whole-application coverage percentages and the whole-application uncovered-file/line/branch inventory are therefore unavailable from this run.** They must not be inferred from the narrow diagnostic's output.

### Every failed Vitest test

1. **AI assistant: selected-thread event**
   - File/test: `spec/javascript/controllers/ai_assistant_controller.test.js:242`, `ai-assistant controller > announces selected-thread updates and clearing from its own panel`.
   - Failed assertion: `spec/javascript/controllers/ai_assistant_controller.test.js:251:45`.
   - Actual output: `AssertionError: expected null to be <div …(13)>…(12)</div> // Object.is equality`.
   - After `await tick()`, `changed.mock.calls[0][0].target` is `null`; the test expects the mounted panel element. The preceding one-call assertion passed; the subsequent detail/clearing assertions were not reached in this test.
   - Related source: `app/javascript/controllers/ai_assistant_controller.js:89-90`, `conversationIdValueChanged` dispatches `conversationChanged` with `{ conversationId }`.
   - Reproduced in the four-file diagnostic at the same assertion. The full run reports 176 tests in this file, 175 passed and 1 failed.

2. **Page builder: new-card entrance animation**
   - File/test: `spec/javascript/controllers/page_builder/drag_drop_manager.test.js:168`, `DragDropManager.flipFromRects — write-phase branches > clamps the entrance offset to the drop point and animates a NEW dropped card`.
   - Failed assertion: `spec/javascript/controllers/page_builder/drag_drop_manager.test.js:177:37`.
   - Actual output: `AssertionError: expected 'translate(120px, -120px) scale(0.96)' to be '' // Object.is equality`.
   - The transform is still the entrance transform after `await flush()`; the test expects an empty transform. Its following opacity assertion was not reached.
   - Related source: `app/javascript/controllers/page_builder/drag_drop_manager.js:95` sets the transform; the nested animation-frame callback at `:99-103` clears transform and opacity. The test's flush waits 10 ms (`spec/javascript/controllers/page_builder/drag_drop_manager.test.js:118`). This report records the observed failure without establishing its root cause.
   - The full run reports 19 tests in this file, 18 passed and 1 failed. This file was not rerun.

The full log also contains stderr from passing error-path tests, aborted happy-dom iframe requests to `http://localhost:3000/preview`, and a missing vendored `diff.js` source-map warning. These are retained in the raw log; the runner's failed-test count is two.

## Measured coverage of the four touched files

Because the failed full run suppressed coverage output, one narrow diagnostic enabled reporting on failure and restricted coverage to the four touched source files. It used the same project config, aliases, setup, environment, provider, and reporters. This was not a second full-suite run.

Command:

```bash
npx vitest run --config config/javascript/vitest.config.js \
  spec/javascript/controllers/captcha_aliyun_controller.test.js \
  spec/javascript/controllers/payments/stripe_card_controller.test.js \
  spec/javascript/controllers/speech_to_text_controller.test.js \
  spec/javascript/controllers/ai_assistant_controller.test.js \
  --coverage --coverage.reportOnFailure \
  --coverage.include=app/javascript/controllers/captcha_aliyun_controller.js \
  --coverage.include=app/javascript/controllers/payments/stripe_card_controller.js \
  --coverage.include=app/javascript/controllers/speech_to_text_controller.js \
  --coverage.include=app/javascript/controllers/ai_assistant_controller.js
```

Exact summary output:

```text
 Test Files  1 failed | 3 passed (4)
      Tests  1 failed | 294 passed (295)
   Start at  16:47:53
   Duration  16.32s (transform 1.08s, setup 440ms, collect 2.09s, tests 11.51s, environment 5.82s, prepare 1.81s)

 % Coverage report from v8

=============================== Coverage summary ===============================
Statements   : 100% ( 1898/1898 )
Branches     : 100% ( 711/711 )
Functions    : 100% ( 148/148 )
Lines        : 100% ( 1898/1898 )
================================================================================
```

Per-file metrics below are from the generated `coverage/javascript/lcov.info` (`LF/LH`, `BRF/BRH`, `FNF/FNH`), not estimated from test counts.

| Source under `app/javascript/controllers/` | Tests passed / failed | Lines covered / total | Branches covered / total | Functions covered / total | Uncovered lines / branches / functions |
| --- | --- | --- | --- | --- | --- |
| `captcha_aliyun_controller.js` | 29 / 0 | 104/104 (100%) | 51/51 (100%) | 14/14 (100%) | 0 / 0 / 0 |
| `payments/stripe_card_controller.js` | 41 / 0 | 309/309 (100%) | 100/100 (100%) | 15/15 (100%) | 0 / 0 / 0 |
| `speech_to_text_controller.js` | 49 / 0 | 321/321 (100%) | 126/126 (100%) | 27/27 (100%) | 0 / 0 / 0 |
| `ai_assistant_controller.js` | 175 / 1 | 1,164/1,164 (100%) | 434/434 (100%) | 92/92 (100%) | 0 / 0 / 0 |

**Uncovered-location inventory for these four files: none.** All four LCOV records have matching found/hit totals and no zero-hit line, branch, or function records. LCOV counter evidence: AI assistant at lines 95-96, 1353-1354, 1789-1790; captcha at 1808-1809, 1928-1929, 1981-1982; speech-to-text at 2013-2014, 2363-2364, 2491-2492; Stripe at 2511-2512, 2837-2838, 2939-2940.

`app/javascript/controllers/billing_settings_controller.js` and its mirrored test are already deleted in the working tree. They are absent from the current source/test scope and have no coverage percentage in this report.

The full config's exclusions remain documented at `config/javascript/vitest.config.js:53-60`: `application.js`, page-builder `drag_engine.js` and `drag_engine/**`, and flowchart `drag_handler.js`. Browser-only geometry coverage depends on Playwright; skipped app-backed drag tests below do not establish that coverage.

## Full lint run

Command: `npm run lint`, which runs `eslint --config config/javascript/eslint.config.js app/javascript`.

Exact diagnostic output:

```text
/home/ec2-user/anysys/app/javascript/controllers/entity_form/template_builder.js
  273:34  warning  'name_slug' is defined but never used. Allowed unused args must match /^_/u  no-unused-vars

/home/ec2-user/anysys/app/javascript/controllers/website_builder_controller.js
  26:32  error  Unexpected control character(s) in regular expression: \x00, \x1f  no-control-regex

✖ 2 problems (1 error, 1 warning)
```

These are all lint findings. Neither finding is in the four touched files. Lint is failing on the `no-control-regex` error.

## Full browser run and server environment

`APP_BASE_URL` was unset. `ss` showed an existing Puma listener on `0.0.0.0:3000` (PID 1087059). The initial `curl` to `http://127.0.0.1:3000/up` timed out after five seconds with `HTTP status: 000`. A later request with a 15-second limit returned `HTTP status: 500`.

The existing development database was not a permitted browser-test target. Most app-backed specs gate themselves on `APP_BASE_URL`, but `spec/e2e/email_template_builder_sync.app.spec.js:3` defaults directly to port 3000 and has no such skip guard. To run the requested full command without sending browser requests to that development server, Playwright ran inside a new user/network namespace with loopback enabled and `APP_BASE_URL` unset. The config's Python static fixture server ran on port 3011 inside that namespace; the existing Rails server was unreachable there.

Executed wrapper (with stdout/stderr captured through `tee`):

```bash
unshare --user --map-root-user --net bash -c \
  'ip link set lo up && env -u APP_BASE_URL npm run test:e2e'
```

The npm script invoked `playwright test --config config/javascript/playwright.config.js`, with no spec filtering. Exact summary output:

```text
Running 318 tests using 2 workers

  2 failed
    [chromium] › spec/e2e/email_template_builder_sync.app.spec.js:6:3 › Email template builder — insert + editor sync › inserts a variable and syncs Rich Text ↔ HTML
    [chromium] › spec/e2e/email_template_builder_sync.app.spec.js:67:3 › Email template builder — insert + editor sync › preview HTML matches rich text editor fragment
  287 skipped
  29 passed (58.4s)
```

### Every failed browser test

1. `spec/e2e/email_template_builder_sync.app.spec.js:6:3`, **inserts a variable and syncs Rich Text ↔ HTML**. Failure at `:7:16`, the initial `page.goto`.
2. `spec/e2e/email_template_builder_sync.app.spec.js:67:3`, **preview HTML matches rich text editor fragment**. Failure at `:68:16`, the initial `page.goto`.

Both failures have identical output:

```text
Error: page.goto: net::ERR_CONNECTION_REFUSED at http://127.0.0.1:3000/81721200/admin/modules/emails/templates/new
```

Both stopped at initial navigation, before their editing/preview assertions. These are absent-app/ungated-spec failures in the isolated environment; they do not establish an email-editor functional regression.

### Passed and skipped browser coverage

All 29 runnable self-contained tests passed:

- `spec/e2e/flowchart_editors/action_rendering.selfcontained.spec.js`: 15 tests.
- `spec/e2e/flowchart_editors/native_submit.selfcontained.spec.js`: 9 tests.
- `spec/e2e/flowchart_editors/pin_handoff.selfcontained.spec.js`: 4 tests.
- `spec/e2e/sortable_reorder.selfcontained.spec.js`: 1 real-pointer drag test.

The 287 app-backed tests skipped with `APP_BASE_URL` unset. Their individual file/test/line entries are in the browser log. Skips include `spec/e2e/page_builder_drag.app.spec.js:29`, `spec/e2e/flowchart_node_drag.app.spec.js:28`, `spec/e2e/entity_attribute_reorder.app.spec.js:17`, and `spec/e2e/speech_to_text_mic.app.spec.js:14`. Those application-level geometry/microphone checks remain unverified. A separately prepared release smoke environment is needed for application-backed acceptance.

## Evidence and log paths

Raw stdout/stderr was captured with `set -o pipefail` and `tee`; failed commands were not converted into successful runs.

| Evidence | Path |
| --- | --- |
| Full Vitest log | `/tmp/opencode/2026-10-11-javascript-verification-vitest.log` |
| Narrow four-file coverage log | `/tmp/opencode/2026-10-11-javascript-verification-touched-coverage.log` |
| Lint log | `/tmp/opencode/2026-10-11-javascript-verification-lint.log` |
| Full browser log, including every skipped case | `/tmp/opencode/2026-10-11-javascript-verification-e2e.log` |
| Subsequent server health result | `/tmp/opencode/2026-10-11-javascript-verification-health.log` |
| Full Vitest tool-output capture | `/home/ec2-user/.local/share/opencode/tool-output/tool_12bdb54b9001FG98puZqJlj8RU` |
| Full browser tool-output capture | `/home/ec2-user/.local/share/opencode/tool-output/tool_12bde07de0010sEhq2dieMpqnC` |
| Four-file LCOV artifact | `coverage/javascript/lcov.info` |
| Four-file HTML coverage report | `coverage/javascript/index.html` |
| Playwright outcome/test IDs | `test-results/.last-run.json` |
| First browser failure context/trace | `test-results/email_template_builder_syn-eb240--and-syncs-Rich-Text-↔-HTML-chromium/error-context.md`, adjacent `trace.zip` |
| Second browser failure context/trace | `test-results/email_template_builder_syn-e54b6-s-rich-text-editor-fragment-chromium/error-context.md`, adjacent `trace.zip` |

The coverage artifacts listed here belong to the narrow diagnostic only. Full-suite reruns are deferred until fixes, as requested.

## Final combined-code verification

After the reported JavaScript/test/lint fixes, the user authorized a full Vitest coverage rerun and lint against the combined working tree. **The latest full run passed all 6,942 tests across 290 test files, and measured 100% lines, branches, functions, and statements across the entire configured coverage scope. Lint passed with zero errors and zero warnings.**

The exact requested Vitest command first encountered a different AI-assistant assertion failure. A second full run enabled only `coverage.reportOnFailure` so complete coverage artifacts would be emitted even if tests failed; that run passed. Both outcomes are recorded here. The passing run does not erase the preceding intermittent failure or establish its cause.

### Requested full rerun: one observed failure

Command:

```bash
npx vitest run --config config/javascript/vitest.config.js --coverage
```

Exact summary output:

```text
 Test Files  1 failed | 289 passed (290)
      Tests  1 failed | 6941 passed (6942)
   Start at  17:34:07
   Duration  364.91s (transform 8.03s, setup 8.58s, collect 30.47s, tests 298.79s, environment 321.56s, prepare 98.66s)
```

There were zero skipped tests. The sole failed test was:

- Definition: `spec/javascript/controllers/ai_assistant_controller.test.js:275`, `ai-assistant controller > stays busy after 202 until an assistant bubble arrives`.
- Failed assertion: `spec/javascript/controllers/ai_assistant_controller.test.js:290:23`, `expect(ctrl.busy).toBe(false)` after appending an assistant bubble and awaiting `tick()`.
- Exact diagnostic: `AssertionError: expected true to be false // Object.is equality`.
- The later button-visibility assertions in this test were not reached. No root cause was established in this verification.

Coverage was again suppressed by the default reporting-on-failure behavior, and `coverage/javascript` was absent after this run. This failure therefore had no generated full-scope missed-line inventory of its own. The original selected-thread and page-builder assertions did not fail in this rerun.

### Additional full run: complete coverage artifacts

Command:

```bash
npx vitest run --config config/javascript/vitest.config.js --coverage --coverage.reportOnFailure
```

The additional option changes only when reports are written. There were no test filters, `coverage.include` overrides, new exclusions, changed thresholds, source/spec edits, or coverage-data edits by this verifier.

Exact summary output:

```text
 Test Files  290 passed (290)
      Tests  6942 passed (6942)
   Start at  17:40:29
   Duration  250.16s (transform 6.63s, setup 5.62s, collect 23.80s, tests 188.08s, environment 224.97s, prepare 68.07s)

 % Coverage report from v8

=============================== Coverage summary ===============================
Statements   : 100% ( 57566/57566 )
Branches     : 100% ( 16364/16364 )
Functions    : 100% ( 3335/3335 )
Lines        : 100% ( 57566/57566 )
================================================================================
```

There were zero failed or skipped tests in this run. The busy-state assertion that failed in the preceding full run passed here without edits by this verifier.

### Full configured coverage scope and missed locations

Coverage used `config/javascript/vitest.config.js` directly: `include: ["app/javascript/**/*.js"]`, `all: true`, V8 provider, and the existing `application.js`/browser-only drag exclusions at lines 53-60. The coverage scope was not narrowed to the touched files. Browser-only excluded engines still require application-backed Playwright acceptance.

Read-only LCOV validation found **283 source-file records**, with totals matching the Vitest summary and generated HTML report exactly:

| Metric | Covered / total | Coverage | Uncovered locations |
| --- | --- | --- | --- |
| Lines | 57,566/57,566 | 100% | None |
| Branches | 16,364/16,364 | 100% | None |
| Functions | 3,335/3,335 | 100% | None |
| Statements | 57,566/57,566 | 100% | None |

**Exact missed-file/line/branch/function inventory: empty.** The LCOV scan found no zero-hit `DA` or `FNDA` records and no zero-hit/unexecuted `BRDA` records across all 283 source-file records. The machine-readable validation output is retained in the LCOV-check log below. This validates the final full-scope artifact; it does not reconstruct coverage for either earlier failed run.

### Lint rerun

Command: `npm run lint`.

Exact complete output:

```text

> lint
> eslint --config config/javascript/eslint.config.js app/javascript

```

The command completed successfully with **0 errors and 0 warnings**. The earlier `no-control-regex` error and unused-`name_slug` warning were absent.

### Follow-up evidence and artifacts

| Evidence | Path |
| --- | --- |
| Requested full rerun log, including the busy-state failure | `/tmp/opencode/2026-10-11-javascript-verification-final-vitest.log` |
| Passing full coverage run log | `/tmp/opencode/2026-10-11-javascript-verification-final-full-coverage.log` |
| Clean lint log | `/tmp/opencode/2026-10-11-javascript-verification-final-lint.log` |
| Read-only full-scope LCOV validation | `/tmp/opencode/2026-10-11-javascript-verification-final-lcov-check.log` |
| Requested full rerun tool-output capture | `/home/ec2-user/.local/share/opencode/tool-output/tool_12c0c44e4001GQocmPz4Tz35ZZ` |
| Passing full coverage tool-output capture | `/home/ec2-user/.local/share/opencode/tool-output/tool_12c107d4b001chP5I2L8sd0PuW` |
| Final full-scope LCOV | `coverage/javascript/lcov.info` |
| Final full-scope HTML report | `coverage/javascript/index.html` |
| Final full-scope LCOV HTML report | `coverage/javascript/lcov-report/index.html` |
| Complete, unmodified final coverage-directory archive | `/tmp/opencode/2026-10-11-javascript-verification-final-coverage.tar.gz` |

The standard `coverage/javascript` paths now contain the final full-scope artifacts and supersede the initial narrow diagnostic's unversioned artifact paths. The earlier command logs, failure details, and narrow coverage counts remain preserved in this report. The archive contains the complete generated coverage directory without report edits or file exclusions.

**Browser acceptance remains pending a dedicated application server and `APP_BASE_URL`.** No browser suite, application-server preparation, migrations, or fixture preparation ran during this follow-up. The only authored workspace change in this follow-up is the audit report.

## 2026-10-12 — current-tree four-worker verification

**Current JavaScript verification: PASS.** The requested full Vitest command passed **6,942 tests across 290 files**, with **100% lines, branches, functions, and statements** across the configured coverage scope. Full lint passed with **0 errors and 0 warnings**. The existing Node helper test file passed **3 tests**. All three commands exited **0**.

This execution used `/home/ec2-user/anysys` and the instructions in `AGENTS.md` and `spec/javascript/AGENT_GUIDE.md`. Vitest ran once with at most four workers; lint ran afterward. The Node helper tests ran concurrently with Vitest. This verifier made no application, spec, helper, or configuration edits, and added no skips, coverage exclusions, or ignore pragmas. The only authored workspace change is this appended audit section. RSpec and browser verification belong to the other execution lanes and were not run here.

The earlier selected-thread, busy-state, and entrance-animation failures remain recorded above. None failed in this run; a passing rerun does not establish their earlier cause.

### Commands, exit statuses, and durations

| Check | Exact command | Exit | Actual result | Runner duration | Command wall time |
| --- | --- | --- | --- | --- | --- |
| Full Vitest coverage | `npx vitest run --config config/javascript/vitest.config.js --coverage --maxWorkers=4 --minWorkers=1` | 0 | 290 files passed; 6,942 tests passed; 0 failed, 0 skipped | 255.78 s | 260.07 s |
| Full lint, after Vitest | `npm run lint` | 0 | 0 errors, 0 warnings | Not separately reported | 12.16 s |
| Node helper tests | `node --test spec/e2e/helpers/provider_backend.test.js` | 0 | 3 passed; 0 failed, cancelled, skipped, or todo | 3,241.194141 ms | 3.38 s |

Raw stdout/stderr and timing were captured using `set -o pipefail` and `/usr/bin/time -f 'elapsed_seconds=%e\ncommand_exit=%x' <command> 2>&1 | tee <log>`. Pipeline failures retain their nonzero status. Command wall time includes launcher/report-generation overhead and differs from the runner's internal duration.

### Full Vitest output and current coverage

Exact summary output:

```text
 Test Files  290 passed (290)
      Tests  6942 passed (6942)
   Start at  03:55:27
   Duration  255.78s (transform 5.46s, setup 7.96s, collect 24.58s, tests 236.94s, environment 309.80s, prepare 87.78s)

 % Coverage report from v8

=============================== Coverage summary ===============================
Statements   : 100% ( 57566/57566 )
Branches     : 100% ( 16364/16364 )
Functions    : 100% ( 3335/3335 )
Lines        : 100% ( 57566/57566 )
================================================================================
elapsed_seconds=260.07
command_exit=0
```

A read-only scan of the newly generated `coverage/javascript/lcov.info` found **283 source-file records**. Aggregate line, branch, and function counters match the runner output exactly. There are **0 uncovered files, lines, branches, or functions** within that scope: no zero-hit `DA`/`FNDA` entries and no zero-hit or unexecuted `BRDA` entries.

The full existing config was used, including `all: true` and `include: ["app/javascript/**/*.js"]`; coverage was not narrowed to changed files. The existing entrypoint/browser-only exclusions listed earlier remain the configured boundary of this measurement.

The table covers all six modified, still-present JavaScript source files in `git diff`, plus the drag-drop manager whose test was modified. Counts are from this full run's LCOV artifact; every listed percentage is **100%**.

| Source under `app/javascript/controllers/` | Tests passed / failed | Lines covered / total | Branches covered / total | Functions covered / total | Uncovered lines / branches / functions |
| --- | --- | --- | --- | --- | --- |
| `ai_assistant_controller.js` | 176 / 0 | 1,164/1,164 | 434/434 | 92/92 | 0 / 0 / 0 |
| `captcha_aliyun_controller.js` | 29 / 0 | 104/104 | 51/51 | 14/14 | 0 / 0 / 0 |
| `entity_form/template_builder.js` | 46 / 0 | 415/415 | 140/140 | 18/18 | 0 / 0 / 0 |
| `payments/stripe_card_controller.js` | 41 / 0 | 309/309 | 100/100 | 15/15 | 0 / 0 / 0 |
| `speech_to_text_controller.js` | 49 / 0 | 321/321 | 126/126 | 27/27 | 0 / 0 / 0 |
| `website_builder_controller.js` | 161 / 0 | 1,170/1,170 | 610/610 | 102/102 | 0 / 0 / 0 |
| `page_builder/drag_drop_manager.js` | 19 / 0 | 129/129 | 41/41 | 5/5 | 0 / 0 / 0 |

`billing_settings_controller.js` and its test remain deleted in the existing working tree; there is no current source record or coverage percentage for that deletion. **Failed-test and uncovered-location inventories for this run are empty.**

### Lint output

Exact complete output:

```text

> lint
> eslint --config config/javascript/eslint.config.js app/javascript

elapsed_seconds=12.16
command_exit=0
```

### Node helper verification and read-only fixture review

Glob verification confirmed `spec/e2e/helpers/provider_backend.test.js` exists. Its three tests passed:

1. `database guard rejects missing paths, shared databases and mismatched inherited URLs`.
2. `Rails database configuration can be read without creating a database`.
3. `local provider speaks normal and streaming OpenAI HTTP plus multipart transcription`.

Exact TAP totals:

```text
1..3
# tests 3
# suites 0
# pass 3
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 3241.194141
elapsed_seconds=3.38
command_exit=0
```

Read-only review covered the ten files under `spec/e2e/helpers/` and their `spec/e2e/support/bootstrap.rb` and `provider_server.rb` implementations. Observed shell/process and fixture boundaries:

- Current subprocess call sites use `execFileSync` or `spawn` with executable names and argument arrays; none requests `shell: true` or constructs a shell command string. Bootstrap mode selection is allowlisted.
- `rails_runner.js` restricts the database to a dedicated direct child of app-local `storage/`, with a `browser*.sqlite3` or `e2e*.sqlite3` filename, rejects existing path aliases/symlinks and mismatched inherited `DATABASE_URL`, permits only development/test, and rejects `E2E_STUB_ASSISTANT=1`.
- The database configuration is checked by loading `config/application` before application initialization/connection. The Node test confirmed its probe database did not exist before or after inspection. The Ruby bootstrap independently checks the database identity before loading `config/environment`; bootstrap create/export use the isolated environment, with export assigning the same path to `TEST_DATABASE`.
- Website fixtures require an already prepared isolated database and the pinned owner. Their token is a validated 32-character hexadecimal UUID, fixture method names are fixed internal calls, and string arguments are JSON-serialized into the Rails runner argument. Cleanup scopes to the customer/site and the exact two token-owned slugs rather than deleting by prefix.
- The provider uses a loopback WEBrick listener and the fixed dummy bearer credential. The passing test exercised unauthorized/unknown requests, normal and streaming chat, and multipart audio; its health assertions confirmed request metadata omitted authorization headers and message bodies. SDK endpoint preload requires a loopback HTTP `/v1` endpoint and development/test configuration.

This review inspected the bootstrap/fixture code without executing create, apply, export, cleanup, an application server, or a browser suite. The helper test executed only its guarded configuration probe and local HTTP provider.

### Current evidence paths

| Evidence | Path |
| --- | --- |
| Full four-worker Vitest log | `/tmp/opencode/2026-10-12-javascript-verification-vitest-max4.log` |
| Full lint log | `/tmp/opencode/2026-10-12-javascript-verification-lint.log` |
| Node helper test log | `/tmp/opencode/2026-10-12-javascript-verification-node-helpers.log` |
| Read-only LCOV validation, including every touched-file count and uncovered inventory | `/tmp/opencode/2026-10-12-javascript-verification-lcov-check.log` |
| Full Vitest tool-output capture | `/home/ec2-user/.local/share/opencode/tool-output/tool_12e43e3f50016jBACEu9frhXih` |
| Current full-scope LCOV | `coverage/javascript/lcov.info` |
| Current full-scope HTML reports | `coverage/javascript/index.html`, `coverage/javascript/lcov-report/index.html` |

The standard coverage paths now hold this run's generated reports. Previous command outcomes and intermittent-failure details above are preserved; this append records the current JS lane only.

## 2026-10-12 — website preview-race follow-up evidence verification

**Latest verified JS result: PASS — 6,948 full-suite tests, 100% configured-scope coverage, clean current lint, and 4 passing current Node helper tests.** The website agent's existing full run was verified against the current tree and reused. This verifier did not repeat Vitest. Lint and the updated helper tests were executed here; the initial helper invocation failed its environment guard and the subsequent isolated invocation passed, both recorded below.

The supplied `website-followup-20261012-qa4.log`/`.json` are browser-lane artifacts. The matching **full JavaScript** evidence is `/tmp/opencode/website-followup-20261012-vitest.log`, read through its final coverage summary. Its website test file reports **167 passed tests**, including the new stale-response/disconnect cases, rather than the earlier 161. This append preserves the previous 6,942-test results and historical intermittent failures.

### Existing full-run output

The existing raw log identifies Vitest `2.1.9` with V8 coverage. Exact final output:

```text
 Test Files  290 passed (290)
      Tests  6948 passed (6948)
   Start at  05:15:10
   Duration  187.13s (transform 6.61s, setup 5.43s, collect 23.93s, tests 182.70s, environment 231.53s, prepare 64.23s)

 % Coverage report from v8

=============================== Coverage summary ===============================
Statements   : 100% ( 57574/57574 )
Branches     : 100% ( 16371/16371 )
Functions    : 100% ( 3335/3335 )
Lines        : 100% ( 57574/57574 )
================================================================================
```

There are **0 failed or skipped tests** in the completed runner summary. The raw log does not retain the originating shell command/argv, worker limit, command wall time, or numeric process exit status; those metadata are not reconstructed or attributed to this verifier. The full test inventory and coverage scope are validated directly below. The earlier explicitly executed four-worker command remains recorded in the preceding section.

### Current-source proof and coverage-artifact validation

The read-only inventory at **05:28:40 UTC** checked **598 files** under `app/javascript/`, `spec/javascript/`, and `vendor/javascript/`, plus the Vitest/ESLint configs and npm package/lock files. **No checked file or source/test/vendor directory had an mtime or ctime later than the existing full run's 05:15:10 UTC start.** The newest source/test files are the website controller and its mirrored test, both saved at **05:14:47.435 UTC**, before that run. The inventory also records current Git HEAD/status and SHA-256 hashes for every checked file.

- Current full-suite inventory: **290 test files**. The raw log contains exactly those 290 passing file records, totaling **6,948 tests**; no current test file is missing from the run and no logged test file is missing from the tree.
- Current production inventory: **286 JavaScript files**, yielding **283 expected coverage records** after the existing config's exclusions. LCOV contains exactly those 283 records, with no missing or unexpected source files.
- Full log mtime: **05:18:17.616 UTC**. LCOV mtime: **05:18:18.626 UTC**. LCOV totals match the raw runner summary: lines **57,574/57,574**, branches **16,371/16,371**, functions **3,335/3,335**, all **100%**.
- A second hash check at **05:30:50 UTC**, after the helper rerun, found **0 changed files** relative to the 598-file inventory. The existing measured JS inputs therefore remained current throughout this verification.
- Final inventory/hash check at **05:32:22 UTC** again found **0 added, removed, or changed files**, no newer source/test/vendor directories, and an unchanged full-run log.
- **Uncovered inventory: empty** across all 283 records. There are no zero-hit line/function entries or zero-hit/unexecuted branch entries. This verifier changed no coverage data, config, scope, exclusions, tests, or application code.

Artifact SHA-256:

| Artifact | SHA-256 |
| --- | --- |
| Existing full Vitest log | `d9ae80dd8ba98098d4bee7aff9e8fb34d806914e96b570afd4020ab86306891c` |
| Current full-scope LCOV | `d0d56aacf39b78ce5dc4f1514fb697ec725a9dcc63b2c103af25e340fa52007a` |

Current per-touched-file counts are from this existing full run's LCOV. Every metric below is **100%**:

| Source under `app/javascript/controllers/` | Tests passed / failed | Lines covered / total | Branches covered / total | Functions covered / total | Uncovered lines / branches / functions |
| --- | --- | --- | --- | --- | --- |
| `ai_assistant_controller.js` | 176 / 0 | 1,164/1,164 | 434/434 | 92/92 | 0 / 0 / 0 |
| `captcha_aliyun_controller.js` | 29 / 0 | 104/104 | 51/51 | 14/14 | 0 / 0 / 0 |
| `entity_form/template_builder.js` | 46 / 0 | 415/415 | 140/140 | 18/18 | 0 / 0 / 0 |
| `payments/stripe_card_controller.js` | 41 / 0 | 309/309 | 100/100 | 15/15 | 0 / 0 / 0 |
| `speech_to_text_controller.js` | 49 / 0 | 321/321 | 126/126 | 27/27 | 0 / 0 / 0 |
| `website_builder_controller.js` | 167 / 0 | 1,178/1,178 | 616/616 | 102/102 | 0 / 0 / 0 |
| `page_builder/drag_drop_manager.js` | 19 / 0 | 129/129 | 41/41 | 5/5 | 0 / 0 / 0 |

The deleted billing-settings controller/test still have no current source/coverage record.

### Newly executed lint and helper checks

Lint and the first helper invocation ran concurrently. Exact command: `npm run lint`. Complete output:

```text

> lint
> eslint --config config/javascript/eslint.config.js app/javascript

elapsed_seconds=7.97
command_exit=0
```

Result: **0 errors, 0 warnings; exit 0; 7.97 seconds wall time**.

#### Initial helper invocation: missing isolated environment

Exact command: `node --test spec/e2e/helpers/provider_backend.test.js`.

Actual result: **2 passed, 2 failed, 0 skipped; exit 1; 4,305.53908 ms runner duration; 4.85 seconds wall time**. Both failures occurred before schema export or HTTP assertions:

- `local provider speaks normal and streaming OpenAI HTTP plus multipart transcription`, definition at `spec/e2e/helpers/provider_backend.test.js:47:1`.
- `fixture validation rejects serializer String types and malformed conditional/union output`, definition at `spec/e2e/helpers/provider_backend.test.js:90:1`.

Both reported `E2E_DATABASE_PATH must name a dedicated app-local storage/browser*.sqlite3 or storage/e2e*.sqlite3 file`, from `isolatedEnvironment` → `runRails` → `providerSchemas`. The updated tests now resolve actual application schemas through the guarded Rails runner, so these two cases require the existing isolated environment. The database-guard and configuration-only probe cases passed in this invocation. The failing raw log is preserved.

#### Isolated helper rerun: 4 passed

After reading the existing isolated database/preload configuration and confirming the database exists, executed:

```bash
env -u E2E_STUB_ASSISTANT -u TEST_DATABASE -u TEST_ENV_NUMBER \
  RAILS_ENV=development \
  E2E_DATABASE_PATH=/home/ec2-user/anysys/storage/browser_audit_final.sqlite3 \
  DATABASE_URL=sqlite3:/home/ec2-user/anysys/storage/browser_audit_final.sqlite3 \
  RUBYOPT=-r/tmp/opencode/browser-final-sqlite.rb \
  node --test spec/e2e/helpers/provider_backend.test.js
```

Exact TAP totals:

```text
1..4
# tests 4
# suites 0
# pass 4
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 109073.988776
elapsed_seconds=109.45
command_exit=0
```

The four passing cases cover database guards, the non-creating configuration probe, normal/streaming chat and multipart audio, and JSONSchemer validation of resolved entity/flowchart contracts. The schema checks accept valid Calculated formulas, presence validators and select options, while rejecting serializer `type: "String"`, missing conditional fields, invalid visibility and malformed option unions. Audio metadata includes a verified SHA-256 of the uploaded bytes. Schema/document payloads are JSON-serialized through subprocess stdin; current subprocess calls use argument arrays rather than shell command strings.

This rerun reused the existing isolated database for schema resolution and a temporary loopback provider; no schema load, fixture bootstrap, application server, browser suite, RSpec suite, or source/spec edit was performed by this verifier. Both helper outcomes are distinct evidence, not test counts to add together.

### Follow-up evidence paths

| Evidence | Path |
| --- | --- |
| Reused full Vitest output | `/tmp/opencode/website-followup-20261012-vitest.log` |
| Current-source mtime/ctime/Git/hash proof and test inventory | `/tmp/opencode/2026-10-12-javascript-verification-website-followup-source-proof.json` |
| LCOV scope/totals/touched-file validation and subsequent source-hash check | `/tmp/opencode/2026-10-12-javascript-verification-website-followup-lcov-check.json` |
| Final current-tree inventory/hash recheck | `/tmp/opencode/2026-10-12-javascript-verification-website-followup-final-source-check.json` |
| Newly executed clean lint | `/tmp/opencode/2026-10-12-javascript-verification-website-followup-lint.log` |
| Initial helper run, including both environment-guard failures | `/tmp/opencode/2026-10-12-javascript-verification-website-followup-node-helpers.log` |
| Passing isolated helper rerun | `/tmp/opencode/2026-10-12-javascript-verification-website-followup-node-helpers-isolated.log` |
| Validated generated coverage | `coverage/javascript/lcov.info`, `coverage/javascript/index.html`, `coverage/javascript/lcov-report/index.html` |

The only authored workspace change in this follow-up is this appended audit section. The existing full-run evidence was sufficient for the current tree, so no additional full Vitest run was needed.

## 2026-10-12 — preview lifecycle completed evidence: 6,956 tests

The documentation integration lane read the existing lifecycle-run log, generated `coverage-summary.json`, controller and mirrored spec. **Completed full JS evidence is 6,956 passed / 0 failed across 290 files**, with 100% configured-scope lines, statements, branches and functions. No Vitest, lint, RSpec, browser suite or subagent was run by this integration lane; the evidence belongs to the earlier lifecycle execution. The original audit filename is retained.

### Source and regression trace

`website_builder_controller.js#initialize` sets `previewRevision` once. `connect()` leaves it intact; `disconnect()` and `reloadPreview()` invalidate earlier requests and clear debounce work. Private `#scheduleLivePreview` invalidates at edit time, before debounce; `#pushLivePreview` checks its captured revision before installing HTML or cleaning up an error. Resetting the counter on reconnect would reuse a revision and admit old response/error work.

The mirrored spec grew from **167 to 175 tests**, adding exactly **8** lifecycle/upload cases: two deferred-preview response/body cases, three stale-preview rejected/non-OK/body-error cases, and three old-upload rejected/non-OK/invalid-JSON cases. The tests disconnect/reconnect the same actual Stimulus controller and retain the independent image-upload identity guard. Existing stale edit/save/disconnect regressions remain. This is consolidated source bug **W09**, not eight separate production bug roots.

### Completed runner output and coverage

Exact full-log summary:

```text
 Test Files  290 passed (290)
      Tests  6956 passed (6956)
   Start at  06:07:12
   Duration  120.17s (transform 4.52s, setup 2.94s, collect 14.93s, tests 118.29s, environment 157.38s, prepare 38.58s)

Statements   : 100% ( 57577/57577 )
Branches     : 100% ( 16374/16374 )
Functions    : 100% ( 3336/3336 )
Lines        : 100% ( 57577/57577 )
```

The full log's website file record is **175 tests passed**. Its generated coverage summary agrees with the raw aggregate above and records the controller at **1,181/1,181 lines/statements**, **619/619 branches**, **103/103 functions**, all 100%. The preceding completed controller-only run also reports **175/0**, 7.28 seconds, and those same controller metrics. These overlapping runs are separate evidence, not additive totals.

| Evidence | Retained path |
| --- | --- |
| Completed full run | `/tmp/opencode/website-lifecycle-20261012-full.log` |
| Full generated summary and LCOV | `/tmp/opencode/website-lifecycle-20261012-full-coverage/coverage-summary.json`, adjacent `lcov.info` |
| Completed controller-only run | `/tmp/opencode/website-lifecycle-20261012-targeted.log` |
| Controller-only generated reports | `/tmp/opencode/website-lifecycle-20261012-targeted-coverage/` |
| Lifecycle regression evidence | `/tmp/opencode/website-lifecycle-20261012-regression-before.log`, `website-lifecycle-20261012-regression-reproduced.log`, `website-lifecycle-20261012-regression-native-lifecycle.log` |

The raw full log and coverage summary retain actual counts and runner timing, but not the originating shell argv or numeric exit status; those fields are not reconstructed here. The lifecycle lint log is empty and does not by itself establish an exit status. Earlier explicitly recorded lint/helper outcomes remain in their own sections. Existing configured entrypoint/browser-only geometry exclusions remain the measurement boundary.

**Final combined gates: PENDING.** The [RSpec report](2026-10-11-rspec-verification.md) and [browser report](2026-10-11-browser-verification.md) will hold the actual eight-worker/four-worker outcomes. At this reconciliation, their last completed results remain **25,266/1** and **331 cases, 330 passed/1 failed** respectively. The [fixed ledger](2026-10-11-fixed-bug-ledger.md#final-combined-execution-slots--parent-handoff) and [route manifest](2026-10-11-route-audit-manifest.md#final-combined-execution-slots--parent-handoff) retain explicit parent-fill slots.

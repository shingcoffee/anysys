# Mission: drive assigned JS files to 100% Vitest coverage (lines AND branches AND functions)

You are an anysys-qa-engineer writing **Vitest** unit tests. Read `spec/javascript/AGENT_GUIDE.md`
FIRST — it is the canonical convention (mirror path, bare-specifier imports, mock vendored deps,
characterize ACTUAL behavior, never write fake-geometry assertions that pass on zeros).

## Your goal
For EACH source file in your assigned list, extend its mirror test at
`spec/javascript/<same path>.test.js` until that source file reports **100% lines, 100% branches,
100% functions**. Mirror tests already exist for every file — you are EXTENDING them, not starting
from scratch.

## Never modify production code
NEVER edit anything under `app/javascript`, `vendor/`, or `config/`. Tests only. If a source line
looks like a real bug, note it in your final report — do not "fix" it.

## The coverage loop (do this per file)
1. Run coverage scoped to your area, writing to YOUR OWN reports dir (avoid clobbering peers):
   `npx vitest run --coverage --coverage.reportsDirectory=coverage/AREA spec/javascript/<your dirs>`
   (replace AREA with a unique slug you pick, e.g. `js-entityform`.)
2. See exactly which lines/branches/funcs are uncovered for your files:
   `LCOV=coverage/AREA/lcov.info node spec/javascript/support/coverage_gaps.mjs <substr> [<substr>...]`
   Pass path substrings that match your files (e.g. `entity_form/schema_manager`). It prints
   `uncovered lines:`, `uncovered funcs:`, `uncovered branches: line N branch#K`.
3. Open the source at those line numbers, understand the untaken path, write a test that exercises it
   (characterize the real behavior — verify empirically with a tiny logging test if unsure).
4. Repeat until the helper prints `✅100%` for every one of your files.

## happy-dom limits (from prior work — real env constraints, not app bugs)
- `getBoundingClientRect`/layout return ZEROS. For geometry math you can still often cover a branch by
  stubbing: `Object.defineProperty(el, "getBoundingClientRect", { value: () => ({ x, y, width, height, top, left, right, bottom }) })`, or by stubbing `el.offsetWidth`, `el.scrollTop`, `PointerEvent` coords via a plain object event, `requestAnimationFrame` (already stubbed in setup.js — check it). USE these to reach geometry branches.
- happy-dom CSS quirks: `[name*='[action]']` attr-value selectors mis-parse; `:scope > svg` returns null; repeated `<select>.value` writes don't refresh `selectedOptions`. Drive such paths via datasets/fallbacks.
- If — and ONLY if — a specific line/branch is GENUINELY impossible to exercise in happy-dom (it needs
  a real layout/pointer engine and no stub can fake it), do NOT fake it. Record it in your final report
  as `UNREACHABLE: <file>:<line> — <reason>`. Do not add `/* v8 ignore */` to source.

## Rules
- Mock vendored/side-effecting deps: `vi.mock("sortablejs")`, `vi.mock("diff")`, `vi.mock("mermaid")`, fetch, etc.
- Use the mount helper `spec/javascript/support/stimulus.js` (`mountController`) for controller tests.
- Keep tests focused/readable; group with `describe`, use `it`/`it.each`.

## Definition of done
- The gap helper prints `✅100%` for EVERY file in your list (or the file is on your final report's
  UNREACHABLE list with a concrete per-line reason).
- Your area's vitest run is fully GREEN (0 failures).
- Final report: files taken to 100%, any UNREACHABLE lines (file:line + reason), any suspected source bugs, total tests added.

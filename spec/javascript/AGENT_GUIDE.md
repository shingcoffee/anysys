# JS Test-Writing Guide (read this fully before writing tests)

You are writing **Vitest** unit tests for this Rails app's JavaScript. Infrastructure is
already set up and proven. Your job: write real, passing tests for an assigned list of
source files, maximizing meaningful coverage.

## Where things live
- Source: `app/javascript/**`
- Tests: `spec/javascript/**` — mirror the source path. For
  `app/javascript/controllers/foo/bar_controller.js` write
  `spec/javascript/controllers/foo/bar_controller.test.js`.
- Run YOUR tests: `npx vitest run spec/javascript/<your area>` (from the worktree root,
  which is your cwd). Use `--reporter=verbose` to see individual cases.

## How imports resolve (importmap mirror)
`config/javascript/vitest.config.js` aliases bare specifiers to `app/javascript`:
- `import x from "controllers/…"` → app/javascript/controllers/…
- `import x from "lib/…"`, `"flowchart/…"`, `"constants/…"`, `"versions/…"` → same pattern
- `import { fns } from "utils"` → app/javascript/utils/index.js
- Vendored libs: `"sortablejs"`, `"diff"` resolve to vendor/javascript. `@hotwired/stimulus`
  is a real npm dep (already installed).

**Import your target the same way the app does** (bare specifier), e.g.
`import Controller from "controllers/entity_form/dnd_manager"`.

## Two proven patterns — READ THESE FILES FIRST
1. **Pure-logic (no DOM):** `spec/javascript/lib/formula_engine.test.js` — import the
   module, call functions, assert. No DOM needed.
2. **Stimulus controller (needs DOM):** `spec/javascript/controllers/countable_items_reorder_controller.test.js`
   plus the mount helper `spec/javascript/support/stimulus.js`. Use
   `mountController(identifier, ControllerClass, html)` to mount in happy-dom, then dispatch
   events / assert on the DOM. Import the helper via a RELATIVE path, e.g.
   `import { mountController, click } from "../support/stimulus.js"` (adjust `../` depth to
   your test file's location).

## Rules
- **environment is happy-dom** (configured globally). `document`/`window` exist.
- **Mock vendored/side-effecting deps** with `vi.mock("sortablejs", …)`, `vi.mock("diff", …)`,
  `vi.mock("mermaid", …)` etc. — see the countable-items exemplar for the shape.
- **DOM-free modules** (pure functions, config/data objects, class logic that never touches
  `document`): test directly, no mounting. Many `flowchart/constants/*` files just export
  config objects — assert their shape/keys/invariants.
- **Geometry-dependent code is OUT OF SCOPE for you.** If a file's core logic depends on real
  layout (`getBoundingClientRect`, `PointerEvent` coordinates, `requestAnimationFrame` +
  measured positions, scroll offsets), you CANNOT meaningfully unit-test that path in happy-dom
  (it returns zeroed rects). Test whatever pure/DOM-structural logic you can, and add a top-of-file
  comment `// NOTE: <fn> requires real layout — covered by Playwright (spec/e2e), not unit.`
  Do NOT write fake-geometry assertions that pass on zeros.
- **NEVER modify any file under `app/javascript`, `vendor/`, or `config/`.** Tests only.
  If a source file looks buggy, note it in your final report — do not "fix" it.
- Prefer characterization: assert the code's ACTUAL current behavior. If a result surprises you,
  verify empirically (write a tiny logging test, run it) before asserting — do not guess.
- Keep each test file focused and readable; group with `describe`, use `it`/`it.each`.

## Definition of done for your batch
1. A `.test.js` file exists for every assigned source file that has testable logic.
   (If a file is a pure re-export/barrel or is geometry-only, a short file with a NOTE comment
   explaining why is acceptable — but still create the file.)
2. `npx vitest run spec/javascript/<your area>` is **fully green** (0 failures).
3. Report: which files you covered, total test count, and any files you could only partially
   cover (with the reason).

# Property editor behavioral checks

## Every element editor (Phase 4)

```sh
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/element_editors.selfcontained.spec.js --config config/javascript/playwright.config.js
```

Static fixture + real PropertyEditor / FlowchartCanvas controllers and the
committed ElementCatalog. Covers Start, End (Nothing / Return a value), Process
step add/remove, Decision (Route by value and Yes/No, add/rename/Otherwise,
remove keeps the box, duplicate match values and two Otherwise flagged inline),
Loop (while ⇄ for each, run once first, blank max iterations, advanced
stop/skip), Subflow searchable picker (numeric id), and the Connection form
(label + Notes). Each editor runs at 375 px and 1280 px and asserts the
sidebar does not overflow horizontally.

## Local Chromium / production JavaScript

```sh
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/native_submit.selfcontained.spec.js --config config/javascript/playwright.config.js
```

Uses the existing Playwright static server and the real PropertyEditorController,
FlowchartCanvasController, schemas, managers, SVG canvas, native form validation,
and save serialization. Only the HTTP save response is supplied by the test.
The fixture uses the project's built Tailwind stylesheet. No happy-dom selection
workaround is used in Chromium.

## All 100 action renderers / native controls

```sh
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/action_rendering.selfcontained.spec.js --config config/javascript/playwright.config.js
```

Fifteen category tests reuse a browser mount within each category, with a named
Playwright step for every action in the actual registry. Checks cover native
select defaults, every select option and collection/re-render round trip,
conditional visibility, and every entity-column dropdown/manual transition.
Required and optional column widgets honour `requiredWhen` and checkbox
`visibleWhen` (for example `followRedirects` → `maxRedirects`). This
rendering-only suite uses the production StepManager on a mounted
PropertyEditorController; it performs no diagram state operations and asserts
zero fetch/XHR requests. The native-submit suite also verifies that a manual
`find_model` attribute reaches the real canvas controller's serialized save
payload.

## I/O request handoff / native Chromium

```sh
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/flowchart_editors/pin_handoff.selfcontained.spec.js --config config/javascript/playwright.config.js
```

Uses both real controllers and deferred pin HTTP responses. Checks close/reopen
with an identical-config background refresh, config changes in both response
orders, and switching selection before delivery. Assertions inspect the active
pane without reopening it; the fresh-first case asserts rendering while the
obsolete response is still pending. Identical in-flight reads share one request.

## Release handoff / Rails-backed persistence

Run against a **disposable draft flowchart**; the app test adds and saves an End
node, then reloads the real Rails page to verify the persisted configuration.

```sh
APP_BASE_URL=http://127.0.0.1:3001 \
FLOWCHART_EDIT_PATH=/81721200/admin/maintenance/flowcharts/RELEASE_FIXTURE_ID/edit \
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright \
npx playwright test spec/e2e/flowchart_editors/native_submit.app.spec.js --config config/javascript/playwright.config.js
```

Both environment variables are required; otherwise this test is explicitly
skipped. Release should refresh assets before executing against its server per
AGENTS.md. This suite does not boot or restart Rails.

## Vitest

`spec/javascript/controllers/property_editor/behavior/` mounts the real editor
and canvas. `actions.test.js` generates identifiable category/action contexts for
all 100 registry entries. It exercises every config field's edit/clear/reopen,
picker defaults, initial visibility, and every conditional selector option.
`editors.test.js` has separate contexts for the seven supported element types;
`read_only.test.js` covers launched-state immutability and asynchronous I/O races.

`interaction_seams.test.js` covers false/zero operands and key-value entries,
deletion-triggered autosync, unfinished action changes with edited guards,
read-only → draft control restoration, and selection-switch I/O invalidation.
`pin_races.test.js` exercises the real pin clients/canvas with delayed HTTP
responses: bulk/pane/refresh ownership, config/action changes, and removal.
The native-submit browser suite also checks flat condition member removal,
key-value deletion without another edit, and read-only → draft Save restoration.
All self-contained tests use in-memory records and intercepted HTTP, without DB
fixtures.

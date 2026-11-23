# Layer 2 — Playwright (Tier C) real-browser tests

These cover the geometry-dependent JavaScript that happy-dom **cannot** honestly
test: drag-and-drop engines, canvas node positioning, pointer/`requestAnimationFrame`
flows that read real layout via `getBoundingClientRect`.

## Two kinds

- `*.selfcontained.spec.js` — serve a tiny static HTML fixture (no Rails) and drive
  the vendored interaction lib directly. Proves the refactored library (SortableJS)
  reorders under real pointer events. **Runs with no extra setup** — the Playwright
  `webServer` (python3 http.server on :3011) serves fixtures automatically.

- `*.app.spec.js` — drive the real Rails app's drag engines (`page_builder/drag_engine`,
  `flowchart/drag_handler`, `entity_form/dnd_manager`). These are **gated**: they
  `test.skip` unless `APP_BASE_URL` points at a running server, because they need
  seeded fixtures (a page with fields, an entity with attributes, a flowchart with nodes).

## Running

```bash
# Self-contained (always runnable):
PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test spec/e2e/*.selfcontained.spec.js

# App-backed: boot the app first (from the worktree root), then point the tests at it.
#   rm -f public/assets/.manifest.json
#   SKIP_AUTH=1 bin/rails server -b 127.0.0.1 -p 3001
# then, in another shell:
APP_BASE_URL=http://127.0.0.1:3001 \
  PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright \
  npx playwright test spec/e2e/*.app.spec.js
```

Chromium is the locally-cached Playwright build (revision 1228); no network needed at run time.

## Reproducible application fixtures

Use a dedicated SQLite file directly under this application's `storage/`. All
runner helpers require `E2E_DATABASE_PATH`; an inherited `DATABASE_URL` must be
byte-identical to `sqlite3:<absolute path>`. The helper first loads only Rails
application configuration and asserts the adapter, environment and exact path,
**before connecting or creating a database**. `check` does not create a file.
Default development/test/production databases and symlinks are rejected.

```bash
export E2E_DATABASE_PATH="$PWD/storage/browser_audit_v2.sqlite3"
export DATABASE_URL="sqlite3:$E2E_DATABASE_PATH"
export RAILS_ENV=development APP_HOST=127.0.0.1 APP_PORT=3001
node spec/e2e/helpers/bootstrap.js check
node spec/e2e/helpers/bootstrap.js create # new file only; schema load + fixture apply
# If the DB team already prepared this exact file:
node spec/e2e/helpers/bootstrap.js apply
```

`apply` runs `spec/e2e/support/bootstrap.rb`, is idempotent and prints JSON
containing the actual `PAGE_EDIT_PATH`, `FLOWCHART_EDIT_PATH`, `ENTITY_EDIT_PATH`
and `E2E_ASSISTANT_CONVERSATION_ID`. Pass those values to Playwright; menu/studio
checks pin this read-only seeded conversation while mutation tests create and
clean up their own threads and uniquely named entities per test/worker.
It uses current factories/model validation, version callbacks and official module
provisioners. Fixtures include the pinned platform owner, all registered modules,
an accessible entity-backed **First name** email token, employee/invoice mention
candidates, nine draft spaced-name flowcharts with Start/Process/**End** nodes,
a page with three fields, and two conversations with persisted messages. No
compiled HTML is fabricated. Re-applying keeps existing fixture definitions.

### Isolated drag and native-submit regression checks

`entity_attribute_reorder.app.spec.js`, `flowchart_node_drag.app.spec.js`, and
`flowchart_editors/native_submit.app.spec.js` use
`helpers/drag_fixtures.js` + `helpers/drag_fixtures.rb` to create UUID-named,
customer-owned records per test through the existing factories and version
callbacks. They require the same checked database environment as the server.
They do not use `ENTITY_EDIT_PATH` / `FLOWCHART_EDIT_PATH` for mutations. Cleanup
destroys only each test's exact records and checks that the three bootstrap
entities and nine mention/runtime flowcharts retain identical attributes.

The entity check waits for asynchronous Stimulus loading, scrolls both visible
grips into view before pressing, and uses Chromium mouse input to produce native
HTML5 drag/drop. The flowchart check targets the live `canvasWrapper` SVG and a
`data-element-id` card. Its fresh Start/Process/End fixture uses the current End
properties (`responseType: "none"`); vertical mouse movement allows the engine's
alignment guides to preserve X. Both checks Save through the UI, verify a new
persisted version, reload, and assert the saved order / SVG transform. Passive
event observers require trusted browser input; no synthetic drag dispatch or
editor-method invocation drives these checks.

The app-backed native-submit check shares this per-test fixture pipeline with
`flowchartEndResponse: "http_response"`. It seeds an HTTP-response End node in
the owned record, opens that visible card with a real mouse double-click, changes
the response to None, and submits the native form. It checks the exact owned
PATCH endpoint, trusted native submit, new database version, pruned response
properties, and reopened/reloaded UI. Fixtures are test-scoped (never a shared
`beforeAll` flowchart); teardown deletes only that UUID's flowchart/entity. All
three app-backed checks retain the complete bootstrap baseline comparison, so a
concurrent baseline mutation remains a failure.

```bash
# With APP_BASE_URL and the matching E2E_DATABASE_PATH / DATABASE_URL exported:
npx playwright test --config config/javascript/playwright.config.js --workers=2 \
  --output=/tmp/opencode/drag-followup/<unique-run> --trace=on \
  spec/e2e/entity_attribute_reorder.app.spec.js spec/e2e/flowchart_node_drag.app.spec.js

# Combined parallel isolation check, including the nine static native-form cases:
npx playwright test --config config/javascript/playwright.config.js --workers=4 \
  --output=/tmp/opencode/drag-isolation-final --trace=on \
  spec/e2e/entity_attribute_reorder.app.spec.js spec/e2e/flowchart_node_drag.app.spec.js \
  spec/e2e/flowchart_editors/native_submit.app.spec.js \
  spec/e2e/flowchart_editors/native_submit.selfcontained.spec.js
```

Attachments include initial/final database snapshots, cleanup/isolation proof,
trusted input events, browser errors, rendered DOM, screenshots, and persistence
proof. `--trace=on` retains the real-browser trace for successful checks as well.

### Local provider HTTP service

The bootstrap assigns the official `openai_whisper` provider to both jobs using
only `e2e-local-dummy-key` and valid normal model settings. Menu/studio specs use
`helpers/assistant_ui.js` to intercept assistant writes and assert no enqueue
occurred. Real mutation/audio checks use the SDK's actual HTTP client.

Current provider rows have no API-base field. The explicit test-only preload
configures the **documented SDK base URL** in RubyLLM and ruby-openai; it neither
replaces provider methods nor enables `E2E_STUB_ASSISTANT`. Use it for both the
Rails process and any separately launched job worker. The default async adapter
runs jobs inside the server.

```bash
# Terminal 1: same dedicated database environment as the server; exports the
# resolved application contracts through the guarded, read-only Rails runner
node spec/e2e/helpers/provider_backend.js

# Terminal 2: with the same database environment as above
export E2E_PROVIDER_URL=http://127.0.0.1:3012/v1 SKIP_AUTH=1
rm -f public/assets/.manifest.json
bundle exec ruby -r ./spec/e2e/helpers/sdk_endpoints.rb bin/rails server \
  -b 127.0.0.1 -p 3001 -P tmp/pids/browser-audit-v2.pid
```

The service uses the installed WEBrick HTTP server and Rack multipart parser to
implement normal JSON and SSE chat responses plus multipart audio
transcription. Its `/health` response records endpoint/stream/audio-byte/SHA-256 metadata
only, never authorization headers or prompts. Unknown endpoints and non-dummy
credentials are rejected. Entity writes speak ruby_llm 1.16's OpenAI tool
protocol: a create turn returns `choices[].message.tool_calls` for
`create_entity` (JSON `arguments` string, `content` null, `finish_reason`
`tool_calls`); after the SDK posts the `role: "tool"` result the fixture
returns the final `{"intent":"chat","reply":…}` envelope. A notes follow-up
calls `update_entity` the same way, then tells the admin to review and apply.
Streaming uses `chat.completion.chunk` deltas (`index: 0` on tool_calls, then
`finish_reason`, then `data: [DONE]`). Before JSON/SSE serialization,
`provider_server.rb` validates tool arguments with `JSONSchemer` against the
resolved `Operations.for(key).input_schema(ctx).document` for
`create_entity` / `update_entity` / `get_entity`, and flowchart follow-ons
against `FlowchartDefinitions::StructureSchema`, all exported by
`providerSchemas()` (including registry enums, `$defs`, conditions and unions).
It returns 422 for invalid fixture output. No schema definitions are merged or
relaxed. The fixture recognizes instructions in both `system` and RubyLLM's
default OpenAI `developer` role, so the flowchart follow-up gets its own valid
chat document. The Node/Ruby helper tests reject malformed operation arguments
and exercise the developer-role wire format. Tool arguments then go through
real app validation, confirmation and persistence.

Assistant interactions wait for the actual Stimulus controller on the current
mount via `window.Stimulus.getControllerForElementAndIdentifier`. Mention typing
also waits for the controller's real server-candidate request to finish. This
covers asynchronous imports, intercepted requests and Turbo child remounts;
rendered/visible controls alone do not establish readiness.
Mutation/audio checks also await Turbo Rails' `connected` attribute on both panel
stream sources, which is set after Action Cable confirms their subscriptions.

The second microphone test records
real Chromium audio, uses the application's FFmpeg duration probe, uploads
normally, and asserts the local provider response enters the pinned thread and
the clip succeeds/purges. It checks the exact fixture `conversation_id`, decoded
duration and exact multipart byte count/SHA-256 at the provider. `Clip` has no
duration column; the helper observes the real recorder's `dataavailable` event
and re-probes those bytes with `AudioProbe` after the normal request succeeds.
The SHA-256 match proves the SDK provider received those same bytes even though
Chromium's network inspector omits multipart file contents. Recorder-state/elapsed-time
polling supplies a meaningful audio sample before the UI Stop click. The existing
`chromium-media` project grants microphone permission and fake capture hardware;
no application recording/upload method is invoked by the test. Start-only
microphone checks need only readiness rows.

### Fresh conditional settings exports

Generate current authorized Rails responses in a **separate test database**.
`EXPORT_CUSTOMER_SETTINGS_FIXTURES` chooses the app-local output directory;
the exporter's actual enable flag is `SETTINGS_BROWSER_FIXTURES=1` (set by the
wrapper). Only named `*-en.json` / `*-zh-CN.json` fixtures are overwritten;
unrelated `tmp` artifacts are preserved. The browser helper requires provenance
from the exporter, rejecting old unversioned exports.

```bash
E2E_DATABASE_PATH="$PWD/storage/e2e_settings_exports.sqlite3" \
DATABASE_URL="sqlite3:$PWD/storage/e2e_settings_exports.sqlite3" \
RAILS_ENV=test node spec/e2e/helpers/bootstrap.js create

E2E_DATABASE_PATH="$PWD/storage/e2e_settings_exports.sqlite3" \
DATABASE_URL="sqlite3:$PWD/storage/e2e_settings_exports.sqlite3" \
RAILS_ENV=test EXPORT_CUSTOMER_SETTINGS_FIXTURES=tmp/playwright-customer-settings/fixtures \
node spec/e2e/helpers/bootstrap.js export
```

The exporter uses the reserved member role and a settled invoice; it does not
create a fourth role or fake editable grants. A failing exporter is a real
application/fixture-contract failure: do not reuse older files as a substitute.

It now exports 24 authorized responses (12 named states × English/Chinese),
including provisioned Stripe sandbox/production forms, tenant public-page
protection controls, and user access. All preparation uses the separate test DB
and normal model validations/provisioners. If the shell inherits the isolated
browser's `RUBYOPT` preload, unset it before `bootstrap.js export`.

`customer_settings_support.js` serves exports with an explicit UTF-8 charset and
checks provenance, locale and browser decoding. Shell/title assertions scope to
`#main-content` and the header outside the settings content slot, avoiding
embedded website preview headings. Horizontal overflow/control bounds,
disclosures, modal/focus behavior and translated wording remain required.
Inventory traversal preserves GET query inputs (`plan_code`, sorting, etc.).
Reserved grants are tested as read-only; current personalization creation uses
`email-template-token-bulk`. AI/security Save and platform-managed email/SMS
limits follow the actual current forms.

For a settings-only run, pass the three `customer_settings_*.app.spec.js` files
to the configured Playwright command. Use new `--output` and JSON reporter paths;
`SETTINGS_BROWSER_ARTIFACTS=/tmp/opencode/<new-name>-shots` also preserves earlier
screenshots and inventories. This variable does not change the fixture input
directory. The October 12 follow-up passed all 64 settings cases with four
workers; see `docs/audits/2026-10-12-settings-browser-followup.md`.

### Targeted verification

```bash
node --test spec/e2e/helpers/provider_backend.test.js
APP_BASE_URL=http://127.0.0.1:3001 PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright \
npx playwright test --config config/javascript/playwright.config.js --workers=1 \
  spec/e2e/assistant_mention_menu.app.spec.js spec/e2e/assistant_studio_canvas.app.spec.js \
  spec/e2e/assistant_entity_create.app.spec.js spec/e2e/email_template_builder_sync.app.spec.js \
  spec/e2e/customer_settings_conditional.app.spec.js spec/e2e/speech_to_text_mic.app.spec.js
```

Keep the same app database environment on Node/Playwright so runner subprocesses
target the server's database. Use `--output=/tmp/opencode/<run-name>` to preserve
prior failure artifacts. Page/flowchart/entity editor source and route-builder
exclusions remain outside this fixture lane. Deleted SQLite WAL/SHM descriptors
or disk-I/O errors require the DB team's environment repair before mutation runs.

To rerun only the five assistant/audio failures against an already-prepared
environment, source it **inside a child shell**; keep the exact DB and existing
app/static servers. Do not run `create` or load a schema:

```bash
bash -c 'source /tmp/opencode/browser-final.env &&
  npx playwright test --config config/javascript/playwright.config.js --workers=4 --timeout=120000 \
    --output=/tmp/opencode/assistant-audio-followup/browser-rerun \
    --grep="creates an entity|Tab inserts|clicking a row still inserts|assistant microphone" \
    spec/e2e/assistant_entity_create.app.spec.js \
    spec/e2e/assistant_mention_menu.app.spec.js spec/e2e/speech_to_text_mic.app.spec.js'
```

The 2026-10-12 assistant/audio follow-up passed all five selected cases with four
workers, zero retries/skips/flaky cases. The provider helper checks passed 4/4.
The real recorded clip decoded to 1.32 seconds; its 13,932 bytes and SHA-256
matched the local provider, and clip 4 succeeded in pinned conversation 17 with
audio purged. Evidence: `/tmp/opencode/assistant-audio-followup/results-final.json`,
`browser-final.log`, `helpers-final-2.log` and `summary.md` in that directory.

# Element-Level I/O Auto-Detection & Override — Design

**Date:** 2026-04-21
**Scope:** Auto-detect every element's ctx inputs and outputs from its generator class's body, surface them on the property editor's **I/O tab**, auto-apply nearest-producer input overrides and collision-rename output overrides, and honor those overrides in codegen. Also removes `isolateCtx` and the legacy "Inputs Override" / "Outputs Override" user-declared lists.

## Problem

1. The element-level I/O tab is driven by free-text "Inputs Override" / "Outputs Override" lists the user has to maintain by hand. Lists drift from generator reality.
2. When two elements emit the same ctx key (e.g. `ctx[:model]` from both `P1` and `P2`), a downstream reader's `ctx[:model]` is ambiguous at codegen. The per-step feature (shipped 2026-04-20) handles this inside a single process element; element-to-element collisions are not handled.
3. `isolateCtx` introduces a notional ctx snapshot inside a process element that does not exist in the real Trailblazer runtime model. ctx is a single shared bus per activity; the snapshot is misleading and adds resolver complexity.

## Non-Goals

- Changing the shipped per-step `io_overrides` mechanism — it stays as-is and still resolves collisions *inside* a process element.
- Subflow internals. A subflow's own codegen resolves its internal I/O.
- Migrating historical flowchart JSON; AGENTS.md forbids backward-compat hacks.

## Design Summary

Three principles:

- **Generator body is the only source of truth.** Every element's (and step's) inputs and outputs come from literal `ctx[:x]` reads and writes found by the existing `BodyAnalyzer`. No user-declared pin lists anywhere.
- **One override shape.** Same `io_overrides: { inputs: [...], outputs: [...] }` persisted on both step and element, keyed only by ctx key name (no element/step id pointers).
- **Single ctx universe.** No `isolateCtx`; predecessor reachability is pure topology.

```
flowchart load
   │
   ▼
┌──────────────────────┐   POST /code_generators/:action_name/io_params            (step,    shipped)
│ per-element pin cache│   POST /code_generators/element_types/:element_type/...   (element, new)
│   canvas.elementPins │
│   canvas.stepPins    │
└──────────────────────┘
   │
   ▼
┌──────────────────────┐
│ override resolver    │  default inputs = nearest reachable producer key
│ (JS, per element)    │  default outputs = rename when effective key collides
└──────────────────────┘
   │
   ▼
┌──────────────────────┐   structural-change invalidation walks and drops
│ io_overrides on      │   any entry whose override_key is no longer emitted.
│ element + step       │
└──────────────────────┘
   │
   ▼
ActivityGenerator
   → EmissionRewriter (per-step path, shipped)
   → EmissionRewriter (per-element path, new)
   → emitted Ruby
```

## Data Model

### Persisted shape

Each element (and each step, unchanged) carries `io_overrides` inside its properties:

```json
{
  "id": "elem_P2",
  "type": "process",
  "properties": {
    "io_overrides": {
      "inputs":  [ { "pin": "model", "override_key": "model_a3f2" } ],
      "outputs": [ { "pin": "model", "renamed_to":   "model_e7c1" } ]
    }
  }
}
```

- `inputs[].pin` — logical ctx key name on this element (from the body analyzer).
- `inputs[].override_key` — the literal ctx key to read from instead of `pin`. Empty string is a tombstone meaning "user explicitly wants no override; do not re-default."
- `outputs[].pin` — logical ctx key name on this element (the pre-rename key).
- `outputs[].renamed_to` — the literal ctx key to emit instead of `pin`. Absent when no rename needed.

No `producer_element_id`, no `producer_step_id`. The ctx key is globally unique after rename, so it identifies the producer by itself. Stale entries are dropped by a validator walk — see §6.

### Extraction result shape (shared by step and element endpoints)

```json
{
  "inputs":  [ { "pin": "api_url", "ctx_key": "api_url", "source": "config_expr" } ],
  "outputs": [ { "pin": "api_response", "ctx_key": "api_response" } ]
}
```

Identical to the shipped step extractor result. Applied uniformly via `BodyAnalyzer`.

### Rename key format

`"#{pin}_#{sha1(element_id:pin)[0..3]}"`, e.g. `model_e7c1`. Deterministic and stable across edits. If two `(id, pin)` pairs collide on the 4-char prefix, the resolver extends to 6 chars. Same policy as the shipped per-step rename.

## Subsystems

### 1. `IOExtractor` — element-type entry point (server)

`app/services/code_generators/io_extractor.rb` gets a second entry point:

```ruby
CodeGenerators::IOExtractor.call_element(
  element_type: "loop",
  properties: { "loopType" => "for_each", "collection" => "ctx[:items]" }
)
# => { inputs: [...], outputs: [...] }
```

Algorithm:

1. Resolve element-type generator class via `GeneratorRegistry.find_element_type(element_type)`. Unknown type → empty pins.
2. Instantiate with a stub element hash carrying `properties`.
3. Call `generate_body`. `rescue StandardError` → empty pins.
4. Pass body through `BodyAnalyzer` (shared with step extractor).
5. For `process` elements specifically: element-level pins = union of the element's steps' effective pins (post per-step rename), minus inputs satisfied by an earlier step in the same process. Process uses the per-step pin cache; it does not re-analyze a process body from scratch.

For non-process elements (start, end, decision, loop, timer, subflow, error_handler, join, …): generator body is analyzed directly. Whatever literal `ctx[:x]` reads/writes appear become the pins. No synthetic pins, no special cases. Elements with no literal ctx access legitimately show empty I/O.

### 2. `EmissionRewriter` — element-level rewrite pass (server)

`app/services/code_generators/emission_rewriter.rb` (shipped) gets a new public entry for element-level bodies:

```ruby
CodeGenerators::EmissionRewriter.call_element(
  body:,
  element_id:,
  io_overrides:,          # from element.properties
  rename_map:,            # whole-flowchart element-level rename map (§3)
  reachability:,          # Ruby-side predecessor index
  producer_outputs:       # element_id → effective emitted keys
)
# => rewritten_body_string
```

Behavior parallels the step entry:

- **Writes**: each write to `ctx[:pin]` is rewritten to `ctx[:<renamed_to>]` when the element has an output override with a `renamed_to`.
- **Reads**: each read of `ctx[:pin]` is rewritten to `ctx[:<override_key>]` when the element's inputs override says so; otherwise walks `reachability` to find the nearest reachable upstream emitter of a matching key and rewrites to that key; otherwise left as `ctx[:pin]`.
- Reverse-source-order splice to keep offsets stable. Same technique as the step path.

The step-level `EmissionRewriter.call` is untouched; both passes run — step first (inside process bodies), element second (at element boundaries).

### 3. `ConflictResolver` — element-level pass (server)

The shipped step-level `ConflictResolver` stays. A new element-level pass runs alongside:

1. For every element, compute effective emitted keys (post per-step rename if any).
2. Invert to `emitted_key → [element_ids]`.
3. Any key with ≥ 2 emitters triggers rename of **all** emitters of that key.
4. Produce `rename_map = { element_id => { pin => renamed_key } }`.

Reachability does not constrain element-level collision detection: *any* two elements emitting the same key trigger rename across the whole flowchart. Matches user intent ("all other leaves").

### 4. `ActivityGenerator` changes (server)

- Remove `apply_process_scope_options`'s `isolateCtx` branch. Keep `onStepFailure` handling.
- Before emitting each element's body, run `EmissionRewriter.call_element` with the element's `io_overrides` and the flowchart's element-level rename map.
- Remove the `isolate = properties["isolateCtx"] == "true"` read and its snapshot-wrapping heredoc entirely. `ctx` is a single shared bus; no snapshot/copy-back.

### 5. HTTP Endpoint

Route: `POST /code_generators/element_types/:element_type/io_params`.
Controller: `CodeGenerators::ElementTypeIoParamsController#show`.
Request:

```json
{ "properties": { "loopType": "for_each", "collection": "ctx[:items]" } }
```

Response (always 200):

```json
{
  "inputs":  [ { "pin": "items", "ctx_key": "items", "source": "config_expr" } ],
  "outputs": []
}
```

Unknown element_type or generator failure → `{"inputs":[], "outputs":[]}`, 200.

### 6. Client — Canvas cache & invalidation

`canvas.elementPins[element_id]` is a new JS-side cache parallel to the shipped `canvas.stepPins`. Populated:

- On flowchart load: fetch pins for every element in parallel, cache.
- On **structural change**: the canvas emits a `flowchartStructureChanged` event after any of:
  - connection added / removed
  - element added / removed
  - element's config field edited (debounced 300ms)
  - a step added / removed / config-edited inside a process element (propagates to that element's own pins)

Two listeners wire up:

1. **Pin cache invalidator** — refetches pins for the touched element (and, if it's a process, recomputes its rolled-up pins from `stepPins`).
2. **Override validator** — walks *every* element's `io_overrides`:
   - For each `inputs[].override_key`: if no upstream reachable element currently emits that key, drop the entry. On next render the resolver re-defaults to nearest. Silent — no toast, no marker.
   - For each `outputs[].renamed_to`: recompute from the element-level resolver; if the element no longer collides, clear the rename; if it now collides with a different element, update the rename.

### 7. Client — `ElementIoManager` (JS)

`app/javascript/controllers/property_editor/element_io_manager.js` is the I/O tab renderer. Parallel to `step_io_manager.js`.

- `openForElement(element, paneElement)` — ensures pins are fetched, renders the I/O pane.
- `updateProducer(elementId, pinName, overrideKey)` — writes/tombstones the `inputs[]` override, persists to `element.properties.io_overrides`, dispatches change event.
- Sub-modules:
  - `element_io/reachability.js` — predecessor set walk from an element id. No universes, no `isolateCtx`.
  - `element_io/override_computer.js` — computes default input overrides (nearest reachable producer emitting a matching effective key) and default output overrides (element-level rename when effective keys collide across elements).

### 8. Client — I/O tab layout

Replaces the current I/O tab contents for every element:

```
Inputs
──────────────────────────────────────────────────
 model          [ elem_P1 "Fetch" • model_a3f2 ▾ ]  (nearest)
 api_url        [ — no producer —               ▾ ]
 headers        [ elem_S1 "Start" • headers     ▾ ]

Outputs
──────────────────────────────────────────────────
 user                                    (from step_b)
 token          ⚠ renamed → token_b7e1   (collides with elem_P5)
```

- One row per extracted input pin; producer dropdown; default selection = nearest reachable producer; "— no producer —" when none matches; selecting "no producer" tombstones the override so defaults don't re-apply on next render.
- One row per extracted output pin; read-only; rename badge when element-level collision triggered.
- Empty state: "This element reads no ctx values" / "This element writes no ctx values."
- No "Add Input" / "Add Output" buttons. Not user-editable.

### 9. Deletions

- Remove `isolateCtx` field from `ELEMENT_SCHEMAS.process` (`app/javascript/flowchart/constants/schemas.js`).
- Remove `isolateCtx` branch and associated snapshot heredoc from `apply_process_scope_options` in `app/services/activity_generator.rb`.
- Remove universe / `sameUniverse` logic from `app/javascript/controllers/property_editor/step_io/reachability.js` and `step_io/override_computer.js`. Predecessor set is pure topology.
- Remove `COMMON_PROPERTIES.inputs`, `COMMON_PROPERTIES.outputs`, and every element's reference to them in `schemas.js`. Delete `HIDDEN_DEFAULT_INPUTS` / `HIDDEN_DEFAULT_OUTPUTS`.
- Remove `IOManager.buildInputsFieldHTML`, `buildOutputsFieldHTML`, `collectInputs`, `collectOutputs`, `buildVarMappings…` (whatever isn't used elsewhere), inherited-inputs logic from `FormBuilder._applyInheritedInputsFromParent`, and the related event listeners in `property_editor_controller.js` (`addInput`, `removeInput`, `onInputChange`, `addOutput`, `removeOutput`, `inputAdded`/`inputRemoved`/`outputAdded`/`outputRemoved` sync hooks).
- Remove I/O-tab badge counters that count `data-input-item` / `data-output-item` in `_updateTabBadges` (replace with counts of extracted pins).
- Stale `isolateCtx: "true"` values persisted in flowchart JSON are ignored at load; no migration.

## Testing

### Ruby (rspec)

- `spec/services/code_generators/io_extractor_spec.rb` — extend with `call_element` cases: start, end, decision, loop, timer, join, error_handler, subflow; empty-body elements; process (roll-up from steps).
- `spec/services/code_generators/emission_rewriter_spec.rb` — new `call_element` cases: element-only rename, element rewrite with upstream per-step rename, element with both element-level and step-level overrides interacting.
- `spec/services/code_generators/conflict_resolver_spec.rb` — new element-level cases: two elements emitting same key → both renamed; single emitter → no rename; step-level rename already disambiguates → no element-level rename.
- `spec/services/activity_generator_spec.rb` — integration: two elements emit `model`, downstream consumes, emitted module uses renamed keys; `isolateCtx` removal — no snapshot/copy-back code appears in output for any flowchart.
- `spec/controllers/code_generators/element_type_io_params_controller_spec.rb` — new endpoint mirrors step endpoint semantics.

### JS

- `element_io/reachability_spec.js` — predecessor walk, no-universe cases.
- `element_io/override_computer_spec.js` — nearest producer default, tombstone behavior, element-level rename default, interaction with shipped per-step rename.
- `element_io_manager_spec.js` — render default overrides on open, user selection persists, tombstone round-trips, structural-change invalidation drops stale override and silently re-defaults.

### System (Capybara)

- `spec/system/property_editor/element_io_tab_spec.rb`:
  - Open I/O tab on a process element, see rolled-up pins.
  - Two-producer element scenario, see rename badge.
  - Pick non-default producer from dropdown, save, reopen → selection persists.
  - Delete upstream producer's emitting element, reopen → override silently reset to nearest.
  - Remove `isolateCtx` smoke: no such control is visible on process element's Advanced tab.

## Open Risks

- **Element-type generator bodies with non-literal ctx access.** `BodyAnalyzer` only recognizes `ctx[:symbol]`. Dynamic access (`ctx[some_var]`) is skipped, same as for steps. Follow-up lint pass to surface these; not a v1 blocker.
- **Performance on large flowcharts (> 100 elements).** Initial pin fetch is `O(N)` element-type extraction calls. Parallel fetch + server-side generator invocation should stay under a couple hundred ms; if profiling shows otherwise, add memoization keyed by `(element_type, properties-hash)`.
- **Resolver drift between JS and Ruby.** Two implementations (client for live UI, server for codegen) risk diverging. Mitigation: fixture-based contract tests — a set of flowchart JSON fixtures with expected rename maps and override outcomes, executed both in RSpec and in a Node-backed JS harness.

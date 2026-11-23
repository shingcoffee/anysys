# Step I/O Tab & Ctx Conflict Resolution — Design

**Date:** 2026-04-20
**Scope:** Step-action generators on the flowchart edit page. Element-type generators (start/end/process/decision/loop/…) are out of scope for this spec.

## Problem

Two problems, solved together because they share a data model:

1. **Empty I/O tab.** The property editor's "I/O" tab, when a step (inside a process element) is being edited, should show the input parameters and output parameters the step actually uses. Today that tab reflects element-level ctx-key overrides and is unpopulated for per-step editing.
2. **Ctx key collisions at codegen.** Two steps can each write `ctx[:model] = …`. When both are reachable to a downstream reader, the reader's `ctx[:model]` is ambiguous — it might be one producer or the other depending on control flow. Renaming one producer is not enough: reads aren't bound to any specific writer, so renaming silently disconnects them.

## Non-Goals

- Extracting I/O for element-type generators (process, decision, loop, etc.). Those elements remain populated via their existing element-level Inputs/Outputs overrides.
- Changing Trailblazer semantics. `ctx` remains a flat shared bus; `Input()`/`Output()` macros are not used (they would limit each step's view of ctx).
- Rewriting generator bodies. Generators keep emitting plain `ctx[:x]` source; rewrites happen after body generation, in a dedicated pass.
- Subflow internals. A subflow element's own codegen handles its internal conflicts independently.

## Design Summary

Three server-side subsystems, one UI surface, and a small addition to the flowchart save format.

```
                ┌──────────────────────────────────────────────┐
                │  Flowchart save format                        │
                │    per-step: config (as today)                │
                │              io_bindings[] (NEW)              │
                └──────────────────────────────────────────────┘
                                │
      ┌─────────────────────────┼──────────────────────────┐
      ▼                         ▼                          ▼
┌───────────────┐        ┌────────────────┐        ┌────────────────┐
│ IOExtractor   │        │ ConflictResolver│       │ EmissionRewriter│
│ (per step)    │        │ (whole chart)  │        │ (per step body) │
│ → pins list   │        │ → rename map   │        │ → rewritten body│
└───────────────┘        └────────────────┘        └────────────────┘
      │                         │                          │
      ▼                         ▼                          ▼
   HTTP endpoint         ActivityGenerator            Final emitted code
      │                         integrates both
      ▼
 Step modal I/O tab
 (Stimulus, JS)
```

The shared primitive is **`BodyAnalyzer`** — a Ripper-based walker that takes a body of Ruby source and returns `{reads: [...], writes: [...]}` of literal `ctx[:symbol]` occurrences with source positions. Used by `IOExtractor` (for the endpoint) and `EmissionRewriter` (for the codegen pass).

## Data Model

### Flowchart save format additions

Each step gains one field, `io_bindings`:

```json
{
  "id": "step_7",
  "action": "api_call",
  "label": "Fetch profile",
  "config": { "url": "ctx[:api_url]", "resultVar": "api_response" },
  "io_bindings": [
    {
      "pin": "api_url",
      "producer_step_id": "step_3",
      "producer_pin": "user_url"
    },
    {
      "pin": "headers",
      "producer_step_id": null
    }
  ]
}
```

- `pin` — logical input name on this step (from `IOExtractor`).
- `producer_step_id` — upstream step whose output this input reads. `null` means "use nearest reachable producer at codegen time."
- `producer_pin` — logical output name on the producer (disambiguates a producer that writes multiple ctx keys).

Outputs are **not** on the save side — they are derived from the generator per extraction, not user-declared.

### IOExtractor result shape

```json
{
  "inputs":  [
    { "pin": "api_url", "ctx_key": "api_url", "source": "config_expr" },
    { "pin": "headers", "ctx_key": "headers", "source": "config_expr" }
  ],
  "outputs": [
    { "pin": "api_response", "ctx_key": "api_response" }
  ]
}
```

- `pin` — canonical logical name; equal to the ctx key in the pre-rename generated body.
- `ctx_key` — same as `pin` today; separate field so later aliasing can distinguish.
- `source` — `"config_expr"` when the pin originated from a `ctx[:x]` reference in a user-authored config value; `"generator_literal"` when hardcoded in the generator body.

### ConflictResolver output

In-memory rename map produced per codegen run:

```ruby
{
  "step_3" => { "model" => "model_a3f2" },
  "step_7" => {},
  "step_9" => { "model" => "model_b7e1" }
}
```

Key: step id. Value: `{logical_pin → renamed_ctx_key}` for outputs that need the unique suffix. A missing entry means "emit naturally."

### Rename key format

`"#{pin}_#{short_uuid}"` where `short_uuid = Digest::SHA1.hexdigest("#{step_id}:#{pin}")[0..3]`.

- Deterministic across regenerations (same flowchart ⇒ same keys).
- Stable across unrelated edits (suffix depends only on the step's id and pin).
- Short — 4 base16 chars; collision probability within a single flowchart is negligible. A resolver-level collision check falls back to 6 chars if two `(step_id, pin)` pairs ever produce the same 4-char prefix.

## Subsystems

### 1. IOExtractor (`app/services/code_generators/io_extractor.rb`)

Public API:

```ruby
CodeGenerators::IOExtractor.call(
  action: "api_call",
  config: { "url" => "ctx[:api_url]", "resultVar" => "api_response" }
)
# => { inputs: [...], outputs: [...] }
```

Algorithm:

1. Resolve generator class via `GeneratorRegistry.find_step_action(action)`. Unknown action → return empty pins.
2. Instantiate generator with a stub element hash and a context carrying `config`.
3. Call `generate_body`. Wrap in `rescue StandardError` — return empty pins on failure.
4. Wrap the body in `def __stub__(ctx); <body>; end` and pass to `BodyAnalyzer` (Ripper parse, AST walk).
5. Classify each read/write by literal symbol. Dedupe preserving first-seen order.
6. Tag `source` by matching pin name against `ctx[:X]` references found in config string values.

Factored helper: `app/services/code_generators/io_extractor/body_analyzer.rb` owns the Ripper parse and the `ctx[:X]` node walk. Pure input→output; reusable by `EmissionRewriter`.

Edge cases:

- **Dynamic ctx access** (`ctx[some_var]`, `ctx[config["key"].to_sym]`) — skipped. Only literal `ctx[:symbol]` nodes count. Documented limitation.
- **Op-assigns** (`ctx[:x] ||= …`) — treated as both read and write.
- **Nested chains** (`ctx[:x][:y][:z]`) — reads `ctx[:x]` only.
- **Interpolated strings containing `ctx[:x]`** — the nested node is visited; counts as a read.
- **Comments** — non-program text, ignored.

### 2. ConflictResolver (`app/services/code_generators/conflict_resolver.rb`)

Public API:

```ruby
CodeGenerators::ConflictResolver.call(flowchart)
# => rename_map hash (see Data Model)
```

Algorithm:

1. For every step action in the flowchart, call `IOExtractor` → build `step_id → output_pins`.
2. Invert to `pin_name → [step_ids]`. Discard pins with a single producer.
3. Build predecessor reachability via `FlowchartTopologyAnalyzer` (reuse existing DFS / node_guards infrastructure). Respect `isolateCtx` process boundaries as separate reachability universes.
4. For each multi-producer pin:
   - Find all readers (steps whose extracted inputs include the pin).
   - For each reader, compute the set of producers with at least one path to it.
   - If *any* reader has ≥2 producers reachable, rename **all** producers of that pin across the flowchart.
5. Assign each to-be-renamed producer the `pin + "_" + sha1_prefix` key.
6. Return the rename map.

Policy rationale: renaming every producer structurally prevents the "silent wrong producer" class of bug even if binding metadata is lost or missing. Safer than the per-reader alternative; cost is a few extra uuid-suffixed keys in generated code.

Edge cases:

- **Single producer + multiple readers** — no rename.
- **Multiple producers, no reader** — no rename (dead writes are harmless).
- **Producers on mutually exclusive decision branches** — still renamed. Static analysis treats both as reachable; runtime picks one branch but the reader must explicitly bind.
- **`isolateCtx`** — a process with this flag forms its own reachability universe. Producers inside don't count as reachable outside.
- **Subflows** — treated as opaque single steps. Their declared outputs are the subflow element's outputs; internal conflicts resolve inside that subflow's own codegen.

### 3. EmissionRewriter (`app/services/code_generators/emission_rewriter.rb`)

Public API:

```ruby
CodeGenerators::EmissionRewriter.call(
  body:,
  step_id:,
  io_bindings:,
  rename_map:,
  reachability:,
  producer_outputs:
)
# => rewritten_body_string
```

Algorithm:

1. Pass `body` through `BodyAnalyzer` to get `ctx[:X]` read and write nodes with source positions.
2. **Writes**: for each write, look up `rename_map[step_id][pin]`. If present, splice `ctx[:<renamed>]` over the source range.
3. **Reads**: for each read:
   - Find binding: `io_bindings.find { |b| b["pin"] == pin }`.
   - If binding has `producer_step_id` → look up `rename_map[producer_step_id][producer_pin]`. Splice `ctx[:<renamed or producer_pin>]`.
   - If binding is null or absent → walk `reachability` to find the nearest upstream step whose `producer_outputs` include `pin`. Apply the same rename lookup.
   - If no reachable producer → leave `ctx[:pin]` untouched (matches today's behavior: runtime `nil` if no one set it).
4. **Splice in reverse source order** so earlier offsets stay stable.
5. Return the rewritten body. Original is untouched (pure function).

Why source splice rather than AST-to-source: generator bodies are hand-crafted Ruby strings; AST regeneration would churn formatting (indent, heredocs, quote style). Position-based splice preserves everything except the rewritten `ctx[:...]` token ranges.

### ActivityGenerator integration

Current (simplified):

```
for each step in topological order:
  body = generator.generate_body
  emit "def #{step_name}(ctx, **); #{body}; end"
```

Updated:

```
rename_map       = ConflictResolver.call(flowchart)
producer_outputs = {step_id => extracted_output_pins}  # reused from resolver
reachability     = FlowchartTopologyAnalyzer.predecessor_index(flowchart)

for each step in topological order:
  body           = generator.generate_body
  rewritten_body = EmissionRewriter.call(
    body:, step_id: step["id"],
    io_bindings: step["io_bindings"] || [],
    rename_map:, reachability:, producer_outputs:
  )
  emit "def #{step_name}(ctx, **); #{rewritten_body}; end"
```

Extraction results are computed once and threaded through — no repeated Ripper parses per step.

## HTTP Endpoint

Route: `POST /code_generators/:action_name/io_params` — note the path param is `:action_name`, not `:action`, to avoid collision with Rails' reserved `action` routing param.
Controller: `CodeGenerators::IoParamsController#show`
Request:

```json
{ "config": { "url": "ctx[:api_url]", "resultVar": "api_response" } }
```

Response (always 200):

```json
{
  "inputs":  [{ "pin": "api_url", "ctx_key": "api_url", "source": "config_expr" }],
  "outputs": [{ "pin": "api_response", "ctx_key": "api_response" }]
}
```

(The `ctx_key` field matches the Data Model's IOExtractor result shape; identical to `pin` in v1.)

Unknown action or extraction failure returns `{"inputs": [], "outputs": []}` with 200 to keep mid-edit UX smooth. Session auth + CSRF as on other edit endpoints.

## UI: Step Modal I/O Tab

### Scope

Populated only in the **step modal** (step inside a process element). The element-level I/O tab on the main property editor is untouched.

### New JS modules

- `app/javascript/controllers/property_editor/step_io_manager.js` — orchestrates the step modal's I/O tab.
- `app/javascript/controllers/property_editor/step_io_reachability.js` — pure graph walk producing predecessor sets; testable without DOM.
- `app/javascript/controllers/property_editor/step_io_conflict_detector.js` — JS port of `ConflictResolver`'s algorithm. Recomputes the rename decision and suffix locally so the UI shows the same keys the server will emit.

### Data plumbing

- On flowchart load, fetch extracted pins for every step once and cache in `canvas.stepPins[step_id]`.
- On step config field change (debounced 300ms), refetch `/code_generators/:action_name/io_params` for the affected step and update the cache.
- `step_io_conflict_detector` recomputes the rename map from `canvas.stepPins` + connections whenever pins change.

### Layout

```
Inputs
────────────────────────────────────────────────
 api_url        [ — nearest upstream —   ▾]  (config expr)
                 step_3 "build URL" • pin: user_url
                 step_1 "start"     • pin: api_url
 headers        [ — no producers —       ▾]  (config expr)

Outputs
────────────────────────────────────────────────
 api_response                ⚠ renamed → api_response_a3f2
                              Conflict with step_9 "refresh token"
```

- **Input row** — pin name, producer dropdown, source label. Dropdown lists every reachable upstream step whose output matches the pin name. First option is a sentinel `— nearest upstream —` (stored as `null` in `io_bindings`).
- **Output row** — pin name plus a rename badge when the conflict detector marks it. Clicking the badge reveals the conflicting steps with jump links.
- **Empty states** — "This step reads no ctx values" / "This step writes no ctx values" when the extractor returns empty.

### Validation

When a pin has ≥2 reachable producers and the user hasn't picked one (binding is `null`), the input row gets a red outline and tooltip: "Multiple producers exist. Pick one." The canvas save is blocked until resolved, with a toast listing unresolved bindings. Codegen does not run until all bindings are resolved.

### Backward compatibility for existing flowcharts

Existing flowcharts have no `io_bindings` field. On load:

- Missing field is treated as `[]`. Reads fall back to nearest-producer.
- No conflicts → code generates identically to today.
- Conflicts → the user must open affected steps and pick producers before codegen. A small dot on the canvas step marks steps with unresolved bindings.

No bulk migration script; lazy resolution is sufficient because bindings only matter when conflicts exist.

## Testing

### Rspec (server)

- `spec/services/code_generators/io_extractor_spec.rb`
  - Representative generators per category (api_call, pluck_fields, cache set, etc.).
  - Literal reads, writes, op-assigns, dynamic access (expected skip), nested chains.
  - Config-expr ctx references tagged `source: "config_expr"`.
  - Generator-raises → empty pins, no crash.
- `spec/services/code_generators/io_extractor/body_analyzer_spec.rb` — pure-Ruby input, no generator dependency.
- `spec/services/code_generators/conflict_resolver_spec.rb`
  - Single producer → empty rename map.
  - Two producers, no reader → empty rename map.
  - Two sequential producers + reader → both renamed.
  - Two parallel (fork) producers + reader past join → both renamed.
  - Two decision-branch producers + reader past merge → both renamed.
  - `isolateCtx` boundary: inside and outside each keep their own rename universe.
  - Determinism: same flowchart twice ⇒ identical rename map.
  - 4-char prefix collision fallback to 6 chars.
- `spec/services/code_generators/emission_rewriter_spec.rb`
  - Output-only rename.
  - Input rewrite following a renamed producer.
  - Op-assign rename.
  - Multiple occurrences in one body.
  - Reverse-order splice correctness.
  - Dynamic access preserved.
  - Comment mentioning `ctx[:x]` preserved.
  - Nearest-producer fallback when binding is null.
- `spec/services/code_generators/activity_generator_spec.rb` — integration: full flowchart with two producers of `model`, one reader ⇒ final emitted module uses renamed keys and correct reader reference.
- `spec/controllers/code_generators/io_params_controller_spec.rb` — endpoint returns expected JSON; unknown action → empty pins; malformed config → empty pins + 200.

### System (Capybara)

- `spec/system/property_editor/step_io_tab_spec.rb`
  - Open step modal → I/O tab populates.
  - Change config field → pins refresh after debounce.
  - Two-producer scenario → rename badge appears.
  - Pick producer from dropdown → binding persists on save → reopen step shows selection.

### JS

- If a JS test harness is present: `spec/javascript/controllers/property_editor/step_io_manager_spec.js`, `step_io_reachability_spec.js`, `step_io_conflict_detector_spec.js`. Otherwise system specs cover the surface.

## Open Risks

- **Dynamic ctx access in generator bodies.** The literal-only extractor will miss these. Mitigation: lint pass over generators in a follow-up to surface dynamic access and either convert to literals or mark as an opaque write; not a v1 blocker.
- **Performance of full-chart extraction on flowchart load.** Extraction is <5ms per step; large flowcharts (100+ steps) may want memoization keyed by `(action, config hash)`. Defer; profile first.
- **JS/Ruby resolver drift.** Two implementations of the rename policy in different languages can diverge. Mitigation: a shared fixture-based contract test — a set of flowchart fixtures with expected rename maps, executed both server-side (RSpec) and client-side (JS test harness or a small Node harness).

# Process Element I/O Tab — Design

**Date:** 2026-04-21
**Topic:** Populate the property editor's I/O tab for process elements by extracting inputs/outputs from the step-action code generators.

## Problem

On `/flowcharts/:id/edit`, clicking a process element opens the property editor. Its I/O tab is empty — shows "This element reads no ctx values" and "This element writes no ctx values" — even when the process contains steps that read and write ctx.

Other element types (start, end, decision, loop, join, timer) each have a `<type>_generator.rb`. Their I/O tab is populated via `CodeGenerators::IoExtractor.call_element(element_type:, properties:)`, which finds the generator, runs `generate_body`, and passes the body through `BodyAnalyzer` to surface `ctx[:pin]` reads/writes.

Process has no `process_generator.rb`. `GeneratorRegistry` intentionally skips the `process/` directory (its subfolders are scanned as step-action generators instead). So `find_element_type("process")` returns nil and `ElementExtractor#call` returns `EMPTY`.

## Solution

Extend `CodeGenerators::IoExtractor::ElementExtractor#call` with a process-specific code path. Instead of looking up a non-existent process generator, delegate to each step's existing step-action generator via the already-tested `IoExtractor.call(action:, config:)`, then concatenate + dedupe.

### Flow

`ElementExtractor#call`:

1. If `@element_type == "process"` → call `extract_process_io`.
2. Otherwise → existing behavior (find element-type generator, run, analyze).

`extract_process_io`:

1. Read `steps = @properties["steps"] || @properties[:steps] || []`. Non-array → treat as empty.
2. For each step hash:
   - `action = step["action"] || step[:action]`
   - `config = step["config"] || step[:config] || {}`
   - Skip steps with blank `action`.
   - Call `IoExtractor.call(action: action, config: config)` — returns `{inputs: [...], outputs: [...]}`.
   - Accumulate its `inputs` and `outputs`.
3. Dedupe accumulated inputs by `pin` preserving first-seen order. Same for outputs.
4. Return `{inputs:, outputs:}`.

If step action is unknown, `IoExtractor.call` already returns `EMPTY`, so that step contributes nothing. If a step-action generator raises, the existing `rescue StandardError` inside `Extractor#build_body` swallows it.

### Input source tag

When input hashes are merged, the `source` field ("config_expr" vs "generator_literal") is preserved as reported by each step's extractor. No new source tag is introduced.

## Why not create `ProcessGenerator`

1. The registry explicitly excludes `process/` from element-type scanning. The audit script (`scripts/audit_generator_ui.rb`) does the same. A `ProcessGenerator` would be a phantom generator at odds with that established convention.
2. Process does not emit its own Ruby — `ActivityGenerator` handles process orchestration separately. A `ProcessGenerator#generate_body` that just concatenates step bodies would be pure plumbing, only re-parsed by `BodyAnalyzer` to recover information the per-step extractor already produces.
3. Delegating to the per-step path reuses the already-tested extraction pipeline, including `config_expr` detection for ctx references wired into string config values.

## Scope — raw union (option A)

The unioned I/O shows **every** pin read or written by **any** step in the process. Internal handoffs appear on both sides (if step 1 writes `user` and step 2 reads `user`, `user` shows up as both a process input and a process output).

Consequence for the I/O tab: the producer dropdown for an input whose actual producer is an earlier step in the same process will show only "— no producer —", because the reachability-based predecessor list scans the canvas graph (external peers), not step-internal emitters. This is accepted for option A.

## Edge cases

| Case | Behavior |
|------|----------|
| `properties.steps` missing | Returns `EMPTY` |
| `properties.steps` is `[]` | Returns `EMPTY` |
| Step with missing/blank `action` | Contributes nothing |
| Step with unknown `action` | Contributes nothing (existing `Extractor` returns EMPTY) |
| Step generator raises | Contributes nothing (existing rescue) |
| Pin collision across steps | Deduped by `pin` name, first-seen order preserved |
| Same pin appearing as both read and write across steps | Appears in both inputs and outputs (raw union) |
| `properties` hash uses symbol vs string keys | Accept both (`"steps"` and `:steps`) |

## Files changed

- `app/services/code_generators/io_extractor.rb` — add `extract_process_io` inside `ElementExtractor`, plus dispatch in `#call`.

No frontend changes. No controller changes. No new files.

## Testing

Extend `spec/services/code_generators/io_extractor_spec.rb` (or co-located file for element extraction) with `call_element(element_type: "process", ...)` coverage:

1. Process with two steps, each with distinct ctx reads and writes → union of both.
2. Process where step 1 writes `user` and step 2 reads `user` → `user` appears in both inputs and outputs (option-A raw union).
3. Process with duplicate output pin across two steps → deduped, first-seen order preserved.
4. Process with no `steps` key → `{inputs: [], outputs: []}`.
5. Process with `steps: []` → `{inputs: [], outputs: []}`.
6. Process with one unknown-action step → that step contributes nothing.
7. Process with one step whose generator raises → that step contributes nothing, other steps unaffected.
8. Process properties with symbol keys (`:steps`, `:action`, `:config`) → same result as string keys.

Integration-level: a request spec hitting `POST /code_generators/element_types/process/io_params` with a process payload, asserting the JSON response contains the expected inputs and outputs.

## Out of scope

- No changes to the frontend `ElementIoManager` or producer dropdown logic.
- No filtering of internal handoffs (that would be option B).
- No new `process_generator.rb`, no registry changes, no audit-script changes.
- No changes to how step-level I/O is rendered inside the Steps tab — that pipeline already works.

# Enrich Flowchart "Validate" — Design

**Date:** 2026-06-13
**Status:** Approved, ready for implementation

## Problem

The editor's **Validate** button should "find all the issues of any given flowchart" —
covering every process step action and every scenario of the other element types.
Today it runs three layers:

1. Client `ValidationService` — structural rules (orphans, reachability, branch counts
   for decision/join, per-element completeness for a handful of types).
2. Client `InputOutputValidationService` — missing-input detection.
3. Server `FlowchartServerValidator` — subflow access/cycle checks + an `ActivityGenerator`
   dry-run that scans the generated source for `# TODO:` markers.

**The gap:** every code generator (all 117 — 14 element types + ~100 step actions)
already implements a rich `validate_config(config)` that checks required fields, enum
allowlists, numeric bounds, and conditional requirements (e.g. `wait_n` requires
`requiredCount`, `for_each` requires `collection`, `find_model` rejects an unknown
`findStrategy`). **This validation is completely dormant** — it is only ever called by
the dev `CodeGenerators::TestRunner`, never during Validate. So a process step with a
bad `findStrategy`, or a switch with no `cases`, generates broken/placeholder code and
the user is never told why.

The codegen dry-run only surfaces problems that generators emit as `# TODO:` markers,
which covers *unknown* actions/types and *raised* exceptions — not the far larger class
of *misconfigured-but-non-raising* elements that `validate_config` is built to catch.

## Decision

Activate the dormant per-generator `validate_config` during server-side validation, for
**every element and every process step**. This is the single highest-leverage change:
it lights up the existing, comprehensive, per-action/per-scenario config rules across the
whole catalog in one move, and it is the natural home for these checks because the rules
live in Ruby (the client cannot evaluate them).

Add two small **client** topology rules (`fork_branches`, `switch_branches`) for the only
gap activation cannot close — branch-count checks need the connection graph, which
`validate_config` never sees.

## Architecture

### 1. Server — `FlowchartServerValidator#config_validation_problems`

New phase, run inside the existing 10s `Timeout` block alongside `subflow_problems` and
`codegen_problems`:

```
elements.each:
  if type == "process":
    for each step in properties.steps (with index):
      gen = registry.find_step_action(action) || registry.find_step_action(action.downcase)
      next if gen.nil?            # unknown action → codegen TODO already covers it
      errors = gen.new(step, {}).validate_config((step["config"] || {}).with_indifferent_access)
      → one "step_config_invalid" problem per error (element_id = element id)
  else:
    gen = registry.find_element_type(type)
    next if gen.nil?             # unknown type → codegen TODO already covers it
    errors = gen.new(el, {}).validate_config((el["properties"] || {}).with_indifferent_access)
    → one "element_config_invalid" problem per error (element_id = element id)
```

- **Resolution mirrors `ActivityGenerator`** exactly (element generator reads
  `properties`; step generator reads `config`; downcase fallback for action names).
- **Skip when the generator is nil** — the existing codegen dry-run already emits a
  `# TODO: unknown step action / element type` for those, so we avoid double-reporting.
- **Per-call `rescue StandardError`** — a single buggy `validate_config` (or constructor)
  must not abort the whole validation; on rescue, skip that element/step silently
  (the codegen dry-run still independently reports a raised generator).
- **`with_indifferent_access`** on the config — generator `validate_config`s use string
  keys and `cfg.key?`; element JSON has string keys, so this is safe and future-proof.
- Bounded by the existing `MAX_ELEMENTS` (1000) pre-flight cap and the 10s timeout.

#### Problem schema (unchanged shape)

```ruby
{ type: "step_config_invalid",    severity: "error", element_id:, connection_id: nil,
  message: "Step \"<label>\" (<action>): <generator error>", fix_hint: "Fix this step's configuration" }

{ type: "element_config_invalid", severity: "error", element_id:, connection_id: nil,
  message: "<label> (<type>): <generator error>",          fix_hint: "Fix this element's configuration" }
```

The label/action prefix gives the user context in the problem panel (which groups by
element); the generator's own message carries the specific defect.

#### Known, accepted minor redundancy

For the ~6 element types the client already partially validates (decision condition,
loop collection, join requiredCount, subflow target, end returnValue, timer duration),
the server may now emit an additional, differently-worded message for the *same* defect.
This is accepted: the goal is maximal detection, the panel groups by element, and the
generator also surfaces many checks the client does **not** (enum validity, secondary
numeric bounds, conditional-field misuse). No brittle server-side exclusion list.

### 2. Client — two topology rules + navigation

`app/javascript/flowchart/validation_service.js`, in `_validateCompleteness`, mirroring
the existing `decision_branches` / `join_branches` rules:

- `fork_branches` (error): a `fork` element with `< 2` outgoing connections —
  "Fork \"<label>\" needs at least 2 outgoing connections (parallel branches)".
- `switch_branches` (error): a `switch` element with `< 2` outgoing connections —
  "Switch \"<label>\" needs at least 2 outgoing connections (cases)".

`app/javascript/flowchart/validation_navigation.js` — add to `RULE_NAV`:

- `fork_branches: null` and `switch_branches: null` (canvas-level, like the other
  `*_branches` rules — no field to focus).
- `step_config_invalid: { tab: "steps", fixHint: "Fix this step's configuration" }`.
- `element_config_invalid: { tab: "advanced", fixHint: "Fix this element's configuration" }`.

No change needed in the merge/render path — `validations_controller` already camelizes
arbitrary problem hashes, and the canvas controller already renders any problem with an
`elementId` + click-to-fix via `navFor`.

## Testing

Server (`spec/services/flowchart_server_validator_spec.rb`, extended):
- A process element whose step has invalid config (e.g. `find_model` with an unknown
  `findStrategy`) → one `step_config_invalid` problem with the right `element_id` and a
  message containing the generator error.
- A non-process element with invalid config (e.g. `switch` missing `sourceVariable`, or
  `join` `wait_n` with no `requiredCount`) → `element_config_invalid`.
- A fully valid flowchart → no `*_config_invalid` problems.
- An unknown step action / element type → NO `*_config_invalid` (only the existing
  codegen TODO), proving we don't double-report.
- A generator whose `validate_config` raises → swallowed; validation still returns and
  reports other problems (no 500).
- Multi-tenant: validator already runs on an in-memory copy scoped to `@flowchart`'s
  tenant; the new phase adds no DB access, so isolation is unchanged.

Request spec (`spec/requests/maintenance/flowchart_validations_spec.rb`, extended):
- POST with a misconfigured step returns the camelCased `stepConfigInvalid`-type problem
  in the JSON `problems` array.

Client rules: no JS test framework exists; `fork_branches` / `switch_branches` mirror
proven existing rules and are verified by manual smoke on the editor.

## Out of scope

- Enriching individual generators' `validate_config` (they are already rich; we only
  activate them).
- Client/server cross-layer deduplication.
- New topology rules for parallel_for_each/saga/transaction/signal_wait (their config is
  covered by the server activation; their flow semantics are out of scope here).

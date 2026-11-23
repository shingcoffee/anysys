# Element I/O Tab — Read-Only Rule & Self-As-Producer — Design

**Date:** 2026-04-21
**Topic:** On the flowchart edit page, show element I/O tab inputs as read-only unless the pin has multiple real producer candidates. Treat the element's own outputs as a producer candidate for its own inputs.

## Problem

On `/:customer_id/flowcharts/:id/edit`, opening the property editor's **I/O** tab for any element currently renders a `<select>` producer dropdown for every input pin — even when only one producer (or zero) matches. This creates two issues:

1. **Visual noise.** A dropdown with only `— no producer —` or a single option looks interactive but offers no real choice.
2. **Missing self-emissions.** When an element both reads and writes the same ctx key (common for process elements with raw-union I/O), the element's own matching output is not offered as a producer option. The dropdown may show `— no producer —` even though the element itself emits the key.

## Solution — summary

Scope: **Element I/O tab only** (`ElementIoManager` and its `override_computer`). The per-step Steps-tab I/O pane (`StepIoManager`) is out of scope.

Rule:

- Enumerate **real candidates** for each input pin = `external producers ∪ self-outputs` (see Definitions).
- `≥ 2` real candidates → render dropdown as today (with self-outputs added as options).
- `≤ 1` real candidate → render the pin name only, no producer text, no `<select>`.
- The tombstone option `— no producer —` is an option in the dropdown but **does not count** toward the candidate threshold.
- Outputs section is unchanged (already read-only with `⚠ renamed → <key>` badges).

Override-persistence behavior is identical in both branches: `element.properties.io_overrides.inputs` is auto-computed and persisted at open, regardless of whether the row is editable or read-only, so downstream codegen sees the same resolved producer either way.

## Definitions

- **External producer candidate** — a reachable predecessor element whose outputs (honoring that predecessor's own `io_overrides.outputs`) emit a key that matches the pin, where "match" is either equal to the pin name or of the form `<pin>_<shorthash>`.
- **Self-output candidate** — the current element's own output whose effective key (honoring this element's `io_overrides.outputs`) matches the input pin under the same match rule.
- **Real candidates** — `external ∪ self`. The tombstone (`— no producer —`) does not count.
- **Editable threshold** — `real candidates.length >= 2`.

## Flow

### On tab open — `ElementIoManager#openForElement`

1. Fetch pins if the cache is empty (unchanged).
2. Call `computeElementOverrides(canvas, element.id)` to produce default overrides. The revised computer also considers self-outputs as a fallback candidate (see below).
3. Merge into existing `element.properties.io_overrides` via existing `_merge`.
4. Render.

### Per-input render — `_renderInputRow`

Pseudocode:

```
externals = externalCandidates(element, pin)           // reachable preds emitting match
selfs     = selfCandidates(element, pin)               // own outputs emitting match
candidates = externals.concat(selfs)

if candidates.length >= 2:
  render: <pin name> + <select>
    options:
      1. "— no producer —"                              (tombstone, always first)
      2. ...externals (farthest-first order, current)
      3. ...selfs (labeled "<label> • <effective> (self)")
    preselect: existing override match, else nearest candidate
else:
  render: <pin name> only
```

No `<select>` is emitted in the read-only branch.

### Override-computer change — `computeInputOverrides`

After the existing reachable-predecessor scan, if no external producer chosen:

1. Read `selfOutputs = canvas.getElementPins(elementId).outputs`, applying this element's own `io_overrides.outputs` to compute effective keys.
2. If any self effective key matches the pin (plain or `pin_<hash>`), set `chosen = { pid: elementId, effective: <self effective> }`.

Recording rule is unchanged: if `chosen.effective === pin`, record no entry (the plain key already "just works"); else push `{ pin, override_key: chosen.effective }`.

External matches continue to win over self matches — self is a *fallback*, consulted only when the external scan produced no hit. This preserves the existing "nearest reachable producer" semantics for the non-collision case.

## Tombstone interaction

A stored tombstone (`override_key: ""`) always reflects a user's explicit "no producer" choice. Rendering:

- Tombstone present + `≥ 2` real candidates → editable dropdown with `— no producer —` preselected (lets the user revise).
- Tombstone present + `≤ 1` real candidate → read-only, pin name only. Tombstone remains in storage; user sees no producer text.

## Edge cases

| Case | Behavior |
|------|----------|
| 0 real candidates | Read-only row, pin name only. No override entry recorded. |
| 1 real external candidate | Read-only row. Override auto-persisted to that producer's effective key (unless it equals the pin). |
| 1 real self-output candidate (element reads+writes same pin, no external match) | Read-only row. Override auto-persisted to self effective key (unless it equals the pin). |
| `≥ 2` real candidates, no stored choice | Editable dropdown. Default selection = nearest external, else self. Auto-persisted. |
| `≥ 2` real candidates, stored choice | Editable dropdown preselected to stored choice. |
| Stored producer no longer exists / no longer emits match | Existing fallback behavior: revert to default. Unchanged by this design. |
| Self-output pin has been collision-renamed (`renamed_to` on self) | Candidate match uses the renamed effective key; dropdown label shows the renamed key. |
| External + self both match | External wins for the default; both appear in the dropdown when editable. |

## Files changed

- `app/javascript/controllers/property_editor/element_io_manager.js` — `_renderInputRow` gains the candidate-count branch and self-output option rendering.
- `app/javascript/controllers/property_editor/element_io/override_computer.js` — `computeInputOverrides` extends its candidate search to include self-outputs as a fallback, with self-output rename awareness.

No HTML, route, controller, model, or other Ruby changes. No change to `element.properties.io_overrides` shape.

## Out of scope

- Per-step I/O pane in the Steps tab (`step_io_manager.js`) — deferred.
- Outputs section UI — unchanged (already read-only).
- Producer dropdown for process elements whose actual producer is an internal step — still shows "— no producer —" for inputs whose producer is only step-internal (the previous raw-union design accepts this).
- Any server-side changes to `IoExtractor`, `GeneratorRegistry`, or controllers.

## Testing

This project currently has **no JavaScript unit test framework configured** (no `jest.config`, no `spec/javascript/`). The existing `spec/system/property_editor/element_io_tab_spec.rb` is skipped pending a Capybara JS driver. New JS-only logic cannot be asserted via Ruby specs.

Plan:

1. **Extend `spec/system/property_editor/element_io_tab_spec.rb`** with new (still-skipped) examples so the intent is codified for when the JS driver is wired up:
   - Input with `≤ 1` real candidate renders no `<select>` element (just the pin name).
   - Input with `≥ 2` real candidates renders a `<select>` and the options include a `(self)`-labeled entry when the element itself emits the pin.
   - Outputs section remains untouched.

2. **Manual verification on `/96546124/flowcharts/49/edit`**:
   - Element whose every input has only one producer (or none) → all input rows are plain text, no dropdown.
   - Element with a pin that has two matching predecessors → dropdown appears, both options listed.
   - Element that both reads and writes the same pin with no external producer → plain text row (self counts as 1 candidate, threshold not met).
   - Element that both reads and writes a pin AND has an external producer for it → dropdown with external + `(self)` option.
   - Outputs still show the amber `⚠ renamed → <key>` badge when collision-renamed.

3. **No Ruby spec suite runs expected to regress.** Run `bundle exec rspec spec/controllers/code_generators/ spec/services/code_generators/` after the change as a safety check — none of those touch the element I/O tab logic but the JS file is reachable through asset precompile flags on CI.

## Non-goals / guardrails

- Do not introduce a new `CandidateResolver` helper module for this change — the rule is small enough to live inline. Extract later if a second consumer appears.
- Do not change the `io_overrides` JSON shape.
- Do not touch the Step I/O pane or the per-step override computer.

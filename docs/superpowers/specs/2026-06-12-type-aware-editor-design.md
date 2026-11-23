# Type-Aware Property Editor (Round 3) — Semantic Awareness

**Date:** 2026-06-12
**Builds on:** Rounds 1–2 (specs/plans of the same date). Same hard constraints: strictly additive, byte-identical saved JSON, importmap/Stimulus/Tailwind only, existing endpoints only.

## Grounding (verified)

- Entity attributes carry `type` (`String`/`Integer`/`Float`/`NestedEntity`) and `html_type` (`text`/`number`/…), available client-side in `canvas.entityAttributes` and the branch modal's `_selectedEntitySchema`.
- Pins and implicit keys are **name-only**; typing them requires server-side generator analysis — **out of scope**.
- Model actions carry no entity-identifier field by design: the runtime operates on the flowchart's bound entity. Step-level entity inference is therefore unnecessary — the bound entity *is* the step's entity context.
- Value inputs (QC WHERE values, condition right operands, `findValue`) legitimately hold `ctx[:...]` expressions. **Changing input types would block expressions — forbidden.** Type-awareness must be advisory, never restrictive.

## Scope

### A. Type badges on column options

Everywhere a column select renders from an entity schema (step-config `entityField` selects, QC WHERE field select, branch-modal left-operand entity attribute options): the option label gains a type suffix, e.g. `Amount — number`. The option **value** is unchanged (bare slug / `data.<slug>` conventions preserved).

### B. Type-aware value assistance (advisory only)

When the paired column is known (QC WHERE row after field selection; branch field condition whose left operand is an entity attribute; `findValue` when `findField` was chosen from the column select):

1. A small **type chip** (e.g. `number`) appears next to the value input.
2. **Boolean-ish quick-picks**: none in current type vocabulary — skipped (no boolean type exists; revisit if added).
3. **Soft validation**: on change, if the value is neither (a) a literal matching the column's `html_type` (`number` → numeric literal) nor (b) an expression (`looksLikeExpression`: starts with `ctx`, `{{`, `$`, or contains `[:`), the input gets an amber ring + title hint "Expected a number or a ctx expression". Never blocks save, never clears the value.
4. The text input, variable picker, and free typing remain exactly as they are.

Shared helper in `templates.js`: `columnTypeOf(schema, slug)` → `{type, htmlType}|null` and `looksLikeExpression(value)`; one `applySoftTypeValidation(input, htmlType)` used by all three surfaces.

### C. Cross-element collision awareness for resultVar

`_applyResultVarAutoSuggest` extends its collision set with upstream output pin names from the cached `getAvailableVariables` result (await at commit time; on fetch failure, fall back to today's sibling-only scan). Suffixing logic unchanged.

### D. Wiring type data where it already flows

- QC WHERE: `_selectedEntitySchema` is present at row-build time — store the selected column's `html_type` on the row (`data-qc-col-type`) on field change and re-run soft validation.
- Branch field condition: left-operand select options derived from entity attributes carry `data-attr-type`; on left-operand change, the right operand's chip/validation updates. Operator list is **not** filtered (additive constraint).
- `findValue` (and other paired value fields listed in the plan): when the paired `entityField` column select changes, update the chip/validation from `canvas.entityAttributes`.

## Out of scope

- Typing pins/implicit keys (server-side IO extractor changes).
- Step-level entity selection (moot — bound entity is the model context).
- Operator filtering by type (removes capability).
- Date/select widgets (no such types in the current vocabulary).
- Any change to serialized shapes or option values.

## Error handling / degradation

- No bound entity / no schema / unknown column → no chip, no validation, today's exact behavior.
- Validation is visual only (amber ring + title); saving is never blocked by it.

## Testing

- Targeted rspec for any server-rendered touchpoints (likely none); JS via node syntax checks + release-engineer smoke + manual audit list.
- QA: serialization byte-equality on QC WHERE rows / conditions / findValue; no-removal audit (expressions still accepted everywhere); degradation paths.

# Detail-Config Layer Refactor (Round 2) — Process Action Config / Decision Detail / Loop Detail

**Date:** 2026-06-12
**Page:** `/:cid/admin/maintenance/flowcharts/:id/edit` (property sidebar)
**Builds on:** Round 1 (docs/superpowers/specs/2026-06-12-property-editor-refactor-design.md, commits dad9e3f5..23ee14a1)

## Goal

Make the *detail* configuration layer guided and developer-friendly: the per-action `configSchema` fields inside expanded process step cards, the decision branch modal's field-condition / query-count panels, and the loop condition/collection fields. Surface what the system already knows (upstream context variables, tenant entity schemas, sibling-step variable names) at the right moment instead of demanding free-text recall.

## Hard constraints

1. **Strictly additive — no feature or functionality removal.** Every current capability stays: all field types, manual text entry (always available as an escape hatch on every new widget), key-value lists, all existing options and behaviors. New widgets *wrap or augment* existing inputs; they never take a capability away.
2. **Saved config JSON is byte-identical.** No changes to `configSchema` key names, value types, or the serialized shapes of `config{}`, `condition{}`, `queryConfig{}`, `branches[]`, or loop properties. New schema properties are rendering hints only (`keyPlaceholder`, `valuePlaceholder`, `group`, `entityField`) and are never serialized into element config.
3. Importmap + Stimulus + Tailwind only; admin-only surface; tenant-scoped data sources only (existing endpoints — no new APIs).
4. Layout reorganization is permitted (user-approved) but the panel shell, tabs, and round-1 surfaces keep their behavior.

## Decisions on PO open questions

1. **Entity context for model-action column pickers:** derive from `canvas.entityAttributes` (the flowchart's bound entity). When absent or the entity API errors, degrade silently to today's plain text input. No UI-only entity pseudo-pickers, no serialized `entityId` additions.
2. **Disclosure split rule:** heuristic — `required: true` fields and `visibleWhen`-free fields stay open when the action has > 6 fields; the rest collapse under "More options". An optional `group: "core" | "advanced"` annotation on a schema field overrides the heuristic in either direction. Hand-annotate the heavy actions (`query_models`, `transform`, `API_call` and similar 12+-field schemas) so their core workflow fields stay exposed.
3. **resultVar collision detection:** synchronous scan of the current process element's sibling steps only (live DOM via the same selectors `collectSteps` uses). Suffix `_2`, `_3`… on collision. The variable dropdown additionally shows a "Used in this element" group.

## Design

### A. Variable-pick affordance (extends `context_autocomplete_controller`)

A small variable icon button (`{x}` glyph) rendered inside the right edge of text inputs that reference variables/expressions. Clicking it opens the *same* grouped dropdown the controller already shows on keystroke (Always Available / From '<element>' / From '<step>' / Used in this element), inserting at cursor (replacing the whole value when empty).

- Mechanism: add a `picker` action to `context_autocomplete_controller` (button click → open dropdown with empty-prefix match = full list). Purely additive; keystroke behavior unchanged.
- Attached where the schema key matches the variable-reference pattern (`*Var`, `*Variable`, `*Key`, `*Expression`, `collection`, `sourceField`, `targetField`) — pattern centralized in one helper so the field builders and condition builders share it.
- Also attached to: loop `collection`, condition-builder left-operand manual input and right-operand custom input (decision + loop), and query-count WHERE value inputs.
- Never on `select`/`number`/`key_value_list` fields.

### B. Entity-aware column selects

- New rendering-hint annotation `entityField: true` on configSchema fields that hold a model column name (`findField`, `distinctField`, `groupBy`, `aggregateField`, `filterField`, `sortField`, `groupField`, …).
- When `canvas.entityAttributes` provides a bound entity, these render as a `<select>` of columns with an "enter manually…" option swapping to the original text input (same swap pattern as the branch left operand). No entity context → exactly today's text input.
- Query-count WHERE row key side becomes a column-select seeded from the already-fetched `_selectedEntitySchema`, same escape hatch; fetch failure → plain text input (existing silent-fail behavior preserved).

### C. Progressive disclosure inside configSchemas

- `buildStepConfigFieldsHTML` partitions fields: core (per decision #2) renders flat; the rest render inside a `buildDisclosureSection` "More options" (collapsed) with an "(N set)" badge counting non-default values inside.
- Actions with ≤ 6 fields render flat — no disclosure.
- Open/closed state persists across step-card collapse/expand within the page session (Map keyed by step id + section id; cleared on element close).
- `visibleWhen` continues to work in both partitions unchanged.

### D. resultVar auto-suggest

- On step commit, output-variable fields (`resultVar`, `outputKey`, `targetVariable`) auto-fill per schema `default`; when no default, derive from the action key (e.g. `find_model` → `model`). Collision with sibling steps appends `_2`, `_3`….
- Pre-filled, immediately editable, never re-derived after manual edit (same `iff-empty`/dirty-flag discipline as the round-1 For-Each auto-fill).

### E. Semantic key-value list placeholders

- `buildConfigKeyValueList` honors optional `keyPlaceholder` / `valuePlaceholder` schema hints (falling back to today's "Key"/"Value").
- Populate meaningful placeholders across the KV-list fields in action_configs (`conditions`, `bindings`, `computedFields`, `fieldAssignments`, `fieldMappings`, `renameMap`, `headers`, etc.). Display-only; serialization untouched.

### F. Layout polish (within the existing shell)

- Detail config fields inside a step card get a consistent two-tier layout: core fields stacked full-width with aligned labels; "More options" disclosure beneath; helper text styling consistent with round 1.
- Condition builders (decision main, branch modal, loop) share identical row styling and the variable-pick affordance, so the three surfaces feel like one system.
- No tab structure changes; the panel shell, resize behavior, and round-1 surfaces stay as shipped.

## Data flow notes

- Variable lists come from the existing cached `ContextVariableProvider.getAvailableVariables` (implicit keys endpoint + upstream pins) — no new fetches beyond what fires today.
- Column lists come from `canvas.entityAttributes` (page-load) and the branch modal's existing `/entities/:id.json` fetch. 403/error → silent degradation to text input.

## Error handling

- Entity API failure: amber "schema unavailable" icon hint, plain text input, never blocking.
- Empty variable list: dropdown shows the implicit group only; full failure shows a non-blocking "No variables available" row.

## Testing

- Component/request specs where server-rendered surfaces are touched (minimal this round — mostly client-side).
- Request-spec markup guards extended only for *additive* attributes (e.g. variable-pick button data-attributes in server-rendered shells, if any).
- QA focus: serialization byte-equality for representative configs (KV lists, WHERE rows, condition objects, resultVar fields) before/after the widget upgrades; degradation paths (no entity, API error); no-removal audit — every pre-round-2 interaction still possible.

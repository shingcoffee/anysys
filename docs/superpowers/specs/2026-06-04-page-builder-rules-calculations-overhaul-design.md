# Page Builder — Conditional Rules & Calculated Fields Overhaul

**Date:** 2026-06-04
**Surface:** `/:cid/admin/maintenance/pages/:id/edit` toolbar → "Conditional Rules" and "Calculated Fields"
**Scope decision:** Full world-class overhaul (Airtable-style pill formula editor; centralized + per-field rule entry).

## Guiding references
- **Conditional Rules** → Jotform Conditions (centralized list + live tester) + Fillout (per-field inline logic) + Typeform (contextual value editors).
- **Calculated Fields** → Airtable formula field (pill tokens + autocomplete + live result) + Fillout (validation + formatting).

## Current state (baseline)
- `app/javascript/controllers/page_builder/rules_manager.js` (485 lines) and `calculations_manager.js` (286 lines) build their editor modals from large `innerHTML` template literals — **violates AGENTS.md** (views must be encapsulated in ViewComponents; Stimulus-only JS).
- Rules & calculations persist in `Page#configuration_json` (`rules: []`, `calculations: []`). No new AR model needed.
- Runtime evaluation: `app/javascript/controllers/condition_runtime_controller.js` using `lib/condition_evaluator.js` + `lib/formula_engine.js`.
- Gaps:
  - Condition value is always a plain text `<input>` regardless of operator/field type.
  - Builder cannot set action values, though runtime supports `set_value` / `set_required value`.
  - `between` / `matches_regex` operators exist in the runtime evaluator but are not exposed in the builder.
  - Formula editor is a plain `<textarea>` — no validation, autocomplete, live preview, or error feedback; invalid formulas silently fail at runtime.
  - Runtime supports calculation `format` (currency/number) but the builder cannot configure it.

## Architecture principles
1. **Eliminate inline `innerHTML` modal strings** — replace with **ViewComponents** rendering the markup, driven by **dedicated Stimulus controllers**. Tailwind-only, Stimulus-only, no custom CSS/JS frameworks.
2. **No new AR models / migrations / routes.** Rules & calculations stay in `Page#configuration_json`. Multi-tenant surface unchanged (page already `customer_id`-scoped at the controller; admin-or-owner guard already present).
3. **One shared formula module** — `lib/formula_validator.js` wraps `FormulaEngine` to return `{ valid, errors[], referencedFields[], result }`, reused by the editor (live preview/validation).

## Data / schema changes (within `configuration_json`)
- **Formula storage** switches to stable `{field_id}` token refs (e.g. `{price} * {qty}`) so pills survive label edits. `FormulaEngine.tokenize` + runtime updated to parse braces. Existing bare-identifier formulas normalize to `{field_id}` on load (one-time, no back-compat shim retained).
- **Calculation** gains `format: { type: plain|number|currency|percent|date, decimals, prefix, suffix }`.
- **Rule action** gains `value` (for `set_value` / `set_required`); operators `between` & `matches_regex` exposed in the builder.

## Feature set — Conditional Rules
1. **Contextual condition value editor** — value input adapts to *operator × target-field type*:
   - select/radio field → option dropdown
   - number field → number input; `between` → two number inputs
   - date field → date picker; date `between` → two date pickers
   - boolean field → checked/unchecked toggle
   - `is_empty` / `is_not_empty` / `is_selected` / `is_not_selected` → no free value input
   - `matches_regex` → text input + hint
   - Operator list is filtered to those valid for the chosen field type.
2. **Action value editor** — `set_value` shows a value editor matching the target field; `set_required` toggle; show/hide/enable/disable need no value.
3. **Live Test mode** — a toggle inside the rule editor renders sample inputs for the referenced fields and evaluates the rule in real time, showing which actions *would* fire (✓/✗). (Jotform-style tester.)
4. **Per-field "Add logic"** — an affordance on each field's property panel opens the rule editor pre-scoped with that field as the action target; the centralized panel remains the source of truth.
5. **List polish** — enable/disable toggle, duplicate, human-readable summary line ("When Country = US → show 3 fields"), and search/filter when the list is long.

## Feature set — Calculated Fields (Airtable-style)
1. **Pill/token editor** — a `contentEditable` surface; field refs render as removable colored pills; backspace deletes a whole pill; caret-aware insertion.
2. **Autocomplete** — typing `{` or `@` opens a field picker; typing letters opens a function dropdown with signatures (e.g. `ROUND(number, decimals)`).
3. **Live preview panel** — editable sample values for referenced fields → instant computed result with formatting applied; validation status (valid / error with message + position).
4. **Inline error highlighting** — unknown function, unbalanced parens, unknown field reference.
5. **Output formatting controls** — type / decimals / prefix / suffix, reflected live in preview.
6. **Circular-dependency detection** — warns if calc A → calc B → A.
7. **Function reference** — grouped Math / Logic / Text / Date with one-line descriptions and signatures.

## Server-side validation (Reform contract + Activity step on page save)
Reject saves where: a referenced/target field id doesn't exist on the page, a formula fails to parse, an action target is missing, or calculations form a dependency cycle. Returns structured errors to the editor. **No new route/URL** — folded into the existing page-update path under `/:cid/admin/maintenance/pages/:id` (admin-or-owner guard already present).

## Component / file plan (high level)
- **New ViewComponents:** `PageBuilder::RuleEditorComponent`, `PageBuilder::ConditionRowComponent`, `PageBuilder::CalculationEditorComponent`, `PageBuilder::FormulaPillEditorComponent`; enhance existing `RulesPanelComponent` / `CalculationsPanelComponent`.
- **New / refactored Stimulus:** `rule_builder_controller.js`, `formula_editor_controller.js`; `rules_manager.js` / `calculations_manager.js` slim down to open/close + read-back (no HTML strings).
- **Shared lib:** `lib/formula_validator.js`; update `lib/formula_engine.js` + `lib/condition_evaluator.js` (brace tokens, exposed operators) + `controllers/condition_runtime_controller.js` (format / value / new-operator alignment).
- **Backend:** page-update Reform contract validation + Activity step; specs.

## Testing
- ViewComponent specs for each new component.
- Contract / request specs for the save-validation path, including the field-existence guard (tenant isolation is inherent — config is per-page and the page is customer-scoped).
- System spec for the editor interactions if a system-spec harness exists; otherwise lean on component + request specs.
- Honour the stale-test policy: when an existing spec fails because production behaviour intentionally changed, rewrite the spec.

## Out of scope
- No new AR models, migrations, or routes.
- No changes to the runtime form-rendering pipeline beyond token-format + operator/format alignment.
- No backward-compat shims (greenfield per AGENTS.md) — existing formulas migrate to `{field_id}` tokens via a one-time normalize on load.

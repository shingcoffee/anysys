# Conditional Rules & Calculated Fields — UX Redesign

**Date:** 2026-06-05
**Surface:** Page editor (`/:cid/admin/maintenance/pages/:id/edit`) toolbar → "Conditional Rules" and "Calculated Fields"
**Approach:** A — right-docked slide-over drawer with master→detail, unified chrome

## Problem

The current UX for both features is dated/generic and the build experience is clunky:

- Two-level navigation: a full-screen tab-panel overlay (`top-16 left-72`) for the list, then a centered blocking modal for editing.
- The modal hides the canvas, so users can't see their fields while wiring rules/formulas.
- Conditions and actions are built from bare, unlabeled `<select>` rows — hard to read and compose.
- The wide centered overlay wastes space for what is essentially a list.

Goal: modernize the visuals **and** improve the build experience, with **zero loss of existing functionality** and a **unified** design language across both features (differentiated only by accent: indigo = Rules, purple = Calculations).

## Feature inventory (must preserve)

### Conditional Rules
- **List:** rule count, search box (shown when > 6 rules), empty state, per-rule enable/disable toggle, name, natural-language summary, hover actions (duplicate / edit / delete).
- **Editor:** rule name; top-level AND/OR logic; condition **groups** (each with its own AND/OR, add/remove); condition **rows** with 16 operators (`equals … matches_regex`) and type-contextual value editors (text / number / number-range / date / date-range / select / boolean / none); 9 action types (`show_field, hide_field, show_page, hide_page, skip_to_page, enable_field, disable_field, set_required, set_value`) with field-or-page target select + value input for `set_required`/`set_value`; **Test Mode** with sample inputs that show which actions fire.

### Calculated Fields (live path = `CalculationEditorComponent`)
- **List:** calculation count, search (> 6), empty state, target-field label, format badge, mono formula preview, hover actions (edit / delete).
- **Editor:** target field select (grouped by page via `<optgroup>` when multiple pages); **pill formula editor** (`FormulaPillEditorComponent` + `formula-editor` controller) with contenteditable surface, autocomplete dropdown, live validation/preview, errors; 31 functions across Math / Logic / Text / Date; output formatting (plain / number / currency / percent) + decimals + prefix + suffix; sample-value live preview.

## Design

### Shared chrome — `PageBuilder::BuilderDrawerComponent`
A reusable right-docked slide-over panel (~520px wide; full-width sheet below `sm`). Provides:
- **Header:** accent-tinted icon, title, subtitle, close button.
- **Body:** scrollable; hosts either the **list** state or the **editor** state. Transition between states is an animated horizontal slide (master→detail) with a back affordance in the editor header.
- **Footer:** sticky; contextual actions (list state: none/primary "Add"; editor state: Cancel / Save).
- **Accent token:** `accent: :indigo | :purple` drives header tint, primary button, focus rings, connector badges. This is the only visual difference between the two features.

The drawer replaces BOTH the full-screen tab-panel overlay AND the centered modal. The canvas remains visible to the left while the drawer is open. A translucent scrim sits over the canvas on mobile only.

### Conditional Rules
- **List state:** rows show a status pill (enabled/disabled), rule name, and a one-line natural-language summary ("When **Country** equals US → Show **Shipping address**"). Hover reveals duplicate / edit / delete. Search appears above the list when > 6. Empty state with icon + copy + primary "Add Rule".
- **Editor state:** a readable **WHEN → THEN** layout.
  - **WHEN:** group AND/OR rendered as a segmented control. Each condition is a natural-language chip row `[Field ▾] [operator ▾] [value]` stacked on a vertical rail; AND/OR connector badges render between rows and between groups. Add condition / add group / remove preserved. Every one of the 16 operators and all contextual value editors are preserved (the `ConditionRowComponent` value-editor logic is reused).
  - **THEN:** action rows `[Action ▾] [Target ▾] (value)` with all 9 action types; target switches between field/page lists by action type; value input for `set_required`/`set_value`. Add/remove preserved.
  - **Live summary** at the top of the editor mirrors the list summary as the user edits.
  - **Test Mode** kept as a collapsible section at the bottom (toggle + sample inputs + per-action fire indicator).

### Calculated Fields
- **List state:** rows with target-field label, format badge, and mono formula preview. Hover reveals edit / delete. Search > 6. Empty state + primary "Add Calculation".
- **Editor state:**
  - Target field select (grouped by page, preserved).
  - **Pill formula editor** kept as-is functionally (contenteditable + autocomplete + live result + errors), restyled to match drawer chrome.
  - **Function inserter:** the 31 functions presented as a categorized, searchable inserter — Math / Logic / Text / Date tabs with click-to-insert chips and a filter box. Replaces the old flat wall of buttons.
  - **Format controls:** type / decimals / prefix / suffix, preserved.
  - **Sample-value preview** preserved.

## Component & file plan

**New / changed ViewComponents (Tailwind only):**
- `PageBuilder::BuilderDrawerComponent` (new) — shared chrome (header/body/footer, accent, list↔editor slots).
- `PageBuilder::RulesPanelComponent` — restyle as drawer list state.
- `PageBuilder::RuleEditorComponent` — restyle as drawer editor state (WHEN/THEN rail, segmented AND/OR, live summary). Reuse `ConditionRowComponent` value-editor logic.
- `PageBuilder::ConditionRowComponent` — chip styling, accent-aware.
- `PageBuilder::CalculationsPanelComponent` — restyle as drawer list state.
- `PageBuilder::CalculationEditorComponent` — restyle as drawer editor state + categorized function inserter.
- `PageBuilder::FormulaPillEditorComponent` — restyle only.

**Editor view (`app/views/admin/maintenance/pages/_editor.html.erb`):**
- Replace the two `tab-panel` full-screen overlays (rules, calculations) with drawer mounts.
- Keep the existing template-clone pattern for the editor states.

**Stimulus (reuse, adapt mount targets — no logic rewrite):**
- `page_builder_controller.js` + `page_builder/rules_manager.js` + `page_builder/calculations_manager.js`: change open/close to drive the drawer + master→detail slide instead of the overlay+modal. Inline HTML strings in the managers updated to match new markup.
- `rule_builder`, `formula-editor` controllers: unchanged logic; selectors verified against restyled markup.

**Dead code removal (verified unused):**
- `app/components/page_builder/formula_editor_component.rb`
- `app/components/page_builder/formula_editor_component.html.erb`
- `app/javascript/controllers/formula_engine_controller.js`
(All three are referenced only by each other; the live path is `CalculationEditorComponent` + `formula-editor`.)

## Constraints
- Tailwind only, Stimulus only, ViewComponent encapsulation (AGENTS.md).
- Fully responsive: ~520px drawer on desktop/tablet, full-width sheet on mobile.
- This surface lives under `/:cid/admin/...` (admin area) — no route/auth/tenant changes; no schema changes (rules/calculations remain in `configuration_json`). Backend/security/migration work is out of scope.

## Out of scope
- Changing the rule/calculation JSON data model or the runtime engines (`Pages::RulesEngine`, `FlowchartRuntime::*`).
- New operators, action types, or formula functions beyond what exists.
- Any non-page-builder surface.

## Testing
- Component specs for `BuilderDrawerComponent`, restyled panels/editors (render + slot + accent + feature-parity assertions: all operators/actions/format controls present).
- Existing rule/calculation request/system specs must still pass; update any spec that asserts the old overlay/modal markup (stale-test policy: rewrite to match new markup, do not revert production).

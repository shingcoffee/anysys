# Property Popup Improvements — Design

Date: 2026-04-17
Scope: Flowchart edit page → right-side property popup / property editor.

## Goals

Five user-facing changes to the property popup on the flowchart edit page:

- **(a)** Header shows only the element icon and label; no element type text.
- **(b)** The default active tab when the popup opens depends on element type:
  `process → Steps`, `decision → Branches`, `loop → Advanced`, `timer → Advanced`, `error_handler → Advanced`, everything else → `General`.
- **(c)** Refactor the Loop element's Advanced tab — it is cluttered because the `loopType` selector lives on General while the fields it controls live on Advanced.
- **(d)** The General tab's `label` field is auto-derived from the element's other property configuration. The user can override it by typing; clearing the field resumes auto-derivation. Derivation is live as the user edits properties in the popup.
- **(e)** The Add Decision Branch modal — remove the separate "label" concept entirely: the branch's label is always its name. Description already sits at the bottom of the modal and stays there.

## Non-Goals

- No element schema changes beyond moving `loopType` to Advanced and adding label derivation for `join` and `subflow`.
- No changes to how labels are persisted server-side.
- No changes to other popups (step modal, join modal, I/O panel).
- No changes to canvas element rendering paths beyond the existing `renderElement` path used when a label changes.

## Current State (verified from code)

Relevant files:

- `app/views/flowcharts/_editor.html.erb:445-551` — right sidebar property popup markup.
- `app/javascript/controllers/property_editor_controller.js` — main Stimulus controller; houses `_deriveLabelFromProperties`, `_autoDeriveLabelOnOpen`, `_syncChangesToCanvas`.
- `app/javascript/controllers/property_editor/form_builder.js` — builds form fields, `_updateTitle`, label auto-derive detection.
- `app/javascript/controllers/property_editor/tab_manager.js` — tab visibility and default tab per element type.
- `app/javascript/controllers/property_editor/branch_manager.js` — branch collection, modal behavior, branch row construction.
- `app/javascript/controllers/property_editor/templates.js` — branch modal template and branch row template.
- `app/javascript/flowchart/constants/schemas.js` — element property schemas.
- `app/javascript/flowchart/constants/elements.js` — element colors / default labels.

Findings that shape the work:

1. Task **(a)** — header already renders only icon + label (`form_builder.js:109-135`). The "type-looking" text the user sees is the label falling back to the default type name (`"Process"`, `"Decision"`, …) when no meaningful label has been set. Fixing label derivation (d) fixes (a) as a by-product.
2. Task **(b)** — default-tab-per-type is already implemented in `tab_manager.js:65-69` for `process`, `decision`, `loop`. Gaps: `timer` and `error_handler` should default to Advanced too.
3. Task **(c)** — the cluttered feeling comes from `loopType` being on General while `condition`, `collection`, `itemVariable`, `indexVariable` are on Advanced (`schemas.js:316-369`). Changing tabs to see the effect is the core issue.
4. Task **(d)** — `_deriveLabelFromProperties` already handles `process/decision/start/end/loop/timer/error_handler`. Gaps: `join` and `subflow`. Current derivation runs on popup-open only, not live on property changes.
5. Task **(e)** — the modal has no visible "label" field (only Branch Name, Condition, Description, with description already last at `templates.js:765-774`). The `label` concept survives only as a hidden form input (`templates.js:861`) and a `· labelSuffix` in the row (`templates.js:817-820, 845`). The user wants this removed — label is always the name.

## Design

### 1. Label auto-derivation (task d, and transitively task a)

Behavior:

- **On popup open:** compute `derived = _deriveLabelFromProperties(props)`. Set the label `<input>` value to `derived` and `currentElement.label = derived`. Set `_labelAutoDerived = true`.
  - Exception: if the element already has a label that differs from both the default type name and the current derived value, treat it as a user-authored override. Do not overwrite it. Set `_labelAutoDerived = false`.
- **On property change within the popup** (any call path that reaches `_syncChangesToCanvas`): if `_labelAutoDerived`, re-run derivation and update the label `<input>` and `currentElement.label` in place, then re-render the canvas element title (existing path — the same one the header uses).
- **On user typing in the label `<input>`:** set `_labelAutoDerived = false`. Derivation stops until the field is cleared.
- **On the user clearing the label `<input>`:** set `_labelAutoDerived = true` and immediately re-derive.

New formulas to fill gaps:

- `join` → `"Join (" + joinStrategy + ")"` (e.g. `"Join (wait_all)"`). Fallback `"Join"`.
- `subflow` → `"→ " + referencedSubflowName` when known; fallback `"Subflow"`. The referenced subflow name is read from whatever property currently stores it; if unresolved (e.g. schema does not track it), keep `"Subflow"` and leave a TODO for a future pass that surfaces the subflow reference on the schema.

Wiring:

- `property_editor_controller.js` — add `_refreshDerivedLabel()`:
  - Guard: return early if `!_labelAutoDerived`.
  - Compute `derived` from currently-collected properties (use the same properties-collection path `_syncChangesToCanvas` uses so the derivation sees live in-flight values).
  - Update the label `<input>` DOM value (without firing another input event — set `.value` directly).
  - Update `currentElement.label = derived`.
  - Ask the canvas to refresh this element (existing path already used when label changes).
- Call `_refreshDerivedLabel()` from `_syncChangesToCanvas()` after properties are collected but before change events fire.
- `form_builder.js` — attach `input` and `blur` listeners on the label field:
  - On `input`: if the field has content, `_labelAutoDerived = false`. If empty, `_labelAutoDerived = true` and call `_refreshDerivedLabel()`.
  - (Extends the existing logic at `form_builder.js:484-492`.)
- `_deriveLabelFromProperties` (`property_editor_controller.js:877-904`) — add `case "join"` and `case "subflow"`.

Task (a) is resolved transitively: once derivation is reliable, the header title never falls back to the default type name.

### 2. Default tab per element type (task b)

Extend the map in `tab_manager.js:65-69`:

```
process         → steps
decision        → steps   (pane is labeled "Branches")
loop            → advanced
timer           → advanced   (NEW)
error_handler   → advanced   (NEW)
start           → general
end             → general
join            → general
subflow         → general
```

The existing `configureForElementType()` already applies the map on every popup open, so no other wiring is needed. Confirm with system tests (see Testing).

### 3. Loop Advanced tab refactor (task c)

Moves:

- `schemas.js` — change `loopType.tab` from `"general"` to `"advanced"`.
- `schemas.js` — reorder the loop schema so `loopType` appears first among `advanced` fields.
- `schemas.js` — mark the field so the renderer uses a segmented control: `loopType.control = "segmented"`.
- `form_builder.js` — in `_buildInputHTML`, when `fieldSchema.type === "select" && fieldSchema.control === "segmented"`, render as a 3-button segmented control:
  - Pattern mirrors the existing Field/Query toggle at `templates.js:669-682`.
  - Buttons: `While`, `Do-While`, `For-Each`.
  - Buttons carry `data-action="click->property-editor#selectSegmentedOption"` (new small handler) which updates a hidden `<input name="loopType">` and dispatches the `change` event — so the existing `handleLoopTypeChange` visibility handler keeps working unchanged.
  - Group role: `role="radiogroup"`, each button `role="radio"` and `aria-checked`.
- `form_builder.js` — existing single-column layout for loop Advanced (`form_builder.js:182-188`) stays. Add a light visual grouping:
  - Top: the segmented control (loopType).
  - Middle: fields governed by the current loopType (already toggled via `visibleWhen`).
  - Bottom: `Max Iterations` under a small `Safety` mini-label, added to the schema as a metadata field `safetyGroup: true` or (simpler) inserted literally by the renderer when emitting the loop Advanced pane.

No new Stimulus controller. One new small handler (`selectSegmentedOption`) on the existing `property-editor` controller, reusable by any future segmented select.

### 4. Decision branch — remove label concept (task e)

- `templates.js` (`buildBranchItemTemplate`, `templates.js:804-867`):
  - Remove `label` from the destructured params.
  - Remove the `labelSuffix` computation and its use in the row markup.
  - Remove the hidden `branches[index][label]` input.
- `branch_manager.js`:
  - `collectBranches()` — drop `label` from reads and from the returned object.
  - `buildBranchItemHTML(index, branchValue, label, description, …)` — drop the `label` parameter.
  - `buildBranchesFieldHTML` — drop `branch.label` when rendering existing branches.
  - `addBranchFromModal` / `quickAddBranch` — drop the `label` argument passed to `buildBranchItemHTML`.
- The modal itself (`buildBranchModalTemplate`, `templates.js:624-797`) — no change; description is already last.

Downstream consumers of `branch.label` must be updated at the same time (grep: ruby services, codegen templates, specs). Per `AGENTS.md` (no backward compatibility), replace references with `branch.name` rather than aliasing.

## Files Touched

| File | Change |
|---|---|
| `app/javascript/controllers/property_editor_controller.js` | `_refreshDerivedLabel`; call from `_syncChangesToCanvas`; `case "join"` and `case "subflow"` in `_deriveLabelFromProperties`; `selectSegmentedOption` handler. |
| `app/javascript/controllers/property_editor/form_builder.js` | Segmented-control render path; label input listeners extended; safety mini-label for loop Advanced. |
| `app/javascript/controllers/property_editor/tab_manager.js` | Extend default-tab map (`timer`, `error_handler`). |
| `app/javascript/controllers/property_editor/branch_manager.js` | Drop `label` from collection / builder / add / render paths. |
| `app/javascript/controllers/property_editor/templates.js` | `buildBranchItemTemplate` drops `label` suffix and hidden input. |
| `app/javascript/flowchart/constants/schemas.js` | `loop.loopType.tab = "advanced"`, `control = "segmented"`, reorder. |
| Ruby downstream (codegen / services / specs) | Replace `branch.label` reads with `branch.name` wherever they exist. |

## Testing

**System tests** in `spec/system/flowchart_management_spec.rb`:

- Opening a Process popup lands on the Steps tab.
- Opening a Decision popup lands on the Branches tab.
- Opening a Loop popup lands on the Advanced tab.
- Opening a Timer or Error Handler popup lands on Advanced.
- Loop Advanced: segmented control renders; clicking `For-Each` shows collection/item/index fields and hides the condition builder.
- Label derivation: adding a first step to an empty Process updates the popup header and label field to the step's action name. Typing in the label input freezes derivation (change another property → label does not update). Clearing the label resumes derivation.
- Adding a decision branch: the new row shows only the name + condition summary + description. No `· label` suffix. No hidden `branches[*][label]` input in the DOM.

**Component specs** under `spec/components/property_editor/`: if a ViewComponent is introduced for the segmented control, add a spec. (If rendered inline from `form_builder.js` only, no new component spec.)

**JS-level assertions** are covered via system tests since there is no JS test harness configured.

## Risks & Mitigations

1. **Downstream consumers of `branch.label`.** Grep the codegen / services layer; update to `branch.name`. No shim.
2. **Derivation on every keystroke.** String ops are cheap; if the canvas re-render flashes, debounce `_refreshDerivedLabel` at ~60ms.
3. **User-authored label preservation across sessions.** Open-time detection: if `currentElement.label` is non-empty AND not equal to the derived value AND not equal to the default type name, assume user-authored, set `_labelAutoDerived = false`.
4. **Segmented control accessibility.** Use `role="radiogroup"` / `role="radio"` / `aria-checked`; active-state styling mirrors the existing Field/Query toggle so visual language stays consistent.

## Out of Scope

- Back-end changes to how labels or branches are persisted.
- Other popups or modals.
- Canvas rendering changes beyond the existing path triggered when an element's label changes.
- Adding a subflow-reference schema field (acknowledged as a TODO for subflow label derivation).

# Flowchart Editor Bug Fixes & Issues

**Date:** 2026-03-26
**Scope:** 4 bugs + 2 issues in the flowchart edit page property editor
**Approach:** Targeted fixes, minimal changes (Approach A)

---

## Bug 1: Timer element conditional fields don't toggle

**Severity:** High
**Root cause:** `form_builder.js:205-213` wires change handlers for `loopType`, `triggerType`, and `responseType` selects but not for `delayType` on the Timer element. The schema defines `duration`, `durationUnit`, and `waitCondition` with `visibleWhen: { field: "delayType" }`, so changing delay type has no effect on field visibility.

**Fix:**
- `form_builder.js`: Add `delayType` to the extraAction mapping in `_buildFieldHTML()`:
  ```js
  } else if (fieldName === "delayType") {
    extraAction = ` data-action="change->property-editor#handleDelayTypeChange"`
  }
  ```
- `property_editor_controller.js`: Add `handleDelayTypeChange(event)` handler following the same pattern as `handleLoopTypeChange` — queries `[data-visible-when]` elements, filters on `visibleWhen === "delayType"`, toggles `hidden` class based on `data-visible-values`.

**Files changed:**
- `app/javascript/controllers/property_editor/form_builder.js`
- `app/javascript/controllers/property_editor_controller.js`

---

## Bug 2: "stepChanged" event not listened for

**Severity:** High
**Root cause:** `step_manager.js:1253` dispatches a `"stepChanged"` custom event from `handleConfigFieldChange()`, but `_setupFormChangeListeners()` in `property_editor_controller.js:762-787` never registers a listener for it. Config field changes within expanded steps (find strategy, save strategy, etc.) don't trigger canvas sync.

**Fix:**
- `property_editor_controller.js`: Add `"stepChanged"` event listener in `_setupFormChangeListeners()` and corresponding `removeEventListener` in `_removeFormChangeListeners()`.

**Files changed:**
- `app/javascript/controllers/property_editor_controller.js`

---

## Bug 3: Step presets violate 1-step-per-process limit

**Severity:** Medium
**Root cause:** `step_manager.js` STEP_PRESETS define multi-step arrays (CRUD Create has 4 steps), but the UI enforces a 1-step limit per process element. The 1-step limit is intentional by design.

**Fix:**
- Rework `STEP_PRESETS` to contain only the primary step per preset:
  - `crud_create` -> `save_model` (saveStrategy: "saveAll")
  - `crud_read` -> `find_model` (findStrategy: "find") — already 1 step
  - `crud_update` -> `save_model` (saveStrategy: "saveAll")
  - `crud_delete` -> `destroy_model` (destroyStrategy: "destroy")
- The existing `applyPreset()` logic already disables the Add Step button after adding steps, so no other changes needed.

**Files changed:**
- `app/javascript/controllers/property_editor/step_manager.js`

---

## Bug 4: No "Label" field in element schemas

**Severity:** Medium-High
**Root cause:** `schemas.js` ELEMENT_SCHEMAS don't include a label/name field. Process and Decision auto-derive labels from steps/condition, but Start, End, Loop, Fork, Join, Error Handler, and Timer have no way to change their label from the property editor.

**Fix:**
- `schemas.js`: Add a `label` field as the first property in every element schema:
  ```js
  label: { type: "text", label: "Label", placeholder: "Element name..." }
  ```
- `form_builder.js` `buildForm()`: Populate the label field from `this.controller.currentElement.label` since label lives on the element itself, not in `element.properties`.
- `property_editor_controller.js` `_collectFormData()`: Read the label value from form data and return it alongside properties.
- `property_editor_controller.js` `_deriveLabelFromProperties()`: If user has explicitly typed a label value, use it. Only auto-derive for process (from steps) and decision (from condition) when the label field is empty or matches the auto-derived value.
- `_performSync()` and `save()`: Pass the explicit label to `canvas.updateElementProperties()`.

**Files changed:**
- `app/javascript/flowchart/constants/schemas.js`
- `app/javascript/controllers/property_editor/form_builder.js`
- `app/javascript/controllers/property_editor_controller.js`

---

## Issue 5: Decision default branch may duplicate on re-open

**Severity:** Low-Medium
**Root cause:** `branch_manager.js:359-368` creates a default "Yes" branch element on the canvas when `branches.length === 0`. If the form is rebuilt before branch data is persisted (open editor, close without saving, open again), a duplicate branch element could be created.

**Fix:**
- In `buildBranchesFieldHTML()`, before creating the default branch element, check if there are already connections FROM the current decision element to process elements on the canvas. If a connected element exists, reuse its ID rather than creating a new element.
- Specifically: search `canvas.connections` for connections where `from === currentElement.id`, find the target element, and use it as the default branch's `elementId`.

**Files changed:**
- `app/javascript/controllers/property_editor/branch_manager.js`

---

## Issue 6: Style only saves when BOTH fill and stroke are set

**Severity:** Low
**Root cause:** `property_editor_controller.js:662` uses `if (styleFill && styleStroke)` — empty string is falsy, so if only one value is set, style becomes `null`.

**Fix:**
- Change condition from `if (styleFill && styleStroke)` to `if (styleFill || styleStroke)`.
- When both are empty (Default style), style correctly becomes `null`.

**Files changed:**
- `app/javascript/controllers/property_editor_controller.js`

---

## Files Impact Summary

| File | Bugs/Issues |
|------|-------------|
| `app/javascript/controllers/property_editor_controller.js` | 1, 2, 4, 6 |
| `app/javascript/controllers/property_editor/form_builder.js` | 1, 4 |
| `app/javascript/controllers/property_editor/step_manager.js` | 3 |
| `app/javascript/controllers/property_editor/branch_manager.js` | 5 |
| `app/javascript/flowchart/constants/schemas.js` | 4 |

## Test Coverage

Each fix should have corresponding RSpec or JS tests:
- Bug 1: Test timer element property editor shows/hides fields on delayType change
- Bug 2: Test that config field changes in steps trigger canvas sync
- Bug 3: Test that presets apply exactly 1 step
- Bug 4: Test that label field appears in all element type editors and updates canvas
- Issue 5: Test that reopening decision editor doesn't create duplicate branch elements
- Issue 6: Test that style saves correctly with partial fill/stroke values

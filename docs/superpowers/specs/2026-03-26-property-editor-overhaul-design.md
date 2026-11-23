# Property Editor Overhaul Design Spec

**Date:** 2026-03-26
**Scope:** Redesign the right sidebar property editor for a more professional, structured feel
**Style Reference:** Webflow/Retool — dense, structured panels with clear section headers and visible affordances

---

## Overview

Four changes to make the property editor look and feel like a professional tool panel: a color-coded header, pinned footer, field section separators, and consistent input styling.

**What changes:** Header appearance, footer positioning, field grouping, input/label styling.
**What does NOT change:** Field types, schema structure, form data collection, save/sync logic, step/branch/IO managers' functional behavior.

---

## Change 1: Color-Coded Header

**Current:** Generic edit icon + "Process Properties" title + close button. Same appearance for all element types.

**Proposed:**
- **Left side:** Small colored dot (8px circle, matching element type stroke color) + type name only (e.g., "Process")
- **Right side:** Close button (slightly smaller: `h-4 w-4`)
- **Padding:** `px-3 py-2.5` (compact, down from `p-4`)
- Remove the generic edit SVG icon

**Element type colors for the dot** (from `ELEMENT_COLORS` constant):
- Start → `#10b981` (green)
- End → `#ef4444` (red)
- Process → `#3b82f6` (blue)
- Decision → `#f59e0b` (amber)
- Loop → `#a855f7` (purple)
- Error Handler → `#ea580c` (orange)
- Timer → `#64748b` (slate)
- Subflow → `#06b6d4` (cyan)
- Fork → `#3b82f6` (blue)
- Join → `#3b82f6` (blue)

**Implementation:** The `_updateTitle()` method in `form_builder.js` already sets the title text. Extend it to also set a `data-element-color` attribute or directly style a dot element. The dot is a `<span>` in the header HTML with a dynamic `style="background-color: ..."` set by the controller.

**Files:**
- `app/views/flowcharts/_editor.html.erb` — rewrite header HTML
- `app/javascript/controllers/property_editor/form_builder.js` — update `_updateTitle()` to set dot color

---

## Change 2: Pinned Footer

**Current:** Save/Cancel buttons are inside the scrollable `<div class="flex-1 overflow-y-auto p-4">`, so they scroll out of view.

**Proposed:** Move buttons outside the scrollable area, pinned to the bottom of the sidebar.

**New HTML structure:**
```
sidebar (w-[320px], flex flex-col)
  modalContent (relative h-full flex flex-col)
    header (flex-shrink-0)
    form (flex-1 flex flex-col min-h-0)
      scrollable content (flex-1 overflow-y-auto px-3 py-3)
        formFields container
      pinned footer (flex-shrink-0 border-t border-slate-100 px-3 py-2.5 bg-white)
        Cancel | Save buttons
    step modal container
    branch modal container
```

**Button sizing:** Slightly smaller — `px-2.5 py-1.5 text-xs font-medium rounded-md` (instead of `px-3 py-2 text-sm`).

**Files:**
- `app/views/flowcharts/_editor.html.erb` — restructure sidebar HTML

---

## Change 3: Field Section Separators

**Current:** All fields in a flat list with uniform `space-y-4` spacing.

**Proposed:** The form builder injects a thin separator with an uppercase label before certain well-known field names:

| Before field name | Section label |
|---|---|
| `inputs` | DATA FLOW |
| `description` | DETAILS |
| `errorHandling` | ADVANCED |

**Separator HTML:**
```html
<div class="pt-2 mt-3 border-t border-slate-100">
  <span class="text-[10px] font-medium uppercase tracking-wider text-slate-400">DATA FLOW</span>
</div>
```

Fields above the first separator (label, triggerType, steps, condition, loopType, etc.) are the "primary" fields and have no section header.

**Implementation:** In `form_builder.js` `_buildFormFields()`, check each `fieldName` before building its HTML. If the field name is in the separator map, prepend the separator HTML.

**Files:**
- `app/javascript/controllers/property_editor/form_builder.js` — add separator injection in `_buildFormFields()`

---

## Change 4: Field Styling Consistency

**Current:** Inputs use `border-slate-300 shadow-sm focus:ring-blue-500 focus:border-blue-500`. Labels use `text-sm font-medium`. Field spacing is `mb-4`.

**Proposed:**

**Input class** (in `form_builder.js` `_buildInputHTML`):
```
w-full px-2.5 py-1.5 text-sm border border-slate-200 bg-slate-50 rounded-md
focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500 focus:bg-white
transition-colors
```

Changes from current:
- `border-slate-300` → `border-slate-200` (lighter border)
- Add `bg-slate-50` (inset surface) + `focus:bg-white` (clears on focus)
- `shadow-sm` removed (too heavy for dense panel)
- `focus:ring-blue-500` → `focus:ring-1 focus:ring-indigo-500` (consistent primary, thinner ring)
- `px-3 py-2` → `px-2.5 py-1.5` (slightly more compact)
- Remove `sm:text-sm` (redundant, already `text-sm`)

**Label class:**
- `text-sm font-medium text-slate-700` → `text-xs font-medium text-slate-600`
- Required label: `text-xs font-medium text-slate-900`

**Field spacing:** `mb-4` → `mb-3` (tighter)

**Same input styling applied in:**
- `form_builder.js` — the central `inputClass` constant
- `templates.js` — all input/select/textarea elements in templates
- `step_manager.js` — step-related inputs
- `branch_manager.js` — branch-related inputs (if uses blue focus)

**NOT changed:**
- `io_manager/input_operations.js` — uses `focus:ring-green-500` intentionally (semantic: inputs)
- `io_manager/output_operations.js` — uses `focus:ring-purple-500` intentionally (semantic: outputs/signals)

For these IO manager files, only update the border and background to match (`border-slate-200 bg-slate-50`), keep the green/purple focus rings.

**Files:**
- `app/javascript/controllers/property_editor/form_builder.js`
- `app/javascript/controllers/property_editor/templates.js`
- `app/javascript/controllers/property_editor/step_manager.js`
- `app/javascript/controllers/property_editor/branch_manager.js`
- `app/javascript/controllers/property_editor/io_manager/input_operations.js`
- `app/javascript/controllers/property_editor/io_manager/output_operations.js`

---

## Files Impact Summary

| File | Changes |
|------|---------|
| `app/views/flowcharts/_editor.html.erb` | 1, 2 |
| `app/javascript/controllers/property_editor/form_builder.js` | 1, 3, 4 |
| `app/javascript/controllers/property_editor/templates.js` | 4 |
| `app/javascript/controllers/property_editor/step_manager.js` | 4 |
| `app/javascript/controllers/property_editor/branch_manager.js` | 4 |
| `app/javascript/controllers/property_editor/io_manager/input_operations.js` | 4 (border/bg only) |
| `app/javascript/controllers/property_editor/io_manager/output_operations.js` | 4 (border/bg only) |

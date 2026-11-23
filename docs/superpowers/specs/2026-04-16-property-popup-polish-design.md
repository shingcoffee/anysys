# Property Popup Polish: Modal Consistency & Condition Builder UX

**Date:** 2026-04-16
**Status:** Approved
**Scope:** Visual consistency fixes and condition builder UX improvement in the property editor modals

## Problem

Three areas of the property editor popup are visually inconsistent or hard to use:

1. **Branch modal styling mismatch** -- Uses a different visual language than the step modal (amber header bg, different border radii, different backdrop, different button styles).
2. **Branch condition builder UX** -- The "Field Condition" vs "Query Count" toggle uses tiny `text-[10px]` pill buttons. The field condition inputs are crammed onto one line with no labels. The query count panel lacks clear visual grouping.
3. **Step modal advanced section inconsistency** -- Label styles and input sizing don't match the rest of the modal.

## Design

### Section 1: Branch Modal Shell Alignment

Align the branch modal's outer structure to match the step modal.

| Element | Current (branch) | New (matching step) |
|---|---|---|
| Backdrop | `bg-black/50` | `bg-slate-900/40 backdrop-blur-[2px]` |
| Container | `rounded-lg shadow-xl ring-1 ring-slate-200` | `rounded-xl shadow-2xl ring-1 ring-black/5` |
| Header | `bg-amber-50 border-b border-slate-200` | White bg, `border-b border-slate-100` |
| Header icon | None | `w-7 h-7 rounded-lg bg-amber-50` with amber fork/branch SVG |
| Header title | `text-sm font-medium` | `text-sm font-semibold` |
| Close button hover | `hover:bg-amber-100` | `hover:bg-slate-100` with `p-1.5 rounded-lg` |
| Footer | `bg-slate-50 border-t border-slate-200` | `bg-slate-50/50 border-t border-slate-100` |
| Cancel button | `rounded-md` no shadow | `rounded-lg shadow-sm` matching step modal |
| Submit button | `bg-indigo-600 rounded-md` | `bg-indigo-600 rounded-lg shadow-sm shadow-indigo-200` + plus icon |

The amber color identity for decision elements is preserved in the header icon badge only (`bg-amber-50` with amber SVG).

### Section 2: Condition Builder Redesign

Replace the cramped inline condition row with a stacked layout and proper segmented control.

#### Condition Type Toggle

Replace the tiny `text-[10px] font-bold` pill buttons with a segmented control matching the property editor tab bar:

- Container: `flex gap-1 p-1 bg-slate-100 rounded-lg`
- Active state: `bg-white text-slate-900 shadow-sm ring-1 ring-black/5 rounded-md`
- Inactive state: `text-slate-500 hover:text-slate-700 hover:bg-white/50 rounded-md`
- Font: `text-xs font-medium` (up from `text-[10px] font-bold`)

#### Field Condition Panel

Three fully stacked fields replacing the current inline 3-input row:

- **Left Operand** -- full-width text input, `font-mono` for code values
- **Operator** -- full-width select dropdown
- **Right Operand** -- full-width text input, `font-mono` for code values

Each field gets a label: `text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase`

Input styling unified to: `w-full px-3 py-2 text-sm border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400`

All inputs use amber focus rings to match the branch/decision color identity.

#### Query Count Panel

Same stacked treatment:

- **Entity** selector: full label, same input styling as above
- **WHERE filters**: unchanged layout (already decent), but unify input/select styling to match
- **Count operator**: own labeled row, full-width select
- **Count value**: own labeled row, full-width number input

All focus rings use amber (`focus:ring-amber-500/20 focus:border-amber-400`).

#### branch_manager.js Update

Two methods need class updates:

1. **`switchBranchConditionType` handler** -- swap the new segmented control classes:
   - Active: remove `text-slate-500`, add `bg-white text-slate-900 shadow-sm ring-1 ring-black/5`
   - Inactive: remove `bg-white text-slate-900 shadow-sm ring-1 ring-black/5`, add `text-slate-500`

2. **`openBranchModal` reset** -- the modal reset logic currently sets the "Field Condition" button to `bg-amber-200 text-amber-800` and the "Query Count" button to `bg-gray-100 text-gray-500`. Update to use the same new active/inactive classes as above.

(Both replace the old `bg-amber-200 text-amber-800` / `bg-gray-100 text-gray-500` pattern.)

### Section 3: Step Modal Advanced Section Cleanup

Unify styles inside the collapsible "Advanced" accordion to match the rest of the step modal.

**Labels** (4 fields: retry count, retry backoff, timeout, guard condition):
- Current: `text-xs font-medium text-slate-600 mb-1`
- New: `text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase`

**Inputs** (all 4 fields):
- Current: `px-3 py-1.5 text-sm border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500`
- New: `px-3 py-2 text-sm border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400`

**Helper text**: stays as `text-[10px] text-slate-400` (already consistent).

**Accordion wrapper**: no changes -- `border border-slate-200 rounded-md` is fine.

## Files Changed

| File | Changes |
|---|---|
| `app/javascript/controllers/property_editor/templates.js` | Branch modal template, condition builder HTML, step modal advanced labels/inputs |
| `app/javascript/controllers/property_editor/branch_manager.js` | Condition type toggle class swapping logic |

## Files NOT Changed

- `step_manager.js` -- no changes needed
- `form_builder.js` -- no changes needed
- `_editor.html.erb` -- no changes needed
- `property_editor_controller.js` -- no changes needed

## Testing

- Open property editor for a Decision element, verify branch modal matches step modal aesthetic
- Test condition type toggle (Field Condition / Query Count) switches correctly with new segmented control
- Verify field condition stacked layout with all operator options
- Verify query count panel layout and entity selection flow
- Open property editor for a Process element, add a step, expand Advanced section, verify label/input styling matches
- Verify no regressions in step modal functionality (add step, keyword params, config fields)

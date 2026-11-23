# Property Editor Refinements Design

## Overview

Three changes to the flowchart editor page:
1. Move minimap from bottom-right to bottom-left
2. Refine property editor sidebar with narrower width and "Refined Minimal" aesthetic
3. Fix confirmed bugs in the property editor

## Task A: Minimap Relocation

**File:** `app/views/flowcharts/_editor.html.erb` (line ~244)

Change `right-2` to `left-2` on the minimap container div. No JS or manager changes needed — `MinimapManager` doesn't reference positioning.

## Task B: Property Editor Refactor

### Width

| Property | Before | After |
|----------|--------|-------|
| Default width | 500px | 420px |
| Min width | 400px | 360px |
| Max width | 700px | 520px |

Update in `_editor.html.erb`: inline `style="width: 420px;"` and `data-panel-resize-*-value` attributes.

### Refined Minimal Style

Direction: clean, tight spacing, uppercase micro-labels, subtle dividers. No structural HTML changes.

**Header** (`_editor.html.erb`):
- Padding: `px-5 pt-4 pb-3` -> `px-4 pt-3 pb-2`
- Type icon: `w-9 h-9` -> `w-8 h-8`

**Tab bar** (`_editor.html.erb`):
- Padding: `px-5 pb-3` -> `px-4 pb-2`

**Tab panes** (`_editor.html.erb`):
- Padding: `px-5 py-4` -> `px-4 py-3`
- Field spacing: `space-y-4` -> `space-y-3`

**Footer** (`_editor.html.erb`):
- Padding: `px-5 py-3.5` -> `px-4 py-3`

**Form labels** (`form_builder.js`):
- Add `uppercase text-[10px] tracking-wide` classes to field labels for micro-label style
- Update any label classes in `templates.js` to match

## Task C: Bug Fixes

### Fix 1: Sync timeout not cleared on disconnect

**File:** `app/javascript/controllers/property_editor_controller.js`
**Location:** `disconnect()` method (~line 80)

Add `if (this._syncTimeout) clearTimeout(this._syncTimeout)` before existing cleanup.

### Fix 2: Async race in query count entity change

**File:** `app/javascript/controllers/property_editor/branch_manager.js`
**Location:** `onQueryCountEntityChange()` (~line 136)

Add a request counter. Increment on each call, capture the value before `await`, and only apply the response if the counter still matches (i.e., no newer request was made).

```javascript
// In constructor or class field:
this._entityFetchId = 0

// In onQueryCountEntityChange:
const fetchId = ++this._entityFetchId
// ... await fetch ...
if (fetchId !== this._entityFetchId) return  // stale response
```

### Fix 3: Canvas elementLayer null guards

**Files:** `branch_manager.js`, `property_editor_controller.js`

Add optional chaining (`?.`) before `querySelector` calls on `canvas.elementLayer` in:
- `_removeBranchElementFromCanvas()`
- `_refreshDecisionElement()`
- `syncJoinBranches()` in main controller

## Files Changed

- `app/views/flowcharts/_editor.html.erb` — minimap position, sidebar width/padding
- `app/javascript/controllers/property_editor/form_builder.js` — label styling
- `app/javascript/controllers/property_editor/templates.js` — label styling consistency
- `app/javascript/controllers/property_editor_controller.js` — timeout cleanup, elementLayer guard
- `app/javascript/controllers/property_editor/branch_manager.js` — async race fix, elementLayer guard

## Out of Scope

- No structural HTML changes to the sidebar
- No new ViewComponents
- Tab manager listener cleanup (not a real leak in modern browsers)
- Unsaved changes cache behavior (by-design feature)

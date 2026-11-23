# Canvas Editor Bug Fixes & UX Improvements

**Date:** 2026-03-26
**Scope:** 4 bugs + 6 improvements in the flowchart canvas editor
**Approach:** Targeted fixes + focused UX enhancements

---

## Bug Fixes

### Bug A: Drag state cleanup incomplete

**Severity:** Medium
**File:** `app/javascript/flowchart/drag_handler.js:208-220`
**Root cause:** `_cleanupDragState()` doesn't reset `dropTargetElement`, `dragOffset`, or hide the drop-side indicator. This can leave ghost visual artifacts (drop indicator lines) on the canvas after a drag finishes.

**Fix:** Add to `_cleanupDragState()`:
```js
this.dropTargetElement = null
this.dragOffset = { x: 0, y: 0 }
this._hideDropSideIndicator()
```

### Bug B: Hardcoded position constants in palette

**Severity:** Medium
**File:** `app/javascript/controllers/element_palette_controller.js:141-164`
**Root cause:** Double-click to add uses hardcoded `ELEMENT_SPACING = 50`, `ELEMENT_HEIGHT = 45`, `GRID = 15` instead of importing from `flowchart/constants`. These diverge from canvas constants, causing misaligned element placement.

**Fix:** Import `DEFAULT_ELEMENT_SPACING`, `DEFAULT_ELEMENT_HEIGHT`, `GRID_SIZE` from `flowchart/constants` and use them in `_calculateOptimalPosition()`.

### Bug C: Silent start element rejection

**Severity:** Low-Medium
**File:** `app/javascript/flowchart/canvas.js:806-810`
**Root cause:** Adding a second Start element silently returns `null` with `console.warn`. No UI feedback.

**Fix:** After the `console.warn`, dispatch a custom event or call the toast system (Improvement 1) to show "Only one Start element allowed per flowchart". Same for `addElementRelativeTo()`.

### Bug D: Self-connection prevention missing in createConnection

**Severity:** Medium
**File:** `app/javascript/flowchart/connection_manager.js:45-51`
**Root cause:** `createConnection()` checks for duplicate connections but not self-connections (`A→A`). All current call sites have upstream guards, but the method itself is unprotected.

**Fix:** Add `if (fromElement.id === toElement.id) return null` at the start of `createConnection()`.

---

## Improvement 1: Toast Notification System

**Purpose:** Provide user feedback for blocked actions, validation errors, and status updates.

**Implementation:**
- Add a toast container div in `_editor.html.erb`, absolute positioned at the top-center of the canvas area
- Add `showToast(message, type)` method to `flowchart_canvas_controller.js`
- Types: `info` (blue), `warning` (amber), `error` (red) with TailwindCSS styling
- Auto-dismiss after 3 seconds with fade-out transition
- Used for: "Only one Start element allowed", connection validation failures, save confirmations

**HTML structure:**
```html
<div data-flowchart-canvas-target="toastContainer"
     class="absolute top-4 left-1/2 -translate-x-1/2 z-40 pointer-events-none">
</div>
```

**Toast element (created dynamically):**
```html
<div class="pointer-events-auto px-4 py-2 rounded-lg shadow-lg text-sm font-medium
            transition-all duration-300 ease-in-out">
  <message text>
</div>
```

**Files:**
- `app/views/flowcharts/_editor.html.erb` — add toast container
- `app/javascript/controllers/flowchart_canvas_controller.js` — add `showToast()` method
- `app/javascript/flowchart/canvas.js` — emit toast events for blocked actions

---

## Improvement 2: Connection Handle Discoverability

**Purpose:** Make it obvious that elements can be connected by always showing connection handles on selected elements.

**Implementation:**
- When an element is selected (single-click), show its 4 connection handles (top, bottom, left, right) permanently
- When element is deselected, hide handles
- Hover behavior on unselected elements remains unchanged
- Multi-select: show handles on all selected elements

**Change location:** In `selection_manager.js`, the `_selectElement()` and `_deselectElement()` methods should call `showConnectionHandles()` / `hideConnectionHandles()` on the affected element(s).

**Files:**
- `app/javascript/flowchart/selection_manager.js`

---

## Improvement 3: Keyboard Shortcut Reference Panel

**Purpose:** Make keyboard shortcuts discoverable. Currently undocumented.

**Implementation:**
- Press `?` to toggle a semi-transparent overlay panel in the bottom-left of the canvas
- Panel shows all keyboard shortcuts in a compact 2-column layout
- Dismiss with `?` again or `Escape`
- Panel implemented as a hidden div in `_editor.html.erb`
- Toggle handler added to `canvas.js` `_handleKeyDown()`

**Shortcuts to display:**

| Key | Action |
|-----|--------|
| S / E / P / D / L / H / T | Add element by type |
| Ctrl+Z / Ctrl+Y | Undo / Redo |
| Ctrl+F | Search |
| Delete / Backspace | Delete selected |
| Escape | Deselect / Close panel |
| Space + Drag | Pan canvas |
| Ctrl + Scroll | Zoom |
| Scroll | Pan |
| ? | Toggle this panel |

**Files:**
- `app/views/flowcharts/_editor.html.erb` — add shortcut panel div
- `app/javascript/flowchart/canvas.js` — add `?` key handler and toggle logic

---

## Improvement 4: Inline Label Editing

**Purpose:** Edit element labels directly on the canvas without opening the property sidebar. Faster workflow.

**Implementation:**
- Double-click on an element's label text (the `<text>` SVG element) starts inline editing
- Double-click on the element body (but not label) opens the property sidebar as before
- An HTML `<input>` is absolutely positioned over the SVG label using `getBoundingClientRect()` on the text element
- Enter or blur: save the label, re-render the element
- Escape: cancel editing, restore original label
- The input matches the label's font size and is centered on the text

**Detection logic in `_handleDoubleClick()`:**
```
1. Check if click target is a <text> element inside an element group
2. If yes → start inline label edit
3. If no → open property sidebar (existing behavior)
```

**Files:**
- `app/javascript/flowchart/canvas.js` — modify `_handleDoubleClick()`, add `_startInlineLabelEdit()`, `_endInlineLabelEdit()`, `_cancelInlineLabelEdit()`

---

## Improvement 5: Canvas Right-Click Context Menu

**Purpose:** Quick access to common actions without toolbar navigation.

**Implementation:**
- Right-click shows a context menu at cursor position
- Menu items vary based on click target
- Click outside menu or Escape closes it
- Menu is an absolutely-positioned div in `_editor.html.erb`

**Menu items by target:**

**Right-click on empty canvas:**
| Item | Action |
|------|--------|
| Add Process | Add process element at cursor position |
| Add Decision | Add decision element at cursor position |
| Add End | Add end element at cursor position |
| --- | separator |
| Paste | Paste from clipboard (if available) |

**Right-click on element:**
| Item | Action |
|------|--------|
| Edit Properties | Open property sidebar |
| Duplicate | Duplicate element |
| Delete | Delete element |
| --- | separator |
| Connect From Here | Start connection draw from this element |

**Right-click on connection:**
| Item | Action |
|------|--------|
| Delete Connection | Remove the connection |

**Files:**
- `app/views/flowcharts/_editor.html.erb` — add context menu container div
- `app/javascript/flowchart/canvas.js` — add `_handleContextMenu()`, `_showContextMenu()`, `_hideContextMenu()`, `_executeContextAction()`

---

## Improvement 6: Minimap Visible by Default

**Purpose:** Spatial awareness when flowchart exceeds viewport.

**Implementation:**
- Remove the `hidden` class from the minimap container in `_editor.html.erb`
- In `flowchart_canvas_controller.js`, initialize minimap as visible in `connect()` method

**Files:**
- `app/views/flowcharts/_editor.html.erb`
- `app/javascript/controllers/flowchart_canvas_controller.js`

---

## Files Impact Summary

| File | Changes |
|------|---------|
| `app/javascript/flowchart/drag_handler.js` | Bug A |
| `app/javascript/controllers/element_palette_controller.js` | Bug B |
| `app/javascript/flowchart/canvas.js` | Bugs C, Improvements 3, 4, 5 |
| `app/javascript/flowchart/connection_manager.js` | Bug D |
| `app/javascript/flowchart/selection_manager.js` | Improvement 2 |
| `app/javascript/controllers/flowchart_canvas_controller.js` | Improvements 1, 6 |
| `app/views/flowcharts/_editor.html.erb` | Improvements 1, 3, 5, 6 |

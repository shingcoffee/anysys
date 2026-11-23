# Flowchart Editor Toolbar Redesign

## Problem

The flowchart editor toolbar has 17 interactive elements in a single flat row with no logical grouping. It's visually cluttered and hard to navigate.

## Design

### Layout Structure

Two-row toolbar:

```
Row 1: [Save*] [Undo] [Redo]  |  Flowchart Name  |  [-] 100% [+] [Fit]
Row 2: [View v] [Tools v] [Export v]
```

**Row 1 — Primary actions and navigation:**
- Left: Save (with dot indicator), Undo, Redo
- Center: Flowchart name (link to detail page)
- Right: Zoom controls

**Row 2 — Dropdown menus:**
- Left-aligned: View, Tools, Export dropdowns

Rows separated by a subtle `border-b border-gray-100` on row 1. Row 2 uses tighter padding (`py-1.5`) for a compact secondary bar feel.

### Group 1: Primary Actions (icon-only)

| Button | Action | Controller |
|--------|--------|------------|
| Save | `toolbar#save` | toolbar |
| Undo | `toolbar#undo` | toolbar |
| Redo | `toolbar#redo` | toolbar |

**Save button states** via a small dot indicator (absolute-positioned `w-2 h-2 rounded-full` top-right):
- Default: no dot
- Unsaved changes: amber dot (`bg-amber-500`)
- Saving: blue pulsing dot (`bg-blue-500 animate-pulse`)
- Saved: green dot (`bg-green-500`), fades after 3s
- Error: red dot (`bg-red-500`), fades after 5s

Undo/Redo retain existing disabled states (`disabled:opacity-50 disabled:cursor-not-allowed`).

### Group 2: Dropdown Menus

Each uses the existing `dropdown` Stimulus controller.

All dropdown menu items chain `click->dropdown#close` as a second action to dismiss the menu after selection (e.g., `data-action="click->flowchart-canvas#validate click->dropdown#close"`).

**View dropdown:**
| Icon | Label | Action |
|------|-------|--------|
| Checkmark circle | Validate | `flowchart-canvas#validate` |
| Play circle | Run Test | `flowchart-canvas#toggleTestPanel` |
| Clock | History | `flowchart-canvas#toggleVersionPanel` |
| List | Elements | `flowchart-canvas#toggleElementsPanel` |

The Validate item includes the validation badge (`data-flowchart-canvas-target="validationBadge"`) inline — a small `rounded-full text-xs font-medium bg-red-100 text-red-800` badge showing error count, hidden by default. This preserves the existing `validationBadgeTarget` used by `flowchart_canvas_controller.js` to display validation results.

**Tools dropdown:**
| Icon | Label | Action |
|------|-------|--------|
| Grid layout | Auto Layout | `toolbar#autoLayout` |
| Lightning | Connection Routing | `toolbar#cycleConnectionRouting` |
| Document | Generate Docs | `flowchart-canvas#generateDocs` |
| --- divider --- | | |
| Trash (red) | Clear Canvas | `toolbar#clear` |

**Export dropdown** (same items, menu width updated to `w-48` for consistency):
| Icon | Label | Action |
|------|-------|--------|
| File | Export as SVG | `toolbar#exportSVG` |
| Image | Export as PNG | `toolbar#exportPNG` |

### Group 3: Flowchart Name

Link to detail page, centered. Same as current: `text-lg font-medium text-gray-900 hover:text-indigo-600`.

### Group 4: Zoom Controls (icon-only)

| Button | Action | Controller |
|--------|--------|------------|
| Zoom out (magnifier −) | `toolbar#zoomOut` | toolbar |
| Percentage display | — (read-only `text-sm font-mono w-12`) | toolbar target |
| Zoom in (magnifier +) | `toolbar#zoomIn` | toolbar |
| Fit to content (expand arrows) | `toolbar#fitToContent` | toolbar |

### Styling Details

**Toolbar container (outer wrapper):**
- `bg-white border-b border-gray-200 flex-shrink-0`

**Row 1 (primary):**
- `px-4 py-2 flex items-center justify-between border-b border-gray-100`

**Row 2 (secondary):**
- `px-4 py-1.5 flex items-center space-x-2`

**Icon-only buttons:**
- `p-2 rounded-md border border-gray-300 shadow-sm text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors`
- Save override: `bg-indigo-600 text-white hover:bg-indigo-700 border-transparent`

**Dropdown trigger buttons:**
- `px-2.5 py-2 rounded-md border border-gray-300 shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 transition-colors`
- Icon + label + chevron SVG

**Dropdown menus:**
- `w-48 rounded-md shadow-lg bg-white ring-1 ring-black/5 z-10`
- Items: `px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center`
- Destructive items: `text-red-600 hover:bg-red-50` with `border-t border-gray-100` separator above

**Dividers between groups:**
- `w-px h-6 bg-gray-200 mx-2`

### Styling Details (continued)

**Row padding:** Row 1 uses `py-2` (reduced from current `py-3`). Row 2 uses `py-1.5` for a compact secondary bar. The two rows together are slightly taller than the original single row, but provide much better organization.

**Save dot fade mechanism:** The dot visibility is controlled by toggling a `hidden` class. The existing `setTimeout` in `_showSaveSuccess` (3s) and `_showSaveError` (5s) already handle timing — the dot simply gets hidden when the timer fires. No CSS transitions needed.

### Component Structure

Implement as inline ERB in `app/views/flowcharts/_editor.html.erb` (replacing the existing toolbar section, lines 11-197). While the project convention is ViewComponent for views, the toolbar is tightly coupled to multiple controller targets (`toolbar`, `flowchart-canvas`, `dropdown`) and is not reused elsewhere, making inline ERB the pragmatic choice here.

### Changes to toolbar_controller.js

**Save status management** — Replace text-based status with dot indicator:
- Remove `saveStatus` target
- Add `saveDot` target (the status dot element)
- Update `_updateSaveStatus`, `_showSaving`, `_showSaveSuccess`, `_showSaveError` to toggle dot color classes and `hidden` class

**Dead code cleanup:**
- Remove `nameInput` from targets array (no corresponding HTML element exists)
- Remove `updateName()` method and `_saveNameChange()` method (unused dead code)
- Remove `_clearDebounceTimer()` and `nameInputDebounceTimer` (only used by removed methods)

**No other JS changes needed.** All action methods already exist. Dropdown behavior handled by existing `dropdown` controller.

### Changes to flowchart_canvas_controller.js

The `unsavedIndicator` target (`data-flowchart-canvas-target="unsavedIndicator"`) is removed from the template. The canvas controller's `_updateUnsavedIndicator()` method uses a `hasUnsavedIndicatorTarget` guard, so it will safely no-op. The toolbar already listens for `flowchartChanged` events to manage its own save dot state, so no functional behavior is lost. Optionally remove `_updateUnsavedIndicator()` and the `unsavedIndicator` target declaration for cleanliness.

### Removed Elements

- Save status text ("Ready" / "Unsaved changes" / etc.) — replaced by dot indicator
- Separate "Unsaved changes" amber text with pulse dot — replaced by save button dot
- Text labels on primary action buttons (Save, Undo, Redo) — icon-only with tooltips
- Clear button from prominent position — moved into Tools dropdown

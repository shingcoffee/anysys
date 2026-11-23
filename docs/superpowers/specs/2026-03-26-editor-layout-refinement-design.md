# Flowchart Editor Layout Refinement

**Date:** 2026-03-26
**Scope:** 5 layout changes to make the flowchart editor more professional and easier to use
**Style Reference:** Lucidchart/draw.io three-panel layout with modern refinements

---

## Change 1: Streamlined Toolbar

**Current:** Save button + Undo/Redo + 3 dropdown menus (View, Tools, Export) + flowchart name (center) + zoom controls (right). Important actions (Validate, Test) hidden behind dropdown clicks.

**Proposed layout (left to right):**
1. **Left pill group** (`bg-gray-100 rounded-lg p-0.5`): Save (indigo button) | Undo icon | Redo icon
2. **Divider** (`w-px h-5 bg-gray-200`)
3. **Center:** Flowchart name link (unchanged)
4. **Divider**
5. **Zoom pill group:** `-` | percentage | `+`
6. **Actions pill group:** Validate (checkmark icon) | Test (play icon) | Overflow `...` (ellipsis icon)

**Overflow menu (triggered by `...`):**
- Auto Layout
- Connection Routing
- Generate Docs
- separator
- Export as SVG
- Export as PNG
- separator
- Clear Canvas (red/danger styling)

**Removed:** View dropdown, Tools dropdown, Export dropdown — all items redistributed.

**Actions promoted to top-level icons:**
- Validate (from View dropdown)
- Test Runner (from View dropdown)

**Actions moved to overflow:**
- History (from View dropdown) — accessible via overflow or bottom panel tab
- Elements list (from View dropdown) — accessible via bottom panel tab
- Auto Layout, Connection Routing, Generate Docs (from Tools dropdown)
- Export SVG/PNG (from Export dropdown)
- Clear Canvas (from Tools dropdown)

**Files:**
- `app/views/flowcharts/_editor.html.erb` — rewrite toolbar section
- `app/javascript/controllers/toolbar_controller.js` — update targets and actions for new layout

---

## Change 2: Narrower Left Sidebar (140px)

**Current:** 256px (`w-64`), 2-column grid of element tiles, separate Flows section with search.

**Proposed:**
- **Width:** 140px (`w-[140px]`)
- **Background:** `bg-gray-50` (subtle separation from canvas)
- **Top:** Unified search bar (`bg-white border rounded-lg`) that filters both elements and flows
- **Elements section:**
  - Header: `ELEMENTS` in uppercase, small text, gray
  - Single-column list of draggable rows
  - Each row: 16px colored shape icon + label text, `bg-white border border-gray-200 rounded px-2 py-1`
  - Element order: Start, Process, Decision, End, Loop, Error Handler, Timer
- **Flows section:**
  - Header: `FLOWS` in uppercase, small text, gray
  - Same single-column list format as elements
  - Each row: flow icon + name

**Element palette ViewComponents unchanged** — the component rendering stays the same, only the container layout CSS changes from `grid grid-cols-2` to `flex flex-col`.

**Files:**
- `app/views/flowcharts/_editor.html.erb` — change sidebar width, restructure element palette layout
- `app/components/flowchart_elements/base_element_component.rb` — adjust template for single-column row layout (icon + label horizontal instead of vertical)
- `app/components/flowchart_elements/base_element_component.html.erb` — update HTML from vertical tile to horizontal row

---

## Change 3: Narrower Right Sidebar (320px)

**Current:** 448px (`w-[448px]`), hidden by default.

**Proposed:**
- **Width:** 320px (`w-[320px]`)
- **Header:** Element type name (e.g., "Process") + close button. Clean border-b.
- **Field labels:** Uppercase section labels (`text-[10px] font-medium uppercase tracking-wider text-gray-500`)
- **Footer:** Save/Cancel buttons pinned to bottom in a `border-t` bar, always visible regardless of scroll position
- **Behavior:** Still hidden by default, slides in on element double-click or context menu "Edit Properties"

**Files:**
- `app/views/flowcharts/_editor.html.erb` — change sidebar width class from `w-[448px]` to `w-[320px]`

---

## Change 4: Tabbed Bottom Panel

**Current:** 4 separate panels (Validation, Test Runner, History, Elements) each independently toggled from the View dropdown or toolbar. Each has its own show/hide state and close button.

**Proposed:**
- **Single container div** at the bottom of the canvas area
- **Tab bar** at the top: `Problems` | `Test Runner` | `History` | `Elements`
- Active tab: indigo text + 2px bottom border (`border-b-2 border-indigo-500`)
- Inactive tabs: gray text, hover highlight
- **Single close button** at the right end of the tab bar
- **Content area** below tabs shows the active tab's content
- **Panel state:**
  - Hidden by default
  - Opens when any tab is activated (Validate button, Test button, etc.)
  - Remembers last active tab
  - Close button hides entire panel
- **Max height:** `max-h-[40%]` (unchanged)

**Tab content mapping:**
- Problems tab → existing validation panel content
- Test Runner tab → existing test panel content
- History tab → existing version panel content
- Elements tab → existing elements panel content

**How tabs are activated:**
- Validate toolbar icon → opens panel, switches to Problems tab
- Test toolbar icon → opens panel, switches to Test Runner tab
- Overflow menu "History" → opens panel, switches to History tab (if we add it to overflow)
- Direct tab click → switches tab (panel already open)

**Files:**
- `app/views/flowcharts/_editor.html.erb` — replace 4 separate panel divs with 1 tabbed container
- `app/javascript/controllers/flowchart_canvas_controller.js` — refactor panel toggle methods into tab switching logic

---

## Change 5: Canvas Dot Grid Background

**Current:** Line grid drawn via SVG `<line>` elements in `canvas.js` `_drawGrid()`.

**Proposed:**
- Replace line grid with dot grid using SVG `<pattern>` and `<circle>` elements
- **Dot specs:** `r=1`, `fill: #cbd5e1` (gray-300), centered in each grid cell
- **Pattern size:** Same as current `GRID_SIZE` (15px)
- **Implementation:** Define `<defs><pattern>` in SVG, apply as `fill` on a full-canvas `<rect>`
- Lighter, less visually noisy, modern aesthetic

**Files:**
- `app/javascript/flowchart/canvas.js` — replace `_drawGrid()` method

---

## Files Impact Summary

| File | Changes |
|------|---------|
| `app/views/flowcharts/_editor.html.erb` | 1, 2, 3, 4 |
| `app/javascript/controllers/toolbar_controller.js` | 1 |
| `app/javascript/controllers/flowchart_canvas_controller.js` | 4 |
| `app/javascript/flowchart/canvas.js` | 5 |
| `app/components/flowchart_elements/base_element_component.rb` | 2 |
| `app/components/flowchart_elements/base_element_component.html.erb` | 2 |

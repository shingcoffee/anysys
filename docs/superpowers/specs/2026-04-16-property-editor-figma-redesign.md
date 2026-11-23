# Property Editor Figma-Style Full Redesign

## Overview

Full redesign of the flowchart editor's property popup (sidebar, modals, item lists, I/O panel) to achieve a Figma-style dense, polished, and usable interface. This covers aesthetics and usability across all property editor surfaces: sidebar structure, form fields, step items/modal, branch items/modal, I/O panel, join panel, and error handling.

Scope includes extracting reusable ViewComponents, consolidating HTML templates, and separating canvas operations from form managers.

## Design Principles

- **Figma-style density**: compact panels with clear sections, icon-heavy, efficient use of space
- **Both aesthetics and usability**: polish the look AND improve interaction patterns
- **No backward compatibility concerns**: treat as a fresh implementation per AGENTS.md
- **ViewComponent encapsulation**: extract reusable UI patterns per AGENTS.md guidelines

---

## Section 1: Visual Language

### Spacing Scale

| Context | Before | After |
|---------|--------|-------|
| Section gap | `space-y-3` / `space-y-4` | `space-y-2` (8px) |
| Field gap within section | `space-y-3` | `space-y-1.5` (6px) |
| Item inner padding | `px-3 py-2` | `px-2 py-1.5` |
| Modal body padding | `p-4` | `p-3` |

### Typography

| Element | Before | After |
|---------|--------|-------|
| Labels | `text-xs font-medium text-slate-500 uppercase tracking-wide` | `text-[11px] font-medium text-slate-500` (no uppercase, no tracking) |
| Inputs | `text-sm` (14px) | `text-xs` (12px) |
| Section headers | various | `text-xs font-semibold text-slate-700` |
| Helper text | `text-[10px] text-slate-400` | `text-[10px] text-slate-400` (unchanged) |

### Inputs

- Height: `py-1.5` (down from `py-2`)
- Border: `border border-slate-200 rounded-md` (not `rounded-lg`)
- Focus ring: single color per context (indigo for step, amber for branch, slate for sidebar)
- No `shadow-sm` on inputs

### Item Cards (steps, branches, I/O items)

- No background color fills (remove amber/green/blue backgrounds)
- Left accent border: `border-l-2 border-{color}-400` for type identification
- Hover: `hover:bg-slate-50`
- Padding: `px-2.5 py-1.5`

### Buttons

| Type | Classes |
|------|---------|
| Primary | `bg-indigo-600 text-white text-xs py-1.5 px-3 rounded-md` |
| Secondary | `text-xs text-slate-600 bg-white border border-slate-200 rounded-md py-1.5 px-3` |
| Inline add | `text-[11px] text-indigo-600 hover:text-indigo-700` with `+` icon, no border |
| Remove (icon) | `text-slate-300 hover:text-red-500`, visible on hover only |

### Empty States

Consistent pattern everywhere:
```
border border-dashed border-slate-200 rounded-md py-3 text-center text-[11px] text-slate-400
```
Centered icon + message, muted colors.

### Required Field Indicator

Red dot `text-red-400` instead of asterisk `*`.

---

## Section 2: Sidebar Structure & Header

### Sidebar Container

- Width: 420px default (360-520 range) — unchanged
- Shadow: `shadow-lg` (down from `shadow-2xl`)
- Border: `border-l border-slate-200` — unchanged

### Header

- Type indicator: `w-6 h-6 rounded-lg` (down from `w-8 h-8 rounded-xl`)
- Title + type on same line: `[icon] [Title] . [Type]`
  - Title: `text-sm font-semibold text-slate-900 truncate`
  - Type: `text-[10px] text-slate-400 font-medium` inline after title, separated by ` . `
- Close button: `w-6 h-6`
- Header padding: `px-3 pt-2.5 pb-1.5`

### Tab Bar

- Segmented control stays, but slimmer
- Tab button: `py-1` (down from `py-1.5`), `text-[11px]` (down from `text-xs`)
- Tab bar padding: `px-3 pb-1.5`
- Badges inline in label text: `Steps (2)` as single text node, not separate span

### Tab Panes

- Padding: `px-3 py-2` (down from `px-4 py-3`)
- Advanced tab: 2-column grid with `gap-2` (down from `gap-3`)

### Footer

- Padding: `px-3 py-2` (down from `px-4 py-3`)
- Buttons: `text-xs py-1.5 px-3` (down from `text-sm py-2 px-4/px-5`)
- No icon on Save button — text only: "Save" and "Cancel"
- No `shadow-sm shadow-indigo-200` on Save

---

## Section 3: Form Fields (General / I/O / Advanced)

### Standard Fields (text, textarea, number, select)

- Label-input gap: `mb-1` (down from `mb-1.5`)
- Remove `transition-all duration-150` from inputs
- Select: custom chevron, `rounded-md`
- Textarea: `rows="2"`, `resize-none`
- Required: red dot instead of asterisk

### I/O Panel Redesign

Two-column layout: `grid grid-cols-2 gap-3`

**Left column — Inputs:**
- Section header: `Inputs` with count + inline `+` add button
- Items: compact rows `[value text] [x]`
- Inherited inputs: italic text + `(inherited)` in `text-slate-400`, no remove button, no blue background
- Add new: clicking `+` appends inline select at bottom, selecting a value converts it to a static text row
- "all params" displayed as `text-[11px] font-medium text-indigo-600`

**Right column — Outputs:**
- Same pattern as inputs

**Var mappings (Start subflow):**
- Compact key-value rows: `[key dropdown] -> [value input]` on one line

**Signal wiring / Data mappings (End subflow):**
- Same compact key-value pattern

### Error Handling Redesign

Remove the red `bg-red-50` box wrapper. Replace with:
- "On Failure" as a standard select field (same style as all other fields)
- "Error Output Field" appears conditionally below — no special color, no box, just another field

### Conditional Visibility

Keep `visibleWhen` logic. Add subtle transition: `transition-all duration-150` with `overflow-hidden` on the wrapper div.

---

## Section 4: Step Items & Step Modal

### Step Items List

Replace cards with compact single-line rows:
- Separator: `border-b border-slate-100` between rows, no card borders
- Layout: `[drag handle] [color dot] [action label] [sub-option breadcrumb] [...] [remove]`
  - Drag handle: `w-3 h-3` grip icon, `text-slate-300 hover:text-slate-500`
  - Color dot: `w-2 h-2 rounded-full bg-{color}-500` — replaces 24px icon box
  - Action label: `text-xs font-medium text-slate-800`
  - Sub-option path: `text-[11px] text-slate-400` separated by `/` — plain text, not badge pills
  - Remove: `text-slate-300 hover:text-red-500`, visible on row hover only
- Click to expand: row expands with `pl-6` indent (past drag handle + dot)
  - Expanded state indicated by `bg-slate-50` background
  - No expand/collapse chevron — entire row is clickable
  - Config fields: same compact field style as sidebar
  - Description: editable `text-[11px]` textarea
  - Keyword params: comma-separated inline tags with `x` to remove, `+` to add

### Step Modal

- Size: `max-w-sm` (down from `max-w-md`)
- Header: icon + title, `px-4 py-2.5`
- Cascading dropdowns: `text-xs` inputs, `space-y-2` between levels
- Keyword parameters: single comma-separated input instead of individual rows with add/remove buttons
- Advanced section: 2-column grid inside collapsible
  - Row 1: `[Retry Count] [Retry Backoff]`
  - Row 2: `[Timeout] [Guard Condition]`
- Description: bottom, `rows="2"`
- Footer: `px-4 py-2.5`, compact buttons

---

## Section 5: Branch Items & Branch Modal

### Branch Items List

Same compact row pattern as step items:
- Layout: `[color dot] [branch name] [condition summary] [...] [remove]`
  - Color dot: `w-2 h-2 rounded-full bg-amber-500`
  - Branch name: `text-xs font-medium text-slate-800`
  - Label (if different): `text-[11px] text-slate-400` after name, separated by `·`
  - Condition summary: `text-[10px] font-mono text-slate-400` inline — e.g., `ctx[:status] == "active"` or `Count Orders > 0`. No colored badge pills.
  - Remove: hover-reveal pattern
- Click to expand: description + full condition details with edit affordance
- No drag handle — branch order determined by canvas port positions
- Rows separated by `border-b border-slate-100`

Quick-add stays: dropdown + "Add" button inline at list bottom.

### Branch Modal

- Size: `max-w-sm` (consistent with step modal)
- Header: amber dot + "Add Branch", compact style
- Body `p-3 space-y-2.5`:
  - **Name + Label on one row**: `grid grid-cols-2 gap-2`
  - Description: `rows="2"` textarea, optional
  - **Condition section**: `border-t border-slate-100 pt-2.5 mt-2.5`
    - Header: `text-[11px] font-medium text-slate-500` — "Condition (optional)"
    - Segmented toggle: `py-1 text-[11px]` — Field Condition / Query Count
    - **Field Condition inline row**: `[left input] [operator select w-16] [right input]` all on one line. Left/right are `flex-1 text-xs font-mono`. Operator is fixed `w-16`. Replaces 3 stacked full-width fields.
    - **Query Count panel**:
      - Entity select: full-width `text-xs`
      - WHERE rows: `[field select] [op select] [value input] [x]` inline per row
      - Count comparison: `[operator select] [value input]` — `grid grid-cols-2 gap-2`
      - Add filter: inline `+ Add filter` text link
- Footer: compact, "Cancel" + "Add Branch"

### Join Panel

- Source decision indicator: `text-[11px] text-slate-400` — "Branches from: [Decision Name]"
- Branch checkboxes as compact rows: `[checkbox] [color dot] [branch name] [connected badge]`
  - Connected badge: `text-[10px] bg-green-50 text-green-600 rounded px-1` — "connected"
  - Unconnected: no badge
- Empty state: dashed box "No source decision detected"
- Row spacing: `space-y-1`

---

## Section 6: ViewComponent Extraction & Architecture

### New ViewComponents

| Component | Purpose | Props |
|-----------|---------|-------|
| `PropertyEditor::CompactItemComponent` | Reusable row for step/branch/I/O items | Slots: `leading`, `title`, `subtitle`, `trailing`. Expandable variant with `content` slot. |
| `PropertyEditor::InlineConditionComponent` | `[left] [op] [right]` row | `left_value`, `operator`, `right_value`, `focus_color` |
| `PropertyEditor::SectionHeaderComponent` | Section label with count + add button | `label`, `count`, `add_action` |
| `PropertyEditor::EmptyStateComponent` | Dashed box with icon + message | `message`, `icon` |
| `PropertyEditor::SegmentedControlComponent` | Toggle between options | `options` (array of `{value, label}`), `active_value`, `size` |

ViewComponents render server-side HTML. JS template functions in `templates.js` produce matching HTML for dynamic client-side creation. Both use identical CSS classes and DOM structure.

### Template Consolidation

All HTML template functions move to `templates.js`. Managers import from there.

New template functions (mirroring ViewComponents):
- `buildCompactItem(params)` — matches `CompactItemComponent` output
- `buildInlineCondition(params)` — matches `InlineConditionComponent` output
- `buildSectionHeader(params)` — matches `SectionHeaderComponent` output
- `buildEmptyState(params)` — matches `EmptyStateComponent` output
- `buildSegmentedControl(params)` — matches `SegmentedControlComponent` output

Existing template functions (`buildStepModalTemplate`, `buildBranchModalTemplate`, `buildStepItemTemplate`, `buildBranchItemTemplate`, `buildErrorHandlingFieldTemplate`, etc.) are rewritten to use the new base template functions internally.

### Canvas Bridge Extraction

**New file: `property_editor/canvas_bridge.js`**

Extracted from `branch_manager.js` and `join_manager.js`:
- `createBranchElement(decisionElement, branchName, label, index)`
- `removeBranchElement(branchElementId)`
- `repositionBranches(decisionElement)`
- `syncJoinConnections(joinElement, selectedBranchIds)`
- `traceBackToDecision(element)` — graph traversal logic
- `branchSlotPosition(decisionElement, index, total)`

Managers call `this.canvasBridge.createBranchElement(...)` instead of manipulating canvas DOM directly.

### Manager Simplification

- **`io_manager.js`**: Remove all inline HTML, delegate to template functions. Single `_nextIndex(type)` helper replaces separate counters.
- **`branch_manager.js`**: Remove canvas operations (to canvas_bridge), remove inline HTML. Becomes form state + event handling.
- **`step_manager.js`**: Remove inline HTML, simplify keyword params to comma-separated input.
- **`join_manager.js`**: Remove graph traversal (to canvas_bridge), simplify to checkbox rendering + events.

### File Structure After Refactor

```
app/javascript/controllers/
  property_editor_controller.js    (slimmer)
  property_editor/
    form_builder.js                (field rendering, uses templates)
    tab_manager.js                 (minor changes)
    step_manager.js                (logic + events only)
    branch_manager.js              (logic + events only)
    io_manager.js                  (logic + events only)
    join_manager.js                (logic + events only)
    canvas_bridge.js               (NEW)
    templates.js                   (ALL HTML templates)

app/components/property_editor/
  compact_item_component.rb        (NEW)
  compact_item_component.html.erb  (NEW)
  inline_condition_component.rb    (NEW)
  inline_condition_component.html.erb (NEW)
  section_header_component.rb      (NEW)
  section_header_component.html.erb (NEW)
  empty_state_component.rb         (NEW)
  empty_state_component.html.erb   (NEW)
  segmented_control_component.rb   (NEW)
  segmented_control_component.html.erb (NEW)
```

### Testing Strategy

- **ViewComponent specs**: for each new component — rendered HTML assertions, prop variations, slot rendering
- **System specs**: property editor interaction — open, edit, save for each element type (process, decision, join, start, end)
- **No JS unit tests**: no existing JS test framework in project — rely on system specs for integration coverage

---

## Files Changed

### Modified

- `app/views/flowcharts/_editor.html.erb` — sidebar structure, header, tabs, footer, panes
- `app/javascript/controllers/property_editor_controller.js` — slimmer, delegates to canvas_bridge
- `app/javascript/controllers/property_editor/form_builder.js` — new field styling, uses template functions
- `app/javascript/controllers/property_editor/tab_manager.js` — slimmer tabs, inline badges
- `app/javascript/controllers/property_editor/templates.js` — full rewrite, all templates consolidated
- `app/javascript/controllers/property_editor/step_manager.js` — remove inline HTML, simplify keyword params
- `app/javascript/controllers/property_editor/branch_manager.js` — remove canvas ops and inline HTML
- `app/javascript/controllers/property_editor/io_manager.js` — remove inline HTML, use template functions
- `app/javascript/controllers/property_editor/join_manager.js` — remove graph traversal, simplify

### New

- `app/javascript/controllers/property_editor/canvas_bridge.js`
- `app/components/property_editor/compact_item_component.rb` + `.html.erb`
- `app/components/property_editor/inline_condition_component.rb` + `.html.erb`
- `app/components/property_editor/section_header_component.rb` + `.html.erb`
- `app/components/property_editor/empty_state_component.rb` + `.html.erb`
- `app/components/property_editor/segmented_control_component.rb` + `.html.erb`
- `spec/components/property_editor/compact_item_component_spec.rb`
- `spec/components/property_editor/inline_condition_component_spec.rb`
- `spec/components/property_editor/section_header_component_spec.rb`
- `spec/components/property_editor/empty_state_component_spec.rb`
- `spec/components/property_editor/segmented_control_component_spec.rb`

## Out of Scope

- Flowchart canvas rendering (elements, connections, minimap)
- Server-side property schema definitions
- Action registry / step action definitions
- Page builder components
- Code generator changes

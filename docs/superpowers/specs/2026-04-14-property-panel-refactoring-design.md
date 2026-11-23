# Property Panel Refactoring Design

## Problem

The flowchart edit page property editor panel is too narrow at 320px fixed width, leading to:
- Cramped fields that are hard to read and edit
- Excessive clicking to add steps (4-click modal flow) and branches
- All properties in a single scrollable area, making complex elements (Process, Decision) hard to navigate

## Solution

Refactor the property editor from a 320px fixed-width single-scroll panel to a **500px default, resizable, tabbed panel** with inline quick-add for steps and branches.

## Panel Layout

- **Width**: 500px default, resizable via left-edge drag handle
- **Min width**: 400px, **Max width**: 700px
- **Position**: right-side overlay (unchanged), full height
- **Resize persistence**: user-preferred width stored in localStorage, restored on next open
- **Drag handle**: subtle 4px left border, cursor changes to `col-resize` on hover

## Tab Structure

4 tabs: **General**, **Steps/Branches** (element-specific label), **I/O**, **Advanced**

Tabs are horizontal buttons below the header. Active tab: indigo bottom border + bold text. Inactive: slate gray. Tab switching is instant (no animation). All unsaved form data preserved across tab switches via existing cache mechanism.

### Tab Visibility Per Element Type

| Element Type | General | Steps/Branches | I/O | Advanced |
|---|---|---|---|---|
| Process | yes | "Steps" | yes | yes (errorHandling) |
| Decision | yes | "Branches" (condition + branches) | yes | yes |
| Start | yes | hidden | yes | yes (trigger config) |
| End | yes | hidden | yes | yes (response config) |
| Loop | yes | hidden | yes | yes (loop config) |
| Error Handler | yes | hidden | yes | yes (errorTypes, fallback) |
| Timer | yes | hidden | yes | yes (delay config) |
| Subflow | yes | hidden | yes | yes |
| Join | yes | hidden | hidden | yes |

### Tab Badges

Tabs display live counts where applicable:
- "Steps (3)" — number of steps
- "Branches (2)" — number of branches
- "I/O (2/3)" — inputs count / outputs count

Counts update in real-time as items are added or removed.

## Tab Content

### General Tab (all element types)

Default active tab when panel opens. Contains:
- **Label** — text input, full width
- **Description** — textarea, full width, 3 rows default
- **Comments/Notes** — textarea, full width, 3 rows default

### Steps Tab (Process elements only)

- Ordered list of existing steps with:
  - Drag-to-reorder handle
  - Step name and action label
  - "Edit" button (opens existing step configuration modal)
  - Delete button
- **Inline quick-add row** at bottom of list:
  - Category dropdown (filters available actions)
  - Action dropdown (auto-filters based on selected category)
  - "Add" button
  - Reduces step creation from 4 clicks (open modal, pick category, pick action, confirm) to 2 selections + 1 click (select category, select action, click Add)
- After adding, new step appears in list immediately; click "Edit" for detailed modal config

### Branches Tab (Decision elements only)

- **Condition builder** section at top (same as current)
- **Branch list** below with edit/delete per branch
- **Inline quick-add row**: condition type dropdown + "Add" button
- Clicking "Edit" opens existing branch configuration modal
- After adding, new branch appears in list immediately

### I/O Tab (most element types, hidden for Join)

- **Inputs** section with add/remove rows (same interaction as current)
- **Outputs** section with add/remove rows (same interaction as current)
- Each section gets full tab height, reducing scrolling

### Advanced Tab (content varies by element type)

- **Process**: errorHandling mode selector
- **Start**: triggerType select + conditional fields (httpMethod, httpPath, eventName, cronExpression)
- **End**: responseType select + conditional fields (returnValue, httpStatus, responseBody)
- **Loop**: loopType select + conditional fields (condition, collection, itemVariable, indexVariable, iterations)
- **Error Handler**: errorTypes text field, fallbackAction select
- **Timer**: delayType select + conditional fields (duration, durationUnit, waitCondition)
- **Subflow**: reserved for future configuration
- **Join**: join-specific fields (merged branches, source decision)

Short fields (selects, number inputs) use **2-column layout** side by side. Text and textarea fields use full width.

## Interaction Details

### Panel Resizing

- Left edge drag handle: 4px border, `col-resize` cursor on hover
- Constrained to 400px min, 700px max
- Preferred width persisted in localStorage key (e.g., `flowchart_property_panel_width`)
- Restored automatically on next panel open

### Tab Switching

- Instant content swap via `hidden` class toggle on tab panes
- All form data preserved in memory across tab switches (existing unsavedChangesCache mechanism)
- Active tab state resets to "General" when opening a different element

### Auto-Sync

- Same as current: real-time sync to canvas on input/change events (debounced 100ms)
- Explicit Save button persists to database
- Tab badge counts update live

### Modals

- Existing step configuration modal and branch configuration modal remain unchanged
- Modals are triggered by "Edit" buttons on step/branch list items
- Modal containers (`stepModalContainer`, `branchModalContainer`) remain in same position

## Architecture

### Schema Changes

Add a `tab` property to each field definition in `schemas.js`:

```javascript
// Example for process element
process: {
  label: { ...COMMON_PROPERTIES.label, tab: "general" },
  description: { ...COMMON_PROPERTIES.description, tab: "general" },
  comments: { ...COMMON_PROPERTIES.comments, tab: "general" },
  inputs: { ...COMMON_PROPERTIES.inputs, tab: "io" },
  steps: { type: "steps", label: "Steps", actionOptions: STEP_ACTIONS, tab: "steps" },
  outputs: { ...COMMON_PROPERTIES.outputs, tab: "io" },
  errorHandling: { type: "error_handling", label: "Error Handling", tab: "advanced" }
}
```

Fields without a `tab` property default to `"general"`.

### Stimulus Controller Refactoring

Current `property_editor_controller.js` (1129 lines) is refactored into:

1. **`property_editor_controller.js`** — main controller: open/close, save, tab switching orchestration
2. **`property_editor/tab_manager.js`** — new module: manages tab state, renders fields into correct tab panes, handles tab badge updates, preserves data across tab switches
3. **`panel_resize_controller.js`** — new small controller: drag-to-resize with min/max constraints and localStorage persistence

Existing modules remain unchanged:
- `property_editor/form_builder.js` — updated to group fields by tab
- `property_editor/step_manager.js` — renders into Steps tab pane, adds inline quick-add row
- `property_editor/branch_manager.js` — renders into Branches tab pane, adds inline quick-add row
- `property_editor/io_manager.js` — renders into I/O tab pane
- `property_editor/join_manager.js` — renders into Advanced tab pane
- `property_editor/templates.js` — unchanged

### HTML Structure

Update `_editor.html.erb` property sidebar:

```
Panel (w-[500px], inline style for dynamic resize)
  Header (title, type indicator, close button)
  Tab Bar (General | Steps/Branches | I/O | Advanced)
  Form
    Tab Pane: General (fields)
    Tab Pane: Steps/Branches (step list + quick-add OR branch list + quick-add)
    Tab Pane: I/O (inputs + outputs)
    Tab Pane: Advanced (element-specific fields)
  Footer (Cancel | Save)
  Modal Containers (step modal, branch modal)
```

### No New ViewComponents

The property editor is entirely JavaScript-driven dynamic form rendering (same as current). The tab bar is simple HTML rendered by the Stimulus controller. No new Ruby ViewComponents are needed.

### No Backend Changes

This is a purely client-side refactoring. No changes to models, controllers, routes, or database.

## Testing

- **No RSpec changes**: property editor is entirely client-side
- **JavaScript tests**: update existing property editor specs to cover:
  - Tab switching preserves form data
  - Correct tabs shown/hidden per element type
  - Tab badge counts update on add/remove
  - Inline quick-add flow for steps (select category, select action, click Add)
  - Inline quick-add flow for branches (select condition, click Add)
  - Panel resize drag, min/max constraints
  - Panel width persistence in localStorage
  - Default tab is General on open

## Files to Modify

1. `app/views/flowcharts/_editor.html.erb` — panel HTML structure, tab bar, tab panes
2. `app/javascript/flowchart/constants/schemas.js` — add `tab` property to field definitions
3. `app/javascript/controllers/property_editor_controller.js` — refactor, add tab switching
4. `app/javascript/controllers/property_editor/tab_manager.js` — new module
5. `app/javascript/controllers/property_editor/form_builder.js` — group fields by tab
6. `app/javascript/controllers/property_editor/step_manager.js` — add inline quick-add row
7. `app/javascript/controllers/property_editor/branch_manager.js` — add inline quick-add row
8. `app/javascript/controllers/panel_resize_controller.js` — new controller

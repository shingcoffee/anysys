# Rules & Calculations Drawer Redesign — UI Design Spec

**Date:** 2026-06-05
**Author:** UX Designer agent
**Surface:** Page editor (`/:cid/admin/maintenance/pages/:id/edit`) — Conditional Rules and Calculated Fields drawers
**Nav area:** Maintenance/Modules (page-builder admin surface)

---

## 1. Surface Inventory

| Surface | Nav Area | Entry Point | Accent |
|---|---|---|---|
| Rules Drawer — List State | Maintenance/Modules | Toolbar "Rules" tab button | indigo |
| Rules Drawer — Editor State | Maintenance/Modules | "Add Rule" or row "Edit" action | indigo |
| Calculations Drawer — List State | Maintenance/Modules | Toolbar "Calculations" tab button | purple |
| Calculations Drawer — Editor State | Maintenance/Modules | "Add Calculation" or row "Edit" action | purple |

Both drawers share one structural chrome (`BuilderDrawerComponent`) and live inside the page-editor layout (`data-controller="page-builder"`). The canvas and left sidebar remain visible to the left while any drawer is open.

---

## 2. Shared Drawer Chrome

### 2.1 Structural Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PAGE EDITOR (full viewport)                                             │
│  ┌──────────────────────────────────┐  ┌────────────────────────────┐  │
│  │ LEFT SIDEBAR (w-72)              │  │  DRAWER (~520px)           │  │
│  │                                  │  │  fixed inset-y-0 right-0   │  │
│  ├──────────────────────────────────┤  │  ┌──────────────────────┐  │  │
│  │ CANVAS (flex-1)                  │  │  │ HEADER (px-5 py-4)   │  │  │
│  │                                  │  │  ├──────────────────────┤  │  │
│  │ Canvas stays visible             │  │  │ BODY (flex-1         │  │  │
│  │ while drawer is open             │  │  │  overflow-y-auto)    │  │  │
│  │                                  │  │  │                      │  │  │
│  │                                  │  │  │ [LIST or EDITOR      │  │  │
│  │                                  │  │  │  state here]         │  │  │
│  │                                  │  │  │                      │  │  │
│  │                                  │  │  ├──────────────────────┤  │  │
│  │                                  │  │  │ FOOTER (sticky,      │  │  │
│  │                                  │  │  │  border-t, px-5 py-3)│  │  │
│  └──────────────────────────────────┘  └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

On mobile (`< sm`): drawer is `fixed inset-0` (full-width sheet). A semi-transparent scrim `bg-black/40` sits between canvas and drawer on mobile only (`sm:hidden`).

### 2.2 Drawer Outer Container

```
Tailwind classes (outer wrapper element):
  fixed inset-y-0 right-0 z-40
  w-full sm:w-[520px] sm:max-w-[92vw]
  bg-white shadow-2xl border-l border-gray-200
  flex flex-col
  transition-transform duration-200 ease-out

Hidden state:   translate-x-full   (JS adds this class when closed)
Visible state:  translate-x-0      (JS removes translate-x-full when open)

data attributes (must keep for existing JS):
  role="tabpanel"
  data-tab-panel="<key>"              (e.g. "rules" or "calculations")
  data-page-builder-target="tabPanel"
  class="tab-panel ..."               (existing JS reads .tab-panel selector)
```

Note: The existing JS uses `hidden` + `fixed top-16 left-72 right-0 bottom-0` for tab panels. For the drawer, replace the `hidden` toggle with `translate-x-full` / `translate-x-0` so the slide animation works. The JS `closeAllTabPanels` method will need to add `translate-x-full` instead of `hidden`. This is the only JS behaviour change in the close/open path.

### 2.3 Drawer Header

```
┌──────────────────────────────────────────────────────────┐
│  ┌───┐  Title text (text-base font-semibold text-gray-900)│  [✕]  │
│  │ ◉ │  Subtitle (text-xs text-gray-500 mt-0.5)          │       │
│  └───┘                                                    │       │
└──────────────────────────────────────────────────────────┘
```

Tailwind classes:
```
Header wrapper:
  flex items-start justify-between gap-3 px-5 py-4 border-b border-gray-100 flex-shrink-0

Icon container:
  flex items-center justify-center w-9 h-9 rounded-lg flex-shrink-0
  bg-indigo-50   (Rules)  |  bg-purple-50   (Calcs)

Icon SVG:
  w-5 h-5
  text-indigo-600  (Rules)  |  text-purple-600  (Calcs)

Title+subtitle wrapper:
  flex flex-col min-w-0

Title:
  text-base font-semibold text-gray-900 truncate

Subtitle:
  text-xs text-gray-500 mt-0.5

Close button:
  p-2 -mr-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100
  rounded-lg transition-colors flex-shrink-0
  data-action="click->page-builder#closeAllTabPanels"
```

### 2.4 Drawer Body (master→detail container)

The body hosts two layers stacked in a relative container. JS toggles visibility between list and editor by toggling `hidden` on each layer:

```
Body wrapper:
  flex-1 overflow-y-auto relative

List layer:
  data-drawer-list="<key>"
  block / hidden

Editor layer:
  data-drawer-editor="<key>"
  block / hidden
  (cloned editor is injected here by the manager; starts hidden)
```

### 2.5 Drawer Footer (sticky)

The footer is rendered inside the outer flex column, below the body, so it sticks at the bottom naturally:

```
Footer wrapper:
  flex items-center justify-between px-5 py-3
  border-t border-gray-100 bg-white flex-shrink-0

List state footer:
  Left side: empty (or rule count echo — optional)
  Right side: primary "Add Rule" / "Add Calculation" button

Editor state footer:
  Left side: "Cancel" (secondary)
  Right side: "Save Rule" / "Save" (primary, accent-colored)
```

### 2.6 Accent Token Map

| Token | Rules (indigo) | Calcs (purple) |
|---|---|---|
| Icon bg | `bg-indigo-50` | `bg-purple-50` |
| Icon color | `text-indigo-600` | `text-purple-600` |
| Primary btn bg | `bg-indigo-600 hover:bg-indigo-700` | `bg-purple-600 hover:bg-purple-700` |
| Primary btn text | `text-white` | `text-white` |
| Focus ring | `focus:ring-indigo-500` | `focus:ring-purple-500` |
| Row hover border | `hover:border-indigo-200` | `hover:border-purple-200` |
| Format badge bg | `bg-indigo-50 text-indigo-700` | `bg-purple-100 text-purple-700` |
| Connector badge bg | `bg-indigo-100 text-indigo-600` | (N/A — only rules have connectors) |
| Search ring | `focus:ring-indigo-500` | `focus:ring-purple-500` |
| Add-item dashed border hover | `hover:border-indigo-400 hover:text-indigo-600` | `hover:border-purple-400 hover:text-purple-600` |
| Segmented control active | `bg-indigo-600 text-white` | (N/A) |

### 2.7 Button Classes (shared)

```
Primary button:
  inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium
  bg-indigo-600 hover:bg-indigo-700 text-white
  rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-1

  (purple variant: replace indigo with purple throughout)

Secondary button:
  px-4 py-2 text-sm font-medium text-gray-700
  bg-white border border-gray-300 hover:bg-gray-50
  rounded-lg transition-colors

Destructive icon button (delete):
  p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors

Ghost icon button (edit / duplicate):
  p-1.5 text-gray-400 hover:text-indigo-600 hover:bg-indigo-50 rounded-md transition-colors
  (purple variant for calcs)
```

---

## 3. Rules — List State

### 3.1 Layout

```
┌─────────────────────────────────────┐  ← drawer body (px-4 py-4)
│  [3 rules configured]    [+ Add Rule] ← top bar
├─────────────────────────────────────┤
│  [Search rules…             🔍]      ← shown when > 6 rules
├─────────────────────────────────────┤
│  ● Rule Name                         ← enabled dot = emerald-500
│  When Country equals US →            ← summary, xs text-gray-400
│              [□] [✎] [🗑]  ← hover actions (opacity-0 group-hover:opacity-100)
├─────────────────────────────────────┤
│  ○ Shipping Conditions              ← disabled dot = gray-300
│  When Shipping equals …             │
├─────────────────────────────────────┤
│  …                                  │
└─────────────────────────────────────┘
```

### 3.2 List Item Row

```
Row wrapper:
  group p-3 bg-white rounded-lg border border-gray-200
  hover:border-indigo-200 hover:shadow-sm transition-all
  data-rule-id="<id>"

Row layout:
  flex items-center justify-between gap-2

Left cluster (min-w-0 flex items-center gap-2):
  Status dot button (flex-shrink-0):
    data-action="click->page-builder#toggleRule"
    data-rule-id="<id>"
    Inner span:
      block w-2 h-2 rounded-full
      bg-emerald-500  (enabled)  |  bg-gray-300  (disabled)

  Rule name:
    text-sm font-medium text-gray-800 truncate

Summary line (below, not inline):
  mt-1 text-xs text-gray-400 truncate
  format: "When [field] [op] [value] → [action] [target]"

Right hover actions (flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity):
  Duplicate button (amber hover)
  Edit button (indigo hover)
  Delete button (red hover)
```

### 3.3 Search Bar (shown when rules.length > 6)

```
Container: mb-3

Input:
  w-full px-2.5 py-1.5 text-xs border border-gray-200 rounded-md
  focus:outline-none focus:ring-1 focus:ring-indigo-500
  placeholder="Search rules…"
  data-action="input->page-builder#filterPanel"
  data-filter-panel="rules-panel"
  data-filter-items="rule-id"
```

### 3.4 Empty State

```
Container: flex flex-col items-center justify-center py-16 text-center px-4

Icon container: w-12 h-12 bg-indigo-50 rounded-xl flex items-center justify-center mb-3
Icon SVG: w-6 h-6 text-indigo-400 (checklist / rules icon)

Heading: text-sm font-medium text-gray-900 mb-1
  "No rules defined"

Body: text-xs text-gray-500 max-w-[240px] mb-5
  "Add conditional rules to show or hide fields dynamically based on user input."

Primary CTA: same as "+ Add Rule" primary button (indigo)
  data-action="click->page-builder#openRuleEditor"
```

### 3.5 Top Bar (always shown, inside list body padding)

```
Container: flex items-center justify-between mb-3

Left: text-xs text-gray-500
  "<N> rule<s> configured"  (use pluralize helper)

Right: "+ Add Rule" button
  inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium
  text-indigo-600 bg-indigo-50 hover:bg-indigo-100 rounded-md transition-colors
  data-action="click->page-builder#openRuleEditor"
```

---

## 4. Rules — Editor State

### 4.1 Layout within the drawer body

The editor state completely replaces the list layer inside the drawer body. The drawer header retains its title/close, but the footer now shows Cancel + Save Rule.

The editor is injected by `rules_manager.js` cloning the `ruleEditorTemplate` into `data-drawer-editor="rules"`. The cloned element is no longer a modal scrim — it is a plain `<div>` with `data-controller="rule-builder"` that fills the drawer body.

```
┌─────────────────────────────────────┐
│  HEADER (drawer chrome, kept)        │
├─────────────────────────────────────┤  ← drawer body starts
│  ← Back to Rules          [live summary banner]  │
├─────────────────────────────────────┤
│  Rule Name  [________________________]  │
├─────────────────────────────────────┤
│  WHEN   [All conditions ▾]  ← segmented ctrl │
│                                     │
│  ┌──── Condition Group (AND) ────┐  │
│  │  [Field ▾] [Operator ▾] [Val] [✕] │
│  │  AND                             │  ← AND badge on rail
│  │  [Field ▾] [Operator ▾] [Val] [✕] │
│  │  [+ Add Condition]               │
│  └──────────────────────────────┘  │
│  OR                                 │  ← OR badge between groups
│  ┌──── Condition Group (OR) ─────┐  │
│  │  [Field ▾] [Operator ▾] [Val] [✕] │
│  └──────────────────────────────┘  │
│  [+ Add Condition Group]             │
├─────────────────────────────────────┤
│  THEN                               │
│  [Action ▾] [Target ▾] ([Value])  [✕] │
│  [Action ▾] [Target ▾]            [✕] │
│  [+ Add Action]                     │
├─────────────────────────────────────┤
│  ▶ Test Mode  (collapsible toggle)  │
│    [sample inputs / action results] │
├─────────────────────────────────────┤  ← drawer footer
│  [Cancel]                [Save Rule] │
└─────────────────────────────────────┘
```

### 4.2 Back Navigation & Live Summary

```
Back bar (top of editor body, px-4 py-3 border-b border-gray-100):
  flex items-center gap-2

  Back button:
    p-1.5 -ml-1 text-gray-400 hover:text-gray-700 hover:bg-gray-100 rounded-lg
    data-action="click->page-builder#closeRuleEditor"
    Inner: chevron-left SVG w-4 h-4

  Live summary:
    flex-1 min-w-0
    data-rule-builder-target="liveSummary"
    text-xs text-gray-500 italic truncate
    placeholder text: "When [field] … → [action]"
    (JS populates this on every model change; empty until first condition)
```

### 4.3 Rule Name Input

```
Section: px-4 py-4 border-b border-gray-100

Label: block text-xs font-medium text-gray-500 uppercase tracking-wide mb-1.5
  "Rule Name"

Input:
  w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
  focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-400
  placeholder="e.g. Show shipping address when shipping selected"
  data-rule-builder-target="ruleName"
```

### 4.4 WHEN Section — Top-Level Logic + Condition Groups

```
Section wrapper: px-4 py-4 space-y-3

Section header (flex items-center justify-between mb-2):
  Label: text-xs font-semibold text-gray-500 uppercase tracking-wide
    "WHEN"
  Top-level AND/OR segmented control:
    data-rule-builder-target="conditionsLogic"
    (see §4.5 for segmented control spec)
```

#### 4.4.1 Condition Group Container

```
Group wrapper:
  relative border border-gray-200 rounded-lg bg-gray-50/60
  data-condition-group="<index>"

Vertical rail:
  absolute left-5 top-8 bottom-8 w-px bg-gray-200
  (visual rail connecting condition rows within the group)

Group header (px-3 py-2 flex items-center justify-between):
  Group label: text-xs font-medium text-gray-400
    "Group <N>"  (or just "Conditions" for single group)
  Group AND/OR segmented control:
    data-group-logic="<index>"
    (same segmented control as top-level, but smaller: text-[10px] h-6)
  Remove group button:
    p-1 text-gray-400 hover:text-red-500 rounded
    data-action="click->rule-builder#removeConditionGroup"
    data-group-index="<index>"
    × SVG w-3.5 h-3.5

Condition items wrapper:
  px-3 pb-3 space-y-0
  data-condition-items="<index>"

  Between condition rows: AND/OR connector badge (see §4.4.2)

Add condition button (inside group, below items):
  mx-3 mb-2 w-[calc(100%-1.5rem)] px-2 py-1.5 text-xs
  text-gray-500 border border-dashed border-gray-300 rounded-md
  hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50/60
  transition-colors
  data-action="click->rule-builder#addConditionItem"
  data-group-index="<index>"
  "+ Add Condition"
```

#### 4.4.2 AND/OR Connector Badge (between condition rows and between groups)

The connector is a thin horizontal rule with a centered badge. It reads from the parent's logic setting (AND/OR) and is rendered between each pair of sibling rows or sibling groups.

```
Connector wrapper (between two condition rows inside a group):
  relative flex items-center my-1 mx-3

  Left line: flex-1 border-t border-gray-200
  Badge: mx-2 flex-shrink-0
    px-2 py-0.5 text-[10px] font-semibold rounded-full
    bg-indigo-100 text-indigo-600   (AND)  |  bg-amber-100 text-amber-600  (OR)
    "AND"  or  "OR"
  Right line: flex-1 border-t border-gray-200

Connector between condition groups (between two group containers):
  Same structure but slightly larger badge:
    px-2.5 py-0.5 text-xs font-semibold rounded-full
    bg-indigo-100 text-indigo-700  (AND)  |  bg-amber-100 text-amber-700  (OR)
  Wrapper: relative flex items-center my-2 px-4
```

### 4.5 Segmented AND/OR Control

The segmented control replaces the `<select>` visually but keeps the `<select>` element in the DOM for JS compatibility. Use a visually hidden `<select>` paired with button-pair buttons, OR — simpler and fully compatible — style the `<select>` directly using a custom-styled appearance.

Recommended approach: keep the `<select>` element, style it as a pill with two-option appearance using `appearance-none` + a background/padding trick. This is zero-JS and keeps all data-attribute hooks.

```
Wrapper: inline-flex rounded-lg border border-gray-200 overflow-hidden bg-gray-100 p-0.5

The <select> element stays in DOM with its data-rule-builder-target attribute.
Style it hidden. Drive it from two <button> siblings that update the <select> value
via a micro Stimulus action.

Two-button visual:
  [All (AND)] [Any (OR)]

  Each button:
    px-3 py-1 text-xs font-medium rounded-md transition-all

  Active state (JS adds class when value matches):
    bg-indigo-600 text-white shadow-sm

  Inactive state:
    text-gray-600 hover:text-gray-800

  Data wiring:
    data-action="click->rule-builder#setConditionsLogic"
    data-value="all"  /  data-value="any"
    (rule_builder controller adds a setConditionsLogic action that updates the hidden select)
```

Note: if adding a new JS action to `rule_builder` is out of scope for this task, fall back to the simpler approach of styling the `<select>` with `appearance-none` + descriptive classes so it looks reasonable. The fully styled segmented control is the preferred design.

### 4.6 Condition Row (chip styling)

Replaces the raw `flex-wrap` row with a compact chip layout. The `ConditionRowComponent` renders each row. Its data attributes remain identical.

```
Row wrapper:
  relative flex items-center gap-1.5 py-1.5
  data-condition-item="<group>-<item>"

Field chip (select styled as chip):
  min-w-0 flex-1 max-w-[160px]
  appearance-none px-2 py-1 text-xs font-medium
  bg-white border border-gray-200 rounded-md
  focus:ring-1 focus:ring-indigo-500 focus:border-indigo-400
  text-gray-700 truncate cursor-pointer
  data-condition-field="<group>-<item>"
  data-action="change->rule-builder#onConditionFieldChange"

Operator chip (select styled as chip):
  appearance-none px-2 py-1 text-xs
  bg-indigo-50 border border-indigo-200 rounded-md
  text-indigo-700 cursor-pointer
  focus:ring-1 focus:ring-indigo-500
  data-condition-operator="<group>-<item>"
  data-action="change->rule-builder#onConditionOperatorChange"

Value editors (contextual — same 7 branches as current, restyled):
  All value inputs: px-2 py-1 text-xs border border-gray-200 rounded-md
    focus:ring-1 focus:ring-indigo-500 bg-white

  :none — nothing rendered
  :select — flex-1 min-w-[100px] (same chip style as field chip)
  :boolean — w-20 (True/False select)
  :number — flex-1 min-w-[72px] type="number"
  :number_range — two inputs w-16 each, "–" span between
  :date — flex-1 type="date"
  :date_range — two date inputs, "–" span between
  :text (default) — flex-1 min-w-[80px] type="text"

Remove button:
  flex-shrink-0 p-1 text-gray-300 hover:text-red-500 rounded transition-colors
  data-action="click->rule-builder#removeConditionItem"
  × SVG w-3.5 h-3.5
```

### 4.7 THEN Section — Action Rows

```
Section wrapper: px-4 py-4 border-t border-gray-100 space-y-2

Section header: text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2
  "THEN"

Action items wrapper: data-rule-builder-target="ruleActions" space-y-2

Action row:
  flex flex-wrap items-center gap-1.5 p-2.5 bg-gray-50 rounded-lg border border-gray-100
  data-action-item="<index>"

  Action type chip (select):
    appearance-none px-2 py-1 text-xs bg-white border border-gray-200 rounded-md
    text-gray-700 focus:ring-1 focus:ring-indigo-500
    data-action-type="<index>"
    data-action="change->rule-builder#onActionTypeChange"
    Options: 9 action types (all preserved — show_field, hide_field, show_page,
      hide_page, skip_to_page, enable_field, disable_field, set_required, set_value)

  Target chip (select):
    appearance-none flex-1 min-w-[120px] px-2 py-1 text-xs
    bg-indigo-50 border border-indigo-200 rounded-md text-indigo-700
    focus:ring-1 focus:ring-indigo-500
    data-action-target="<index>"

  Value input (for set_required / set_value only):
    w-24 px-2 py-1 text-xs border border-gray-200 rounded-md
    focus:ring-1 focus:ring-indigo-500
    placeholder="Value"
    data-action-value="<index>"

  Action result indicator:
    text-[10px] text-gray-400
    data-rule-builder-target="actionResult"

  Remove button:
    p-1 text-gray-300 hover:text-red-500 rounded
    data-action="click->rule-builder#removeAction"

Add action button (below items):
  mt-2 w-full px-3 py-2 text-xs text-gray-500 border border-dashed border-gray-300
  rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50/60
  transition-colors
  data-action="click->rule-builder#addAction"
  "+ Add Action"
```

### 4.8 Test Mode (collapsible section)

```
Wrapper: px-4 py-4 border-t border-gray-100

Toggle row (flex items-center gap-2 cursor-pointer):
  Chevron icon (rotates on open): w-4 h-4 text-gray-400 transition-transform
  Checkbox (visually hidden, actual DOM element kept for JS compatibility):
    data-rule-builder-target="testToggle"
    data-action="change->rule-builder#toggleTest"
  Label: text-xs font-medium text-gray-600
    "Test Mode"
  Status badge (shown when active): px-1.5 py-0.5 text-[10px] rounded-full
    bg-amber-100 text-amber-700 "Active"

Collapsible body (data-rule-builder-target="testPanel" hidden until toggled):
  mt-3 space-y-3 bg-amber-50/60 rounded-lg p-3 border border-amber-100

  Instruction: text-xs text-gray-500
    "Enter sample values to see which actions would fire."

  Sample inputs container:
    data-rule-builder-target="sampleInputs"
    space-y-2
    (JS populates input rows for each referenced field)

  Each sample input row:
    flex items-center gap-2
    Label: text-xs text-gray-600 w-28 truncate flex-shrink-0
    Input: flex-1 px-2 py-1 text-xs border border-gray-200 rounded-md

  Action fire indicators: rendered by JS next to action results
    data-rule-builder-target="actionResult"
    Fired: text-[10px] text-emerald-600 "✓ fires"
    Not fired: text-[10px] text-gray-400 "– skipped"
```

### 4.9 Data Templates (unchanged, kept in DOM)

Both templates remain in the DOM inside the cloned editor element, invisible to users:

```html
<template data-operators-template>
  <!-- 16 operator <option> elements, verbatim from current implementation -->
</template>
<template data-action-types-template>
  <!-- 9 action type <option> elements, verbatim from current implementation -->
</template>
```

These are required by `rule_builder` JS. Do not move, rename, or remove them.

---

## 5. Calculations — List State

### 5.1 Layout

```
┌─────────────────────────────────────┐
│  [2 calculations]  [+ Add Calculation] │
├─────────────────────────────────────┤
│  [Search calculations…       🔍]    ← > 6 only
├─────────────────────────────────────┤
│  Total Price         [Currency]     │
│  = SUM(qty, price) * 1.1           │
│                         [✎] [🗑]   │
├─────────────────────────────────────┤
│  …                                  │
└─────────────────────────────────────┘
```

### 5.2 Calculation List Row

```
Row wrapper:
  group flex items-center justify-between p-3 bg-white rounded-lg
  border border-gray-200 hover:border-purple-200 hover:shadow-sm transition-all
  data-calculation-id="<id>"

Left section (min-w-0 flex flex-col gap-0.5):
  Top row (flex items-center gap-1.5):
    Target field label: text-sm font-medium text-gray-800 truncate
    Format badge (if present):
      px-1.5 py-0.5 text-[10px] rounded-md
      bg-purple-100 text-purple-700 font-medium
      (e.g. "Currency", "Percent", "Number")

  Formula mono preview:
    text-xs text-gray-500 font-mono block truncate max-w-[300px]
    "= SUM(price, tax)"

Right section (hover actions):
  flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0

  Edit button:
    p-1.5 text-gray-400 hover:text-purple-600 hover:bg-purple-50 rounded-md transition-colors
    data-action="click->page-builder#editCalculation"

  Delete button:
    p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors
    data-action="click->page-builder#deleteCalculation"
```

### 5.3 Empty State

```
Container: flex flex-col items-center justify-center py-16 text-center px-4

Icon container: w-12 h-12 bg-purple-50 rounded-xl flex items-center justify-center mb-3
Icon SVG: w-6 h-6 text-purple-400 (calculator icon — existing SVG)

Heading: text-sm font-medium text-gray-900 mb-1
  "No calculated fields"

Body: text-xs text-gray-500 max-w-[240px] mb-5
  "Add formulas to automatically compute field values from other fields."

Primary CTA: purple primary button
  data-action="click->page-builder#openFormulaEditor"
  "+ Add Calculation"
```

---

## 6. Calculations — Editor State

### 6.1 Layout within the drawer body

```
┌─────────────────────────────────────┐
│  HEADER (drawer chrome, kept)        │
├─────────────────────────────────────┤
│  ← Back       [live formula preview] │  ← back bar
├─────────────────────────────────────┤
│  Target Field  [Select field…    ▾] │  ← grouped by page (optgroups)
├─────────────────────────────────────┤
│  Formula                            │
│  ┌─────────────────────────────┐   │
│  │ [Quantity] × [Price] + ...  │   │  ← pill editor surface (contenteditable)
│  │                             │   │
│  └─────────────────────────────┘   │
│  ✓ Valid · Result: 42.00           │  ← status + preview
│  [autocomplete dropdown here]       │
├─────────────────────────────────────┤
│  INSERT FUNCTION                    │
│  [Math][Logic][Text][Date]  [🔍]   │  ← tab bar + search
│  ┌──────────────────────────────┐  │
│  │ [SUM] [SUBTRACT] [MULTIPLY]  │  │
│  │ [DIVIDE] [MIN] [MAX] ...     │  │
│  └──────────────────────────────┘  │
├─────────────────────────────────────┤
│  OUTPUT FORMAT                      │
│  ┌───────────┐  ┌───────────┐      │
│  │ Format    │  │ Decimals  │      │
│  │ [Plain ▾] │  │ [2      ] │      │
│  └───────────┘  └───────────┘      │
│  ┌───────────┐  ┌───────────┐      │
│  │ Prefix    │  │ Suffix    │      │
│  │ [$      ] │  │ [USD    ] │      │
│  └───────────┘  └───────────┘      │
├─────────────────────────────────────┤
│  SAMPLE VALUES                      │
│  Field: [_______]  Result: 42.00   │
├─────────────────────────────────────┤  ← footer
│  [Cancel]                    [Save] │
└─────────────────────────────────────┘
```

### 6.2 Back Bar + Live Preview

```
Back bar: px-4 py-3 border-b border-gray-100 flex items-center gap-3

  Back button:
    p-1.5 -ml-1 text-gray-400 hover:text-gray-700 hover:bg-gray-100 rounded-lg
    data-action="click->page-builder#closeFormulaEditor"
    chevron-left SVG w-4 h-4

  Live preview text:
    flex-1 min-w-0 text-xs font-mono text-gray-500 truncate
    Populated by formula-editor controller via data-formula-editor-target="preview"
```

### 6.3 Target Field Select

```
Section: px-4 py-4 border-b border-gray-100

Label: block text-xs font-medium text-gray-500 uppercase tracking-wide mb-1.5
  "Target Field"

Select:
  w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
  focus:outline-none focus:ring-2 focus:ring-purple-500/30 focus:border-purple-400
  appearance-none
  data-page-builder-target="calculationTargetField"

  When pages > 1: <optgroup label="Page Name"> wraps each page's fields
  When 1 page: flat <option> list
```

### 6.4 Pill Formula Editor Surface

The `FormulaPillEditorComponent` is restyled but all data attributes, targets, and the `formula-editor` controller remain unchanged.

```
Section: px-4 py-4 border-b border-gray-100

Label: block text-xs font-medium text-gray-500 uppercase tracking-wide mb-1.5
  "Formula"

Formula pill editor wrapper:
  data-controller="formula-editor"
  data-formula-editor-fields-value="..."
  data-formula-editor-formula-value="..."
  space-y-2

Contenteditable surface:
  min-h-[72px] w-full rounded-lg border border-gray-300 bg-white
  px-3 py-2 font-mono text-sm leading-7
  focus:outline-none focus:ring-2 focus:ring-purple-500/30 focus:border-purple-400
  data-formula-editor-target="surface"
  data-action="input->formula-editor#onInput keydown->formula-editor#onKeydown"

Autocomplete dropdown (positioned by controller):
  hidden absolute z-50 max-h-56 w-64 overflow-y-auto
  rounded-lg border border-gray-200 bg-white shadow-lg
  data-formula-editor-target="autocomplete"

Status + preview row (flex items-center justify-between text-xs):
  Status span: data-formula-editor-target="status" font-medium
    Valid: text-emerald-600
    Invalid: text-red-600
  Preview span: data-formula-editor-target="preview" text-gray-500

Error block (hidden until error):
  rounded-md bg-red-50 px-3 py-2 text-xs text-red-700
  data-formula-editor-target="errors"

PILL STYLING for field/function tokens inside the contenteditable:
  Each pill span:
    inline-flex items-center gap-0.5 px-1.5 py-0.5 mx-0.5 align-middle
    text-[11px] font-medium rounded-md leading-tight
    select-none contenteditable="false"

  Field pill: bg-purple-50 text-purple-700 border border-purple-200
  Function pill: bg-gray-100 text-gray-700 border border-gray-200
  Number literal: text-amber-700 (plain text, no pill border)
  Operator (+−×÷): text-gray-500 (plain text)
```

### 6.5 Function Inserter

The inserter replaces the old flat wall of buttons. It has: category tabs, a filter search input, and click-to-insert chips. The 31 functions are organized into 4 categories.

#### Category Map (full parity, must include all 31)

| Category | Functions (12) |
|---|---|
| Math | SUM, SUBTRACT, MULTIPLY, DIVIDE, MIN, MAX, AVERAGE, ROUND, FLOOR, CEIL, ABS, MOD |
| Logic | IF, AND, OR, NOT, SWITCH |
| Text | CONCAT, UPPER, LOWER, TRIM, LENGTH, LEFT, RIGHT |
| Date | TODAY, NOW, YEAR, MONTH, DAY, DATE_DIFF, DATE_ADD |

#### Inserter Layout

```
Section wrapper: px-4 py-3 border-b border-gray-100

Section header: text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2
  "Insert Function"

Category tabs + search (flex items-center gap-2 mb-2):
  Tab bar (flex items-center gap-0.5 flex-1 bg-gray-100 rounded-lg p-0.5):
    [Math] [Logic] [Text] [Date]
    Each tab button:
      px-2.5 py-1 text-xs font-medium rounded-md transition-all
      Active: bg-white text-gray-900 shadow-sm
      Inactive: text-gray-500 hover:text-gray-700
      data-action="click->formula-editor#switchFunctionTab"  (or inline Stimulus on parent)
      data-category="Math"

  Search input:
    px-2 py-1 text-xs border border-gray-200 rounded-md w-28
    focus:ring-1 focus:ring-purple-500 placeholder="Filter…"
    data-action="input->formula-editor#filterFunctions"
    data-formula-editor-target="fnSearch"

Function chips grid (flex flex-wrap gap-1.5 min-h-[52px]):
  data-formula-editor-target="fnGrid"
  (JS filters this by active tab + search term)

  Each chip:
    inline-flex items-center px-2 py-1 text-[11px] font-mono font-medium
    bg-gray-50 border border-gray-200 text-gray-700
    rounded-md cursor-pointer
    hover:bg-purple-50 hover:border-purple-300 hover:text-purple-700
    transition-colors
    data-fn-insert
    data-function="SUM"
    data-action="click->formula-editor#insertFunctionToken"

  (All 31 chips rendered in DOM; JS shows/hides by category + search filter)
```

#### Function Inserter Stimulus Notes

The `formula-editor` controller needs two new actions (or these can be wired to a new `function-inserter` sub-controller if preferred, but inline on `formula-editor` is simpler):

- `switchFunctionTab(event)` — reads `event.currentTarget.dataset.category`, shows chips for that category, updates tab active state.
- `filterFunctions(event)` — filters visible chips by search term (case-insensitive `includes`).
- `insertFunctionToken(event)` — reads `event.currentTarget.dataset.function`, inserts the function name + `(` at cursor in the surface. This action likely already exists or is close to existing `insertToken` logic — verify against the actual controller before building.

### 6.6 Format Controls Grid

```
Section wrapper: px-4 py-4 border-b border-gray-100

Section header: text-xs font-semibold text-gray-500 uppercase tracking-wide mb-3
  "Output Format"

Grid: grid grid-cols-2 gap-3

Cell 1 — Format Type:
  Label: block text-xs text-gray-500 mb-1  "Type"
  Select:
    w-full px-2.5 py-1.5 text-sm border border-gray-200 rounded-md
    focus:ring-1 focus:ring-purple-500 appearance-none
    data-calc-format="type"
    Options: Plain, Number, Currency, Percent  (all 4 preserved)

Cell 2 — Decimal Places:
  Label: block text-xs text-gray-500 mb-1  "Decimals"
  Input type="number" min=0 max=10:
    w-full px-2.5 py-1.5 text-sm border border-gray-200 rounded-md
    focus:ring-1 focus:ring-purple-500
    data-calc-format="decimals"

Cell 3 — Prefix:
  Label: block text-xs text-gray-500 mb-1  "Prefix"
  Input type="text" placeholder="e.g. $":
    w-full px-2.5 py-1.5 text-sm border border-gray-200 rounded-md
    focus:ring-1 focus:ring-purple-500
    data-calc-format="prefix"

Cell 4 — Suffix:
  Label: block text-xs text-gray-500 mb-1  "Suffix"
  Input type="text" placeholder="e.g. USD":
    w-full px-2.5 py-1.5 text-sm border border-gray-200 rounded-md
    focus:ring-1 focus:ring-purple-500
    data-calc-format="suffix"
```

### 6.7 Sample Values Preview

```
Section wrapper: px-4 py-4

Section header: text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2
  "Sample Values"

Instruction (shown when no fields referenced yet):
  text-xs text-gray-400 italic
  "Enter sample values for referenced fields to see a live preview."

Container: data-calc-sample-values space-y-2

Each JS-rendered sample row (populated by formula-editor controller):
  flex items-center gap-2
  Label: text-xs text-gray-600 w-32 truncate  (field label)
  Input: flex-1 px-2 py-1 text-xs border border-gray-200 rounded-md
    focus:ring-1 focus:ring-purple-500
    placeholder="0"

Live result display (below sample rows):
  mt-2 flex items-center gap-2
  Label: text-xs text-gray-500  "Result:"
  Value: text-sm font-semibold font-mono text-gray-900
    (formatted per format controls; populated by formula-editor controller)
```

---

## 7. Interaction Flows

### 7.1 Opening a Drawer

```
User action: clicks "Rules" tab button in toolbar
→ page-builder#switchTab fires
→ closeAllTabPanels() removes "translate-x-0", adds "translate-x-full" on all drawers
→ showTabPanel("rules") removes "translate-x-full" on rules drawer
→ Rules drawer slides in from right (CSS transition 200ms ease-out)
→ List state is visible (editor layer hidden)
→ Canvas remains partially visible to the left
```

### 7.2 Adding a New Rule

```
Starting: Rules drawer open, list state visible
User: clicks "+ Add Rule"
→ page-builder#openRuleEditor fires
→ rules_manager.js clones ruleEditorTemplate into data-drawer-editor="rules"
→ list layer hidden (data-drawer-list="rules")
→ editor layer shown (data-drawer-editor="rules")
→ Footer switches to Cancel / Save Rule
→ rule-builder controller initializes on the cloned element
→ User fills rule name, adds conditions, adds actions
→ Live summary updates in back bar
```

### 7.3 Editing an Existing Rule

```
Starting: Rules list, hovering a row
User: clicks Edit (pencil) icon
→ page-builder#editRule fires with data-rule-id
→ rules_manager loads rule data, clones editor with pre-filled values
→ Same master→detail transition as "Add" flow
```

### 7.4 Saving a Rule

```
User: clicks "Save Rule" in footer
→ page-builder#saveRule fires
→ rules_manager serializes the editor state, updates configuration_json
→ editor layer hidden, list layer shown (back to list)
→ List re-renders with updated rule (JS re-renders the list HTML)
→ Success toast (if present in existing implementation)
```

### 7.5 Cancelling (returning to list)

```
User: clicks "Cancel" or back chevron
→ page-builder#closeRuleEditor fires
→ editor layer hidden, list layer shown
→ Cloned editor element removed from DOM
→ No data changes persisted
```

### 7.6 Closing the Drawer

```
User: clicks × close button in drawer header
→ page-builder#closeAllTabPanels fires
→ translate-x-full applied to all drawers
→ Canvas becomes fully visible again
```

### 7.7 Test Mode Flow

```
Starting: Rule editor open, user has defined conditions
User: checks "Enable Test Mode" toggle
→ rule-builder#toggleTest fires
→ testPanel shown (slides in or `hidden` removed)
→ sampleInputs populated with one input per referenced field
→ User types sample values
→ rule-builder evaluates conditions, updates actionResult spans ("✓ fires" / "– skipped")
```

### 7.8 Inserting a Function (Calculations)

```
Starting: Calc editor open, formula surface focused (or not)
User: clicks a function chip (e.g. "SUM")
→ formula-editor#insertFunctionToken fires
→ Controller inserts "SUM(" at cursor position in the contenteditable surface
→ Autocomplete dropdown may appear for argument hints
→ User continues typing formula
```

### 7.9 Filtering Functions

```
User: types "ro" in the function filter input
→ formula-editor#filterFunctions fires
→ Chips with names not containing "ro" (case-insensitive) get "hidden" class
→ Only ROUND, FLOOR stay visible
→ Clearing the filter shows all chips in the active category
```

### Failure Flows

| Scenario | Behavior |
|---|---|
| Save with no conditions | "Save Rule" is allowed; rule with empty conditions is valid (existing behavior, not restricted by UI) |
| Save with no target field (calc) | "Save" button may be disabled; formula-editor controller handles validation |
| Formula syntax error | Errors block (`data-formula-editor-target="errors"`) shows red error text |
| No fields in form | Condition field select shows "Select field…" with no options; Add Condition still works |
| Drawer open on narrow viewport (mobile) | Full-width sheet (inset-0); canvas hidden behind scrim; close button always reachable |

---

## 8. Component Reuse Map

| UI Piece | Existing Component / New Component | Notes |
|---|---|---|
| Drawer chrome (header / body / footer) | **NEW**: `PageBuilder::BuilderDrawerComponent` | Shared by both features; accent prop drives indigo/purple |
| Rules list | **RESTYLE**: `PageBuilder::RulesPanelComponent` | Remove `p-5` card wrapper; adapt to drawer body padding |
| Rule editor form | **RESTYLE**: `PageBuilder::RuleEditorComponent` | Remove `fixed inset-0 bg-black/50` modal scrim; strip `max-w-2xl` centering; render as flat div |
| Condition row chips | **RESTYLE**: `PageBuilder::ConditionRowComponent` | Chip styling; all 7 value editor branches preserved |
| Calculations list | **RESTYLE**: `PageBuilder::CalculationsPanelComponent` | Remove card wrapper; adapt spacing |
| Calc editor form | **RESTYLE**: `PageBuilder::CalculationEditorComponent` | Remove modal scrim; add function inserter section |
| Pill formula surface | **RESTYLE**: `PageBuilder::FormulaPillEditorComponent` | Visual only; purple focus ring; no data-attribute changes |
| Function inserter | **NEW SECTION** inside `CalculationEditorComponent` | Not a separate ViewComponent; rendered inline in editor template with `FUNCTIONS` constant from `.rb` |
| AND/OR connector badge | **NEW PARTIAL** or inline ERB helper | Rendered between condition rows and between groups |
| Segmented AND/OR control | **NEW INLINE PATTERN** within `RuleEditorComponent` | Visually replaces `<select>`; keeps `<select>` in DOM for JS |
| Back bar in editor states | **NEW INLINE** in editor templates | Chevron + live summary; anchored at top of editor layer |

### Existing components that do NOT change

- `PageBuilder::ToolbarComponent` — toolbar tab buttons stay; only their target panels change
- `PageBuilder::CanvasComponent`
- `PageBuilder::ConditionBuilderComponent` — separate feature, untouched
- `PageBuilder::FloatingPanelComponent`
- All property panel components

---

## 9. Tailwind & Stimulus Notes

### 9.1 Typography Scale at 520px Width

```
Section labels:     text-xs font-semibold text-gray-500 uppercase tracking-wide
Body labels:        text-xs font-medium text-gray-600
Form inputs:        text-sm (px-2.5 py-1.5 for compact; px-3 py-2 for primary)
Chip selects:       text-xs (px-2 py-1)
Rule row name:      text-sm font-medium text-gray-800
Rule summary:       text-xs text-gray-400
Calc formula mono:  text-xs font-mono text-gray-500
Connector badge:    text-[10px] font-semibold
Format badge:       text-[10px] font-medium
```

### 9.2 Spacing Rhythm

```
Drawer outer padding: px-4 py-4 (all body sections)
Section dividers: border-t border-gray-100 (light dividers; border-gray-200 for stronger separation)
Between sections: py-4 (not py-6 — drawer is narrower, less vertical space needed)
Between items in a list: space-y-2
Between chips/tokens: gap-1.5
Between condition row elements: gap-1.5
```

### 9.3 Hover & Focus State Conventions

```
All interactive elements must have explicit :hover and :focus-visible states.
Never rely on browser defaults alone.

Focus rings: focus:outline-none focus:ring-2 focus:ring-{accent}-500/30 focus:border-{accent}-400
Hover backgrounds: hover:bg-gray-100 (neutral) or hover:bg-{accent}-50 (accent-tinted)
Transition: transition-colors (for color changes); transition-transform (for drawer slide)
```

### 9.4 Responsive Breakpoints

```
Default (mobile):
  Drawer: fixed inset-0 (full-width sheet)
  Scrim: fixed inset-0 bg-black/40 z-39 sm:hidden (only on mobile, behind drawer)
  Drawer z-index: z-40

sm: (≥640px):
  Drawer: fixed inset-y-0 right-0 w-[520px] max-w-[92vw]
  Scrim: hidden (sm:hidden)

The 520px target fits comfortably on any tablet (768px+) with room for canvas.
On a 1280px desktop, canvas gets 1280 - 72 (left sidebar) - 520 = ~688px — adequate.
```

### 9.5 Slide Transition

```
The drawer uses CSS transform for the open/close animation.

Hidden: translate-x-full  (slides out to the right, off-screen)
Visible: translate-x-0    (slides in to its natural position)

Transition: transition-transform duration-200 ease-out

JS changes:
  To open: element.classList.remove('translate-x-full')
           element.classList.add('translate-x-0')
  To close: element.classList.remove('translate-x-0')
            element.classList.add('translate-x-full')

The existing JS uses the `.hidden` class (display:none) for tab panels.
The drawer pattern switches from display-none to transform-based visibility.
JS must be updated to use translate classes instead of `hidden` for drawer panels.
Non-drawer panels (templates, settings, theme) keep their existing `hidden`/`fixed`
full-screen behavior — only the rules and calculations panels become drawers.
```

### 9.6 Master→Detail Transition (within drawer body)

```
The drawer body contains two stacked layers.
Transition between them uses opacity + translate for a horizontal slide feel:

List layer leaving: opacity-0 -translate-x-4 (fades + slides left)
Editor layer entering: opacity-100 translate-x-0

Or simpler (no animation, just toggle): use `hidden` on list, remove `hidden` on editor.
Simpler approach recommended since the drawer slide itself provides motion context.

JS approach:
  showEditor(key):
    listEl.classList.add('hidden')
    editorEl.classList.remove('hidden')
  showList(key):
    editorEl.classList.add('hidden')
    listEl.classList.remove('hidden')
    editorEl.innerHTML = ''  // clean up cloned editor
```

### 9.7 Stimulus Controllers Involved

| Controller | Changes Needed | New Actions |
|---|---|---|
| `page-builder` | Change `closeAllTabPanels` / `showTabPanel` from `hidden` to `translate-x-full`; add `showDrawerEditor(key)` / `showDrawerList(key)` helpers | `showDrawerEditor`, `showDrawerList` |
| `rule-builder` | No logic changes; verify selectors match restyled markup; add `setConditionsLogic` if segmented control is implemented | `setConditionsLogic` (optional) |
| `formula-editor` | Add `switchFunctionTab`, `filterFunctions`; verify or add `insertFunctionToken` | `switchFunctionTab`, `filterFunctions`, `insertFunctionToken` |
| `rules_manager` (module) | Change editor mount target (drawer body vs. modal container); update inline HTML strings to match new markup | — |
| `calculations_manager` (module) | Same as rules_manager | — |

### 9.8 Z-index Stack

```
Left sidebar: z-20
Right property panel: z-20
Toolbar: z-30
Drawers (rules, calcs): z-40
Mobile scrim: z-39
Autocomplete dropdown (formula): z-50
Modals (template preview, existing): z-50
```

---

## 10. State & Data Attribute Preservation Checklist

All of the following must survive the restyle unchanged. The frontend developer must verify each attribute is present in the new markup:

**Rules Panel:**
- `data-rules-panel` on outer div
- `data-action="click->page-builder#filterPanel"` + `data-filter-panel="rules-panel"` + `data-filter-items="rule-id"` on search input
- `data-rule-id="<id>"` on each row div
- `data-action="click->page-builder#toggleRule"` + `data-rule-id` on toggle button
- `data-action="click->page-builder#duplicateRule"` + `data-rule-id` on duplicate button
- `data-action="click->page-builder#editRule"` + `data-rule-id` on edit button
- `data-action="click->page-builder#deleteRule"` + `data-rule-id` on delete button
- `data-action="click->page-builder#openRuleEditor"` on "Add Rule" button

**Rule Editor:**
- `data-controller="rule-builder"` on editor root div
- `data-rule-builder-fields-value` + `data-rule-builder-pages-value` + `data-rule-id` on editor root
- `data-rule-builder-target="ruleName"` on name input
- `data-rule-builder-target="conditionsLogic"` on top-level logic select
- `data-rule-builder-target="conditionGroups"` on groups container
- `data-condition-group="<index>"` on each group div
- `data-group-logic="<index>"` on each group's logic select
- `data-condition-items="<index>"` on each group's items container
- `data-condition-item="<group>-<item>"` on each condition row
- `data-condition-field="<group>-<item>"` on field select
- `data-condition-operator="<group>-<item>"` on operator select
- `data-condition-value="<group>-<item>"` on value input/select
- `data-condition-value-max="<group>-<item>"` on range max input
- `data-rule-builder-target="ruleActions"` on actions container
- `data-action-item="<index>"` on each action row
- `data-action-type="<index>"` on type select
- `data-action-target="<index>"` on target select
- `data-action-value="<index>"` on value input (set_value/set_required)
- `data-rule-builder-target="actionResult"` on result span
- `data-rule-builder-target="testToggle"` on test checkbox
- `data-rule-builder-target="testPanel"` on collapsible test body
- `data-rule-builder-target="sampleInputs"` on sample inputs container
- `<template data-operators-template>` — all 16 operators
- `<template data-action-types-template>` — all 9 action types
- `data-action="click->page-builder#saveRule"` on Save button
- `data-action="click->page-builder#closeRuleEditor"` on Cancel/back

**Calculations Panel:**
- `data-calculations-panel` on outer div
- `data-filter-panel="calculations-panel"` + `data-filter-items="calculation-id"` on search
- `data-calculation-id="<id>"` on each row
- `data-action="click->page-builder#editCalculation"` on edit button
- `data-action="click->page-builder#deleteCalculation"` on delete button
- `data-action="click->page-builder#openFormulaEditor"` on Add button

**Calculation Editor:**
- `data-page-builder-target="calculationTargetField"` on target select
- `data-calc-format="type"` on format type select
- `data-calc-format="decimals"` on decimals input
- `data-calc-format="prefix"` on prefix input
- `data-calc-format="suffix"` on suffix input
- `data-calc-sample-values` on sample values container
- `data-action="click->page-builder#saveCalculation"` on Save
- `data-action="click->page-builder#closeFormulaEditor"` on Cancel/back

**Formula Pill Editor:**
- `data-controller="formula-editor"` on root div
- `data-formula-editor-fields-value` + `data-formula-editor-formula-value`
- `data-formula-editor-target="surface"` on contenteditable
- `data-action="input->formula-editor#onInput keydown->formula-editor#onKeydown"` on surface
- `data-formula-editor-target="autocomplete"` on dropdown
- `data-formula-editor-target="status"` on status span
- `data-formula-editor-target="preview"` on preview span
- `data-formula-editor-target="errors"` on errors block

**Function Inserter (new):**
- `data-fn-insert` on every chip
- `data-function="<NAME>"` on every chip
- `data-action="click->formula-editor#insertFunctionToken"` on every chip
- `data-formula-editor-target="fnGrid"` on the chips container
- `data-formula-editor-target="fnSearch"` on the filter input
- Total chip count: exactly 31 (Math:12 + Logic:5 + Text:7 + Date:7)

---

## 11. Visual Design Summary

### Color Philosophy
- Rules = indigo: intellectual, logical, structured
- Calculations = purple: mathematical, creative, powerful
- Gray remains the neutral base; green (emerald) for enabled status; amber for OR connectors and test mode; red for errors and destructive actions

### Typography Philosophy
- 520px is narrower than a full-screen panel. Use `text-xs` (12px) for all supporting text and labels. Use `text-sm` (14px) only for primary content (rule names, formula text, field labels in the target select).
- `font-mono` only for formula text and function names — never for prose.

### Whitespace Philosophy
- Compact by default (the user is in a side-by-side working state with the canvas). `py-4` between sections, `py-2`/`py-3` for less important rows. No gratuitous padding.
- The connector rail between conditions is a visual lightweight (`border-t border-gray-200`) that guides the eye without adding bulk.

### Elevation Model
- Drawer sits on `shadow-2xl` + `border-l border-gray-200` — clearly above the canvas.
- List rows are flat (`bg-white border border-gray-200`) with `hover:shadow-sm` on hover — depth appears on interaction.
- The formula editor surface has a subtle inset (white bg, border) inside the already-elevated drawer.

---

## RETURN
ux_doc: /home/ec2-user/anysys/docs/superpowers/specs/2026-06-05-rules-calculations-drawer-redesign-UI.md
surfaces:
  - name: Rules Drawer — List State
    nav_area: Maintenance/Modules
    new_components: [PageBuilder::BuilderDrawerComponent]
    reused_components: [PageBuilder::RulesPanelComponent]
  - name: Rules Drawer — Editor State
    nav_area: Maintenance/Modules
    new_components: []
    reused_components: [PageBuilder::RuleEditorComponent, PageBuilder::ConditionRowComponent]
  - name: Calculations Drawer — List State
    nav_area: Maintenance/Modules
    new_components: []
    reused_components: [PageBuilder::CalculationsPanelComponent]
  - name: Calculations Drawer — Editor State
    nav_area: Maintenance/Modules
    new_components: []
    reused_components: [PageBuilder::CalculationEditorComponent, PageBuilder::FormulaPillEditorComponent]
overall: READY_FOR_FRONTEND
notes: All four states share one BuilderDrawerComponent chrome (accent prop drives indigo vs purple). The master-to-detail transition is a simple hidden/show toggle within the drawer body — the drawer slide itself provides the motion context so no inner animation is required. Every existing data-attribute hook, JS target, and feature (all 16 operators, all 9 action types, all 4 format controls, all 31 functions) is explicitly mapped and must survive the restyle. The function inserter is an inline section of CalculationEditorComponent — not a separate ViewComponent — driven by a FUNCTIONS constant on the .rb class and two new formula-editor controller actions (switchFunctionTab, filterFunctions). The segmented AND/OR control can fall back to the styled select approach if adding a new JS action to rule_builder is out of scope.

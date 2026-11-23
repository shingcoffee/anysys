# Property Editor Refactor — UX Layout Specification

**Date:** 2026-06-12
**Author:** UX Designer agent
**Surface:** `/:cid/admin/maintenance/flowcharts/:id/edit` — right-hand 420 px property sidebar
**Design input:** `2026-06-12-property-editor-refactor-design.md`

---

## 1. Surface Inventory

| Surface | Nav Area | Element Type | Tab |
|---|---|---|---|
| Process Step tab — inline action picker (empty state) | admin | process | Steps |
| Process Step tab — committed step card (expanded) | admin | process | Steps |
| Process Step tab — committed step card (collapsed) | admin | process | Steps |
| Decision Branches tab — Add Branch modal (upgraded) | admin | decision | Steps/Branches |
| Decision Branches tab — branch card list | admin | decision | Steps/Branches |
| Loop Advanced tab — For-Each fields | admin | loop | Advanced |
| Loop Advanced tab — While/Do-While fields | admin | loop | Advanced |
| Shared: disclosure section pattern | admin | all | any |
| Shared: unified card pattern | admin | process + decision | Steps |

All surfaces live in the existing property sidebar shell (`width: 420px`, `absolute right-0 top-0 bottom-0`). No new routes or URL surfaces are introduced.

---

## 2. Layout Spec Per Surface

### 2.1 Process Step Tab — Inline Action Picker (Empty / Search State)

This replaces the old dual-dropdown quick-add row AND the cascade-dropdown step modal. The picker is the hero when no step has been committed yet.

#### Empty-Query State (tab just opened, no step committed)

```
┌─────────────────────────────────────────┐  ← steps tab pane (px-3 py-2)
│  Steps                                  │  ← buildSectionHeader (text-xs font-semibold text-slate-700)
│                                         │
│ ┌─────────────────────────────────────┐ │  ← picker wrapper (border border-slate-200 rounded-lg bg-white shadow-sm)
│ │ 🔍  Search actions…                 │ │  ← search input (text-xs px-2 py-1.5 border-0 ring-0 w-full)
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌──── results dropdown (max-h-72) ────┐ │  ← shown immediately, all categories
│ │  MODEL                              │ │  ← category heading
│ │    ● Save Model                     │ │  ← action row
│ │    ● Find Model                     │ │
│ │    ● Destroy Model                  │ │
│ │  VALIDATION                         │ │  ← next category heading
│ │    ● Validate Fields                │ │
│ │    ○ Format › Email  (disabled)     │ │  ← singleUse already used
│ │    …                                │ │
│ │                                     │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Tailwind classes:**

- Picker wrapper: `relative border border-slate-200 rounded-lg bg-white shadow-sm`
- Search input: `w-full px-3 py-1.5 text-xs text-slate-800 placeholder:text-slate-400 bg-transparent border-0 focus:outline-none focus:ring-0`
- Search icon (inside left padding): `absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400`
- Results dropdown: `absolute z-50 mt-1 w-full bg-white border border-slate-200 rounded-md shadow-lg max-h-72 overflow-y-auto`
- Category heading: `px-2.5 py-1 text-[10px] font-semibold text-slate-400 uppercase tracking-wide bg-slate-50 sticky top-0`
- Action row (default): `flex items-center gap-2 px-2.5 py-1.5 cursor-pointer hover:bg-indigo-50 group`
- Action row (keyboard-focused / `aria-selected`): `bg-indigo-50`
- Action color dot: `w-2 h-2 rounded-full bg-{color}-500 flex-shrink-0` (uses `getColorClasses(action.color)`)
- Action label: `text-xs font-medium text-slate-800 flex-1 min-w-0 truncate`
- Action breadcrumb (leaf with parent context): `text-[10px] text-slate-400 truncate` — format: `Category › Label` — only shown when query is non-empty and the match is a sub-option leaf
- Action description tooltip hint (on hover, trailing): `text-[10px] text-slate-500 max-w-[120px] truncate`
- Disabled action row: `opacity-50 cursor-not-allowed pointer-events-none`
- Disabled badge: `ml-auto text-[9px] font-medium text-slate-400 bg-slate-100 px-1 rounded`  text: "already added"

#### Filtered (Query Active) State

When query text exists, results are filtered across `label`, `description`, and `category`. Category headings only appear if at least one action in the category matches. Breadcrumb label format: `"Validate › Format › Email"` — the `›` character (U+203A) separates hierarchy levels flattened from `subOptions` trees.

#### No-Results State

```
│ ┌─────────────────────────────────────┐ │
│ │ 🔍  validate email something        │ │
│ └─────────────────────────────────────┘ │
│                                         │
│   ┌── no-results (inside dropdown) ──┐  │
│   │  No actions found for            │  │
│   │  "validate email something"      │  │
│   └───────────────────────────────────┘ │
```

No-results: `py-6 text-center text-[11px] text-slate-400`

#### Keyboard Interaction (CRITICAL — must not deviate)

| Key | Behavior |
|---|---|
| Any printable character | Focuses search input; begins filtering |
| `↓` / `↑` | Moves `aria-selected` highlight through visible rows; wraps at ends |
| `Enter` | Commits the currently highlighted action immediately — no confirm step |
| `Escape` | Clears query text; if already empty, collapses dropdown |
| `Tab` | Moves focus out of picker; dropdown closes |
| Click on row | Commits that action immediately (same as Enter) |

**CRITICAL:** Commit is immediate on Enter/click. There is no separate "Add Step" button. The commit fires `stepPicker#commit` which calls the step manager to build the card and removes the picker from the DOM.

#### Data shown

- Full `getActionsByCategory()` result tree, with `subOptions` trees flattened to leaf entries
- Each entry carries: `value`, `label`, `color`, `description`, `category` key, breadcrumb path string, `singleUse` boolean

---

### 2.2 Process Step Tab — Committed Step Card (Expanded — just-added)

When an action is committed the picker disappears and the step card renders **expanded by default** for newly-added steps. Reloaded steps (from saved config) start collapsed.

```
┌─────────────────────────────────────────┐  ← steps-container (space-y-1)
│ ╠══ [indigo border-l-2] ═══════════════╣ │  ← step card
│ │  ════ header row ════════════════════ │ │
│ │  ⠿  ●  Validate › Format › Email   ↓ │ │  ← drag handle | color dot | breadcrumb label | chevron (rotated) | Remove (hover)
│ │                            [Change] [✕]│ │  ← Change + Remove in trailing, appear on hover
│ │ ── description (if set) ──────────── │ │  ← text-[10px] text-slate-400 pl-6
│ │                                      │ │
│ │  ── config fields section ─────────  │ │  ← pl-6 space-y-2 (inside expanded body)
│ │    Format                            │ │  ← field label text-[11px] font-medium text-slate-500 mb-1
│ │   [email                          ]  │ │  ← CONFIG_INPUT_CLASSES
│ │    Template                          │ │
│ │   [Select template…              ▼]  │ │
│ │                                      │ │
│ │  ┌── Advanced ──────────── [2 overrides] ┐ │  ← disclosure section (collapsed)
│ │  │ ⌄                                    │ │
│ │  └──────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Header row Tailwind:**

```
flex items-center gap-2 px-2.5 py-2
```

- Drag handle: `flex-shrink-0 cursor-grab active:cursor-grabbing text-slate-300 hover:text-slate-500`
- Color dot: `w-2 h-2 rounded-full bg-{color}-500 flex-shrink-0`
- Breadcrumb label: `flex-1 min-w-0 text-xs font-medium text-slate-800 truncate`
- Expand/collapse chevron: `w-3 h-3 text-slate-400 transition-transform duration-150` — `rotate-90` when expanded
- Change button (hover-only): `text-[10px] font-medium text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 px-1.5 py-0.5 rounded transition-colors opacity-0 group-hover:opacity-100`
- Remove button (hover-only): `p-1 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-md opacity-0 group-hover:opacity-100 transition-all flex-shrink-0`

**Expanded body:**

```
pl-6 pt-1.5 border-t border-slate-100 space-y-2 mt-1.5
```

Config fields use existing `buildStepConfigFieldsHTML` output (unchanged). `visibleWhen` fields are evaluated against defaulted config values on first render so dependents appear correctly from the moment of commit.

**"Change" affordance behavior (CRITICAL):**

Clicking Change re-opens the inline picker in-place (the card collapses into the picker state). The existing step data is preserved and only replaced if a new action is committed. Pressing Escape on the picker restores the previous committed card unchanged.

---

### 2.3 Process Step Tab — Committed Step Card (Collapsed — reload state)

```
│ ╠══ [indigo border-l-2] ═════════════════╣
│ │  ⠿  ●  Validate › Format › Email     ▶  │  ← chevron pointing right (collapsed)
│ │                              [Change] [✕]│  ← hover only
└─────────────────────────────────────────┘
```

The body (`data-step-details`) carries `class="hidden"` on reload. Click anywhere on the header row (except action buttons) toggles expansion. The expand chevron class removes `rotate-90`.

**Advanced disclosure sub-section:**

```
┌── Advanced ─────────── [2 overrides] ──┐
│ ⌄ (chevron, rotates when open)         │  ← button: w-full flex items-center justify-between px-2.5 py-1.5
├─────────────────────────────────────────┤  ← border-t border-slate-200 (only when open)
│  ┌── 2-col grid ─────────────────────┐ │
│  │  Retry Count   [0         ]       │ │  ← grid-cols-2 gap-2 pt-2.5 px-2.5 pb-2.5
│  │  Retry Backoff [None     ▼]       │ │
│  │  Timeout (sec) [0         ]       │ │
│  │  Guard Cond.   [           ]      │ │
│  └─────────────────────────────────── ┘ │
└─────────────────────────────────────────┘
```

Override badge: `inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-[10px] font-semibold text-indigo-600 bg-indigo-50 border border-indigo-200 rounded` — hidden when count is 0.

Override count is computed as the number of these fields whose value differs from its default: `retryCount !== 0 || retryBackoff !== "none" || timeout !== 0 || guardCondition !== ""`.

---

### 2.4 Process Step Tab — Empty State (No Step)

When no step is committed and the picker is in its empty-query state, no additional empty-state component is rendered — the picker IS the empty state. The `data-steps-empty` div is removed.

---

### 2.5 Decision Branches Tab — Add Branch Modal (Upgraded)

The modal keeps its existing shell (`absolute inset-0 z-50`, `max-w-sm`, `max-h-[80vh]`). The body is restructured to add a preset chip row at the top.

```
┌──────────────────────────────────────────┐
│  ●  Add Decision Branch              [✕] │  ← header (unchanged structure)
├──────────────────────────────────────────┤
│                                          │
│  ┌── Preset ────────────────────────┐   │
│  │ [Yes] [No] [Otherwise] [Custom]  │   │  ← chip row (flex gap-1.5)
│  └──────────────────────────────────┘   │
│                                          │
│  Branch Name *                           │
│  [Active                             ]   │  ← pre-filled by chip; still editable
│                                          │
│  ─────── Condition (optional) ────────── │
│  ┌── Field Condition │ Query Count ────┐ │  ← segmented control (unchanged)
│  │ [left operand ▼] [== ▼] [value   ] │ │  ← see 2.5a
│  └──────────────────────────────────── ┘ │
│                                          │
│  Description (optional)                  │
│  [                                   ]   │
│                                          │
├──────────────────────────────────────────┤
│                   [Cancel] [Add Branch]  │
└──────────────────────────────────────────┘
```

#### 2.5a Preset Chip Row

```
<div class="flex flex-wrap gap-1.5">
  <!-- chip -->
  <button type="button" data-preset="yes" ...>Yes</button>
  <button type="button" data-preset="no" ...>No</button>
  <button type="button" data-preset="otherwise" ...>Otherwise</button>
  <button type="button" data-preset="custom" ...>Custom</button>
</div>
```

**Chip — inactive:** `px-3 py-1 text-[11px] font-medium text-slate-600 bg-white border border-slate-200 rounded-full hover:border-slate-300 hover:bg-slate-50 transition-colors`

**Chip — active/selected:** `px-3 py-1 text-[11px] font-medium text-indigo-700 bg-indigo-50 border border-indigo-300 rounded-full ring-1 ring-indigo-200`

**CRITICAL — chip behavior:** Selecting a chip pre-fills the name field and condition skeleton but does NOT lock any field. Every field remains fully editable after chip selection. Clicking the currently active chip deselects it (returns to Custom/blank state). Chips are purely a convenience pre-fill; the data collected on "Add Branch" is always whatever the live fields contain at submission time.

**Pre-fill behavior per chip:**

| Chip | Name | Left Operand | Operator | Right Operand | Condition |
|---|---|---|---|---|---|
| Yes | "Yes" | upstream signal/ctx field | `==` | `true` | Field Condition type |
| No | "No" | upstream signal/ctx field | `==` | `false` | Field Condition type |
| Otherwise | "Otherwise" | (empty) | (empty) | (empty) | no condition |
| Custom | "" | (empty) | `==` | (empty) | Field Condition type |

"Upstream signal/ctx field" = first entry from `_getParentOutputOptions()` if it exists, else `signal`.

#### 2.5b Left Operand Select (Field Condition type)

The plain text input `[data-branch-condition-left]` is replaced with a `<select>` seeded from upstream parent outputs + entity attributes + common literals. An "enter manually..." option at the bottom of the select swaps the select for a text input (same swap mechanism as the existing right-operand custom value path).

```
┌─── Field Condition ─────────────────────┐
│  [ctx.status ▼] [== ▼] [active       ] │  ← select | select | text
└──────────────────────────────────────────┘
```

Left operand select classes: `flex-1 px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-400`

When user picks "enter manually…" (`value="__manual__"`): hide the select, show a text input with `placeholder="ctx[:field]"` and a small `[▲]` button on the right to revert to select. This mirrors the existing `switchToSelectRightOperand` pattern.

**Focus order on left-operand change:** When a left operand is selected from the dropdown, focus moves automatically to the operator select. When operator is selected, focus moves to the right operand field if the operator requires one.

**CRITICAL — collect behavior:** `_collectFieldCondition` reads from whichever widget (select or manual input) is currently visible for the left operand. The select value is the option's `value` attribute; the manual input uses its `value` directly.

---

### 2.6 Decision Branches Tab — Branch Card List

```
┌─────────────────────────────────────────┐
│  Branches                         [2]   │  ← section header with count
│                                         │
│ ╠══ [amber border-l-2] ══════════════╣ │
│ │  ● Yes                           [✕] │ │  ← name | remove (hover)
│ │    ctx.status equals active         │ │  ← condition summary line
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
│ ╠══ [amber border-l-2] ══════════════╣ │
│ │  ● Otherwise                     [✕] │ │
│ │  ┌── no condition — always matches ┐ │ │  ← amber badge
│ │  └──────────────────────────────── ┘ │ │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  [+ Add Branch]                         │  ← amber-tinted full-width button
└─────────────────────────────────────────┘
```

**Condition summary line:** `text-[10px] font-mono text-slate-400 mt-0.5 pl-5` — format constructed from `BRANCH_OPERATORS` labels:
- Field condition: `"{leftOperand} {operatorLabel} {rightOperand}"` (e.g. `"ctx.status equals active"`)
- Query count: `"Count of {entityName} {countOp} {countValue}"` (e.g. `"Count of Users > 10"`)
- Unary operator: `"{leftOperand} {operatorLabel}"` (e.g. `"ctx.email is not empty"`)

**"No condition" amber badge:** `inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 bg-amber-50 border border-amber-200 rounded-full mt-0.5 ml-5`

**Add Branch button:** `mt-2 w-full inline-flex items-center justify-center px-2 py-1.5 text-xs font-medium text-amber-600 bg-amber-50 border border-amber-200 rounded hover:bg-amber-100 transition-colors`

**Empty state (no branches yet):** `buildEmptyState("No branches yet. Click \"Add Branch\" to create the first route.")` — `border border-dashed border-slate-200 rounded-md py-3 text-center text-[11px] text-slate-400`

The existing quick-add inline dropdown row (`data-branch-quick-add`) is removed. "Add Branch" modal is the only entry path.

---

### 2.7 Loop Advanced Tab — For-Each Layout

The Advanced tab pane (`data-property-editor-target="tabPaneAdvanced"`) renders loop fields. The segmented control for loop type stays at the top. Below it, fields are shown/hidden via CSS (`visibleWhen`) — no DOM removal.

```
┌─────────────────────────────────────────┐  ← loop advanced tab pane
│                                         │
│  Loop Type                              │
│  ┌─ While ─┬─ Do-While ─┬─ For-Each ──┐│  ← segmented control (existing builder)
│  └─────────┴────────────┴─────────────┘│  ← p-1 bg-slate-100 rounded-lg
│                                         │
│  ┄┄┄ [For-Each fields — visible] ┄┄┄┄ │
│                                         │
│  Collection *                           │
│  [ctx.items                         ]   │  ← required; text-xs px-2 py-1.5 border border-slate-200 bg-white rounded-md
│                                         │
│  Item Variable                          │
│  [item                              ]   │  ← auto-filled "item" on first select
│  ← Available inside the loop body as   │  ← live hint line
│    `item`                               │  ← text-[10px] text-slate-400 mt-0.5 font-mono
│                                         │
│  Index Variable                         │
│  [index                             ]   │  ← auto-filled "index" on first select
│                                         │
│  Skip Condition                         │
│  [item.nil?                         ]   │  ← ctx.placeholder hint
│                                         │
│  ┌── Options ────────────────────────┐ │  ← disclosure section (see 2.9)
│  │ ⌄  Options                        │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Auto-fill rule (CRITICAL):** When the user first selects "For-Each" and `itemVariable` is currently empty (or the field has never been touched), write `"item"` into `itemVariable` and `"index"` into `indexVariable`. If those fields already contain non-empty values, do not overwrite. This iff-empty check runs in the `handleLoopTypeChange` handler (or its replacement in the consolidated visibility manager).

**Live hint line:** `itemVariable` field is followed by a `<p>` element with `data-item-variable-hint` that reads `Available inside the loop body as \`{value}\``. The hint updates on every `input` event on the `itemVariable` field. Hint classes: `mt-0.5 text-[10px] text-slate-400` + the variable portion styled `font-mono text-slate-600`.

---

### 2.8 Loop Advanced Tab — While / Do-While Layout

```
┌─────────────────────────────────────────┐
│  Loop Type  [ While │ Do-While │ … ]   │
│                                         │
│  ┄┄┄ [While/Do-While fields] ┄┄┄┄┄┄┄  │
│                                         │
│  Loop Condition                         │
│  ┌── condition builder (amber) ────────┐│  ← existing buildConditionFieldHTML output
│  │  [signal  ▼] [==  ▼] [value     ]  ││
│  │  [+ Add Condition]                  ││
│  └─────────────────────────────────────┘│
│                                         │
│  ┌── Options ──────────────────────────┐│  ← disclosure (same pattern as For-Each)
│  │ ⌄  Options                          ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

The condition builder is the same `buildConditionFieldHTML` output used in the decision element, unchanged.

---

### 2.9 Shared: Disclosure Section Pattern

Used by: step Advanced sub-section, loop Options group.

```
┌── [label] ───────── [N badge] ──────────┐  ← border border-slate-200 rounded-md
│ ⌄  [label]             [N overrides]   │  ← button: w-full flex items-center justify-between px-2.5 py-1.5
│                                         │  ← text-xs font-medium text-slate-700
│                                         │  ← hover:bg-slate-50 rounded-md transition-colors
├── (separator, only when open) ──────────┤  ← border-t border-slate-200
│  [body content]                         │  ← hidden/shown by data-disclosure-body
│  [px-2.5 pb-2.5 space-y-2 pt-2.5]     │
└─────────────────────────────────────────┘
```

**Chevron:** `w-3.5 h-3.5 text-slate-400 transition-transform duration-150` — `rotate-180` when open.

**Badge (optional, only when count > 0):** `inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-[10px] font-semibold text-indigo-600 bg-indigo-50 border border-indigo-200 rounded`

**New template function:** `buildDisclosureSection({ label, badgeCount = 0, bodyHTML, startOpen = false })`

- Outer: `class="border border-slate-200 rounded-md"`
- Toggle button: `data-action="click->property-editor#toggleDisclosure" data-disclosure-id="{id}"`
- Body: `data-disclosure-body data-disclosure-id="{id}" class="{startOpen ? '' : 'hidden'} px-2.5 pb-2.5 border-t border-slate-200"`

---

### 2.10 Shared: Unified Card Pattern (Step + Branch)

Both step and branch items use `buildCompactItem` evolution:

```
border-l-2 border-{color}-400
px-2.5 py-2
hover:bg-slate-50
transition-colors
group
relative
```

Header row inside:
```
flex items-center gap-2
```

- Leading (drag handle or spacer): `flex-shrink-0`
- Color dot: `w-2 h-2 rounded-full bg-{color}-500 flex-shrink-0`
- Content area: `flex-1 min-w-0 cursor-pointer`
- Trailing actions: `ml-auto opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-0.5`

Trailing action buttons: `p-1 rounded-md transition-all duration-150 flex-shrink-0`
- Neutral: `text-slate-300 hover:text-slate-600 hover:bg-slate-100`
- Destructive: `text-slate-300 hover:text-red-500 hover:bg-red-50`

---

### 2.11 Empty States Per Section

| Section | Message | Icon |
|---|---|---|
| Process Step (no step) | Picker is shown directly — no separate empty state message | — |
| Decision Branches | "No branches yet. Click \"Add Branch\" to create the first route." | `plus` |
| Loop fields (no collection on For-Each) | Inline required field error ("Collection is required") on save attempt | — |

---

## 3. Interaction Flow

### 3.1 Adding a Process Step (happy path)

```
URL: /:cid/admin/maintenance/flowcharts/:id/edit
→ User clicks Process element on canvas
→ Property sidebar opens, Step tab is active
→ Picker renders in empty-query state, all categories visible in dropdown

→ User types "save"
→ Dropdown filters to: Model › Save Model, Caching › Cache Set, …

→ User presses ↓ to highlight "Save Model"
→ User presses Enter  ← COMMITS IMMEDIATELY
→ Picker disappears; step card renders EXPANDED with configFields pre-filled with defaults
→ [data-step-config] hidden input carries defaulted config JSON
→ stepAdded event dispatched → canvas auto-sync

User edits config fields inline.
User clicks header row → card collapses.
User saves → collectSteps() reads live DOM + stored config; emits JSON contract.
```

### 3.2 Changing a Committed Step

```
User hovers over committed step card → "Change" button appears
→ User clicks "Change"
→ Card body hidden; picker re-opens in empty-query state at same position
→ User picks a different action OR presses Escape
   - If new action committed: old step data replaced; new card expands
   - If Escape pressed: picker closes; previous card restores (no data change)
```

### 3.3 Expanding/Collapsing Advanced

```
User clicks "Advanced" disclosure header on expanded step card
→ Body slides open (remove "hidden")
→ Chevron rotates 180°
→ Override badge renders if any field is non-default

User types retryCount = 3
→ Override badge shows "1 override"
User saves → collectSteps() reads retryCount=3 from hidden input within card
```

### 3.4 Adding a Branch (preset — Yes)

```
User clicks Decision element on canvas
→ Property sidebar: Branches tab
→ User clicks "+ Add Branch" modal button
→ Modal opens; focus lands on Branch Name input
→ User clicks "Yes" chip
   → Name field pre-filled: "Yes"
   → Left operand select pre-filled: first parent output or "signal"
   → Operator pre-filled: "=="
   → Right operand field pre-filled: "true"
   → Name field remains focused; still editable
→ User edits name to "Approved" if desired
→ User clicks "Add Branch"
   → Modal closes
   → Branch card appears with condition summary: "signal equals true"
   → Canvas: branch process element created + connection drawn
   → branchAdded event dispatched
```

### 3.5 Failure Flows

| Failure | Behavior |
|---|---|
| Picker: entity API fails in Query Count | Dropdown shows "Could not load entities" disabled option; silent fail |
| Branch modal: name empty on submit | `_highlightFieldError` on name input (existing red ring); submit blocked |
| For-Each save: collection empty | Inline `text-[10px] text-red-500 mt-0.5` error below field; save blocked for that field only |
| Permission denied (non-admin) | No editor sidebar rendered (controller guard); no JS-level handling needed |

---

## 4. Component Reuse Map

| UI Element | Existing Component | New Component | Notes |
|---|---|---|---|
| Section header (Steps, Branches) | `PropertyEditor::SectionHeaderComponent` | — | Reuse unchanged |
| Empty state | `PropertyEditor::EmptyStateComponent` | — | Reuse unchanged |
| Compact item card (step + branch) | `buildCompactItem` (JS) / `PropertyEditor::CompactItemComponent` (server) | — | Evolve in place; add `data-change-btn` slot |
| Segmented control (loop type, condition type) | `buildSegmentedControl` (JS) / `PropertyEditor::SegmentedControlComponent` | — | Reuse unchanged |
| Inline condition builder (loop While/Do-While) | `buildInlineCondition` (JS) / `PropertyEditor::InlineConditionComponent` | — | Reuse unchanged |
| Searchable select (action picker) | existing `searchable-select` Stimulus controller | — | Already wired in `_renderDropdownLevel` level-0 path; reuse and extend |
| Disclosure section | — | `buildDisclosureSection()` in `templates.js` | New JS template function; no new ViewComponent needed unless server-rendered |
| Preset chip row | — | Inline HTML in `buildBranchModalTemplate()` | No ViewComponent; rendered by branch_manager |
| Left operand select + manual input swap | — | Inline in `buildBranchModalTemplate()` | Same swap pattern as existing right-operand custom input |
| Live item-variable hint | — | Inline `<p data-item-variable-hint>` below field | No new component; updated by Stimulus value observer |

---

## 5. Tailwind and Stimulus Notes

### 5.1 Palette and Typography Consistency

All classes must be drawn from the palette already present in `templates.js` and the existing modal HTML. No new colors may be introduced:

- **Indigo** (`indigo-50/100/200/400/500/600/700`): primary actions, step cards, picker focus rings, Change button, override badges
- **Amber** (`amber-50/100/200/400/500/600/700/800`): branch cards, branch modal, "no condition" badge, Add Branch button
- **Slate** (`slate-50/100/200/300/400/500/600/700/800/900`): all neutral text, borders, backgrounds, labels
- **Red** (`red-50/500`): remove buttons (hover state only), required field error text
- Per-action colors (`emerald`, `blue`, `green`, `indigo`, `amber`, `red`, `purple`, `cyan`, `pink`, `teal`): color dots and accent border on cards, sourced from `getColorClasses()`

Typography scale in use (must not deviate):
- Section labels: `text-xs font-semibold text-slate-700`
- Field labels: `text-[11px] font-medium text-slate-500`
- Card titles: `text-xs font-medium text-slate-800`
- Subtitles / hints: `text-[10px] text-slate-400` or `text-[10px] text-slate-500`
- Category headings in picker: `text-[10px] font-semibold text-slate-400 uppercase tracking-wide`
- Action labels in picker: `text-xs font-medium text-slate-800`
- Breadcrumb path in picker: `text-[10px] text-slate-500`
- Input text: `text-xs`
- Buttons (primary): `text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700`
- Buttons (secondary): `text-xs font-medium text-slate-600 bg-white border border-slate-200 rounded-md hover:bg-slate-50`

### 5.2 Stimulus Controllers

Three Stimulus controllers are involved; no new controller files are required — only extensions to existing controllers:

**`property-editor` (main controller, already exists)**

New actions/values needed:

| Action | Handler | Trigger |
|---|---|---|
| `stepPickerCommit` | receives committed `{action, selectionPath, breadcrumb}` from searchable-select | custom event from searchable-select |
| `stepPickerEscape` | restores previous card if picker was opened via "Change" | Escape key in picker |
| `changeStep` | opens picker in-place for a committed step | "Change" button click on card |
| `toggleDisclosure` | open/close a disclosure section body | click on disclosure header |
| `updateItemVariableHint` | updates `data-item-variable-hint` text | `input` event on itemVariable field |
| `applyBranchPreset` | pre-fills modal fields from chip | click on preset chip |
| `swapLeftOperandToManual` | hide select, show text input | "enter manually…" selection |
| `swapLeftOperandToSelect` | hide text input, show select | revert button click |

The existing `handleLoopTypeChange` DOM-walking logic is replaced by a call to the consolidated `visibleWhen` evaluator already present in `handleConfigFieldChange`, meaning loop type change triggers a `change` event on the `loopType` field, which the existing visibility loop processes. The auto-fill logic for `itemVariable` / `indexVariable` moves into `updateItemVariableHint` (which also handles auto-fill as a side effect of the first For-Each selection when the field is empty).

**`searchable-select` (already exists)**

The existing controller already powers the level-0 action dropdown in the step modal. For the inline picker it is used directly: the picker IS the searchable-select mount point. The controller dispatches a custom `searchable-select:commit` event upward when a leaf is selected; `property-editor#stepPickerCommit` listens for it.

No changes to the controller itself; the commit event was already dispatched — it just needs to be listened to at the `property-editor` level.

**`context-autocomplete` (already exists)**

Used on config text/textarea fields inside expanded step cards (`data-controller="context-autocomplete"`). No changes.

### 5.3 Responsive Safety

The sidebar is fixed at 420px by the shell (`style="width: 420px"`). All inner layouts must work within that constraint:

- No fixed widths on inner elements — use `w-full`, `flex-1`, `min-w-0` to let content flow
- Truncate long action labels with `truncate` on `text-xs` spans
- The picker dropdown uses `max-h-72 overflow-y-auto` — safe within the sidebar height
- The branch modal uses `max-w-sm` and `max-h-[80vh]` — already responsive-safe
- All `grid` layouts use `grid-cols-2 gap-2` maximum — no 3-column grids inside the sidebar
- The preset chip row uses `flex flex-wrap gap-1.5` — chips wrap naturally if sidebar is narrowed below 420px via the resize handle

---

## 6. Critical Implementation Flags

The following details must not be inferred or approximated by the frontend developer:

1. **Picker commits on Enter/click immediately** — no confirm button. The `addStepFromModal` path (modal + submit button) is deleted.

2. **"Change" button restores on Escape** — the previous committed step data must be snapshot-preserved before the picker opens, and restored if Escape is pressed without committing.

3. **Preset chips pre-fill only** — clicking a chip is not a commit. The modal "Add Branch" button is still required. Fields remain editable after chip selection. Clicking the active chip again deselects it.

4. **Left operand select → "enter manually…" swap** — the escape hatch is an option with `value="__manual__"` at the bottom of the left-operand select. The swap hides the select and shows a text input; a `[▲]` button reverts. `_collectFieldCondition` reads whichever is visible.

5. **Loop type fields are CSS-hidden, never DOM-removed** — all loop field values survive round-trips when switching loop type. The `visibleWhen` evaluator handles show/hide; `handleLoopTypeChange` must NOT remove or re-create DOM nodes.

6. **Auto-fill itemVariable / indexVariable iff-empty** — only auto-fills on first selection of For-Each when the fields are currently empty. Never overwrites a previously entered value.

7. **Override badge count logic** — badge shows N where N = count of (retryCount !== 0, retryBackoff !== "none", timeout !== 0, guardCondition !== ""). Badge is hidden (not rendered as 0) when N is 0.

8. **singleUse disabled styling** — disabled action rows in the picker must still be visible (opacity-50) so the user knows the action exists but cannot be re-added. Do not omit them from the result list.

9. **Condition summary refreshes immediately** — after the branch modal closes successfully, the branch card's condition summary line is built fresh from the collected condition object before the card is inserted into the DOM. No deferred refresh.

10. **`buildDisclosureSection` is a new JS template function in `templates.js`** — it is NOT a new ViewComponent. The Advanced sub-section on step cards and the Options group on loop cards both use this single function, ensuring visual parity.

---

```
## RETURN
ux_doc: /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/docs/superpowers/specs/2026-06-12-property-editor-refactor-ux.md
surfaces:
  - name: Process Step tab — inline action picker
    nav_area: admin
    new_components: []
    reused_components: [searchable-select Stimulus controller, buildEmptyState, buildSectionHeader]
  - name: Process Step tab — committed step card (expanded + collapsed)
    nav_area: admin
    new_components: [buildDisclosureSection (JS template function)]
    reused_components: [buildCompactItem, buildStepConfigFieldsHTML, getColorClasses, PropertyEditor::CompactItemComponent]
  - name: Decision Branches tab — Add Branch modal (upgraded with preset chips + left-operand select)
    nav_area: admin
    new_components: []
    reused_components: [buildBranchModalTemplate, buildSegmentedControl, buildInlineCondition]
  - name: Decision Branches tab — branch card list
    nav_area: admin
    new_components: []
    reused_components: [buildBranchItemTemplate, buildCompactItem, buildEmptyState, buildSectionHeader]
  - name: Loop Advanced tab — For-Each fields with live hint + disclosure
    nav_area: admin
    new_components: [buildDisclosureSection (JS template function)]
    reused_components: [buildSegmentedControl, SegmentedControlComponent]
  - name: Loop Advanced tab — While/Do-While fields
    nav_area: admin
    new_components: []
    reused_components: [buildConditionFieldHTML, buildDisclosureSection]
overall: READY_FOR_FRONTEND
notes: All surfaces live inside the existing 420px sidebar shell — no new routes, URL areas, or ViewComponent classes are needed. The only new JS artifact is buildDisclosureSection() in templates.js. The key design risks are: (1) the immediate-commit behavior of the picker which differs fundamentally from the old modal flow, (2) the iff-empty auto-fill for For-Each variables, and (3) the Escape-to-restore mechanic on "Change". These are flagged as critical implementation flags in section 6 of the spec. All Tailwind classes are sourced exclusively from the existing palette in templates.js; no new colors or type sizes are introduced.
```

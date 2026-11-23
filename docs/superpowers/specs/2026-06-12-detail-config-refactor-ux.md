# Detail-Config Layer Refactor (Round 2) — UX Layout Specification

**Date:** 2026-06-12
**Author:** UX Designer agent
**Surface:** `/:cid/admin/maintenance/flowcharts/:id/edit` — right-hand 420 px property sidebar (detail layer only)
**Design input:** `2026-06-12-detail-config-refactor-design.md`
**Round-1 reference:** `2026-06-12-property-editor-refactor-ux.md`

---

## 0. Design System Anchor

All decisions in this document are additive on top of the round-1 spec. The palette, typography scale, disclosure section pattern (`buildDisclosureSection`), compact-item card pattern (`buildCompactItem`), CONFIG_INPUT_CLASSES, and general spacing rhythm are taken as fixed givens and are not re-specified here except where this round modifies them.

---

## 1. Surface Inventory

All surfaces below live inside the existing 420 px property sidebar. No new routes, URL areas, or ViewComponent classes are introduced.

| Surface | Nav Area | Affected Element Type | New in Round 2 |
|---|---|---|---|
| Step config — variable-pick icon button on text inputs | admin | process | Yes |
| Step config — entity column select with manual swap | admin | process | Yes |
| Step config — "More options" progressive disclosure | admin | process | Yes |
| Step config — semantic KV-list placeholders | admin | process | Yes |
| Step config — resultVar auto-suggest pre-fill | admin | process | Yes |
| Decision/Loop condition builder — unified row with variable buttons | admin | decision, loop | Yes |
| Query-count WHERE row key — column select with manual swap | admin | decision | Yes |

---

## 2. Layout Spec Per Surface

### 2.1 Variable-Pick Icon Button

The button is rendered **inside** every `text` and `textarea` config input that matches the variable-reference key pattern (`*Var`, `*Variable`, `*Key`, `*Expression`, `collection`, `sourceField`, `targetField`). The button is purely additive: the input remains a fully functional free-text field. The button is a shortcut to open the context-autocomplete dropdown.

#### 2.1a Input Wrapper Structure

Because the button must sit inside the visible input border, the current bare `<input>` must become a `relative` wrapper div with the input inside and the button absolutely positioned on the right edge.

```
┌─────────────────────────────────────────────────────┐
│  Target Variable *                                  │  ← label (unchanged)
│                                                     │
│ ┌──────────────────────────────────────── [  {x} ] ─┐ │
│ │  ctx[:user]                                       │ │  ← input (pr-7 to avoid underlap)
│ └─────────────────────────────────────────────────── ┘ │
└─────────────────────────────────────────────────────┘
```

**Wrapper div:** `relative`

**Input — modified classes (diff from CONFIG_INPUT_CLASSES):**
The only change is `pr-7` (instead of the implicit `pr-2` from `px-2`). Full classes:
```
w-full pl-2 pr-7 py-1.5 text-xs border border-slate-200 bg-white rounded-md
placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20
focus:border-indigo-400
```

**Variable-pick button (absolute, inside wrapper):**
```
absolute right-0.5 top-1/2 -translate-y-1/2
flex items-center justify-center
w-5 h-5
text-slate-400 hover:text-indigo-600 hover:bg-indigo-50
rounded
transition-colors
cursor-pointer
```

The glyph is `{x}` rendered as text (`text-[10px] font-mono font-bold`) rather than an SVG, for compactness at the 20×20 target:

```html
<button type="button"
        tabindex="-1"
        title="Insert variable"
        data-action="click->context-autocomplete#picker"
        class="absolute right-0.5 top-1/2 -translate-y-1/2 flex items-center
               justify-center w-5 h-5 text-[10px] font-mono font-bold
               text-slate-400 hover:text-indigo-600 hover:bg-indigo-50
               rounded transition-colors">
  {x}
</button>
```

`tabindex="-1"` keeps Tab navigation on the input; the button is reachable by mouse or programmatic focus only. This avoids disrupting the existing Tab flow through config fields.

#### 2.1b Hover / Focus States

| State | Input border | Button appearance |
|---|---|---|
| Input idle | `border-slate-200` | `text-slate-400` |
| Input focused | `border-indigo-400 ring-2 ring-indigo-500/20` | `text-indigo-500` (same transition) |
| Button hovered | (unchanged) | `text-indigo-600 bg-indigo-50` |
| Button active/pressed | (unchanged) | `text-indigo-700 bg-indigo-100` (add `active:bg-indigo-100 active:text-indigo-700`) |

The button does NOT get its own focus ring (tabindex=-1 prevents focus via keyboard). If accessibility is extended later, add `focus-visible:ring-1 focus-visible:ring-indigo-400`.

#### 2.1c Dropdown Anchor and Trigger Mechanics

When the button is clicked, it calls `context-autocomplete#picker`. That action must:

1. Set `_filteredGroups` to the **full unfiltered** variable list (empty prefix match = all groups).
2. Call `_renderDropdown()` — which uses the existing `_positionDropdown()` to anchor below/above the input element (not the button), using `this.element.getBoundingClientRect()`. The dropdown already handles the above-or-below flip via the existing `spaceBelow` logic. No positional change is needed.
3. Move browser focus back to the input after the dropdown opens, so keyboard navigation (↓/↑/Enter/Escape) works immediately.

The keystroke-typed path is completely unchanged. The button is a second entry point into the same existing dropdown mechanism.

**CRITICAL:** `_selectOption` replaces the word at cursor. When the picker-button is clicked on an **empty** input (value `""`), `_selectOption` inserts at position 0, producing the selected variable as the full input value. When the input already has text, it replaces the word under the cursor (or appends at cursor if cursor is between words). This is the existing `_selectOption` behavior — no change needed.

#### 2.1d "Used in this element" Group

The design spec (section A of the design doc) introduces a new group "Used in this element" at the **top** of the dropdown when there are sibling-step result variables available.

Dropdown group render order when picker-button is clicked:
1. **Used in this element** — sibling steps' `resultVar` / `outputKey` / `targetVariable` values collected from the live DOM via `collectSteps()` sibling scan. Only shown if at least one sibling step has a non-empty result variable.
2. Existing groups from `getAvailableVariables()` in their current order (Always Available / From `<element>` / From `<step>` / etc.).

Group header styling — same as existing groups:
```
px-2 py-1 text-[10px] font-semibold text-slate-500 uppercase tracking-wide bg-slate-50 sticky top-0
```

Group label text: `"Used in this element"`

Each entry in this group: same `.context-autocomplete-option` row styling as existing options.

#### 2.1e Empty / No-Variables State

If `getAvailableVariables()` returns zero items AND there are no sibling-step variables:

```
┌────────────────────────────────────────┐
│  No variables available                │  ← text-[11px] text-slate-400 italic px-3 py-2
└────────────────────────────────────────┘
```

This replaces the existing "No matching variables" string for the picker-button trigger path. The keystroke path continues showing "No matching variables" (different intent: user typed something with no match vs. the system genuinely has nothing).

#### 2.1f textarea Fields

The same wrapper-and-button pattern applies to `textarea` config fields that match the variable-reference key pattern. The button sits at `top-1.5 right-0.5` (not vertically centered, since the textarea height varies). The `top-1/2 -translate-y-1/2` centering is replaced with `top-2 right-0.5` for textareas.

**CRITICAL:** `_getWordAtCursor` already works on textareas (uses `selectionStart`). No textarea-specific changes needed.

---

### 2.2 Entity Column-Select with Manual Swap

Used in two contexts:
- **(a)** Step config fields annotated `entityField: true` in the configSchema (e.g., `findField`, `distinctField`, `groupBy`, `aggregateField`, `filterField`, `sortField`, `groupField`).
- **(b)** Query-count WHERE row key side (the `data-qc-where-field` select in `_addQueryCountWhereRow`).

#### 2.2a Normal State — Column Select Available

When `canvas.entityAttributes` provides a bound entity (context a) or after `_selectedEntitySchema` is populated (context b), the field renders as a `<select>` pre-populated with column names, followed by an "enter manually…" escape hatch at the bottom.

```
┌── Step config field (entityField annotation) ─────┐
│  Find Field *                                      │
│                                                    │
│ ┌───────────────────────────────────────── [  ▼ ]─┐│
│ │  email                                          ││  ← <select> data-entity-column-select
│ └────────────────────────────────────────────────── ┘│
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
└────────────────────────────────────────────────────┘
```

**Column select classes** (same as existing selects in the modal — already established for `data-branch-condition-left-select`):
```
w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md shadow-sm
focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400
```

(Using `indigo` focus ring for step config fields; `amber` focus ring for the query-count WHERE context — matches the amber tone of the branch modal panel.)

**Option structure:**
```html
<option value="">Select column…</option>
<!-- entity columns seeded from entityAttributes / _selectedEntitySchema -->
<option value="email">email</option>
<option value="name">name</option>
…
<optgroup label="Other">
  <option value="__manual__">enter manually…</option>
</optgroup>
```

"enter manually…" uses `value="__manual__"` consistent with the existing left-operand swap pattern in `buildBranchModalTemplate`.

#### 2.2b Manual Input Swap (escape hatch)

Selecting "enter manually…" hides the select and shows a text input in the same slot, plus a revert button.

```
┌── After swap ─────────────────────────────────────┐
│  Find Field *                                      │
│                                                    │
│ ┌──────────────────────────────── [{x}] [▲] ──┐  │
│ │  custom_column_name                          │  │  ← text input (flex-1) + var-pick btn + revert
│ └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

**Wrapper for swappable area:** `relative flex gap-1`

**Manual text input classes:**
```
flex-1 min-w-0 px-2 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded-md
shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1
focus:ring-indigo-500 focus:border-indigo-400
```

(`font-mono` signals raw field name entry; same pattern as `data-branch-condition-left`.)

**Revert button (▲ = switch back to select):**
```
px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200
rounded hover:bg-slate-50 flex-shrink-0
```

Glyph: `&#x25B2;` (up-pointing triangle) — identical to the existing `swapLeftOperandToSelect` revert button in the branch modal.

**Data attribute layout (markup skeleton):**
```html
<!-- Normal state (select visible) -->
<div data-entity-field-wrapper>
  <select data-entity-column-select
          data-action="change->property-editor#handleEntityColumnSelectChange"
          class="…">
    …
  </select>
  <!-- Manual input (hidden by default) -->
  <div data-entity-manual-wrap class="hidden relative flex gap-1">
    <input type="text"
           data-config-input="<field.key>"
           data-entity-column-manual
           placeholder="column name"
           class="…">
    <!-- variable-pick button follows the 2.1a pattern here too -->
    <button type="button" tabindex="-1" title="Insert variable"
            data-action="click->context-autocomplete#picker"
            class="… absolute right-7 …">
      {x}
    </button>
    <button type="button"
            data-action="click->property-editor#swapEntityColumnToSelect"
            class="px-2 py-1 text-[10px] …">
      &#x25B2;
    </button>
  </div>
</div>
```

**CRITICAL — data-config-input placement:** The `data-config-input="<field.key>"` attribute lives on the text input inside `data-entity-manual-wrap`, not on the select. When the select is visible, `handleEntityColumnSelectChange` copies the selected value to a hidden input with `data-config-input="<field.key>"`. When the manual input is visible, `data-config-input` is read directly. This ensures `collectSteps()` reads from exactly one element regardless of which widget is active.

**Alternative (simpler) approach the frontend developer may prefer:** Keep a hidden `<input data-config-input="<field.key>" type="hidden">` always present; both the select handler and the manual input's `input` event update it. This avoids conditional reading logic in `collectSteps()`.

#### 2.2c Degraded State — Schema Unavailable

When `canvas.entityAttributes` is absent (no bound entity) or the entity API returns an error, the field degrades silently to the existing plain text input (`buildConfigTextField` output, unchanged). No amber warning is shown inline — error handling is invisible to avoid visual noise on every non-entity-bound flowchart.

**Exception — query-count WHERE key side:** After an entity is selected and the API fetch fails, an amber inline hint appears beneath the WHERE rows container (not per-row):

```
┌── WHERE Filters ────────────────────────────┐
│  [plain text input    ] [op ▼] [value     ] │  ← fallback row (plain inputs)
│                                              │
│  ⚠ Schema unavailable — enter field names   │  ← amber hint text
│    manually                                  │
└──────────────────────────────────────────────┘
```

**Amber hint text:**
```
mt-1 flex items-center gap-1 text-[10px] text-amber-700
```

Amber warning icon (inline SVG `w-3 h-3`). Text: `"Schema unavailable — enter field names manually"`.

This amber state appears only in the query-count panel, where the user has explicitly chosen an entity and the fetch failed. In step config entityField context, the field just shows a plain text input with no annotation (the fetch never happens — it relies on `canvas.entityAttributes` which is pre-loaded).

---

### 2.3 Progressive Disclosure in Step Config Fields

For actions with more than 6 configSchema fields, `buildStepConfigFieldsHTML` partitions them into a core group (rendered flat) and a "More options" disclosure (collapsed by default). This disclosure sits **between** the core fields and the existing "Advanced" disclosure in the step card body.

#### 2.3a Partition Heuristic

- Fields with `group: "core"` annotation → always core.
- Fields with `group: "advanced"` annotation → always "More options".
- Otherwise (no annotation):
  - `required: true` AND no `visibleWhen` → core.
  - All remaining fields → "More options".
- If the action has ≤ 6 fields total (counting only currently visible fields) → render flat, no disclosure.

The `group` annotation is a new schema-only hint; it is never written to the saved config JSON.

#### 2.3b Layout Inside the Step Card Body

The step card expanded body (`data-step-details`) already has `pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-2`. The section order from top to bottom is:

```
┌── Step card expanded body ──────────────────────────────┐
│ pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-2 │
│                                                          │
│  ┌── Core fields (flat) ──────────────────────────────┐ │
│  │  Query Type                                         │ │  ← always-visible fields
│  │  [where         ▼]                                  │ │
│  │  Result Variable                                    │ │
│  │  [models           {x}]                             │ │  ← var-pick on resultVar
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌── More options disclosure ─────────── [3 set] ─────┐ │  ← "More options" label
│  │ ⌄  More options                          [3 set]   │ │  ← collapsed by default
│  ├─────────────────────────────────────────────────────┤ │
│  │  [body: non-core fields — space-y-2 pt-2.5 px-2.5  │ │
│  │   pb-2.5]                                          │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌── Advanced disclosure ────────── [2 overrides] ────┐ │  ← round-1 existing
│  │ ⌄  Advanced                        [2 overrides]   │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

**"More options" disclosure is identical in markup to "Advanced"** — it uses the existing `buildDisclosureSection()` function with:
- `id`: `step-more-${stepIndex}`
- `label`: `"More options"`
- `badgeHTML`: built via a new `buildSetCountBadge(count)` function (see 2.3c)
- `startOpen`: `false`

The `space-y-2` gap in the body ensures the three sections (core fields, More options disclosure, Advanced disclosure) are visually separated without extra margin.

#### 2.3c "(N set)" Badge for "More options"

The "More options" badge counts how many fields inside the disclosure have a **non-default value** (i.e., the current config value differs from `field.default ?? ""`). This mirrors the existing "N overrides" badge on Advanced.

**Badge function:** `buildSetCountBadge(count)` — distinct from `buildOverrideBadge` because the label text differs and the badge must be hidden at 0 (same rule).

```
Badge — hidden at 0:
  (nothing rendered)

Badge — N > 0:
  <span data-set-count-badge
        class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5
               text-[10px] font-semibold text-slate-600 bg-slate-100 border
               border-slate-200 rounded hidden">
    0 set
  </span>

Badge — rendered visible (count > 0):
  class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5
         text-[10px] font-semibold text-slate-600 bg-slate-100 border
         border-slate-200 rounded">
  3 set
```

Using `slate` (not `indigo`) intentionally distinguishes "set non-default" from "Advanced overrides" (indigo) at a glance. The label is `"N set"` (not "N override(s)").

#### 2.3d Disclosure-State Persistence

Open/closed state for "More options" (and "Advanced") persists within the page session (not across page loads). Key: `"step-more-${stepId}"` and `"step-advanced-${stepId}"` in a module-level `Map<string, boolean>` in `templates.js` (or the step manager). State is cleared when the element is closed.

**CRITICAL:** On step card first-render (newly committed step), both disclosures render collapsed (`startOpen: false`) regardless of badge count. The badge gives enough information at-a-glance without auto-opening.

#### 2.3e Interaction with visibleWhen

`visibleWhen` fields continue to work inside both the core group and the "More options" body unchanged. The partition assignment happens at render time based on the full schema; `visibleWhen` only affects visibility, not partition.

If a `visibleWhen` field is in "More options" and its controlling field is in core, changing the core field correctly triggers re-evaluation of `visibleWhen` in the disclosure body regardless of open/closed state (the body is `hidden` via CSS, not removed from DOM).

---

### 2.4 Semantic KV-List Placeholders

This is a visual-only change to `buildConfigKeyValueList`. The existing row structure and layout are **unchanged**. Only the placeholder text on the two input elements changes.

#### Current (hardcoded):

```
[Key        ] [Value      ] [✕]
```

#### After (honoring schema hints):

```
[field name ] [ctx[:value]] [✕]   ← example for "conditions" KV field
[source key ] [target key ] [✕]   ← example for "fieldMappings"
[header name] [ctx[:val]  ] [✕]   ← example for "headers"
```

**Schema hint fields (new, rendering-only, never serialized):**
- `keyPlaceholder: string` — overrides `"Key"` placeholder on the key input
- `valuePlaceholder: string` — overrides `"Value"` placeholder on the value input

**Tailwind change:** None. The existing `placeholder:text-slate-400` already styles placeholders correctly. Only the string content changes.

**buildConfigKeyValueList signature change (additive):**
```js
function buildConfigKeyValueList(field, value) {
  const keyPlaceholder   = field.keyPlaceholder   ?? "Key"
  const valuePlaceholder = field.valuePlaceholder  ?? "Value"
  // … rest unchanged
}
```

**Recommended placeholder values for existing KV-list fields:**

| configSchema key | keyPlaceholder | valuePlaceholder |
|---|---|---|
| `conditions` | `field name` | `value or ctx[:ref]` |
| `bindings` | `param name` | `ctx[:source]` |
| `computedFields` | `field name` | `Ruby expression` |
| `fieldAssignments` | `model attribute` | `ctx[:value]` |
| `fieldMappings` | `source key` | `target key` |
| `renameMap` | `old key` | `new key` |
| `headers` | `header name` | `ctx[:value]` |
| `arrayValue` | `index` | `value` |
| `hashValue` | `key` | `value` |
| `fieldsToRemove` | `field name` | `(leave blank)` |

These are applied by annotating the relevant entries in `model_actions.js`, `data_actions.js`, etc. — adding `keyPlaceholder` / `valuePlaceholder` properties to the existing configSchema objects. Zero serialization impact.

---

### 2.5 resultVar Auto-Suggest Pre-Fill

No new chrome. The field renders identically to any other text input — it just arrives pre-filled.

#### Pre-fill rules (on step commit):

1. If the configSchema entry for the output variable has a `default` value (e.g., `default: "model"`), use that.
2. If no `default`, derive from the action key: `find_model` → `"model"`, `query_models` → `"models"`, `calculate` → `"result"`, `transform` → `"result"`. Derivation rule: take the part before `_model` / `_models` if present; otherwise use the action key with underscores as-is, truncated to the first word.
3. Collision check: scan sibling steps for existing `resultVar` values. If a collision is found, append `_2`, then `_3`, etc.
4. The pre-filled value is immediately editable. Once the user edits the field, the auto-derive logic must not overwrite it again (dirty-flag check, same `iff-empty` discipline as round-1 For-Each auto-fill).

**Subtle "auto" hint: none.** The field just shows the pre-filled value. No `(auto)` suffix, no placeholder-style annotation. Rationale: the value is correct and immediately editable; adding metadata to the input would imply the user cannot own the value, which contradicts the design goal of "immediately editable". The round-1 For-Each `item` / `index` auto-fill follows the same invisible-fill pattern.

The variable-pick button (`{x}`) IS present on `resultVar` fields (the key matches `*Var` pattern). This gives the user a way to pick a sibling output variable if they want to reuse one — additive.

---

### 2.6 Condition-Builder Unification — Unified Row Recipe

The same condition row anatomy is reused across three surfaces:
- **Decision main condition** (field condition in the branch modal `[data-branch-condition-field-panel]`)
- **Branch modal — field condition row** (same panel, same markup)
- **Loop while/do-while condition** (`buildConditionFieldHTML` / `buildInlineCondition`)

The existing `buildInlineCondition` in `templates.js` already produces a correct 3-part row (`left text | operator select | right text`). This round **adds variable-pick buttons** to the left and right text inputs.

#### 2.6a Unified Row Structure (ASCII)

```
┌── condition row (relative p-2 bg-white rounded border border-amber-100) ─┐
│                                                                            │
│  ┌── left operand ────────────── [{x}]─┐  [op ▼]  ┌── right ──── [{x}]─┐ │
│  │  ctx[:field]                        │  [== ▼]  │  true              │ │
│  └─────────────────────────────────────┘          └────────────────────┘ │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

Layout: `flex items-center gap-1.5` on the row interior.

**Left operand slot (flex-1):** `relative` wrapper div containing:
- Text input (`flex-1`, `pr-7`, `font-mono`) — OR — select when using the left-operand select in the branch modal field-condition panel.
- Variable-pick button (`{x}`, absolute, `right-0.5 top-1/2 -translate-y-1/2`) — only when the slot is a text input, not when it is a select.

**Operator select (`w-16`):** unchanged from existing code.

**Right operand slot (flex-1):** `relative` wrapper div containing:
- Text input OR select (existing right-operand select / custom-input swap pattern) — unchanged.
- Variable-pick button (`{x}`) only on the **custom text input** path, not on the right-operand select.

**Tailwind for each input in the row (matches existing `buildInlineCondition` output):**
```
flex-1 min-w-0 pl-2 pr-7 py-1.5 text-xs font-mono bg-white border border-slate-200
rounded shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1
focus:ring-amber-500 focus:border-amber-500
```

(`amber` focus ring in condition builders vs `indigo` in step config fields — preserves the existing amber/indigo color semantics.)

#### 2.6b Branch Modal — Field Condition Panel Specific

The existing `[data-branch-condition-field-panel]` uses a select for the left operand (`[data-branch-condition-left-select]`) and a plain text input for the right (`[data-branch-condition-right]`). Round 2 adds the variable-pick button to the **right-operand text input only** (left operand is already a select; variable-pick buttons are not placed on selects).

The right-operand text input in the branch modal currently lacks `pr-7`. This must be added when the variable-pick button is added. The wrapper div around the input must become `relative`:

```
Before (existing):
  <input type="text" data-branch-condition-right placeholder="value" class="flex-1 …">

After (round 2 addition):
  <div class="relative flex-1">
    <input type="text" data-branch-condition-right placeholder="value"
           data-controller="context-autocomplete"
           data-context-autocomplete-element-id-value="…"
           class="w-full pl-2 pr-7 py-1.5 text-xs font-mono bg-white border
                  border-slate-200 rounded shadow-sm placeholder:text-slate-400
                  focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
    <button type="button" tabindex="-1" title="Insert variable"
            data-action="click->context-autocomplete#picker"
            class="absolute right-0.5 top-1/2 -translate-y-1/2 flex items-center
                   justify-center w-5 h-5 text-[10px] font-mono font-bold
                   text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 rounded">
      {x}
    </button>
  </div>
```

#### 2.6c Loop Condition Builder (buildInlineCondition / buildConditionFieldHTML)

Both the existing `buildInlineCondition` (used for the loop simple condition) and the multi-row `buildConditionFieldHTML` (used for decision element conditions with AND/OR) need the variable-pick buttons added to their left and right text inputs.

For `buildConditionFieldHTML` row (`_buildConditionRowHTML`), the **left-operand slot** is currently a select (`data-condition-left-operand`). The variable-pick button is NOT added to the left-operand select. The right-operand custom input (`data-condition-right-operand-custom`) is a text input — add the variable-pick button there.

For `buildInlineCondition`, both `data-condition-left` and `data-condition-right` are text inputs — both get the variable-pick button.

**Focus management after operator change:** When the operator select changes to a unary operator (`is_empty`, `is_not_empty`, `is_true`, `is_false`, `is_nil`), the right operand container is hidden. Focus should move to the **Add Condition** button or the next interactive element — not trap in the now-hidden right operand. This is handled by the existing `handleConditionOperatorChange` handler; no UX change needed, just a reminder not to break it.

---

### 2.7 Query-Count WHERE Row Key — Column Select with Manual Swap

The existing `_addQueryCountWhereRow` renders `data-qc-where-field` as a `<select>` seeded from `_selectedEntitySchema`. This is **already a column select**. Round 2 adds the "enter manually…" escape hatch to this existing select.

#### Before (existing):

```
┌── [field select ▼] ──┐  [op ▼]  [value    ]  [✕]
└───────────────────────┘
```

#### After (round 2):

```
┌── [field select ▼] ──┐  [op ▼]  ┌── [value {x}] ───┐  [✕]
└───────────────────────┘           └──────────────────┘
```

"enter manually…" escape hatch is added as an `<optgroup>` item at the bottom of `data-qc-where-field`:

```html
<select data-qc-where-field …>
  <option value="">Select field…</option>
  … entity columns …
  <option value="created_at">created_at</option>
  <option value="updated_at">updated_at</option>
  <optgroup label="Other">
    <option value="__manual__">enter manually…</option>
  </optgroup>
</select>
<!-- manual input (hidden until __manual__ selected) -->
<div data-qc-where-field-manual class="hidden flex gap-1">
  <input type="text"
         data-qc-where-field-input
         placeholder="column name"
         class="flex-1 min-w-0 px-2 py-1.5 text-xs font-mono bg-white border
                border-slate-200 rounded shadow-sm focus:outline-none
                focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
  <button type="button"
          data-action="click->property-editor#swapQcWhereFieldToSelect"
          class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700
                 border border-slate-200 rounded hover:bg-slate-50 flex-shrink-0">
    &#x25B2;
  </button>
</div>
```

The variable-pick button (`{x}`) is added to `data-qc-where-value` (the value input, rightmost column), following the section 2.1a pattern. The `context-autocomplete` controller needs the `elementId` value; in this context it is the decision element's ID, available on `this.controller.currentElement.id`.

**Amber schema-unavailable fallback** (from 2.2c): If the entity fetch fails after entity selection, the WHERE rows are not added. An amber hint below `[data-branch-qc-where-rows]` explains the degradation. No per-row change.

---

## 3. Interaction Flows

### 3.1 Variable-Pick Button — Happy Path

```
User has a step card expanded showing "Target Variable" field (empty)
→ User clicks {x} button inside the input
→ context-autocomplete#picker fires
→ Full variable list loaded (all groups + "Used in this element")
→ Dropdown opens anchored below the input
→ Browser focus returns to the input
→ User presses ↓ to highlight "ctx[:user_id]"
→ User presses Enter
→ Variable inserted into input at cursor position (replacing all content if empty)
→ Dropdown closes
→ Input value: "ctx[:user_id]"
→ `input` event fires → form sync
```

### 3.2 Variable-Pick Button — Input Already Has Text

```
User has input value "prefix_"  (cursor after "_")
→ User clicks {x}
→ Dropdown opens
→ User clicks "ctx[:user_id]"
→ _selectOption replaces word at cursor ("" between "_" and end) → inserts variable
→ Result: "prefix_ctx[:user_id]"
```

CRITICAL: `_getWordAtCursor` uses `\w` regex which stops at `[` — so selecting a variable inside an expression works as expected without clobbering surrounding text.

### 3.3 Entity Column Select — Happy Path (Step Config)

```
User expands step card "Find Model" (findField is entityField)
→ canvas.entityAttributes present (entity bound to flowchart)
→ findField renders as column select instead of text input
→ User opens select → sees: email, name, created_at, updated_at, … enter manually
→ User picks "email"
→ Hidden config input updated to "email"
→ Collect: findField = "email"
```

### 3.4 Entity Column Select — Enter Manually Swap

```
User picks "enter manually…" from column select
→ Select hidden (classList.add("hidden"))
→ Manual text input shown (classList.remove("hidden"))
→ Focus moves to text input
→ User types "custom_field_name"
→ Collect: findField = "custom_field_name"

User wants to revert:
→ Clicks ▲ button
→ Manual input hidden; select visible again
→ Select value reset to ""
→ User picks a column from the select
```

### 3.5 Progressive Disclosure — "More Options" Opens

```
User expands "Query Models" step (20 fields → many in "More options")
→ Core fields flat: queryType, resultVar
→ "More options" disclosure shows: badge "5 set" (N fields differ from default)
→ User clicks "More options" header
→ Body expands (hidden class removed, chevron rotates 180°)
→ User edits "groupBy" → badge updates to "6 set"
→ User collapses step card
→ User re-expands step card
→ "More options" restores to open state (session Map preserves it)
```

### 3.6 More Options — visibleWhen Cross-Partition

```
"Query Models": queryType (core) controls conditions KV-list (More options)
→ User changes queryType from "where" to "scope"
→ property-editor#handleConfigFieldChange fires
→ visibleWhen evaluator runs on ALL config-field divs in the card body,
  including those inside the "More options" body (not removed from DOM)
→ conditions KV-list div gets class "hidden"; scopeName/scopeArgs divs lose "hidden"
→ "More options" badge re-counts non-default set fields → updates
```

### 3.7 resultVar Auto-Fill on Step Commit

```
User picks "Find Model" from step picker → Enter/click commits
→ buildStepItemTemplate called with configSchema
→ resultVar field has default: "model"
→ Auto-fill check: scan sibling steps for resultVar = "model"
  → Found: another step already uses "model"
  → Try "model_2" → not found → use "model_2"
→ Step card renders with resultVar pre-filled as "model_2"
→ User can immediately change it; dirty flag set on first user edit
```

### 3.8 Condition Builder — Variable Pick on Right Operand

```
User is in loop While condition builder
→ Right operand text input shows placeholder "value"
→ User clicks {x} on right operand input
→ Dropdown opens with full variable list
→ User picks "ctx[:max_count]"
→ Right operand value = "ctx[:max_count]"
→ Collect: rightOperand = "ctx[:max_count]"
```

### 3.9 Failure Paths

| Failure | Behavior |
|---|---|
| Entity API 403 / network error (step config entityField) | Plain text input shown immediately (no flash); user types column name manually |
| Entity API error (query-count entity selected) | Amber hint below WHERE rows; rows stay plain text inputs (existing silent-fail behavior enhanced with visual cue) |
| Variable list empty (picker button clicked) | Dropdown shows "No variables available" in italic, text-[11px] text-slate-400 |
| "More options" partition produces 0 non-core fields | No disclosure rendered; all fields rendered flat (same as ≤ 6 field case) |
| resultVar collision after max 9 suffixes | Stop at `_9`; leave duplicate visible; user must resolve manually |

---

## 4. Component Reuse Map

| UI Element | Existing Artifact | New/Changed | Notes |
|---|---|---|---|
| Variable-pick button | none | New: inline HTML in `buildConfigTextField`, `buildConfigTextareaField`, `buildInlineCondition`, `_buildConditionRowHTML`, and branch modal right-operand wrapper | No new ViewComponent; inlined at each call site |
| `context-autocomplete#picker` action | `context_autocomplete_controller.js` | Add `picker()` method | See 5.2 for method spec |
| "Used in this element" group | `context_autocomplete_controller.js` | Extend `_buildDropdownHTML` | Add group at top when sibling vars available |
| Entity column select wrapper | none | New: `buildEntityColumnSelect(field, value, entityAttributes)` helper in `templates.js` | Returns either select markup or fallback text input |
| Manual-swap handlers (entity field) | `swapLeftOperandToManual` / `swapLeftOperandToSelect` (branch_manager.js) | New: `swapEntityColumnToManual` / `swapEntityColumnToSelect` in `property_editor_controller.js` | Same pattern, different data selectors |
| "More options" disclosure | `buildDisclosureSection` (templates.js) | Reuse unchanged | Pass `id="step-more-${stepIndex}"`, `label="More options"`, `badgeHTML=buildSetCountBadge(N)` |
| Set-count badge | `buildOverrideBadge` (templates.js) | New: `buildSetCountBadge(count)` (slate colors, "N set" label) | Distinguish from Advanced overrides badge visually |
| Step config field partition | `buildStepConfigFieldsHTML` (templates.js) | Extend to partition + wrap disclosure | Core fields returned flat; non-core wrapped in More options disclosure |
| KV-list placeholder | `buildConfigKeyValueList` (templates.js) | Extend: read `field.keyPlaceholder` / `field.valuePlaceholder` | No structural change |
| resultVar auto-fill | step_manager.js (commit path) | Extend commit handler: fill output-var fields iff empty, with collision suffix | Dirty-flag logic mirrors For-Each item/index auto-fill |
| Unified condition row variable buttons | `buildInlineCondition`, `_buildConditionRowHTML` | Extend both to wrap text inputs in `relative` div + add `{x}` button | Left operand select rows: button omitted |
| QC WHERE key escape hatch | `_addQueryCountWhereRow` (branch_manager.js) | Add optgroup + manual swap | New `swapQcWhereFieldToManual` / `swapQcWhereFieldToSelect` actions |
| QC WHERE value variable-pick | `_addQueryCountWhereRow` | Add `{x}` button to value input | Same wrapper+absolute-button pattern as 2.1a |
| Amber "schema unavailable" hint | none | New: inline HTML added by `onQueryCountEntityChange` error handler | `text-[10px] text-amber-700` |

---

## 5. Tailwind and Stimulus Notes

### 5.1 Palette and Typography Consistency

No new colors or type sizes. All additions use:

- **Indigo** (`indigo-50/100/400/500/600/700`): variable-pick button hover/active in step config context; `{x}` button hover state universally.
- **Amber** (`amber-50/100/200/500/600/700`): focus rings in condition builders; amber schema-unavailable hint text; already present in condition builder markup.
- **Slate** (`slate-50/100/200/400/500/600/700`): set-count badge background/text (`slate-100/slate-600`), manual-swap revert button, all neutral states.
- **Red** (`red-50/500`): no new usages beyond existing error states.
- **Font-mono** (`font-mono`): applied to manual field-name inputs (column name entry) and condition builder left/right text inputs — signals "this is a technical identifier or expression", consistent with the existing branch condition left-manual input.

Typography scale (no new sizes):
- Variable-pick `{x}` glyph: `text-[10px]` (smallest existing size in the scale).
- Set-count badge: `text-[10px]` (same as override badge).
- Amber schema hint: `text-[10px]` (matches helper/hint text scale).
- "No variables available" dropdown state: `text-[11px]` (matches existing empty-state scale).

### 5.2 Stimulus — context_autocomplete_controller.js Extension

**New method: `picker(event)`**

```
picker(event) {
  event.preventDefault()
  if (!this._canvas) this._resolveCanvas()
  // 1. Load full variable list (no prefix filter)
  getAvailableVariables(this._canvas, this.elementIdValue, this.stepIndexValue)
    .then(result => {
      const sibling = this._collectSiblingStepVars()   // new private helper
      this._filteredGroups = this._buildPickerGroups(result.groups, sibling)
      this._allOptions = this._flattenOptions(this._filteredGroups)
      this._selectedIndex = 0
      if (this._allOptions.length > 0) {
        this._renderDropdown()
      } else {
        this._renderNoVariablesDropdown()
      }
      // Return focus to input so keyboard nav works immediately
      this.element.focus()
    })
}
```

**New private helper: `_collectSiblingStepVars()`**

Scans the live DOM for `[data-step-item]` siblings of the current step card, reads their `data-step-config` hidden inputs, parses JSON, and collects the values of output-variable keys (`resultVar`, `outputKey`, `targetVariable`). Returns an array of strings. Called only from `picker()`.

**New private helper: `_buildPickerGroups(existingGroups, siblingVars)`**

Prepends a "Used in this element" group (if `siblingVars.length > 0`) before `existingGroups`.

**New private helper: `_renderNoVariablesDropdown()`**

Creates/shows the dropdown with a single non-interactive row:
```html
<div class="px-3 py-2 text-[11px] text-slate-400 italic">No variables available</div>
```

### 5.3 Stimulus — property_editor_controller.js Extensions

New actions needed for round-2 surfaces:

| Action Method | Trigger | Behavior |
|---|---|---|
| `handleEntityColumnSelectChange(event)` | `change` on `[data-entity-column-select]` | If value is `"__manual__"`, call `swapEntityColumnToManual`; else copy value to hidden `data-config-input` sibling |
| `swapEntityColumnToManual(event)` | Internal call or button | Hide select wrapper, show manual wrapper, focus manual input |
| `swapEntityColumnToSelect(event)` | Click on ▲ revert button | Hide manual wrapper, show select, reset select to `""` |
| `swapQcWhereFieldToManual(event)` | `__manual__` selected in `data-qc-where-field` | Same pattern; show `data-qc-where-field-manual`, focus input |
| `swapQcWhereFieldToSelect(event)` | Click ▲ in WHERE row | Hide manual, show select, reset |
| `updateMoreOptionsBadge(stepIndex)` | Internal; called after any config field change | Re-count non-default values in "More options" disclosure body; update `data-set-count-badge` |

### 5.4 No New Stimulus Controllers

All new interactive behaviors are implemented as new methods on **existing controllers** (`context-autocomplete` and `property-editor`). No new controller files are introduced.

### 5.5 Responsive Safety Within 420 px

All new UI elements stay within the existing 420 px sidebar shell:

- Variable-pick button (`w-5 h-5`) is an absolutely-positioned overlay inside the input — zero impact on horizontal layout.
- Entity column select uses `w-full` — fits within `pl-6` indented config field area (≈ 390 px usable).
- Manual-swap wrapper uses `flex gap-1` with `flex-1 min-w-0` on the input and fixed-width revert button (`px-2 py-1` ≈ 32 px) — no overflow.
- "More options" disclosure uses the same full-width `buildDisclosureSection` pattern as "Advanced".
- Set-count badge is inline in the disclosure header — same `buildOverrideBadge` sizing already proven at this width.
- Condition row with variable-pick buttons: the three-column layout (`flex items-center gap-1.5`) is unchanged; the `{x}` button is overlaid inside each input at `absolute`, not adding width.

---

## 6. Critical Implementation Flags

The following must not be inferred or approximated:

1. **Additive-only: input remains plain-text-first.** The `{x}` variable-pick button is `tabindex="-1"`. Tab navigation must not land on the button. The input itself remains the primary interaction target. Pressing Enter/Tab in the autocomplete dropdown still inserts and closes; the button is a second entry point only.

2. **`pr-7` is mandatory on variable-pick inputs.** Text must not underlap the `{x}` button. Every text input that gets a variable-pick button must switch from `px-2` (implicit symmetry) to `pl-2 pr-7`.

3. **Entity column select writes to `data-config-input`, not to itself.** The `<select data-entity-column-select>` does not have `data-config-input`. A companion hidden input (or the manual text input) holds the `data-config-input` attribute. `collectSteps()` must never be changed — it reads `data-config-input` elements; all new widgets must honor that contract.

4. **"More options" disclosure is CSS-hidden, not DOM-removed.** `visibleWhen` evaluation runs on all `[data-config-field]` elements inside the step card, including those inside the closed "More options" body. Removing the body from the DOM breaks `visibleWhen` for cross-partition dependencies (e.g., a select in core that controls a field in "More options").

5. **Partition is computed at render time, not at schema-definition time.** The heuristic (required + no visibleWhen → core, rest → More options) runs inside `buildStepConfigFieldsHTML` when the step card is built. The `group` annotation on the schema object overrides the heuristic. Neither the partition decision nor the `group` hint is ever written to the saved config JSON.

6. **resultVar auto-fill: iff-empty, once.** If the user clears the resultVar field and then re-expands another step, the auto-fill must NOT re-fire. The dirty flag is set the moment the user makes any edit to the field. Auto-fill fires only at step-commit time when the field is currently empty (default state, never been touched).

7. **Collision suffix stops at `_9`.** Do not loop indefinitely. If `_2` through `_9` are all taken, leave `_9` as the value and let the user resolve manually.

8. **Variable-pick button `{x}` does NOT appear on:** select fields, number fields, key_value_list fields, or any field whose key does not match the variable-reference pattern. Pattern to centralize:
   ```js
   const VAR_REF_PATTERN = /Var$|Variable$|Key$|Expression$|^collection$|^sourceField$|^targetField$/
   function isVarRefField(fieldKey) { return VAR_REF_PATTERN.test(fieldKey) }
   ```
   This function is called in `buildConfigTextField`, `buildConfigTextareaField`, and condition-row builders. Put it in a shared location (e.g., `templates.js`) so field builders and condition builders share one definition.

9. **Amber focus ring on condition builders, indigo on step config fields.** Do not unify the colors. The amber tone is a deliberate signal that condition rows are in the decision/loop domain. Changing it to indigo would break the round-1 established color semantics.

10. **"enter manually…" `value="__manual__"` is the sentinel.** Both the entity column select (step config) and the QC WHERE field select use `value="__manual__"` for the swap trigger. `_collectFieldCondition` and `collectSteps()` must never emit `"__manual__"` into the saved JSON. The swap handler clears the select value to `""` when the manual input is shown, ensuring the sentinel never propagates.

11. **Context-autocomplete `picker()` must restore input focus after dropdown renders.** The button click transfers focus to the button momentarily (browser default). The `picker()` action must call `this.element.focus()` after `_renderDropdown()` so that subsequent ↓/↑/Enter/Escape keystrokes on the input are handled by the existing `_onKeydown` listener.

12. **Set-count badge uses `data-set-count-badge` attribute; override badge uses `data-override-badge`.** These are sibling badges on different disclosures within the same step card. `updateMoreOptionsBadge` targets `data-set-count-badge`; `updateStepOverrideBadge` targets `data-override-badge`. Do not conflate selectors.

---

```
## RETURN
ux_doc: /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/docs/superpowers/specs/2026-06-12-detail-config-refactor-ux.md
surfaces:
  - name: Step config — variable-pick icon button on text/textarea inputs
    nav_area: admin
    new_components: [VAR_REF_PATTERN helper in templates.js, context-autocomplete#picker action]
    reused_components: [context_autocomplete_controller, buildConfigTextField, buildConfigTextareaField, buildInlineCondition]
  - name: Step config — entity column select with manual swap
    nav_area: admin
    new_components: [buildEntityColumnSelect helper in templates.js, swapEntityColumnToManual/swapEntityColumnToSelect actions]
    reused_components: [buildConfigTextField (fallback), existing swapLeftOperandToSelect pattern]
  - name: Step config — More options progressive disclosure
    nav_area: admin
    new_components: [buildSetCountBadge in templates.js, partition logic in buildStepConfigFieldsHTML]
    reused_components: [buildDisclosureSection, buildOverrideBadge (pattern reference)]
  - name: Step config — semantic KV-list placeholders
    nav_area: admin
    new_components: []
    reused_components: [buildConfigKeyValueList (extended with keyPlaceholder/valuePlaceholder)]
  - name: Step config — resultVar auto-suggest pre-fill
    nav_area: admin
    new_components: []
    reused_components: [step_manager commit handler (extended), buildConfigTextField]
  - name: Condition builder — unified row with variable-pick buttons
    nav_area: admin
    new_components: []
    reused_components: [buildInlineCondition (extended), _buildConditionRowHTML (extended), context_autocomplete_controller]
  - name: Query-count WHERE row key — column select + manual swap + value var-pick
    nav_area: admin
    new_components: [swapQcWhereFieldToManual/swapQcWhereFieldToSelect actions, amber schema-unavailable hint]
    reused_components: [_addQueryCountWhereRow (extended), existing __manual__ swap pattern]
overall: READY_FOR_FRONTEND
notes: All round-2 surfaces are additive overlays on the existing 420px step card and branch modal markup. The two most structurally significant changes are (1) the input wrapper restructure for variable-pick buttons (bare input → relative div + input + absolute button, with pr-7 on input) and (2) the buildStepConfigFieldsHTML partition into core/More-options, which wraps non-core fields in an additional buildDisclosureSection. The entity column select and QC WHERE key swap follow the exact same __manual__ pattern already present in the branch modal left-operand select, giving the frontend developer a clear implementation reference. No new colors, type sizes, or Stimulus controllers are introduced.
```

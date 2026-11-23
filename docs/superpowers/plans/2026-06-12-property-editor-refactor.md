# Property Editor Refactor (Step Picker / Loop Advanced / Decision Branches) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Intended save path:** `docs/superpowers/plans/2026-06-12-property-editor-refactor.md`
> **Specs:** `docs/superpowers/specs/2026-06-12-property-editor-refactor-design.md`, `docs/superpowers/specs/2026-06-12-property-editor-refactor-ux.md`
> **Worktree:** `/home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor` (all paths below relative to it)

**Goal:** Make the three heaviest property-editor surfaces guided instead of blank-slate: one inline searchable action picker for Process steps (modal + quick-add deleted), an upgraded Decision branch modal with preset chips and a seeded left-operand select (quick-add deleted), and progressive-disclosure Loop Advanced fields with iff-empty auto-fill — all sharing one disclosure template, one card template, and one condition-summary helper, with saved JSON contracts byte-identical to today.

**Architecture:** Pure form-layer refactor inside the existing 420px sidebar (`_editor.html.erb:475-580`). All UI is built by manual HTML template strings in `templates.js` consumed by `step_manager.js` / `branch_manager.js` / `form_builder.js`, orchestrated by the `property-editor` Stimulus controller. The existing `searchable-select` Stimulus controller becomes the picker engine (one small additive `expandAll` value). Canvas mutation order for branches (`onBeforeChange` → DOM insert → `collectBranches` → element create → connection condition → reposition → `onchange`) is untouched.

**Tech Stack:** Rails 8, importmap (no bundler), Stimulus 3, Tailwind, ViewComponent, RSpec. **No JS unit runner exists** (no `package.json`/jest — verified); JS verification = `node --input-type=module --check` syntax checks (verified working in this env) + manual dev-server passes. System specs with `js: true` exist but are skipped (`spec/system/property_editor/element_io_tab_spec.rb:13` — "System specs need Capybara JS driver configuration"); do not rely on them.

---

## Spec-vs-code contradictions found (binding resolutions for builders)

1. **`searchable-select:commit` event does not exist.** UX doc §5.2 claims the controller "already dispatched" a custom commit event. False — `searchable_select_controller.js:344` dispatches a plain `change` event on its **hidden input** target. **Resolution:** wire `data-action="change->property-editor#stepPickerCommit"` on the hidden input (exact same pattern the old level-0 modal dropdown uses at `step_manager.js:1138`).
2. **Groups are collapsed by default in searchable-select** (`renderOptions` sets `groupItems` to `hidden`; `filter()` with empty query collapses all; `resetFilter()` calls `collapseAllGroups()`). The UX empty-query state (§2.1) shows all actions under category headings. **Resolution:** add an optional `expandAll: Boolean` Stimulus value to `searchable_select_controller.js` (additive, off by default — existing call sites unaffected). UX said "no controller changes"; this is the minimal deviation required.
3. **No action in the registry has `subOptions` or `configSchemaBySubOption`** (grep over `app/javascript/flowchart/constants/action_configs/*.js` = 0 matches). Breadcrumbs like "Validate › Format › Email" cannot occur with current data; the cascade-dropdown machinery in `step_manager.js` is dead-in-practice. **Resolution:** implement leaf flattening generically (registry format permits subOptions) but expect single-level leaves; keep `suboption`/`configSchemaBySubOption` support in the commit path so the contract key survives.
4. **Loop visibility consolidation target.** UX §5.2 says to reuse "the consolidated visibleWhen evaluator already present in handleConfigFieldChange" — but that evaluator works on step-config fields (JSON in `data-visible-when`, scoped to a step card), while element-level fields use `data-visible-when="<field>" data-visible-values="a,b"` (form-scoped, built by `form_builder.js:163-174`). **Resolution:** consolidate the four duplicated element-level handlers (`handleLoopTypeChange`/`handleTriggerTypeChange`/`handleResponseTypeChange`/`handleDelayTypeChange`, controller lines 680-699, 743-762, 773-792, 803-821) into one `handleVisibilityFieldChange` that keys off `event.target.name`. Do not merge with the step-config mechanism.
5. **Focus after left-operand pick:** design doc §2 says "focuses the right operand"; UX §2.5b says focus moves to the **operator select** first. **Resolution:** follow UX (operator first; right operand after operator chosen — the existing `handleConditionOperatorChange` pattern).
6. **Disclosure ViewComponent:** design doc Testing mentions component specs for "disclosure section"; UX §6.10 says `buildDisclosureSection` is JS-only, **NOT** a ViewComponent. **Resolution:** JS-only; component specs cover `CompactItemComponent` changes only.
7. **branches[] contract in the design doc is slightly wrong.** `collectBranches()` (`branch_manager.js:448-484`) emits `{name, description, branchKey: "branch_N", elementId?, condition?}` — there is **no `id` key** and `branchKey` is present. **Resolution:** keep the code's actual shape byte-identical; the design doc's listed shape is descriptive only.
8. **Keyboard wrap:** UX §2.1 says ↑/↓ "wraps at ends"; the controller clamps (`Math.min`/`Math.max`, lines 299-305). **Resolution:** accept clamping; do not modify navigation.
9. **Keyword params / step description** were only settable in the deleted modal. They remain in the steps[] contract via round-trip hidden inputs in the card template; new steps commit with `keywordParams: []`, `description: ""` (same as today's quick-add path). No new editor UI for them (YAGNI; description is also editable at element level).
10. **`buildCompactItem` and friends have zero callers today** (`buildStepItemTemplate`/`buildBranchItemTemplate` are hand-rolled). Its signature may change freely in Task 1.

## Data contracts that MUST remain byte-identical

- **`properties.steps[]`** — produced by `collectSteps()` (`step_manager.js:659-750`). Shape: `{id, action, description, suboption?, selectionLabels?, keywordParams?, retryCount?+retryBackoff? (only when retryCount>0), timeout? (only when >0), guardCondition? (only when non-empty), config? (only when non-empty)}`. Only the four advanced-field **selectors** change in Task 3 (tag-prefixed → tagless); the emitted object logic is untouched.
- **`properties.branches[]`** — produced by `collectBranches()` (`branch_manager.js:448-484`): `{name, description, branchKey, elementId?, condition?}` + condition mirrored onto the connection in `addBranchFromModal` (lines 268-276). `collectBranches` is **not modified at all**.
- **Branch condition objects** — field: `{type: "single", leftOperand, operator, rightOperand}`; query count: `{conditionType: "query_count", queryConfig: {entityId, entityName, conditions?}, countOperator, countValue}` (`_collectFieldCondition` / `_collectQueryCountCondition`, lines 1150-1207).
- **Loop keys** — `loopType, condition{}, collection, itemVariable, indexVariable, iterations, breakCondition, accumulatorVariable, skipCondition` flow through `FormData` field **names** in `_collectFormData` (controller 832-865). Names must not change; the Options disclosure only wraps markup (CSS-hidden inputs still serialize into FormData, so loop-type round-trips stay lossless).
- **Canvas mutation order** for branch add/remove (`onBeforeChange` → insert DOM → `collectBranches` → `_createBranchElement` → connection condition → `branchAdded` → `_repositionAllBranchElements` → `_refreshDecisionElement` → `_hideConnectionHandles` → `updateConnections` → `onchange`) — copy verbatim, never reorder.

## Task dependency / parallelism map

- **Task 1 (shared templates + controller plumbing)** — must land first; Tasks 2-4 import its functions.
- **Task 2 (loop)** and **Task 4 (decision branches)** touch disjoint functions and can be built **in parallel** after Task 1 (overlap limited to different sections of `schemas.js` and different methods of `property_editor_controller.js` — trivial merges).
- **Task 3 (process step picker)** is the largest and overlaps `templates.js` + controller heavily with Task 4 — run it **sequentially** (either before or after the 2∥4 pair; recommended order 1 → 2 → 3 → 4 to match spec ordering, or 1 → (2 ∥ 4) → 3 if dispatching parallel agents in separate worktrees with a merge step).
- **Task 5 (ViewComponent parity + specs)** depends only on Task 1's final card design — parallel with 2/3/4.
- **Task 6 (cleanup)** last, after everything merges.

Each task leaves the app fully working (Task 3 deletes the modal and adds the picker atomically within the task).

---

### Task 1: Shared templates — disclosure section, override badge, condition summary, unified card, `toggleDisclosure`

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (add 3 exports after `buildSegmentedControl` ~line 93; replace `buildCompactItem` at lines 155-182; add import of `BRANCH_OPERATORS`)
- Modify: `app/javascript/controllers/property_editor_controller.js` (add `toggleDisclosure` near `toggleStepAdvanced`, ~line 510)
- Test: syntax check + Task 5 component specs cover the mirrored markup; no runnable JS test (no jest)

- [ ] **Step 1: Add imports and `buildDisclosureSection` + `buildOverrideBadge` to `templates.js`**

At the top (line 7), extend imports:

```js
import { escapeHtml } from "utils"
import { BRANCH_OPERATORS } from "flowchart/constants/schemas"
```

(Importing from `flowchart/constants/schemas` directly avoids the barrel; `schemas.js` only imports `action_registry` so no cycle with `templates.js`.)

After `buildSegmentedControl` (line 93), add:

```js
/**
 * Build a collapsible disclosure section (chevron header + body + optional badge).
 * Used by the step card "Advanced" sub-section and the loop "Options" group.
 * @param {Object} params
 * @param {string} params.id - Stable identifier written to data-disclosure-id
 * @param {string} params.label - Header label
 * @param {string} params.badgeHTML - Optional pre-built badge HTML (not escaped)
 * @param {string} params.bodyHTML - Body content HTML (not escaped)
 * @param {boolean} params.startOpen - Render expanded (default collapsed)
 * @returns {string} Disclosure section HTML
 */
export function buildDisclosureSection({ id, label, badgeHTML = "", bodyHTML = "", startOpen = false }) {
  return `
    <div class="border border-slate-200 rounded-md" data-disclosure data-disclosure-id="${escapeHtml(id)}">
      <button type="button"
              data-action="click->property-editor#toggleDisclosure"
              class="w-full flex items-center justify-between px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-50 transition-colors rounded-md">
        <span class="flex items-center gap-1.5">
          <span>${escapeHtml(label)}</span>
          ${badgeHTML}
        </span>
        <svg data-disclosure-chevron class="w-3.5 h-3.5 text-slate-400 transition-transform duration-150 ${startOpen ? "rotate-180" : ""}"
             fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div data-disclosure-body class="${startOpen ? "" : "hidden"} px-2.5 pb-2.5 border-t border-slate-200">
        ${bodyHTML}
      </div>
    </div>
  `.trim()
}

/**
 * Build the "N override(s)" badge for the step Advanced disclosure.
 * Rendered hidden (not omitted) when count is 0 so JS can update it in place.
 * @param {number} count
 * @returns {string} Badge HTML
 */
export function buildOverrideBadge(count) {
  const hiddenClass = count > 0 ? "" : " hidden"
  return `<span data-override-badge class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-[10px] font-semibold text-indigo-600 bg-indigo-50 border border-indigo-200 rounded${hiddenClass}">${count} override${count === 1 ? "" : "s"}</span>`
}
```

- [ ] **Step 2: Add `buildConditionSummaryText` to `templates.js`** (after `buildOverrideBadge`):

```js
const UNARY_OPERATORS = ["is_empty", "is_not_empty", "is_true", "is_false", "is_nil"]

/**
 * Human-readable branch/loop condition summary using BRANCH_OPERATORS labels.
 * Examples: "ctx.status equals active", "Count of Users > 10", "ctx.email is not empty".
 * Returns "" for null/empty conditions. Output is PLAIN TEXT — caller escapes it.
 * @param {Object|null} condition
 * @returns {string}
 */
export function buildConditionSummaryText(condition) {
  if (!condition) return ""

  if (condition.conditionType === "query_count") {
    const qc = condition.queryConfig || {}
    const entityName = qc.entityName || `Entity#${qc.entityId || "?"}`
    return `Count of ${entityName} ${condition.countOperator || ">"} ${condition.countValue ?? 0}`
  }

  if (!condition.leftOperand && !condition.operator) return ""

  const rawLabel = BRANCH_OPERATORS.find(op => op.value === condition.operator)?.label
    || condition.operator || ""
  // "equals (==)" -> "equals"
  const opLabel = rawLabel.replace(/\s*\(.*\)$/, "")

  if (UNARY_OPERATORS.includes(condition.operator)) {
    return `${condition.leftOperand || ""} ${opLabel}`.trim()
  }
  return `${condition.leftOperand || ""} ${opLabel} ${condition.rightOperand || ""}`.trim()
}
```

- [ ] **Step 3: Replace `buildCompactItem` (templates.js:155-182) with the unified card** (zero existing callers — verified by grep; Tasks 3/4 wire the step/branch templates onto it):

```js
/**
 * Unified card used by both step and branch items: accent border, header row
 * (leading | color dot | title + subtitle | trailing actions), optional body
 * and hidden inputs. Trailing actions reveal on hover.
 * @param {Object} params
 * @param {string} params.accentColor - Tailwind color name (e.g. "indigo", "amber")
 * @param {string} params.title - Card title (escaped here)
 * @param {string} params.subtitleHTML - Pre-built HTML under the title (NOT escaped)
 * @param {string} params.leadingHTML - HTML before the color dot (NOT escaped)
 * @param {string} params.trailingHTML - HTML in the trailing actions slot (NOT escaped)
 * @param {string} params.bodyHTML - Expandable/extra body HTML after the header row
 * @param {string} params.hiddenInputsHTML - Hidden form inputs kept inside the card root
 * @param {string} params.headerAttrs - Extra attributes on the header row div
 * @param {string} params.extraClasses - Extra classes on the card root
 * @param {string} params.extraAttrs - Extra attributes on the card root
 * @returns {string}
 */
export function buildCompactItem({
  accentColor,
  title,
  subtitleHTML = "",
  leadingHTML = "",
  trailingHTML = "",
  bodyHTML = "",
  hiddenInputsHTML = "",
  headerAttrs = "",
  extraClasses = "",
  extraAttrs = ""
}) {
  return `
    <div class="relative border-l-2 border-${accentColor}-400 border-b border-b-slate-100 px-2.5 py-2 hover:bg-slate-50 transition-colors group ${extraClasses}" ${extraAttrs}>
      <div class="flex items-center gap-2" ${headerAttrs}>
        ${leadingHTML}
        <div class="w-2 h-2 rounded-full bg-${accentColor}-500 flex-shrink-0"></div>
        <div class="flex-1 min-w-0 cursor-pointer">
          <div class="text-xs font-medium text-slate-800 truncate">${escapeHtml(title)}</div>
          ${subtitleHTML}
        </div>
        <div class="ml-auto flex items-center gap-0.5 flex-shrink-0">${trailingHTML}</div>
      </div>
      ${bodyHTML}
      ${hiddenInputsHTML}
    </div>
  `.trim()
}
```

- [ ] **Step 4: Add `toggleDisclosure` to `property_editor_controller.js`** (insert directly after `toggleStepAdvanced`, i.e. after line 520; `toggleStepAdvanced` itself is deleted in Task 3):

```js
/**
 * Toggle a buildDisclosureSection() body open/closed.
 * Generic replacement for toggleStepAdvanced; used by step Advanced and loop Options.
 */
toggleDisclosure(event) {
  event.preventDefault()
  const section = event.currentTarget.closest("[data-disclosure]")
  if (!section) return
  const body = section.querySelector("[data-disclosure-body]")
  const chevron = section.querySelector("[data-disclosure-chevron]")
  if (body) body.classList.toggle("hidden")
  if (chevron) chevron.classList.toggle("rotate-180")
}
```

- [ ] **Step 5: Syntax-verify both files**

Run:
```bash
node --input-type=module --check < app/javascript/controllers/property_editor/templates.js && \
node --input-type=module --check < app/javascript/controllers/property_editor_controller.js && echo OK
```
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat(property-editor): shared disclosure, override badge, condition summary, unified card templates

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Loop Advanced — schema regroup, consolidated visibility handler, iff-empty auto-fill, live hint, collection validation

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js:479-497` (loop `iterations`/`breakCondition`/`accumulatorVariable`)
- Modify: `app/javascript/controllers/property_editor/form_builder.js` (`_buildFormFields` 79-127, `_buildFieldHTML` 129-202, `extraAction` block 177-186, `_buildInputHTML` text case 222-232, `changeActionMap` 295-300; add `buildDisclosureSection` import)
- Modify: `app/javascript/controllers/property_editor_controller.js` (replace handlers at 680-699, 743-762, 773-792, 803-821; add validation in `save()` at 352-389)
- Test: manual via dev server (no JS runner); syntax checks

- [ ] **Step 1: Schema changes** (`schemas.js`, inside `loop`):

`iterations` (lines 479-485) before→after:
```js
// BEFORE
iterations: {
  type: "number",
  label: "Max Iterations",
  min: 1,
  placeholder: "10",
  tab: "advanced"
},
// AFTER
iterations: {
  type: "number",
  label: "Max iterations (safety guard)",
  helperText: "Stops the loop even if its condition never becomes false.",
  min: 1,
  placeholder: "10",
  group: "options",
  tab: "advanced"
},
```

`breakCondition` (486-491) and `accumulatorVariable` (492-497): add `group: "options",` to each (no other changes). `skipCondition`, `collection`, `itemVariable`, `indexVariable`, `condition`, `loopType` unchanged (skipCondition stays top-level per design §3).

- [ ] **Step 2: `form_builder.js` — Options disclosure grouping + helperText + hint**

Add import at top:
```js
import { buildDisclosureSection } from "controllers/property_editor/templates"
```

In `_buildFormFields` (lines 91-105) before→after:
```js
// BEFORE
const tabFields = { general: "", steps: "", io: "", advanced: "" }
Object.entries(schema).forEach(([fieldName, fieldSchema]) => {
  ...
  const tab = fieldSchema.tab || "general"
  tabFields[tab] += fieldHTML
})
// AFTER
const tabFields = { general: "", steps: "", io: "", advanced: "" }
const optionsGroupFields = { general: "", steps: "", io: "", advanced: "" }
Object.entries(schema).forEach(([fieldName, fieldSchema]) => {
  ...
  const tab = fieldSchema.tab || "general"
  if (fieldSchema.group === "options") {
    optionsGroupFields[tab] += fieldHTML
  } else {
    tabFields[tab] += fieldHTML
  }
})

// Collapsed "Options" disclosure per tab for fields declaring group: "options"
Object.keys(optionsGroupFields).forEach(tab => {
  if (!optionsGroupFields[tab]) return
  const disclosure = buildDisclosureSection({
    id: `${tab}-options`,
    label: "Options",
    bodyHTML: `<div class="space-y-2 pt-2.5">${optionsGroupFields[tab]}</div>`,
    startOpen: false
  })
  // col-span-2 keeps it full-width when the advanced pane uses the 2-col grid
  tabFields[tab] += `<div class="${tab === "advanced" ? "col-span-2" : ""}">${disclosure}</div>`
})
```

In `_buildFieldHTML`, replace the `extraAction` block (lines 177-186):
```js
// BEFORE: four if/else branches mapping loopType/triggerType/responseType/delayType
// AFTER
let extraAction = ""
if (["loopType", "triggerType", "responseType", "delayType"].includes(fieldName)) {
  extraAction = ` data-action="change->property-editor#handleVisibilityFieldChange"`
} else if (fieldName === "itemVariable") {
  extraAction = ` data-action="input->property-editor#updateItemVariableHint"`
}
```

In `_buildInputHTML` `case "text"` (lines 223-232), add `${extraAction}` to the input tag (it is currently dropped for text inputs):
```js
case "text":
  return `
    <input type="text"
           id="prop_${fieldName}"
           name="${fieldName}"
           value="${escapeHtml(currentValue)}"
           ${placeholder}
           ${isRequired}
           ${extraAction}
           class="${inputClass}">
  `
```

In `_buildFieldHTML` just before the closing `fieldHTML += "</div>"` (line 199), append helper text and the live hint:
```js
if (fieldSchema.helperText) {
  fieldHTML += `<p class="mt-0.5 text-[10px] text-slate-400">${escapeHtml(fieldSchema.helperText)}</p>`
}
if (fieldName === "itemVariable" && this.controller.currentElement?.type === "loop") {
  const hintVar = String(currentValue || "item")
  fieldHTML += `<p data-item-variable-hint class="mt-0.5 text-[10px] text-slate-400">Available inside the loop body as <code class="font-mono text-slate-600">${escapeHtml(hintVar)}</code></p>`
}
```

In `_buildSegmentedControlHTML`, replace the `changeActionMap` (lines 295-300):
```js
const VISIBILITY_FIELDS = ["loopType", "triggerType", "responseType", "delayType"]
const changeAction = VISIBILITY_FIELDS.includes(fieldName)
  ? ` data-action="change->property-editor#handleVisibilityFieldChange"`
  : ""
```

- [ ] **Step 3: Controller — replace the four duplicated handlers with one** (`property_editor_controller.js`). Delete `handleLoopTypeChange` (680-699), `handleTriggerTypeChange` (743-762), `handleResponseTypeChange` (773-792), `handleDelayTypeChange` (803-821) and add in their place:

```js
// ===================
// Field Visibility (loopType / triggerType / responseType / delayType)
// ===================

/**
 * Single change handler for every select that controls visibleWhen fields.
 * Replaces the former handleLoopTypeChange / handleTriggerTypeChange /
 * handleResponseTypeChange / handleDelayTypeChange quadruplication.
 * Fields are CSS-hidden, never removed, so hidden values survive type switches.
 */
handleVisibilityFieldChange(event) {
  const fieldName = event.target.name
  if (!fieldName || !this.hasFormTarget) return

  this._applyFieldVisibility(fieldName, event.target.value)

  if (fieldName === "loopType") {
    this._autoFillForEachDefaults(event.target.value)
  }

  this._syncChangesToCanvas()
}

_applyFieldVisibility(fieldName, selectedValue) {
  this.formTarget.querySelectorAll("[data-visible-when]").forEach(field => {
    if (field.dataset.visibleWhen !== fieldName) return
    const visibleValues = (field.dataset.visibleValues || "").split(",")
    field.classList.toggle("hidden", !visibleValues.includes(selectedValue))
  })
}

/**
 * Auto-fill itemVariable="item" / indexVariable="index" when For-Each is
 * selected — ONLY if the field is currently empty. Never overwrites.
 */
_autoFillForEachDefaults(loopType) {
  if (loopType !== "for_each") return
  const itemInput = this.formTarget.querySelector('input[name="itemVariable"]')
  const indexInput = this.formTarget.querySelector('input[name="indexVariable"]')
  if (itemInput && itemInput.value.trim() === "") itemInput.value = "item"
  if (indexInput && indexInput.value.trim() === "") indexInput.value = "index"
  this._updateItemVariableHintText()
}

/** input handler on the itemVariable field (wired by form_builder). */
updateItemVariableHint() {
  this._updateItemVariableHintText()
}

_updateItemVariableHintText() {
  if (!this.hasFormTarget) return
  const hint = this.formTarget.querySelector("[data-item-variable-hint]")
  if (!hint) return
  const value = this.formTarget.querySelector('input[name="itemVariable"]')?.value?.trim() || "item"
  hint.innerHTML = `Available inside the loop body as <code class="font-mono text-slate-600">${this._escapeAttr(value)}</code>`
}
```

- [ ] **Step 4: Block save on empty For-Each collection.** In `save()` (line 362, right after the `if (!this.currentElement || !this.canvas) return` guard), insert:

```js
if (!this._validateBeforeSave()) return
```

and add the helpers (near `_collectFormData`):

```js
/**
 * Pre-save validation. Currently: For-Each loops require a collection.
 * Shows an inline error under the field and blocks the save.
 */
_validateBeforeSave() {
  if (this.currentElement?.type !== "loop") return true
  const loopType = this.formTarget.querySelector('[name="loopType"]')?.value
  if (loopType !== "for_each") return true

  const collectionInput = this.formTarget.querySelector('input[name="collection"]')
  if (collectionInput && collectionInput.value.trim() === "") {
    this._showFieldError(collectionInput, "Collection is required")
    return false
  }
  return true
}

_showFieldError(input, message) {
  input.classList.add("ring-2", "ring-red-500", "border-red-500")
  let error = input.parentElement.querySelector("[data-field-error]")
  if (!error) {
    error = document.createElement("p")
    error.setAttribute("data-field-error", "")
    error.className = "text-[10px] text-red-500 mt-0.5"
    input.insertAdjacentElement("afterend", error)
  }
  error.textContent = message
  input.focus()
  setTimeout(() => {
    input.classList.remove("ring-2", "ring-red-500", "border-red-500")
    error.remove()
  }, 2500)
}
```

- [ ] **Step 5: Syntax checks**

```bash
for f in app/javascript/flowchart/constants/schemas.js app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor_controller.js; do node --input-type=module --check < "$f" || exit 1; done; echo OK
```
Expected: `OK`

- [ ] **Step 6: Manual verification (dev server)** — run `bin/dev`, open `/:cid/admin/maintenance/flowcharts/:id/edit`, add a Loop element:
  - Advanced tab: segmented While/Do-While/For-Each at top; While shows condition builder only + collapsed "Options" disclosure containing Max iterations (with helper text), Break Condition, Accumulator Variable.
  - Switch to For-Each: `itemVariable` auto-fills "item", `indexVariable` "index"; hint reads ``Available inside the loop body as `item` `` and live-updates on typing.
  - Type custom item variable, switch While → For-Each: value NOT overwritten; switch types repeatedly: all values retained (CSS-only hide).
  - Save with empty Collection on For-Each: red ring + "Collection is required", no save. Fill it: saves.
  - Regression: Start element triggerType, End responseType, Timer delayType show/hide still work (now via `handleVisibilityFieldChange`).
  - Saved JSON spot check (browser devtools → element properties): keys `loopType, condition, collection, itemVariable, indexVariable, iterations, breakCondition, accumulatorVariable, skipCondition` unchanged.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat(property-editor): loop progressive disclosure, consolidated visibility handler, for-each auto-fill

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Process Step tab — inline searchable picker, expanded card with inline Advanced, delete step modal + quick-add

**Files:**
- Modify: `app/javascript/controllers/searchable_select_controller.js` (additive `expandAll` value: lines 25, 27-36, 221-231, 395-404)
- Modify: `app/javascript/controllers/property_editor/templates.js` (add `buildStepPickerTemplate`; rewrite `buildStepItemTemplate` 509-597; delete `buildStepModalTemplate` 220-307 and `buildDropdownFieldTemplate` 317-338; delete `buildSelectionPathText` 603-633)
- Modify: `app/javascript/controllers/property_editor/step_manager.js` (major rewrite — exact deletions/additions below)
- Modify: `app/javascript/controllers/property_editor_controller.js` (targets line 26; delegates 451-536)
- Modify: `app/javascript/controllers/property_editor/form_builder.js:80-83` (remove stepModalContainer clearing)
- Modify: `app/views/admin/maintenance/flowcharts/_editor.html.erb:573-574` (remove step modal container div)
- Test: manual via dev server; syntax checks

- [ ] **Step 1: `searchable_select_controller.js` — additive `expandAll` value**

Line 25: `static values = { options: Array, selected: String, expandAll: Boolean }`

In `connect()` after `this.renderOptions()` (line 31): `if (this.expandAllValue) this.expandAllGroups()`

In `filter()` empty-query branch (line 229) before→after:
```js
// BEFORE
if (items && header) this.collapseGroup(items, header)
// AFTER
if (items && header) {
  if (this.expandAllValue) { this.expandGroup(items, header) } else { this.collapseGroup(items, header) }
}
```

In `resetFilter()` (line 402) before→after:
```js
// BEFORE
this.collapseAllGroups()
// AFTER
if (this.expandAllValue) { this.expandAllGroups() } else { this.collapseAllGroups() }
```

- [ ] **Step 2: `templates.js` — add `buildStepPickerTemplate`** (place where `buildStepModalTemplate` was):

```js
/**
 * Inline searchable action picker for the Process Step tab.
 * Mounts the searchable-select controller; committing fires a `change` on the
 * hidden input which property-editor#stepPickerCommit handles.
 * @param {string} optionsJSON - JSON.stringify'd grouped options, with ' escaped to &#39;
 * @returns {string}
 */
export function buildStepPickerTemplate(optionsJSON) {
  return `
    <div data-step-picker
         data-controller="searchable-select"
         data-searchable-select-expand-all-value="true"
         data-searchable-select-options-value='${optionsJSON}'
         class="relative border border-slate-200 rounded-lg bg-white shadow-sm">
      <svg class="absolute left-2.5 top-[13px] w-3.5 h-3.5 text-slate-400 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
      <input type="text"
             data-searchable-select-target="search"
             data-action="input->searchable-select#filter keydown->searchable-select#keydown focus->searchable-select#open keydown.esc->property-editor#stepPickerEscape"
             placeholder="Search actions…"
             autocomplete="off"
             class="w-full pl-8 pr-3 py-1.5 text-xs text-slate-800 placeholder:text-slate-400 bg-transparent border-0 focus:outline-none focus:ring-0">
      <input type="hidden"
             data-searchable-select-target="hidden"
             data-action="change->property-editor#stepPickerCommit">
      <div data-searchable-select-target="dropdown"
           class="hidden absolute z-50 mt-1 w-full bg-white border border-slate-200 rounded-md shadow-lg max-h-72 overflow-y-auto"></div>
    </div>
  `.trim()
}
```

- [ ] **Step 3: `templates.js` — rewrite `buildStepItemTemplate` (509-597) onto `buildCompactItem`** with `expanded` param, breadcrumb title, Change button, and inline Advanced disclosure (editable inputs replace the four hidden advanced inputs; **names unchanged**):

```js
/**
 * Build a step item card. Newly-committed steps render expanded; reloaded
 * steps render collapsed. Advanced fields (retry/backoff/timeout/guard) are
 * editable inline inside a collapsed disclosure; their input names match the
 * old hidden inputs exactly so collectSteps() output is byte-identical.
 */
export function buildStepItemTemplate(params) {
  const {
    id = "", index, action, description, actionOptionData, selectionLabels, suboption,
    keywordParams = [], retryCount = 0, retryBackoff = "none", timeout = 0,
    guardCondition = "", configFieldsHTML = "", currentConfig = {}, expanded = false
  } = params

  const colorName = actionOptionData?.color || "blue"
  const labels = Array.isArray(selectionLabels) && selectionLabels.length > 0
    ? selectionLabels
    : [actionOptionData?.label || action]
  const breadcrumbTitle = labels.join(" \u203A ")

  const overrideCount =
    ((parseInt(retryCount, 10) || 0) !== 0 ? 1 : 0) +
    (retryBackoff !== "none" ? 1 : 0) +
    ((parseInt(timeout, 10) || 0) !== 0 ? 1 : 0) +
    (String(guardCondition || "").trim() !== "" ? 1 : 0)

  const advancedBodyHTML = `
    <div class="grid grid-cols-2 gap-2 pt-2.5">
      <div>
        <label class="block text-[11px] font-medium text-slate-500 mb-1">Retry Count</label>
        <input type="number" name="steps[${index}][retryCount]" min="0" max="5" value="${parseInt(retryCount, 10) || 0}"
               data-action="input->property-editor#updateStepOverrideBadge"
               class="${CONFIG_INPUT_CLASSES}">
      </div>
      <div>
        <label class="block text-[11px] font-medium text-slate-500 mb-1">Retry Backoff</label>
        <select name="steps[${index}][retryBackoff]"
                data-action="change->property-editor#updateStepOverrideBadge"
                class="${CONFIG_INPUT_CLASSES}">
          <option value="none"${retryBackoff === "none" ? " selected" : ""}>None</option>
          <option value="linear"${retryBackoff === "linear" ? " selected" : ""}>Linear</option>
          <option value="exponential"${retryBackoff === "exponential" ? " selected" : ""}>Exponential</option>
        </select>
      </div>
      <div>
        <label class="block text-[11px] font-medium text-slate-500 mb-1">Timeout (sec)</label>
        <input type="number" name="steps[${index}][timeout]" min="0" value="${parseInt(timeout, 10) || 0}"
               data-action="input->property-editor#updateStepOverrideBadge"
               class="${CONFIG_INPUT_CLASSES}">
      </div>
      <div>
        <label class="block text-[11px] font-medium text-slate-500 mb-1">Guard Condition</label>
        <input type="text" name="steps[${index}][guardCondition]" value="${escapeHtml(guardCondition)}"
               placeholder='ctx[:role] == "admin"'
               data-action="input->property-editor#updateStepOverrideBadge"
               class="${CONFIG_INPUT_CLASSES}">
      </div>
    </div>
  `

  const keywordParamsHTML = keywordParams.length > 0
    ? `<div class="text-[10px] text-slate-400">Params: ${keywordParams.map(p => escapeHtml(p)).join(", ")}</div>`
    : ""

  const bodyHTML = `
    <div data-step-details class="${expanded ? "" : "hidden"} pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-2">
      ${configFieldsHTML}
      ${description ? `<div class="text-[10px] text-slate-400">${escapeHtml(description)}</div>` : ""}
      ${keywordParamsHTML}
      ${buildDisclosureSection({
        id: `step-advanced-${index}`,
        label: "Advanced",
        badgeHTML: buildOverrideBadge(overrideCount),
        bodyHTML: advancedBodyHTML,
        startOpen: false
      })}
    </div>
  `

  const leadingHTML = `
    <div class="flex-shrink-0 cursor-grab active:cursor-grabbing text-slate-300 hover:text-slate-500"
         data-drag-handle title="Drag to reorder">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 8h16M4 16h16" />
      </svg>
    </div>
  `

  const trailingHTML = `
    <button type="button"
            data-action="click->property-editor#changeStep"
            class="text-[10px] font-medium text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 px-1.5 py-0.5 rounded transition-colors opacity-0 group-hover:opacity-100"
            title="Change action">Change</button>
    <button type="button"
            data-action="click->property-editor#removeStep"
            class="p-1 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-md opacity-0 group-hover:opacity-100 transition-all duration-150 flex-shrink-0"
            title="Remove step">
      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
      </svg>
    </button>
    <span data-step-expand-icon class="flex-shrink-0 inline-flex">
      <svg class="w-3 h-3 text-slate-300 group-hover:text-slate-500 transition-transform duration-150 ${expanded ? "rotate-90" : ""}"
           fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </span>
  `

  const hiddenInputsHTML = `
    <input type="hidden" name="steps[${index}][action]" value="${escapeHtml(action)}">
    <input type="hidden" name="steps[${index}][suboption]" value="${escapeHtml(suboption || "")}">
    <input type="hidden" name="steps[${index}][description]" value="${escapeHtml(description || "")}" data-step-description>
    ${selectionLabels ? `<input type="hidden" name="steps[${index}][selectionLabels]" value="${escapeHtml(JSON.stringify(selectionLabels))}">` : ""}
    <input type="hidden" name="steps[${index}][keywordParams]" value="${escapeHtml(JSON.stringify(keywordParams))}">
    <input type="hidden" name="steps[${index}][config]" value="${escapeHtml(JSON.stringify(currentConfig || {}))}" data-step-config>
  `

  return buildCompactItem({
    accentColor: colorName,
    title: breadcrumbTitle,
    leadingHTML,
    trailingHTML,
    bodyHTML,
    hiddenInputsHTML,
    headerAttrs: `data-action="click->property-editor#toggleStep"`,
    extraClasses: expanded ? "step-expanded" : "",
    extraAttrs: `data-step-item draggable="true" data-step-index="${index}" data-step-id="${escapeHtml(id)}" data-step-action="${escapeHtml(action)}" data-action="dragstart->property-editor#handleStepDragStart dragend->property-editor#handleStepDragEnd"`
  })
}
```

Then **delete** from `templates.js`: `buildStepModalTemplate` (220-307), `buildDropdownFieldTemplate` (317-338), `buildSelectionPathText` (603-633, now unused).

- [ ] **Step 4: `step_manager.js` rewrite.**

**Delete these members entirely** (line refs from current file): `openStepModal` (68-86), `closeStepModal` (88-119), `addKeywordParam` (124-178), `removeKeywordParam` (183-214), `_resetKeywordParams` (219-222), `_resetAdvancedFields` (227-246), `_addEmptyKeywordParamItem` (251-271), `_collectKeywordParams` (276-280), `addStepFromModal` (282-375), `handleDropdownChange` (582-653), `renderStepModal` (826-839), `_renderDropdownLevel` (1081-1191), `_getSubOptionLabel` (1193-1196), `_updateSubmitButtonState` (1198-1208), `_isStepSelectionComplete` (1210-1221), `populateQuickAddCategories` (1382-1391), `handleQuickAddCategoryChange` (1393-1420), `quickAddStep` (1425-1477), `_disableQuickAdd` (1482-1490). In the constructor (47-53) delete `this._stepSelectionPath = []` and `this._availableActions = []`; in `reset()` (59-63) delete the `_stepSelectionPath` line. Keep: drag handlers, `toggleStep`, `collectSteps`, `collectRenderedConfigFieldKeys`, `collectStepConfig`, `getUsedSingleUseActions`, `buildStepConfigHTML`, `_collapseAllSteps`, `_setStepExpanded`, `_reindexSteps`, `handleConfigFieldChange`, `addConfigKvRow`, `removeConfigKvRow`. (`STEP_PRESETS`/`applyPreset` are deleted in Task 6.)

**Update imports** (lines 6-16):
```js
import { escapeHtml, generateStepId } from "utils"
import {
  buildStepPickerTemplate,
  buildStepItemTemplate,
  buildSectionHeader,
  buildStepConfigFieldsHTML
} from "controllers/property_editor/templates"
import { ModalMixin } from "controllers/property_editor/modal_mixin"
import { BaseManager } from "controllers/property_editor/base_manager"
import { getActionConfig, getSingleUseActions, getActionsByCategory } from "flowchart/constants/action_registry"
```
(`getColorClasses` import dropped — no remaining use in this file.)

**Replace `buildStepsFieldHTML` (841-962)** with:

```js
buildStepsFieldHTML(fieldName, fieldSchema, currentValue) {
  const steps = Array.isArray(currentValue) ? currentValue : []
  const actionOptions = fieldSchema.actionOptions || []

  let stepsHTML = `
    <div class="space-y-3">
      <section>
        ${buildSectionHeader({ label: fieldSchema.label || "Step" })}
        <div data-steps-container class="space-y-1"
             data-action="dragover->property-editor#handleStepDragOver drop->property-editor#handleStepDrop">
  `

  // Render existing steps (collapsed — reload state)
  steps.forEach((step, index) => {
    const actionOption = actionOptions.find(opt => opt.value === step.action)
    let selectionLabels = null
    if (step.selectionLabels) {
      try {
        selectionLabels = typeof step.selectionLabels === "string"
          ? JSON.parse(step.selectionLabels) : step.selectionLabels
      } catch { selectionLabels = null }
    }
    let keywordParams = []
    if (step.keywordParams) {
      try {
        keywordParams = typeof step.keywordParams === "string"
          ? JSON.parse(step.keywordParams) : step.keywordParams
      } catch { keywordParams = [] }
    }
    let currentConfig = {}
    if (step.config) {
      try {
        currentConfig = typeof step.config === "string" ? JSON.parse(step.config) : step.config
      } catch { currentConfig = {} }
    }
    stepsHTML += this.buildStepItemHTML(
      index, step.action || "", step.description || "", actionOptions,
      false, // collapsed on reload
      step.suboption || "", actionOption, selectionLabels, keywordParams,
      parseInt(step.retryCount || "0", 10) || 0,
      step.retryBackoff || "none",
      parseInt(step.timeout || "0", 10) || 0,
      step.guardCondition || "",
      currentConfig,
      step.id || generateStepId()
    )
    this.stepIndex = index + 1
  })

  stepsHTML += `
        </div>
        <div data-step-picker-mount class="${steps.length >= 1 ? "hidden" : "mt-1"}">
          ${this.buildStepPickerHTML()}
        </div>
      </section>
      <input type="hidden" data-action-options value="${escapeHtml(JSON.stringify(actionOptions))}">
    </div>
  `
  return stepsHTML
}
```
(Note: `data-steps-empty` is gone — the picker IS the empty state per UX §2.4. The quick-add `Configure` section, `renderStepModal()` call, and `populateQuickAddCategories` setTimeout are all removed.)

**Add picker methods:**

```js
// ===================
// Inline Action Picker
// ===================

/**
 * Build the inline picker HTML and (re)build the leaf lookup map.
 * subOptions trees are flattened to selectable leaves; the leaf value encodes
 * "action" or "action::sub/path". singleUse actions already present render
 * disabled but visible.
 */
buildStepPickerHTML() {
  const grouped = getActionsByCategory()
  const usedSingleUse = this.getUsedSingleUseActions()
  const singleUseList = getSingleUseActions()

  this._pickerLeafMap = {}
  const optionsData = grouped.map(g => ({
    group: g.category.label,
    items: this._flattenActionLeaves(g.actions, usedSingleUse, singleUseList)
  }))

  const optionsJSON = JSON.stringify(optionsData).replace(/'/g, "&#39;")
  return buildStepPickerTemplate(optionsJSON)
}

_flattenActionLeaves(actions, usedSingleUse, singleUseList) {
  const items = []
  const walk = (node, rootAction, pathValues, pathLabels) => {
    const subOptions = node.subOptions || []
    if (subOptions.length === 0) {
      const subPath = pathValues.slice(1).join("/")
      const value = subPath ? `${rootAction.value}::${subPath}` : rootAction.value
      const display = pathLabels.join(" \u203A ")
      const disabled = singleUseList.includes(rootAction.value) && usedSingleUse.includes(rootAction.value)
      this._pickerLeafMap[value] = {
        action: rootAction.value,
        suboption: subPath,
        selectionLabels: [...pathLabels],
        actionOption: rootAction
      }
      items.push([display, value, {
        icon: rootAction.icon,
        color: rootAction.color,
        description: node.description || rootAction.description,
        disabled
      }])
      return
    }
    subOptions.forEach(sub => walk(sub, rootAction, [...pathValues, sub.value], [...pathLabels, sub.label]))
  }
  actions.forEach(a => walk(a, a, [a.value], [a.label]))
  return items
}

/**
 * Commit handler — fired by the picker's hidden input `change` event
 * (dispatched by searchable_select_controller#select). Commits immediately:
 * builds the expanded card with defaulted config and removes the picker.
 */
stepPickerCommit(event) {
  const value = event.target.value
  if (!value) return
  const leaf = this._pickerLeafMap?.[value]
  if (!leaf) return

  const container = this.controller.formFieldsTarget.querySelector("[data-steps-container]")
  if (!container) return
  // One step per process element
  if (container.querySelectorAll("[data-step-item]").length >= 1) return

  // A commit during a Change flow confirms the replacement — drop the snapshot.
  this._changeSnapshot = null

  const actionEntry = getActionConfig(leaf.action)
  const defaultConfig = {}
  if (actionEntry) {
    const schema = actionEntry.configSchemaBySubOption?.[leaf.suboption] || actionEntry.configSchema || []
    schema.forEach(field => {
      if (field.default !== undefined) defaultConfig[field.key] = field.default
    })
  }

  const stepHtml = this.buildStepItemHTML(
    this.stepIndex, leaf.action, "", null,
    true, // expanded — just-added
    leaf.suboption, leaf.actionOption, leaf.selectionLabels, [],
    0, "none", 0, "", defaultConfig, generateStepId()
  )
  container.insertAdjacentHTML("beforeend", stepHtml)
  this.stepIndex++

  this._hideStepPicker()
  this._dispatchEvent("stepAdded")
}

/**
 * "Change" affordance: detach the committed card (live DOM node — preserves
 * edited input values), re-open the picker. Escape restores the node unchanged.
 */
changeStep(event) {
  event.preventDefault()
  const stepItem = event.target.closest("[data-step-item]")
  if (!stepItem) return
  this._changeSnapshot = stepItem
  stepItem.remove()
  this._showStepPicker({ focus: true })
}

stepPickerEscape() {
  if (!this._changeSnapshot) return
  const container = this.controller.formFieldsTarget.querySelector("[data-steps-container]")
  if (container) container.appendChild(this._changeSnapshot)
  this._changeSnapshot = null
  this._hideStepPicker()
}

_showStepPicker({ focus = false } = {}) {
  const mount = this.controller.formFieldsTarget.querySelector("[data-step-picker-mount]")
  if (!mount) return
  // Re-render so singleUse disabled states reflect the current step list
  mount.innerHTML = this.buildStepPickerHTML()
  mount.classList.remove("hidden")
  if (focus) {
    setTimeout(() => mount.querySelector("input[type='text']")?.focus(), 50)
  }
}

_hideStepPicker() {
  const mount = this.controller.formFieldsTarget.querySelector("[data-step-picker-mount]")
  if (!mount) return
  mount.classList.add("hidden")
  const search = mount.querySelector("input[type='text']")
  if (search) search.value = ""
  const hidden = mount.querySelector("input[type='hidden']")
  if (hidden) hidden.value = ""
}

/**
 * Override-badge updater for the inline Advanced disclosure.
 * N = count of (retryCount !== 0, retryBackoff !== "none", timeout !== 0, guardCondition !== "").
 */
updateStepOverrideBadge(event) {
  const stepItem = event.target.closest("[data-step-item]")
  if (!stepItem) return
  const retryCount = parseInt(stepItem.querySelector("[name*='[retryCount]']")?.value || "0", 10) || 0
  const retryBackoff = stepItem.querySelector("[name*='[retryBackoff]']")?.value || "none"
  const timeout = parseInt(stepItem.querySelector("[name*='[timeout]']")?.value || "0", 10) || 0
  const guardCondition = stepItem.querySelector("[name*='[guardCondition]']")?.value?.trim() || ""
  const count =
    (retryCount !== 0 ? 1 : 0) + (retryBackoff !== "none" ? 1 : 0) +
    (timeout !== 0 ? 1 : 0) + (guardCondition !== "" ? 1 : 0)

  const badge = stepItem.querySelector("[data-override-badge]")
  if (!badge) return
  badge.textContent = `${count} override${count === 1 ? "" : "s"}`
  badge.classList.toggle("hidden", count === 0)
}
```

**Update `removeStep` (399-431):** delete the quick-add re-enable block (lines 414-427) and the empty-state block (407-412); after `stepItem.remove()` add:
```js
// Re-open the picker — it is the empty state
this._changeSnapshot = null
this._showStepPicker()
```

**Update `buildStepItemHTML` (964-1005):** rename the 5th param `collapsed` → `expanded` and pass it through to `buildStepItemTemplate` as `expanded` (add `expanded` to the object passed at line 989).

**Update `collectSteps` (671-674):** make the four advanced selectors tagless so the new `<select>` for retryBackoff is found (output logic untouched):
```js
// BEFORE
const retryCountInput = item.querySelector("input[name*='[retryCount]']")
const retryBackoffInput = item.querySelector("input[name*='[retryBackoff]']")
const timeoutInput = item.querySelector("input[name*='[timeout]']")
const guardConditionInput = item.querySelector("input[name*='[guardCondition]']")
// AFTER
const retryCountInput = item.querySelector("[name*='[retryCount]']")
const retryBackoffInput = item.querySelector("[name*='[retryBackoff]']")
const timeoutInput = item.querySelector("[name*='[timeout]']")
const guardConditionInput = item.querySelector("[name*='[guardCondition]']")
```

**Update `_reindexSteps` (1064-1068):** the advanced inputs include a `<select>`; broaden:
```js
// BEFORE
const inputs = item.querySelectorAll("input[name^='steps[']")
// AFTER
const inputs = item.querySelectorAll("[name^='steps[']")
```

- [ ] **Step 5: Controller wiring** (`property_editor_controller.js`):

Delete delegates: `openStepModal` (451-453 + doc comment 446-450), `closeStepModal` (455-457), `addStepFromModal` (459-461), `addKeywordParam` (463-465), `removeKeywordParam` (467-469), `handleDropdownChange` (495-497), `toggleStepAdvanced` (511-520), `handleQuickAddCategoryChange` (529-531), `quickAddStep` (533-536). Remove `"stepModalContainer"` from targets (line 26).

Add delegates:
```js
stepPickerCommit(event) {
  this.stepManager.stepPickerCommit(event)
}

stepPickerEscape(event) {
  this.stepManager.stepPickerEscape(event)
}

changeStep(event) {
  this.stepManager.changeStep(event)
}

updateStepOverrideBadge(event) {
  this.stepManager.updateStepOverrideBadge(event)
}
```

- [ ] **Step 6: Remove the step modal container** — `_editor.html.erb` lines 573-574 (delete the comment + `<div data-property-editor-target="stepModalContainer" ...></div>`), and `form_builder.js` lines 80-83 (the `hasStepModalContainerTarget` clearing block).

- [ ] **Step 7: Syntax checks**

```bash
for f in app/javascript/controllers/searchable_select_controller.js app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/step_manager.js app/javascript/controllers/property_editor_controller.js app/javascript/controllers/property_editor/form_builder.js; do node --input-type=module --check < "$f" || exit 1; done; echo OK
```
Expected: `OK`. Also `grep -rn "stepModalContainer\|buildStepModalTemplate\|buildDropdownFieldTemplate\|data-step-quick\|handleDropdownChange\|addStepFromModal\|openStepModal" app/javascript app/views` → only `modal_mixin.js` doc-comment mention of `[data-step-modal]` may remain (update that comment to `[data-branch-modal]`).

- [ ] **Step 8: Manual verification** (`bin/dev`, Process element):
  - Step tab opens with picker as hero; focusing input shows all categories **expanded** with headings; typing filters across label/description/category; no-results message for garbage query.
  - ↑/↓ + Enter commits immediately (no confirm button); click commits too. Card renders **expanded** with config defaults pre-filled and `visibleWhen` dependents correct from first paint (e.g. Find Model → strategy-dependent fields).
  - Picker hidden after commit (one step max). Remove step → picker returns.
  - `singleUse` already-used action shows disabled with "(already used)" suffix after Change is clicked (step still in snapshot is detached — it should NOT be disabled; verify it's selectable again).
  - Advanced disclosure: collapsed by default; set Retry Count 3 → badge "1 override"; set backoff Linear → "2 overrides"; clear → badge hides.
  - Change button: edit a config value first, click Change, press Escape → card restored **with the edited value intact** (live-node detach). Click Change, pick a different action → replaced, new card expanded.
  - Reload a saved element: card starts collapsed; header click toggles; chevron rotates.
  - Save, inspect `properties.steps[0]` JSON: identical shape to pre-refactor (id/action/description/suboption/selectionLabels/keywordParams/retryCount+retryBackoff only when >0, timeout only when >0, guardCondition only when set, merged config).
  - Element label auto-derivation still works (`_deriveLabelFromSteps` consumes selectionLabels).

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/searchable_select_controller.js app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/step_manager.js app/javascript/controllers/property_editor_controller.js app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor/modal_mixin.js app/views/admin/maintenance/flowcharts/_editor.html.erb
git commit -m "feat(property-editor): inline searchable step picker; delete step modal and quick-add

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Decision Branches — preset chips, left-operand select, readable cards, name validation, delete quick-add

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (`buildBranchModalTemplate` body 670-727; rewrite `buildBranchItemTemplate` 823-877)
- Modify: `app/javascript/controllers/property_editor/branch_manager.js` (`openBranchModal` onOpen 36-88; `addBranchFromModal` 198-208; delete `quickAddBranch` 298-394; `buildBranchesFieldHTML` 673-746; `_collectFieldCondition` 1150-1163; `_loadQueryCountEntities` 1049-1077; new methods)
- Modify: `app/javascript/controllers/property_editor_controller.js` (delete `quickAddBranch` 563-566; add 4 delegates)
- Modify: `app/javascript/flowchart/constants/schemas.js` (delete `conditionOptions: BRANCH_CONDITIONS` line 365; delete `BRANCH_CONDITIONS` 70-134 — grep-verified unused elsewhere)
- Test: manual; syntax checks

- [ ] **Step 1: `buildBranchModalTemplate` body changes** (within lines 670-727). Insert the preset row as the **first** child of the body `div` (before "Branch Name"):

```html
<!-- Preset chips -->
<div>
  <label class="block text-[11px] font-medium text-slate-500 mb-1">Preset</label>
  <div class="flex flex-wrap gap-1.5" data-branch-preset-row>
    <button type="button" data-preset="yes" data-active="false"
            data-action="click->property-editor#applyBranchPreset"
            class="px-3 py-1 text-[11px] font-medium text-slate-600 bg-white border border-slate-200 rounded-full hover:border-slate-300 hover:bg-slate-50 transition-colors">Yes</button>
    <button type="button" data-preset="no" data-active="false"
            data-action="click->property-editor#applyBranchPreset"
            class="px-3 py-1 text-[11px] font-medium text-slate-600 bg-white border border-slate-200 rounded-full hover:border-slate-300 hover:bg-slate-50 transition-colors">No</button>
    <button type="button" data-preset="otherwise" data-active="false"
            data-action="click->property-editor#applyBranchPreset"
            class="px-3 py-1 text-[11px] font-medium text-slate-600 bg-white border border-slate-200 rounded-full hover:border-slate-300 hover:bg-slate-50 transition-colors">Otherwise</button>
    <button type="button" data-preset="custom" data-active="false"
            data-action="click->property-editor#applyBranchPreset"
            class="px-3 py-1 text-[11px] font-medium text-slate-600 bg-white border border-slate-200 rounded-full hover:border-slate-300 hover:bg-slate-50 transition-colors">Custom</button>
  </div>
</div>
```

Replace the left-operand input inside `[data-branch-condition-field-panel]` (lines 704-726) — the `flex items-center gap-1.5` row's first child changes from a text input to a select+manual swap (operator select and right input unchanged):

```html
<!-- BEFORE -->
<input type="text" data-branch-condition-left placeholder="ctx[:field]" class="flex-1 px-2 py-1.5 text-xs font-mono ...">
<!-- AFTER -->
<div class="flex-1 min-w-0">
  <select data-branch-condition-left-select
          data-action="change->property-editor#handleBranchLeftOperandChange"
          class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-400">
    <option value="">Select operand...</option>
  </select>
  <div data-branch-condition-left-manual class="hidden flex gap-1">
    <input type="text"
           data-branch-condition-left
           placeholder="ctx[:field]"
           class="flex-1 min-w-0 px-2 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-400">
    <button type="button"
            data-action="click->property-editor#swapLeftOperandToSelect"
            class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50"
            title="Switch to dropdown">&#x25B2;</button>
  </div>
</div>
```

- [ ] **Step 2: rewrite `buildBranchItemTemplate` (823-877)** onto the unified card + summary helper (add `buildCompactItem, buildConditionSummaryText` to the import in `branch_manager.js`'s template usage — the function lives in templates.js so only templates.js internals change):

```js
export function buildBranchItemTemplate(params) {
  const { index, branchValue, description, branchElementId, condition } = params
  const branchName = branchValue || `Branch ${index}`

  const summaryText = buildConditionSummaryText(condition)
  const subtitleHTML = condition && summaryText
    ? `<div class="text-[10px] font-mono text-slate-400 mt-0.5 truncate">${escapeHtml(summaryText)}</div>`
    : `<div class="mt-0.5"><span class="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 bg-amber-50 border border-amber-200 rounded-full">no condition &mdash; always matches</span></div>`

  const trailingHTML = `
    <button type="button"
            data-action="click->property-editor#removeBranch"
            class="p-1 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-md opacity-0 group-hover:opacity-100 transition-all duration-150 flex-shrink-0"
            title="Remove branch">
      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
      </svg>
    </button>
  `

  const bodyHTML = description
    ? `<div class="pl-5 mt-0.5 text-[10px] text-slate-400">${escapeHtml(description)}</div>`
    : ""

  const hiddenInputsHTML = `
    <input type="hidden" name="branches[${index}][name]" value="${escapeHtml(branchName)}">
    <input type="hidden" name="branches[${index}][description]" value="${escapeHtml(description || "")}">
    ${branchElementId ? `<input type="hidden" name="branches[${index}][elementId]" value="${escapeHtml(branchElementId)}">` : ""}
    ${condition ? `<input type="hidden" name="branches[${index}][condition]" value="${escapeHtml(JSON.stringify(condition))}">` : ""}
  `

  return buildCompactItem({
    accentColor: "amber",
    title: branchName,
    subtitleHTML,
    trailingHTML,
    bodyHTML,
    hiddenInputsHTML,
    extraAttrs: `data-branch-item data-branch-index="${index}"${branchElementId ? ` data-branch-element-id="${escapeHtml(branchElementId)}"` : ""}`
  })
}
```
(The summary is built fresh from the condition object at insert time — satisfies UX critical flag 9.)

- [ ] **Step 3: `branch_manager.js` — new methods + onOpen reset.**

Add chip class constants + methods (near the modal section):

```js
const CHIP_INACTIVE_CLASSES = "px-3 py-1 text-[11px] font-medium text-slate-600 bg-white border border-slate-200 rounded-full hover:border-slate-300 hover:bg-slate-50 transition-colors"
const CHIP_ACTIVE_CLASSES = "px-3 py-1 text-[11px] font-medium text-indigo-700 bg-indigo-50 border border-indigo-300 rounded-full ring-1 ring-indigo-200"
```

```js
// ===================
// Preset Chips + Left Operand
// ===================

/**
 * Pre-fill modal fields from a preset chip. Pre-fill only — never locks
 * fields, never commits. Clicking the active chip deselects (custom/blank).
 */
applyBranchPreset(event) {
  event.preventDefault()
  const chip = event.currentTarget
  const modal = chip.closest("[data-branch-modal]")
  if (!modal) return

  const wasActive = chip.dataset.active === "true"
  modal.querySelectorAll("[data-branch-preset-row] button[data-preset]").forEach(b => this._setChipActive(b, false))

  if (wasActive) {
    this._applyPresetValues(modal, "custom")
    return
  }
  this._setChipActive(chip, true)
  this._applyPresetValues(modal, chip.dataset.preset)
}

_setChipActive(chip, active) {
  chip.dataset.active = active ? "true" : "false"
  chip.className = active ? CHIP_ACTIVE_CLASSES : CHIP_INACTIVE_CLASSES
}

_applyPresetValues(modal, preset) {
  const nameInput = modal.querySelector("[data-branch-name]")
  const leftSelect = modal.querySelector("[data-branch-condition-left-select]")
  const opSelect = modal.querySelector("[data-branch-condition-op]")
  const rightInput = modal.querySelector("[data-branch-condition-right]")

  // First upstream output if present, else "signal" (literals excluded)
  const literals = ["true", "false", "null", "ctx"]
  const firstUpstream = (this._availableOutputOptions || [])
    .find(o => !literals.includes(o.value))?.value || "signal"

  // Presets always target the Field Condition type with the select visible
  this._resetLeftOperandSwap(modal)

  switch (preset) {
    case "yes":
      if (nameInput) nameInput.value = "Yes"
      if (leftSelect) leftSelect.value = firstUpstream
      if (opSelect) opSelect.value = "=="
      if (rightInput) rightInput.value = "true"
      break
    case "no":
      if (nameInput) nameInput.value = "No"
      if (leftSelect) leftSelect.value = firstUpstream
      if (opSelect) opSelect.value = "=="
      if (rightInput) rightInput.value = "false"
      break
    case "otherwise":
      if (nameInput) nameInput.value = "Otherwise"
      if (leftSelect) leftSelect.value = ""
      if (opSelect) opSelect.value = "=="
      if (rightInput) rightInput.value = ""
      break
    case "custom":
    default:
      if (nameInput) nameInput.value = ""
      if (leftSelect) leftSelect.value = ""
      if (opSelect) opSelect.value = "=="
      if (rightInput) rightInput.value = ""
      break
  }

  if (nameInput) { nameInput.focus(); nameInput.select() }
}

/**
 * Left operand select change: "__manual__" swaps to a text input; any real
 * value defaults the operator to "==" and moves focus to the operator select.
 */
handleBranchLeftOperandChange(event) {
  const modal = event.target.closest("[data-branch-modal]")
  if (!modal) return
  if (event.target.value === "__manual__") {
    this.swapLeftOperandToManual(event)
    return
  }
  const opSelect = modal.querySelector("[data-branch-condition-op]")
  if (opSelect && event.target.value) {
    if (!opSelect.value) opSelect.value = "=="
    opSelect.focus()
  }
}

swapLeftOperandToManual(event) {
  if (event.preventDefault) event.preventDefault()
  const modal = event.target.closest("[data-branch-modal]")
  if (!modal) return
  const select = modal.querySelector("[data-branch-condition-left-select]")
  const manual = modal.querySelector("[data-branch-condition-left-manual]")
  if (select) { select.classList.add("hidden"); select.value = "" }
  if (manual) {
    manual.classList.remove("hidden")
    const input = manual.querySelector("[data-branch-condition-left]")
    if (input) { input.value = ""; input.focus() }
  }
}

swapLeftOperandToSelect(event) {
  event.preventDefault()
  const modal = event.target.closest("[data-branch-modal]")
  if (!modal) return
  this._resetLeftOperandSwap(modal)
}

_resetLeftOperandSwap(modal) {
  const select = modal.querySelector("[data-branch-condition-left-select]")
  const manual = modal.querySelector("[data-branch-condition-left-manual]")
  if (manual) {
    manual.classList.add("hidden")
    const input = manual.querySelector("[data-branch-condition-left]")
    if (input) input.value = ""
  }
  if (select) select.classList.remove("hidden")
}

/** Seed the left-operand select: signals/ctx/entity fields/parent outputs + manual escape hatch. */
_populateLeftOperandSelect(modal) {
  const select = modal.querySelector("[data-branch-condition-left-select]")
  if (!select) return
  this._availableOutputOptions = this._getParentOutputOptions()
  select.innerHTML =
    this._buildContextAwareLeftOperandOptions("") +
    `<optgroup label="Other"><option value="__manual__">enter manually&hellip;</option></optgroup>`
}
```

**`openBranchModal` onOpen (lines 36-88) updates:** replace the condition reset block (44-49) with:
```js
// Reset condition fields (select + manual swap + op + right)
this._populateLeftOperandSelect(modal)
this._resetLeftOperandSwap(modal)
const condRight = modal.querySelector("[data-branch-condition-right]")
const condOp    = modal.querySelector("[data-branch-condition-op]")
if (condRight) condRight.value = ""
if (condOp)    condOp.value    = "=="

// Reset preset chips
modal.querySelectorAll("[data-branch-preset-row] button[data-preset]")
  .forEach(b => this._setChipActive(b, false))
```
(Everything else in onOpen — toggle reset, panels, query-count reset, submit enable — stays.)

**`_collectFieldCondition` (1150-1163):** read whichever left widget is visible:
```js
_collectFieldCondition(modal) {
  const manualWrap = modal.querySelector("[data-branch-condition-left-manual]")
  const manualVisible = manualWrap && !manualWrap.classList.contains("hidden")
  const conditionLeft = manualVisible
    ? (modal.querySelector("[data-branch-condition-left]")?.value?.trim() || "")
    : (modal.querySelector("[data-branch-condition-left-select]")?.value?.trim() || "")
  const conditionOp = modal.querySelector("[data-branch-condition-op]")?.value || "=="
  const conditionRight = this._operatorNeedsRightOperand(conditionOp)
    ? (modal.querySelector("[data-branch-condition-right]")?.value?.trim() || "")
    : ""

  if (conditionLeft.length === 0) return null

  return { type: "single", leftOperand: conditionLeft, operator: conditionOp, rightOperand: conditionRight }
}
```
(`__manual__` can never leak: selecting it immediately swaps and clears the select.)

**`addBranchFromModal` (198-208):** require name —
```js
const branchNameInput = modal.querySelector("[data-branch-name]")
const branchName = branchNameInput?.value?.trim() || ""
if (!branchName) {
  this._highlightFieldError(branchNameInput)
  return
}
...
const displayLabel = branchName  // fallback removed
```
**Do not touch anything from the `container` lookup (line 210) onward** — canvas order is sacrosanct.

**`_loadQueryCountEntities` (1049-1077):** render a disabled error option on failure. Replace the `if (!response.ok) return` and the empty catch:
```js
if (!response.ok) { this._appendEntityLoadError(entitySelect); return }
...
} catch (e) {
  this._appendEntityLoadError(entitySelect)
}
```
with helper:
```js
_appendEntityLoadError(entitySelect) {
  if (entitySelect.querySelector("option[data-entity-load-error]")) return
  const option = document.createElement("option")
  option.value = ""
  option.disabled = true
  option.setAttribute("data-entity-load-error", "")
  option.textContent = "Could not load entities"
  entitySelect.appendChild(option)
}
```

**Delete `quickAddBranch` (298-394) entirely.**

- [ ] **Step 4: rewrite `buildBranchesFieldHTML` (673-746)** — section header with live count, shared empty state, no quick-add row:

```js
buildBranchesFieldHTML(fieldName, fieldSchema, currentValue) {
  const branches = Array.isArray(currentValue) ? currentValue : []

  let branchesHTML = `
    <div class="mb-4" data-branches-section>
      ${buildSectionHeader({ label: fieldSchema.label || "Branches", count: branches.length })}
      <div data-branches-container class="space-y-1">
        <div data-branches-empty class="${branches.length > 0 ? "hidden" : ""}">
          ${buildEmptyState('No branches yet. Click "Add Branch" to create the first route.')}
        </div>
  `

  branches.forEach((branch, index) => {
    branchesHTML += this.buildBranchItemHTML(
      index,
      branch.name || branch.value || `Branch ${index}`,
      branch.description || "",
      branch.elementId || null,
      branch.condition || null
    )
    this.branchIndex = index + 1
  })

  branchesHTML += `
      </div>
      <button type="button"
              data-action="click->property-editor#openBranchModal"
              class="mt-2 w-full inline-flex items-center justify-center px-2 py-1.5 text-xs font-medium text-amber-600 bg-amber-50 border border-amber-200 rounded hover:bg-amber-100 transition-colors">
        <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
        Add Branch
      </button>
    </div>
  `

  this.renderBranchModal()
  return branchesHTML
}
```

Update imports at top of `branch_manager.js`:
```js
import { buildBranchModalTemplate, buildBranchItemTemplate, buildSectionHeader, buildEmptyState } from "controllers/property_editor/templates"
```

Add count refresh helper and call it at the end of `addBranchFromModal` (just before `this.closeBranchModal()`) and `removeBranch` (after the canvas block):
```js
_updateBranchSectionCount() {
  const section = this.controller.formFieldsTarget.querySelector("[data-branches-section]")
  if (!section) return
  const badge = section.querySelector("[data-section-count]")
  const count = section.querySelectorAll("[data-branch-item]").length
  if (badge) badge.textContent = count
}
```

- [ ] **Step 5: Controller + schema cleanup.** In `property_editor_controller.js` delete `quickAddBranch` (563-566) and add delegates:
```js
applyBranchPreset(event) {
  this.branchManager.applyBranchPreset(event)
}

handleBranchLeftOperandChange(event) {
  this.branchManager.handleBranchLeftOperandChange(event)
}

swapLeftOperandToManual(event) {
  this.branchManager.swapLeftOperandToManual(event)
}

swapLeftOperandToSelect(event) {
  this.branchManager.swapLeftOperandToSelect(event)
}
```
In `schemas.js`: delete `conditionOptions: BRANCH_CONDITIONS,` (line 365) and the whole `BRANCH_CONDITIONS` export (lines 70-134; grep-verified: no other reference).

- [ ] **Step 6: Syntax checks**

```bash
for f in app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor_controller.js app/javascript/flowchart/constants/schemas.js; do node --input-type=module --check < "$f" || exit 1; done; echo OK
```
Expected: `OK`. Also: `grep -rn "quickAddBranch\|data-branch-quick\|BRANCH_CONDITIONS" app/javascript app/views` → 0 matches.

- [ ] **Step 7: Manual verification** (`bin/dev`, Decision element):
  - Branches tab: section header "Branches [N]"; dashed empty state when none; single "Add Branch" path (quick-add row gone).
  - Modal: chips row first; "Yes" chip → name "Yes", left = first parent output (or "signal"), op "==", right "true"; all fields still editable; clicking "Yes" again deselects → blank. "Otherwise" → name only, no operands.
  - Left operand select shows Signals/Context/Entity Fields/Parent Outputs optgroups + "enter manually…"; choosing it swaps to mono text input with ▲ revert; choosing a real operand focuses the operator select.
  - Empty name + Add Branch → red ring on name, submit blocked, modal stays open.
  - Add "Yes" preset branch → card shows "Yes" with mono summary "signal equals true"; canvas spawns the process element + labeled connection at the right port; undo (Ctrl+Z) reverts cleanly (order preserved).
  - Add "Otherwise" → amber "no condition — always matches" pill.
  - Remove branch → connections remapped, count badge updates, empty state returns at zero.
  - Query Count tab unchanged; kill network (devtools offline) and switch to Query Count → "Could not load entities" disabled option.
  - Save / reopen / re-save: `properties.branches[]` round-trips byte-identical (`name, description, branchKey, elementId, condition`), condition mirrored on connection.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor_controller.js app/javascript/flowchart/constants/schemas.js
git commit -m "feat(property-editor): branch preset chips, seeded left-operand select, readable cards; delete branch quick-add

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: ViewComponent parity (CompactItemComponent) + component specs

**Files:**
- Modify: `app/components/property_editor/compact_item_component.html.erb`
- Test: `spec/components/property_editor/compact_item_component_spec.rb`
- (No changes: `section_header_component`, `empty_state_component`, `segmented_control_component`, `inline_condition_component` — UX §4 says reuse unchanged; no `DisclosureSectionComponent` is created per UX flag 10.)

- [ ] **Step 1: Update the failing-first spec** — edit `spec/components/property_editor/compact_item_component_spec.rb` to assert the unified-card markup:

```ruby
require "rails_helper"

RSpec.describe PropertyEditor::CompactItemComponent, type: :component do
  it "renders with accent color" do
    render_inline(described_class.new(accent_color: "indigo")) do |c|
      c.with_title { "My Item" }
    end
    expect(page).to have_text("My Item")
    expect(page).to have_css(".border-l-2.border-indigo-400")
  end

  it "renders the title and subtitle stacked (subtitle below title)" do
    render_inline(described_class.new(accent_color: "amber")) do |c|
      c.with_title { "Branch" }
      c.with_subtitle { "ctx.status equals active" }
    end
    expect(page).to have_css(".font-mono", text: "ctx.status equals active")
    # subtitle sits inside the same flex-1 column as the title
    expect(page).to have_css("div.flex-1 .font-mono")
  end

  it "reveals trailing actions on hover via group-hover" do
    render_inline(described_class.new(accent_color: "indigo")) do |c|
      c.with_title { "Step" }
      c.with_trailing { tag.button("x") }
    end
    expect(page).to have_css(".ml-auto.opacity-0.group-hover\\:opacity-100 button", text: "x")
  end

  it "renders expandable content when expandable" do
    render_inline(described_class.new(accent_color: "indigo", expandable: true)) do |c|
      c.with_title { "Step" }
      c.with_expandable_content { "config body" }
    end
    expect(page).to have_css("[data-compact-item-content]", text: "config body")
  end
end
```

- [ ] **Step 2: Run to verify the new assertions fail**

```bash
bundle exec rspec spec/components/property_editor/compact_item_component_spec.rb
```
Expected: FAIL on the stacked-subtitle and ml-auto trailing examples (current template renders subtitle inline and trailing without `ml-auto`).

- [ ] **Step 3: Update `compact_item_component.html.erb`** to mirror `buildCompactItem` (Task 1):

```erb
<div class="relative border-l-2 <%= accent_border_class %> border-b border-b-slate-100 px-2.5 py-2 hover:bg-slate-50 transition-colors group">
  <div class="flex items-center gap-2">
    <% if leading? %>
      <%= leading %>
    <% end %>
    <div class="w-2 h-2 rounded-full bg-<%= @accent_color %>-500 flex-shrink-0"></div>
    <div class="flex-1 min-w-0 cursor-pointer">
      <% if title? %>
        <div class="text-xs font-medium text-slate-800 truncate"><%= title %></div>
      <% end %>
      <% if subtitle? %>
        <div class="text-[10px] font-mono text-slate-400 mt-0.5 truncate"><%= subtitle %></div>
      <% end %>
    </div>
    <% if trailing? %>
      <div class="ml-auto flex items-center gap-0.5 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
        <%= trailing %>
      </div>
    <% end %>
  </div>
  <% if expandable? && expandable_content? %>
    <div class="pl-6 mt-1.5" data-compact-item-content>
      <%= expandable_content %>
    </div>
  <% end %>
</div>
```
(`compact_item_component.rb` unchanged.)

- [ ] **Step 4: Run all property_editor component specs**

```bash
bundle exec rspec spec/components/property_editor/
```
Expected: all green (the other four components are untouched).

- [ ] **Step 5: Commit**

```bash
git add app/components/property_editor/compact_item_component.html.erb spec/components/property_editor/compact_item_component_spec.rb
git commit -m "feat(property-editor): align CompactItemComponent with unified JS card template

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Dead-code sweep + final verification

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js` (`STEP_PRESETS` 19-44, `applyPreset` 1223-1272)
- Modify: `app/javascript/controllers/property_editor_controller.js` (`applyStepPreset` 522-527)
- Modify: `app/javascript/controllers/property_editor/modal_mixin.js:15` (doc-comment example, if not already updated in Task 3)
- Test: greps + full component suite + final manual smoke

- [ ] **Step 1: Delete `STEP_PRESETS` + `applyPreset` + `applyStepPreset`** (grep-verified: no view or JS markup references `applyStepPreset`; `applyPreset` is only reachable from it).

- [ ] **Step 2: Orphan greps — every command must return 0 matches:**

```bash
grep -rn "openStepModal\|closeStepModal\|addStepFromModal\|addKeywordParam\|removeKeywordParam\|handleDropdownChange\|toggleStepAdvanced\|applyStepPreset\|applyPreset\|STEP_PRESETS" app/javascript app/views
grep -rn "buildStepModalTemplate\|buildDropdownFieldTemplate\|buildSelectionPathText" app/javascript
grep -rn "data-step-quick\|data-steps-empty\|data-step-modal\b" app/javascript app/views
grep -rn "quickAddBranch\|data-branch-quick\|BRANCH_CONDITIONS\|conditionOptions" app/javascript app/views
grep -rn "stepModalContainer" app/javascript app/views
```

- [ ] **Step 3: Full syntax + spec pass**

```bash
for f in $(git diff --name-only HEAD~5 -- 'app/javascript/**/*.js'); do node --input-type=module --check < "$f" || exit 1; done; echo JS_OK
bundle exec rspec spec/components/property_editor/ spec/system/property_editor/element_io_tab_spec.rb
```
Expected: `JS_OK`; component specs pass; `element_io_tab_spec.rb` still skips (untouched).

- [ ] **Step 4: Final manual smoke (release-engineer pass)** on `/:cid/admin/maintenance/flowcharts/:id/edit`:
  1. Process: picker → commit → expanded card → Advanced overrides → save → reload → collapsed card → Change/Escape restore → Change/replace → save.
  2. Decision: Yes/No/Otherwise presets → cards + canvas elements + summaries → remove middle branch → port remap intact → save → reopen → re-save (condition survives double round-trip).
  3. Loop: While condition builder → For-Each auto-fill + hint + Options disclosure → empty-collection save blocked → type-switch retention.
  4. Non-refactored regression: Start/End/Timer Advanced visibility switches, connection editor, I/O tab, join element.
  5. Read-only (active flowchart): all new inputs/buttons disabled by `_applyReadOnlyState` (it disables every `input/textarea/select/button` generically — verify the picker and chips are covered).

- [ ] **Step 5: Commit**

```bash
git add -A app/javascript
git commit -m "chore(property-editor): remove dead presets and step-modal remnants

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** design §1 (picker, immediate config, inline advanced) → Task 3; §2 (presets, left-operand select, readable cards, canvas safety) → Task 4; §3 (loop disclosure, auto-fill, CSS-only visibility, consolidation) → Task 2; §4 (shared templates/ViewComponents) → Tasks 1+5; error handling table → Tasks 2 (collection), 4 (entity fail, name validation); testing section → Task 5 + manual checklists (no jest — confirmed).
- **Type consistency:** `buildDisclosureSection({id, label, badgeHTML, bodyHTML, startOpen})` used identically in Tasks 1/2/3; `buildStepItemTemplate` 5th positional arg is `expanded` everywhere (`buildStepsFieldHTML` passes `false`, `stepPickerCommit` passes `true`); advanced input names `steps[N][retryCount|retryBackoff|timeout|guardCondition]` match the tagless selectors in `collectSteps`.
- **Known accepted deviations** (flagged above): searchable-select keyboard clamping instead of wrapping; picker row styling rendered by the controller (text-sm gray) differs slightly from UX's text-xs slate classes — accepted to avoid rewriting the shared controller; `expandAll` value is the one controller change.

### Critical Files for Implementation
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/templates.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/step_manager.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/branch_manager.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor_controller.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/form_builder.js
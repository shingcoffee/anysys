# Property Popup Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five targeted changes to the flowchart edit page's property popup — no type text in the header, element-aware default tab, loop Advanced tab refactor, live auto-derived label with user override, and decision-branch label concept removal.

**Architecture:** All changes are in the JavaScript layer of the property editor (Stimulus controller + helper modules) plus one schema edit. No Ruby model or backend changes. The existing `_performSync` already wires live label derivation + header refresh — so task (d) is mainly gap-filling (`join`, `subflow`) and one behavior polish. Task (c) uses a reusable segmented-control renderer triggered by `schema.control === "segmented"`. Task (e) removes the `label` concept from decision branches — the label is always the branch name.

**Testing strategy:** **Manual browser verification.** The project's system-test harness is currently not operational (all `spec/system/*` files are `skip`'d; there is no working sign-in helper for `:system` specs; DOM selectors would have to be discovered per-test). Building that harness is out of scope for this feature work. Pure-function coverage for this feature is not feasible either — the changes live entirely in Stimulus controllers and a JS constants file, and no JS unit-test harness is configured. Task 6 is a comprehensive manual verification pass the implementer performs in the dev server before declaring completion.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS, ViewComponent.

**Spec:** `docs/superpowers/specs/2026-04-17-property-popup-improvements-design.md`

---

## File Structure

**Modified files (JavaScript):**

- `app/javascript/controllers/property_editor_controller.js` — add `selectSegmentedOption` handler; add `case "join"` and `case "subflow"` to `_deriveLabelFromProperties`; add `_deriveLabelForJoin` and `_deriveLabelForSubflow` helpers.
- `app/javascript/controllers/property_editor/form_builder.js` — segmented-control render path; refine the "resume on clear" behavior in `_attachLabelInputListener`.
- `app/javascript/controllers/property_editor/tab_manager.js` — extend `defaultTabMap` for `timer` and `error_handler`.
- `app/javascript/controllers/property_editor/branch_manager.js` — strip `label` from `collectBranches`, `buildBranchItemHTML`, `buildBranchesFieldHTML`, `addBranchFromModal`, `quickAddBranch`.
- `app/javascript/controllers/property_editor/templates.js` — strip `label` suffix and hidden `branches[*][label]` input from `buildBranchItemTemplate`.
- `app/javascript/flowchart/constants/schemas.js` — `loop.loopType`: tab → `"advanced"`, add `control: "segmented"`, reorder so it appears first among advanced fields.
- `app/javascript/flowchart/dynamic_ports.js` — simplify `label: branch.label || branch.name || …` to `label: branch.name || …` (since `branch.label` is gone).

No new files. No Ruby changes.

---

## Task 1: Fill label-derivation gaps (join, subflow)

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:877-904` (`_deriveLabelFromProperties` switch block, plus new helpers after `_deriveLabelForErrorHandler`)

- [ ] **Step 1: Add `case "join"` and `case "subflow"` to `_deriveLabelFromProperties`**

Locate the `switch (type)` block inside `_deriveLabelFromProperties` (around lines 886-903) and add two new cases:

```javascript
      case "join":
        return this._deriveLabelForJoin(properties)
      case "subflow":
        return this._deriveLabelForSubflow(properties)
```

- [ ] **Step 2: Add the two helper methods**

Immediately after `_deriveLabelForErrorHandler` (after line 982), add:

```javascript
  _deriveLabelForJoin(properties) {
    const strategy = properties.joinStrategy || "wait_all"
    return `Join (${strategy})`
  }

  _deriveLabelForSubflow(properties) {
    const name = properties.subflowName || properties.referencedSubflow || ""
    return name ? `→ ${name}` : "Subflow"
  }
```

- [ ] **Step 3: Manual verification**

Start the dev server (`bin/dev`), open a flowchart, drop a **join** element on the canvas. Click it. Header title and label field should read `Join (wait_all)`.

Drop a **subflow** element. Header title and label field should read `Subflow`.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat(property-popup): derive labels for join and subflow elements"
```

---

## Task 2: Polish label derivation "resume on clear"

The existing behavior (`_performSync` + `_attachLabelInputListener`) sets `_labelAutoDerived = true` when the user clears the label field, but doesn't re-derive immediately — the field stays empty until the next property change. Fix so clearing the label re-derives right away.

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js:484-492`

- [ ] **Step 1: Trigger immediate re-derive when the label is cleared**

Replace the body of `_boundLabelInputHandler` at `form_builder.js:484-492` with:

```javascript
    this._boundLabelInputHandler = () => {
      if (labelInput.value.trim() === "") {
        this.controller._labelAutoDerived = true
        // Re-derive immediately so the field doesn't stay empty
        this.controller._performSync()
      } else {
        this.controller._labelAutoDerived = false
      }
    }
```

- [ ] **Step 2: Manual verification**

In the dev server, drop a Process element → add a step named `Send email` → label auto-fills to `Send email`. Type `Custom name` in the label field → label stays as `Custom name` even if you add another step. Clear the label field → label immediately re-derives from the current steps.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/form_builder.js
git commit -m "feat(property-popup): re-derive label immediately when cleared"
```

---

## Task 3: Extend default-tab map (task b)

**Files:**
- Modify: `app/javascript/controllers/property_editor/tab_manager.js:65-69`

- [ ] **Step 1: Extend the `defaultTabMap`**

Replace lines 65-70 in `tab_manager.js` with:

```javascript
    // Default to the most relevant tab for each element type
    const defaultTabMap = {
      process: "steps",
      decision: "steps",
      loop: "advanced",
      timer: "advanced",
      error_handler: "advanced"
    }
    this.activeTab = defaultTabMap[elementType] || "general"
```

- [ ] **Step 2: Manual verification**

In the dev server, click through each element type and confirm the initial active tab:

| Element type | Expected tab |
|---|---|
| process | Steps |
| decision | Branches |
| loop | Advanced |
| timer | Advanced |
| error_handler | Advanced |
| start, end, join, subflow | General |

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/tab_manager.js
git commit -m "feat(property-popup): default Timer and ErrorHandler to Advanced tab"
```

---

## Task 4: Loop Advanced tab refactor — move `loopType`, render as segmented control (task c)

### Task 4a: Add a reusable segmented-control renderer

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js` (add `selectSegmentedOption` handler)
- Modify: `app/javascript/controllers/property_editor/form_builder.js` (add `_buildSegmentedControlHTML`, route select fields with `control: "segmented"` to it)

- [ ] **Step 1: Add `selectSegmentedOption` handler on the controller**

In `app/javascript/controllers/property_editor_controller.js`, add this method immediately after the existing `handleLoopTypeChange` method:

```javascript
  /**
   * Click handler for segmented-control option buttons.
   * Updates the hidden input, re-applies active-state classes to the buttons,
   * and dispatches a native `change` event so existing `change->` handlers still fire.
   */
  selectSegmentedOption(event) {
    event.preventDefault()
    const button = event.currentTarget
    const group = button.closest("[data-segmented-group]")
    if (!group) return

    const fieldName = group.dataset.segmentedField
    const value = button.dataset.segmentedValue

    const hiddenInput = group.querySelector(`input[type="hidden"][name="${fieldName}"]`)
    if (hiddenInput) {
      hiddenInput.value = value
      hiddenInput.dispatchEvent(new Event("change", { bubbles: true }))
    }

    group.querySelectorAll("button[data-segmented-value]").forEach(btn => {
      const isActive = btn.dataset.segmentedValue === value
      btn.setAttribute("aria-checked", isActive ? "true" : "false")
      if (isActive) {
        btn.classList.remove("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
        btn.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
      } else {
        btn.classList.remove("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
        btn.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
      }
    })
  }
```

- [ ] **Step 2: Add `_buildSegmentedControlHTML` on `FormBuilder` and route select fields to it**

In `app/javascript/controllers/property_editor/form_builder.js`, locate where select fields are rendered (search for the `type === "select"` branch in the `_buildInputHTML` method). At the top of that branch, insert:

```javascript
    if (fieldSchema.type === "select" && fieldSchema.control === "segmented") {
      return this._buildSegmentedControlHTML(fieldName, fieldSchema, currentValue)
    }
```

Then add the new method on the same class:

```javascript
  _buildSegmentedControlHTML(fieldName, fieldSchema, currentValue) {
    const value = currentValue || fieldSchema.default || (fieldSchema.options[0]?.value ?? "")

    const changeActionMap = {
      loopType: "change->property-editor#handleLoopTypeChange",
      triggerType: "change->property-editor#handleTriggerTypeChange",
      responseType: "change->property-editor#handleResponseTypeChange",
      delayType: "change->property-editor#handleDelayTypeChange"
    }
    const changeAction = changeActionMap[fieldName]
      ? ` data-action="${changeActionMap[fieldName]}"`
      : ""

    const buttons = fieldSchema.options.map(opt => {
      const isActive = String(opt.value) === String(value)
      const activeClasses = isActive
        ? "bg-white text-slate-900 shadow-sm ring-1 ring-black/5"
        : "text-slate-500 hover:text-slate-700 hover:bg-white/50"
      return `
        <button type="button"
                role="radio"
                aria-checked="${isActive ? "true" : "false"}"
                data-segmented-value="${opt.value}"
                data-action="click->property-editor#selectSegmentedOption"
                class="flex-1 py-1 px-2 text-[11px] font-medium rounded-md transition-all duration-150 ${activeClasses}">
          ${opt.label}
        </button>
      `
    }).join("")

    return `
      <div data-segmented-group data-segmented-field="${fieldName}" role="radiogroup"
           class="flex gap-0.5 p-0.5 bg-slate-100 rounded-lg">
        ${buttons}
        <input type="hidden" name="${fieldName}" value="${value}"${changeAction}>
      </div>
    `
  }
```

- [ ] **Step 3: Commit the reusable primitive**

```bash
git add app/javascript/controllers/property_editor_controller.js \
        app/javascript/controllers/property_editor/form_builder.js
git commit -m "feat(property-popup): add reusable segmented-control renderer"
```

### Task 4b: Move `loopType` to Advanced, opt into segmented control

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js:316-369` (the `loop` entry)

- [ ] **Step 1: Replace the loop schema**

Replace lines 316-369 in `schemas.js` with:

```javascript
  loop: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
    loopType: {
      type: "select",
      control: "segmented",
      label: "Loop Type",
      options: [
        { value: "while", label: "While" },
        { value: "do_while", label: "Do-While" },
        { value: "for_each", label: "For-Each" }
      ],
      default: "while",
      tab: "advanced"
    },
    condition: {
      type: "condition",
      label: "Loop Condition",
      visibleWhen: { field: "loopType", values: ["while", "do_while", ""] },
      tab: "advanced"
    },
    collection: {
      type: "text",
      label: "Collection",
      placeholder: "e.g. ctx.items or ctx.users",
      visibleWhen: { field: "loopType", value: "for_each" },
      tab: "advanced"
    },
    itemVariable: {
      type: "text",
      label: "Item Variable",
      placeholder: "item",
      visibleWhen: { field: "loopType", value: "for_each" },
      tab: "advanced"
    },
    indexVariable: {
      type: "text",
      label: "Index Variable",
      placeholder: "index",
      visibleWhen: { field: "loopType", value: "for_each" },
      tab: "advanced"
    },
    iterations: {
      type: "number",
      label: "Max Iterations",
      min: 1,
      placeholder: "10",
      tab: "advanced"
    },
    outputs: COMMON_PROPERTIES.outputs,
    description: {
      ...COMMON_PROPERTIES.description,
      placeholder: "Describe what this loop does..."
    },
  },
```

- [ ] **Step 2: Manual verification**

In the dev server, drop a Loop element. The popup should:
- Open on the Advanced tab (Task 3 default).
- Show a segmented control at the top labeled `While / Do-While / For-Each`, with `While` active.
- Show the condition builder below the segmented control.
- General tab should no longer have a `Loop Type` dropdown.
- Click `For-Each` → condition builder hides; `Collection`, `Item Variable`, `Index Variable` text fields appear.
- Click `While` → condition builder reappears; the for_each fields hide.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js
git commit -m "feat(property-popup): move loopType to Advanced as segmented control"
```

---

## Task 5: Remove `label` concept from decision branches (task e)

### Task 5a: Strip `label` from the branch row template

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:804-867`

- [ ] **Step 1: Rewrite `buildBranchItemTemplate`**

In `app/javascript/controllers/property_editor/templates.js`, replace lines 804-867 with:

```javascript
export function buildBranchItemTemplate(params) {
  const {
    index,
    branchValue,
    description,
    branchElementId,
    condition
  } = params

  const branchName = branchValue || `Branch ${index}`

  let conditionSummary = ''
  if (condition) {
    if (condition.conditionType === "query_count") {
      const qc = condition.queryConfig || {}
      const entityName = qc.entityName || `Entity#${qc.entityId || '?'}`
      const countOp = escapeHtml(condition.countOperator || '>')
      const countVal = escapeHtml(String(condition.countValue ?? 0))
      conditionSummary = `Count ${escapeHtml(entityName)} ${countOp} ${countVal}`
    } else {
      conditionSummary = `${escapeHtml(condition.leftOperand || '')} ${escapeHtml(condition.operator || '')} ${escapeHtml(condition.rightOperand || '')}`
    }
  }

  return `
    <div data-branch-item
         data-branch-index="${index}"
         ${branchElementId ? `data-branch-element-id="${escapeHtml(branchElementId)}"` : ""}
         class="relative border-l-2 border-amber-400 border-b border-b-slate-100 px-2.5 py-2 hover:bg-slate-50 transition-colors group">

      <div class="flex items-center gap-2">
        <div class="w-2 h-2 rounded-full bg-amber-500 flex-shrink-0"></div>
        <div class="flex-1 min-w-0">
          <div class="text-xs font-medium text-slate-800">${escapeHtml(branchName)}</div>
          ${conditionSummary ? `<div class="text-[10px] font-mono text-slate-400">${conditionSummary}</div>` : ""}
        </div>
        <button type="button"
                data-action="click->property-editor#removeBranch"
                class="p-1 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-md opacity-0 group-hover:opacity-100 transition-all duration-150 flex-shrink-0"
                title="Remove branch">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      </div>
      ${description ? `<div class="pl-5 mt-0.5 text-[10px] text-slate-400">${escapeHtml(description)}</div>` : ""}

      <!-- Hidden inputs for form submission -->
      <input type="hidden" name="branches[${index}][name]" value="${escapeHtml(branchName)}">
      <input type="hidden" name="branches[${index}][description]" value="${escapeHtml(description || "")}">
      ${branchElementId ? `<input type="hidden" name="branches[${index}][elementId]" value="${escapeHtml(branchElementId)}">` : ""}
      ${condition ? `<input type="hidden" name="branches[${index}][condition]" value="${escapeHtml(JSON.stringify(condition))}">` : ""}
    </div>
  `
}
```

### Task 5b: Strip `label` from `branch_manager.js`

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js` (five spots listed below)

- [ ] **Step 1: `buildBranchItemHTML` signature (lines 726-736)**

Replace the method with:

```javascript
  buildBranchItemHTML(index, branchValue, description, branchElementId = null, condition = null) {
    return buildBranchItemTemplate({
      index,
      branchValue,
      description,
      branchElementId,
      condition
    })
  }
```

- [ ] **Step 2: `buildBranchesFieldHTML` render-existing loop (lines 673-683)**

Replace that `branches.forEach` block with:

```javascript
    branches.forEach((branch, index) => {
      branchesHTML += this.buildBranchItemHTML(
        index,
        branch.name || branch.value || `Branch ${index}`,
        branch.description || "",
        branch.elementId || null
      )
      this.branchIndex = index + 1
    })
```

- [ ] **Step 3: `addBranchFromModal` call site (lines 222-230)**

Replace the `buildBranchItemHTML` call in `addBranchFromModal` with:

```javascript
    const branchHtml = this.buildBranchItemHTML(
      this.branchIndex,
      branchName,
      description,
      null,
      condition
    )
```

- [ ] **Step 4: `quickAddBranch` call site (lines 320-327)**

Replace the `buildBranchItemHTML` call in `quickAddBranch` with:

```javascript
    const branchHtml = this.buildBranchItemHTML(
      this.branchIndex,
      conditionLabel,
      "",
      null,
      condition
    )
```

- [ ] **Step 5: `collectBranches` (lines 441-465)**

Replace the method with:

```javascript
  collectBranches() {
    const container = this.controller.formFieldsTarget.querySelector("[data-branches-container]")
    if (!container) return null

    const branches = []
    const branchItems = container.querySelectorAll("[data-branch-item]")

    branchItems.forEach(item => {
      const nameInput = item.querySelector("input[name*='[name]']") || item.querySelector("input[name*='[value]']")
      const descInput = item.querySelector("input[name*='[description]']")
      const elementIdInput = item.querySelector("input[name*='[elementId]']")

      const name = nameInput?.value || `Branch ${branches.length}`
      const description = descInput?.value?.trim() || ""
      const elementId = elementIdInput?.value || item.dataset.branchElementId || null

      const branch = { name, description, branchKey: `branch_${branches.length}` }
      if (elementId) branch.elementId = elementId
      branches.push(branch)
    })

    return branches
  }
```

### Task 5c: Simplify `dynamic_ports.js`

**Files:**
- Modify: `app/javascript/flowchart/dynamic_ports.js:48`

- [ ] **Step 1: Drop the `branch.label` fallback**

Change line 48 from:

```javascript
      label: branch.label || branch.name || `Branch ${i}`
```

to:

```javascript
      label: branch.name || `Branch ${i}`
```

### Task 5d: Verify and commit

- [ ] **Step 1: Manual verification**

In the dev server:
- Drop a Decision element.
- Open the Add Branch modal; the modal body ordering from top to bottom is: Branch Name → Condition → Description. ✓ (already the case in the modal; this is a sanity check).
- Fill in `Active` and a condition, click `Add Branch`. The new row shows: amber dot + `Active` + condition summary + description line. **No `· label` suffix anywhere.**
- Inspect the row in DevTools — there is **no** hidden input with name ending in `[label]`. There is `[name]`, `[description]`, `[elementId]`, `[condition]`.
- Save the flowchart. Reload the page. Click the Decision → the branch row still reads `Active`, still has no `label` suffix, still has no `[label]` hidden input.
- The port label on the decision's outgoing connection still reads `Active` (dynamic_ports.js fallback chain still works).

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js \
        app/javascript/controllers/property_editor/branch_manager.js \
        app/javascript/flowchart/dynamic_ports.js
git commit -m "feat(property-popup): remove label concept from decision branches"
```

---

## Task 6: Full manual verification sweep

**Files:** none — verification only.

- [ ] **Step 1: Run any existing automated specs to catch accidental regressions**

Run: `bundle exec rspec`

Expected: same failures as before this feature (documented in memory: 3 CSS component specs + 4 query_count_branching_spec). **No new failures.** If any new failure appears, triage before proceeding.

- [ ] **Step 2: Full manual sweep in the dev server**

Run `bin/dev`. Open the flowchart editor and verify each item below:

**Header & default tab (tasks a, b):**
- [ ] Drop one of each element type (start, end, process, decision, join, loop, subflow, timer, error_handler) and click each. For every one: the popup header shows an icon + a label that is **not** the raw type name. Default tab matches:
  - process → Steps
  - decision → Branches
  - loop, timer, error_handler → Advanced
  - start, end, join, subflow → General

**Label auto-derivation (task d):**
- [ ] Process: empty label → `Process`-ish default is replaced with the first step's action name as soon as one is added.
- [ ] Typing in the label field freezes derivation (add another step — label does not change).
- [ ] Clearing the label resumes derivation immediately (field repopulates without any other interaction).
- [ ] Join: label is `Join (wait_all)` (or the current strategy).
- [ ] Subflow: label is `Subflow` (or `→ Name` if a subflow name property is present).

**Loop Advanced refactor (task c):**
- [ ] Loop popup opens on Advanced. Top of Advanced pane shows a segmented `While / Do-While / For-Each` control. General tab has no Loop Type field.
- [ ] Click each option; the field groups below swap inline (condition builder for while/do_while; collection + item + index for for_each). Max Iterations stays visible for all.

**Decision branch (task e):**
- [ ] Add Branch modal: Branch Name → Condition → Description, in that order, Description last.
- [ ] Added branch row shows only name + condition summary + description; no `· label` suffix.
- [ ] DevTools: no `branches[*][label]` hidden input.
- [ ] Save + reload: branch persists correctly.
- [ ] Decision's outgoing connection on the canvas still shows the branch name as its label.

- [ ] **Step 3: Report results**

Report which items passed and which failed. Do not mark the plan complete unless every verification checkbox passes.

---

## Self-Review Notes (resolved inline during plan authoring)

- Every spec requirement maps to a task: (a) → Tasks 1+2 (resolves transitively via reliable derivation), (b) → Task 3, (c) → Task 4, (d) → Tasks 1+2, (e) → Task 5.
- No placeholders. Every code step shows the actual code.
- Function/property names consistent across tasks.
- Subflow's `subflowName` / `referencedSubflow` properties aren't guaranteed to exist in the schema today; the helper falls back to `"Subflow"` so the header never goes blank. Acknowledged as a future polish in the spec's "Out of Scope".
- `handleTriggerTypeChange`, `handleResponseTypeChange`, `handleDelayTypeChange` remain as native selects (not converted to segmented). Only `loopType` is segmented; the `changeActionMap` in Task 4 Step 2 is future-proofing for if they're ever segmented later — no behavior change today.
- Testing strategy downgraded from "system specs + manual" to "manual only" after verifying the project's system-test harness is not operational (all `spec/system/*` are `skip`'d, no sign-in helper, selectors would need discovery per-test). Building the harness is out of scope for this feature.

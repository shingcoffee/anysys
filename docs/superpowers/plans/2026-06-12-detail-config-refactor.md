# Detail-Config Layer Refactor (Round 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the detail configuration layer (process step configSchema fields, decision branch modal field/query-count panels, loop condition/collection fields) guided — variable-pick buttons, entity column selects, progressive disclosure, semantic KV placeholders, resultVar auto-suggest — with zero feature removal and byte-identical saved config JSON.

**Architecture:** All changes are client-side overlays on the existing 420 px property sidebar: `templates.js` gains shared helpers (VAR_REF_PATTERN, var-pick button, entity column select, set-count badge, core/More-options partition); `context_autocomplete_controller` gains a `picker` entry point into its existing dropdown; `step_manager`/`branch_manager`/`property_editor_controller`/`form_builder` wire new Stimulus actions; action_configs gain rendering-hint-only annotations (`keyPlaceholder`, `valuePlaceholder`, `entityField`, `group`). No new controllers, files, routes, or APIs. Every collection path (`collectSteps`, `collectStepConfig`, `collectBranches`, `_collectQueryCountCondition`, `collectCondition`) keeps emitting today's exact shapes; every new widget keeps exactly one `data-config-input` element per field and a manual-text escape hatch.

**Tech Stack:** Rails 8 + importmap + Stimulus + Tailwind. No JS test runner — JS verification is `node --input-type=module --check < <file>` plus the enumerated manual audit; Ruby verification is `bundle exec rspec spec/requests/maintenance/flowcharts_editor_spec.rb`.

**Worktree:** `/home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor` (all paths below relative to it).

---

## Spec-vs-Code Contradictions — Binding Resolutions

These were found by grounding the spec against the real source. The resolutions below are **binding** for all tasks.

1. **Stimulus action scope (UX 2.1a / 2.6b markup is broken as written).** The UX spec puts `data-action="click->context-autocomplete#picker"` on a button that is a *sibling* of the input, while the controller is attached to the input itself (`templates.js:355,369`). Stimulus only routes actions to controllers on an ancestor element — the button click would never fire. **Resolution:** move `data-controller="context-autocomplete"` to the new `relative` wrapper div; the input gets `data-context-autocomplete-target="input"`; the controller gains a `_input` getter (`hasInputTarget ? inputTarget : element`) so any controller still mounted directly on a bare input (backward compatibility) keeps working unchanged. Additionally, the button gets `mousedown->context-autocomplete#keepFocus` (preventDefault) so the input never loses focus, and `_onBlur` gains an `activeElement !== this._input` guard (defense against the picker→refocus race destroying the dropdown).

2. **`buildInlineCondition` is dead code.** It is exported from `templates.js:180` but has **zero callers** (`grep -rn buildInlineCondition app/javascript` → only its definition). Loop conditions actually render through `branch_manager.buildConditionFieldHTML` → `_buildConditionRowHTML` (schemas.js: loop `condition` is `type: "condition"`, routed by `form_builder.js:150`). **Resolution:** do NOT modify `buildInlineCondition` (modifying unreachable code adds untestable surface; leaving it untouched satisfies "nothing deleted"). The unified-row variable-pick treatment goes on the surfaces users actually reach: `_buildConditionRowHTML` (decision main condition + loop while/do-while) and the branch modal field panel (`buildBranchModalTemplate`).

3. **One step per process element.** `stepPickerCommit` (step_manager.js:736) caps each process element at a single step, so the "sibling steps" scans (design decisions #3, UX 2.1d) are trivially empty today. **Resolution:** implement the DOM scans exactly as specced (scan `[data-step-item]` siblings in `[data-steps-container]`, excluding self) — they cost nothing, degrade to "group not shown / no suffix appended", and become live automatically if multi-step returns. Flagged so QA does not file "Used in this element never appears" as a bug.

4. **`canvas.entityAttributes` exists and the shape is confirmed** (the design's riskiest assumption holds). Set in `flowchart_canvas_controller.js:108` from `entityAttributesValue`, which the server renders in `app/views/admin/maintenance/flowcharts/_editor.html.erb:9` from `@flowchart.entity&.property_schema_json || []` — an array of attribute hashes with `name` and `name_slug` (see `app/models/entity.rb:78-90` and the existing consumer pattern `attr.name_slug || attr.name || attr` at `branch_manager.js:1506`). **Convention split (binding):** step-config entity column selects emit the **bare slug** (e.g. `email`) — same as what users type into `findField` today; query-count WHERE field options keep their existing `data.<slug>` values plus bare `created_at`/`updated_at` (byte-compat with `_addQueryCountWhereRow`, branch_manager.js:1130-1137).

5. **QC degraded state (UX 2.2c "rows stay plain text inputs") contradicts current code.** Today a WHERE row's key side is always a `<select>`; on entity-fetch failure no row is auto-added, but "Add Filter" still produces a select containing only `created_at`/`updated_at`. Replacing it with a plain text input would *change* existing behavior. **Resolution:** keep today's select (now with the "enter manually…" optgroup, which covers manual entry), and add only the amber "Schema unavailable" hint on fetch failure. No removal, escape hatch satisfied.

6. **resultVar derivation rule is self-contradictory in UX 2.5** ("take the part before `_model`" vs example `find_model → "model"`). **Resolution:** schema `default` always wins (rule 1, and nearly all output-var fields already have defaults — e.g. `query_models.resultVar default: "models"`); fallback: action key ending `_models` → `"models"`, ending `_model` → `"model"`, otherwise `"result"`. Matches every example in the spec.

7. **Output-variable key set (binding):** exactly `["resultVar", "outputKey", "targetVariable"]` (per design D and UX 2.1d), exported once as `OUTPUT_VAR_KEYS` from `templates.js`. `targetVar` (data_actions.js:15) and `responseVar` (communication_actions.js:95) are deliberately excluded this round — extending the constant later is a one-line change.

8. **Dirty-flag for resultVar auto-suggest is structurally guaranteed:** auto-fill runs only inside `stepPickerCommit` (step creation). Nothing ever re-invokes derivation for an existing card — reload renders from stored config, `changeStep`+Escape restores the live DOM node. No flag variable is needed; do not add one.

**Parallelization:** Task 1 first (it creates the shared exports). Then **Tasks 2, 3, 4, 5 have fully disjoint file sets and can run in parallel** in this worktree (Task 5 is even independent of Task 1). Task 6 runs last.

---

### Task 1: templates.js — shared helpers, var-pick wrappers, entity column select, partition, KV placeholders, badge, branch-modal additions

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (lines 140-216 region for new exports; 350-486 config field builders; 498-620 step item; 630-835 branch modal)

- [ ] **Step 1: Add shared constants and the var-pick button builder** (insert after the `buildOverrideBadge` function, templates.js:138, keeping `UNARY_OPERATORS` below intact):

```js
/**
 * Round-2 shared helpers — variable-reference detection and var-pick button.
 * VAR_REF_PATTERN is the single source of truth for "this field references a
 * context variable/expression"; field builders and condition builders share it.
 */
export const VAR_REF_PATTERN = /Var$|Variable$|Key$|Expression$|^collection$|^sourceField$|^targetField$/

export function isVarRefField(fieldKey) {
  return VAR_REF_PATTERN.test(String(fieldKey || ""))
}

/**
 * Output-variable configSchema keys recognised by the resultVar auto-suggest
 * and the picker dropdown's "Used in this element" group. Deliberately
 * excludes targetVar/responseVar this round (see plan resolution #7).
 */
export const OUTPUT_VAR_KEYS = ["resultVar", "outputKey", "targetVariable"]

/**
 * The {x} variable-pick button. Must be rendered inside a `relative` wrapper
 * that carries data-controller="context-autocomplete"; the input in the same
 * wrapper carries data-context-autocomplete-target="input" and pl-2 pr-7.
 * tabindex="-1" keeps Tab flow on the input; mousedown->keepFocus prevents
 * the click from blurring the input.
 * @param {Object} params
 * @param {string} params.positionClasses - absolute positioning classes
 * @returns {string}
 */
export function buildVarPickButton({ positionClasses = "right-0.5 top-1/2 -translate-y-1/2" } = {}) {
  return `<button type="button"
        tabindex="-1"
        title="Insert variable"
        data-action="mousedown->context-autocomplete#keepFocus click->context-autocomplete#picker"
        class="absolute ${positionClasses} flex items-center justify-center w-5 h-5 text-[10px] font-mono font-bold text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 active:bg-indigo-100 active:text-indigo-700 rounded transition-colors cursor-pointer">{x}</button>`
}

/**
 * data-controller attributes for a context-autocomplete wrapper div.
 * Returns "" when elementId is absent so markup degrades to today's exact output.
 */
function autocompleteWrapperAttrs(elementId, stepIndex) {
  if (!elementId) return ""
  return ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="${stepIndex ?? -1}"`
}
```

- [ ] **Step 2: Add `buildSetCountBadge`** (directly after `buildOverrideBadge`, mirroring its hidden-at-zero contract, per UX 2.3c — slate, label "N set", `data-set-count-badge`):

```js
/**
 * "N set" badge for the step "More options" disclosure. Counts non-default
 * values inside the disclosure body. Hidden (not omitted) at 0 so JS can
 * update it in place. Distinct from buildOverrideBadge (indigo, "N overrides").
 * @param {number} count
 * @returns {string} Badge HTML
 */
export function buildSetCountBadge(count) {
  const hiddenClass = count > 0 ? "" : " hidden"
  return `<span data-set-count-badge class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-[10px] font-semibold text-slate-600 bg-slate-100 border border-slate-200 rounded${hiddenClass}">${count} set</span>`
}
```

- [ ] **Step 3: Rework `buildConfigTextField` / `buildConfigTextareaField`** (templates.js:352-378). The var-ref branch is new; the non-var-ref branch must stay **byte-identical** to today's output:

```js
const CONFIG_INPUT_CLASSES = "w-full px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
// Same as CONFIG_INPUT_CLASSES but pl-2 pr-7 so text never underlaps the {x} button (UX flag #2).
const CONFIG_INPUT_VARPICK_CLASSES = "w-full pl-2 pr-7 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"

function buildConfigTextField(field, value, context = {}) {
  const { elementId, stepIndex } = context

  if (elementId && isVarRefField(field.key)) {
    return `<div class="relative"${autocompleteWrapperAttrs(elementId, stepIndex)}>
    <input type="text"
      data-config-input="${escapeHtml(field.key)}"
      data-context-autocomplete-target="input"
      value="${escapeHtml(String(value))}"
      placeholder="${escapeHtml(field.placeholder || "")}"
      ${field.required ? "required" : ""}
      class="${CONFIG_INPUT_VARPICK_CLASSES}">
    ${buildVarPickButton()}
  </div>`
  }

  const controllerAttrs = elementId
    ? ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="${stepIndex ?? -1}"`
    : ""

  return `<input type="text"
    data-config-input="${escapeHtml(field.key)}"${controllerAttrs}
    value="${escapeHtml(String(value))}"
    placeholder="${escapeHtml(field.placeholder || "")}"
    ${field.required ? "required" : ""}
    class="${CONFIG_INPUT_CLASSES}">`
}

function buildConfigTextareaField(field, value, context = {}) {
  const { elementId, stepIndex } = context

  if (elementId && isVarRefField(field.key)) {
    return `<div class="relative"${autocompleteWrapperAttrs(elementId, stepIndex)}>
    <textarea
      data-config-input="${escapeHtml(field.key)}"
      data-context-autocomplete-target="input"
      rows="2"
      placeholder="${escapeHtml(field.placeholder || "")}"
      ${field.required ? "required" : ""}
      class="${CONFIG_INPUT_VARPICK_CLASSES} resize-none">${escapeHtml(String(value))}</textarea>
    ${buildVarPickButton({ positionClasses: "right-0.5 top-2" })}
  </div>`
  }

  const controllerAttrs = elementId
    ? ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="${stepIndex ?? -1}"`
    : ""

  return `<textarea
    data-config-input="${escapeHtml(field.key)}"${controllerAttrs}
    rows="2"
    placeholder="${escapeHtml(field.placeholder || "")}"
    ${field.required ? "required" : ""}
    class="${CONFIG_INPUT_CLASSES} resize-none">${escapeHtml(String(value))}</textarea>`
}
```

- [ ] **Step 4: Add `buildEntityColumnSelect`** (new export, after `buildConfigKeyValueList`). CRITICAL contract (UX flag #3/#10): the **hidden input** is the single `data-config-input` element; the select and manual input never carry it; `__manual__` never reaches the hidden input. When the saved value is not one of the entity's columns, render with the manual side visible so reopening a step never loses a custom value:

```js
/**
 * Entity-aware column select with "enter manually…" escape hatch.
 * Renders for configSchema fields annotated entityField: true when the
 * flowchart has a bound entity (canvas.entityAttributes non-empty).
 * Returns null when no columns are available — caller falls back to the
 * plain text field (today's exact markup).
 *
 * Value contract: a single hidden <input data-config-input> holds the value
 * read by collectStepConfig(); the select / manual input mirror into it via
 * property-editor#handleEntityColumnSelectChange / #syncEntityColumnManual.
 * Emits the bare attribute slug (e.g. "email"), same as manual typing today.
 */
export function buildEntityColumnSelect(field, value, entityAttributes, context = {}) {
  const columns = (entityAttributes || [])
    .map(attr => attr.name_slug || attr.name || String(attr))
    .filter(Boolean)
  if (columns.length === 0) return null

  const strValue = String(value ?? "")
  const valueInColumns = strValue === "" || columns.includes(strValue)
  const { elementId, stepIndex } = context

  const optionsHTML =
    `<option value="">Select column&hellip;</option>` +
    columns.map(c => `<option value="${escapeHtml(c)}"${c === strValue ? " selected" : ""}>${escapeHtml(c)}</option>`).join("")

  return `
    <div data-entity-field-wrapper>
      <select data-entity-column-select
              data-action="change->property-editor#handleEntityColumnSelectChange"
              class="${valueInColumns ? "" : "hidden "}w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
        ${optionsHTML}
        <optgroup label="Other"><option value="__manual__">enter manually&hellip;</option></optgroup>
      </select>
      <div data-entity-manual-wrap class="${valueInColumns ? "hidden " : ""}relative flex gap-1"${autocompleteWrapperAttrs(elementId, stepIndex)}>
        <input type="text"
               data-entity-column-manual
               ${elementId ? `data-context-autocomplete-target="input"` : ""}
               data-action="input->property-editor#syncEntityColumnManual"
               value="${valueInColumns ? "" : escapeHtml(strValue)}"
               placeholder="column name"
               class="flex-1 min-w-0 pl-2 pr-7 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded-md shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-400">
        ${elementId ? buildVarPickButton({ positionClasses: "right-9 top-1/2 -translate-y-1/2" }) : ""}
        <button type="button"
                data-action="click->property-editor#swapEntityColumnToSelect"
                title="Switch to dropdown"
                class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50 flex-shrink-0">&#x25B2;</button>
      </div>
      <input type="hidden" data-config-input="${escapeHtml(field.key)}" value="${escapeHtml(strValue)}">
    </div>
  `.trim()
}
```

- [ ] **Step 5: KV-list placeholders** — change `buildConfigKeyValueList` (templates.js:406-446) to honor `keyPlaceholder`/`valuePlaceholder` and to publish them as data attributes (so `addConfigKvRow` in step_manager can reuse them on dynamically added rows):

Before → after fragments:
```js
// BEFORE (line 406):
function buildConfigKeyValueList(field, value) {
  // value should be an array of { key, value } objects, or empty
  const rows = Array.isArray(value) && value.length > 0 ? value : [{ key: "", value: "" }]

// AFTER:
function buildConfigKeyValueList(field, value) {
  // value should be an array of { key, value } objects, or empty
  const rows = Array.isArray(value) && value.length > 0 ? value : [{ key: "", value: "" }]
  // Rendering hints only — never serialized (falls back to today's strings).
  const keyPlaceholder = field.keyPlaceholder ?? "Key"
  const valuePlaceholder = field.valuePlaceholder ?? "Value"
```
```js
// BEFORE (lines 415 / 420):
             placeholder="Key"
…
             placeholder="Value"

// AFTER:
             placeholder="${escapeHtml(keyPlaceholder)}"
…
             placeholder="${escapeHtml(valuePlaceholder)}"
```
```js
// BEFORE (line 434):
    <div data-key-value-list data-config-input="${escapeHtml(field.key)}" class="space-y-1">

// AFTER:
    <div data-key-value-list data-config-input="${escapeHtml(field.key)}" data-key-placeholder="${escapeHtml(keyPlaceholder)}" data-value-placeholder="${escapeHtml(valuePlaceholder)}" class="space-y-1">
```

- [ ] **Step 6: Partition `buildStepConfigFieldsHTML`** (replace templates.js:448-486 entirely). Extract the per-field renderer, add `data-field-default`, route `entityField` text fields, then partition core/More-options per UX 2.3a. The disclosure body is CSS-hidden, never DOM-removed (UX flag #4); all field divs keep `data-config-field` regardless of nesting so `collectStepConfig`/`collectRenderedConfigFieldKeys` (step_manager.js:318-362) are untouched:

```js
/** True when `value` differs from the field's schema default (UX 2.3c). */
function isFieldValueNonDefault(field, value) {
  if (field.type === "key_value_list") {
    return Array.isArray(value) && value.some(row => String(row.key || "").trim() !== "")
  }
  return String(value ?? "") !== String(field.default ?? "")
}

function buildSingleConfigFieldHTML(field, currentConfig, context) {
  const value = currentConfig[field.key] ?? field.default ?? ""
  const isVisible = shouldFieldBeVisible(field, currentConfig)
  const hiddenClass = isVisible ? "" : " hidden"
  const requiredMark = field.required ? ' <span class="text-red-500">*</span>' : ""

  let inputHTML
  switch (field.type) {
    case "text":
      // entityField is a rendering hint only: with a bound entity render the
      // column select; otherwise degrade silently to today's plain text input.
      inputHTML = (field.entityField && (context.entityAttributes || []).length > 0)
        ? (buildEntityColumnSelect(field, value, context.entityAttributes, context)
            || buildConfigTextField(field, value, context))
        : buildConfigTextField(field, value, context)
      break
    case "textarea":  inputHTML = buildConfigTextareaField(field, value, context); break
    case "number":    inputHTML = buildConfigNumberField(field, value); break
    case "select":    inputHTML = buildConfigSelectField(field, value); break
    case "key_value_list": inputHTML = buildConfigKeyValueList(field, value); break
    default:          inputHTML = buildConfigTextField(field, value, context)
  }

  return `
    <div class="step-config-field${hiddenClass}"
         data-config-field="${escapeHtml(field.key)}"
         data-field-default="${escapeHtml(String(field.default ?? ""))}"
         ${field.visibleWhen ? `data-visible-when='${escapeHtml(JSON.stringify(field.visibleWhen))}'` : ""}>
      <label class="block text-[11px] font-medium text-slate-500 mb-1">
        ${escapeHtml(field.label)}${requiredMark}
      </label>
      ${inputHTML}
    </div>`
}

/**
 * Build HTML for action-specific config fields in expanded step item.
 * Actions with > 6 currently-visible fields are partitioned: core fields
 * (group:"core", or required without visibleWhen) render flat; the rest go
 * into a collapsed "More options" disclosure with an "N set" badge.
 * The partition and the `group` hint are render-time only — never serialized.
 * @param {Array} configSchema - Array of field schema objects from the action registry
 * @param {Object} currentConfig - Current config values (from step.config)
 * @param {Object} context - { elementId, stepIndex, entityAttributes, moreOpen }
 * @returns {string} HTML string for all config fields
 */
export function buildStepConfigFieldsHTML(configSchema, currentConfig = {}, context = {}) {
  if (!configSchema || configSchema.length === 0) return ""

  const renderAll = fields =>
    fields.map(field => buildSingleConfigFieldHTML(field, currentConfig, context)).join("")

  const visibleCount = configSchema.filter(f => shouldFieldBeVisible(f, currentConfig)).length
  if (visibleCount <= 6) {
    return `<div data-step-config-fields class="space-y-2">${renderAll(configSchema)}</div>`
  }

  const core = []
  const more = []
  configSchema.forEach(field => {
    if (field.group === "core") { core.push(field); return }
    if (field.group === "advanced") { more.push(field); return }
    if (field.required && !field.visibleWhen) { core.push(field) } else { more.push(field) }
  })

  // Degenerate partitions render flat (UX 3.9 failure table + plan resolution).
  if (core.length === 0 || more.length === 0) {
    return `<div data-step-config-fields class="space-y-2">${renderAll(configSchema)}</div>`
  }

  const setCount = more.filter(f =>
    (f.key in currentConfig) && isFieldValueNonDefault(f, currentConfig[f.key])
  ).length

  return `<div data-step-config-fields class="space-y-2">${renderAll(core)}${buildDisclosureSection({
    id: `step-more-${context.stepIndex ?? 0}`,
    label: "More options",
    badgeHTML: buildSetCountBadge(setCount),
    bodyHTML: `<div class="space-y-2 pt-2.5">${renderAll(more)}</div>`,
    startOpen: context.moreOpen === true
  })}</div>`
}
```

- [ ] **Step 7: `buildStepItemTemplate` — restore Advanced disclosure state** (templates.js:498-620). Two minimal edits:

```js
// BEFORE (lines 500-503, destructuring):
    id = "", index, action, description, actionOptionData, selectionLabels, suboption,
    keywordParams = [], retryCount = 0, retryBackoff = "none", timeout = 0,
    guardCondition = "", configFieldsHTML = "", currentConfig = {}, expanded = false

// AFTER (adds advancedOpen, default false → backward compatible):
    id = "", index, action, description, actionOptionData, selectionLabels, suboption,
    keywordParams = [], retryCount = 0, retryBackoff = "none", timeout = 0,
    guardCondition = "", configFieldsHTML = "", currentConfig = {}, expanded = false,
    advancedOpen = false
```
```js
// BEFORE (line 565):
        startOpen: false

// AFTER:
        startOpen: advancedOpen
```

- [ ] **Step 8: `buildBranchModalTemplate(elementId = "")` — var-pick on the field-condition manual-left and right inputs** (templates.js:630-835). Signature gains an optional param (callers passing nothing keep working — controller attrs are omitted when empty, per `autocompleteWrapperAttrs`).

```js
// BEFORE (line 630):
export function buildBranchModalTemplate() {

// AFTER:
export function buildBranchModalTemplate(elementId = "") {
```

Replace the left-manual wrap (lines 718-727) — keeps `data-branch-condition-left-manual`, `data-branch-condition-left`, and the existing revert button byte-for-byte in behavior, adds `relative`, the autocomplete wrapper attrs, target attr, `pl-2 pr-7`, and the `{x}` button positioned left of the revert button:

```html
                      <div data-branch-condition-left-manual class="hidden relative flex gap-1"${autocompleteWrapperAttrs(elementId, -1)}>
                        <input type="text"
                               data-branch-condition-left
                               ${elementId ? `data-context-autocomplete-target="input"` : ""}
                               placeholder="ctx[:field]"
                               class="flex-1 min-w-0 pl-2 pr-7 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-400">
                        ${elementId ? buildVarPickButton({ positionClasses: "right-9 top-1/2 -translate-y-1/2" }) : ""}
                        <button type="button"
                                data-action="click->property-editor#swapLeftOperandToSelect"
                                class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50"
                                title="Switch to dropdown">&#x25B2;</button>
                      </div>
```

Replace the right-operand input (lines 741-744) per UX 2.6b:

```html
                    <div class="relative flex-1"${autocompleteWrapperAttrs(elementId, -1)}>
                      <input type="text"
                             data-branch-condition-right
                             ${elementId ? `data-context-autocomplete-target="input"` : ""}
                             placeholder="value"
                             class="w-full pl-2 pr-7 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-400">
                      ${elementId ? buildVarPickButton() : ""}
                    </div>
```

Note: this turns the static template string into a template using `${...}` interpolation — it already is a template literal, so only the inserted expressions change. `_collectFieldCondition` (branch_manager.js:1197-1213) reads `[data-branch-condition-right]` by attribute — unaffected by the wrapper.

- [ ] **Step 9: Syntax check**

Run: `node --input-type=module --check < app/javascript/controllers/property_editor/templates.js`
Expected: no output (exit 0).

- [ ] **Step 10: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat(property-editor): shared var-pick/entity-select/partition template helpers

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: context_autocomplete_controller.js — input target, picker action, "Used in this element" group, empty state

**Files:**
- Modify: `app/javascript/controllers/context_autocomplete_controller.js` (whole file touched lightly; no behavior change for the keystroke path)

Depends on Task 1 only for the `OUTPUT_VAR_KEYS` import (runtime, not syntax) — can be built in parallel.

- [ ] **Step 1: Add the import, the `input` target, and the `_input` getter** (top of class):

```js
import { Controller } from "@hotwired/stimulus"
import { getAvailableVariables, filterVariables } from "flowchart/context_variable_provider"
import { OUTPUT_VAR_KEYS } from "controllers/property_editor/templates"
import { escapeHtml } from "utils"
```
```js
export default class extends Controller {
  static targets = ["input"]
  static values = {
    elementId: String,
    stepIndex: { type: Number, default: -1 }
  }

  /**
   * The text input/textarea this controller manages. New round-2 markup mounts
   * the controller on a `relative` wrapper (so the {x} button is in scope) and
   * marks the input with data-context-autocomplete-target="input". Legacy
   * markup mounts directly on the input — both keep working.
   */
  get _input() {
    return this.hasInputTarget ? this.inputTarget : this.element
  }
```

- [ ] **Step 2: Repoint every input-element reference from `this.element` to `this._input`.** Exact lines (current numbering): `connect()` listeners 32-34, `disconnect()` 40-42, `_getWordAtCursor` 56, `_positionDropdown` 100, `_selectOption` 226. Example for connect:

```js
    this._input.addEventListener("input", this._boundOnInput)
    this._input.addEventListener("keydown", this._boundOnKeydown)
    this._input.addEventListener("blur", this._boundOnBlur)
```

- [ ] **Step 3: Widen `_onClickOutside`** (line 271-275) so clicks anywhere inside the controller scope (input OR button) don't close the dropdown — for a bare-input mount `element.contains(target)` is equivalent to today's `target === element`:

```js
  _onClickOutside(event) {
    if (this._dropdown && !this._dropdown.contains(event.target) && !this.element.contains(event.target)) {
      this._destroyDropdown()
    }
  }
```

- [ ] **Step 4: Guard `_onBlur`** (line 262-269) against the picker refocus race:

```js
  _onBlur(event) {
    // Close dropdown after short delay to allow click on option. Keep it open
    // when focus has already returned to the input (picker() refocuses it).
    setTimeout(() => {
      if (!this._dropdown?.contains(document.activeElement) && document.activeElement !== this._input) {
        this._destroyDropdown()
      }
    }, 150)
  }
```

- [ ] **Step 5: Extract dropdown creation and add the picker entry point + helpers** (new code; `_renderDropdown` body shrinks to use `_ensureDropdown()`):

```js
  _ensureDropdown() {
    if (this._dropdown) return
    this._dropdown = document.createElement("div")
    this._dropdown.className = "context-autocomplete-dropdown bg-white border border-slate-200 rounded-lg shadow-lg max-h-64 overflow-y-auto w-64"
    this._dropdown.style.cssText = "position: fixed; z-index: 9999;"
    document.body.appendChild(this._dropdown)
    document.addEventListener("mousedown", this._boundOnClickOutside)
  }

  _renderDropdown() {
    this._ensureDropdown()
    this._positionDropdown()
    this._dropdown.innerHTML = this._buildDropdownHTML()
    this._updateSelection()
    this._wireOptionClicks()
  }

  /** mousedown handler on the {x} button — keeps focus on the input. */
  keepFocus(event) {
    event.preventDefault()
  }

  /**
   * Variable-pick button entry point: opens the same dropdown the keystroke
   * path uses, with the full (unfiltered) variable list plus a leading
   * "Used in this element" group of sibling-step output variables.
   * Purely additive — the typed path is unchanged.
   */
  async picker(event) {
    event.preventDefault()
    if (!this._canvas) this._resolveCanvas()

    let groups = []
    try {
      const result = await getAvailableVariables(this._canvas, this.elementIdValue, this.stepIndexValue)
      groups = result.groups || []
    } catch {
      groups = []
    }

    this._filteredGroups = this._buildPickerGroups(groups, this._collectSiblingStepVars())
    this._allOptions = this._flattenOptions(this._filteredGroups)
    this._selectedIndex = 0

    if (this._allOptions.length > 0) {
      this._renderDropdown()
    } else {
      this._renderNoVariablesDropdown()
    }

    // Restore focus so ↓/↑/Enter/Escape are handled by _onKeydown immediately.
    this._input.focus()
  }

  /**
   * Sibling-step output variables (resultVar/outputKey/targetVariable) read
   * from the live DOM — the same [data-step-item]/[data-step-config] elements
   * collectSteps() uses. Empty under the current one-step-per-element cap;
   * future-proof for multi-step elements.
   */
  _collectSiblingStepVars() {
    const ownItem = this._input.closest("[data-step-item]")
    const container = ownItem?.closest("[data-steps-container]")
    if (!container) return []

    const vars = []
    container.querySelectorAll("[data-step-item]").forEach(item => {
      if (item === ownItem) return
      const configInput = item.querySelector("[data-step-config]")
      if (!configInput?.value) return
      try {
        const config = JSON.parse(configInput.value)
        OUTPUT_VAR_KEYS.forEach(key => {
          const v = config[key]
          if (typeof v === "string" && v.trim() !== "" && !vars.includes(v)) vars.push(v)
        })
      } catch { /* ignore malformed config JSON */ }
    })
    return vars
  }

  _buildPickerGroups(existingGroups, siblingVars) {
    if (!siblingVars || siblingVars.length === 0) return existingGroups
    return [
      { label: "Used in this element", source: "sibling-steps", variables: siblingVars },
      ...existingGroups
    ]
  }

  /** Non-interactive empty state for the picker path (UX 2.1e). */
  _renderNoVariablesDropdown() {
    this._ensureDropdown()
    this._positionDropdown()
    this._dropdown.innerHTML = '<div class="px-3 py-2 text-[11px] text-slate-400 italic">No variables available</div>'
  }
```

(The keystroke path keeps its existing `'No matching variables'` string in `_buildDropdownHTML` — different intent, per UX 2.1e.)

- [ ] **Step 6: Syntax check**

Run: `node --input-type=module --check < app/javascript/controllers/context_autocomplete_controller.js`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/context_autocomplete_controller.js
git commit -m "feat(property-editor): context-autocomplete picker action with sibling-vars group

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: step_manager.js + property_editor_controller.js + form_builder.js — resultVar auto-suggest, entity-column swap actions, disclosure-state Map, badge refresh, KV row placeholders, loop collection var-pick

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js` (imports line 6-15; `stepPickerCommit` 727-761; `buildStepItemHTML` 447-489; `addConfigKvRow` 624-650; new methods)
- Modify: `app/javascript/controllers/property_editor_controller.js` (connect 60-82; `_hideSidebar` 972-988; `toggleDisclosure` 487-495; delegations 443-511; `_performSync` 1055-1098)
- Modify: `app/javascript/controllers/property_editor/form_builder.js` (`_buildInputHTML` text case, ~line 260)

- [ ] **Step 1: step_manager.js — import the new symbols** (extend the existing import from templates, line 7-12):

```js
import {
  buildStepPickerTemplate,
  buildStepItemTemplate,
  buildSectionHeader,
  buildStepConfigFieldsHTML,
  OUTPUT_VAR_KEYS
} from "controllers/property_editor/templates"
```
Also add `escapeHtml` usage check — already imported (line 6).

- [ ] **Step 2: step_manager.js — resultVar auto-suggest in `stepPickerCommit`.** After the existing `schema.forEach(field => { if (field.default !== undefined) ... })` block (lines 744-748), add one call:

```js
    const actionEntry = getActionConfig(leaf.action)
    const defaultConfig = {}
    if (actionEntry) {
      const schema = actionEntry.configSchemaBySubOption?.[leaf.suboption] || actionEntry.configSchema || []
      schema.forEach(field => {
        if (field.default !== undefined) defaultConfig[field.key] = field.default
      })
      this._applyResultVarAutoSuggest(schema, defaultConfig, leaf.action)
    }
```

New private methods (place after `_hideStepPicker`):

```js
  /**
   * Pre-fill output-variable fields (resultVar/outputKey/targetVariable) at
   * step-commit time only: schema default first, derived base otherwise, with
   * _2.._9 suffix on collision against sibling steps' stored configs.
   * Runs exactly once per committed step — nothing re-derives after the user
   * edits the field (reloads render from stored config; changeStep restores
   * the live DOM node), so no dirty flag is needed.
   */
  _applyResultVarAutoSuggest(schema, defaultConfig, actionKey) {
    const usedVars = this._collectSiblingOutputVars()
    schema.forEach(field => {
      if (!OUTPUT_VAR_KEYS.includes(field.key)) return

      let base = defaultConfig[field.key]
      if (base === undefined || String(base).trim() === "") {
        base = this._deriveOutputVarBase(actionKey)
      }
      base = String(base)

      let candidate = base
      let suffix = 2
      while (usedVars.includes(candidate) && suffix <= 9) {
        candidate = `${base}_${suffix}`
        suffix++
      }
      defaultConfig[field.key] = candidate
      usedVars.push(candidate)
    })
  }

  _deriveOutputVarBase(actionKey) {
    if (/_models$/.test(actionKey)) return "models"
    if (/_model$/.test(actionKey)) return "model"
    return "result"
  }

  /** Output-variable values already used by step cards in the live DOM. */
  _collectSiblingOutputVars() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return []

    const vars = []
    container.querySelectorAll("[data-step-item]").forEach(item => {
      const configInput = item.querySelector("[data-step-config]")
      if (!configInput?.value) return
      try {
        const config = JSON.parse(configInput.value)
        OUTPUT_VAR_KEYS.forEach(key => {
          const v = config[key]
          if (typeof v === "string" && v.trim() !== "" && !vars.includes(v)) vars.push(v)
        })
      } catch { /* ignore */ }
    })
    return vars
  }
```

- [ ] **Step 3: step_manager.js — pass entityAttributes + disclosure state into rendering.** In `buildStepItemHTML` (lines 459-489), move `resolvedId` computation above the context and extend it:

```js
    // Every step DOM item must carry a stable id in data-step-id … (comment unchanged)
    const resolvedId = id || generateStepId()

    // Build config fields HTML for the expanded step item
    const context = {
      elementId: this.controller.currentElement?.id || "",
      stepIndex: index,
      entityAttributes: this.controller.canvas?.entityAttributes || [],
      moreOpen: this.controller.disclosureState?.get(`${resolvedId}:more`) === true
    }
    const configFieldsHTML = this.buildStepConfigHTML(action, currentConfig, suboption, context)
```
and add to the `buildStepItemTemplate({...})` call:
```js
      expanded,
      advancedOpen: this.controller.disclosureState?.get(`${resolvedId}:advanced`) === true
```

- [ ] **Step 4: step_manager.js — entity column swap/sync handlers** (new methods, after `removeConfigKvRow`). Contract: hidden input is the only `data-config-input`; `__manual__` is cleared immediately so it can never be collected (UX flag #10); every path funnels through `handleConfigFieldChange` so visibleWhen, stored config, step I/O, and canvas sync behave exactly as a plain text edit does today:

```js
  /**
   * Entity column select changed: "__manual__" swaps to the manual input;
   * any real value is mirrored into the hidden data-config-input element
   * that collectStepConfig() reads.
   */
  handleEntityColumnSelectChange(event) {
    const select = event.target
    const wrapper = select.closest("[data-entity-field-wrapper]")
    if (!wrapper) return

    if (select.value === "__manual__") {
      this.swapEntityColumnToManual(event)
      return
    }

    const hidden = wrapper.querySelector("input[type='hidden'][data-config-input]")
    if (hidden) hidden.value = select.value
    this.handleConfigFieldChange(event)
  }

  swapEntityColumnToManual(event) {
    if (event.preventDefault) event.preventDefault()
    const wrapper = event.target.closest("[data-entity-field-wrapper]")
    if (!wrapper) return
    const select = wrapper.querySelector("[data-entity-column-select]")
    const manualWrap = wrapper.querySelector("[data-entity-manual-wrap]")
    const hidden = wrapper.querySelector("input[type='hidden'][data-config-input]")
    if (select) { select.classList.add("hidden"); select.value = "" }
    if (hidden) hidden.value = ""
    if (manualWrap) {
      manualWrap.classList.remove("hidden")
      const input = manualWrap.querySelector("[data-entity-column-manual]")
      if (input) { input.value = ""; input.focus() }
    }
    this.handleConfigFieldChange(event)
  }

  swapEntityColumnToSelect(event) {
    event.preventDefault()
    const wrapper = event.target.closest("[data-entity-field-wrapper]")
    if (!wrapper) return
    const select = wrapper.querySelector("[data-entity-column-select]")
    const manualWrap = wrapper.querySelector("[data-entity-manual-wrap]")
    const hidden = wrapper.querySelector("input[type='hidden'][data-config-input]")
    if (manualWrap) {
      manualWrap.classList.add("hidden")
      const input = manualWrap.querySelector("[data-entity-column-manual]")
      if (input) input.value = ""
    }
    if (hidden) hidden.value = ""
    if (select) { select.classList.remove("hidden"); select.value = "" }
    this.handleConfigFieldChange(event)
  }

  /** Mirror manual column typing into the hidden data-config-input element. */
  syncEntityColumnManual(event) {
    const wrapper = event.target.closest("[data-entity-field-wrapper]")
    const hidden = wrapper?.querySelector("input[type='hidden'][data-config-input]")
    if (hidden) hidden.value = event.target.value
  }
```

- [ ] **Step 5: step_manager.js — semantic placeholders on dynamically added KV rows.** In `addConfigKvRow` (lines 624-650):

```js
// BEFORE (line 632-642):
    const kvInput = "flex-1 px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
    newRow.innerHTML = `
      <input type="text" data-kv-key placeholder="Key" class="${kvInput}">
      <input type="text" data-kv-value placeholder="Value" class="${kvInput}">

// AFTER:
    const kvInput = "flex-1 px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
    const keyPlaceholder = kvList.dataset.keyPlaceholder || "Key"
    const valuePlaceholder = kvList.dataset.valuePlaceholder || "Value"
    newRow.innerHTML = `
      <input type="text" data-kv-key placeholder="${escapeHtml(keyPlaceholder)}" class="${kvInput}">
      <input type="text" data-kv-value placeholder="${escapeHtml(valuePlaceholder)}" class="${kvInput}">
```

- [ ] **Step 6: step_manager.js — More-options badge refresh** (new method after `updateStepOverrideBadge`). It mirrors `buildSetCountBadge`'s counting rules against the live DOM via `data-field-default`:

```js
  /**
   * Re-count non-default values inside each step card's "More options"
   * disclosure body and update its data-set-count-badge in place.
   * Called from property_editor_controller._performSync (debounced 100ms),
   * so typing, select changes, and KV edits all keep the badge fresh.
   */
  refreshMoreOptionsBadges() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return

    container.querySelectorAll("[data-step-item]").forEach(item => {
      const badge = item.querySelector("[data-set-count-badge]")
      if (!badge) return
      const body = badge.closest("[data-disclosure]")?.querySelector("[data-disclosure-body]")
      if (!body) return

      let count = 0
      body.querySelectorAll("[data-config-field]").forEach(fieldEl => {
        const defaultValue = fieldEl.dataset.fieldDefault ?? ""

        const kvList = fieldEl.querySelector("[data-key-value-list]")
        if (kvList) {
          const hasPair = [...kvList.querySelectorAll("[data-kv-row]")]
            .some(row => row.querySelector("[data-kv-key]")?.value?.trim())
          if (hasPair) count++
          return
        }

        const input = fieldEl.querySelector("[data-config-input]")
        if (input && String(input.value ?? "") !== defaultValue) count++
      })

      badge.textContent = `${count} set`
      badge.classList.toggle("hidden", count === 0)
    })
  }
```

- [ ] **Step 7: property_editor_controller.js — disclosure-state Map.** In `connect()` (after line 64):

```js
    this.unsavedChangesCache = {} // Cache for unsaved changes by element ID
    this.disclosureState = new Map() // per-session step disclosure open/closed (key: "<stepId>:more|advanced")
```

In `_hideSidebar()` (after line 985 `this.currentElement = null` region — add before nulling):

```js
    // Disclosure open/closed state is per element-session (spec C).
    this.disclosureState?.clear()
```

Replace `toggleDisclosure` (lines 487-495):

```js
  /**
   * Toggle a buildDisclosureSection() body open/closed.
   * Used by step Advanced / More options and loop Options. For step-card
   * disclosures the state is recorded per (stepId, section) so it survives
   * card collapse/expand within the page session; cleared on element close.
   */
  toggleDisclosure(event) {
    event.preventDefault()
    const section = event.currentTarget.closest("[data-disclosure]")
    if (!section) return
    const body = section.querySelector("[data-disclosure-body]")
    const chevron = section.querySelector("[data-disclosure-chevron]")
    if (body) body.classList.toggle("hidden")
    if (chevron) chevron.classList.toggle("rotate-180")
    this._recordDisclosureState(section, body)
  }

  _recordDisclosureState(section, body) {
    if (!body || !this.disclosureState) return
    const stepId = section.closest("[data-step-item]")?.dataset.stepId
    if (!stepId) return
    const disclosureId = section.dataset.disclosureId || ""
    const kind = disclosureId.startsWith("step-more") ? "more"
      : disclosureId.startsWith("step-advanced") ? "advanced" : null
    if (!kind) return
    this.disclosureState.set(`${stepId}:${kind}`, !body.classList.contains("hidden"))
  }
```

- [ ] **Step 8: property_editor_controller.js — new delegated actions.** Add after `removeConfigKvRow` delegation (line 481), keeping the existing delegation style. The QC delegations point at branch_manager methods implemented in Task 4 (safe: nothing triggers them until Task 4's markup ships):

```js
  handleEntityColumnSelectChange(event) {
    this.stepManager.handleEntityColumnSelectChange(event)
  }

  swapEntityColumnToManual(event) {
    this.stepManager.swapEntityColumnToManual(event)
  }

  swapEntityColumnToSelect(event) {
    this.stepManager.swapEntityColumnToSelect(event)
  }

  syncEntityColumnManual(event) {
    this.stepManager.syncEntityColumnManual(event)
  }

  handleQcWhereFieldChange(event) {
    this.branchManager.handleQcWhereFieldChange(event)
  }

  swapQcWhereFieldToManual(event) {
    this.branchManager.swapQcWhereFieldToManual(event)
  }

  swapQcWhereFieldToSelect(event) {
    this.branchManager.swapQcWhereFieldToSelect(event)
  }
```

- [ ] **Step 9: property_editor_controller.js — badge refresh hook in `_performSync`.** After `this._updateTabBadges()` (line 1097):

```js
    this._updateTabBadges()

    // Keep "N set" badges on step More-options disclosures current.
    if (this.currentElement?.type === "process") {
      this.stepManager?.refreshMoreOptionsBadges()
    }
```

- [ ] **Step 10: form_builder.js — var-pick on element-level var-ref text fields (loop `collection`, `itemVariable`, `indexVariable`).** Add imports at the top of form_builder.js (it already imports `buildDisclosureSection` and `escapeHtml`; extend the templates import):

```js
import { isVarRefField, buildVarPickButton } from "controllers/property_editor/templates"
```
(merge into the existing import statement from `controllers/property_editor/templates` if one exists — check the file head; otherwise add a new import line.)

In `_buildInputHTML`, replace the `case "text":` branch:

```js
      case "text": {
        const elementId = this.controller.currentElement?.id || ""
        if (elementId && isVarRefField(fieldName)) {
          return `
            <div class="relative" data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}">
              <input type="text"
                     id="prop_${fieldName}"
                     name="${fieldName}"
                     data-context-autocomplete-target="input"
                     value="${escapeHtml(currentValue)}"
                     ${placeholder}
                     ${isRequired}
                     ${extraAction}
                     class="w-full pl-2 pr-7 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
              ${buildVarPickButton()}
            </div>
          `
        }
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
      }
```

(`name="${fieldName}"` placement is unchanged, so `FormData`/`_collectFormData` and the For-Each validation `querySelector('input[name="collection"]')` at property_editor_controller.js:760 keep working. The `itemVariable` hint action `input->property-editor#updateItemVariableHint` rides along via `extraAction`.)

- [ ] **Step 11: Syntax checks**

```bash
node --input-type=module --check < app/javascript/controllers/property_editor/step_manager.js
node --input-type=module --check < app/javascript/controllers/property_editor_controller.js
node --input-type=module --check < app/javascript/controllers/property_editor/form_builder.js
```
Expected: exit 0 for all three.

- [ ] **Step 12: Commit**

```bash
git add app/javascript/controllers/property_editor/step_manager.js app/javascript/controllers/property_editor_controller.js app/javascript/controllers/property_editor/form_builder.js
git commit -m "feat(property-editor): resultVar auto-suggest, entity column swaps, disclosure state, loop var-pick

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: branch_manager.js — QC WHERE key escape hatch + value var-pick, amber schema hint, condition-row right-operand var-pick, modal elementId

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js` (imports line 10; `renderBranchModal` 402-407; `onQueryCountEntityChange` 144-179; `_addQueryCountWhereRow` 1126-1185; `_collectQueryCountCondition` 1216-1258; `_buildConditionRowHTML` 657-737; new swap methods)

- [ ] **Step 1: Extend the templates import** (line 10):

```js
import { buildBranchModalTemplate, buildBranchItemTemplate, buildSectionHeader, buildEmptyState, buildVarPickButton } from "controllers/property_editor/templates"
```

- [ ] **Step 2: Pass the decision element id into the modal template** (`renderBranchModal`, lines 402-407):

```js
  renderBranchModal() {
    if (!this.controller.hasBranchModalContainerTarget) return

    // Use template from templates.js; elementId enables the var-pick buttons'
    // context-autocomplete scope (omitted attrs when no element — degrades).
    this.controller.branchModalContainerTarget.innerHTML =
      buildBranchModalTemplate(this.controller.currentElement?.id || "")
  }
```

- [ ] **Step 3: Add a private autocomplete-attrs helper** (near `_getCustomerId`, line 1018):

```js
  /** data-controller attrs for a var-pick wrapper, "" when no current element. */
  _autocompleteAttrs() {
    const elementId = this.controller.currentElement?.id || ""
    if (!elementId) return ""
    return ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="-1"`
  }
```

- [ ] **Step 4: `_addQueryCountWhereRow` — manual optgroup on the key select, manual input, var-pick on the value input.** Replace the function body (lines 1126-1185). The select keeps every existing option byte-for-byte (entity `data.<slug>` fields, `created_at`, `updated_at`) and gains only the change-action and the trailing optgroup; the value input keeps its selector and classes, gaining only `pl-2 pr-7` and the wrapper:

```js
  _addQueryCountWhereRow(container) {
    const schema = this._selectedEntitySchema || []
    const rowIndex = container.querySelectorAll("[data-qc-where-row]").length

    let fieldOptionsHTML = `<option value="">Select field...</option>`
    schema.forEach(field => {
      const slug = field.name_slug || field.name
      fieldOptionsHTML += `<option value="data.${escapeHtml(slug)}">${escapeHtml(field.name || slug)}</option>`
    })
    // Add system fields
    fieldOptionsHTML += `<option value="created_at">created_at</option>`
    fieldOptionsHTML += `<option value="updated_at">updated_at</option>`
    // Manual escape hatch (value is a sentinel — never collected, see
    // _collectQueryCountCondition / swapQcWhereFieldToManual)
    fieldOptionsHTML += `<optgroup label="Other"><option value="__manual__">enter manually&hellip;</option></optgroup>`

    const autoAttrs = this._autocompleteAttrs()

    const removeButton = rowIndex > 0 ? `
      <button type="button"
              data-action="click->property-editor#removeQueryCountWhereRow"
              class="absolute -top-1 -right-1 p-0.5 text-slate-400 hover:text-red-500 bg-white border border-slate-200 rounded-full shadow-sm hover:bg-red-50 transition-colors"
              title="Remove filter">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    ` : ""

    const rowHTML = `
      <div data-qc-where-row class="relative p-2 bg-white rounded border border-amber-100">
        ${removeButton}
        <div class="grid grid-cols-3 gap-2">
          <div>
            <select data-qc-where-field
                    data-action="change->property-editor#handleQcWhereFieldChange"
                    class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
              ${fieldOptionsHTML}
            </select>
            <div data-qc-where-field-manual class="hidden flex gap-1">
              <input type="text"
                     data-qc-where-field-input
                     placeholder="column name"
                     class="flex-1 min-w-0 px-2 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
              <button type="button"
                      data-action="click->property-editor#swapQcWhereFieldToSelect"
                      title="Switch to dropdown"
                      class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50 flex-shrink-0">&#x25B2;</button>
            </div>
          </div>
          <div>
            <select data-qc-where-op
                    class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
              <option value="==">==</option>
              <option value="!=">!=</option>
              <option value=">">&gt;</option>
              <option value=">=">&gt;=</option>
              <option value="<">&lt;</option>
              <option value="<=">&lt;=</option>
              <option value="contains">contains</option>
              <option value="blank?">is empty</option>
              <option value="present?">is not empty</option>
            </select>
          </div>
          <div class="relative"${autoAttrs}>
            <input type="text"
                   data-qc-where-value
                   ${autoAttrs ? `data-context-autocomplete-target="input"` : ""}
                   class="w-full pl-2 pr-7 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm font-mono placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500"
                   placeholder="value" />
            ${autoAttrs ? buildVarPickButton() : ""}
          </div>
        </div>
      </div>
    `

    container.insertAdjacentHTML("beforeend", rowHTML)
  }
```

- [ ] **Step 5: QC field swap handlers** (new methods after `removeQueryCountWhereRow`, line 196). Sentinel discipline: select is cleared to `""` the moment manual mode is entered:

```js
  /** WHERE key select changed: only "__manual__" needs handling. */
  handleQcWhereFieldChange(event) {
    if (event.target.value === "__manual__") this.swapQcWhereFieldToManual(event)
  }

  swapQcWhereFieldToManual(event) {
    if (event.preventDefault) event.preventDefault()
    const row = event.target.closest("[data-qc-where-row]")
    if (!row) return
    const select = row.querySelector("[data-qc-where-field]")
    const manual = row.querySelector("[data-qc-where-field-manual]")
    if (select) { select.classList.add("hidden"); select.value = "" }
    if (manual) {
      manual.classList.remove("hidden")
      const input = manual.querySelector("[data-qc-where-field-input]")
      if (input) { input.value = ""; input.focus() }
    }
  }

  swapQcWhereFieldToSelect(event) {
    event.preventDefault()
    const row = event.target.closest("[data-qc-where-row]")
    if (!row) return
    const select = row.querySelector("[data-qc-where-field]")
    const manual = row.querySelector("[data-qc-where-field-manual]")
    if (manual) {
      manual.classList.add("hidden")
      const input = manual.querySelector("[data-qc-where-field-input]")
      if (input) input.value = ""
    }
    if (select) { select.classList.remove("hidden"); select.value = "" }
  }
```

- [ ] **Step 6: `_collectQueryCountCondition` — read the manual key when visible.** Replace the WHERE-rows loop (lines 1226-1235). Output shape (`{field, op, value}` strings, rules array, AND operator) is unchanged; when manual mode is unused the read path is identical to today:

```js
    // Collect WHERE rules
    const whereRows = modal.querySelectorAll("[data-qc-where-row]")
    const rules = []
    whereRows.forEach(row => {
      const manualWrap = row.querySelector("[data-qc-where-field-manual]")
      const manualVisible = manualWrap && !manualWrap.classList.contains("hidden")
      const field = manualVisible
        ? (row.querySelector("[data-qc-where-field-input]")?.value?.trim() || "")
        : (row.querySelector("[data-qc-where-field]")?.value || "")
      const op = row.querySelector("[data-qc-where-op]")?.value || "=="
      const value = row.querySelector("[data-qc-where-value]")?.value?.trim() || ""

      if (field) {
        rules.push({ field, op, value })
      }
    })
```

- [ ] **Step 7: Amber "schema unavailable" hint in `onQueryCountEntityChange`** (lines 144-179). Add the clear call after the rows are emptied, and show on both failure paths (post-`fetchId` staleness check):

```js
    // Clear existing WHERE rows
    whereRows.innerHTML = ""
    this._clearQcSchemaError(modal)

    if (!entityId) return
    …
    try {
      const response = await fetch(`/${customerId}/admin/maintenance/entities/${entityId}.json`, {
        headers: { "Accept": "application/json" }
      })
      if (fetchId !== this._entityFetchId) return
      if (!response.ok) { this._showQcSchemaError(whereRows); return }

      const entity = await response.json()
      this._selectedEntitySchema = entity.property_schema || []
      this._selectedEntityName = entity.name || ""

      // Add one empty WHERE row
      this._addQueryCountWhereRow(whereRows)
    } catch (e) {
      if (fetchId === this._entityFetchId) this._showQcSchemaError(whereRows)
    }
```

New private methods (near `_appendEntityLoadError`, line 1116):

```js
  /**
   * Amber non-blocking hint under the WHERE rows when the entity schema fetch
   * fails. Rows remain fully usable: the key select still offers system fields
   * and the "enter manually…" escape hatch.
   */
  _showQcSchemaError(whereRows) {
    if (!whereRows) return
    if (whereRows.parentElement?.querySelector("[data-qc-schema-error]")) return
    whereRows.insertAdjacentHTML("afterend", `
      <div data-qc-schema-error class="mt-1 flex items-center gap-1 text-[10px] text-amber-700">
        <svg class="w-3 h-3 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <span>Schema unavailable &mdash; enter field names manually</span>
      </div>
    `)
  }

  _clearQcSchemaError(modal) {
    modal?.querySelector("[data-qc-schema-error]")?.remove()
  }
```

(Note the reordering: the staleness check now precedes the `!response.ok` return so a stale failure can't paint the hint over a fresh selection.)

- [ ] **Step 8: `_buildConditionRowHTML` — var-pick on the right-operand custom input** (lines 720-732). Left operand stays a select — no button (UX 2.6c). Replace the custom-container block:

```js
            <div class="${isCustomValue ? '' : 'hidden'}" data-condition-right-operand-custom-container>
              <div class="relative flex gap-1"${this._autocompleteAttrs()}>
                <input type="text"
                       data-condition-right-operand-custom
                       ${this._autocompleteAttrs() ? `data-context-autocomplete-target="input"` : ""}
                       value="${isCustomValue ? escapeHtml(rightOperand) : ''}"
                       placeholder="Enter custom value..."
                       class="flex-1 min-w-0 pl-2 pr-7 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
                ${this._autocompleteAttrs() ? buildVarPickButton({ positionClasses: "right-9 top-1/2 -translate-y-1/2" }) : ""}
                <button type="button"
                        data-action="click->property-editor#switchToSelectRightOperand"
                        class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50"
                        title="Switch to dropdown">&#x25BC;</button>
              </div>
            </div>
```

(To avoid calling `_autocompleteAttrs()` four times, hoist `const autoAttrs = this._autocompleteAttrs()` to the top of `_buildConditionRowHTML` and use `autoAttrs` in the template.) `collectCondition` (lines 1394-1463) reads `[data-condition-right-operand-custom]` and the container's `hidden` class — both preserved, so emitted `condition{}` objects are byte-identical. `handleConditionOperatorChange` (1268-1282) and `switchToSelectRightOperand` (1383-1392) selectors are untouched.

- [ ] **Step 9: Syntax check**

Run: `node --input-type=module --check < app/javascript/controllers/property_editor/branch_manager.js`
Expected: exit 0.

- [ ] **Step 10: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git commit -m "feat(property-editor): QC where-key escape hatch, value var-pick, amber schema hint, condition-row var-pick

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: action_configs — rendering-hint annotations (pure data; no key renames, no value/type changes)

**Files (Modify only — every change adds properties to existing field objects):**
- `app/javascript/flowchart/constants/action_configs/model_actions.js`
- `app/javascript/flowchart/constants/action_configs/data_actions.js`
- `app/javascript/flowchart/constants/action_configs/communication_actions.js`
- `app/javascript/flowchart/constants/action_configs/background_actions.js`
- `app/javascript/flowchart/constants/action_configs/caching_actions.js`
- `app/javascript/flowchart/constants/action_configs/file_actions.js`
- `app/javascript/flowchart/constants/action_configs/human_workflow_actions.js`
- `app/javascript/flowchart/constants/action_configs/resilience_actions.js`
- `app/javascript/flowchart/constants/action_configs/response_actions.js`
- `app/javascript/flowchart/constants/action_configs/scheduling_actions.js`
- `app/javascript/flowchart/constants/action_configs/security_actions.js`
- `app/javascript/flowchart/constants/action_configs/service_actions.js`
- `app/javascript/flowchart/constants/action_configs/utility_actions.js`
- (`concurrency_actions.js`, `realtime_actions.js`, `validation_actions.js` have no `key_value_list` fields and no entity-column fields — no changes.)

Annotation pattern (the only edit shape allowed in this task — example on `model_actions.js` `conditions`):

```js
      {
        key: "conditions",
        type: "key_value_list",
        label: "Conditions",
        keyPlaceholder: "field name",
        valuePlaceholder: "value or ctx[:ref]",
        visibleWhen: { field: "queryType", value: "where" }
      },
```

- [ ] **Step 1: `keyPlaceholder`/`valuePlaceholder` on every `key_value_list` field** (every occurrence — some keys appear in multiple actions within a file; annotate each). Complete table (placeholders chosen per UX 2.4's recommended set, extended to the full sweep):

| File | key | keyPlaceholder | valuePlaceholder |
|---|---|---|---|
| background_actions | `discardOn` | `error class` | `(leave blank)` |
| background_actions | `retryOn` | `error class` | `(leave blank)` |
| caching_actions | `tags` (×2) | `tag` | `(leave blank)` |
| communication_actions | `headers` (×3) | `header name` | `value or ctx[:ref]` |
| communication_actions | `queryParams` | `param name` | `value or ctx[:ref]` |
| communication_actions | `cookies` | `cookie name` | `value` |
| communication_actions | `retryOnStatus` | `status code` | `(leave blank)` |
| communication_actions | `attachments` | `file name` | `ctx[:source]` |
| communication_actions | `metadata` | `key` | `value` |
| communication_actions | `fallbackChannels` | `channel` | `(leave blank)` |
| data_actions | `arrayValue` | `index` | `value` |
| data_actions | `hashValue` | `key` | `value` |
| data_actions | `fieldMappings` (×2) | `source key` | `target key` |
| data_actions | `fieldsToRemove` | `field name` | `(leave blank)` |
| data_actions | `computedFields` | `field name` | `Ruby expression` |
| data_actions | `tags` | `tag` | `(leave blank)` |
| data_actions | `contextFields` | `ctx key` | `(leave blank)` |
| data_actions | `ignoreKeys` | `key` | `(leave blank)` |
| data_actions | `mappings` | `source key` | `target key` |
| data_actions | `operandList` | `operand` | `(leave blank)` |
| data_actions | `variablePaths` | `ctx path` | `(leave blank)` |
| data_actions | `operations` | `operation` | `argument` |
| data_actions | `keys` | `key` | `(leave blank)` |
| data_actions | `renameMap` | `old key` | `new key` |
| data_actions | `csvColumns` | `column` | `(leave blank)` |
| data_actions | `sortFields` | `field name` | `asc or desc` |
| data_actions | `collectionKeys` | `key` | `(leave blank)` |
| data_actions | `valueList` | `value` | `(leave blank)` |
| data_actions | `fields` | `field name` | `(leave blank)` |
| data_actions | `renameMapping` | `old key` | `new key` |
| file_actions | `columns` | `column` | `(leave blank)` |
| file_actions | `allowedTypes` | `MIME type` | `(leave blank)` |
| file_actions | `metadata` | `key` | `value` |
| file_actions | `includeHeaders` | `header` | `(leave blank)` |
| file_actions | `colTypes` | `column` | `type` |
| human_workflow_actions | `notificationChannels` (×2) | `channel` | `(leave blank)` |
| human_workflow_actions | `checklistItems` | `item` | `(leave blank)` |
| human_workflow_actions | `attachments` | `file name` | `ctx[:source]` |
| human_workflow_actions | `formFields` | `field name` | `field type` |
| human_workflow_actions | `validationRules` | `field name` | `rule` |
| human_workflow_actions | `escalationLevels` | `level` | `assignee` |
| model_actions | `conditions` (×4) | `field name` | `value or ctx[:ref]` |
| model_actions | `structuredConditions` | `field name` | `value or ctx[:ref]` |
| model_actions | `computedFields` | `field name` | `Ruby expression` |
| model_actions | `uniqueBy` (×2) | `field name` | `(leave blank)` |
| model_actions | `returning` (×2) | `field name` | `(leave blank)` |
| model_actions | `matchFields` | `field name` | `(leave blank)` |
| model_actions | `fields` | `field name` | `(leave blank)` |
| model_actions | `excludeFields` | `field name` | `(leave blank)` |
| model_actions | `overrideFields` | `field name` | `value or ctx[:ref]` |
| model_actions | `fieldAssignments` | `model attribute` | `ctx[:value]` |
| model_actions | `aggregations` | `function` | `field name` |
| model_actions | `groupByFields` | `field name` | `(leave blank)` |
| model_actions | `bindings` | `param name` | `ctx[:source]` |
| resilience_actions | `retryableErrors` | `error class` | `(leave blank)` |
| response_actions | `headers` | `header name` | `value or ctx[:ref]` |
| response_actions | `queryParams` | `param name` | `value or ctx[:ref]` |
| scheduling_actions | `schedule` | `cron field` | `value` |
| scheduling_actions | `holidays` | `date (YYYY-MM-DD)` | `(leave blank)` |
| security_actions | `roleList` | `role` | `(leave blank)` |
| security_actions | `allowedTags` | `tag` | `(leave blank)` |
| security_actions | `allowedAttributes` | `attribute` | `(leave blank)` |
| security_actions | `claims` | `claim` | `value or ctx[:ref]` |
| security_actions | `algorithmAllowlist` | `algorithm` | `(leave blank)` |
| security_actions | `requiredClaims` | `claim` | `(leave blank)` |
| service_actions | `args` | `position` | `value or ctx[:ref]` |
| service_actions | `kwargs` | `keyword` | `value or ctx[:ref]` |
| utility_actions | `metadata` | `key` | `value` |
| utility_actions | `tools` | `tool name` | `(leave blank)` |
| utility_actions | `interpolations` | `placeholder` | `value or ctx[:ref]` |
| utility_actions | `fieldsToReturn` | `field name` | `(leave blank)` |
| utility_actions | `variables` | `name` | `value or ctx[:ref]` |
| utility_actions | `filters` | `filter` | `argument` |

Completeness check after editing: `grep -c 'type: "key_value_list"'` must equal `grep -c 'keyPlaceholder:'` per file.

- [ ] **Step 2: `entityField: true` on entity-column fields.** Add the property line right under each `key:` line:

- `model_actions.js`: `findField` (find_model, line ~50), `groupBy` (query_models ~296, distinct_query ~596, aggregate_query ~1005), `distinctField` (distinct_query ~589), `aggregateField` (aggregate_query ~1042).
- `data_actions.js` (collection-item field keys — typically entity columns when the collection came from query_models; manual hatch covers everything else): every occurrence of `filterField` (~1775, ~2349, ~2591, ~2638), `sortField` (~2029), `groupField` (~2103), `matchField` (~2540).
- Do **not** annotate `sourceField`/`targetField` (they are var-ref fields, handled by VAR_REF_PATTERN) and do **not** annotate the generic `field` key at data_actions.js:~1961 unless inspection shows it denotes a record column (it sits under a `custom` option context — leave it untouched if ambiguous).

- [ ] **Step 3: `group` annotations on the heavy schemas.** Only `group: "core"` lines are added (everything unannotated follows the heuristic: required-without-visibleWhen → core, rest → More options). Rule of thumb applied: visibleWhen children of a core controlling select are annotated core so they don't reveal inside a collapsed disclosure.

- `model_actions.js` — `query_models`: add `group: "core"` to `queryType`, `conditions`, `scopeName`, `scopeArgs`, `sqlExpression`, `orderBy`, `limit`, `resultVar`. (Heuristic alone would have left only `sqlExpression` exposed.)
- `model_actions.js` — `find_model`: add `group: "core"` to `findStrategy`, `findField`, `findValue`, `resultVar`.
- `data_actions.js` — `transform`: add `group: "core"` to `transformType`, `sourceField`, `targetField`, `fieldMappings`, `customExpression`, plus its `resultVar` if the schema has one (check — the visible block ends at `format`; if absent, skip).
- `communication_actions.js` — `API_call`: add `group: "core"` to `httpMethod`, `url`, `headers`, `bodyTemplate`, `authType`, `authToken`, `authUsername`, `authPassword`, `apiKeyHeader`, `apiKeyValue`, `resultVar` (the auth fields are visibleWhen children of `authType`).

- [ ] **Step 4: Syntax check all touched config files**

```bash
for f in app/javascript/flowchart/constants/action_configs/*.js; do node --input-type=module --check < "$f" || echo "FAIL: $f"; done
```
Expected: no FAIL lines.

- [ ] **Step 5: Serialization-shape guard.** Confirm no key renames or value changes slipped in:

```bash
git diff -U0 app/javascript/flowchart/constants/action_configs/ | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^\+\s*(keyPlaceholder|valuePlaceholder|entityField|group):'
```
Expected: empty output (every added line is one of the four annotations; nothing removed).

- [ ] **Step 6: Commit**

```bash
git add app/javascript/flowchart/constants/action_configs/
git commit -m "feat(property-editor): rendering-hint annotations on action configSchemas

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Verification — specs, syntax sweep, no-removal audit, byte-equality QA

**Files:**
- Test: `spec/requests/maintenance/flowcharts_editor_spec.rb` (run only; the server-rendered surface `app/views/admin/maintenance/flowcharts/_editor.html.erb` is untouched this round, so no new markup guards are required — additive guards would assert client-rendered markup the request spec cannot see)

- [ ] **Step 1: Full JS syntax sweep of every touched file**

```bash
for f in \
  app/javascript/controllers/property_editor/templates.js \
  app/javascript/controllers/context_autocomplete_controller.js \
  app/javascript/controllers/property_editor/step_manager.js \
  app/javascript/controllers/property_editor/branch_manager.js \
  app/javascript/controllers/property_editor/form_builder.js \
  app/javascript/controllers/property_editor_controller.js \
  app/javascript/flowchart/constants/action_configs/*.js; do
  node --input-type=module --check < "$f" || echo "FAIL: $f"
done
```
Expected: no FAIL lines.

- [ ] **Step 2: Targeted request specs**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_editor_spec.rb`
Expected: all green (same count as before this branch — no server-rendered changes).

- [ ] **Step 3: Cross-file contract greps** (each must hold):

```bash
# Exactly one data-config-input element exists per entityField widget (hidden input only)
grep -n "data-config-input" app/javascript/controllers/property_editor/templates.js
# Expected: select/manual input lines do NOT carry data-config-input; the hidden input does.

# Sentinel never collectable
grep -n "__manual__" app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor/step_manager.js app/javascript/controllers/property_editor/templates.js
# Expected: every swap handler clears the select to "" before showing manual.

# Badge selectors not conflated (UX flag #12)
grep -n "data-set-count-badge\|data-override-badge" app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/step_manager.js
```

- [ ] **Step 4: Manual no-removal audit (run in browser at `/:cid/admin/maintenance/flowcharts/:id/edit`, draft flowchart).** Every item is a pre-round-2 interaction that must still work exactly:

1. Process step: pick action, type free text into every field type (text, textarea, number, select, KV list) — typing never blocked by any new widget.
2. KV list: add row, remove row, last-row auto-replenish; rows added via "Add" show the semantic placeholders; collected pairs unchanged (`{key, value}` array).
3. visibleWhen: change `queryType` on Query Models — `conditions`/`scopeName`/`sqlExpression` toggle correctly **including fields inside the closed "More options" body** (cross-partition, UX 3.6).
4. Advanced disclosure: retry/backoff/timeout/guard inputs still named `steps[i][...]`; override badge updates; collapse/expand state survives card collapse/expand and clears on sidebar close.
5. More options: appears only for actions with > 6 visible fields; "N set" badge counts non-default values and updates while typing (100 ms debounce); ≤ 6-field actions render flat with no disclosure.
6. Var-pick `{x}`: on resultVar-like fields opens the full dropdown, focus returns to input, ↓/↑/Enter/Escape work, insert-at-cursor and empty-input replacement behave per `_selectOption`; Tab never lands on the button; keystroke autocomplete path unchanged on the same inputs; button absent on select/number/KV fields and on non-matching keys.
7. Entity column select (flowchart with bound entity): pick column → saved config contains the bare slug string; "enter manually…" swaps, ▲ reverts (select reset to ""); reopening a step whose value is not a column shows the manual input pre-filled. Flowchart **without** bound entity: field renders today's exact plain text input.
8. resultVar auto-suggest: new Find Model step arrives with `resultVar: "model"` (schema default), immediately editable; clearing it and collapsing/expanding does not re-fill.
9. Decision: add branch via modal — presets, left-operand select + manual swap, operator, right operand (now with `{x}`), Query Count panel: entity load, WHERE rows (key select incl. `data.<slug>` options + system fields + manual hatch, op, value with `{x}`), count op/value. Saved `condition{}` / `queryConfig{}` JSON byte-identical for select-driven input (see Step 5).
10. QC degraded: block `/entities/:id.json` (devtools) → amber "Schema unavailable" hint appears, Add Filter still works with system-fields select + manual hatch.
11. Loop: while/do-while condition rows (left select, operator incl. unary hiding the right operand, right select + custom input with `{x}`); For-Each `collection` field has `{x}` and still autofills `item`/`index`; For-Each empty-collection save validation still blocks.
12. Read-only (active) flowchart: all new buttons/selects disabled by `_applyReadOnlyState` (it disables every `input, textarea, select, button` in the form — new widgets are covered automatically).

- [ ] **Step 5: Byte-equality QA.** For one representative element of each kind (process with Query Models incl. KV conditions + More-options values; decision with one field-condition branch and one query-count branch with 2 WHERE rows; loop with do-while group condition): on main, open the element, save, and copy `configuration` from the network PUT payload; repeat on this branch making **no edits** (open → save). Diff the JSON:

```bash
diff <(jq -S . /tmp/config_main.json) <(jq -S . /tmp/config_branch.json)
```
Expected: empty diff (key order is normalized by `jq -S`; the stored string itself is regenerated by the same `JSON.stringify` collection paths, which this plan does not alter).

- [ ] **Step 6: Commit (audit notes only if any fixups were needed); otherwise no-op.**

```bash
git status --short
# fixups, if any:
git commit -am "fix(property-editor): round-2 audit fixups

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Design A → Tasks 1/2/3/4 (var-pick on step fields, loop collection, branch modal left-manual/right, condition rows, QC value). Design B → Tasks 1 (builder) + 3 (handlers) + 4 (QC key) + 5 (`entityField`). Design C → Tasks 1 (partition/badge) + 3 (state Map, badge refresh) + 5 (`group`). Design D → Task 3. Design E → Tasks 1 + 3 (dynamic rows) + 5 (placeholders). Design F → covered by the shared row recipes; no tab/shell changes anywhere. Error handling → Task 4 amber hint, Task 2 empty-state row.
- **Hard constraints:** nothing is deleted (the only "replaced" markup keeps all attributes/selectors and adds wrappers); all collectors unchanged except the two explicitly additive read-path branches (`_collectQueryCountCondition` manual key, identical output when unused); annotations are display-only and absent-safe (`?? "Key"`, `field.entityField &&`, `field.group ===`, all guarded); degradation paths reproduce today's exact markup (`autocompleteWrapperAttrs("")` → empty string → legacy branch).
- **Type consistency:** `OUTPUT_VAR_KEYS`/`isVarRefField`/`buildVarPickButton`/`buildEntityColumnSelect`/`buildSetCountBadge` are defined once in Task 1 and imported by name in Tasks 2-4; `disclosureState` keys are `` `${stepId}:more` `` / `` `${stepId}:advanced` `` in both writer (Task 3 Step 7) and reader (Task 3 Step 3).

### Critical Files for Implementation
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/templates.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/context_autocomplete_controller.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/step_manager.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor/branch_manager.js
- /home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor/app/javascript/controllers/property_editor_controller.js
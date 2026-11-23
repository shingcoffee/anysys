# Type-Aware Property Editor (Round 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add advisory type assistance (option-label type suffixes, type chips next to value inputs, amber soft validation, cross-element resultVar collision awareness) to the flowchart property editor, per the binding spec `docs/superpowers/specs/2026-06-12-type-aware-editor-design.md`.

**Architecture:** Strictly additive layer over the existing template-string builders. Shared helpers (`columnTypeOf`, `looksLikeExpression`, `buildTypeChip`, `upsertTypeChip`, `wireSoftTypeValidation`/`applySoftTypeValidation`, `PAIRED_VALUE_FIELDS`) live in `app/javascript/controllers/property_editor/templates.js` and are consumed by `branch_manager.js` and `step_manager.js`. Type data rides on `<option>` `data-*` attributes (`data-col-type` / `data-attr-type`) emitted only when the type is known; validation listeners are attached programmatically at change time so every degradation path produces today's byte-identical markup.

**Tech Stack:** Rails 8 + importmap + Stimulus + Tailwind. No JS test runner — verification is `node --input-type=module --check` syntax sweeps, targeted rspec for the server-rendered touchpoints (none are modified; run as regression), and an explicit manual audit list.

---

## CRITICAL CONSTRAINTS (binding — from round-3 spec)

1. **Advisory only.** Soft validation = amber ring (`ring-2 ring-amber-300 border-amber-400`) + `title` hint. It NEVER blocks save, NEVER prevents collection, NEVER mutates or clears input values.
2. **Expressions always accepted.** `looksLikeExpression` (starts with `ctx`, `{{`, `$`, or contains `[:`) short-circuits validation to valid. Input types stay `type="text"` — never `type="number"`.
3. **Byte-identical serialization.** No change to `collectStepConfig`, `collectSteps`, `_collectFieldCondition`, `_collectQueryCountCondition`, `collectCondition`, `collectBranches`. Option **values** (`bare slug`, `data.<slug>`, `ctx.model.<slug>`) are untouched — only **labels** gain a ` — <html_type>` suffix, and only when `html_type` is non-empty.
4. **Degradation = today's exact markup.** No bound entity / no schema / unknown column / missing `html_type` → no suffix, no `data-*` attribute, no chip, no listener. `data-col-type`/`data-attr-type` attributes are emitted conditionally, never as empty strings.
5. **Chips render only when the column is known** (selected from a schema-backed option carrying a type). Manual entry / `__manual__` / empty selection removes the chip and clears validation.
6. **No operator filtering** (spec "Out of scope"). The operator selects in `_buildConditionRowHTML` (branch_manager.js:744-749), the branch modal (templates.js:926-937), and QC WHERE rows (branch_manager.js:1247-1258) are not touched.
7. **No boolean quick-picks** — no boolean type exists in the current vocabulary (spec B.2).

## Spec-vs-code contradictions — binding resolutions

| # | Contradiction | Binding resolution |
|---|---|---|
| 1 | Spec A example `Amount — number` uses the display name; `buildEntityColumnSelect` (templates.js:552) labels options with the **slug**, QC WHERE rows (branch_manager.js:1203) with `field.name`, left-operand entity options (branch_manager.js:1600) with `ctx.model.<slug>` | Keep each surface's existing base label and append `" — <html_type>"`. Do not switch slug↔name (that would be a behavioral change, not additive). |
| 2 | Spec C says "the **cached** `getAvailableVariables` result" — `context_variable_provider.js` has no public result cache; only implicit keys are module-cached (lines 14-49). `getAvailableVariables` (line 86) recomputes per call but is cheap: reachability + `canvas.getElementPins` are synchronous/local; only the implicit-keys fetch hits the network, once. | Call `await getAvailableVariables(canvas, elementId, -1)` directly at commit time inside `try/catch`; on any failure fall back to today's sibling-only scan. Only `source === "element"` groups feed the collision set (spec C says "upstream output **pin** names" — implicit keys and step groups are excluded; with `stepIndex = -1` no step groups are returned anyway). |
| 3 | Spec B chip "appears next to the value input" — placement unspecified; QC/branch value inputs sit in `position:relative` wrappers that already host the absolutely-positioned `{x}` var-pick button | Chip is appended at the end of the input's wrapper `div` (flows on its own line under the input, never overlaps `{x}`). For paired step-config fields (`findValue` etc.) the chip goes inside the field `<label>` (templates.js:627-629). |
| 4 | Round-3 discovery observed `html_type` ∈ {`text`, `number`}, but `bridge_entity_management.rb:163,171` also emits `number`/`select`, and `html_type_options.rb` defines more | Chips display any non-empty `html_type` verbatim. Soft validation enforces **only** `html_type === "number"` (numeric literal or expression). All other types: chip only, never validated. |
| 5 | Spec B says chip for "`findValue` when `findField` **was chosen** from the column select" — on a reloaded editor the column is technically known but no render-time hook exists in the string-template pipeline | Wiring is change-time only this round: chip appears when the user changes the column select/QC field/left operand. Reloaded editors show today's exact markup until interaction. This satisfies the degradation constraint; flagged as accepted scope. |

## Verified grounding (line numbers, current worktree)

- `templates.js` — `buildEntityColumnSelect` 550-589 (option construction 560-562; `columns` array 551-554; `valueInColumns` 557); badge recipes `buildOverrideBadge` 135-138 and `buildSetCountBadge` 192-195 (styling reference for the chip); `OUTPUT_VAR_KEYS` 156; `escapeHtml` imported line 7.
- `branch_manager.js` — `_addQueryCountWhereRow` 1196-1273 (field options 1200-1210 from `this._selectedEntitySchema`, set at 172 from `entity.property_schema`; value input 1260-1267); `handleQcWhereFieldChange` 200-202; `handleBranchLeftOperandChange` 524-536; `handleConditionLeftOperandChange` 1356-1358 (currently a no-op); `_buildConditionRowHTML` 693-778 (right-operand custom input 760-767); `_buildContextAwareLeftOperandOptions` 1580-1614 (entity-attribute loop 1595-1603); modal `onOpen` reset 39-94; imports line 10.
- `step_manager.js` — `handleEntityColumnSelectChange` 931-944; `swapEntityColumnToManual` 946-961; `swapEntityColumnToSelect` 963-978; `stepPickerCommit` 733-768 (the await point — `_applyResultVarAutoSuggest` called at 754); `_applyResultVarAutoSuggest` 820-840; `_collectSiblingOutputVars` 849-866; imports 6-16. Canvas reference: `this.controller.canvas` (e.g. 469).
- `context_variable_provider.js` — `export async function getAvailableVariables(canvas, elementId, stepIndex = -1)` at line 86; returns `{groups: [{label, source, sourceId, variables}]}`; element-output groups have `source: "element"` (line 115); internal fetch failures are caught (lines 41-44) so the function itself resolves — the `try/catch` in step_manager is defense-in-depth.
- Paired column→value fields (verified in action configs): `findField → findValue` (`model_actions.js:51,61`, both gated by the same `visibleWhen` on `findStrategy`); `filterField → filterValue` (`data_actions.js` ~1813/1835, ~2394/2416, ~2642/2663, ~2690/2711); `matchField → matchValue` (`data_actions.js` ~2588/2594, same `visibleWhen` on `predicateType`). NOT paired (no value column): `sortField`, `groupField`, `groupBy`, `distinctField`, `aggregateField`.
- `canvas.entityAttributes` shape: `[{name, name_slug, type, html_type, ...}]` (set in `flowchart_canvas_controller.js:108`; `html_type` confirmed in `Entity#property_schema`, `app/models/concerns/bridge_entity_management.rb:158-171`). `_selectedEntitySchema` is the same shape (`entity.property_schema`, branch_manager.js:172).
- Importmap: `config/importmap.rb` pins the `flowchart` directory, so `import ... from "flowchart/context_variable_provider"` resolves (already used by `context_autocomplete_controller.js:4`).
- Handler routing: `property_editor_controller.js` delegates `handleEntityColumnSelectChange` (484), `handleQcWhereFieldChange` (500), `stepPickerCommit` (540), `handleBranchLeftOperandChange` (585), `handleConditionLeftOperandChange` (640). **No controller changes needed** — `stepPickerCommit` becoming async is transparent to the delegating wrapper.

**Task dependency:** Task 1 first (exports consumed by 2 and 3). **Tasks 2 and 3 are parallel-safe** (disjoint files: `branch_manager.js` vs `step_manager.js`). Task 4 last.

---

### Task 1: Shared type helpers + type suffix in `buildEntityColumnSelect` (templates.js)

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (insert helpers after `buildSetCountBadge`, ~line 195; modify `buildEntityColumnSelect`, lines 550-562)

- [ ] **Step 1: Add the shared helpers block after `buildSetCountBadge` (after line 195), before `const UNARY_OPERATORS` (line 197)**

```javascript
// ===================
// Round-3 type-awareness helpers (advisory only — never block, never mutate)
// ===================

/**
 * entityField config keys whose selected column types advise a paired value
 * input. Verified against the action registry: find_model (model_actions.js),
 * filter/find/partition collection actions and match_field predicates
 * (data_actions.js). Keys NOT listed (sortField, groupBy, distinctField,
 * aggregateField, groupField) have no paired value input.
 */
export const PAIRED_VALUE_FIELDS = {
  findField: "findValue",
  filterField: "filterValue",
  matchField: "matchValue"
}

const SOFT_TYPE_HINT_CLASSES = ["ring-2", "ring-amber-300", "border-amber-400"]
const SOFT_TYPE_HINT_TITLE = "Expected a number or a ctx expression"
const NUMBER_LITERAL_PATTERN = /^-?\d+(\.\d+)?$/

/**
 * Look up a column's type info in an entity schema (canvas.entityAttributes
 * or an entity's property_schema — both carry name/name_slug/type/html_type).
 * @returns {{type: string, htmlType: string}|null} null when unknown — caller
 *   must degrade to today's exact behavior (no chip, no validation).
 */
export function columnTypeOf(schema, slug) {
  if (!slug) return null
  const attr = (schema || []).find(a => a && (a.name_slug || a.name) === slug)
  if (!attr) return null
  return { type: attr.type || "", htmlType: attr.html_type || "" }
}

/**
 * True when a value is a context expression — expressions are ALWAYS valid
 * (round-3 hard constraint: type assistance must never block expressions).
 */
export function looksLikeExpression(value) {
  const v = String(value ?? "").trim()
  return v.startsWith("ctx") || v.startsWith("{{") || v.startsWith("$") || v.includes("[:")
}

/**
 * Small advisory type chip (e.g. "number"). Returns "" when htmlType is
 * empty so degraded paths emit no markup at all.
 */
export function buildTypeChip(htmlType) {
  if (!htmlType) return ""
  return `<span data-type-chip class="ml-1 inline-flex items-center px-1 py-px text-[9px] font-medium text-slate-500 bg-slate-100 border border-slate-200 rounded align-middle">${escapeHtml(htmlType)}</span>`
}

/**
 * Insert/update/remove the type chip inside a container element.
 * Empty htmlType removes the chip (degradation → today's markup).
 */
export function upsertTypeChip(container, htmlType) {
  if (!container) return
  const existing = container.querySelector("[data-type-chip]")
  if (!htmlType) { existing?.remove(); return }
  if (existing) { existing.textContent = htmlType; return }
  container.insertAdjacentHTML("beforeend", buildTypeChip(htmlType))
}

/**
 * Soft validation: amber ring + title hint, applied only when the expected
 * html_type is "number" and the value is neither empty, a numeric literal,
 * nor an expression. NEVER blocks save, NEVER clears the value. Other
 * html_types (text/select/…) are never validated — chip only.
 */
export function applySoftTypeValidation(input, htmlType) {
  if (!input) return
  const value = String(input.value ?? "").trim()
  const needsHint =
    htmlType === "number" &&
    value !== "" &&
    !NUMBER_LITERAL_PATTERN.test(value) &&
    !looksLikeExpression(value)

  SOFT_TYPE_HINT_CLASSES.forEach(cls => input.classList.toggle(cls, needsHint))
  if (needsHint) {
    input.title = SOFT_TYPE_HINT_TITLE
  } else if (input.title === SOFT_TYPE_HINT_TITLE) {
    input.title = ""
  }
}

/**
 * Attach (idempotently) a change-time soft validator to a value input and
 * apply it immediately. Empty htmlType clears the expectation and any
 * existing hint. Listener attaches at most once per input (dataset guard);
 * markup is never modified, so degraded paths stay byte-identical.
 */
export function wireSoftTypeValidation(input, htmlType) {
  if (!input) return
  if (htmlType) {
    input.dataset.expectedType = htmlType
  } else {
    delete input.dataset.expectedType
  }
  if (!input.dataset.softTypeWired) {
    input.dataset.softTypeWired = "1"
    input.addEventListener("change", () => {
      applySoftTypeValidation(input, input.dataset.expectedType || "")
    })
  }
  applySoftTypeValidation(input, htmlType)
}
```

- [ ] **Step 2: Add type suffixes to `buildEntityColumnSelect` option labels (value untouched)**

Before (templates.js:551-562):

```javascript
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
```

After:

```javascript
  const columns = (entityAttributes || [])
    .map(attr => ({
      slug: attr.name_slug || attr.name || String(attr),
      htmlType: attr.html_type || ""
    }))
    .filter(c => Boolean(c.slug))
  if (columns.length === 0) return null

  const strValue = String(value ?? "")
  const valueInColumns = strValue === "" || columns.some(c => c.slug === strValue)
  const { elementId, stepIndex } = context

  // Type suffix is label-only and conditional: option VALUE stays the bare
  // slug, and unknown-type columns render today's exact <option> markup.
  const optionsHTML =
    `<option value="">Select column&hellip;</option>` +
    columns.map(c => {
      const label = c.htmlType ? `${c.slug} — ${c.htmlType}` : c.slug
      return `<option value="${escapeHtml(c.slug)}"${c.slug === strValue ? " selected" : ""}${c.htmlType ? ` data-col-type="${escapeHtml(c.htmlType)}"` : ""}>${escapeHtml(label)}</option>`
    }).join("")
```

- [ ] **Step 3: Syntax-check**

Run: `node --input-type=module --check < app/javascript/controllers/property_editor/templates.js`
Expected: no output, exit 0.

- [ ] **Step 4: Byte-equality audit of the change**

Run: `git diff app/javascript/controllers/property_editor/templates.js | grep '^[-+].*value='`
Expected: every changed `value="..."` attribute is `value="${escapeHtml(c.slug)}"` vs the old `value="${escapeHtml(c)}"` — same emitted bytes (bare slug). The hidden `data-config-input` line (templates.js:586) must be untouched.

- [ ] **Step 5: Regression rspec (templates mirror ViewComponents)**

Run: `bundle exec rspec spec/components/property_editor/`
Expected: all green (no Ruby touched; this guards against accidental edits).

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat(property-editor): shared type helpers + column type suffixes in entity column select

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Branch modal + condition rows — QC WHERE types, left-operand attr types, value chips/soft validation (branch_manager.js) — parallel-safe with Task 3

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js` (imports line 10; `openBranchModal` onOpen 49-52; `handleQcWhereFieldChange` 200-202; `handleBranchLeftOperandChange` 524-536; `handleConditionLeftOperandChange` 1356-1358; `_addQueryCountWhereRow` 1200-1210; `_buildContextAwareLeftOperandOptions` 1595-1603)

- [ ] **Step 1: Extend the templates import (line 10)**

Before:

```javascript
import { buildBranchModalTemplate, buildBranchItemTemplate, buildSectionHeader, buildEmptyState, buildVarPickButton } from "controllers/property_editor/templates"
```

After:

```javascript
import { buildBranchModalTemplate, buildBranchItemTemplate, buildSectionHeader, buildEmptyState, buildVarPickButton, upsertTypeChip, wireSoftTypeValidation } from "controllers/property_editor/templates"
```

- [ ] **Step 2: QC WHERE field options carry type suffix + `data-col-type`**

Before (branch_manager.js:1200-1204):

```javascript
    let fieldOptionsHTML = `<option value="">Select field...</option>`
    schema.forEach(field => {
      const slug = field.name_slug || field.name
      fieldOptionsHTML += `<option value="data.${escapeHtml(slug)}">${escapeHtml(field.name || slug)}</option>`
    })
```

After:

```javascript
    let fieldOptionsHTML = `<option value="">Select field...</option>`
    schema.forEach(field => {
      const slug = field.name_slug || field.name
      const htmlType = field.html_type || ""
      // Label-only type suffix; option VALUE stays "data.<slug>" so collected
      // query_count conditions are byte-identical. data-col-type is emitted
      // only when the type is known (degraded markup unchanged).
      const baseLabel = field.name || slug
      const label = htmlType ? `${baseLabel} — ${htmlType}` : baseLabel
      fieldOptionsHTML += `<option value="data.${escapeHtml(slug)}"${htmlType ? ` data-col-type="${escapeHtml(htmlType)}"` : ""}>${escapeHtml(label)}</option>`
    })
```

(The system-field options `created_at`/`updated_at` at 1206-1207 and the `__manual__` escape hatch at 1210 are untouched.)

- [ ] **Step 3: QC WHERE field change stores `data-qc-col-type` on the row and wires the value input**

Before (branch_manager.js:199-202):

```javascript
  /** WHERE key select changed: only "__manual__" needs handling. */
  handleQcWhereFieldChange(event) {
    if (event.target.value === "__manual__") this.swapQcWhereFieldToManual(event)
  }
```

After:

```javascript
  /**
   * WHERE key select changed: "__manual__" swaps to the text input; any other
   * value updates the row's advisory type assist (chip + soft validation on
   * the value input). Unknown columns clear both — today's exact behavior.
   */
  handleQcWhereFieldChange(event) {
    if (event.target.value === "__manual__") { this.swapQcWhereFieldToManual(event); return }

    const row = event.target.closest("[data-qc-where-row]")
    if (!row) return
    const colType = event.target.selectedOptions?.[0]?.dataset?.colType || ""
    if (colType) {
      row.dataset.qcColType = colType
    } else {
      delete row.dataset.qcColType
    }
    const valueInput = row.querySelector("[data-qc-where-value]")
    if (!valueInput) return
    upsertTypeChip(valueInput.parentElement, colType)
    wireSoftTypeValidation(valueInput, colType)
  }
```

Also clear the assist when the user swaps the field to manual — in `swapQcWhereFieldToManual` (lines 204-216), after the existing `if (manual) {...}` block and before the closing brace, add:

```javascript
    // Manual column ⇒ type unknown ⇒ drop chip + validation (degrade cleanly).
    delete row.dataset.qcColType
    const valueInput = row.querySelector("[data-qc-where-value]")
    if (valueInput) {
      upsertTypeChip(valueInput.parentElement, "")
      wireSoftTypeValidation(valueInput, "")
    }
```

- [ ] **Step 4: Left-operand entity-attribute options carry type suffix + `data-attr-type`**

`_buildContextAwareLeftOperandOptions` is shared by the branch-modal select (`_populateLeftOperandSelect`, line 571) and the condition rows (`_buildConditionRowHTML`, line 701), so one edit covers both surfaces.

Before (branch_manager.js:1595-1603):

```javascript
    if (entityAttributes.length > 0) {
      html += `<optgroup label="Entity Fields">`
      entityAttributes.forEach(attr => {
        const slug = attr.name_slug || attr.name || attr
        const value = `ctx.model.${slug}`
        html += this._optionTag(value, value, selectedValue)
      })
      html += `</optgroup>`
    }
```

After:

```javascript
    if (entityAttributes.length > 0) {
      html += `<optgroup label="Entity Fields">`
      entityAttributes.forEach(attr => {
        const slug = attr.name_slug || attr.name || attr
        const value = `ctx.model.${slug}`
        const htmlType = attr.html_type || ""
        // Type suffix is label-only; option VALUE stays "ctx.model.<slug>".
        // data-attr-type emitted only when known (degraded markup unchanged).
        const selected = value === selectedValue ? " selected" : ""
        const label = htmlType ? `${value} — ${htmlType}` : value
        html += `<option value="${escapeHtml(value)}"${selected}${htmlType ? ` data-attr-type="${escapeHtml(htmlType)}"` : ""}>${escapeHtml(label)}</option>`
      })
      html += `</optgroup>`
    }
```

(`_buildContextAwareRightOperandOptions` at 1628-1663 deliberately stays untouched — its values are inserted *as* expressions.)

- [ ] **Step 5: Branch-modal left-operand change updates the right operand's chip/validation**

Before (branch_manager.js:524-536):

```javascript
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
```

After:

```javascript
  handleBranchLeftOperandChange(event) {
    const modal = event.target.closest("[data-branch-modal]")
    if (!modal) return
    if (event.target.value === "__manual__") {
      this.swapLeftOperandToManual(event)
      return
    }
    // Advisory type assist: entity-attribute options carry data-attr-type;
    // anything else (signal/ctx/parent outputs/empty) clears chip + hint.
    // Operator list is NOT filtered (round-3 additive constraint).
    const attrType = event.target.selectedOptions?.[0]?.dataset?.attrType || ""
    const rightInput = modal.querySelector("[data-branch-condition-right]")
    if (rightInput) {
      upsertTypeChip(rightInput.parentElement, attrType)
      wireSoftTypeValidation(rightInput, attrType)
    }
    const opSelect = modal.querySelector("[data-branch-condition-op]")
    if (opSelect && event.target.value) {
      if (!opSelect.value) opSelect.value = "=="
      opSelect.focus()
    }
  }
```

- [ ] **Step 6: Condition-row left-operand change wires the right-operand custom input**

Before (branch_manager.js:1356-1358):

```javascript
  handleConditionLeftOperandChange(event) {
    // No preview to update - values are collected on save
  }
```

After:

```javascript
  handleConditionLeftOperandChange(event) {
    // Advisory type assist only (no preview; values still collected on save).
    // Entity-attribute options carry data-attr-type; the chip/hint attach to
    // the row's free-text custom input. The right-operand SELECT is untouched
    // (its options are expressions and always valid).
    const row = event.target.closest("[data-condition-row]")
    if (!row) return
    const attrType = event.target.selectedOptions?.[0]?.dataset?.attrType || ""
    const customInput = row.querySelector("[data-condition-right-operand-custom]")
    if (!customInput) return
    upsertTypeChip(customInput.parentElement, attrType)
    wireSoftTypeValidation(customInput, attrType)
  }
```

- [ ] **Step 7: Modal reopen cleanup — drop stale chips/hints**

In `openBranchModal`'s `onOpen` (after `if (condOp) condOp.value = "=="`, line 52), add:

```javascript
          // Round-3 type assist: a reopened modal starts with no column
          // selected — remove stale chips and clear any amber hint so the
          // reset state matches today's exact markup.
          modal.querySelectorAll("[data-type-chip]").forEach(chip => chip.remove())
          if (condRight) wireSoftTypeValidation(condRight, "")
```

- [ ] **Step 8: Syntax-check**

Run: `node --input-type=module --check < app/javascript/controllers/property_editor/branch_manager.js`
Expected: exit 0.

- [ ] **Step 9: Serialization byte-equality audit**

Run: `git diff app/javascript/controllers/property_editor/branch_manager.js | grep -E '^[-+].*(value="data\.|value="\$\{escapeHtml\(value\)\}|_collect|collectCondition|collectBranches)'`
Expected: option `value=` constructions byte-identical; zero hits on any `_collect*`/`collect*` function (they are not modified).

- [ ] **Step 10: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git commit -m "feat(property-editor): advisory column types in QC WHERE rows and condition left operands

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Paired findField→findValue assist + cross-element resultVar collisions (step_manager.js) — parallel-safe with Task 2

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js` (imports 6-16; `stepPickerCommit` 733-768; `_applyResultVarAutoSuggest` 820-840; `handleEntityColumnSelectChange` 931-944; `swapEntityColumnToManual` 946-961; `swapEntityColumnToSelect` 963-978)

- [ ] **Step 1: Extend imports**

Before (step_manager.js:6-16):

```javascript
import { escapeHtml, generateStepId } from "utils"
import {
  buildStepPickerTemplate,
  buildStepItemTemplate,
  buildSectionHeader,
  buildStepConfigFieldsHTML,
  OUTPUT_VAR_KEYS
} from "controllers/property_editor/templates"
```

After:

```javascript
import { escapeHtml, generateStepId } from "utils"
import {
  buildStepPickerTemplate,
  buildStepItemTemplate,
  buildSectionHeader,
  buildStepConfigFieldsHTML,
  OUTPUT_VAR_KEYS,
  PAIRED_VALUE_FIELDS,
  columnTypeOf,
  upsertTypeChip,
  wireSoftTypeValidation
} from "controllers/property_editor/templates"
import { getAvailableVariables } from "flowchart/context_variable_provider"
```

(`flowchart/context_variable_provider` resolves via the importmap `flowchart` pin — already imported by `context_autocomplete_controller.js:4`.)

- [ ] **Step 2: Wire the paired value field in `handleEntityColumnSelectChange` and add the helper**

Before (step_manager.js:931-944):

```javascript
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
```

After:

```javascript
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
    this._updatePairedValueTypeAssist(wrapper, select.value)
    this.handleConfigFieldChange(event)
  }

  /**
   * Round-3 advisory assist: when an entityField column select changes and
   * the field has a paired value field (PAIRED_VALUE_FIELDS, e.g.
   * findField→findValue), show a type chip in the paired field's label and
   * soft-validate its input against the column's html_type. Unknown column /
   * cleared selection / manual entry removes both (today's exact behavior).
   * Never blocks save, never mutates the paired value.
   */
  _updatePairedValueTypeAssist(wrapper, columnSlug) {
    const fieldKey = wrapper.querySelector("input[type='hidden'][data-config-input]")?.dataset?.configInput
    const pairedKey = PAIRED_VALUE_FIELDS[fieldKey]
    if (!pairedKey) return

    const stepItem = wrapper.closest("[data-step-item]")
    const pairedField = stepItem?.querySelector(`[data-config-field="${pairedKey}"]`)
    if (!pairedField) return
    const pairedInput = pairedField.querySelector("[data-config-input]")
    if (!pairedInput) return

    const colInfo = columnTypeOf(this.controller.canvas?.entityAttributes, columnSlug)
    const htmlType = colInfo?.htmlType || ""

    const label = pairedField.querySelector("label")
    if (label) upsertTypeChip(label, htmlType)
    wireSoftTypeValidation(pairedInput, htmlType)
  }
```

- [ ] **Step 3: Clear the assist when the column becomes unknown (both swap paths)**

In `swapEntityColumnToManual` (946-961), insert before `this.handleConfigFieldChange(event)`:

```javascript
    this._updatePairedValueTypeAssist(wrapper, "")
```

In `swapEntityColumnToSelect` (963-978), insert before `this.handleConfigFieldChange(event)`:

```javascript
    this._updatePairedValueTypeAssist(wrapper, "")
```

- [ ] **Step 4: Cross-element collision awareness for output-variable auto-suggest**

Before (step_manager.js:752-755, inside `stepPickerCommit`):

```javascript
      schema.forEach(field => {
        if (field.default !== undefined) defaultConfig[field.key] = field.default
      })
      this._applyResultVarAutoSuggest(schema, defaultConfig, leaf.action)
```

After (make `stepPickerCommit` async and await):

```javascript
      schema.forEach(field => {
        if (field.default !== undefined) defaultConfig[field.key] = field.default
      })
      await this._applyResultVarAutoSuggest(schema, defaultConfig, leaf.action)
```

and change the method signature at line 733 from `stepPickerCommit(event) {` to `async stepPickerCommit(event) {`. (The delegating wrapper at `property_editor_controller.js:540` needs no change — the promise is fire-and-forget from Stimulus.)

Before (step_manager.js:820-840):

```javascript
  _applyResultVarAutoSuggest(schema, defaultConfig, actionKey) {
    const usedVars = this._collectSiblingOutputVars()
    schema.forEach(field => {
```

After:

```javascript
  async _applyResultVarAutoSuggest(schema, defaultConfig, actionKey) {
    const usedVars = this._collectSiblingOutputVars()

    // Round-3: extend the collision set with upstream output pin names.
    // Awaited at commit time only; getAvailableVariables caches implicit
    // keys module-wide and computes element pins locally. On ANY failure
    // fall back to today's sibling-only scan (advisory feature — a missed
    // collision must never break step commit).
    if (schema.some(field => OUTPUT_VAR_KEYS.includes(field.key))) {
      try {
        const canvas = this.controller.canvas
        const elementId = this.controller.currentElement?.id
        if (canvas && elementId) {
          const { groups } = await getAvailableVariables(canvas, elementId, -1)
          groups.forEach(group => {
            if (group.source !== "element") return
            group.variables.forEach(v => {
              if (typeof v === "string" && v.trim() !== "" && !usedVars.includes(v)) usedVars.push(v)
            })
          })
        }
      } catch { /* sibling-only fallback — today's behavior */ }
    }

    schema.forEach(field => {
```

(The suffixing loop body at 822-839 — `_2.._9` candidates, `usedVars.push(candidate)` — is unchanged. `_collectSiblingOutputVars` at 849-866 is unchanged.)

- [ ] **Step 5: Syntax-check**

Run: `node --input-type=module --check < app/javascript/controllers/property_editor/step_manager.js`
Expected: exit 0.

- [ ] **Step 6: Serialization byte-equality audit**

Run: `git diff app/javascript/controllers/property_editor/step_manager.js | grep -E '^[-+].*(collectStepConfig|collectSteps|data-step-config)'`
Expected: zero hits — collection paths untouched. Also confirm `git diff` shows no change inside the suffix `while` loop.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/property_editor/step_manager.js
git commit -m "feat(property-editor): paired findField->findValue type assist and cross-element resultVar collisions

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Verification sweep, no-removal audit, targeted rspec

**Files:** none modified (verification only).

- [ ] **Step 1: Full syntax sweep over touched modules + their importers**

```bash
for f in app/javascript/controllers/property_editor/templates.js \
         app/javascript/controllers/property_editor/branch_manager.js \
         app/javascript/controllers/property_editor/step_manager.js \
         app/javascript/flowchart/context_variable_provider.js \
         app/javascript/controllers/property_editor_controller.js; do
  echo "== $f"; node --input-type=module --check < "$f" || exit 1
done
```
Expected: all exit 0.

- [ ] **Step 2: Targeted rspec**

Run: `bundle exec rspec spec/components/property_editor/ spec/requests/maintenance/flowcharts_editor_spec.rb`
Expected: all green (no server-rendered touchpoints were modified — this is the regression gate the spec's Testing section requires).

- [ ] **Step 3: Byte-equality greps (serialized shapes and option values)**

```bash
# Option values unchanged on all three surfaces:
grep -n 'value="data\.\${escapeHtml(slug)}"' app/javascript/controllers/property_editor/branch_manager.js
grep -n 'value="\${escapeHtml(value)}"' app/javascript/controllers/property_editor/branch_manager.js
grep -n 'value="\${escapeHtml(c.slug)}"' app/javascript/controllers/property_editor/templates.js
# Collection functions untouched across the whole round:
git diff main...HEAD -- app/javascript/controllers/property_editor/branch_manager.js | grep -cE '^[-+] *(_collectFieldCondition|_collectQueryCountCondition|collectCondition|collectBranches)\(' ; # expect 0
git diff main...HEAD -- app/javascript/controllers/property_editor/step_manager.js | grep -cE '^[-+] *(collectStepConfig|collectSteps)\(' ; # expect 0
```

- [ ] **Step 4: No-removal manual audit (expressions accepted everywhere) — run in the editor**

1. **QC WHERE value**: pick an entity, pick a `number` column → chip `number` appears; type `ctx[:count]` → no amber ring; type `abc` → amber ring + title "Expected a number or a ctx expression"; **Add Branch still succeeds** and the saved `condition.queryConfig.conditions.rules[0]` is `{field: "data.<slug>", op, value: "abc"}` — value preserved verbatim.
2. **QC WHERE degraded**: entity schema fetch fails (existing amber "Schema unavailable" hint) → field options are system fields + manual only, no suffixes, no chip, value input markup identical to today.
3. **Branch modal field condition**: left operand `ctx.model.<number-col>` → chip on right operand; `is_empty` operator still collects no right operand; left operand `signal`/`ctx` → chip removed, no validation; `__manual__` left operand → no chip.
4. **Condition rows (loop/decision condition builder)**: select an entity-attribute left operand → chip/validation on the custom right input only after "Custom value…"; switching back to the select clears nothing it shouldn't; collected condition shape unchanged (`{leftOperand, operator, rightOperand, expression}`).
5. **findField → findValue**: choose `find_by` strategy, pick a number column in Find Field → `number` chip in the Find Value label; type `ctx[:email]` → valid; type `abc` → amber hint only; save → step `config.findValue === "abc"` (never blocked/mutated). Switch Find Field to "enter manually…" → chip and hint disappear.
6. **resultVar collisions**: place two connected elements where the upstream emits output pin `model`; commit a `*_model` action downstream → suggested `model_2`. Disconnect network (devtools offline) and repeat → suggestion falls back to sibling-only (`model`), commit still works.
7. **No bound entity**: flowchart without an entity → every surface renders today's exact markup (no suffixes, no `data-col-type`/`data-attr-type`, no chips).
8. **Reopen branch modal** after a typed session → no stale chip, no amber ring.

- [ ] **Step 5: Final commit (only if audit fixes were needed; otherwise no-op)**

```bash
git status --short   # expect clean
```

---

## Self-review

- **Spec coverage:** A (badges on column options) → Task 1 Step 2 (entityField selects), Task 2 Steps 2 and 4 (QC WHERE, left operands). B (chips + soft validation, expressions never blocked, no input-type changes) → Task 1 Step 1 helpers, Task 2 Steps 3/5/6, Task 3 Step 2; B.2 boolean quick-picks explicitly skipped. C (cross-element resultVar) → Task 3 Step 4 with try/catch sibling-only fallback. D (wiring: `data-qc-col-type` on field change, `data-attr-type` on left-operand options, paired value fields) → Task 2 Steps 3/4, Task 3 Steps 2/3. Out-of-scope items (operator filtering, pin typing, date/select widgets, serialization changes) have no tasks — correct.
- **Placeholder scan:** all steps carry full code; no TBDs.
- **Type consistency:** `upsertTypeChip(container, htmlType)`, `wireSoftTypeValidation(input, htmlType)`, `columnTypeOf(schema, slug) → {type, htmlType}|null`, `PAIRED_VALUE_FIELDS` used with identical signatures in Tasks 2 and 3; `applySoftTypeValidation` is exported and invoked only through `wireSoftTypeValidation` (kept exported per spec line 28).

# Decision Branch Edit-In-Place Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Edit affordance to each decision-branch card that reopens the existing branch modal pre-filled and, on submit, updates the branch's hidden inputs, card, and the existing canvas connection in place — no element creation, no repositioning, no branchKey/elementId churn.

**Architecture:** All changes live in the round-1/2/3 property-editor layer: `templates.js` gains the Edit button (same hover-reveal trailing pattern as Remove, `buildBranchItemTemplate`) and a title hook on the branch modal; `BranchManager` gains an edit-mode state (`_editingBranchItem`), an `editBranch` open/prefill path, and a `saveBranchEdits` submit path that mirrors `addBranchFromModal`'s canvas mutation order minus creation/repositioning; `property_editor_controller.js` gains two delegations and a `branchUpdated` auto-sync listener. `addBranchFromModal`, `collectBranches`, and every condition collection shape are untouched.

**Tech Stack:** Rails 8 importmap + Stimulus + Tailwind. No JS test runner — verification via `node --input-type=module --check`, targeted rspec, and a manual QA list.

**Worktree:** `/home/ec2-user/anysys/.worktrees/refactor-anysys-property-editor` (all paths below relative to it).

---

## Spec-vs-code contradictions — binding resolutions

The requirements list and the shipped code disagree (or are silent) in nine places. These resolutions are **binding** for all tasks:

1. **How the connection update is performed.** Ground truth is `addBranchFromModal` (`app/javascript/controllers/property_editor/branch_manager.js:342-350`): it locates the connection with `canvas.connections.find(c => c.from === decisionId && c.to === branchElementId)` and assigns `conn.condition = condition` — **only when condition is truthy**, so a condition-less branch has **no `condition` key at all** on its connection. Saved flowchart JSON spreads the live connection object (`app/javascript/flowchart/canvas.js:1912-1915`), so absent-key is the canonical "no condition" shape (the undo manager normalizes absent and null identically at snapshot time — `app/javascript/controllers/flowchart_canvas/undo_redo_manager.js:62`). **Resolution:** edit-save uses the identical `find`, then `conn.condition = condition` when truthy and `delete conn.condition` when the user cleared the condition.
2. **Connection label.** The add flow stamps the connection label with the branch name (`branch_manager.js:322` → `:949` `createConnection(..., { label: connectionLabel })`), and `updateConnections` re-renders it (`app/javascript/flowchart/connection_manager.js:97,134-136`). Leaving it stale after a rename is a visible canvas inconsistency; blindly overwriting could clobber a label the user customized via the connection editor (`property_editor_controller.js:1153-1159`). **Resolution:** update `conn.label = newName` **only if `conn.label` still equals the old branch name**.
3. **Branch Process element's own canvas label** (`element.label`, set at creation from the branch name): **not touched**. The user may have renamed/configured that element independently.
4. **Which canvas refreshes.** Decision port labels derive from `element.properties.branches[i].name` (`app/javascript/flowchart/dynamic_ports.js:22,39-48`), so a rename **requires** `element.properties.branches = this.collectBranches()` followed by `_refreshDecisionElement` (`branch_manager.js:1090-1098`), then `canvas._hideConnectionHandles()` + `canvas.updateConnections()` (re-renders connection labels), then `canvas.onchange?.()` — the same tail as add (`branch_manager.js:356-363`). **Not called:** `_repositionAllBranchElements` (`:1017-1040`), `_remapBranchConnections` (`:986-1011`), and `_updateBranchSectionCount` (`:626-632`) — branch count and order are unchanged. `branchKey` is regenerated positionally by `collectBranches` (`:439`), so it cannot change when order doesn't.
5. **Submit routing without touching the add flow.** A mode guard inside `addBranchFromModal` would modify it. **Resolution:** `addBranchFromModal` stays untouched. Edit mode rewrites the submit button's `data-action` attribute to `click->property-editor#saveBranchEdits` (Stimulus observes attribute mutations and rebinds); the add-mode reset restores the original string verbatim. `saveBranchEdits` defensively falls back to `addBranchFromModal` if no edit target survives.
6. **Refactoring inside `openBranchModal`/`switchBranchConditionType`.** The 60-line onOpen reset (`branch_manager.js:39-99`) and the toggle body (`:115-147`) are extracted into `_resetBranchModal` / `_applyConditionTypeToggle` with **statement-identical bodies** so add and edit share them. The rounds' "byte-identical" constraint binds serialized contracts and behavior, not source layout.
7. **Modal text.** Add-mode title is "Add Decision Branch" (`templates.js:966`), submit "Add Branch" (`:1152`). Edit mode: title **"Edit Branch"**, submit **"Save Changes"**. Add-mode strings restored exactly on reset.
8. **Preset chips in edit mode: kept usable.** They only pre-fill (`_applyPresetValues`, `branch_manager.js:504-547`), never commit — consistent with add mode, and `_resetBranchModal` deactivates them on every open.
9. **Auto-sync event.** Add/remove dispatch `branchAdded`/`branchRemoved`, wired to `_boundSyncChanges` (`property_editor_controller.js:1060-1061`). Edit dispatches a new **`branchUpdated`** event, registered additively in `_setupFormChangeListeners`/`_removeFormChangeListeners` — same unsaved-changes/cache semantics as add.

Also noted: Escape closes the whole sidebar, not the modal (`property_editor_controller.js:1197-1201`), and the modal never mutates the branch before save — requirement 3 is satisfied by clearing `_editingBranchItem` in `closeBranchModal`, in `_resetBranchModal` (every open), and by `renderBranchModal` re-rendering add-mode markup whenever an element is reopened. `_highlightFieldError` resolves to the ModalMixin copy (Object.assign at `branch_manager.js:1767` overwrites the class method at `:634-642`) — red ring + focus, exactly what add-mode name validation does today.

---

### Task 1: BranchManager edit mode — reset extraction, open/prefill, save

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
  - constructor (`:18-23`), `openBranchModal` (`:29-102`), `closeBranchModal` (`:104-113`), `switchBranchConditionType` (`:115-147`)
  - new methods inserted after `removeBranch` (`:373-417`)

- [ ] **Step 1: Add edit-mode state to the constructor** (`branch_manager.js:19-23`)

```js
  constructor(controller) {
    super(controller, 'branchIndex')
    this._availableOutputOptions = []
    this._entityFetchId = 0
    // Branch card currently being edited via the modal (null = add mode).
    this._editingBranchItem = null
  }
```

- [ ] **Step 2: Extract the onOpen reset into `_resetBranchModal` and slim `openBranchModal`**

Replace `openBranchModal` (`:29-102`) with:

```js
  openBranchModal(event) {
    event.preventDefault()
    if (!this.controller.hasBranchModalContainerTarget) return

    // Use mixin method to open modal with onOpen callback
    this._openModal(
      this.controller.branchModalContainerTarget,
      "[data-branch-modal]",
      {
        focusSelector: "[data-branch-name]",
        onOpen: (modal) => this._resetBranchModal(modal)
      }
    )
  }

  /**
   * Reset the branch modal to its add-mode defaults. Extracted verbatim from
   * the former openBranchModal onOpen callback so the edit flow can reuse it;
   * additionally clears edit mode and restores add-mode title/submit wiring.
   */
  _resetBranchModal(modal) {
    this._editingBranchItem = null
    this._setModalMode(modal, "add")

    // Reset form fields to defaults
    this._resetModalFields(modal, {
      inputs: ["[data-branch-name]"],
      textareas: "[data-branch-modal-description]"
    })

    // Reset condition fields (select + manual swap + op + right)
    this._populateLeftOperandSelect(modal)
    this._resetLeftOperandSwap(modal)
    const condRight = modal.querySelector("[data-branch-condition-right]")
    const condOp    = modal.querySelector("[data-branch-condition-op]")
    if (condRight) condRight.value = ""
    if (condOp)    condOp.value    = "=="
    // Round-3 type assist: a reopened modal starts with no column
    // selected — remove stale chips and clear any amber hint so the
    // reset state matches today's exact markup.
    modal.querySelectorAll("[data-type-chip]").forEach(chip => chip.remove())
    if (condRight) wireSoftTypeValidation(condRight, "")

    // Reset preset chips
    modal.querySelectorAll("[data-branch-preset-row] button[data-preset]")
      .forEach(b => this._setChipActive(b, false))

    // Reset condition type toggle to "Field Condition" + panels
    this._applyConditionTypeToggle(modal, "field")

    // Reset query count fields
    const qcEntity = modal.querySelector("[data-branch-qc-entity]")
    if (qcEntity) qcEntity.value = ""
    const qcWhereRows = modal.querySelector("[data-branch-qc-where-rows]")
    if (qcWhereRows) qcWhereRows.innerHTML = ""
    const qcCountOp = modal.querySelector("[data-branch-qc-count-op]")
    if (qcCountOp) qcCountOp.value = ">"
    const qcCountValue = modal.querySelector("[data-branch-qc-count-value]")
    if (qcCountValue) qcCountValue.value = "0"

    // Clear cached entity data for fresh selection
    this._selectedEntitySchema = null
    this._selectedEntityName = ""

    // Ensure submit button is always enabled
    this._setSubmitButtonState(modal, "[data-branch-modal-submit]", true)
  }

  /**
   * Switch the modal between add and edit personas: header title, submit
   * label, and submit routing (data-action rewrite — Stimulus rebinds on
   * attribute mutation). Add-mode strings are restored verbatim so the add
   * flow stays byte-identical.
   */
  _setModalMode(modal, mode) {
    const title = modal.querySelector("[data-branch-modal-title]")
    const submit = modal.querySelector("[data-branch-modal-submit]")
    if (mode === "edit") {
      if (title) title.textContent = "Edit Branch"
      if (submit) {
        submit.textContent = "Save Changes"
        submit.setAttribute("data-action", "click->property-editor#saveBranchEdits")
      }
    } else {
      if (title) title.textContent = "Add Decision Branch"
      if (submit) {
        submit.textContent = "Add Branch"
        submit.setAttribute("data-action", "click->property-editor#addBranchFromModal")
      }
    }
  }
```

Note: the original reset's condition-type-toggle block (`:63-81`) is replaced by the `_applyConditionTypeToggle(modal, "field")` call — the helper (Step 3) contains those exact statements. IMPORTANT: verify `_resetBranchModal`'s body against the CURRENT `openBranchModal` onOpen callback in the file and carry over every statement verbatim (the listing above reflects the file at planning time; if the live file differs, the live file wins for everything except the new `_editingBranchItem`/`_setModalMode`/`_applyConditionTypeToggle` lines).

- [ ] **Step 3: Extract `_applyConditionTypeToggle` from `switchBranchConditionType`** (replace `:115-147`)

```js
  switchBranchConditionType(event) {
    event.preventDefault()
    const modal = this.controller.branchModalContainerTarget?.querySelector("[data-branch-modal]")
    if (!modal) return
    this._applyConditionTypeToggle(modal, event.currentTarget.dataset.conditionType)
  }

  /**
   * Apply the field / query_count toggle styling and panel visibility.
   * loadEntities=false lets the edit prefill own the (awaited) entity load,
   * avoiding a duplicate concurrent fetch that would double-append options.
   */
  _applyConditionTypeToggle(modal, selectedType, { loadEntities = true } = {}) {
    const toggleContainer = modal.querySelector("[data-condition-type-toggle]")
    if (!toggleContainer) return

    // Update toggle button styles
    toggleContainer.querySelectorAll("button").forEach(btn => {
      if (btn.dataset.conditionType === selectedType) {
        btn.classList.remove("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
        btn.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
      } else {
        btn.classList.remove("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
        btn.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
      }
    })

    // Toggle panels
    const fieldPanel = modal.querySelector("[data-branch-condition-field-panel]")
    const queryPanel = modal.querySelector("[data-branch-condition-query-panel]")

    if (selectedType === "query_count") {
      if (fieldPanel) fieldPanel.classList.add("hidden")
      if (queryPanel) queryPanel.classList.remove("hidden")
      if (loadEntities) this._loadQueryCountEntities(modal)
    } else {
      if (fieldPanel) fieldPanel.classList.remove("hidden")
      if (queryPanel) queryPanel.classList.add("hidden")
    }
  }
```

(Carry over the live file's exact statements if they differ from this listing.)

- [ ] **Step 4: Clear edit mode in `closeBranchModal`** (`:104-113`)

```js
  closeBranchModal(event) {
    if (event) event.preventDefault()
    // Cancel/backdrop/X always exits edit mode; the next open re-labels via
    // _resetBranchModal, so a stale "Save Changes" can never fire add-mode.
    this._editingBranchItem = null
    if (!this.controller.hasBranchModalContainerTarget) return

    // Use mixin method to close modal
    this._closeModal(
      this.controller.branchModalContainerTarget,
      "[data-branch-modal]"
    )
  }
```

- [ ] **Step 5: Add the edit open/prefill path** — insert after `removeBranch` (`:417`), inside a new `// Branch Edit (in place)` section:

```js
  // ===================
  // Branch Edit (in place)
  // ===================

  /**
   * Open the branch modal in edit mode, pre-filled from the card's hidden
   * inputs. Pre-fill only — nothing is mutated until Save Changes.
   */
  editBranch(event) {
    event.preventDefault()
    if (!this.controller.hasBranchModalContainerTarget) return
    const branchItem = event.target.closest("[data-branch-item]")
    if (!branchItem) return

    const name = branchItem.querySelector("input[name*='[name]']")?.value || ""
    const description = branchItem.querySelector("input[name*='[description]']")?.value || ""
    let condition = null
    const conditionInput = branchItem.querySelector("input[name*='[condition]']")
    if (conditionInput?.value) {
      try {
        condition = JSON.parse(conditionInput.value)
      } catch {
        // Malformed stored condition — edit proceeds as condition-less,
        // mirroring collectBranches' tolerance.
      }
    }

    this._openModal(
      this.controller.branchModalContainerTarget,
      "[data-branch-modal]",
      {
        focusSelector: "[data-branch-name]",
        onOpen: (modal) => {
          this._resetBranchModal(modal)            // clears _editingBranchItem
          this._editingBranchItem = branchItem     // set AFTER reset
          this._setModalMode(modal, "edit")
          this._prefillBranchModal(modal, branchItem, { name, description, condition })
        }
      }
    )
  }

  _prefillBranchModal(modal, branchItem, { name, description, condition }) {
    const nameInput = modal.querySelector("[data-branch-name]")
    if (nameInput) nameInput.value = name
    const descTextarea = modal.querySelector("[data-branch-modal-description]")
    if (descTextarea) descTextarea.value = description

    if (!condition) return
    if (condition.conditionType === "query_count") {
      this._applyConditionTypeToggle(modal, "query_count", { loadEntities: false })
      // Async: entity list + schema fetches; guarded against modal reuse.
      this._prefillQueryCountCondition(modal, branchItem, condition)
    } else {
      this._prefillFieldCondition(modal, condition)
    }
  }

  /**
   * Field condition prefill: select the stored left operand when it is among
   * the options, otherwise populate the manual input (same swap markup as
   * swapLeftOperandToManual, but keeping the stored value). Re-applies the
   * round-3 advisory chip from the selected option's data-attr-type.
   */
  _prefillFieldCondition(modal, condition) {
    const left = condition.leftOperand || ""
    const leftSelect = modal.querySelector("[data-branch-condition-left-select]")
    const hasOption = !!leftSelect && Array.from(leftSelect.options)
      .some(o => o.value === left && o.value !== "__manual__")

    if (hasOption) {
      leftSelect.value = left
      const attrType = leftSelect.selectedOptions?.[0]?.dataset?.attrType || ""
      const rightInput = modal.querySelector("[data-branch-condition-right]")
      if (rightInput) {
        upsertTypeChip(rightInput.parentElement, attrType)
        wireSoftTypeValidation(rightInput, attrType)
      }
    } else if (left) {
      const manual = modal.querySelector("[data-branch-condition-left-manual]")
      if (leftSelect) { leftSelect.classList.add("hidden"); leftSelect.value = "" }
      if (manual) {
        manual.classList.remove("hidden")
        const input = manual.querySelector("[data-branch-condition-left]")
        if (input) input.value = left
      }
    }

    const opSelect = modal.querySelector("[data-branch-condition-op]")
    if (opSelect) opSelect.value = condition.operator || "=="
    const rightInput = modal.querySelector("[data-branch-condition-right]")
    if (rightInput) rightInput.value = condition.rightOperand || ""
  }

  /**
   * Query-count prefill: load entities, select the stored entity, fetch its
   * schema (same endpoint/guards as onQueryCountEntityChange), rebuild WHERE
   * rows from stored rules, set count operator/value. Aborts after any await
   * if the modal left edit mode for this card (close / re-open as add).
   */
  async _prefillQueryCountCondition(modal, branchItem, condition) {
    const qc = condition.queryConfig || {}

    await this._loadQueryCountEntities(modal)
    if (this._editingBranchItem !== branchItem) return

    const entitySelect = modal.querySelector("[data-branch-qc-entity]")
    if (entitySelect && qc.entityId != null) entitySelect.value = String(qc.entityId)

    const countOp = modal.querySelector("[data-branch-qc-count-op]")
    if (countOp) countOp.value = condition.countOperator || ">"
    const countValue = modal.querySelector("[data-branch-qc-count-value]")
    if (countValue) countValue.value = String(condition.countValue ?? 0)

    const whereRows = modal.querySelector("[data-branch-qc-where-rows]")
    if (!whereRows) return

    // Fetch the entity schema exactly like onQueryCountEntityChange does
    // (silent degradation: rows fall back to the manual input on failure).
    const entityId = entitySelect?.value
    const customerId = this._getCustomerId()
    if (entityId && customerId) {
      const fetchId = ++this._entityFetchId
      try {
        const response = await fetch(`/${customerId}/admin/maintenance/entities/${entityId}.json`, {
          headers: { "Accept": "application/json" }
        })
        if (fetchId !== this._entityFetchId) return
        if (this._editingBranchItem !== branchItem) return
        if (response.ok) {
          const entity = await response.json()
          this._selectedEntitySchema = entity.property_schema || []
          this._selectedEntityName = entity.name || ""
        } else {
          this._showQcSchemaError(whereRows)
        }
      } catch (e) {
        if (fetchId !== this._entityFetchId) return
        if (this._editingBranchItem !== branchItem) return
        this._showQcSchemaError(whereRows)
      }
    }
    if (this._editingBranchItem !== branchItem) return

    const rules = qc.conditions?.rules || []
    if (rules.length === 0) {
      // Match the one-empty-row state the add flow shows after entity pick.
      this._addQueryCountWhereRow(whereRows)
      return
    }
    rules.forEach(rule => {
      this._addQueryCountWhereRow(whereRows)
      const rows = whereRows.querySelectorAll("[data-qc-where-row]")
      this._prefillQcWhereRow(rows[rows.length - 1], rule)
    })
  }

  /**
   * Seed one WHERE row from a stored rule. Field values are "data.<slug>" /
   * system fields when they came from the select; anything not among the
   * options swaps to the manual input (schema-missing degradation included).
   */
  _prefillQcWhereRow(row, rule) {
    if (!row) return
    const select = row.querySelector("[data-qc-where-field]")
    const hasOption = !!select && Array.from(select.options)
      .some(o => o.value === rule.field && o.value !== "__manual__")

    if (hasOption) {
      select.value = rule.field
      const colType = select.selectedOptions?.[0]?.dataset?.colType || ""
      if (colType) {
        row.dataset.qcColType = colType
        const valueInput = row.querySelector("[data-qc-where-value]")
        if (valueInput) {
          upsertTypeChip(valueInput.parentElement, colType)
          wireSoftTypeValidation(valueInput, colType)
        }
      }
    } else if (rule.field) {
      const manual = row.querySelector("[data-qc-where-field-manual]")
      if (select) { select.classList.add("hidden"); select.value = "" }
      if (manual) {
        manual.classList.remove("hidden")
        const input = manual.querySelector("[data-qc-where-field-input]")
        if (input) input.value = rule.field
      }
    }

    const opSelect = row.querySelector("[data-qc-where-op]")
    if (opSelect) opSelect.value = rule.op || "=="
    const valueInput = row.querySelector("[data-qc-where-value]")
    if (valueInput) valueInput.value = rule.value || ""
  }
```

IMPORTANT for the implementer: verify the exact selectors (`[data-qc-where-op]`, `[data-qc-where-field-manual]`, `[data-qc-where-field-input]`, rule key names `field/op/value`) against the live `_addQueryCountWhereRow` / `_collectQueryCountCondition` code before applying — the live file wins over this listing.

- [ ] **Step 6: Add `saveBranchEdits`** — immediately after `_prefillQcWhereRow`:

```js
  /**
   * Edit-mode submit. Mirrors addBranchFromModal's mutation order minus
   * creation: onBeforeChange snapshot → re-render the card (same index,
   * same elementId — hidden inputs regenerated by the template) → sync
   * element.properties.branches → update the EXISTING connection in place →
   * branchUpdated → decision re-render + updateConnections → onchange.
   * NO element creation, NO repositioning, NO port remap, NO count change.
   */
  saveBranchEdits(event) {
    event.preventDefault()
    if (!this.controller.hasBranchModalContainerTarget) return

    const branchItem = this._editingBranchItem
    if (!branchItem || !branchItem.isConnected) {
      // Defensive: edit target vanished (element re-rendered) — behave as add.
      this.addBranchFromModal(event)
      return
    }

    const modal = this.controller.branchModalContainerTarget.querySelector("[data-branch-modal]")
    if (!modal) return

    const branchNameInput = modal.querySelector("[data-branch-name]")
    const branchName = branchNameInput?.value?.trim() || ""
    if (!branchName) {
      this._highlightFieldError(branchNameInput)
      return
    }

    const description = modal.querySelector("[data-branch-modal-description]")?.value?.trim() || ""
    const condition = this._collectBranchConditionFromModal(modal)

    const oldName = branchItem.querySelector("input[name*='[name]']")?.value || ""
    const index = parseInt(branchItem.dataset.branchIndex || "0", 10)
    const branchElementId = branchItem.dataset.branchElementId || null

    // Snapshot current state for undo BEFORE making any changes
    if (this.controller.canvas) {
      this.controller.canvas.onBeforeChange?.()
    }

    // Re-render the card in place with the SAME index and elementId; title,
    // condition summary, no-condition badge, and hidden inputs all come from
    // the one template (buildBranchItemTemplate / buildConditionSummaryText).
    branchItem.outerHTML = this.buildBranchItemHTML(
      index, branchName, description, branchElementId, condition
    )

    // Sync decision properties. branchKey is positional in collectBranches
    // and order is unchanged, so branchKey/elementId cannot change.
    if (this.controller.canvas && this.controller.currentElement) {
      const element = this.controller.currentElement
      element.properties = element.properties || {}
      element.properties.branches = this.collectBranches()
    }

    // Update the EXISTING connection (same lookup as addBranchFromModal).
    if (branchElementId && this.controller.canvas && this.controller.currentElement) {
      const decisionElementId = this.controller.currentElement.id
      const conns = this.controller.canvas.connections || []
      const conn = conns.find(c => c.from === decisionElementId && c.to === branchElementId)
      if (conn) {
        if (condition) {
          conn.condition = condition
        } else {
          // Absent key is the add-flow shape for condition-less branches.
          delete conn.condition
        }
        // Follow the rename on the canvas, but never clobber a label the
        // user customized via the connection editor.
        if (conn.label === oldName) conn.label = branchName
      }
    }

    // Dispatch event to trigger auto-sync to canvas (parity with branchAdded)
    this._dispatchEvent("branchUpdated")

    // Refresh: decision port labels derive from branches[].name; connection
    // labels re-render in updateConnections. No reposition / no remap —
    // branch count and order are unchanged.
    if (this.controller.canvas && this.controller.currentElement) {
      this._refreshDecisionElement(this.controller.currentElement)
      this.controller.canvas._hideConnectionHandles()
      this.controller.canvas.updateConnections()
      // Commit the complete change to undo stack AFTER all modifications
      this.controller.canvas.onchange?.()
    }

    this.closeBranchModal()
  }
```

IMPORTANT for the implementer: verify the exact helper names against the live file before applying — in particular how add-mode collects the condition (the plan calls it `_collectBranchConditionFromModal(modal)`; if the live code uses separate `_collectFieldCondition`/`_collectQueryCountCondition` keyed off the visible panel, replicate exactly what `addBranchFromModal` does to produce `condition`), the card template entry point (`buildBranchItemHTML` signature), and the data attributes (`dataset.branchElementId` vs a hidden elementId input). The live add-flow code is ground truth; mirror it.

- [ ] **Step 7: Syntax check**

```bash
node --input-type=module --check < app/javascript/controllers/property_editor/branch_manager.js
```
Expected: exit 0.

- [ ] **Step 8: Regression rspec**

```bash
bundle exec rspec spec/components/property_editor/ spec/requests/maintenance/flowcharts_editor_spec.rb
```
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git commit -m "feat(property-editor): branch edit-in-place core in BranchManager

Edit-mode open/prefill (field + query_count) and saveBranchEdits that
updates hidden inputs, card, decision branches, and the existing
connection in place. Add flow untouched; reset/toggle bodies extracted
verbatim for reuse.

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Controller delegations + branchUpdated auto-sync

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:577-579` (after `removeBranch` delegation), `:1048-1062` (`_setupFormChangeListeners`), `:1067-1078` (`_removeFormChangeListeners`)

- [ ] **Step 1: Add delegations** — insert after the `removeBranch` delegation, before `applyBranchPreset`:

```js
  editBranch(event) {
    this.branchManager.editBranch(event)
  }

  saveBranchEdits(event) {
    this.branchManager.saveBranchEdits(event)
  }
```

- [ ] **Step 2: Register `branchUpdated`** — in `_setupFormChangeListeners`, after the `branchRemoved` line:

```js
    this.formTarget.addEventListener("branchUpdated", this._boundSyncChanges)
```

and the matching `removeEventListener` in `_removeFormChangeListeners`.

- [ ] **Step 3: Syntax check** — `node --input-type=module --check < app/javascript/controllers/property_editor_controller.js` → exit 0.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat(property-editor): editBranch/saveBranchEdits delegations + branchUpdated sync

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Templates — Edit button on the branch card, modal title hook

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:966` (modal `<h3>`), `:1180-1189` (`buildBranchItemTemplate` trailing actions)

- [ ] **Step 1: Add the title hook to the modal header** — add `data-branch-modal-title` to the `<h3>` ("Add Decision Branch"). The submit button already carries `data-branch-modal-submit` — no change there.

- [ ] **Step 2: Add the Edit pencil before Remove in `buildBranchItemTemplate`** — replace the `trailingHTML` block with (Remove button byte-identical to today; only Edit is new):

```js
  const trailingHTML = `
    <button type="button"
            data-action="click->property-editor#editBranch"
            class="p-1 text-slate-300 hover:text-indigo-600 hover:bg-indigo-50 rounded-md opacity-0 group-hover:opacity-100 transition-all duration-150 flex-shrink-0"
            title="Edit branch">
      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
      </svg>
    </button>
    <button type="button"
            data-action="click->property-editor#removeBranch"
            class="p-1 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-md opacity-0 group-hover:opacity-100 transition-all duration-150 flex-shrink-0"
            title="Remove branch">
      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
      </svg>
    </button>
  `
```

- [ ] **Step 3: Syntax check** — `node --input-type=module --check < app/javascript/controllers/property_editor/templates.js` → exit 0.

- [ ] **Step 4: Targeted rspec** — `bundle exec rspec spec/components/property_editor/ spec/requests/maintenance/flowcharts_editor_spec.rb` → all green.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat(property-editor): Edit affordance on branch cards + modal title hook

Co-Authored-By: Copilot Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Verification sweep + manual QA audit

**Files:** none modified.

- [ ] **Step 1: Full module syntax sweep** over branch_manager.js, templates.js, property_editor_controller.js — all exit 0.

- [ ] **Step 2: Full targeted rspec** — `bundle exec rspec spec/components/property_editor/ spec/requests/maintenance/flowcharts_editor_spec.rb` → all green.

- [ ] **Step 3: Manual QA on `/:cid/admin/maintenance/flowcharts/:id/edit`:**
  1. Add flow unchanged: Add Branch → preset chip → save → element spawned, positioned, condition on connection; saved JSON shapes unchanged.
  2. Edit a field-condition branch: pencil → "Edit Branch"/"Save Changes", fields pre-filled (select pre-selected; manual input for hand-typed operands); rename + condition change → card title/summary update, decision port label updates, connection label follows the rename, canvas element count unchanged, no movement; same branchKey/elementId.
  3. Edit a query_count branch: entity pre-selected, WHERE rows rebuilt (type chips for known columns), count op/value populated; round-trips byte-identical queryConfig.
  4. Clear a condition in edit → amber "no condition" badge; connection's condition key absent in saved JSON.
  5. Cancel / backdrop / X mid-edit → branch untouched; next Add Branch shows add-mode labels and blank fields.
  6. Empty name on Save Changes → red ring, modal stays open.
  7. Undo after edit-save restores the pre-edit branch in one step.
  8. Round-3 type assist works in edit mode; never blocks save.

---

## Self-review notes

- Requirements 1–5 map to Tasks 1–3; nine contradictions carry binding resolutions used consistently.
- Add-flow byte-identity: `addBranchFromModal`, `collectBranches`, `_collectFieldCondition`, `_collectQueryCountCondition` have zero diffs; shared-code deltas are statement-preserving extractions only.
- The implementer must treat the LIVE file as ground truth for extracted bodies, selectors, and helper names — this plan's listings reflect planning-time line numbers.

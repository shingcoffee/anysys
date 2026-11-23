# Query Count Condition UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add frontend UI in the branch modal for configuring query count conditions — toggle between "Field Condition" and "Query Count" mode, entity selector, WHERE clause builder, and count operator/value.

**Architecture:** The branch modal template (`templates.js`) gets a condition type toggle and a query count panel. `BranchManager` gets methods to handle the toggle, fetch entities on-demand, fetch entity fields on selection, and collect query count condition data. The `addBranchFromModal` method is updated to detect the active condition type and build the correct condition object. The branch item template is updated to display a human-readable query count badge. New delegated actions are wired through `property_editor_controller.js`.

**Tech Stack:** StimulusJS, TailwindCSS, JavaScript (ES modules)

**Spec:** `docs/superpowers/specs/2026-04-06-conditional-branching-design.md`

---

## File Map

### Modified Files

| File | Responsibility |
|---|---|
| `app/javascript/controllers/property_editor/templates.js` | Add condition type toggle + query count panel to branch modal; update branch item badge for query count |
| `app/javascript/controllers/property_editor/branch_manager.js` | Toggle handler, entity fetch, entity field fetch, query count data collection, modal reset for query count fields |
| `app/javascript/controllers/property_editor_controller.js` | Delegate new action methods to BranchManager |

### No New Files

All changes are additions to existing files.

---

## Task 1: Branch modal template — Add condition type toggle and query count panel

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:594-620`

- [ ] **Step 1: Replace the Branch Condition section in `buildBranchModalTemplate`**

In `app/javascript/controllers/property_editor/templates.js`, find the existing Branch Condition section (lines 594-620):

```html
              <!-- Branch Condition -->
              <div class="mt-4 border-t border-gray-100 pt-4">
                <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Branch Condition (optional)</label>
                <p class="text-xs text-gray-400 mb-2">If set, this branch only activates when the condition matches. Leave blank to use the element's main condition.</p>
                <div class="flex items-center gap-2">
                  <input type="text"
                         data-branch-condition-left
                         class="flex-1 min-w-0 rounded border border-gray-300 px-2 py-1 text-xs font-mono placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-500"
                         placeholder="ctx.field_name" />
                  <select data-branch-condition-op
                          class="rounded border border-gray-300 px-2 py-1 text-xs text-gray-700 focus:outline-none focus:ring-1 focus:ring-blue-500">
                    <option value="==">==</option>
                    <option value="!=">!=</option>
                    <option value=">">&gt;</option>
                    <option value=">=">&gt;=</option>
                    <option value="<">&lt;</option>
                    <option value="<=">&lt;=</option>
                    <option value="is_empty">is empty</option>
                    <option value="is_not_empty">is not empty</option>
                    <option value="contains">contains</option>
                  </select>
                  <input type="text"
                         data-branch-condition-right
                         class="flex-1 min-w-0 rounded border border-gray-300 px-2 py-1 text-xs font-mono placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-500"
                         placeholder="value" />
                </div>
              </div>
```

Replace it with:

```html
              <!-- Branch Condition -->
              <div class="mt-4 border-t border-gray-100 pt-4">
                <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Branch Condition (optional)</label>
                <p class="text-xs text-gray-400 mb-2">If set, this branch only activates when the condition matches.</p>

                <!-- Condition Type Toggle -->
                <div class="flex items-center gap-1 mb-3" data-condition-type-toggle>
                  <button type="button"
                          data-action="click->property-editor#switchBranchConditionType"
                          data-condition-type="field"
                          class="px-3 py-1 text-[10px] font-bold rounded-full transition-colors bg-amber-200 text-amber-800">
                    Field Condition
                  </button>
                  <button type="button"
                          data-action="click->property-editor#switchBranchConditionType"
                          data-condition-type="query_count"
                          class="px-3 py-1 text-[10px] font-bold rounded-full transition-colors bg-gray-100 text-gray-500">
                    Query Count
                  </button>
                </div>

                <!-- Field Condition Panel (default, visible) -->
                <div data-branch-condition-field-panel>
                  <div class="flex items-center gap-2">
                    <input type="text"
                           data-branch-condition-left
                           class="flex-1 min-w-0 rounded border border-gray-300 px-2 py-1 text-xs font-mono placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-500"
                           placeholder="ctx.field_name" />
                    <select data-branch-condition-op
                            class="rounded border border-gray-300 px-2 py-1 text-xs text-gray-700 focus:outline-none focus:ring-1 focus:ring-blue-500">
                      <option value="==">==</option>
                      <option value="!=">!=</option>
                      <option value=">">&gt;</option>
                      <option value=">=">&gt;=</option>
                      <option value="<">&lt;</option>
                      <option value="<=">&lt;=</option>
                      <option value="is_empty">is empty</option>
                      <option value="is_not_empty">is not empty</option>
                      <option value="contains">contains</option>
                    </select>
                    <input type="text"
                           data-branch-condition-right
                           class="flex-1 min-w-0 rounded border border-gray-300 px-2 py-1 text-xs font-mono placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-500"
                           placeholder="value" />
                  </div>
                </div>

                <!-- Query Count Panel (hidden by default) -->
                <div data-branch-condition-query-panel class="hidden space-y-3">
                  <!-- Entity Selector -->
                  <div>
                    <label class="block text-[10px] text-slate-500 mb-1">Entity</label>
                    <select data-branch-qc-entity
                            data-action="change->property-editor#onQueryCountEntityChange"
                            class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
                      <option value="">Select entity...</option>
                    </select>
                  </div>

                  <!-- WHERE Filters -->
                  <div>
                    <label class="block text-[10px] text-slate-500 mb-1">Where (optional)</label>
                    <div data-branch-qc-where-rows class="space-y-2">
                      <!-- Populated dynamically after entity selection -->
                    </div>
                    <button type="button"
                            data-action="click->property-editor#addQueryCountWhereRow"
                            class="mt-1.5 w-full inline-flex items-center justify-center px-2 py-1 text-[10px] font-medium text-amber-600 bg-white border border-amber-200 rounded hover:bg-amber-50 transition-colors">
                      <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                      </svg>
                      Add Filter
                    </button>
                  </div>

                  <!-- Count Comparison -->
                  <div>
                    <label class="block text-[10px] text-slate-500 mb-1">Count</label>
                    <div class="flex items-center gap-2">
                      <select data-branch-qc-count-op
                              class="rounded border border-gray-300 px-2 py-1.5 text-xs text-gray-700 focus:outline-none focus:ring-1 focus:ring-amber-500">
                        <option value=">">&gt;</option>
                        <option value=">=">&gt;=</option>
                        <option value="==">==</option>
                        <option value="!=">!=</option>
                        <option value="<">&lt;</option>
                        <option value="<=">&lt;=</option>
                      </select>
                      <input type="number"
                             data-branch-qc-count-value
                             value="0"
                             min="0"
                             class="flex-1 min-w-0 rounded border border-gray-300 px-2 py-1.5 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-amber-500"
                             placeholder="0" />
                    </div>
                  </div>
                </div>
              </div>
```

- [ ] **Step 2: Verify the template renders correctly**

Run the Rails server and open a flowchart editor. Double-click a Decision element, click "Add Branch". Verify:
- The "Field Condition" / "Query Count" toggle buttons appear
- "Field Condition" is active by default (amber pill)
- The original 3-field condition UI is visible
- The query count panel is hidden

---

## Task 2: Branch item template — Display query count condition badge

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:650-719`

- [ ] **Step 1: Update `buildBranchItemTemplate` to handle query count conditions**

In `app/javascript/controllers/property_editor/templates.js`, find the `buildBranchItemTemplate` function. Replace the `conditionHtml` logic (lines 664-669):

```javascript
  // Condition badge HTML
  const conditionHtml = condition
    ? `<span class="inline-flex items-center gap-1 mt-1 text-xs font-mono text-blue-700 bg-blue-50 border border-blue-200 rounded px-1.5 py-0.5">
         <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 3.907-.542.369-1.25.85-1.994 1.093V17m0 4h.01M12 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
         if ${escapeHtml(condition.leftOperand)} ${escapeHtml(condition.operator)} ${escapeHtml(condition.rightOperand || '')}
       </span>`
    : ''
```

Replace with:

```javascript
  // Condition badge HTML
  let conditionHtml = ''
  if (condition) {
    if (condition.conditionType === "query_count") {
      const qc = condition.queryConfig || {}
      const entityName = qc.entityName || `Entity#${qc.entityId || '?'}`
      const countOp = escapeHtml(condition.countOperator || '>')
      const countVal = escapeHtml(String(condition.countValue ?? 0))
      conditionHtml = `<span class="inline-flex items-center gap-1 mt-1 text-xs font-mono text-purple-700 bg-purple-50 border border-purple-200 rounded px-1.5 py-0.5">
           <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"/></svg>
           Count ${escapeHtml(entityName)} ${countOp} ${countVal}
         </span>`
    } else {
      conditionHtml = `<span class="inline-flex items-center gap-1 mt-1 text-xs font-mono text-blue-700 bg-blue-50 border border-blue-200 rounded px-1.5 py-0.5">
           <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 3.907-.542.369-1.25.85-1.994 1.093V17m0 4h.01M12 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
           if ${escapeHtml(condition.leftOperand || '')} ${escapeHtml(condition.operator || '')} ${escapeHtml(condition.rightOperand || '')}
         </span>`
    }
  }
```

- [ ] **Step 2: Verify visually**

Open the branch modal, create a branch. Confirm the existing field condition badge still displays correctly with blue styling.

---

## Task 3: BranchManager — Condition type toggle handler

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`

- [ ] **Step 1: Add `switchBranchConditionType` method**

In `app/javascript/controllers/property_editor/branch_manager.js`, add the following method after the `closeBranchModal(event)` method (after line 66):

```javascript
  switchBranchConditionType(event) {
    event.preventDefault()
    const modal = this.controller.branchModalContainerTarget?.querySelector("[data-branch-modal]")
    if (!modal) return

    const selectedType = event.currentTarget.dataset.conditionType
    const toggleContainer = modal.querySelector("[data-condition-type-toggle]")
    if (!toggleContainer) return

    // Update toggle button styles
    toggleContainer.querySelectorAll("button").forEach(btn => {
      if (btn.dataset.conditionType === selectedType) {
        btn.classList.remove("bg-gray-100", "text-gray-500")
        btn.classList.add("bg-amber-200", "text-amber-800")
      } else {
        btn.classList.remove("bg-amber-200", "text-amber-800")
        btn.classList.add("bg-gray-100", "text-gray-500")
      }
    })

    // Toggle panels
    const fieldPanel = modal.querySelector("[data-branch-condition-field-panel]")
    const queryPanel = modal.querySelector("[data-branch-condition-query-panel]")

    if (selectedType === "query_count") {
      if (fieldPanel) fieldPanel.classList.add("hidden")
      if (queryPanel) queryPanel.classList.remove("hidden")
      this._loadQueryCountEntities(modal)
    } else {
      if (fieldPanel) fieldPanel.classList.remove("hidden")
      if (queryPanel) queryPanel.classList.add("hidden")
    }
  }
```

- [ ] **Step 2: Verify toggle works**

Open branch modal, click "Query Count" toggle. Confirm:
- "Query Count" button becomes amber, "Field Condition" becomes gray
- Field condition panel hides, query count panel shows
- Clicking "Field Condition" reverses the toggle

---

## Task 4: BranchManager — Entity fetch and field population

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`

- [ ] **Step 1: Add `_loadQueryCountEntities` method**

Add this method in the Private Methods section of `BranchManager` (after line 684, before the Condition Section Handlers comment):

```javascript
  async _loadQueryCountEntities(modal) {
    const entitySelect = modal.querySelector("[data-branch-qc-entity]")
    if (!entitySelect) return

    // Avoid re-fetching if already loaded
    if (entitySelect.options.length > 1) return

    const customerId = this.controller.canvas?.customerIdValue
    if (!customerId) return

    try {
      const response = await fetch(`/${customerId}/entities.json`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const entities = await response.json()
      this._cachedEntities = entities

      entities.forEach(entity => {
        const option = document.createElement("option")
        option.value = entity.id
        option.textContent = entity.name
        entitySelect.appendChild(option)
      })
    } catch (e) {
      // Silently fail — entity dropdown stays empty with placeholder
    }
  }
```

- [ ] **Step 2: Add `onQueryCountEntityChange` method**

Add this method after `switchBranchConditionType`:

```javascript
  async onQueryCountEntityChange(event) {
    const entityId = event.target.value
    const modal = event.target.closest("[data-branch-modal]")
    if (!modal) return

    const whereRows = modal.querySelector("[data-branch-qc-where-rows]")
    if (!whereRows) return

    // Clear existing WHERE rows
    whereRows.innerHTML = ""

    if (!entityId) return

    // Fetch entity schema for field options
    const customerId = this.controller.canvas?.customerIdValue
    if (!customerId) return

    try {
      const response = await fetch(`/${customerId}/entities/${entityId}.json`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const entity = await response.json()
      this._selectedEntitySchema = entity.property_schema || []
      this._selectedEntityName = entity.name || ""

      // Add one empty WHERE row
      this._addQueryCountWhereRow(whereRows)
    } catch (e) {
      // Silently fail
    }
  }
```

- [ ] **Step 3: Verify entity loading**

Open branch modal, switch to "Query Count" mode. Confirm:
- Entity dropdown populates with available entities
- Selecting an entity adds one WHERE filter row with the entity's fields

---

## Task 5: BranchManager — WHERE clause row builder

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`

- [ ] **Step 1: Add `_addQueryCountWhereRow` and `addQueryCountWhereRow` methods**

Add these methods after `onQueryCountEntityChange`:

```javascript
  addQueryCountWhereRow(event) {
    event.preventDefault()
    const modal = event.target.closest("[data-branch-modal]")
    if (!modal) return

    const whereRows = modal.querySelector("[data-branch-qc-where-rows]")
    if (!whereRows) return

    this._addQueryCountWhereRow(whereRows)
  }
```

Add this in the Private Methods section (after `_loadQueryCountEntities`):

```javascript
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
                    class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
              ${fieldOptionsHTML}
            </select>
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
          <div>
            <input type="text"
                   data-qc-where-value
                   class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded shadow-sm font-mono placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500"
                   placeholder="value" />
          </div>
        </div>
      </div>
    `

    container.insertAdjacentHTML("beforeend", rowHTML)
  }

  removeQueryCountWhereRow(event) {
    event.preventDefault()
    const row = event.target.closest("[data-qc-where-row]")
    if (row) row.remove()
  }
```

- [ ] **Step 2: Verify WHERE rows**

Open branch modal, switch to Query Count, select an entity. Confirm:
- One WHERE row appears with the entity's field names in the dropdown
- "Add Filter" button adds more rows
- Remove button (X) on 2nd+ row removes that row
- Operator dropdown includes `==`, `!=`, `>`, `>=`, `<`, `<=`, `contains`, `is empty`, `is not empty`

---

## Task 6: BranchManager — Update `addBranchFromModal` to collect query count data

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js:68-141`

- [ ] **Step 1: Update `addBranchFromModal` to detect condition type and collect data**

In `app/javascript/controllers/property_editor/branch_manager.js`, replace the condition extraction section in `addBranchFromModal` (lines 84-95):

```javascript
    // Extract branch-level condition fields
    const conditionLeftInput  = modal.querySelector("[data-branch-condition-left]")
    const conditionOpInput    = modal.querySelector("[data-branch-condition-op]")
    const conditionRightInput = modal.querySelector("[data-branch-condition-right]")

    const conditionLeft  = conditionLeftInput?.value?.trim() || ""
    const conditionOp    = conditionOpInput?.value || "=="
    const conditionRight = conditionRightInput?.value?.trim() || ""

    const condition = (conditionLeft.length > 0)
      ? { type: "single", leftOperand: conditionLeft, operator: conditionOp, rightOperand: conditionRight }
      : null
```

Replace with:

```javascript
    // Detect active condition type
    const condition = this._collectBranchConditionFromModal(modal)
```

- [ ] **Step 2: Add `_collectBranchConditionFromModal` method**

Add this method in the Private Methods section:

```javascript
  _collectBranchConditionFromModal(modal) {
    const activeToggle = modal.querySelector("[data-condition-type-toggle] button.bg-amber-200")
    const conditionType = activeToggle?.dataset?.conditionType || "field"

    if (conditionType === "query_count") {
      return this._collectQueryCountCondition(modal)
    }
    return this._collectFieldCondition(modal)
  }

  _collectFieldCondition(modal) {
    const conditionLeft = modal.querySelector("[data-branch-condition-left]")?.value?.trim() || ""
    const conditionOp = modal.querySelector("[data-branch-condition-op]")?.value || "=="
    const conditionRight = modal.querySelector("[data-branch-condition-right]")?.value?.trim() || ""

    if (conditionLeft.length === 0) return null

    return { type: "single", leftOperand: conditionLeft, operator: conditionOp, rightOperand: conditionRight }
  }

  _collectQueryCountCondition(modal) {
    const entitySelect = modal.querySelector("[data-branch-qc-entity]")
    const entityId = entitySelect?.value
    if (!entityId) return null

    // Get entity name for display
    const entityName = entitySelect?.options[entitySelect.selectedIndex]?.textContent || ""

    // Collect WHERE rules
    const whereRows = modal.querySelectorAll("[data-qc-where-row]")
    const rules = []
    whereRows.forEach(row => {
      const field = row.querySelector("[data-qc-where-field]")?.value || ""
      const op = row.querySelector("[data-qc-where-op]")?.value || "=="
      const value = row.querySelector("[data-qc-where-value]")?.value?.trim() || ""

      if (field) {
        rules.push({ field, op, value })
      }
    })

    const countOp = modal.querySelector("[data-branch-qc-count-op]")?.value || ">"
    const countValue = parseInt(modal.querySelector("[data-branch-qc-count-value]")?.value || "0", 10) || 0

    const condition = {
      conditionType: "query_count",
      queryConfig: {
        entityId: parseInt(entityId, 10),
        entityName: entityName
      },
      countOperator: countOp,
      countValue: countValue
    }

    if (rules.length > 0) {
      condition.queryConfig.conditions = {
        operator: "AND",
        rules: rules
      }
    }

    return condition
  }
```

- [ ] **Step 3: Verify data collection**

Open branch modal, switch to Query Count, select an entity, add a WHERE filter, set count `> 5`, click "Add Branch". Confirm:
- Branch item appears in the list with a purple "Count EntityName > 5" badge
- The condition is stored on the connection object

---

## Task 7: BranchManager — Reset query count fields on modal open

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js:24-55`

- [ ] **Step 1: Update `openBranchModal` to also reset query count state**

In the `openBranchModal` method, after the existing condition field reset (after line 48: `if (condOp) condOp.value = "=="`), add:

```javascript
          // Reset condition type toggle to "Field Condition"
          const toggleContainer = modal.querySelector("[data-condition-type-toggle]")
          if (toggleContainer) {
            toggleContainer.querySelectorAll("button").forEach(btn => {
              if (btn.dataset.conditionType === "field") {
                btn.classList.remove("bg-gray-100", "text-gray-500")
                btn.classList.add("bg-amber-200", "text-amber-800")
              } else {
                btn.classList.remove("bg-amber-200", "text-amber-800")
                btn.classList.add("bg-gray-100", "text-gray-500")
              }
            })
          }

          // Reset panels: show field, hide query count
          const fieldPanel = modal.querySelector("[data-branch-condition-field-panel]")
          const queryPanel = modal.querySelector("[data-branch-condition-query-panel]")
          if (fieldPanel) fieldPanel.classList.remove("hidden")
          if (queryPanel) queryPanel.classList.add("hidden")

          // Reset query count fields
          const qcEntity = modal.querySelector("[data-branch-qc-entity]")
          if (qcEntity) qcEntity.value = ""
          const qcWhereRows = modal.querySelector("[data-branch-qc-where-rows]")
          if (qcWhereRows) qcWhereRows.innerHTML = ""
          const qcCountOp = modal.querySelector("[data-branch-qc-count-op]")
          if (qcCountOp) qcCountOp.value = ">"
          const qcCountValue = modal.querySelector("[data-branch-qc-count-value]")
          if (qcCountValue) qcCountValue.value = "0"
```

- [ ] **Step 2: Clear cached entity schema**

In the same `openBranchModal` onOpen callback, also add:

```javascript
          // Clear cached entity data for fresh selection
          this._selectedEntitySchema = null
          this._selectedEntityName = ""
```

- [ ] **Step 3: Verify reset behavior**

Open branch modal, configure a query count condition, close modal. Reopen. Confirm:
- Toggle is back to "Field Condition" (default)
- Query count panel is hidden
- All query count fields are reset to defaults

---

## Task 8: PropertyEditorController — Wire up delegated actions

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:390-432`

- [ ] **Step 1: Add delegated action methods**

In `app/javascript/controllers/property_editor_controller.js`, after the `removeConditionRow` method (line 431), add the following new delegated methods:

```javascript
  switchBranchConditionType(event) {
    this.branchManager.switchBranchConditionType(event)
  }

  onQueryCountEntityChange(event) {
    this.branchManager.onQueryCountEntityChange(event)
  }

  addQueryCountWhereRow(event) {
    this.branchManager.addQueryCountWhereRow(event)
  }

  removeQueryCountWhereRow(event) {
    this.branchManager.removeQueryCountWhereRow(event)
  }
```

- [ ] **Step 2: Verify wiring**

Open branch modal, switch to "Query Count", interact with all controls. Confirm:
- Toggle buttons work (calls `switchBranchConditionType`)
- Entity dropdown change triggers entity fetch (calls `onQueryCountEntityChange`)
- "Add Filter" button adds WHERE rows (calls `addQueryCountWhereRow`)
- Remove filter button removes rows (calls `removeQueryCountWhereRow`)

---

## Task 9: Integration verification — End-to-end test

- [ ] **Step 1: Test complete flow**

1. Open a flowchart with a Decision element
2. Double-click the Decision element to open property editor
3. Click "Add Branch"
4. In the modal, switch to "Query Count"
5. Select an entity from the dropdown
6. Add a WHERE filter (e.g., `data.status == active`)
7. Set count operator to `>` and value to `5`
8. Click "Add Branch"
9. Verify: branch item shows purple badge "Count [EntityName] > 5"
10. Click "Save" on the property editor
11. Verify: the condition is persisted in the flowchart configuration on the connection

- [ ] **Step 2: Test backward compatibility**

1. Open a Decision element that already has field-condition branches
2. Verify existing branches display correctly
3. Add a new branch with "Field Condition" mode
4. Verify it works exactly as before (no regression)

- [ ] **Step 3: Test mixed conditions**

1. On a Decision element, add branch with "Field Condition"
2. Add another branch with "Query Count"
3. Save the flowchart
4. Reload the page
5. Verify both branches display correctly

---

## Task 10: Commit

- [ ] **Step 1: Stage and commit all changes**

```bash
git add app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat: add query count condition UI in branch modal"
```

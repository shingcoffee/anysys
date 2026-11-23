# Property Popup Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the branch modal's visual language with the step modal, redesign the condition builder to use stacked fields with labels, and unify the step modal's advanced section styling.

**Architecture:** Pure CSS class changes in two JS files. The branch modal template in `templates.js` gets updated shell/header/footer classes plus a rebuilt condition section. `branch_manager.js` gets updated class-swapping logic for the condition type toggle and a selector fix.

**Tech Stack:** StimulusJS, TailwindCSS

**Spec:** `docs/superpowers/specs/2026-04-16-property-popup-polish-design.md`

---

### Task 1: Branch Modal Shell — Backdrop, Container, Header

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:541-575`

- [ ] **Step 1: Update backdrop classes**

In `buildBranchModalTemplate()`, change the backdrop div (line ~546):

```javascript
// OLD:
<div class="absolute inset-0 bg-black/50 transition-opacity"

// NEW:
<div class="absolute inset-0 bg-slate-900/40 backdrop-blur-[2px] transition-opacity"
```

- [ ] **Step 2: Update container classes**

Change the modal container div (line ~551):

```javascript
// OLD:
<div class="bg-white rounded-lg shadow-xl ring-1 ring-slate-200 overflow-hidden max-h-[80vh] flex flex-col">

// NEW:
<div class="bg-white rounded-xl shadow-2xl ring-1 ring-black/5 overflow-hidden max-h-[80vh] flex flex-col">
```

- [ ] **Step 3: Update header**

Replace the header block (lines ~554-563):

```javascript
// OLD:
            <!-- Header -->
            <div class="flex items-center justify-between px-4 py-3 border-b border-slate-200 bg-amber-50">
              <h3 class="text-sm font-medium text-slate-900">Add Decision Branch</h3>
              <button type="button"
                      data-action="click->property-editor#closeBranchModal"
                      class="text-slate-400 hover:text-slate-600 p-1 rounded hover:bg-amber-100 transition-colors">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

// NEW:
            <!-- Header -->
            <div class="flex items-center justify-between px-5 py-3.5 border-b border-slate-100">
              <div class="flex items-center gap-2.5">
                <div class="w-7 h-7 rounded-lg bg-amber-50 flex items-center justify-center">
                  <svg class="w-3.5 h-3.5 text-amber-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M13 17h8m-8-5h8m-8-5h8M3 17l3-3-3-3M3 7l3 3-3 3" />
                  </svg>
                </div>
                <h3 class="text-sm font-semibold text-slate-900">Add Decision Branch</h3>
              </div>
              <button type="button"
                      data-action="click->property-editor#closeBranchModal"
                      class="text-slate-400 hover:text-slate-600 p-1.5 rounded-lg hover:bg-slate-100 transition-colors">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
```

- [ ] **Step 4: Verify in browser**

Run `bin/dev`, open the flowchart editor, click a Decision element, go to Branches tab, click "+ Add Branch". Confirm:
- Backdrop has subtle blur
- Modal has rounded-xl corners and subtle shadow
- Header is white with amber icon badge and bold title
- Close button has rounded-lg hover state

---

### Task 2: Branch Modal Shell — Footer and Buttons

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:700-713`

- [ ] **Step 1: Update footer and buttons**

Replace the footer block (lines ~700-713):

```javascript
// OLD:
            <!-- Footer -->
            <div class="flex items-center justify-end gap-2 px-4 py-3 border-t border-slate-200 bg-slate-50">
              <button type="button"
                      data-action="click->property-editor#closeBranchModal"
                      class="px-3 py-1.5 text-sm font-medium text-slate-700 bg-white border border-slate-200 rounded-md shadow-sm hover:bg-slate-50 focus:outline-none focus:ring-1 focus:ring-indigo-500 transition-colors">
                Cancel
              </button>
              <button type="button"
                      data-action="click->property-editor#addBranchFromModal"
                      data-branch-modal-submit
                      class="px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 border border-transparent rounded-md shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-1 focus:ring-indigo-600 transition-colors">
                Add Branch
              </button>
            </div>

// NEW:
            <!-- Footer -->
            <div class="flex items-center justify-end gap-2.5 px-5 py-3.5 border-t border-slate-100 bg-slate-50/50">
              <button type="button"
                      data-action="click->property-editor#closeBranchModal"
                      class="px-4 py-2 text-sm font-medium text-slate-600 bg-white border border-slate-200 rounded-lg shadow-sm hover:bg-slate-50 hover:border-slate-300 transition-all duration-150">
                Cancel
              </button>
              <button type="button"
                      data-action="click->property-editor#addBranchFromModal"
                      data-branch-modal-submit
                      class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-lg shadow-sm shadow-indigo-200 hover:bg-indigo-700 hover:shadow-indigo-300 transition-all duration-150 disabled:opacity-50 disabled:cursor-not-allowed">
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                </svg>
                Add Branch
              </button>
            </div>
```

- [ ] **Step 2: Verify in browser**

Open branch modal again. Confirm:
- Footer has subtle bg-slate-50/50 and lighter border
- Cancel button is rounded-lg with shadow
- Add Branch button has plus icon, rounded-lg, indigo shadow

---

### Task 3: Branch Modal — Condition Type Toggle Redesign

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:601-619`

- [ ] **Step 1: Replace the condition type toggle HTML**

In `buildBranchModalTemplate()`, replace the condition type toggle section (lines ~601-619):

```javascript
// OLD:
              <!-- Branch Condition -->
              <div class="mt-4 border-t border-gray-100 pt-4">
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Branch Condition (optional)</label>
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

// NEW:
              <!-- Branch Condition -->
              <div class="mt-4 border-t border-slate-100 pt-4">
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Branch Condition (optional)</label>
                <p class="text-xs text-slate-400 mb-3">If set, this branch only activates when the condition matches.</p>

                <!-- Condition Type Toggle — segmented control -->
                <div class="flex gap-1 p-1 bg-slate-100 rounded-lg mb-3" data-condition-type-toggle>
                  <button type="button"
                          data-action="click->property-editor#switchBranchConditionType"
                          data-condition-type="field"
                          class="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-all duration-150 bg-white text-slate-900 shadow-sm ring-1 ring-black/5">
                    Field Condition
                  </button>
                  <button type="button"
                          data-action="click->property-editor#switchBranchConditionType"
                          data-condition-type="query_count"
                          class="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-all duration-150 text-slate-500 hover:text-slate-700 hover:bg-white/50">
                    Query Count
                  </button>
                </div>
```

- [ ] **Step 2: Verify in browser**

Open branch modal, scroll to "Branch Condition" section. Confirm:
- Toggle uses segmented control style matching the property editor tab bar
- "Field Condition" is active (white background, shadow, ring)
- "Query Count" is inactive (gray text, no background)
- Clicking toggles appearance correctly (will be verified after Task 5 updates the JS)

---

### Task 4: Branch Modal — Stacked Field Condition Panel

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:622-645`

- [ ] **Step 1: Replace the inline field condition with stacked layout**

Replace the field condition panel (lines ~622-645):

```javascript
// OLD:
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

// NEW:
                <!-- Field Condition Panel (default, visible) -->
                <div data-branch-condition-field-panel class="space-y-3">
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Left Operand</label>
                    <input type="text"
                           data-branch-condition-left
                           class="w-full px-3 py-2 text-sm font-mono border border-slate-200 rounded-lg shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"
                           placeholder="ctx[:field_name]" />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Operator</label>
                    <select data-branch-condition-op
                            class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
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
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Right Operand</label>
                    <input type="text"
                           data-branch-condition-right
                           class="w-full px-3 py-2 text-sm font-mono border border-slate-200 rounded-lg shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"
                           placeholder="value" />
                  </div>
                </div>
```

- [ ] **Step 2: Verify in browser**

Open branch modal. Confirm the field condition section shows:
- Three stacked full-width fields with uppercase labels
- Amber focus rings on all inputs
- Inputs use `text-sm` and `rounded-lg`

---

### Task 5: Branch Modal — Stacked Query Count Panel

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:648-696`

- [ ] **Step 1: Replace the query count panel with stacked layout and unified styling**

Replace the query count panel (lines ~648-696):

```javascript
// OLD:
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

// NEW:
                <!-- Query Count Panel (hidden by default) -->
                <div data-branch-condition-query-panel class="hidden space-y-3">
                  <!-- Entity Selector -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Entity</label>
                    <select data-branch-qc-entity
                            data-action="change->property-editor#onQueryCountEntityChange"
                            class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                      <option value="">Select entity...</option>
                    </select>
                  </div>

                  <!-- WHERE Filters -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Where (optional)</label>
                    <div data-branch-qc-where-rows class="space-y-2">
                      <!-- Populated dynamically after entity selection -->
                    </div>
                    <button type="button"
                            data-action="click->property-editor#addQueryCountWhereRow"
                            class="mt-1.5 w-full inline-flex items-center justify-center px-2 py-1.5 text-xs font-medium text-amber-600 bg-white border border-amber-200 rounded-lg hover:bg-amber-50 transition-colors">
                      <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                      </svg>
                      Add Filter
                    </button>
                  </div>

                  <!-- Count Operator -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Count Operator</label>
                    <select data-branch-qc-count-op
                            class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                      <option value=">">&gt;</option>
                      <option value=">=">&gt;=</option>
                      <option value="==">==</option>
                      <option value="!=">!=</option>
                      <option value="<">&lt;</option>
                      <option value="<=">&lt;=</option>
                    </select>
                  </div>

                  <!-- Count Value -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Count Value</label>
                    <input type="number"
                           data-branch-qc-count-value
                           value="0"
                           min="0"
                           class="w-full px-3 py-2 text-sm font-mono border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"
                           placeholder="0" />
                  </div>
                </div>
```

- [ ] **Step 2: Verify in browser**

Open branch modal, switch to "Query Count" tab. Confirm:
- Entity selector has proper uppercase label and unified input styling
- WHERE section has proper label
- Count operator and count value are on separate stacked rows with labels
- All inputs use amber focus rings and `rounded-lg`

---

### Task 6: Branch Manager — Update Toggle Class Swapping and Selector

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js:52-61,113-121,1113`

- [ ] **Step 1: Update openBranchModal reset classes**

In `openBranchModal()`, replace the toggle reset logic (lines 52-61):

```javascript
// OLD:
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

// NEW:
          // Reset condition type toggle to "Field Condition"
          const toggleContainer = modal.querySelector("[data-condition-type-toggle]")
          if (toggleContainer) {
            toggleContainer.querySelectorAll("button").forEach(btn => {
              if (btn.dataset.conditionType === "field") {
                btn.classList.remove("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
                btn.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
              } else {
                btn.classList.remove("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
                btn.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
              }
            })
          }
```

- [ ] **Step 2: Update switchBranchConditionType classes**

In `switchBranchConditionType()`, replace the toggle style logic (lines 113-121):

```javascript
// OLD:
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

// NEW:
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
```

- [ ] **Step 3: Fix the active toggle detection selector**

In `_collectBranchConditionFromModal()`, update the CSS selector (line 1113):

```javascript
// OLD:
    const activeToggle = modal.querySelector("[data-condition-type-toggle] button.bg-amber-200")

// NEW:
    const activeToggle = modal.querySelector("[data-condition-type-toggle] button.bg-white")
```

- [ ] **Step 4: Verify in browser**

Open branch modal:
1. Confirm "Field Condition" is active by default with white bg/shadow
2. Click "Query Count" — it becomes active, "Field Condition" becomes gray
3. Click "Field Condition" again — it switches back
4. Fill in a branch name, switch to "Query Count", select an entity, add a filter, set count > 0
5. Click "Add Branch" — confirm the branch is added with a query_count condition badge

---

### Task 7: Step Modal Advanced Section — Unify Labels and Inputs

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:107-157`

- [ ] **Step 1: Update advanced section labels and inputs**

In `buildStepModalTemplate()`, replace the advanced section body (lines ~116-157):

```javascript
// OLD:
                <div data-step-advanced-body class="hidden px-3 pb-3 space-y-3 border-t border-slate-200">
                  <!-- Retry Count -->
                  <div class="pt-3">
                    <label class="block text-xs font-medium text-slate-600 mb-1">Retry Count</label>
                    <input type="number"
                           data-step-modal-retry-count
                           min="0" max="5" value="0"
                           class="w-full px-3 py-1.5 text-sm border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">
                    <p class="mt-0.5 text-[10px] text-slate-400">Number of retries on failure (0 = no retry)</p>
                  </div>

                  <!-- Retry Backoff -->
                  <div>
                    <label class="block text-xs font-medium text-slate-600 mb-1">Retry Backoff</label>
                    <select data-step-modal-retry-backoff
                            class="w-full px-3 py-1.5 text-sm bg-white border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">
                      <option value="none" selected>None</option>
                      <option value="linear">Linear</option>
                      <option value="exponential">Exponential</option>
                    </select>
                  </div>

                  <!-- Timeout -->
                  <div>
                    <label class="block text-xs font-medium text-slate-600 mb-1">Timeout (seconds)</label>
                    <input type="number"
                           data-step-modal-timeout
                           min="0" value="0"
                           class="w-full px-3 py-1.5 text-sm border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">
                    <p class="mt-0.5 text-[10px] text-slate-400">0 = no timeout</p>
                  </div>

                  <!-- Guard Condition -->
                  <div>
                    <label class="block text-xs font-medium text-slate-600 mb-1">Guard Condition</label>
                    <input type="text"
                           data-step-modal-guard-condition
                           placeholder='e.g., ctx[:role] == "admin"'
                           class="w-full px-3 py-1.5 text-sm border border-slate-200 rounded-md shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">
                    <p class="mt-0.5 text-[10px] text-slate-400">Ruby expression; step only runs when truthy</p>
                  </div>
                </div>

// NEW:
                <div data-step-advanced-body class="hidden px-3 pb-3 space-y-3 border-t border-slate-200">
                  <!-- Retry Count -->
                  <div class="pt-3">
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Retry Count</label>
                    <input type="number"
                           data-step-modal-retry-count
                           min="0" max="5" value="0"
                           class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                    <p class="mt-0.5 text-[10px] text-slate-400">Number of retries on failure (0 = no retry)</p>
                  </div>

                  <!-- Retry Backoff -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Retry Backoff</label>
                    <select data-step-modal-retry-backoff
                            class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                      <option value="none" selected>None</option>
                      <option value="linear">Linear</option>
                      <option value="exponential">Exponential</option>
                    </select>
                  </div>

                  <!-- Timeout -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Timeout (seconds)</label>
                    <input type="number"
                           data-step-modal-timeout
                           min="0" value="0"
                           class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                    <p class="mt-0.5 text-[10px] text-slate-400">0 = no timeout</p>
                  </div>

                  <!-- Guard Condition -->
                  <div>
                    <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">Guard Condition</label>
                    <input type="text"
                           data-step-modal-guard-condition
                           placeholder='e.g., ctx[:role] == "admin"'
                           class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                    <p class="mt-0.5 text-[10px] text-slate-400">Ruby expression; step only runs when truthy</p>
                  </div>
                </div>
```

- [ ] **Step 2: Verify in browser**

Open property editor for a Process element, click "+ Add Step" to open step modal, expand "Advanced" section. Confirm:
- All 4 labels use uppercase tracking-wide style with text-slate-500
- All inputs use py-2, rounded-lg, ring-2 focus style
- Helper text unchanged
- Accordion toggle and border unchanged

---

### Task 8: Branch Name Field — Unify with Modal Styling

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:567-574`

While reviewing the branch modal body, the "Branch Name" field uses different styling from the other fields. Unify it.

- [ ] **Step 1: Update branch name field styling**

Replace lines ~567-574:

```javascript
// OLD:
              <!-- Branch Name -->
              <div class="mb-3">
                <label class="block text-[10px] font-medium text-slate-500 mb-1 tracking-wide uppercase">Branch Name</label>
                <input type="text"
                       data-branch-name
                       placeholder="e.g. Active, Pending, Rejected..."
                       class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
              </div>

// NEW:
              <!-- Branch Name -->
              <div>
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">
                  Branch Name
                  <span class="text-red-400 normal-case">*</span>
                </label>
                <input type="text"
                       data-branch-name
                       placeholder="e.g. Active, Pending, Rejected..."
                       class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
              </div>
```

- [ ] **Step 2: Verify in browser**

Open branch modal. Confirm:
- Branch Name field uses same label size and input styling as the other fields
- Has required asterisk indicator
- Amber focus ring matches other branch modal inputs

---

### Task 9: Final Cross-Check

- [ ] **Step 1: Full regression test**

In the browser:
1. Open a **Process** element → click "Steps" tab → click "+ Add Step"
   - Step modal: verify header, body, footer, and advanced section styling
   - Add a step with keyword params → verify step item renders correctly
2. Open a **Decision** element → click "Branches" tab → click "Add Branch"
   - Branch modal: verify header (white bg, amber icon), body (all fields stacked), footer (matching step modal)
   - Switch condition type toggle back and forth → verify segmented control works
   - Fill in a field condition → click "Add Branch" → verify branch item renders with condition badge
   - Open modal again → switch to Query Count → select entity → add filter → set count → add branch → verify query_count badge
3. Close sidebar → reopen each element type → verify no regressions in tab switching or form rendering

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/branch_manager.js
git commit -m "refactor: unify property editor modal styling and redesign condition builder

Align branch modal shell with step modal (backdrop, corners, header, footer, buttons).
Replace cramped inline condition fields with stacked labeled layout.
Replace tiny condition type pills with segmented control.
Unify step modal advanced section labels and inputs."
```

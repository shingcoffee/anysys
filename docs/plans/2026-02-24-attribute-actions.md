# Attribute Actions Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add modal width fix, view/copy actions, and inline delete confirmation to the entity attribute list.

**Architecture:** All three features are purely front-end. The view modal is a new partial rendered alongside the existing add-attribute modal. Copy pre-fills the existing modal. Delete confirm uses hidden/visible toggle of two inline button states inside the row. No model or controller changes needed.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS

---

## Task 1: Widen the Add Attribute Modal

**Files:**
- Modify: `app/views/entities/_attribute_modal.html.erb`

**Step 1: Change max-w-md to max-w-xl**

On line 14, change:
```erb
<div class="relative bg-white rounded-lg shadow-xl w-full max-w-md">
```
to:
```erb
<div class="relative bg-white rounded-lg shadow-xl w-full max-w-xl">
```

`max-w-xl` = 576px. Selection option rows (Default + Label + Value + Remove) no longer overflow.

**Step 2: Verify modal renders**

Open the entity form in browser, click "Add Attribute", select a Dropdown type, add a couple of options — verify they display without overflow.

**Step 3: Commit**

```bash
git add app/views/entities/_attribute_modal.html.erb
git commit -m "fix: increase add attribute modal width to max-w-xl"
```

---

## Task 2: Create Attribute View Modal Partial

**Files:**
- Create: `app/views/entities/_attribute_view_modal.html.erb`
- Modify: `app/views/entities/_form.html.erb`

**Step 1: Create the view modal partial**

Create `app/views/entities/_attribute_view_modal.html.erb`:

```erb
<%# Attribute View Modal Partial %>
<div data-entity-form-target="viewModal"
     class="hidden fixed inset-0 z-50 overflow-y-auto"
     aria-labelledby="view-modal-title"
     role="dialog"
     aria-modal="true">

  <%# Backdrop %>
  <div class="fixed inset-0 bg-gray-900/50 transition-opacity"
       data-action="click->entity-form#closeViewModal"></div>

  <%# Modal Panel %>
  <div class="flex min-h-full items-center justify-center p-4">
    <div class="relative bg-white rounded-lg shadow-xl w-full max-w-xl">

      <%# Modal Header %>
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-gray-900" id="view-modal-title">Attribute Details</h3>
          <button type="button"
                  data-action="click->entity-form#closeViewModal"
                  class="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded transition-colors">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <%# Modal Body %>
      <div class="px-6 py-4">
        <div data-entity-form-target="viewModalContent" class="space-y-4">
        </div>
      </div>

      <%# Modal Footer %>
      <div class="px-6 py-4 bg-gray-50 rounded-b-lg flex justify-end">
        <button type="button"
                data-action="click->entity-form#closeViewModal"
                class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg transition-all hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
          Close
        </button>
      </div>
    </div>
  </div>
</div>
```

**Step 2: Render view modal in entity form**

In `app/views/entities/_form.html.erb`, after line 105 (`<%= render "entities/attribute_modal" %>`), add:

```erb
  <%# Attribute View Modal %>
  <%= render "entities/attribute_view_modal" %>
```

**Step 3: Commit**

```bash
git add app/views/entities/_attribute_view_modal.html.erb app/views/entities/_form.html.erb
git commit -m "feat: add attribute view modal partial"
```

---

## Task 3: Add View Modal Controller Logic

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add new Stimulus targets**

Add `"viewModal"` and `"viewModalContent"` to the static targets array (after `"configMultiple"`):

```javascript
static targets = [
  // ... existing targets ...
  "configMultiple",
  "viewModal",
  "viewModalContent"
]
```

**Step 2: Update handleKeydown to close view modal on Escape**

Replace the existing `handleKeydown` method:

```javascript
handleKeydown(event) {
  if (event.key === "Escape") {
    if (this.hasViewModalTarget && !this.viewModalTarget.classList.contains(CSS.hidden)) {
      this.closeViewModal()
    } else if (this.isModalOpen) {
      this.closeModal()
    }
  }
}
```

**Step 3: Add viewAttribute and closeViewModal methods**

Add after the `hideAllConfigContainers` method:

```javascript
viewAttribute(event) {
  event.preventDefault()
  event.stopPropagation()

  const row = event.target.closest("[data-attribute-item]")
  if (!row) return

  const attribute = this.extractAttributeFromRow(row)
  if (!attribute) return

  if (this.hasViewModalContentTarget) {
    this.viewModalContentTarget.innerHTML = this.buildAttributeViewHtml(attribute)
  }

  if (this.hasViewModalTarget) {
    this.viewModalTarget.classList.remove(CSS.hidden)
    document.body.style.overflow = CSS.hidden
  }
}

closeViewModal(event) {
  if (event) {
    event.preventDefault()
    event.stopPropagation()
  }

  if (this.hasViewModalTarget) {
    this.viewModalTarget.classList.add(CSS.hidden)
    document.body.style.overflow = ""
  }
}
```

**Step 4: Add buildAttributeViewHtml and buildConfigViewHtml methods**

Add in the HTML Builders section (after `buildTruncatedDescriptionHtml`):

```javascript
buildAttributeViewHtml({ name, name_slug, type, html_type, description, validators, config }) {
  const displayType = this.formatTypeName(type)
  const displayHtmlType = this.formatHtmlTypeName(html_type || "text")
  const configHtml = this.buildConfigViewHtml(config, html_type)

  const validatorsHtml = validators?.length
    ? `<div>
        <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-1">Validators</p>
        ${this.buildValidatorBadgesHtml(validators)}
      </div>`
    : ""

  const configSection = configHtml
    ? `<div>
        <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-2">Configuration</p>
        ${configHtml}
      </div>`
    : ""

  const descriptionSection = description
    ? `<div>
        <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-1">Description</p>
        <p class="text-sm text-gray-700">${escapeHtml(description)}</p>
      </div>`
    : ""

  return `
    <dl class="space-y-4">
      <div class="grid grid-cols-2 gap-4">
        <div>
          <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-1">Name</p>
          <p class="text-sm font-medium text-gray-900">${escapeHtml(name)}</p>
        </div>
        <div>
          <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-1">Name Slug</p>
          <code class="text-xs text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded font-mono">${escapeHtml(name_slug)}</code>
        </div>
        <div>
          <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-1">Type</p>
          <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium text-gray-700 bg-gray-200 rounded">${escapeHtml(displayType)}</span>
        </div>
        <div>
          <p class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-1">HTML Type</p>
          <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium text-emerald-700 bg-emerald-100 rounded">${escapeHtml(displayHtmlType)}</span>
        </div>
      </div>
      ${validatorsHtml}
      ${configSection}
      ${descriptionSection}
    </dl>
  `
}

buildConfigViewHtml(config, htmlType) {
  if (!config) return null

  const configType = CONFIG_TYPE_MAP[htmlType]

  if (configType === "selection" && config.options?.length) {
    const rows = config.options.map(opt => `
      <tr class="border-b border-gray-100 last:border-0">
        <td class="py-1 pr-4 text-sm text-gray-900">${escapeHtml(opt.label || "")}</td>
        <td class="py-1 pr-4"><code class="text-xs font-mono text-gray-600">${escapeHtml(opt.value || "")}</code></td>
        <td class="py-1 text-sm">${opt.default ? '<span class="text-xs text-indigo-600 font-medium">Default</span>' : ""}</td>
      </tr>
    `).join("")

    return `
      <table class="w-full">
        <thead>
          <tr>
            <th class="pb-1 text-left text-xs font-medium text-gray-500">Label</th>
            <th class="pb-1 text-left text-xs font-medium text-gray-500">Value</th>
            <th class="pb-1 text-left text-xs font-medium text-gray-500">Default</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `
  }

  if (configType === "numeric") {
    const parts = []
    if (config.min !== null && config.min !== undefined) parts.push(`Min: ${config.min}`)
    if (config.max !== null && config.max !== undefined) parts.push(`Max: ${config.max}`)
    if (config.step !== null && config.step !== undefined) parts.push(`Step: ${config.step}`)
    return parts.length ? `<p class="text-sm text-gray-700">${parts.join(" · ")}</p>` : null
  }

  if (configType === "textarea" && config.rows) {
    return `<p class="text-sm text-gray-700">Rows: ${config.rows}</p>`
  }

  if (configType === "file") {
    const parts = []
    if (config.accept) parts.push(`Accept: ${escapeHtml(config.accept)}`)
    if (config.multiple) parts.push("Multiple: Yes")
    return parts.length ? `<p class="text-sm text-gray-700">${parts.join(" · ")}</p>` : null
  }

  return null
}
```

**Step 5: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add view attribute modal controller logic"
```

---

## Task 4: Add Copy Attribute Support

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add copyAttribute method**

Add after `viewAttribute` / `closeViewModal`:

```javascript
copyAttribute(event) {
  event.preventDefault()
  event.stopPropagation()

  const row = event.target.closest("[data-attribute-item]")
  if (!row) return

  const attribute = this.extractAttributeFromRow(row)
  if (!attribute) return

  this.prefillModalWithAttribute(attribute)

  if (this.hasModalTarget) {
    this.modalTarget.classList.remove(CSS.hidden)
    document.body.style.overflow = CSS.hidden
    this.focusModalNameField()
  }
}
```

**Step 2: Add prefillModalWithAttribute method**

Add after `copyAttribute`:

```javascript
prefillModalWithAttribute({ name, name_slug, type, html_type, description, validators, config }) {
  // Set basic fields
  if (this.hasModalNameTarget) this.modalNameTarget.value = name || ""
  if (this.hasModalNameSlugTarget) this.modalNameSlugTarget.value = name_slug || ""
  if (this.hasModalTypeTarget) this.modalTypeTarget.value = type || ""
  if (this.hasModalHtmlTypeTarget) this.modalHtmlTypeTarget.value = html_type || "text"
  if (this.hasModalDescriptionTarget) this.modalDescriptionTarget.value = description || ""

  // Restore validators
  if (this.hasValidatorsContainerTarget) {
    this.validatorsContainerTarget.innerHTML = ""
    if (validators?.length) {
      validators.forEach(v => this.appendValidatorBadge(v, getValidatorLabel(v) || v))
    }
  }

  // Reset config section, then re-populate
  this.hideConfigSection()
  if (this.hasOptionsContainerTarget) this.optionsContainerTarget.innerHTML = ""
  this.optionIndex = 0

  if (config) {
    const configType = CONFIG_TYPE_MAP[html_type]
    if (!configType) return

    // Show section and correct container (without auto-add)
    if (this.hasOptionsSectionTarget) this.optionsSectionTarget.classList.remove(CSS.hidden)
    this.hideAllConfigContainers()
    if (this[`has${this.capitalize(configType)}ConfigTarget`]) {
      this[`${configType}ConfigTarget`].classList.remove(CSS.hidden)
    }

    if (configType === "selection" && config.options?.length) {
      config.options.forEach(opt => {
        const html = this.buildOptionRowHtml(this.optionIndex)
        this.optionsContainerTarget.insertAdjacentHTML("beforeend", html)
        const newRow = this.optionsContainerTarget.lastElementChild
        const labelEl = newRow.querySelector("[data-option-label]")
        const valueEl = newRow.querySelector("[data-option-value]")
        const defaultEl = newRow.querySelector("[data-option-default]")
        if (labelEl) labelEl.value = opt.label || ""
        if (valueEl) valueEl.value = opt.value || ""
        if (defaultEl) defaultEl.checked = opt.default || false
        this.optionIndex++
      })
    } else if (configType === "numeric") {
      if (this.hasConfigMinTarget) this.configMinTarget.value = config.min ?? ""
      if (this.hasConfigMaxTarget) this.configMaxTarget.value = config.max ?? ""
      if (this.hasConfigStepTarget) this.configStepTarget.value = config.step ?? ""
    } else if (configType === "textarea") {
      if (this.hasConfigRowsTarget) this.configRowsTarget.value = config.rows || ""
    } else if (configType === "file") {
      if (this.hasConfigAcceptTarget) this.configAcceptTarget.value = config.accept || ""
      if (this.hasConfigMultipleTarget) this.configMultipleTarget.checked = config.multiple || false
    }
  }
}
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add copy attribute with modal prefill"
```

---

## Task 5: Add Inline Delete Confirmation to JS Table Builder

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add confirmRemoveAttribute, executeRemoveAttribute, cancelRemoveAttribute methods**

Add after `removeAttribute`:

```javascript
confirmRemoveAttribute(event) {
  event.preventDefault()
  event.stopPropagation()

  const row = event.target.closest("[data-attribute-item]")
  if (!row) return

  const normalBtn = row.querySelector("[data-confirm-normal]")
  const pendingSpan = row.querySelector("[data-confirm-pending]")
  if (!normalBtn || !pendingSpan) return

  normalBtn.classList.add(CSS.hidden)
  pendingSpan.classList.remove(CSS.hidden)
}

executeRemoveAttribute(event) {
  event.preventDefault()
  event.stopPropagation()

  const row = event.target.closest("[data-attribute-item]")
  if (row) {
    row.remove()
    this.showEmptyStateIfNeeded()
    this.syncPropertySchema()
  }
}

cancelRemoveAttribute(event) {
  event.preventDefault()
  event.stopPropagation()

  const row = event.target.closest("[data-attribute-item]")
  if (!row) return

  const normalBtn = row.querySelector("[data-confirm-normal]")
  const pendingSpan = row.querySelector("[data-confirm-pending]")
  if (!normalBtn || !pendingSpan) return

  normalBtn.classList.remove(CSS.hidden)
  pendingSpan.classList.add(CSS.hidden)
}
```

**Step 2: Update buildAttributeRowHtml actions cell**

Replace the current actions `<td>` content (the delete button and hidden inputs) with the new structure that includes view, copy, and confirm-delete buttons. The hidden inputs remain unchanged.

Replace the actions `<td>` template string in `buildAttributeRowHtml`:

```javascript
      <td class="py-1.5 text-right">
        <div class="inline-flex items-center justify-end gap-0.5">
          <button type="button"
                  data-action="click->entity-form#viewAttribute"
                  class="p-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-md transition-colors"
                  title="View attribute">
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              <path stroke-linecap="round" stroke-linejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
            </svg>
          </button>
          <button type="button"
                  data-action="click->entity-form#copyAttribute"
                  class="p-1 text-gray-400 hover:text-indigo-500 hover:bg-indigo-50 rounded-md transition-colors"
                  title="Copy attribute">
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
          </button>
          <button type="button"
                  data-action="click->entity-form#confirmRemoveAttribute"
                  data-confirm-normal
                  class="attribute-remove p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors"
                  title="Remove attribute">
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>
          <span data-confirm-pending class="hidden items-center gap-0.5">
            <button type="button"
                    data-action="click->entity-form#executeRemoveAttribute"
                    class="p-1 text-red-500 hover:bg-red-100 rounded-md transition-colors"
                    title="Confirm remove">
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
              </svg>
            </button>
            <button type="button"
                    data-action="click->entity-form#cancelRemoveAttribute"
                    class="p-1 text-gray-400 hover:bg-gray-100 rounded-md transition-colors"
                    title="Cancel">
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </span>
        </div>
        <input type="hidden" name="attributes[${index}][name]" value="${escapeHtml(name)}" data-input="name">
        <input type="hidden" name="attributes[${index}][name_slug]" value="${escapeHtml(name_slug)}" data-input="name_slug">
        <input type="hidden" name="attributes[${index}][type]" value="${escapeHtml(type)}" data-input="type">
        <input type="hidden" name="attributes[${index}][html_type]" value="${escapeHtml(html_type || "text")}" data-input="html_type">
        <input type="hidden" name="attributes[${index}][description]" value="${escapeHtml(description)}" data-input="description">
        <input type="hidden" name="attributes[${index}][validators]" value="${escapeHtml(validatorsJson)}" data-input="validators">
        <input type="hidden" name="attributes[${index}][config]" value="${escapeHtml(configJson)}" data-input="config">
      </td>
```

Also update the table header in `buildTableHtml` to widen the actions column from `w-[10%]` to `w-[14%]` and reduce description from `w-[22%]` to `w-[18%]`:

```javascript
<th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[18%]">Description</th>
<th class="pb-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider w-[14%]">Actions</th>
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add inline delete confirm and view/copy buttons to table builder"
```

---

## Task 6: Update Server-Rendered Attributes Table Partial

**Files:**
- Modify: `app/views/entities/_attributes_table.html.erb`

**Step 1: Update header column widths**

Change the Description and Actions column widths to match the JS table builder (from Task 5):
- Description: `w-[22%]` → `w-[18%]`
- Actions: `w-[10%]` → `w-[14%]`

**Step 2: Replace the actions cell content**

Replace the current `<% if editable %>` actions `<td>` block with the new structure matching the JS builder from Task 5:

```erb
<% if editable %>
  <td class="py-1.5 text-right">
    <div class="inline-flex items-center justify-end gap-0.5">
      <button type="button"
              data-action="click->entity-form#viewAttribute"
              class="p-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-md transition-colors"
              title="View attribute">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
        </svg>
      </button>
      <button type="button"
              data-action="click->entity-form#copyAttribute"
              class="p-1 text-gray-400 hover:text-indigo-500 hover:bg-indigo-50 rounded-md transition-colors"
              title="Copy attribute">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
      </button>
      <button type="button"
              data-action="click->entity-form#confirmRemoveAttribute"
              data-confirm-normal
              class="attribute-remove p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors"
              title="Remove attribute">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
      </button>
      <span data-confirm-pending class="hidden items-center gap-0.5">
        <button type="button"
                data-action="click->entity-form#executeRemoveAttribute"
                class="p-1 text-red-500 hover:bg-red-100 rounded-md transition-colors"
                title="Confirm remove">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        </button>
        <button type="button"
                data-action="click->entity-form#cancelRemoveAttribute"
                class="p-1 text-gray-400 hover:bg-gray-100 rounded-md transition-colors"
                title="Cancel">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </span>
    </div>
    <%# Hidden Form Inputs %>
    <input type="hidden" name="attributes[<%= index %>][name]" value="<%= attr["name"] %>" data-input="name">
    <input type="hidden" name="attributes[<%= index %>][name_slug]" value="<%= attr["name_slug"] %>" data-input="name_slug">
    <input type="hidden" name="attributes[<%= index %>][type]" value="<%= attr["type"] %>" data-input="type">
    <input type="hidden" name="attributes[<%= index %>][html_type]" value="<%= attr["html_type"] || "text" %>" data-input="html_type">
    <input type="hidden" name="attributes[<%= index %>][description]" value="<%= attr["description"] %>" data-input="description">
    <input type="hidden" name="attributes[<%= index %>][validators]" value="<%= Array(validators).to_json %>" data-input="validators">
    <input type="hidden" name="attributes[<%= index %>][config]" value="<%= attr["config"]&.to_json.presence || "null" %>" data-input="config">
  </td>
<% end %>
```

**Step 3: Commit**

```bash
git add app/views/entities/_attributes_table.html.erb
git commit -m "feat: update attributes table with view/copy/confirm-delete actions"
```

---

## Summary

This plan adds:
1. Wider modal (max-w-xl) to prevent selection option overflow
2. View modal (read-only) showing all attribute details including config
3. Copy action pre-filling the Add Attribute modal with the copied attribute's data
4. Inline delete confirmation using toggled visible/hidden button states (no browser dialog)

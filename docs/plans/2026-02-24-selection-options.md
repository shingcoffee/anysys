# Selection Options Feature Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-expand an options configuration section when selection-type HTML fields (Dropdown, Radio, Checkbox) are chosen in the Add Attribute modal.

**Architecture:** Extend existing modal with a collapsible section controlled by Stimulus. Options stored as JSON array in attribute data alongside existing fields.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS, ViewComponent, RSpec

---

## Task 1: Add selection_type? Helper to HtmlTypeOptions

**Files:**
- Modify: `app/models/concerns/html_type_options.rb`
- Test: `spec/models/concerns/html_type_options_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/concerns/html_type_options_spec.rb`:

```ruby
describe '.selection_type?' do
  it 'returns true for select' do
    expect(HtmlTypeOptions.selection_type?('select')).to be true
  end

  it 'returns true for radio' do
    expect(HtmlTypeOptions.selection_type?('radio')).to be true
  end

  it 'returns true for checkbox' do
    expect(HtmlTypeOptions.selection_type?('checkbox')).to be true
  end

  it 'returns false for text' do
    expect(HtmlTypeOptions.selection_type?('text')).to be false
  end

  it 'returns false for number' do
    expect(HtmlTypeOptions.selection_type?('number')).to be false
  end

  it 'returns false for nil' do
    expect(HtmlTypeOptions.selection_type?(nil)).to be false
  end

  it 'returns false for blank string' do
    expect(HtmlTypeOptions.selection_type?('')).to be false
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb -v`
Expected: FAIL with "undefined method `selection_type?'"

**Step 3: Write minimal implementation**

Add to `app/models/concerns/html_type_options.rb` inside `class << self`:

```ruby
SELECTION_TYPES = %w[select radio checkbox].freeze

def selection_type?(value)
  return false if value.blank?
  SELECTION_TYPES.include?(value.to_s)
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/concerns/html_type_options.rb spec/models/concerns/html_type_options_spec.rb
git commit -m "feat: add selection_type? helper to HtmlTypeOptions"
```

---

## Task 2: Add Options Section HTML to Attribute Modal

**Files:**
- Modify: `app/views/entities/_attribute_modal.html.erb`

**Step 1: Add the options section HTML**

After the HTML Type Field section (after line 84, before the Validators Field), add:

```erb
<%# Selection Options Section (shown only for dropdown/radio/checkbox) %>
<div data-entity-form-target="optionsSection"
     class="hidden border border-gray-200 rounded-lg p-4 bg-gray-50">
  <label class="block text-sm font-medium text-gray-700 mb-3">
    Selection Options
    <span class="text-gray-400 font-normal text-xs">(define available choices)</span>
  </label>

  <%# Options container %>
  <div data-entity-form-target="optionsContainer" class="space-y-2 mb-3">
    <%# Option rows will be added dynamically %>
  </div>

  <%# Add option button %>
  <button type="button"
          data-action="click->entity-form#addOption"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-indigo-600 bg-white border border-indigo-200 rounded-md hover:bg-indigo-50 transition-colors">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
    </svg>
    Add Option
  </button>
</div>
```

**Step 2: Add change action to HTML Type select**

Modify the HTML Type select (around line 75) to add data-action:

```erb
<select data-entity-form-target="modalHtmlType"
        data-action="change->entity-form#htmlTypeChanged"
        class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-colors bg-white" required>
```

**Step 3: Verify modal renders without errors**

Run: `bin/rails server` and navigate to entity form page
Expected: Modal opens without errors, options section hidden by default

**Step 4: Commit**

```bash
git add app/views/entities/_attribute_modal.html.erb
git commit -m "feat: add options section HTML to attribute modal"
```

---

## Task 3: Add Stimulus Targets and htmlTypeChanged Method

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add new targets to static targets array**

Update the static targets array (around line 21-36) to include:

```javascript
static targets = [
  "attributesContainer",
  "attributesTable",
  "emptyState",
  "propertySchema",
  "modal",
  "modalName",
  "modalNameSlug",
  "modalType",
  "modalHtmlType",
  "modalDescription",
  "modalValidatorSelect",
  "validatorsContainer",
  "entityName",
  "entityNameSlug",
  "optionsSection",
  "optionsContainer"
]
```

**Step 2: Add SELECTION_TYPES constant**

Add after the CSS constant (around line 12):

```javascript
const SELECTION_TYPES = ["select", "radio", "checkbox"]
```

**Step 3: Add htmlTypeChanged method**

Add after the updateAttributeNameSlug method (around line 118):

```javascript
// =========================================================================
// HTML Type Change Handler
// =========================================================================

htmlTypeChanged() {
  if (!this.hasModalHtmlTypeTarget || !this.hasOptionsSectionTarget) return

  const htmlType = this.modalHtmlTypeTarget.value
  const isSelectionType = SELECTION_TYPES.includes(htmlType)

  if (isSelectionType) {
    this.showOptionsSection()
  } else {
    this.hideOptionsSection()
  }
}

showOptionsSection() {
  this.optionsSectionTarget.classList.remove("hidden")
}

hideOptionsSection() {
  this.optionsSectionTarget.classList.add("hidden")
}
```

**Step 4: Verify in browser**

Run: Change HTML Type dropdown between selection and non-selection types
Expected: Options section shows/hides accordingly

**Step 5: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add htmlTypeChanged handler for options section toggle"
```

---

## Task 4: Implement addOption Method

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add option index tracking**

Add to connect() method after existing lines:

```javascript
this.optionIndex = 0
```

**Step 2: Add addOption method**

Add after hideOptionsSection method:

```javascript
addOption(event) {
  if (event) {
    event.preventDefault()
    event.stopPropagation()
  }

  if (!this.hasOptionsContainerTarget) return

  const html = this.buildOptionRowHtml(this.optionIndex)
  this.optionsContainerTarget.insertAdjacentHTML("beforeend", html)
  this.optionIndex++

  // Focus the label input of the new row
  const newRow = this.optionsContainerTarget.lastElementChild
  const labelInput = newRow.querySelector('input[data-option-label]')
  if (labelInput) labelInput.focus()
}
```

**Step 3: Add buildOptionRowHtml method**

Add in the HTML Builders section:

```javascript
buildOptionRowHtml(index) {
  const htmlType = this.hasModalHtmlTypeTarget ? this.modalHtmlTypeTarget.value : "select"
  const isCheckbox = htmlType === "checkbox"
  const defaultInputType = isCheckbox ? "checkbox" : "radio"
  const defaultInputName = isCheckbox ? `option_default_${index}` : "option_default"

  return `
    <div data-option-item class="flex items-center gap-2 p-2 bg-white border border-gray-200 rounded-md">
      <label class="flex items-center gap-1.5 text-xs text-gray-500 shrink-0">
        <input type="${defaultInputType}"
               name="${defaultInputName}"
               data-option-default
               class="w-4 h-4 text-indigo-600 border-gray-300 focus:ring-indigo-500">
        <span>Default</span>
      </label>
      <input type="text"
             data-option-label
             placeholder="Label"
             class="flex-1 px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
      <input type="text"
             data-option-value
             placeholder="Value"
             class="flex-1 px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
      <button type="button"
              data-action="click->entity-form#removeOption"
              class="p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded transition-colors"
              title="Remove option">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  `
}
```

**Step 4: Verify in browser**

Run: Select "Dropdown", click "Add Option" multiple times
Expected: Option rows appear with label/value inputs and default radio buttons

**Step 5: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: implement addOption method with dynamic row creation"
```

---

## Task 5: Implement removeOption Method

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add removeOption method**

Add after addOption method:

```javascript
removeOption(event) {
  event.preventDefault()
  event.stopPropagation()

  const row = event.target.closest("[data-option-item]")
  if (row) row.remove()
}
```

**Step 2: Verify in browser**

Run: Add options, then click the X button on each
Expected: Option rows are removed

**Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: implement removeOption method"
```

---

## Task 6: Collect Options Data in Modal

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add getSelectedOptions method**

Add after getSelectedValidators method:

```javascript
getSelectedOptions() {
  if (!this.hasOptionsContainerTarget) return []

  const htmlType = this.hasModalHtmlTypeTarget ? this.modalHtmlTypeTarget.value : ""
  if (!SELECTION_TYPES.includes(htmlType)) return []

  return Array.from(
    this.optionsContainerTarget.querySelectorAll("[data-option-item]")
  ).map(item => {
    const label = item.querySelector("[data-option-label]")?.value.trim() || ""
    const value = item.querySelector("[data-option-value]")?.value.trim() || ""
    const defaultInput = item.querySelector("[data-option-default]")
    const isDefault = defaultInput?.checked || false

    return { label, value, default: isDefault }
  }).filter(opt => opt.label || opt.value) // Filter out empty rows
}
```

**Step 2: Update collectModalData to include options**

Modify the collectModalData method to add options:

```javascript
collectModalData() {
  const name = this.getTargetValue("modalName")
  const htmlType = this.getTargetValue("modalHtmlType") || "text"

  return {
    name,
    name_slug: this.getTargetValue("modalNameSlug") || this.generateSlug(name),
    type: this.getTargetValue("modalType") || "text",
    html_type: htmlType,
    description: this.getTargetValue("modalDescription"),
    validators: this.getSelectedValidators(),
    options: SELECTION_TYPES.includes(htmlType) ? this.getSelectedOptions() : null
  }
}
```

**Step 3: Verify in browser console**

Run: Add attribute with options, check console for collected data
Expected: Options array included in attribute data

**Step 4: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: collect options data when adding attribute"
```

---

## Task 7: Store Options in Hidden Field

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update buildAttributeRowHtml to include options**

Modify the buildAttributeRowHtml method signature and add options hidden field:

```javascript
buildAttributeRowHtml({ name, name_slug, type, html_type, description, validators, options }) {
  const index = this.attributeIndex
  const displayType = this.formatTypeName(type)
  const displayHtmlType = this.formatHtmlTypeName(html_type || "text")
  const validatorsJson = JSON.stringify(validators)
  const optionsJson = JSON.stringify(options || [])
  const validatorBadges = this.buildValidatorBadgesHtml(validators)
  const descriptionHtml = this.buildTruncatedDescriptionHtml(description)

  return `
    <tr data-attribute-item class="attribute-item">
      <td class="py-1.5 text-sm font-medium text-gray-900" data-field="name">${escapeHtml(name)}</td>
      <td class="py-1.5">
        <code class="text-xs text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded font-mono" data-field="name_slug">${escapeHtml(name_slug)}</code>
      </td>
      <td class="py-1.5">
        <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium text-gray-700 bg-gray-200 rounded" data-field="type" data-full-type="${escapeHtml(type)}">${escapeHtml(displayType)}</span>
      </td>
      <td class="py-1.5">
        <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium text-emerald-700 bg-emerald-100 rounded" data-field="html_type">${escapeHtml(displayHtmlType)}</span>
      </td>
      <td class="py-1.5">${validatorBadges}</td>
      <td class="py-1.5 text-sm text-gray-600" data-field="description">${descriptionHtml}</td>
      <td class="py-1.5 text-right">
        <button type="button"
                data-action="click->entity-form#removeAttribute"
                class="attribute-remove p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors"
                title="Remove attribute">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
        <input type="hidden" name="attributes[${index}][name]" value="${escapeHtml(name)}" data-input="name">
        <input type="hidden" name="attributes[${index}][name_slug]" value="${escapeHtml(name_slug)}" data-input="name_slug">
        <input type="hidden" name="attributes[${index}][type]" value="${escapeHtml(type)}" data-input="type">
        <input type="hidden" name="attributes[${index}][html_type]" value="${escapeHtml(html_type || "text")}" data-input="html_type">
        <input type="hidden" name="attributes[${index}][description]" value="${escapeHtml(description)}" data-input="description">
        <input type="hidden" name="attributes[${index}][validators]" value="${escapeHtml(validatorsJson)}" data-input="validators">
        <input type="hidden" name="attributes[${index}][options]" value="${escapeHtml(optionsJson)}" data-input="options">
      </td>
    </tr>
  `
}
```

**Step 2: Update extractAttributeFromRow to include options**

Modify the extractAttributeFromRow method:

```javascript
extractAttributeFromRow(row) {
  const getValue = (type) => row.querySelector(`input[data-input="${type}"]`)?.value.trim() || ""

  const name = getValue("name")
  if (!name) return null

  return {
    name,
    name_slug: getValue("name_slug") || this.generateSlug(name),
    type: getValue("type") || "text",
    html_type: getValue("html_type") || "text",
    description: getValue("description"),
    validators: this.parseValidatorsJson(getValue("validators")),
    options: this.parseOptionsJson(getValue("options"))
  }
}
```

**Step 3: Add parseOptionsJson helper**

Add after parseValidatorsJson method:

```javascript
parseOptionsJson(json) {
  if (!json) return null

  try {
    const parsed = JSON.parse(json)
    return Array.isArray(parsed) && parsed.length > 0 ? parsed : null
  } catch {
    return null
  }
}
```

**Step 4: Verify form submission includes options**

Run: Add attribute with options, submit form, check params
Expected: Options JSON included in form submission

**Step 5: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: store and extract options in attribute row"
```

---

## Task 8: Reset Options Section on Modal Close

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update resetModalFields to clear options**

Add to the resetModalFields method:

```javascript
resetModalFields() {
  if (this.hasModalNameTarget) this.modalNameTarget.value = ""
  if (this.hasModalNameSlugTarget) this.modalNameSlugTarget.value = ""
  if (this.hasModalTypeTarget) this.modalTypeTarget.selectedIndex = 0
  if (this.hasModalHtmlTypeTarget) this.modalHtmlTypeTarget.selectedIndex = 0
  if (this.hasModalDescriptionTarget) this.modalDescriptionTarget.value = ""
  if (this.hasModalValidatorSelectTarget) this.modalValidatorSelectTarget.selectedIndex = 0
  if (this.hasValidatorsContainerTarget) this.validatorsContainerTarget.innerHTML = ""

  // Reset options section
  if (this.hasOptionsContainerTarget) this.optionsContainerTarget.innerHTML = ""
  if (this.hasOptionsSectionTarget) this.optionsSectionTarget.classList.add("hidden")
  this.optionIndex = 0
}
```

**Step 2: Verify in browser**

Run: Add options, close modal, reopen modal
Expected: Options section is empty and hidden

**Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: reset options section when modal closes"
```

---

## Task 9: Add Smooth Animation for Options Section

**Files:**
- Modify: `app/views/entities/_attribute_modal.html.erb`
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update options section HTML for animation**

Update the options section div classes:

```erb
<div data-entity-form-target="optionsSection"
     class="hidden border border-gray-200 rounded-lg p-4 bg-gray-50 transition-all duration-200 ease-in-out">
```

**Step 2: Update show/hide methods for smooth transition**

Replace showOptionsSection and hideOptionsSection:

```javascript
showOptionsSection() {
  if (!this.hasOptionsSectionTarget) return

  this.optionsSectionTarget.classList.remove("hidden")

  // Add first option row if empty
  if (this.hasOptionsContainerTarget && this.optionsContainerTarget.children.length === 0) {
    this.addOption()
  }
}

hideOptionsSection() {
  if (!this.hasOptionsSectionTarget) return
  this.optionsSectionTarget.classList.add("hidden")
}
```

**Step 3: Verify animation in browser**

Run: Toggle between selection and non-selection types
Expected: Options section shows/hides with transition, auto-adds first option row

**Step 4: Commit**

```bash
git add app/views/entities/_attribute_modal.html.erb app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add smooth animation and auto-add first option"
```

---

## Task 10: Final Integration Test

**Files:**
- Test manually in browser

**Step 1: Full workflow test**

1. Open Add Attribute modal
2. Select "Dropdown" as HTML Type
3. Verify options section expands with one empty row
4. Add label "Active", value "active", check Default
5. Click "Add Option"
6. Add label "Inactive", value "inactive"
7. Click "Add Attribute"
8. Verify attribute appears in table with options stored

**Step 2: Test type switching**

1. Open Add Attribute modal
2. Select "Radio Buttons" - verify options section shows
3. Add some options
4. Switch to "Text Input" - verify options section hides
5. Switch back to "Checkbox" - verify options section shows (options preserved)

**Step 3: Test default selection behavior**

1. For Dropdown/Radio: verify only one default can be selected (radio behavior)
2. For Checkbox: verify multiple defaults can be selected

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete selection options feature implementation"
```

---

## Summary

This implementation adds:
1. `HtmlTypeOptions.selection_type?` helper method
2. Collapsible options section in attribute modal
3. Dynamic add/remove option rows
4. Label + Value + Default for each option
5. Single default for dropdown/radio, multiple for checkbox
6. Options stored as JSON in attribute data
7. Smooth show/hide animation

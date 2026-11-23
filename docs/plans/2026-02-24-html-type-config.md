# HTML Type Configuration Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend attribute modal to show type-specific configuration sections for numeric, textarea, and file HTML types, building on existing selection options.

**Architecture:** Generalize existing options section into a unified config system. Single collapsible section with swappable content based on HTML type category. Store all type-specific config in a `config` object.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS, RSpec

---

## Task 1: Add Config Type Helpers to HtmlTypeOptions

**Files:**
- Modify: `app/models/concerns/html_type_options.rb`
- Test: `spec/models/concerns/html_type_options_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/models/concerns/html_type_options_spec.rb`:

```ruby
describe '.config_type_for' do
  it 'returns :selection for select' do
    expect(HtmlTypeOptions.config_type_for('select')).to eq(:selection)
  end

  it 'returns :selection for radio' do
    expect(HtmlTypeOptions.config_type_for('radio')).to eq(:selection)
  end

  it 'returns :selection for checkbox' do
    expect(HtmlTypeOptions.config_type_for('checkbox')).to eq(:selection)
  end

  it 'returns :numeric for number' do
    expect(HtmlTypeOptions.config_type_for('number')).to eq(:numeric)
  end

  it 'returns :numeric for range' do
    expect(HtmlTypeOptions.config_type_for('range')).to eq(:numeric)
  end

  it 'returns :textarea for textarea' do
    expect(HtmlTypeOptions.config_type_for('textarea')).to eq(:textarea)
  end

  it 'returns :file for file' do
    expect(HtmlTypeOptions.config_type_for('file')).to eq(:file)
  end

  it 'returns nil for text' do
    expect(HtmlTypeOptions.config_type_for('text')).to be_nil
  end

  it 'returns nil for email' do
    expect(HtmlTypeOptions.config_type_for('email')).to be_nil
  end

  it 'returns nil for nil input' do
    expect(HtmlTypeOptions.config_type_for(nil)).to be_nil
  end
end

describe '.configurable_type?' do
  it 'returns true for select' do
    expect(HtmlTypeOptions.configurable_type?('select')).to be true
  end

  it 'returns true for range' do
    expect(HtmlTypeOptions.configurable_type?('range')).to be true
  end

  it 'returns true for textarea' do
    expect(HtmlTypeOptions.configurable_type?('textarea')).to be true
  end

  it 'returns true for file' do
    expect(HtmlTypeOptions.configurable_type?('file')).to be true
  end

  it 'returns false for text' do
    expect(HtmlTypeOptions.configurable_type?('text')).to be false
  end

  it 'returns false for email' do
    expect(HtmlTypeOptions.configurable_type?('email')).to be false
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb -v`
Expected: FAIL with "undefined method"

**Step 3: Write minimal implementation**

Add to `app/models/concerns/html_type_options.rb` after SELECTION_TYPES:

```ruby
CONFIG_TYPES = {
  selection: %w[select radio checkbox],
  numeric: %w[number range],
  textarea: %w[textarea],
  file: %w[file]
}.freeze

def config_type_for(value)
  return nil if value.blank?
  CONFIG_TYPES.find { |_type, values| values.include?(value.to_s) }&.first
end

def configurable_type?(value)
  !config_type_for(value).nil?
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/concerns/html_type_options.rb spec/models/concerns/html_type_options_spec.rb
git commit -m "feat: add config_type_for and configurable_type? helpers"
```

---

## Task 2: Add Numeric Config HTML to Modal

**Files:**
- Modify: `app/views/entities/_attribute_modal.html.erb`

**Step 1: Add numeric config container inside optionsSection**

After the existing optionsContainer div (around line 97), add the numeric config container. First, wrap the existing options content in a container with `data-config-type="selection"`, then add numeric config:

Replace the content inside the optionsSection div with:

```erb
<%# Selection Options Content %>
<div data-entity-form-target="selectionConfig" data-config-type="selection" class="hidden">
  <label class="block text-sm font-medium text-gray-700 mb-3">
    Selection Options
    <span class="text-gray-400 font-normal text-xs">(define available choices)</span>
  </label>

  <div data-entity-form-target="optionsContainer" class="space-y-2 mb-3">
  </div>

  <button type="button"
          data-action="click->entity-form#addOption"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-indigo-600 bg-white border border-indigo-200 rounded-md hover:bg-indigo-50 transition-colors">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
    </svg>
    Add Option
  </button>
</div>

<%# Numeric Config Content %>
<div data-entity-form-target="numericConfig" data-config-type="numeric" class="hidden">
  <label class="block text-sm font-medium text-gray-700 mb-3">
    Numeric Settings
  </label>

  <div class="grid grid-cols-3 gap-3">
    <div>
      <label class="block text-xs text-gray-500 mb-1">Min</label>
      <input type="number"
             data-entity-form-target="configMin"
             placeholder="0"
             class="w-full px-2 py-1.5 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
    </div>
    <div>
      <label class="block text-xs text-gray-500 mb-1">Max</label>
      <input type="number"
             data-entity-form-target="configMax"
             placeholder="100"
             class="w-full px-2 py-1.5 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
    </div>
    <div>
      <label class="block text-xs text-gray-500 mb-1">Step</label>
      <input type="number"
             data-entity-form-target="configStep"
             placeholder="1"
             class="w-full px-2 py-1.5 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
    </div>
  </div>
</div>
```

**Step 2: Verify modal renders**

Run: `bin/rails server` and open modal
Expected: Modal renders without errors

**Step 3: Commit**

```bash
git add app/views/entities/_attribute_modal.html.erb
git commit -m "feat: add numeric config section to modal"
```

---

## Task 3: Add Textarea and File Config HTML

**Files:**
- Modify: `app/views/entities/_attribute_modal.html.erb`

**Step 1: Add textarea and file config containers**

After numericConfig div, add:

```erb
<%# Textarea Config Content %>
<div data-entity-form-target="textareaConfig" data-config-type="textarea" class="hidden">
  <label class="block text-sm font-medium text-gray-700 mb-3">
    Textarea Settings
  </label>

  <div>
    <label class="block text-xs text-gray-500 mb-1">Rows</label>
    <input type="number"
           data-entity-form-target="configRows"
           placeholder="3"
           min="1"
           max="20"
           class="w-24 px-2 py-1.5 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
  </div>
</div>

<%# File Config Content %>
<div data-entity-form-target="fileConfig" data-config-type="file" class="hidden">
  <label class="block text-sm font-medium text-gray-700 mb-3">
    File Upload Settings
  </label>

  <div class="space-y-3">
    <div>
      <label class="block text-xs text-gray-500 mb-1">Accepted File Types</label>
      <input type="text"
             data-entity-form-target="configAccept"
             placeholder=".pdf,.jpg,.png"
             class="w-full px-2 py-1.5 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
      <p class="mt-1 text-xs text-gray-400">Comma-separated extensions (e.g., .pdf,.jpg,.png)</p>
    </div>
    <div>
      <label class="flex items-center gap-2 text-sm text-gray-700">
        <input type="checkbox"
               data-entity-form-target="configMultiple"
               class="w-4 h-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500">
        Allow multiple files
      </label>
    </div>
  </div>
</div>
```

**Step 2: Verify modal renders**

Run: Refresh page and open modal
Expected: Modal renders without errors

**Step 3: Commit**

```bash
git add app/views/entities/_attribute_modal.html.erb
git commit -m "feat: add textarea and file config sections to modal"
```

---

## Task 4: Add New Stimulus Targets

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add config targets to static targets array**

Update static targets to include new config targets:

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
  "optionsContainer",
  "selectionConfig",
  "numericConfig",
  "textareaConfig",
  "fileConfig",
  "configMin",
  "configMax",
  "configStep",
  "configRows",
  "configAccept",
  "configMultiple"
]
```

**Step 2: Add CONFIG_TYPE_MAP constant**

Add after SELECTION_TYPES constant:

```javascript
const CONFIG_TYPE_MAP = {
  select: "selection",
  radio: "selection",
  checkbox: "selection",
  number: "numeric",
  range: "numeric",
  textarea: "textarea",
  file: "file"
}
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add config targets and CONFIG_TYPE_MAP constant"
```

---

## Task 5: Update htmlTypeChanged to Show Correct Config

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Replace htmlTypeChanged method**

Replace the existing htmlTypeChanged method:

```javascript
htmlTypeChanged() {
  if (!this.hasModalHtmlTypeTarget || !this.hasOptionsSectionTarget) return

  const htmlType = this.modalHtmlTypeTarget.value
  const configType = CONFIG_TYPE_MAP[htmlType]

  if (configType) {
    this.showConfigSection(configType)
  } else {
    this.hideConfigSection()
  }
}

showConfigSection(configType) {
  // Show the main section
  this.optionsSectionTarget.classList.remove("hidden")

  // Hide all config containers
  this.hideAllConfigContainers()

  // Show the appropriate config container
  const targetName = `${configType}ConfigTarget`
  if (this[`has${this.capitalize(configType)}ConfigTarget`]) {
    this[`${configType}ConfigTarget`].classList.remove("hidden")
  }

  // For selection type, auto-add first option if empty
  if (configType === "selection" && this.hasOptionsContainerTarget && this.optionsContainerTarget.children.length === 0) {
    this.addOption()
  }
}

hideConfigSection() {
  if (!this.hasOptionsSectionTarget) return
  this.optionsSectionTarget.classList.add("hidden")
  this.hideAllConfigContainers()
}

hideAllConfigContainers() {
  if (this.hasSelectionConfigTarget) this.selectionConfigTarget.classList.add("hidden")
  if (this.hasNumericConfigTarget) this.numericConfigTarget.classList.add("hidden")
  if (this.hasTextareaConfigTarget) this.textareaConfigTarget.classList.add("hidden")
  if (this.hasFileConfigTarget) this.fileConfigTarget.classList.add("hidden")
}
```

**Step 2: Remove old showOptionsSection and hideOptionsSection**

Delete the old methods (they are replaced by showConfigSection/hideConfigSection).

**Step 3: Verify in browser**

Run: Select different HTML types and verify correct config shows
Expected: Selection types show options, numeric shows min/max/step, etc.

**Step 4: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: update htmlTypeChanged to show correct config type"
```

---

## Task 6: Add Config Collection Methods

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add getNumericConfig method**

Add after getSelectedOptions:

```javascript
getNumericConfig() {
  const min = this.hasConfigMinTarget ? this.configMinTarget.value : ""
  const max = this.hasConfigMaxTarget ? this.configMaxTarget.value : ""
  const step = this.hasConfigStepTarget ? this.configStepTarget.value : ""

  // Return null if all empty
  if (!min && !max && !step) return null

  return {
    min: min ? parseFloat(min) : null,
    max: max ? parseFloat(max) : null,
    step: step ? parseFloat(step) : null
  }
}
```

**Step 2: Add getTextareaConfig method**

```javascript
getTextareaConfig() {
  const rows = this.hasConfigRowsTarget ? this.configRowsTarget.value : ""

  if (!rows) return null

  return {
    rows: parseInt(rows, 10)
  }
}
```

**Step 3: Add getFileConfig method**

```javascript
getFileConfig() {
  const accept = this.hasConfigAcceptTarget ? this.configAcceptTarget.value.trim() : ""
  const multiple = this.hasConfigMultipleTarget ? this.configMultipleTarget.checked : false

  if (!accept && !multiple) return null

  return {
    accept: accept || null,
    multiple: multiple
  }
}
```

**Step 4: Add getConfigForType method**

```javascript
getConfigForType(htmlType) {
  const configType = CONFIG_TYPE_MAP[htmlType]

  switch (configType) {
    case "selection":
      const options = this.getSelectedOptions()
      return options.length > 0 ? { options } : null
    case "numeric":
      return this.getNumericConfig()
    case "textarea":
      return this.getTextareaConfig()
    case "file":
      return this.getFileConfig()
    default:
      return null
  }
}
```

**Step 5: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: add config collection methods for each type"
```

---

## Task 7: Update collectModalData to Use Config

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update collectModalData**

Replace the collectModalData method:

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
    config: this.getConfigForType(htmlType)
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: update collectModalData to use unified config"
```

---

## Task 8: Update buildAttributeRowHtml for Config

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update buildAttributeRowHtml**

Update the method signature and replace `options` with `config`:

```javascript
buildAttributeRowHtml({ name, name_slug, type, html_type, description, validators, config }) {
  const index = this.attributeIndex
  const displayType = this.formatTypeName(type)
  const displayHtmlType = this.formatHtmlTypeName(html_type || "text")
  const validatorsJson = JSON.stringify(validators)
  const configJson = JSON.stringify(config || null)
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
        <input type="hidden" name="attributes[${index}][config]" value="${escapeHtml(configJson)}" data-input="config">
      </td>
    </tr>
  `
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: update buildAttributeRowHtml to use config"
```

---

## Task 9: Update extractAttributeFromRow for Config

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update extractAttributeFromRow**

```javascript
extractAttributeFromRow(row) {
  const getValue = (type) => row.querySelector(`input[data-input="${type}"]`)?.value.trim() || ""

  const name = getValue("name")
  if (!name) return null

  // Handle backward compatibility: check for both 'config' and legacy 'options'
  let config = this.parseConfigJson(getValue("config"))
  if (!config) {
    const legacyOptions = this.parseOptionsJson(getValue("options"))
    if (legacyOptions) {
      config = { options: legacyOptions }
    }
  }

  return {
    name,
    name_slug: getValue("name_slug") || this.generateSlug(name),
    type: getValue("type") || "text",
    html_type: getValue("html_type") || "text",
    description: getValue("description"),
    validators: this.parseValidatorsJson(getValue("validators")),
    config
  }
}
```

**Step 2: Add parseConfigJson helper**

Add after parseOptionsJson:

```javascript
parseConfigJson(json) {
  if (!json || json === "null") return null

  try {
    const parsed = JSON.parse(json)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch {
    return null
  }
}
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: update extractAttributeFromRow with backward compatibility"
```

---

## Task 10: Update resetModalFields for All Config Types

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Update resetModalFields**

Replace the resetModalFields method:

```javascript
resetModalFields() {
  if (this.hasModalNameTarget) this.modalNameTarget.value = ""
  if (this.hasModalNameSlugTarget) this.modalNameSlugTarget.value = ""
  if (this.hasModalTypeTarget) this.modalTypeTarget.selectedIndex = 0
  if (this.hasModalHtmlTypeTarget) this.modalHtmlTypeTarget.selectedIndex = 0
  if (this.hasModalDescriptionTarget) this.modalDescriptionTarget.value = ""
  if (this.hasModalValidatorSelectTarget) this.modalValidatorSelectTarget.selectedIndex = 0
  if (this.hasValidatorsContainerTarget) this.validatorsContainerTarget.innerHTML = ""

  // Reset selection config
  if (this.hasOptionsContainerTarget) this.optionsContainerTarget.innerHTML = ""
  this.optionIndex = 0

  // Reset numeric config
  if (this.hasConfigMinTarget) this.configMinTarget.value = ""
  if (this.hasConfigMaxTarget) this.configMaxTarget.value = ""
  if (this.hasConfigStepTarget) this.configStepTarget.value = ""

  // Reset textarea config
  if (this.hasConfigRowsTarget) this.configRowsTarget.value = ""

  // Reset file config
  if (this.hasConfigAcceptTarget) this.configAcceptTarget.value = ""
  if (this.hasConfigMultipleTarget) this.configMultipleTarget.checked = false

  // Hide config section and all containers
  this.hideConfigSection()
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat: update resetModalFields for all config types"
```

---

## Task 11: Run Tests and Final Verification

**Files:**
- Test: `spec/models/concerns/html_type_options_spec.rb`

**Step 1: Run all HtmlTypeOptions tests**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb -v`
Expected: All tests pass

**Step 2: Manual browser testing**

Test each config type:
1. Select "Dropdown" → verify options section shows
2. Select "Range Slider" → verify numeric config shows with min/max/step
3. Select "Number" → verify numeric config shows
4. Select "Textarea" → verify rows input shows
5. Select "File Upload" → verify accept and multiple options show
6. Select "Text Input" → verify no config section shows
7. Add attribute with each config type and verify data is stored

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete HTML type configuration feature"
```

---

## Summary

This implementation adds:
1. `config_type_for` and `configurable_type?` helpers in HtmlTypeOptions
2. Config sections in modal for: selection, numeric, textarea, file
3. Dynamic config section display based on HTML type
4. Unified `config` object replacing `options` for all type-specific settings
5. Backward compatibility for existing `options` data
6. Reset functionality for all config inputs

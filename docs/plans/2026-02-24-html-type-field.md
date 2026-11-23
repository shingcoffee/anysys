# HTML Type Field Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an `html_type` field to entity attributes that specifies how the attribute should be rendered as an HTML form element.

**Architecture:** Create a Ruby concern defining HTML type options as grouped constants, add a dropdown to the attribute modal, update the attributes table to display and persist the new field, and update the Stimulus controller to handle the new data.

**Tech Stack:** Ruby on Rails 8, TailwindCSS, StimulusJS, RSpec

---

### Task 1: Create HtmlTypeOptions Concern

**Files:**
- Create: `app/models/concerns/html_type_options.rb`
- Test: `spec/models/concerns/html_type_options_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/models/concerns/html_type_options_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HtmlTypeOptions do
  describe ".grouped_html_types" do
    it "returns a hash of grouped HTML types" do
      result = HtmlTypeOptions.grouped_html_types

      expect(result).to be_a(Hash)
      expect(result.keys).to include("Text", "Selection", "Numeric", "Date & Time", "Contact", "Other")
    end

    it "includes text input in Text category" do
      result = HtmlTypeOptions.grouped_html_types

      expect(result["Text"]).to include(["Text Input", "text"])
    end

    it "includes dropdown in Selection category" do
      result = HtmlTypeOptions.grouped_html_types

      expect(result["Selection"]).to include(["Dropdown", "select"])
    end
  end

  describe ".all_html_types" do
    it "returns a flat array of all HTML types" do
      result = HtmlTypeOptions.all_html_types

      expect(result).to be_an(Array)
      expect(result).to include(["Text Input", "text"])
      expect(result).to include(["Dropdown", "select"])
      expect(result).to include(["Email", "email"])
    end
  end

  describe ".valid_html_type?" do
    it "returns true for valid HTML type values" do
      expect(HtmlTypeOptions.valid_html_type?("text")).to be true
      expect(HtmlTypeOptions.valid_html_type?("select")).to be true
      expect(HtmlTypeOptions.valid_html_type?("email")).to be true
    end

    it "returns false for invalid HTML type values" do
      expect(HtmlTypeOptions.valid_html_type?("invalid")).to be false
      expect(HtmlTypeOptions.valid_html_type?("")).to be false
      expect(HtmlTypeOptions.valid_html_type?(nil)).to be false
    end
  end

  describe ".label_for" do
    it "returns label for a valid HTML type value" do
      expect(HtmlTypeOptions.label_for("text")).to eq("Text Input")
      expect(HtmlTypeOptions.label_for("select")).to eq("Dropdown")
      expect(HtmlTypeOptions.label_for("email")).to eq("Email")
    end

    it "returns the value itself for unknown types" do
      expect(HtmlTypeOptions.label_for("unknown")).to eq("unknown")
    end

    it "returns 'Text Input' for nil" do
      expect(HtmlTypeOptions.label_for(nil)).to eq("Text Input")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb`
Expected: FAIL with "uninitialized constant HtmlTypeOptions"

**Step 3: Write minimal implementation**

```ruby
# app/models/concerns/html_type_options.rb
# frozen_string_literal: true

module HtmlTypeOptions
  extend ActiveSupport::Concern

  GROUPED_HTML_TYPES = {
    "Text" => [
      ["Text Input", "text"],
      ["Textarea", "textarea"],
      ["Password", "password"],
      ["Hidden", "hidden"]
    ],
    "Selection" => [
      ["Dropdown", "select"],
      ["Radio Buttons", "radio"],
      ["Checkboxes", "checkbox"]
    ],
    "Numeric" => [
      ["Number", "number"],
      ["Range Slider", "range"]
    ],
    "Date & Time" => [
      ["Date", "date"],
      ["Time", "time"],
      ["DateTime", "datetime-local"]
    ],
    "Contact" => [
      ["Email", "email"],
      ["Phone", "tel"],
      ["URL", "url"]
    ],
    "Other" => [
      ["Color Picker", "color"],
      ["File Upload", "file"]
    ]
  }.freeze

  class_methods do
    def grouped_html_types
      GROUPED_HTML_TYPES
    end

    def all_html_types
      GROUPED_HTML_TYPES.values.flatten(1)
    end

    def valid_html_type?(value)
      return false if value.blank?
      all_html_types.any? { |_, v| v == value }
    end

    def label_for(value)
      return "Text Input" if value.blank?
      pair = all_html_types.find { |_, v| v == value }
      pair ? pair.first : value
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/concerns/html_type_options_spec.rb`
Expected: All tests PASS

---

### Task 2: Add HTML Type Dropdown to Attribute Modal

**Files:**
- Modify: `app/views/entities/_attribute_modal.html.erb`

**Step 1: Read current modal file**

Read the file to understand exact line numbers for insertion.

**Step 2: Add HTML Type dropdown after Type field**

Insert the following after the Type field section (after line 68, before Validators):

```erb
<%# HTML Type Field %>
<div>
  <label class="block text-sm font-medium text-gray-700 mb-1">
    HTML Type <span class="text-red-500">*</span>
  </label>
  <select data-entity-form-target="modalHtmlType" class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-colors bg-white" required>
    <% HtmlTypeOptions.grouped_html_types.each do |category, types| %>
      <optgroup label="<%= category %>">
        <% types.each do |label, value| %>
          <option value="<%= value %>"><%= label %></option>
        <% end %>
      </optgroup>
    <% end %>
  </select>
</div>
```

**Step 3: Verify manually**

Run: `bin/rails runner "puts HtmlTypeOptions.grouped_html_types.keys"`
Expected: Output the category names

---

### Task 3: Update Attributes Table to Display HTML Type

**Files:**
- Modify: `app/views/entities/_attributes_table.html.erb`

**Step 1: Add HTML Type column header**

Add after the Type header (line 10):

```erb
<th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[10%]">HTML Type</th>
```

**Step 2: Add HTML Type cell in table body**

Add after the Type cell (after line 36):

```erb
<td class="py-1.5">
  <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium text-emerald-700 bg-emerald-100 rounded"
        data-field="html_type">
    <%= HtmlTypeOptions.label_for(attr["html_type"]) %>
  </span>
</td>
```

**Step 3: Add hidden input for html_type**

Add after the type hidden input (after line 56):

```erb
<input type="hidden" name="attributes[<%= index %>][html_type]" value="<%= attr["html_type"] || "text" %>" data-input="html_type">
```

**Step 4: Adjust column widths**

Update the width classes to accommodate the new column:
- Name: `w-[14%]`
- Name Slug: `w-[14%]`
- Type: `w-[10%]`
- HTML Type: `w-[10%]`
- Validators: `w-[20%]`
- Description: `w-[22%]`
- Actions: `w-[10%]`

---

### Task 4: Update Stimulus Controller for HTML Type

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

**Step 1: Add modalHtmlType to targets**

Update targets array (around line 21-35) to include:

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
  "modalHtmlType",  // ADD THIS
  "modalDescription",
  "modalValidatorSelect",
  "validatorsContainer",
  "entityName",
  "entityNameSlug"
]
```

**Step 2: Update collectModalData method**

Update method (around line 242-251) to include html_type:

```javascript
collectModalData() {
  const name = this.getTargetValue("modalName")
  return {
    name,
    name_slug: this.getTargetValue("modalNameSlug") || this.generateSlug(name),
    type: this.getTargetValue("modalType") || "text",
    html_type: this.getTargetValue("modalHtmlType") || "text",
    description: this.getTargetValue("modalDescription"),
    validators: this.getSelectedValidators()
  }
}
```

**Step 3: Update resetModalFields method**

Update method (around line 154-161) to reset html_type:

```javascript
resetModalFields() {
  if (this.hasModalNameTarget) this.modalNameTarget.value = ""
  if (this.hasModalNameSlugTarget) this.modalNameSlugTarget.value = ""
  if (this.hasModalTypeTarget) this.modalTypeTarget.selectedIndex = 0
  if (this.hasModalHtmlTypeTarget) this.modalHtmlTypeTarget.selectedIndex = 0
  if (this.hasModalDescriptionTarget) this.modalDescriptionTarget.value = ""
  if (this.hasModalValidatorSelectTarget) this.modalValidatorSelectTarget.selectedIndex = 0
  if (this.hasValidatorsContainerTarget) this.validatorsContainerTarget.innerHTML = ""
}
```

**Step 4: Update extractAttributeFromRow method**

Update method (around line 411-424) to extract html_type:

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
    validators: this.parseValidatorsJson(getValue("validators"))
  }
}
```

**Step 5: Update buildTableHtml method**

Update method (around line 441-457) to include HTML Type column:

```javascript
buildTableHtml() {
  return `
    <table class="min-w-full divide-y divide-gray-200 table-fixed" data-entity-form-target="attributesTable">
      <thead>
        <tr>
          <th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[14%]">Name</th>
          <th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[14%]">Name Slug</th>
          <th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[10%]">Type</th>
          <th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[10%]">HTML Type</th>
          <th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[20%]">Validators</th>
          <th class="pb-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[22%]">Description</th>
          <th class="pb-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider w-[10%]">Actions</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100"></tbody>
    </table>
  `
}
```

**Step 6: Update buildAttributeRowHtml method**

Update method (around line 459-493) to include html_type:

```javascript
buildAttributeRowHtml({ name, name_slug, type, html_type, description, validators }) {
  const index = this.attributeIndex
  const displayType = this.formatTypeName(type)
  const displayHtmlType = this.formatHtmlTypeName(html_type || "text")
  const validatorsJson = JSON.stringify(validators)
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
      </td>
    </tr>
  `
}
```

**Step 7: Add formatHtmlTypeName helper method**

Add after formatTypeName method (around line 531-534):

```javascript
formatHtmlTypeName(htmlType) {
  const labels = {
    'text': 'Text Input',
    'textarea': 'Textarea',
    'password': 'Password',
    'hidden': 'Hidden',
    'select': 'Dropdown',
    'radio': 'Radio',
    'checkbox': 'Checkbox',
    'number': 'Number',
    'range': 'Range',
    'date': 'Date',
    'time': 'Time',
    'datetime-local': 'DateTime',
    'email': 'Email',
    'tel': 'Phone',
    'url': 'URL',
    'color': 'Color',
    'file': 'File'
  }
  return labels[htmlType] || htmlType
}
```

---

### Task 5: Add Helper Method for Displaying HTML Type Labels

**Files:**
- Modify: `app/helpers/entities_helper.rb` (or create if doesn't exist)

**Step 1: Check if helper exists**

Run: `ls app/helpers/entities_helper.rb 2>/dev/null || echo "NOT FOUND"`

**Step 2: Add or update helper**

```ruby
# app/helpers/entities_helper.rb
# frozen_string_literal: true

module EntitiesHelper
  # ... existing methods ...

  def format_html_type_label(html_type)
    HtmlTypeOptions.label_for(html_type)
  end
end
```

---

### Task 6: Run Full Test Suite and Verify

**Step 1: Run RSpec tests**

Run: `bundle exec rspec --format progress`
Expected: All tests pass

**Step 2: Start development server**

Run: `bin/dev`
Expected: Server starts without errors

**Step 3: Manual verification**

1. Navigate to Entities page
2. Create or edit an Entity
3. Click "Add Attribute"
4. Verify HTML Type dropdown appears below Type field
5. Verify all categories and options are present
6. Add an attribute and verify HTML Type displays in table

---

## Completion Checklist

- [ ] `HtmlTypeOptions` concern created with tests
- [ ] HTML Type dropdown added to attribute modal
- [ ] HTML Type column added to attributes table
- [ ] Stimulus controller updated to handle html_type
- [ ] Helper method added for label display
- [ ] All RSpec tests pass
- [ ] Manual verification complete

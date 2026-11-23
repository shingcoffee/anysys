# Page Builder Phase 3: Power Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add field templates/presets (save and reuse configured fields), slash command palette, canvas zoom with mini-map and field search, breadcrumb navigation for nested fields, and right-click context menus.

**Architecture:** Phase 3 adds three new JS managers (`command_palette_manager.js`, `context_menu_manager.js`, `zoom_manager.js`), five new ViewComponents, and a server-side `FieldTemplate` model with Trailblazer Activities for CRUD. The slash command palette replaces the current "/" shortcut that opens the basic inserter. The context menu provides unified right-click access to all field actions. The zoom system uses CSS `transform: scale()` on the canvas inner container.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS, ViewComponent, RSpec, Trailblazer Activity, Reform

**Spec:** `docs/superpowers/specs/2026-03-23-page-builder-improvements-design.md` (Phase 3 sections 3.1-3.5)

**Depends on:** Phase 1 + Phase 2 complete

---

## File Map

### New Files

| File | Purpose |
|------|---------|
| `db/migrate/XXXXXX_create_field_templates.rb` | Migration for field_templates table |
| `app/models/field_template.rb` | FieldTemplate model with validations |
| `app/services/field_template/create.rb` | Trailblazer Activity for template creation |
| `app/services/field_template/update.rb` | Trailblazer Activity for template update |
| `app/services/field_template/delete.rb` | Trailblazer Activity for template deletion |
| `app/services/field_template/contract.rb` | Reform contract for template validation |
| `app/controllers/field_templates_controller.rb` | JSON API for template CRUD |
| `spec/models/field_template_spec.rb` | Model spec |
| `spec/services/field_template/create_spec.rb` | Activity spec |
| `app/javascript/controllers/page_builder/command_palette_manager.js` | Slash command palette with fuzzy search |
| `app/javascript/controllers/page_builder/context_menu_manager.js` | Right-click context menus |
| `app/javascript/controllers/page_builder/zoom_manager.js` | Canvas zoom, mini-map, field search |
| `app/components/page_builder/command_palette_component.rb` | ViewComponent: command palette |
| `app/components/page_builder/command_palette_component.html.erb` | Template |
| `app/components/page_builder/context_menu_component.rb` | ViewComponent: context menu |
| `app/components/page_builder/context_menu_component.html.erb` | Template |
| `app/components/page_builder/breadcrumb_component.rb` | ViewComponent: breadcrumb bar |
| `app/components/page_builder/breadcrumb_component.html.erb` | Template |
| `app/components/page_builder/zoom_controls_component.rb` | ViewComponent: zoom toolbar |
| `app/components/page_builder/zoom_controls_component.html.erb` | Template |
| `app/components/page_builder/mini_map_component.rb` | ViewComponent: mini-map |
| `app/components/page_builder/mini_map_component.html.erb` | Template |
| `spec/components/page_builder/command_palette_component_spec.rb` | Spec |
| `spec/components/page_builder/context_menu_component_spec.rb` | Spec |
| `spec/components/page_builder/breadcrumb_component_spec.rb` | Spec |
| `spec/components/page_builder/zoom_controls_component_spec.rb` | Spec |
| `spec/components/page_builder/mini_map_component_spec.rb` | Spec |

### Modified Files

| File | Changes |
|------|---------|
| `app/javascript/controllers/page_builder_controller.js` | Import 3 new managers, add targets, delegations |
| `app/javascript/controllers/page_builder/keyboard_manager.js` | Replace "/" handler, add Ctrl+F, Ctrl+Plus/Minus/0 |
| `app/javascript/controllers/page_builder/inserter_manager.js` | Add template loading from API |
| `app/javascript/controllers/page_builder/property_manager.js` | Add breadcrumb rendering for nested fields |
| `app/views/pages/_editor.html.erb` | Add command palette, context menu, breadcrumb, zoom containers |
| `config/routes.rb` | Add field_templates resource routes |

---

## Task 1: FieldTemplate Model and Trailblazer Activities

**Files:**
- Create: `db/migrate/XXXXXX_create_field_templates.rb`
- Create: `app/models/field_template.rb`
- Create: `app/services/field_template/contract.rb`
- Create: `app/services/field_template/create.rb`
- Create: `app/services/field_template/update.rb`
- Create: `app/services/field_template/delete.rb`
- Create: `app/controllers/field_templates_controller.rb`
- Create: `spec/models/field_template_spec.rb`
- Create: `spec/services/field_template/create_spec.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Generate migration**

```bash
rails generate migration CreateFieldTemplates customer_id:bigint name:string category:string description:text configuration:jsonb built_in:boolean
```

Edit the migration to add indexes and defaults:

```ruby
class CreateFieldTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :field_templates do |t|
      t.bigint :customer_id, null: false
      t.string :name, null: false
      t.string :category
      t.text :description
      t.jsonb :configuration, null: false, default: {}
      t.boolean :built_in, default: false, null: false
      t.timestamps
    end

    add_index :field_templates, :customer_id
    add_index :field_templates, [:customer_id, :category]
    add_index :field_templates, [:customer_id, :built_in]
  end
end
```

- [ ] **Step 2: Run migration**

```bash
rails db:migrate
```

- [ ] **Step 3: Write model spec**

```ruby
# spec/models/field_template_spec.rb
require "rails_helper"

RSpec.describe FieldTemplate, type: :model do
  it "requires customer_id" do
    template = FieldTemplate.new(name: "Test", configuration: { "field_type" => "text" })
    expect(template).not_to be_valid
  end

  it "requires name" do
    template = FieldTemplate.new(customer_id: 1, configuration: { "field_type" => "text" })
    expect(template).not_to be_valid
  end

  it "is valid with required fields" do
    template = FieldTemplate.new(customer_id: 1, name: "US Phone", configuration: { "field_type" => "tel" })
    expect(template).to be_valid
  end

  it "scopes by customer" do
    FieldTemplate.create!(customer_id: 1, name: "A", configuration: {})
    FieldTemplate.create!(customer_id: 2, name: "B", configuration: {})
    expect(FieldTemplate.where(customer_id: 1).count).to eq(1)
  end
end
```

- [ ] **Step 4: Write model**

```ruby
# app/models/field_template.rb
class FieldTemplate < ApplicationRecord
  validates :customer_id, presence: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :category, length: { maximum: 50 }, allow_blank: true
  validates :configuration, presence: true

  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :custom, -> { where(built_in: false) }
  scope :built_in, -> { where(built_in: true) }
end
```

- [ ] **Step 5: Run model spec**

```bash
bundle exec rspec spec/models/field_template_spec.rb -v
```

- [ ] **Step 6: Write Reform Contract**

```ruby
# app/services/field_template/contract.rb
module FieldTemplate
  class Contract < Reform::Form
    property :name
    property :category
    property :description
    property :configuration
    property :customer_id

    validates :name, presence: true, length: { maximum: 100 }
    validates :configuration, presence: true
    validates :category, length: { maximum: 50 }, allow_blank: true
    validate :name_unique_per_customer

    def name_unique_per_customer
      scope = ::FieldTemplate.where(customer_id: customer_id, name: name)
      scope = scope.where.not(id: model.id) if model.persisted?
      errors.add(:name, "already exists") if scope.exists?
    end
  end
end
```

- [ ] **Step 7: Write Trailblazer Activities**

```ruby
# app/services/field_template/create.rb
module FieldTemplate
  class Create < Trailblazer::Activity::Railway
    step :build_model
    step :validate
    step :save

    def build_model(ctx, params:, **)
      ctx[:model] = ::FieldTemplate.new(params)
    end

    def validate(ctx, model:, **)
      contract = Contract.new(model)
      ctx[:contract] = contract
      contract.validate(model.attributes)
    end

    def save(ctx, model:, **)
      model.save
    end
  end
end

# app/services/field_template/update.rb
module FieldTemplate
  class Update < Trailblazer::Activity::Railway
    step :find_model
    step :check_not_built_in
    step :validate
    step :save

    def find_model(ctx, id:, customer_id:, **)
      ctx[:model] = ::FieldTemplate.find_by(id: id, customer_id: customer_id)
      ctx[:model].present?
    end

    def check_not_built_in(ctx, model:, **)
      !model.built_in?
    end

    def validate(ctx, model:, params:, **)
      contract = Contract.new(model)
      ctx[:contract] = contract
      contract.validate(params)
    end

    def save(ctx, model:, **)
      model.save
    end
  end
end

# app/services/field_template/delete.rb
module FieldTemplate
  class Delete < Trailblazer::Activity::Railway
    step :find_model
    step :check_not_built_in
    step :destroy

    def find_model(ctx, id:, customer_id:, **)
      ctx[:model] = ::FieldTemplate.find_by(id: id, customer_id: customer_id)
      ctx[:model].present?
    end

    def check_not_built_in(ctx, model:, **)
      !model.built_in?
    end

    def destroy(ctx, model:, **)
      model.destroy
    end
  end
end
```

- [ ] **Step 8: Write controller for JSON API**

```ruby
# app/controllers/field_templates_controller.rb
class FieldTemplatesController < ApplicationController
  def index
    templates = FieldTemplate.for_customer(current_customer_id).order(:name)
    render json: templates.map { |t| template_json(t) }
  end

  def create
    result = FieldTemplate::Create.call(params: template_params.merge(customer_id: current_customer_id))
    if result.success?
      render json: template_json(result[:model]), status: :created
    else
      render json: { errors: result[:contract]&.errors&.messages }, status: :unprocessable_entity
    end
  end

  def update
    result = FieldTemplate::Update.call(id: params[:id], customer_id: current_customer_id, params: template_params)
    if result.success?
      render json: template_json(result[:model])
    else
      render json: { errors: "Update failed" }, status: :unprocessable_entity
    end
  end

  def destroy
    result = FieldTemplate::Delete.call(id: params[:id], customer_id: current_customer_id)
    if result.success?
      head :no_content
    else
      render json: { errors: "Cannot delete built-in templates" }, status: :unprocessable_entity
    end
  end

  private

  def template_params
    params.require(:field_template).permit(:name, :category, :description, configuration: {})
  end

  def template_json(t)
    { id: t.id, name: t.name, category: t.category, description: t.description,
      configuration: t.configuration, built_in: t.built_in }
  end
end
```

- [ ] **Step 9: Add routes**

In `config/routes.rb`, inside the customer scope:

```ruby
resources :field_templates, only: [:index, :create, :update, :destroy]
```

- [ ] **Step 10: Enable "Save as Template" in field group and field action bar**

In `field_manager.js`, in the field group rendering (`_renderFieldGroup`), the "Save as Template" button is currently disabled. Enable it:

```javascript
// Change from:
disabled title="Available in a future update"
// To:
data-action="click->page-builder#saveFieldAsTemplate" data-field-id="${group.id}"
```

Also add "Save as Template" to the field action bar card buttons (or the property panel dropdown).

Add delegation in controller:
```javascript
saveFieldAsTemplate(event) { this.fieldManager.saveFieldAsTemplate(event) }
```

Add method in field_manager.js:
```javascript
saveFieldAsTemplate(event) {
  event.stopPropagation()
  const fieldId = event.currentTarget.dataset.fieldId
  const field = this.c.allFields.find(f => f.id === fieldId)
  if (!field) return

  const name = prompt("Template name:")
  if (!name) return

  const config = JSON.parse(JSON.stringify(field))
  delete config.id
  delete config.order

  fetch(`/${this.c.customerIdValue}/field_templates`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content },
    body: JSON.stringify({ field_template: { name, configuration: config } })
  })
  .then(r => r.ok ? r.json() : Promise.reject(r))
  .then(() => { /* TODO: refresh template sidebar if visible */ })
  .catch(() => alert("Failed to save template"))
}
```

- [ ] **Step 11: Run specs**

```bash
bundle exec rspec spec/models/field_template_spec.rb -v
```

- [ ] **Step 12: Commit**

```bash
git add db/migrate/ app/models/field_template.rb app/services/field_template/ app/controllers/field_templates_controller.rb config/routes.rb spec/models/ spec/services/ app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): add FieldTemplate model with Trailblazer CRUD and Save as Template"
```

---

## Task 2: Command Palette (Slash Commands)

**Files:**
- Create: `app/javascript/controllers/page_builder/command_palette_manager.js`
- Create: `app/components/page_builder/command_palette_component.rb`
- Create: `app/components/page_builder/command_palette_component.html.erb`
- Create: `spec/components/page_builder/command_palette_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder/keyboard_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js`
- Modify: `app/views/pages/_editor.html.erb`

- [ ] **Step 1: Write component spec**

```ruby
# spec/components/page_builder/command_palette_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::CommandPaletteComponent, type: :component do
  it "renders a hidden palette container" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-page-builder-target='commandPalette']")
    expect(page).to have_css(".hidden")
  end

  it "has a search input" do
    render_inline(described_class.new)
    expect(page).to have_css("input[placeholder*='command']")
  end

  it "has a results container" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-page-builder-target='commandPaletteResults']")
  end
end
```

- [ ] **Step 2: Write the component**

```ruby
class PageBuilder::CommandPaletteComponent < ApplicationComponent
end
```

```erb
<%# Command palette overlay %>
<div class="hidden fixed inset-0 z-50 flex items-start justify-center pt-[20vh]"
     data-page-builder-target="commandPalette"
     data-action="click->page-builder#closeCommandPalette">
  <div class="bg-white rounded-xl shadow-2xl border border-gray-200 w-[480px] max-h-[400px] flex flex-col overflow-hidden"
       data-action="click->page-builder#stopPropagation">
    <%# Search input %>
    <div class="p-3 border-b border-gray-100">
      <input type="text"
             class="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
             placeholder="Type a command..."
             data-page-builder-target="commandPaletteInput"
             data-action="input->page-builder#filterCommandPalette keydown->page-builder#commandPaletteKeydown"
             autocomplete="off">
    </div>
    <%# Results %>
    <div class="flex-1 overflow-y-auto p-2" data-page-builder-target="commandPaletteResults">
    </div>
  </div>
</div>
```

- [ ] **Step 3: Run spec**

```bash
bundle exec rspec spec/components/page_builder/command_palette_component_spec.rb -v
```

- [ ] **Step 4: Create command_palette_manager.js**

```javascript
import { BaseManager } from "controllers/page_builder/base_manager"

const FIELD_COMMANDS = [
  { type: "text", label: "Text Input", category: "Fields", icon: "T" },
  { type: "email", label: "Email", category: "Fields", icon: "@" },
  { type: "select", label: "Select Dropdown", category: "Fields", icon: "v" },
  { type: "number", label: "Number", category: "Fields", icon: "#" },
  { type: "date", label: "Date Picker", category: "Fields", icon: "D" },
  { type: "file", label: "File Upload", category: "Fields", icon: "F" },
  { type: "textarea", label: "Textarea", category: "Fields", icon: "P" },
  { type: "checkbox", label: "Checkbox", category: "Fields", icon: "x" },
  { type: "radio", label: "Radio", category: "Fields", icon: "o" },
  { type: "switch", label: "Switch Toggle", category: "Fields", icon: "~" },
  { type: "currency", label: "Currency", category: "Fields", icon: "$" },
  { type: "rating", label: "Rating", category: "Fields", icon: "*" },
  { type: "password", label: "Password", category: "Fields", icon: "." },
  { type: "tel", label: "Phone", category: "Fields", icon: "#" },
  { type: "url", label: "URL", category: "Fields", icon: "/" },
  { type: "rich-text", label: "Rich Text", category: "Fields", icon: "R" },
  { type: "signature", label: "Signature", category: "Fields", icon: "S" }
]

const LAYOUT_COMMANDS = [
  { type: "section", label: "Section", category: "Layout", icon: "=" },
  { type: "heading", label: "Heading", category: "Layout", icon: "H" },
  { type: "paragraph", label: "Paragraph", category: "Layout", icon: "P" },
  { type: "divider", label: "Divider", category: "Layout", icon: "-" },
  { type: "spacer", label: "Spacer", category: "Layout", icon: "|" },
  { type: "columns", label: "Columns", category: "Layout", icon: "[]" },
  { type: "card", label: "Card", category: "Layout", icon: "C" },
  { type: "alert", label: "Alert", category: "Layout", icon: "!" },
  { type: "button", label: "Button", category: "Layout", icon: "B" },
  { type: "image", label: "Image", category: "Layout", icon: "I" },
  { type: "video", label: "Video", category: "Layout", icon: "V" },
  { type: "list", label: "List", category: "Layout", icon: "L" },
  { type: "code_block", label: "Code Block", category: "Layout", icon: "<>" },
  { type: "progress_bar", label: "Progress Bar", category: "Layout", icon: "%" },
  { type: "quote", label: "Quote", category: "Layout", icon: '"' },
  { type: "callout", label: "Callout", category: "Layout", icon: "i" }
]

const ACTION_COMMANDS = [
  { action: "duplicate", label: "Duplicate", category: "Actions", icon: "D" },
  { action: "delete", label: "Delete", category: "Actions", icon: "X" },
  { action: "copy", label: "Copy", category: "Actions", icon: "C" },
  { action: "paste", label: "Paste", category: "Actions", icon: "V" },
  { action: "undo", label: "Undo", category: "Actions", icon: "Z" },
  { action: "redo", label: "Redo", category: "Actions", icon: "Y" },
  { action: "preview", label: "Preview", category: "Actions", icon: "P" },
  { action: "save", label: "Save", category: "Actions", icon: "S" }
]

export class CommandPaletteManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.selectedIndex = 0
    this.filteredResults = []
    this.templates = []
  }

  open() {
    if (!this.c.hasCommandPaletteTarget) return
    this.c.commandPaletteTarget.classList.remove("hidden")
    this.c.commandPaletteInputTarget.value = ""
    this.c.commandPaletteInputTarget.focus()
    this._loadTemplates()
    this._renderResults("")
  }

  close() {
    if (!this.c.hasCommandPaletteTarget) return
    this.c.commandPaletteTarget.classList.add("hidden")
  }

  filter(event) {
    const query = event.target.value.trim().toLowerCase()
    this._renderResults(query)
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, this.filteredResults.length - 1)
      this._updateSelection()
      return
    }
    if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this._updateSelection()
      return
    }
    if (event.key === "Enter") {
      event.preventDefault()
      const selected = this.filteredResults[this.selectedIndex]
      if (selected) this._execute(selected)
    }
  }

  executeFromClick(event) {
    const idx = parseInt(event.currentTarget.dataset.resultIndex, 10)
    const result = this.filteredResults[idx]
    if (result) this._execute(result)
  }

  _loadTemplates() {
    fetch(`/${this.c.customerIdValue}/field_templates`, {
      headers: { "Accept": "application/json" }
    })
    .then(r => r.ok ? r.json() : [])
    .then(templates => { this.templates = templates })
    .catch(() => { this.templates = [] })
  }

  _renderResults(query) {
    const allCommands = [
      ...FIELD_COMMANDS,
      ...LAYOUT_COMMANDS,
      ...this.templates.map(t => ({ type: "template", label: t.name, category: "Templates", icon: "T", template: t })),
      ...ACTION_COMMANDS
    ]

    this.filteredResults = query
      ? allCommands.filter(cmd => cmd.label.toLowerCase().includes(query) || cmd.type?.toLowerCase().includes(query) || cmd.action?.toLowerCase().includes(query))
      : allCommands

    this.selectedIndex = 0

    const container = this.c.commandPaletteResultsTarget
    if (this.filteredResults.length === 0) {
      container.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">No results</p>'
      return
    }

    let currentCategory = ""
    let html = ""

    this.filteredResults.forEach((cmd, idx) => {
      if (cmd.category !== currentCategory) {
        currentCategory = cmd.category
        html += `<div class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider px-2 pt-2 pb-1">${currentCategory}</div>`
      }
      const selectedClass = idx === 0 ? "bg-indigo-50 text-indigo-700" : "text-gray-700"
      html += `<button type="button" class="command-result w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded-md hover:bg-indigo-50 ${selectedClass} transition-colors"
                       data-result-index="${idx}" data-action="click->page-builder#executeCommandPaletteResult">
        <span class="w-5 h-5 rounded bg-gray-100 text-gray-500 text-[10px] font-mono flex items-center justify-center flex-shrink-0">${cmd.icon || "?"}</span>
        <span class="truncate">${cmd.label}</span>
      </button>`
    })

    container.innerHTML = html
  }

  _updateSelection() {
    const buttons = this.c.commandPaletteResultsTarget.querySelectorAll(".command-result")
    buttons.forEach((btn, idx) => {
      btn.classList.toggle("bg-indigo-50", idx === this.selectedIndex)
      btn.classList.toggle("text-indigo-700", idx === this.selectedIndex)
    })
    buttons[this.selectedIndex]?.scrollIntoView({ block: "nearest" })
  }

  _execute(cmd) {
    this.close()

    if (cmd.action) {
      this._executeAction(cmd.action)
      return
    }

    if (cmd.type === "template" && cmd.template) {
      const config = JSON.parse(JSON.stringify(cmd.template.configuration))
      config.id = `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
      this.c.fieldManager.addFieldAtIndex(config, this.c.currentPageFields.length)
      return
    }

    // Insert field or layout element
    const fieldData = { type: cmd.type, label: cmd.label }
    this.c.fieldManager.addFieldAtIndex(fieldData, this.c.currentPageFields.length)
  }

  _executeAction(action) {
    const actions = {
      duplicate: () => this.c.clipboardManager.duplicateSelected(),
      delete: () => this.c.fieldManager.deleteField(),
      copy: () => this.c.clipboardManager.copy(),
      paste: () => this.c.clipboardManager.paste(),
      undo: () => this.c.undoRedoManager.undo(),
      redo: () => this.c.undoRedoManager.redo(),
      preview: () => this.c.saveManager.preview(),
      save: () => this.c.saveManager.save()
    }
    actions[action]?.()
  }
}
```

- [ ] **Step 5: Register in controller**

In `page_builder_controller.js`:
- Import: `import { CommandPaletteManager } from "controllers/page_builder/command_palette_manager"`
- Instantiate: `this.commandPaletteManager = new CommandPaletteManager(this)`
- Add targets: `"commandPalette", "commandPaletteInput", "commandPaletteResults"`
- Add delegations:
```javascript
openCommandPalette() { this.commandPaletteManager.open() }
closeCommandPalette() { this.commandPaletteManager.close() }
filterCommandPalette(event) { this.commandPaletteManager.filter(event) }
commandPaletteKeydown(event) { this.commandPaletteManager.handleKeydown(event) }
executeCommandPaletteResult(event) { this.commandPaletteManager.executeFromClick(event) }
stopPropagation(event) { event.stopPropagation() }
```

- [ ] **Step 6: Update keyboard_manager.js**

Replace the current "/" handler (line ~154-162):

```javascript
if (key === "/" && !this._isInInput(event)) {
  event.preventDefault()
  this.c.commandPaletteManager.open()
  return
}
```

- [ ] **Step 7: Add component to _editor.html.erb**

```erb
<%= render PageBuilder::CommandPaletteComponent.new %>
```

- [ ] **Step 8: Test in browser**

- Press "/" on canvas → command palette opens centered
- Type "em" → shows "Email" and any templates containing "em"
- Arrow keys navigate, Enter inserts
- Escape closes
- Click backdrop closes

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/page_builder/command_palette_manager.js app/components/page_builder/command_palette_component* spec/components/page_builder/command_palette_component_spec.rb app/javascript/controllers/page_builder/keyboard_manager.js app/javascript/controllers/page_builder_controller.js app/views/pages/_editor.html.erb
git commit -m "feat(page-builder): add slash command palette with fuzzy search"
```

---

## Task 3: Canvas Zoom & Navigation

**Files:**
- Create: `app/javascript/controllers/page_builder/zoom_manager.js`
- Create: `app/components/page_builder/zoom_controls_component.rb`
- Create: `app/components/page_builder/zoom_controls_component.html.erb`
- Create: `app/components/page_builder/mini_map_component.rb`
- Create: `app/components/page_builder/mini_map_component.html.erb`
- Create: `spec/components/page_builder/zoom_controls_component_spec.rb`
- Create: `spec/components/page_builder/mini_map_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder_controller.js`
- Modify: `app/javascript/controllers/page_builder/keyboard_manager.js`
- Modify: `app/views/pages/_editor.html.erb`

- [ ] **Step 1: Write component specs**

```ruby
# spec/components/page_builder/zoom_controls_component_spec.rb
require "rails_helper"
RSpec.describe PageBuilder::ZoomControlsComponent, type: :component do
  it "renders zoom in, zoom out, and reset buttons" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-action*='zoomIn']")
    expect(page).to have_css("[data-action*='zoomOut']")
    expect(page).to have_css("[data-action*='zoomReset']")
  end
  it "shows zoom percentage" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-page-builder-target='zoomLevel']")
  end
end
```

```ruby
# spec/components/page_builder/mini_map_component_spec.rb
require "rails_helper"
RSpec.describe PageBuilder::MiniMapComponent, type: :component do
  it "renders a mini-map container" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-page-builder-target='miniMap']")
  end
end
```

- [ ] **Step 2: Write components**

```ruby
class PageBuilder::ZoomControlsComponent < ApplicationComponent
end
```

```erb
<%# Zoom controls - bottom right of canvas %>
<div class="absolute bottom-3 right-3 flex items-center gap-1 bg-white rounded-lg shadow-md border border-gray-200 px-2 py-1 z-30">
  <button type="button" class="p-1 text-gray-500 hover:text-gray-700" data-action="click->page-builder#zoomOut" title="Zoom out">
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4"/></svg>
  </button>
  <span class="text-xs text-gray-600 w-10 text-center" data-page-builder-target="zoomLevel">100%</span>
  <button type="button" class="p-1 text-gray-500 hover:text-gray-700" data-action="click->page-builder#zoomIn" title="Zoom in">
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
  </button>
  <div class="w-px h-4 bg-gray-200 mx-1"></div>
  <button type="button" class="p-0.5 text-gray-400 hover:text-gray-600" data-action="click->page-builder#toggleMiniMap" title="Toggle mini-map">
    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l5.447 2.724A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"/></svg>
  </button>
</div>
```

```ruby
class PageBuilder::MiniMapComponent < ApplicationComponent
end
```

```erb
<%# Mini-map - bottom left of canvas, hidden by default %>
<div class="hidden absolute bottom-3 left-3 w-[120px] h-[80px] bg-white rounded-lg shadow-md border border-gray-200 overflow-hidden z-30"
     data-page-builder-target="miniMap">
  <div class="relative w-full h-full" data-page-builder-target="miniMapCanvas">
    <%# Mini-map content rendered by JS %>
  </div>
</div>
```

- [ ] **Step 3: Create zoom_manager.js**

```javascript
import { BaseManager } from "controllers/page_builder/base_manager"

const ZOOM_LEVELS = [50, 75, 100, 125, 150]

export class ZoomManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.currentZoom = 100
    this.miniMapVisible = false
  }

  zoomIn() {
    const idx = ZOOM_LEVELS.indexOf(this.currentZoom)
    if (idx < ZOOM_LEVELS.length - 1) {
      this.currentZoom = ZOOM_LEVELS[idx + 1]
      this._applyZoom()
    }
  }

  zoomOut() {
    const idx = ZOOM_LEVELS.indexOf(this.currentZoom)
    if (idx > 0) {
      this.currentZoom = ZOOM_LEVELS[idx - 1]
      this._applyZoom()
    }
  }

  zoomReset() {
    this.currentZoom = 100
    this._applyZoom()
  }

  _applyZoom() {
    if (!this.c.hasFieldsContainerTarget) return
    const container = this.c.fieldsContainerTarget
    container.style.transform = `scale(${this.currentZoom / 100})`
    container.style.transformOrigin = "top center"

    if (this.c.hasZoomLevelTarget) {
      this.c.zoomLevelTarget.textContent = `${this.currentZoom}%`
    }
  }

  toggleMiniMap() {
    this.miniMapVisible = !this.miniMapVisible
    if (this.c.hasMiniMapTarget) {
      this.c.miniMapTarget.classList.toggle("hidden", !this.miniMapVisible)
      if (this.miniMapVisible) this._renderMiniMap()
    }
  }

  _renderMiniMap() {
    if (!this.c.hasMiniMapCanvasTarget) return
    const fields = this.c.currentPageFields || []
    const canvas = this.c.miniMapCanvasTarget

    const fieldBlocks = fields.map((f, i) => {
      const color = f.property_type === "layout" ? "bg-violet-200" : "bg-indigo-200"
      const top = (i / Math.max(fields.length, 1)) * 100
      return `<div class="absolute left-1 right-1 h-[3px] ${color} rounded-full" style="top: ${top}%"></div>`
    }).join("")

    const viewportHeight = 30
    canvas.innerHTML = fieldBlocks +
      `<div class="absolute left-0 right-0 border border-indigo-400 bg-indigo-100/20 rounded-sm cursor-move" style="top: 0; height: ${viewportHeight}%" data-page-builder-target="miniMapViewport"></div>`
  }

  // Field search
  openSearch() {
    if (!this.c.hasCanvasAreaTarget) return

    let bar = this.c.canvasAreaTarget.querySelector(".canvas-search-bar")
    if (!bar) {
      bar = document.createElement("div")
      bar.className = "canvas-search-bar absolute top-2 left-1/2 -translate-x-1/2 z-40 bg-white rounded-lg shadow-lg border border-gray-200 px-3 py-2 flex items-center gap-2 w-[300px]"
      bar.innerHTML = `
        <svg class="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
        <input type="text" class="flex-1 text-sm border-none outline-none" placeholder="Search fields..." data-action="input->page-builder#filterCanvasSearch">
        <span class="text-xs text-gray-400" data-page-builder-target="searchCount"></span>
        <button type="button" class="text-gray-400 hover:text-gray-600" data-action="click->page-builder#closeCanvasSearch">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
        </button>
      `
      this.c.canvasAreaTarget.style.position = "relative"
      this.c.canvasAreaTarget.appendChild(bar)
    } else {
      bar.classList.remove("hidden")
    }

    bar.querySelector("input").focus()
  }

  closeSearch() {
    const bar = this.c.canvasAreaTarget?.querySelector(".canvas-search-bar")
    if (bar) bar.classList.add("hidden")
    // Restore all field opacity
    this.c.fieldsContainerTarget?.querySelectorAll(".field-card").forEach(card => {
      card.style.opacity = "1"
    })
  }

  filterSearch(event) {
    const query = event.target.value.trim().toLowerCase()
    if (!query) {
      this.c.fieldsContainerTarget?.querySelectorAll(".field-card").forEach(card => { card.style.opacity = "1" })
      if (this.c.hasSearchCountTarget) this.c.searchCountTarget.textContent = ""
      return
    }

    let matches = 0
    let total = 0
    this.c.fieldsContainerTarget?.querySelectorAll(".field-card").forEach(card => {
      total++
      const text = card.textContent.toLowerCase()
      if (text.includes(query)) {
        card.style.opacity = "1"
        matches++
      } else {
        card.style.opacity = "0.3"
      }
    })

    if (this.c.hasSearchCountTarget) {
      this.c.searchCountTarget.textContent = `${matches} of ${total}`
    }
  }
}
```

- [ ] **Step 4: Register in controller**

Add targets: `"zoomLevel", "miniMap", "miniMapCanvas", "miniMapViewport", "searchCount"`

Add delegations:
```javascript
zoomIn() { this.zoomManager.zoomIn() }
zoomOut() { this.zoomManager.zoomOut() }
zoomReset() { this.zoomManager.zoomReset() }
toggleMiniMap() { this.zoomManager.toggleMiniMap() }
openCanvasSearch() { this.zoomManager.openSearch() }
closeCanvasSearch() { this.zoomManager.closeSearch() }
filterCanvasSearch(event) { this.zoomManager.filterSearch(event) }
```

Import and instantiate: `this.zoomManager = new ZoomManager(this)`

- [ ] **Step 5: Add keyboard shortcuts**

In keyboard_manager.js, add:

```javascript
// Ctrl+F — field search
if ((event.metaKey || event.ctrlKey) && key === "f" && !this._isInInput(event)) {
  event.preventDefault()
  this.c.zoomManager.openSearch()
  return
}

// Ctrl+Plus — zoom in
if ((event.metaKey || event.ctrlKey) && (key === "=" || key === "+")) {
  event.preventDefault()
  this.c.zoomManager.zoomIn()
  return
}

// Ctrl+Minus — zoom out
if ((event.metaKey || event.ctrlKey) && key === "-") {
  event.preventDefault()
  this.c.zoomManager.zoomOut()
  return
}

// Ctrl+0 — zoom reset
if ((event.metaKey || event.ctrlKey) && key === "0") {
  event.preventDefault()
  this.c.zoomManager.zoomReset()
  return
}
```

- [ ] **Step 6: Add components to _editor.html.erb**

Inside the canvas area (with `position: relative`):

```erb
<%= render PageBuilder::ZoomControlsComponent.new %>
<%= render PageBuilder::MiniMapComponent.new %>
```

- [ ] **Step 7: Run specs and test**

```bash
bundle exec rspec spec/components/page_builder/zoom_controls_component_spec.rb spec/components/page_builder/mini_map_component_spec.rb -v
```

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/page_builder/zoom_manager.js app/components/page_builder/zoom_controls_component* app/components/page_builder/mini_map_component* spec/components/page_builder/zoom_controls_component_spec.rb spec/components/page_builder/mini_map_component_spec.rb app/javascript/controllers/page_builder/keyboard_manager.js app/javascript/controllers/page_builder_controller.js app/views/pages/_editor.html.erb
git commit -m "feat(page-builder): add canvas zoom, mini-map, and field search"
```

---

## Task 4: Breadcrumb Navigation

**Files:**
- Create: `app/components/page_builder/breadcrumb_component.rb`
- Create: `app/components/page_builder/breadcrumb_component.html.erb`
- Create: `spec/components/page_builder/breadcrumb_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder/property_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js`

- [ ] **Step 1: Write component spec**

```ruby
# spec/components/page_builder/breadcrumb_component_spec.rb
require "rails_helper"
RSpec.describe PageBuilder::BreadcrumbComponent, type: :component do
  it "renders a breadcrumb container" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-page-builder-target='breadcrumbBar']")
  end
end
```

- [ ] **Step 2: Write component**

```ruby
class PageBuilder::BreadcrumbComponent < ApplicationComponent
end
```

```erb
<div class="hidden px-3 py-1.5 border-b border-gray-100 bg-gray-50/50" data-page-builder-target="breadcrumbBar">
  <div class="flex items-center gap-1 text-xs text-gray-500" data-page-builder-target="breadcrumbContent">
  </div>
</div>
```

- [ ] **Step 3: Add breadcrumb rendering to property_manager.js**

Add method to build breadcrumb trail for a selected field:

```javascript
_renderBreadcrumb(field) {
  if (!this.c.hasBreadcrumbBarTarget) return

  const trail = this._buildBreadcrumbTrail(field)

  if (trail.length <= 1) {
    this.c.breadcrumbBarTarget.classList.add("hidden")
    return
  }

  this.c.breadcrumbBarTarget.classList.remove("hidden")

  const html = trail.map((item, idx) => {
    const isLast = idx === trail.length - 1
    const chevron = isLast ? "" : '<svg class="w-3 h-3 text-gray-300 mx-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>'

    if (isLast) {
      return `<span class="text-gray-700 font-medium truncate">${item.label}</span>`
    }
    return `<button type="button" class="hover:text-indigo-600 transition-colors truncate"
                    data-action="click->page-builder#breadcrumbNavigate mouseenter->page-builder#breadcrumbHighlight mouseleave->page-builder#breadcrumbUnhighlight"
                    data-field-id="${item.id}">${item.label}</button>${chevron}`
  }).join("")

  this.c.breadcrumbContentTarget.innerHTML = html
}

_buildBreadcrumbTrail(field) {
  const trail = []
  const pageName = this.c.currentPage?.name || "Page 1"
  trail.push({ label: pageName, id: null })

  // Check if field is inside a section
  const fields = this.c.currentPageFields
  for (const f of fields) {
    if (f.field_type === "section" && f.id !== field.id) {
      // Check if our field comes after this section and before the next section
      const sectionIdx = fields.indexOf(f)
      const fieldIdx = fields.indexOf(field)
      if (fieldIdx > sectionIdx) {
        const nextSection = fields.slice(sectionIdx + 1).find(nf => nf.field_type === "section")
        const nextIdx = nextSection ? fields.indexOf(nextSection) : fields.length
        if (fieldIdx < nextIdx) {
          trail.push({ label: f.label || "Section", id: f.id })
          break
        }
      }
    }

    // Check if field is inside a group
    if (f.type === "field_group") {
      const child = f.fields?.find(cf => cf.id === field.id)
      if (child) {
        trail.push({ label: f.label || "Field Group", id: f.id })
        break
      }
    }

    // Check if field is inside columns
    if (f.field_type === "columns" && f.columns) {
      for (let colIdx = 0; colIdx < f.columns.length; colIdx++) {
        const col = f.columns[colIdx]
        if (col.fields?.find(cf => cf.id === field.id)) {
          trail.push({ label: f.label || "Columns", id: f.id })
          trail.push({ label: `Column ${colIdx + 1}`, id: `${f.id}_col_${colIdx}` })
          break
        }
      }
    }
  }

  trail.push({ label: field.label || field.field_type, id: field.id })
  return trail
}
```

Call `_renderBreadcrumb(field)` at the end of `populatePropertyPanel()`.

Add delegations:
```javascript
breadcrumbNavigate(event) { this.propertyManager.breadcrumbNavigate(event) }
breadcrumbHighlight(event) { this.propertyManager.breadcrumbHighlight(event) }
breadcrumbUnhighlight(event) { this.propertyManager.breadcrumbUnhighlight(event) }
```

Add targets: `"breadcrumbBar", "breadcrumbContent"`

Add methods:
```javascript
breadcrumbNavigate(event) {
  const fieldId = event.currentTarget.dataset.fieldId
  if (fieldId) this.c.fieldManager.selectFieldById(fieldId)
}

breadcrumbHighlight(event) {
  const fieldId = event.currentTarget.dataset.fieldId
  const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${fieldId}"]`)
  if (card) card.classList.add("ring-2", "ring-indigo-300", "ring-offset-1")
}

breadcrumbUnhighlight(event) {
  const fieldId = event.currentTarget.dataset.fieldId
  const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${fieldId}"]`)
  if (card) card.classList.remove("ring-2", "ring-indigo-300", "ring-offset-1")
}
```

- [ ] **Step 4: Add to property panel**

In `_property_panel.html.erb`, after the header and before the tab bar:

```erb
<%= render PageBuilder::BreadcrumbComponent.new %>
```

- [ ] **Step 5: Run spec and test**

```bash
bundle exec rspec spec/components/page_builder/breadcrumb_component_spec.rb -v
```

- [ ] **Step 6: Commit**

```bash
git add app/components/page_builder/breadcrumb_component* spec/components/page_builder/breadcrumb_component_spec.rb app/javascript/controllers/page_builder/property_manager.js app/views/pages/_property_panel.html.erb app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): add breadcrumb navigation for nested fields"
```

---

## Task 5: Context Menu

**Files:**
- Create: `app/javascript/controllers/page_builder/context_menu_manager.js`
- Create: `app/components/page_builder/context_menu_component.rb`
- Create: `app/components/page_builder/context_menu_component.html.erb`
- Create: `spec/components/page_builder/context_menu_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder_controller.js`
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (add contextmenu action to cards)
- Modify: `app/views/pages/_editor.html.erb`

- [ ] **Step 1: Write component spec**

```ruby
# spec/components/page_builder/context_menu_component_spec.rb
require "rails_helper"
RSpec.describe PageBuilder::ContextMenuComponent, type: :component do
  it "renders a hidden context menu container" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-page-builder-target='contextMenu']")
    expect(page).to have_css(".hidden")
  end
end
```

- [ ] **Step 2: Write component**

```ruby
class PageBuilder::ContextMenuComponent < ApplicationComponent
end
```

```erb
<div class="hidden fixed z-50" data-page-builder-target="contextMenu">
  <div class="bg-white rounded-lg shadow-xl border border-gray-200 py-1 w-48 text-sm" data-page-builder-target="contextMenuContent">
  </div>
</div>
```

- [ ] **Step 3: Create context_menu_manager.js**

```javascript
import { BaseManager } from "controllers/page_builder/base_manager"

export class ContextMenuManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this._onClickOutside = (e) => {
      if (!e.target.closest("[data-page-builder-target='contextMenu']")) this.close()
    }
  }

  openForField(event) {
    event.preventDefault()
    event.stopPropagation()

    const card = event.currentTarget.closest("[data-field-id]")
    if (!card) return

    const fieldId = card.dataset.fieldId
    const field = this.c.allFields.find(f => f.id === fieldId)
    if (!field) return

    // Select the field if not already selected
    if (!this.c.selectionManager.isSelected(fieldId)) {
      this.c.selectionManager._singleSelect(fieldId)
      this.c.selectionManager.updateVisuals()
    }

    const items = this._fieldMenuItems(field)
    this._show(event.clientX, event.clientY, items)
  }

  openForCanvas(event) {
    event.preventDefault()
    // Only if right-clicked on empty canvas area, not on a field card
    if (event.target.closest("[data-field-id]")) return

    const items = [
      this.c.clipboardManager.clipboard.length > 0
        ? { label: "Paste", shortcut: "Ctrl+V", action: () => this.c.clipboardManager.paste() }
        : { label: "Paste", shortcut: "Ctrl+V", disabled: true },
      { type: "divider" },
      { label: "Add Field", action: () => this.c.commandPaletteManager.open() },
      { label: "Select All", shortcut: "Ctrl+A", action: () => this.c.selectionManager.selectAll() }
    ]
    this._show(event.clientX, event.clientY, items)
  }

  close() {
    if (this.c.hasContextMenuTarget) {
      this.c.contextMenuTarget.classList.add("hidden")
    }
    document.removeEventListener("click", this._onClickOutside)
  }

  _fieldMenuItems(field) {
    const isGroup = field.type === "field_group"
    const items = [
      { label: "Edit Label", action: () => { this.close(); this._triggerInlineEdit(field) } },
      { label: "Duplicate", shortcut: "Ctrl+D", action: () => { this.close(); this.c.clipboardManager.duplicateSelected() } },
      { label: "Copy", shortcut: "Ctrl+C", action: () => { this.close(); this.c.clipboardManager.copy() } },
      { label: "Cut", shortcut: "Ctrl+X", action: () => { this.close(); this.c.clipboardManager.cut() } },
      this.c.clipboardManager.clipboard.length > 0
        ? { label: "Paste After", shortcut: "Ctrl+V", action: () => { this.close(); this.c.clipboardManager.paste() } }
        : { label: "Paste After", shortcut: "Ctrl+V", disabled: true },
      { type: "divider" },
      { label: "Width", submenu: [
        { label: "Full", action: () => this._setWidth(field, "full") },
        { label: "3/4", action: () => this._setWidth(field, "three_quarters") },
        { label: "2/3", action: () => this._setWidth(field, "two_thirds") },
        { label: "Half", action: () => this._setWidth(field, "half") },
        { label: "1/3", action: () => this._setWidth(field, "third") },
        { label: "1/4", action: () => this._setWidth(field, "quarter") }
      ]},
      { type: "divider" },
      { label: "Save as Template", action: () => { this.close(); this.c.fieldManager.saveFieldAsTemplate({ currentTarget: { dataset: { fieldId: field.id } }, stopPropagation: () => {} }) } },
      { type: "divider" },
      { label: "Delete", shortcut: "Del", danger: true, action: () => { this.close(); this.c.fieldManager.deleteField() } }
    ]

    if (isGroup) {
      items.splice(-2, 0, { label: "Ungroup", action: () => { this.close(); this.c.fieldManager.ungroupFields({ currentTarget: { dataset: { groupId: field.id } }, stopPropagation: () => {} }) } })
    }

    return items
  }

  _show(x, y, items) {
    if (!this.c.hasContextMenuTarget || !this.c.hasContextMenuContentTarget) return

    const menu = this.c.contextMenuTarget
    const content = this.c.contextMenuContentTarget

    content.innerHTML = items.map((item, idx) => {
      if (item.type === "divider") return '<hr class="my-1 border-gray-100">'
      if (item.disabled) return `<div class="px-3 py-1.5 text-gray-300 cursor-not-allowed flex justify-between"><span>${item.label}</span>${item.shortcut ? `<span class="text-[10px]">${item.shortcut}</span>` : ""}</div>`
      if (item.submenu) {
        return `<div class="relative group/sub">
          <div class="px-3 py-1.5 text-gray-700 hover:bg-gray-50 flex justify-between cursor-pointer">
            <span>${item.label}</span><svg class="w-3 h-3 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>
          </div>
          <div class="hidden group-hover/sub:block absolute left-full top-0 bg-white rounded-lg shadow-xl border border-gray-200 py-1 w-32">
            ${item.submenu.map((sub, si) => `<button type="button" class="w-full px-3 py-1.5 text-left text-gray-700 hover:bg-gray-50" data-context-action="${idx}_${si}">${sub.label}</button>`).join("")}
          </div>
        </div>`
      }
      const dangerClass = item.danger ? "text-red-600 hover:bg-red-50" : "text-gray-700 hover:bg-gray-50"
      return `<button type="button" class="w-full px-3 py-1.5 text-left ${dangerClass} flex justify-between" data-context-action="${idx}">
        <span>${item.label}</span>${item.shortcut ? `<span class="text-[10px] text-gray-400">${item.shortcut}</span>` : ""}
      </button>`
    }).join("")

    // Attach click handlers
    content.querySelectorAll("[data-context-action]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        const parts = btn.dataset.contextAction.split("_")
        const item = items[parseInt(parts[0])]
        if (parts.length === 2 && item.submenu) {
          item.submenu[parseInt(parts[1])].action?.()
        } else {
          item.action?.()
        }
        this.close()
      })
    })

    // Position menu within viewport
    menu.style.left = `${Math.min(x, window.innerWidth - 200)}px`
    menu.style.top = `${Math.min(y, window.innerHeight - 300)}px`
    menu.classList.remove("hidden")

    setTimeout(() => document.addEventListener("click", this._onClickOutside), 0)
  }

  _setWidth(field, width) {
    this.c.saveState()
    field.width = width
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
    this.close()
  }

  _triggerInlineEdit(field) {
    const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${field.id}"]`)
    const editable = card?.querySelector("[data-inline-edit-property]")
    if (editable) {
      editable.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
    }
  }
}
```

- [ ] **Step 4: Register in controller**

Add targets: `"contextMenu", "contextMenuContent"`

Add delegations:
```javascript
openFieldContextMenu(event) { this.contextMenuManager.openForField(event) }
openCanvasContextMenu(event) { this.contextMenuManager.openForCanvas(event) }
closeContextMenu() { this.contextMenuManager.close() }
```

Import and instantiate: `this.contextMenuManager = new ContextMenuManager(this)`

- [ ] **Step 5: Add contextmenu event to field cards**

In `field_manager.js`, in `createFieldCard()`, add to the card's `data-action`:

```javascript
div.dataset.action += " contextmenu->page-builder#openFieldContextMenu"
```

In `_editor.html.erb`, on the canvas drop zone div, add:

```erb
data-action="contextmenu->page-builder#openCanvasContextMenu"
```

- [ ] **Step 6: Add component to _editor.html.erb**

```erb
<%= render PageBuilder::ContextMenuComponent.new %>
```

- [ ] **Step 7: Add Escape handler for context menu**

In keyboard_manager.js, in the Escape cascade, add context menu closing before other modals:

```javascript
// Close context menu first
if (this.c.hasContextMenuTarget && !this.c.contextMenuTarget.classList.contains("hidden")) {
  this.c.contextMenuManager.close()
  return
}
```

- [ ] **Step 8: Run specs and test**

```bash
bundle exec rspec spec/components/page_builder/context_menu_component_spec.rb -v
```

Test: Right-click a field card → context menu appears with Edit Label, Duplicate, Copy, Cut, Paste After, Width submenu, Save as Template, Delete. Right-click empty canvas → Paste, Add Field, Select All.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/page_builder/context_menu_manager.js app/components/page_builder/context_menu_component* spec/components/page_builder/context_menu_component_spec.rb app/javascript/controllers/page_builder_controller.js app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder/keyboard_manager.js app/views/pages/_editor.html.erb
git commit -m "feat(page-builder): add right-click context menus for fields and canvas"
```

---

## Task 6: Final Precompile and Integration Test

- [ ] **Step 1: Run all specs**

```bash
bundle exec rspec spec/components/page_builder/ spec/models/field_template_spec.rb -v
```

- [ ] **Step 2: Precompile and restart**

```bash
RAILS_ENV=development bundle exec rails assets:precompile
pkill -f puma; sleep 1; RAILS_ENV=development bin/rails server -b 0.0.0.0 -p 3000 &
```

- [ ] **Step 3: Full integration test**

At `/96546124/pages/32/edit`:

1. **Field Templates**: Select a configured field → right-click → "Save as Template" → enter name → saved. Press "/" → Templates section shows saved template → select → field inserted.
2. **Slash Commands**: Press "/" → palette opens → type "hea" → "Heading" highlighted → Enter → heading added. Type "save" → "Save" action → executes save.
3. **Canvas Zoom**: Click + → zoom to 125% → canvas scales. Click - → zoom to 100%. Ctrl+0 resets. Click mini-map toggle → mini-map appears.
4. **Field Search**: Ctrl+F → search bar appears → type "email" → non-matching fields dim → "1 of 12" counter. Escape closes.
5. **Breadcrumbs**: Click a field inside columns → breadcrumb shows "Page 1 > Columns > Column 1 > Field". Click "Columns" → selects the columns element. Hover "Columns" → brief highlight.
6. **Context Menu**: Right-click a field → full menu. Width submenu works. Right-click empty canvas → Paste/Add Field/Select All. Right-click a field group → includes "Ungroup".
7. **Undo/redo**: All new operations undoable.
8. **Save**: Ctrl+S saves without errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(page-builder): Phase 3 complete - power features

- Field templates (save/load/manage with Trailblazer CRUD)
- Slash command palette with fuzzy search
- Canvas zoom (50-150%) with mini-map and field search
- Breadcrumb navigation for nested fields
- Right-click context menus for fields, groups, and canvas
- Full keyboard shortcut integration"
```

# JotForm Page Builder Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the page builder with JotForm-style features using ViewComponents, consistent styling, and Rails 8 best practices.

**Architecture:** Component-first rebuild using ViewComponents with TailwindCSS, StimulusJS controllers, and design tokens for consistent styling. Property sidebar behavior matches Anysys (slides in/out from right).

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec

---

## Phase 1: Foundation - Design Tokens & Component Classes

### Task 1: Enhance Design Tokens

**Files:**
- Modify: `app/components/concerns/design_tokens.rb`
- Test: `spec/components/concerns/design_tokens_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/concerns/design_tokens_spec.rb
require 'rails_helper'

RSpec.describe DesignTokens do
  describe 'color tokens' do
    it 'defines PRIMARY_LIGHT color' do
      expect(DesignTokens::PRIMARY_LIGHT).to eq('indigo-50')
    end

    it 'defines BORDER_DARK color' do
      expect(DesignTokens::BORDER_DARK).to eq('gray-300')
    end

    it 'defines TEXT color' do
      expect(DesignTokens::TEXT).to eq('gray-900')
    end

    it 'defines TEXT_MUTED color' do
      expect(DesignTokens::TEXT_MUTED).to eq('gray-500')
    end

    it 'defines TEXT_LIGHT color' do
      expect(DesignTokens::TEXT_LIGHT).to eq('gray-400')
    end
  end

  describe 'ring tokens' do
    it 'defines RING token' do
      expect(DesignTokens::RING).to eq('ring-1 ring-gray-200')
    end

    it 'defines RING_FOCUS token' do
      expect(DesignTokens::RING_FOCUS).to eq('focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/concerns/design_tokens_spec.rb -v`
Expected: FAIL with "uninitialized constant DesignTokens::PRIMARY_LIGHT"

**Step 3: Write minimal implementation**

```ruby
# app/components/concerns/design_tokens.rb
# frozen_string_literal: true

module DesignTokens
  # Colors
  PRIMARY = "indigo-600"
  PRIMARY_HOVER = "indigo-700"
  PRIMARY_LIGHT = "indigo-50"
  SECONDARY = "gray-600"
  BORDER = "gray-200"
  BORDER_DARK = "gray-300"
  SUCCESS = "green-600"
  WARNING = "yellow-600"
  ERROR = "red-600"
  TEXT = "gray-900"
  TEXT_MUTED = "gray-500"
  TEXT_LIGHT = "gray-400"

  # Spacing
  SPACING_XS = "1"
  SPACING_SM = "2"
  SPACING_MD = "4"
  SPACING_LG = "6"
  SPACING_XL = "8"

  # Border radius
  ROUNDED_SM = "rounded"
  ROUNDED_MD = "rounded-lg"
  ROUNDED_LG = "rounded-xl"

  # Shadows
  SHADOW_SM = "shadow-sm"
  SHADOW_MD = "shadow-md"
  SHADOW_LG = "shadow-lg"
  SHADOW_XL = "shadow-xl"

  # Transitions
  TRANSITION_DEFAULT = "transition-all duration-200 ease-in-out"
  TRANSITION_FAST = "transition-all duration-150 ease-out"
  TRANSITION_SLOW = "transition-all duration-300 ease-in-out"

  # Ring (focus states)
  RING = "ring-1 ring-gray-200"
  RING_FOCUS = "focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/concerns/design_tokens_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/concerns/design_tokens.rb spec/components/concerns/design_tokens_spec.rb
git commit -m "feat: enhance design tokens with additional colors and ring states"
```

---

### Task 2: Enhance Component Classes

**Files:**
- Modify: `app/components/concerns/component_classes.rb`
- Test: `spec/components/concerns/component_classes_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/concerns/component_classes_spec.rb
require 'rails_helper'

RSpec.describe ComponentClasses do
  describe 'button classes' do
    it 'defines BTN_DANGER class' do
      expect(ComponentClasses::BTN_DANGER).to include('text-red-600')
    end

    it 'defines BTN_SM class' do
      expect(ComponentClasses::BTN_SM).to include('px-2 py-1')
    end
  end

  describe 'sidebar classes' do
    it 'defines SIDEBAR class' do
      expect(ComponentClasses::SIDEBAR).to include('bg-white')
      expect(ComponentClasses::SIDEBAR).to include('border-l')
    end

    it 'defines SIDEBAR_HEADER class' do
      expect(ComponentClasses::SIDEBAR_HEADER).to include('border-b')
    end

    it 'defines SIDEBAR_BODY class' do
      expect(ComponentClasses::SIDEBAR_BODY).to include('overflow-y-auto')
    end

    it 'defines SIDEBAR_FOOTER class' do
      expect(ComponentClasses::SIDEBAR_FOOTER).to include('border-t')
    end
  end

  describe 'section classes' do
    it 'defines SECTION_HEADER class' do
      expect(ComponentClasses::SECTION_HEADER).to include('hover:bg-gray-50')
    end

    it 'defines SECTION_TITLE class' do
      expect(ComponentClasses::SECTION_TITLE).to include('uppercase')
    end
  end

  describe 'close button' do
    it 'defines CLOSE_BTN class' do
      expect(ComponentClasses::CLOSE_BTN).to include('hover:text-gray-600')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/concerns/component_classes_spec.rb -v`
Expected: FAIL with "uninitialized constant ComponentClasses::BTN_DANGER"

**Step 3: Write minimal implementation**

```ruby
# app/components/concerns/component_classes.rb
# frozen_string_literal: true

module ComponentClasses
  # Buttons
  BTN_PRIMARY = "px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 " \
                "transition-all duration-200 focus:ring-2 focus:ring-indigo-500 " \
                "focus:ring-offset-2 font-medium disabled:opacity-50 disabled:cursor-not-allowed"

  BTN_SECONDARY = "px-4 py-2 bg-white text-gray-700 border border-gray-300 rounded-lg " \
                  "hover:bg-gray-50 transition-all duration-200 focus:ring-2 " \
                  "focus:ring-indigo-500 focus:ring-offset-2 font-medium"

  BTN_GHOST = "px-4 py-2 text-gray-600 rounded-lg hover:bg-gray-100 " \
              "transition-all duration-200 focus:ring-2 focus:ring-gray-300"

  BTN_ICON = "p-2 text-gray-500 rounded-lg hover:bg-gray-100 hover:text-gray-700 " \
             "transition-all duration-200 focus:ring-2 focus:ring-gray-300"

  BTN_DANGER = "px-3 py-1.5 text-sm font-medium text-red-600 bg-white " \
               "border border-gray-300 rounded-md shadow-sm " \
               "hover:bg-red-50 hover:border-red-300 transition-colors"

  BTN_SM = "px-2 py-1 text-xs font-medium rounded-md transition-colors"

  # Cards
  CARD = "bg-white border border-gray-200 rounded-lg shadow-sm"

  CARD_HOVER = "bg-white border border-gray-200 rounded-lg shadow-sm " \
               "hover:border-indigo-300 hover:shadow-md transition-all duration-200 cursor-pointer"

  CARD_SELECTED = "bg-indigo-50 border-2 border-indigo-500 rounded-lg shadow-sm"

  # Inputs
  INPUT = "w-full px-3 py-2 border border-gray-300 rounded-lg " \
          "focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 " \
          "transition-all duration-150 placeholder-gray-400"

  INPUT_SM = "w-full px-3 py-2 text-sm border border-gray-300 rounded-md " \
             "shadow-sm placeholder:text-gray-400 focus:outline-none " \
             "focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"

  INPUT_ERROR = "w-full px-3 py-2 border border-red-300 rounded-lg " \
                "focus:ring-2 focus:ring-red-500 focus:border-red-500 " \
                "transition-all duration-150 bg-red-50"

  # Floating panel
  FLOATING_PANEL = "absolute bg-white border border-gray-200 rounded-xl shadow-xl " \
                   "p-4 z-50 min-w-80 animate-fade-in"

  # Labels
  LABEL = "block text-sm font-medium text-gray-700 mb-1"
  LABEL_SM = "block text-xs font-medium text-gray-700 mb-1.5"
  LABEL_OPTIONAL = "text-gray-400 font-normal"

  # Help text
  HELP_TEXT = "mt-1 text-sm text-gray-500"

  # Badges
  BADGE = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
  BADGE_PRIMARY = "#{BADGE} bg-indigo-100 text-indigo-800"
  BADGE_SECONDARY = "#{BADGE} bg-gray-100 text-gray-800"
  BADGE_SUCCESS = "#{BADGE} bg-green-100 text-green-800"

  # Dropdowns
  DROPDOWN = "absolute right-0 mt-2 w-56 rounded-lg bg-white shadow-lg " \
             "ring-1 ring-black ring-opacity-5 z-50 animate-fade-in"

  DROPDOWN_ITEM = "block w-full px-4 py-2 text-left text-sm text-gray-700 " \
                  "hover:bg-gray-100 transition-colors duration-150"

  # Sidebar (property panel - matches Anysys)
  SIDEBAR = "bg-white border-l border-gray-200 flex-shrink-0"
  SIDEBAR_HEADER = "flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-gray-50"
  SIDEBAR_BODY = "flex-1 overflow-y-auto p-4 space-y-4"
  SIDEBAR_FOOTER = "flex items-center justify-between gap-2 px-4 py-3 border-t border-gray-200 bg-gray-50"

  # Section headers (collapsible)
  SECTION_HEADER = "w-full flex items-center justify-between px-4 py-3 hover:bg-gray-50 transition-colors text-left"
  SECTION_TITLE = "text-xs font-semibold text-gray-500 uppercase tracking-wider"

  # Close button
  CLOSE_BTN = "text-gray-400 hover:text-gray-600 p-1 rounded hover:bg-gray-100 transition-colors"
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/concerns/component_classes_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/concerns/component_classes.rb spec/components/concerns/component_classes_spec.rb
git commit -m "feat: enhance component classes with sidebar and section styles"
```

---

## Phase 2: Property Sidebar Components

### Task 3: Create OptionsEditorComponent

**Files:**
- Create: `app/components/page_builder/options_editor_component.rb`
- Create: `app/components/page_builder/options_editor_component.html.erb`
- Test: `spec/components/page_builder/options_editor_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/options_editor_component_spec.rb
require 'rails_helper'

RSpec.describe PageBuilder::OptionsEditorComponent, type: :component do
  let(:field_id) { 'field_123' }
  let(:options) do
    [
      { 'label' => 'Option 1', 'value' => 'opt1' },
      { 'label' => 'Option 2', 'value' => 'opt2' }
    ]
  end

  it 'renders the options editor container' do
    render_inline(described_class.new(field_id: field_id, options: options))
    expect(page).to have_css('[data-options-editor]')
  end

  it 'renders existing options' do
    render_inline(described_class.new(field_id: field_id, options: options))
    expect(page).to have_field(type: 'text', with: 'Option 1')
    expect(page).to have_field(type: 'text', with: 'Option 2')
  end

  it 'renders add option button' do
    render_inline(described_class.new(field_id: field_id, options: options))
    expect(page).to have_button('Add Option')
  end

  it 'renders allow other toggle' do
    render_inline(described_class.new(field_id: field_id, options: options, allow_other: true))
    expect(page).to have_checked_field('Allow "Other" option')
  end

  it 'renders empty state when no options' do
    render_inline(described_class.new(field_id: field_id, options: []))
    expect(page).to have_button('Add Option')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/options_editor_component_spec.rb -v`
Expected: FAIL with "uninitialized constant PageBuilder::OptionsEditorComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/options_editor_component.rb
# frozen_string_literal: true

module PageBuilder
  class OptionsEditorComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    attr_reader :field_id, :options, :allow_other

    def initialize(field_id:, options: [], allow_other: false)
      @field_id = field_id
      @options = options || []
      @allow_other = allow_other
    end
  end
end
```

```erb
<%# app/components/page_builder/options_editor_component.html.erb %>
<div data-options-editor data-field-id="<%= field_id %>" class="space-y-3">
  <%# Options list %>
  <div class="space-y-2" data-page-builder-target="optionsList">
    <% options.each_with_index do |option, index| %>
      <div class="flex items-center gap-2 group" data-option-index="<%= index %>">
        <%# Drag handle %>
        <button type="button" class="cursor-grab text-gray-400 hover:text-gray-600">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 8h16M4 16h16" />
          </svg>
        </button>

        <%# Label input %>
        <input type="text"
               class="<%= ComponentClasses::INPUT_SM %> flex-1"
               placeholder="Label"
               value="<%= option['label'] %>"
               data-action="input->page-builder#updateOption"
               data-field-id="<%= field_id %>"
               data-option-index="<%= index %>"
               data-property="label">

        <%# Value input %>
        <input type="text"
               class="<%= ComponentClasses::INPUT_SM %> w-24"
               placeholder="Value"
               value="<%= option['value'] %>"
               data-action="input->page-builder#updateOption"
               data-field-id="<%= field_id %>"
               data-option-index="<%= index %>"
               data-property="value">

        <%# Delete button %>
        <button type="button"
                class="p-1 text-gray-400 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
                data-action="click->page-builder#removeOption"
                data-field-id="<%= field_id %>"
                data-option-index="<%= index %>">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    <% end %>
  </div>

  <%# Add option button %>
  <button type="button"
          class="w-full px-3 py-2 text-sm text-gray-600 border border-dashed border-gray-300 rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
          data-action="click->page-builder#addOption"
          data-field-id="<%= field_id %>">
    <svg class="w-4 h-4 inline-block mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
    </svg>
    Add Option
  </button>

  <%# Allow other toggle %>
  <label class="flex items-center mt-3">
    <input type="checkbox"
           <%= 'checked' if allow_other %>
           class="w-4 h-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
           data-action="change->page-builder#updateFieldProperty"
           data-field-id="<%= field_id %>"
           data-property="allow_other">
    <span class="ml-2 text-sm text-gray-700">Allow "Other" option</span>
  </label>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/options_editor_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/options_editor_component.rb app/components/page_builder/options_editor_component.html.erb spec/components/page_builder/options_editor_component_spec.rb
git commit -m "feat: add OptionsEditorComponent for select/radio/checkbox fields"
```

---

### Task 4: Create ConditionBuilderComponent

**Files:**
- Create: `app/components/page_builder/condition_builder_component.rb`
- Create: `app/components/page_builder/condition_builder_component.html.erb`
- Test: `spec/components/page_builder/condition_builder_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/condition_builder_component_spec.rb
require 'rails_helper'

RSpec.describe PageBuilder::ConditionBuilderComponent, type: :component do
  let(:field_id) { 'field_123' }
  let(:available_fields) do
    [
      { 'id' => 'field_1', 'label' => 'First Name' },
      { 'id' => 'field_2', 'label' => 'Email' }
    ]
  end
  let(:conditions) do
    [
      { 'field_id' => 'field_1', 'operator' => 'equals', 'value' => 'test', 'logic' => 'and' }
    ]
  end

  it 'renders the condition builder container' do
    render_inline(described_class.new(field_id: field_id, conditions: conditions, available_fields: available_fields))
    expect(page).to have_css('[data-condition-builder]')
  end

  it 'renders existing conditions' do
    render_inline(described_class.new(field_id: field_id, conditions: conditions, available_fields: available_fields))
    expect(page).to have_select(selected: 'First Name')
    expect(page).to have_select(selected: 'Equals')
  end

  it 'renders add condition button' do
    render_inline(described_class.new(field_id: field_id, conditions: [], available_fields: available_fields))
    expect(page).to have_button('Add Condition')
  end

  it 'renders show/hide action selector' do
    render_inline(described_class.new(field_id: field_id, conditions: conditions, available_fields: available_fields, action: 'show'))
    expect(page).to have_text('Show this field when')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/condition_builder_component_spec.rb -v`
Expected: FAIL with "uninitialized constant PageBuilder::ConditionBuilderComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/condition_builder_component.rb
# frozen_string_literal: true

module PageBuilder
  class ConditionBuilderComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    OPERATORS = [
      { value: 'equals', label: 'Equals' },
      { value: 'not_equals', label: 'Not equals' },
      { value: 'contains', label: 'Contains' },
      { value: 'not_contains', label: 'Not contains' },
      { value: 'greater_than', label: 'Greater than' },
      { value: 'less_than', label: 'Less than' },
      { value: 'is_empty', label: 'Is empty' },
      { value: 'is_not_empty', label: 'Is not empty' }
    ].freeze

    attr_reader :field_id, :conditions, :available_fields, :action

    def initialize(field_id:, conditions: [], available_fields: [], action: 'show')
      @field_id = field_id
      @conditions = conditions || []
      @available_fields = available_fields || []
      @action = action
    end

    def operators
      OPERATORS
    end
  end
end
```

```erb
<%# app/components/page_builder/condition_builder_component.html.erb %>
<div data-condition-builder data-field-id="<%= field_id %>" class="space-y-3">
  <%# Header %>
  <div class="flex items-center justify-between">
    <span class="text-sm font-medium text-gray-700">
      <%= action == 'show' ? 'Show' : 'Hide' %> this field when
    </span>
    <select class="text-xs border border-gray-200 rounded px-2 py-1"
            data-action="change->page-builder#updateConditionAction"
            data-field-id="<%= field_id %>">
      <option value="show" <%= 'selected' if action == 'show' %>>Show</option>
      <option value="hide" <%= 'selected' if action == 'hide' %>>Hide</option>
    </select>
  </div>

  <%# Conditions list %>
  <div class="space-y-2" data-page-builder-target="conditionsList">
    <% conditions.each_with_index do |condition, index| %>
      <div class="p-3 bg-gray-50 rounded-lg border border-gray-200 space-y-2">
        <%# Logic prefix (AND/OR) for non-first conditions %>
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-gray-500">
            <%= index == 0 ? 'If' : condition['logic']&.upcase || 'AND' %>
          </span>
          <button type="button"
                  class="text-gray-400 hover:text-red-500 transition-colors"
                  data-action="click->page-builder#removeCondition"
                  data-field-id="<%= field_id %>"
                  data-condition-index="<%= index %>">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%# Field selector %>
        <select class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                data-action="change->page-builder#updateCondition"
                data-field-id="<%= field_id %>"
                data-condition-index="<%= index %>"
                data-property="field_id">
          <option value="">Select field...</option>
          <% available_fields.each do |f| %>
            <option value="<%= f['id'] %>" <%= 'selected' if condition['field_id'] == f['id'] %>><%= f['label'] %></option>
          <% end %>
        </select>

        <%# Operator selector %>
        <select class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                data-action="change->page-builder#updateCondition"
                data-field-id="<%= field_id %>"
                data-condition-index="<%= index %>"
                data-property="operator">
          <% operators.each do |op| %>
            <option value="<%= op[:value] %>" <%= 'selected' if condition['operator'] == op[:value] %>><%= op[:label] %></option>
          <% end %>
        </select>

        <%# Value input (hidden for is_empty/is_not_empty) %>
        <% unless %w[is_empty is_not_empty].include?(condition['operator']) %>
          <input type="text"
                 class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                 placeholder="Value"
                 value="<%= condition['value'] %>"
                 data-action="input->page-builder#updateCondition"
                 data-field-id="<%= field_id %>"
                 data-condition-index="<%= index %>"
                 data-property="value">
        <% end %>

        <%# Logic selector (for non-first conditions) %>
        <% if index > 0 %>
          <select class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                  data-action="change->page-builder#updateCondition"
                  data-field-id="<%= field_id %>"
                  data-condition-index="<%= index %>"
                  data-property="logic">
            <option value="and" <%= 'selected' if condition['logic'] == 'and' %>>AND</option>
            <option value="or" <%= 'selected' if condition['logic'] == 'or' %>>OR</option>
          </select>
        <% end %>
      </div>
    <% end %>
  </div>

  <%# Add condition button %>
  <button type="button"
          class="w-full px-3 py-2 text-sm text-gray-600 border border-dashed border-gray-300 rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
          data-action="click->page-builder#addCondition"
          data-field-id="<%= field_id %>">
    <svg class="w-4 h-4 inline-block mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
    </svg>
    Add Condition
  </button>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/condition_builder_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/condition_builder_component.rb app/components/page_builder/condition_builder_component.html.erb spec/components/page_builder/condition_builder_component_spec.rb
git commit -m "feat: add ConditionBuilderComponent for conditional field visibility"
```

---

### Task 5: Create FormSettingsComponent

**Files:**
- Create: `app/components/page_builder/form_settings_component.rb`
- Create: `app/components/page_builder/form_settings_component.html.erb`
- Test: `spec/components/page_builder/form_settings_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/form_settings_component_spec.rb
require 'rails_helper'

RSpec.describe PageBuilder::FormSettingsComponent, type: :component do
  let(:settings) do
    {
      'title' => 'Contact Form',
      'description' => 'Please fill out this form',
      'submit_text' => 'Send Message',
      'submit_alignment' => 'center',
      'thank_you_mode' => 'message',
      'thank_you_message' => 'Thank you for your submission!'
    }
  end

  it 'renders form settings container' do
    render_inline(described_class.new(settings: settings))
    expect(page).to have_css('[data-form-settings]')
  end

  it 'renders form title field' do
    render_inline(described_class.new(settings: settings))
    expect(page).to have_field('Form Title', with: 'Contact Form')
  end

  it 'renders submit button settings' do
    render_inline(described_class.new(settings: settings))
    expect(page).to have_field('Button Text', with: 'Send Message')
  end

  it 'renders thank you page settings' do
    render_inline(described_class.new(settings: settings))
    expect(page).to have_text('Thank You Page')
  end

  context 'with wizard enabled' do
    let(:wizard_settings) do
      {
        'enabled' => true,
        'show_progress' => true,
        'progress_style' => 'steps'
      }
    end

    it 'renders wizard settings section' do
      render_inline(described_class.new(settings: settings, wizard_settings: wizard_settings))
      expect(page).to have_text('Wizard Settings')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/form_settings_component_spec.rb -v`
Expected: FAIL with "uninitialized constant PageBuilder::FormSettingsComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/form_settings_component.rb
# frozen_string_literal: true

module PageBuilder
  class FormSettingsComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    attr_reader :settings, :wizard_settings

    def initialize(settings: {}, wizard_settings: nil)
      @settings = settings || {}
      @wizard_settings = wizard_settings
    end

    def wizard_enabled?
      wizard_settings&.dig('enabled') == true
    end

    def title
      settings['title'] || ''
    end

    def description
      settings['description'] || ''
    end

    def submit_text
      settings['submit_text'] || 'Submit'
    end

    def submit_alignment
      settings['submit_alignment'] || 'right'
    end

    def thank_you_mode
      settings['thank_you_mode'] || 'message'
    end

    def thank_you_message
      settings['thank_you_message'] || 'Thank you for your submission!'
    end

    def redirect_url
      settings['redirect_url'] || ''
    end
  end
end
```

```erb
<%# app/components/page_builder/form_settings_component.html.erb %>
<div data-form-settings class="space-y-4">
  <%# Form Details Section %>
  <div class="border-b border-gray-100">
    <button type="button" data-action="click->page-builder#toggleSection"
            class="<%= ComponentClasses::SECTION_HEADER %>">
      <span class="<%= ComponentClasses::SECTION_TITLE %>">Form Details</span>
      <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div class="px-4 pb-4 space-y-4" data-page-builder-target="sectionContent">
      <div>
        <label class="<%= ComponentClasses::LABEL_SM %>">Form Title</label>
        <input type="text"
               name="form_title"
               value="<%= title %>"
               class="<%= ComponentClasses::INPUT_SM %>"
               data-action="input->page-builder#updateFormSettings"
               data-property="title">
      </div>
      <div>
        <label class="<%= ComponentClasses::LABEL_SM %>">Description</label>
        <textarea name="form_description"
                  rows="3"
                  class="<%= ComponentClasses::INPUT_SM %>"
                  data-action="input->page-builder#updateFormSettings"
                  data-property="description"><%= description %></textarea>
      </div>
    </div>
  </div>

  <%# Submit Button Section %>
  <div class="border-b border-gray-100">
    <button type="button" data-action="click->page-builder#toggleSection"
            class="<%= ComponentClasses::SECTION_HEADER %>">
      <span class="<%= ComponentClasses::SECTION_TITLE %>">Submit Button</span>
      <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div class="px-4 pb-4 space-y-4" data-page-builder-target="sectionContent">
      <div>
        <label class="<%= ComponentClasses::LABEL_SM %>">Button Text</label>
        <input type="text"
               name="submit_text"
               value="<%= submit_text %>"
               class="<%= ComponentClasses::INPUT_SM %>"
               data-action="input->page-builder#updateFormSettings"
               data-property="submit_text">
      </div>
      <div>
        <label class="<%= ComponentClasses::LABEL_SM %>">Alignment</label>
        <div class="grid grid-cols-3 gap-2">
          <% %w[left center right].each do |align| %>
            <label class="relative">
              <input type="radio"
                     name="submit_alignment"
                     value="<%= align %>"
                     <%= 'checked' if submit_alignment == align %>
                     class="peer sr-only"
                     data-action="change->page-builder#updateFormSettings"
                     data-property="submit_alignment">
              <div class="px-3 py-2 text-xs font-medium text-center border border-gray-300 rounded-lg cursor-pointer peer-checked:border-indigo-500 peer-checked:bg-indigo-50 peer-checked:text-indigo-700 hover:bg-gray-50 transition-colors">
                <%= align.capitalize %>
              </div>
            </label>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <%# Thank You Page Section %>
  <div class="border-b border-gray-100">
    <button type="button" data-action="click->page-builder#toggleSection"
            class="<%= ComponentClasses::SECTION_HEADER %>">
      <span class="<%= ComponentClasses::SECTION_TITLE %>">Thank You Page</span>
      <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div class="px-4 pb-4 space-y-4" data-page-builder-target="sectionContent">
      <div>
        <label class="<%= ComponentClasses::LABEL_SM %>">Mode</label>
        <div class="flex gap-4">
          <label class="flex items-center">
            <input type="radio"
                   name="thank_you_mode"
                   value="message"
                   <%= 'checked' if thank_you_mode == 'message' %>
                   class="w-4 h-4 text-indigo-600 border-gray-300 focus:ring-indigo-500"
                   data-action="change->page-builder#updateFormSettings"
                   data-property="thank_you_mode">
            <span class="ml-2 text-sm text-gray-700">Message</span>
          </label>
          <label class="flex items-center">
            <input type="radio"
                   name="thank_you_mode"
                   value="redirect"
                   <%= 'checked' if thank_you_mode == 'redirect' %>
                   class="w-4 h-4 text-indigo-600 border-gray-300 focus:ring-indigo-500"
                   data-action="change->page-builder#updateFormSettings"
                   data-property="thank_you_mode">
            <span class="ml-2 text-sm text-gray-700">Redirect</span>
          </label>
        </div>
      </div>

      <div data-thank-you-message <%= 'class="hidden"' if thank_you_mode == 'redirect' %>>
        <label class="<%= ComponentClasses::LABEL_SM %>">Thank You Message</label>
        <textarea name="thank_you_message"
                  rows="3"
                  class="<%= ComponentClasses::INPUT_SM %>"
                  data-action="input->page-builder#updateFormSettings"
                  data-property="thank_you_message"><%= thank_you_message %></textarea>
      </div>

      <div data-redirect-url <%= 'class="hidden"' if thank_you_mode == 'message' %>>
        <label class="<%= ComponentClasses::LABEL_SM %>">Redirect URL</label>
        <input type="url"
               name="redirect_url"
               value="<%= redirect_url %>"
               placeholder="https://example.com/thank-you"
               class="<%= ComponentClasses::INPUT_SM %>"
               data-action="input->page-builder#updateFormSettings"
               data-property="redirect_url">
      </div>
    </div>
  </div>

  <%# Wizard Settings Section (only if wizard enabled) %>
  <% if wizard_enabled? %>
    <div class="border-b border-gray-100">
      <button type="button" data-action="click->page-builder#toggleSection"
              class="<%= ComponentClasses::SECTION_HEADER %>">
        <span class="<%= ComponentClasses::SECTION_TITLE %>">Wizard Settings</span>
        <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div class="px-4 pb-4 space-y-4" data-page-builder-target="sectionContent">
        <label class="flex items-center">
          <input type="checkbox"
                 name="show_progress"
                 <%= 'checked' if wizard_settings['show_progress'] %>
                 class="w-4 h-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
                 data-action="change->page-builder#updateWizardSettings"
                 data-property="show_progress">
          <span class="ml-2 text-sm text-gray-700">Show progress bar</span>
        </label>

        <div>
          <label class="<%= ComponentClasses::LABEL_SM %>">Progress Style</label>
          <select class="<%= ComponentClasses::INPUT_SM %>"
                  data-action="change->page-builder#updateWizardSettings"
                  data-property="progress_style">
            <option value="steps" <%= 'selected' if wizard_settings['progress_style'] == 'steps' %>>Steps</option>
            <option value="bar" <%= 'selected' if wizard_settings['progress_style'] == 'bar' %>>Progress Bar</option>
            <option value="percentage" <%= 'selected' if wizard_settings['progress_style'] == 'percentage' %>>Percentage</option>
          </select>
        </div>

        <label class="flex items-center">
          <input type="checkbox"
                 name="allow_back"
                 <%= 'checked' if wizard_settings['allow_back'] %>
                 class="w-4 h-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
                 data-action="change->page-builder#updateWizardSettings"
                 data-property="allow_back">
          <span class="ml-2 text-sm text-gray-700">Allow back navigation</span>
        </label>

        <label class="flex items-center">
          <input type="checkbox"
                 name="validate_on_next"
                 <%= 'checked' if wizard_settings['validate_on_next'] %>
                 class="w-4 h-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
                 data-action="change->page-builder#updateWizardSettings"
                 data-property="validate_on_next">
          <span class="ml-2 text-sm text-gray-700">Validate before next</span>
        </label>
      </div>
    </div>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/form_settings_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/form_settings_component.rb app/components/page_builder/form_settings_component.html.erb spec/components/page_builder/form_settings_component_spec.rb
git commit -m "feat: add FormSettingsComponent for form-level configuration"
```

---

## Phase 3: New Form Field Components

### Task 6: Create RadioFieldComponent

**Files:**
- Create: `app/components/form_fields/radio_field_component.rb`
- Create: `app/components/form_fields/radio_field_component.html.erb`
- Test: `spec/components/form_fields/radio_field_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/radio_field_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::RadioFieldComponent, type: :component do
  let(:options) do
    [
      { 'label' => 'Option A', 'value' => 'a' },
      { 'label' => 'Option B', 'value' => 'b' },
      { 'label' => 'Option C', 'value' => 'c' }
    ]
  end

  it 'renders radio buttons for each option' do
    render_inline(described_class.new(field_name: :choice, label: 'Pick one', options: options))
    expect(page).to have_css('input[type="radio"]', count: 3)
  end

  it 'renders labels for each option' do
    render_inline(described_class.new(field_name: :choice, options: options))
    expect(page).to have_text('Option A')
    expect(page).to have_text('Option B')
    expect(page).to have_text('Option C')
  end

  it 'renders in inline layout when specified' do
    render_inline(described_class.new(field_name: :choice, options: options, layout: 'inline'))
    expect(page).to have_css('.flex.flex-wrap')
  end

  it 'marks selected option' do
    render_inline(described_class.new(field_name: :choice, options: options, value: 'b'))
    expect(page).to have_checked_field('Option B')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/radio_field_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::RadioFieldComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/radio_field_component.rb
# frozen_string_literal: true

module FormFields
  class RadioFieldComponent < BaseFieldComponent
    attr_reader :options, :layout

    def initialize(options: [], layout: 'vertical', **args)
      super(**args)
      @options = options || []
      @layout = layout
    end

    private

    def field_type
      :radio
    end

    def container_classes
      layout == 'inline' ? 'flex flex-wrap gap-4' : 'space-y-2'
    end
  end
end
```

```erb
<%# app/components/form_fields/radio_field_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <label class="<%= label_classes %>">
    <%= label %>
    <%= required_indicator %>
  </label>

  <div class="<%= container_classes %>">
    <% options.each do |option| %>
      <label class="flex items-center cursor-pointer group">
        <input type="radio"
               name="<%= field_name %>"
               value="<%= option['value'] %>"
               <%= 'checked' if value == option['value'] %>
               <%= 'required' if required && option == options.first %>
               class="w-4 h-4 text-indigo-600 border-gray-300 focus:ring-indigo-500">
        <span class="ml-2 text-sm text-gray-700 group-hover:text-gray-900"><%= option['label'] %></span>
      </label>
    <% end %>
  </div>

  <% if html_attributes[:help_text].present? %>
    <p class="mt-1 text-sm text-gray-500"><%= html_attributes[:help_text] %></p>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/radio_field_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/radio_field_component.rb app/components/form_fields/radio_field_component.html.erb spec/components/form_fields/radio_field_component_spec.rb
git commit -m "feat: add RadioFieldComponent for single-choice radio buttons"
```

---

### Task 7: Create ToggleFieldComponent

**Files:**
- Create: `app/components/form_fields/toggle_field_component.rb`
- Create: `app/components/form_fields/toggle_field_component.html.erb`
- Test: `spec/components/form_fields/toggle_field_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/toggle_field_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::ToggleFieldComponent, type: :component do
  it 'renders toggle switch' do
    render_inline(described_class.new(field_name: :active, label: 'Active'))
    expect(page).to have_css('input[type="checkbox"]')
    expect(page).to have_css('[data-toggle-switch]')
  end

  it 'renders label' do
    render_inline(described_class.new(field_name: :active, label: 'Enable Feature'))
    expect(page).to have_text('Enable Feature')
  end

  it 'renders checked state' do
    render_inline(described_class.new(field_name: :active, label: 'Active', value: true))
    expect(page).to have_checked_field(type: 'checkbox')
  end

  it 'renders description when provided' do
    render_inline(described_class.new(field_name: :active, label: 'Active', description: 'Toggle this to activate'))
    expect(page).to have_text('Toggle this to activate')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/toggle_field_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::ToggleFieldComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/toggle_field_component.rb
# frozen_string_literal: true

module FormFields
  class ToggleFieldComponent < BaseFieldComponent
    attr_reader :description

    def initialize(description: nil, **args)
      super(**args)
      @description = description
    end

    def checked?
      value == true || value == 'true' || value == '1' || value == 1
    end

    private

    def field_type
      :checkbox
    end
  end
end
```

```erb
<%# app/components/form_fields/toggle_field_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <div class="flex items-center justify-between">
    <div class="flex-1">
      <label for="<%= field_id %>" class="text-sm font-medium text-gray-700 cursor-pointer">
        <%= label %>
        <%= required_indicator %>
      </label>
      <% if description.present? %>
        <p class="text-sm text-gray-500"><%= description %></p>
      <% end %>
    </div>

    <label data-toggle-switch class="relative inline-flex items-center cursor-pointer">
      <input type="checkbox"
             name="<%= field_name %>"
             id="<%= field_id %>"
             <%= 'checked' if checked? %>
             <%= 'required' if required %>
             class="sr-only peer"
             <%= merge_html_attributes({}, html_attributes).map { |k, v| "#{k}=\"#{v}\"" }.join(' ').html_safe %>>
      <div class="w-11 h-6 bg-gray-200 rounded-full peer peer-focus:ring-2 peer-focus:ring-indigo-500 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-0.5 after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
    </label>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/toggle_field_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/toggle_field_component.rb app/components/form_fields/toggle_field_component.html.erb spec/components/form_fields/toggle_field_component_spec.rb
git commit -m "feat: add ToggleFieldComponent for yes/no toggle switches"
```

---

### Task 8: Create TimeFieldComponent

**Files:**
- Create: `app/components/form_fields/time_field_component.rb`
- Create: `app/components/form_fields/time_field_component.html.erb`
- Test: `spec/components/form_fields/time_field_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/time_field_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::TimeFieldComponent, type: :component do
  it 'renders time input' do
    render_inline(described_class.new(field_name: :start_time, label: 'Start Time'))
    expect(page).to have_css('input[type="time"]')
  end

  it 'renders with value' do
    render_inline(described_class.new(field_name: :start_time, label: 'Start Time', value: '14:30'))
    expect(page).to have_field('Start Time', with: '14:30')
  end

  it 'renders with min/max constraints' do
    render_inline(described_class.new(field_name: :start_time, label: 'Start Time', min: '09:00', max: '17:00'))
    expect(page).to have_css('input[min="09:00"]')
    expect(page).to have_css('input[max="17:00"]')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/time_field_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::TimeFieldComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/time_field_component.rb
# frozen_string_literal: true

module FormFields
  class TimeFieldComponent < BaseFieldComponent
    attr_reader :min, :max, :step

    def initialize(min: nil, max: nil, step: nil, **args)
      super(**args)
      @min = min
      @max = max
      @step = step
    end

    private

    def field_type
      :time
    end

    def input_attributes
      base = super
      base[:min] = min if min.present?
      base[:max] = max if max.present?
      base[:step] = step if step.present?
      base
    end
  end
end
```

```erb
<%# app/components/form_fields/time_field_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <label for="<%= field_id %>" class="<%= label_classes %>">
    <%= label %>
    <%= required_indicator %>
  </label>

  <div class="relative">
    <input type="time" <%= input_attributes.map { |k, v| "#{k}=\"#{v}\"" }.join(' ').html_safe %>>
    <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
      <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </div>
  </div>

  <% if html_attributes[:help_text].present? %>
    <p class="mt-1 text-sm text-gray-500"><%= html_attributes[:help_text] %></p>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/time_field_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/time_field_component.rb app/components/form_fields/time_field_component.html.erb spec/components/form_fields/time_field_component_spec.rb
git commit -m "feat: add TimeFieldComponent for time picker input"
```

---

### Task 9: Create FileUploadFieldComponent

**Files:**
- Create: `app/components/form_fields/file_upload_field_component.rb`
- Create: `app/components/form_fields/file_upload_field_component.html.erb`
- Test: `spec/components/form_fields/file_upload_field_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/file_upload_field_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::FileUploadFieldComponent, type: :component do
  it 'renders file input' do
    render_inline(described_class.new(field_name: :attachment, label: 'Upload File'))
    expect(page).to have_css('input[type="file"]')
  end

  it 'renders with accept attribute' do
    render_inline(described_class.new(field_name: :image, label: 'Image', accept: 'image/*'))
    expect(page).to have_css('input[accept="image/*"]')
  end

  it 'renders with multiple attribute' do
    render_inline(described_class.new(field_name: :files, label: 'Files', multiple: true))
    expect(page).to have_css('input[multiple]')
  end

  it 'renders drag-drop zone' do
    render_inline(described_class.new(field_name: :attachment, label: 'Upload'))
    expect(page).to have_css('[data-file-drop-zone]')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/file_upload_field_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::FileUploadFieldComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/file_upload_field_component.rb
# frozen_string_literal: true

module FormFields
  class FileUploadFieldComponent < BaseFieldComponent
    attr_reader :accept, :multiple, :max_size

    def initialize(accept: nil, multiple: false, max_size: nil, **args)
      super(**args)
      @accept = accept
      @multiple = multiple
      @max_size = max_size
    end

    def max_size_label
      return nil unless max_size
      if max_size >= 1_000_000
        "#{max_size / 1_000_000}MB"
      else
        "#{max_size / 1_000}KB"
      end
    end

    private

    def field_type
      :file
    end
  end
end
```

```erb
<%# app/components/form_fields/file_upload_field_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <label class="<%= label_classes %>">
    <%= label %>
    <%= required_indicator %>
  </label>

  <div data-file-drop-zone
       class="relative border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-indigo-400 hover:bg-indigo-50 transition-colors cursor-pointer">
    <input type="file"
           name="<%= field_name %>"
           id="<%= field_id %>"
           <%= "accept=\"#{accept}\"" if accept.present? %>
           <%= 'multiple' if multiple %>
           <%= 'required' if required %>
           class="absolute inset-0 w-full h-full opacity-0 cursor-pointer">

    <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
      <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
    </svg>

    <div class="mt-4">
      <span class="text-sm font-medium text-indigo-600">Click to upload</span>
      <span class="text-sm text-gray-500"> or drag and drop</span>
    </div>

    <p class="mt-1 text-xs text-gray-500">
      <% if accept.present? %>
        <%= accept.gsub('/*', ' files').gsub(',', ', ') %>
      <% else %>
        Any file type
      <% end %>
      <% if max_size_label %>
        up to <%= max_size_label %>
      <% end %>
    </p>
  </div>

  <% if html_attributes[:help_text].present? %>
    <p class="mt-1 text-sm text-gray-500"><%= html_attributes[:help_text] %></p>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/file_upload_field_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/file_upload_field_component.rb app/components/form_fields/file_upload_field_component.html.erb spec/components/form_fields/file_upload_field_component_spec.rb
git commit -m "feat: add FileUploadFieldComponent with drag-drop support"
```

---

### Task 10: Create RatingFieldComponent

**Files:**
- Create: `app/components/form_fields/rating_field_component.rb`
- Create: `app/components/form_fields/rating_field_component.html.erb`
- Test: `spec/components/form_fields/rating_field_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/rating_field_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::RatingFieldComponent, type: :component do
  it 'renders 5 stars by default' do
    render_inline(described_class.new(field_name: :rating, label: 'Rating'))
    expect(page).to have_css('[data-rating-star]', count: 5)
  end

  it 'renders custom max stars' do
    render_inline(described_class.new(field_name: :rating, label: 'Rating', max: 10))
    expect(page).to have_css('[data-rating-star]', count: 10)
  end

  it 'renders with selected value' do
    render_inline(described_class.new(field_name: :rating, label: 'Rating', value: 3))
    expect(page).to have_css('[data-rating-star][data-selected="true"]', count: 3)
  end

  it 'renders hidden input for form submission' do
    render_inline(described_class.new(field_name: :rating, label: 'Rating'))
    expect(page).to have_css('input[type="hidden"][name="rating"]')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/rating_field_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::RatingFieldComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/rating_field_component.rb
# frozen_string_literal: true

module FormFields
  class RatingFieldComponent < BaseFieldComponent
    attr_reader :max

    def initialize(max: 5, **args)
      super(**args)
      @max = max.to_i
    end

    def current_value
      value.to_i
    end

    private

    def field_type
      :hidden
    end
  end
end
```

```erb
<%# app/components/form_fields/rating_field_component.html.erb %>
<div class="<%= wrapper_classes %>" data-controller="rating">
  <label class="<%= label_classes %>">
    <%= label %>
    <%= required_indicator %>
  </label>

  <div class="flex items-center gap-1" data-rating-target="stars">
    <% (1..max).each do |star| %>
      <button type="button"
              data-rating-star
              data-value="<%= star %>"
              data-selected="<%= star <= current_value %>"
              data-action="click->rating#select mouseenter->rating#hover mouseleave->rating#unhover"
              class="p-1 transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 rounded">
        <svg class="w-6 h-6 <%= star <= current_value ? 'text-yellow-400 fill-current' : 'text-gray-300' %>"
             viewBox="0 0 24 24" stroke="currentColor" stroke-width="1">
          <path stroke-linecap="round" stroke-linejoin="round" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
        </svg>
      </button>
    <% end %>

    <span class="ml-2 text-sm text-gray-500" data-rating-target="label">
      <%= current_value > 0 ? "#{current_value} of #{max}" : 'Not rated' %>
    </span>
  </div>

  <input type="hidden"
         name="<%= field_name %>"
         value="<%= current_value %>"
         data-rating-target="input"
         <%= 'required' if required %>>

  <% if html_attributes[:help_text].present? %>
    <p class="mt-1 text-sm text-gray-500"><%= html_attributes[:help_text] %></p>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/rating_field_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/rating_field_component.rb app/components/form_fields/rating_field_component.html.erb spec/components/form_fields/rating_field_component_spec.rb
git commit -m "feat: add RatingFieldComponent for star ratings"
```

---

## Phase 4: Layout Element Components

### Task 11: Create HeadingElementComponent

**Files:**
- Create: `app/components/form_fields/heading_element_component.rb`
- Create: `app/components/form_fields/heading_element_component.html.erb`
- Test: `spec/components/form_fields/heading_element_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/heading_element_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::HeadingElementComponent, type: :component do
  it 'renders h2 by default' do
    render_inline(described_class.new(text: 'Section Title'))
    expect(page).to have_css('h2', text: 'Section Title')
  end

  it 'renders specified heading level' do
    render_inline(described_class.new(text: 'Main Title', level: 1))
    expect(page).to have_css('h1', text: 'Main Title')
  end

  it 'renders with custom alignment' do
    render_inline(described_class.new(text: 'Centered', alignment: 'center'))
    expect(page).to have_css('.text-center')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/heading_element_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::HeadingElementComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/heading_element_component.rb
# frozen_string_literal: true

module FormFields
  class HeadingElementComponent < ApplicationComponent
    LEVELS = {
      1 => 'text-3xl font-bold',
      2 => 'text-2xl font-bold',
      3 => 'text-xl font-semibold',
      4 => 'text-lg font-semibold',
      5 => 'text-base font-medium',
      6 => 'text-sm font-medium'
    }.freeze

    attr_reader :text, :level, :alignment

    def initialize(text:, level: 2, alignment: 'left')
      @text = text
      @level = level.to_i.clamp(1, 6)
      @alignment = alignment
    end

    def heading_tag
      "h#{level}"
    end

    def heading_classes
      base = LEVELS[level] || LEVELS[2]
      align = case alignment
              when 'center' then 'text-center'
              when 'right' then 'text-right'
              else 'text-left'
              end
      "#{base} #{align} text-gray-900"
    end
  end
end
```

```erb
<%# app/components/form_fields/heading_element_component.html.erb %>
<div class="mb-4">
  <%= content_tag heading_tag, text, class: heading_classes %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/heading_element_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/heading_element_component.rb app/components/form_fields/heading_element_component.html.erb spec/components/form_fields/heading_element_component_spec.rb
git commit -m "feat: add HeadingElementComponent for form section headings"
```

---

### Task 12: Create DividerElementComponent

**Files:**
- Create: `app/components/form_fields/divider_element_component.rb`
- Create: `app/components/form_fields/divider_element_component.html.erb`
- Test: `spec/components/form_fields/divider_element_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/divider_element_component_spec.rb
require 'rails_helper'

RSpec.describe FormFields::DividerElementComponent, type: :component do
  it 'renders horizontal rule' do
    render_inline(described_class.new)
    expect(page).to have_css('hr')
  end

  it 'renders with label when provided' do
    render_inline(described_class.new(label: 'Or continue with'))
    expect(page).to have_text('Or continue with')
  end

  it 'applies custom spacing' do
    render_inline(described_class.new(spacing: 'lg'))
    expect(page).to have_css('.my-8')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/divider_element_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::DividerElementComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/divider_element_component.rb
# frozen_string_literal: true

module FormFields
  class DividerElementComponent < ApplicationComponent
    SPACING = {
      'sm' => 'my-2',
      'md' => 'my-4',
      'lg' => 'my-8'
    }.freeze

    attr_reader :label, :spacing

    def initialize(label: nil, spacing: 'md')
      @label = label
      @spacing = spacing
    end

    def spacing_class
      SPACING[spacing] || SPACING['md']
    end
  end
end
```

```erb
<%# app/components/form_fields/divider_element_component.html.erb %>
<div class="<%= spacing_class %>">
  <% if label.present? %>
    <div class="relative">
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t border-gray-300"></div>
      </div>
      <div class="relative flex justify-center text-sm">
        <span class="px-2 bg-white text-gray-500"><%= label %></span>
      </div>
    </div>
  <% else %>
    <hr class="border-gray-300">
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/divider_element_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/divider_element_component.rb app/components/form_fields/divider_element_component.html.erb spec/components/form_fields/divider_element_component_spec.rb
git commit -m "feat: add DividerElementComponent for visual separation"
```

---

## Phase 5: Stimulus Controller Enhancements

### Task 13: Add Options Editor Methods to Controller

**Files:**
- Modify: `app/javascript/controllers/page_builder_controller.js`

**Step 1: Understand current state**

The controller already has basic structure. We need to add methods for:
- `addOption()` - Add new option to select/radio/checkbox fields
- `removeOption()` - Remove an option
- `updateOption()` - Update option label/value
- `reorderOptions()` - Drag to reorder options

**Step 2: Add options editor methods**

Add these methods to `page_builder_controller.js` after the condition management section (around line 1380):

```javascript
// ============================================
// OPTIONS EDITOR MANAGEMENT
// ============================================

/**
 * Add a new option to a select/radio/checkbox field
 */
addOption(event) {
  const fieldId = event.currentTarget.dataset.fieldId || this.selectedFieldId
  if (!fieldId) return

  const field = this.currentPageFields.find(f => f.id === fieldId)
  if (!field) return

  this.saveState()

  field.options = field.options || []
  const optionIndex = field.options.length + 1
  field.options.push({
    label: `Option ${optionIndex}`,
    value: `option_${optionIndex}`
  })

  this.renderOptionsEditor(field)
  this.markDirty()
}

/**
 * Remove an option from a field
 */
removeOption(event) {
  const fieldId = event.currentTarget.dataset.fieldId
  const optionIndex = parseInt(event.currentTarget.dataset.optionIndex, 10)

  const field = this.currentPageFields.find(f => f.id === fieldId)
  if (!field || !field.options) return

  this.saveState()

  field.options.splice(optionIndex, 1)

  this.renderOptionsEditor(field)
  this.markDirty()
}

/**
 * Update an option's label or value
 */
updateOption(event) {
  const fieldId = event.target.dataset.fieldId
  const optionIndex = parseInt(event.target.dataset.optionIndex, 10)
  const property = event.target.dataset.property
  const value = event.target.value

  const field = this.currentPageFields.find(f => f.id === fieldId)
  if (!field || !field.options || !field.options[optionIndex]) return

  field.options[optionIndex][property] = value
  this.markDirty()
}

/**
 * Render the options editor UI for a field
 */
renderOptionsEditor(field) {
  const container = this.element.querySelector('[data-options-editor]')
  if (!container) return

  const options = field.options || []

  const optionsHtml = options.map((option, index) => `
    <div class="flex items-center gap-2 group" data-option-index="${index}">
      <button type="button" class="cursor-grab text-gray-400 hover:text-gray-600">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 8h16M4 16h16" />
        </svg>
      </button>
      <input type="text"
             class="flex-1 px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
             placeholder="Label"
             value="${option.label || ''}"
             data-action="input->page-builder#updateOption"
             data-field-id="${field.id}"
             data-option-index="${index}"
             data-property="label">
      <input type="text"
             class="w-24 px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
             placeholder="Value"
             value="${option.value || ''}"
             data-action="input->page-builder#updateOption"
             data-field-id="${field.id}"
             data-option-index="${index}"
             data-property="value">
      <button type="button"
              class="p-1 text-gray-400 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
              data-action="click->page-builder#removeOption"
              data-field-id="${field.id}"
              data-option-index="${index}">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  `).join('')

  container.querySelector('[data-page-builder-target="optionsList"]').innerHTML = optionsHtml
}
```

**Step 3: Verify manually**

Test in browser by adding a select field, opening property panel, and using options editor.

**Step 4: Commit**

```bash
git add app/javascript/controllers/page_builder_controller.js
git commit -m "feat: add options editor methods to page builder controller"
```

---

### Task 14: Add Form Settings Methods to Controller

**Files:**
- Modify: `app/javascript/controllers/page_builder_controller.js`

**Step 1: Add form settings methods**

Add these methods after the options editor section:

```javascript
// ============================================
// FORM SETTINGS MANAGEMENT
// ============================================

/**
 * Update a form setting property
 */
updateFormSettings(event) {
  const property = event.target.dataset.property
  const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value

  if (!property) return

  this.saveState()

  this.configuration.form_settings = this.configuration.form_settings || {}
  this.configuration.form_settings[property] = value

  // Handle thank you mode toggle
  if (property === 'thank_you_mode') {
    const messageDiv = this.element.querySelector('[data-thank-you-message]')
    const redirectDiv = this.element.querySelector('[data-redirect-url]')

    if (messageDiv && redirectDiv) {
      messageDiv.classList.toggle('hidden', value === 'redirect')
      redirectDiv.classList.toggle('hidden', value === 'message')
    }
  }

  this.markDirty()
}

/**
 * Update wizard settings
 */
updateWizardSettings(event) {
  const property = event.target.dataset.property
  const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value

  if (!property) return

  this.saveState()

  this.configuration.wizard_settings = this.configuration.wizard_settings || {}
  this.configuration.wizard_settings[property] = value

  this.markDirty()
}

/**
 * Show form settings in property panel (when no field selected)
 */
showFormSettings() {
  // Hide field-specific sections
  this.element.querySelectorAll('[data-field-section]').forEach(el => {
    el.classList.add('hidden')
  })

  // Show form settings section
  const formSettingsSection = this.element.querySelector('[data-form-settings]')
  if (formSettingsSection) {
    formSettingsSection.classList.remove('hidden')
  }

  // Update panel header
  if (this.hasFieldTypeLabelTarget) {
    this.fieldTypeLabelTarget.textContent = 'Form Settings'
  }
  if (this.hasFieldSlugTarget) {
    this.fieldSlugTarget.textContent = 'Configure form behavior'
  }

  // Show panel
  if (this.hasFloatingPanelTarget) {
    this.floatingPanelTarget.style.display = 'flex'
    this.floatingPanelTarget.style.flexDirection = 'column'
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/page_builder_controller.js
git commit -m "feat: add form settings methods to page builder controller"
```

---

## Phase 6: Integration

### Task 15: Update Property Sidebar Template

**Files:**
- Modify: `app/views/pages/_editor.html.erb` (property sidebar section only)

**Step 1: Update sidebar to include new sections**

Find the property sidebar section (around line 421) and update it to include options editor and condition builder when appropriate:

```erb
<%# Inside the property panel content area, after the Layout Section %>

<%# Options Section (for select/radio/checkbox only) %>
<div class="border-b border-gray-100" data-field-section data-field-types="select,radio,checkbox" style="display: none;">
  <button type="button" data-action="click->page-builder#toggleSection" class="w-full px-4 py-3 flex items-center justify-between hover:bg-gray-50">
    <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Options</span>
    <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
    </svg>
  </button>
  <div class="px-4 pb-4" data-page-builder-target="sectionContent">
    <div data-options-editor data-page-builder-target="optionsEditor">
      <div class="space-y-2" data-page-builder-target="optionsList">
        <%# Options will be rendered dynamically %>
      </div>
      <button type="button"
              class="w-full mt-3 px-3 py-2 text-sm text-gray-600 border border-dashed border-gray-300 rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
              data-action="click->page-builder#addOption">
        <svg class="w-4 h-4 inline-block mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
        Add Option
      </button>
    </div>
  </div>
</div>

<%# Conditional Logic Section %>
<div class="border-b border-gray-100" data-field-section>
  <button type="button" data-action="click->page-builder#toggleSection" class="w-full px-4 py-3 flex items-center justify-between hover:bg-gray-50">
    <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Conditional Logic</span>
    <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
    </svg>
  </button>
  <div class="px-4 pb-4" data-page-builder-target="sectionContent">
    <div data-condition-builder data-page-builder-target="conditionsContainer">
      <%# Conditions will be rendered dynamically %>
      <div class="text-sm text-gray-500 text-center py-4">
        No conditions configured
      </div>
    </div>
    <button type="button"
            class="w-full mt-3 px-3 py-2 text-sm text-gray-600 border border-dashed border-gray-300 rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
            data-action="click->page-builder#addCondition">
      <svg class="w-4 h-4 inline-block mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
      </svg>
      Add Condition
    </button>
  </div>
</div>
```

**Step 2: Commit**

```bash
git add app/views/pages/_editor.html.erb
git commit -m "feat: add options editor and condition builder sections to property sidebar"
```

---

### Task 16: Create Rating Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/rating_controller.js`

**Step 1: Create the rating controller**

```javascript
// app/javascript/controllers/rating_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["stars", "input", "label"]

  connect() {
    this.updateDisplay()
  }

  select(event) {
    const value = parseInt(event.currentTarget.dataset.value, 10)
    this.inputTarget.value = value
    this.updateDisplay()

    // Dispatch change event
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }))
  }

  hover(event) {
    const value = parseInt(event.currentTarget.dataset.value, 10)
    this.highlightStars(value)
  }

  unhover() {
    const currentValue = parseInt(this.inputTarget.value, 10) || 0
    this.highlightStars(currentValue)
  }

  updateDisplay() {
    const value = parseInt(this.inputTarget.value, 10) || 0
    this.highlightStars(value)
    this.updateLabel(value)
  }

  highlightStars(upTo) {
    const stars = this.starsTarget.querySelectorAll('[data-rating-star]')
    const max = stars.length

    stars.forEach((star, index) => {
      const starValue = index + 1
      const isSelected = starValue <= upTo

      star.dataset.selected = isSelected
      const svg = star.querySelector('svg')

      if (isSelected) {
        svg.classList.remove('text-gray-300')
        svg.classList.add('text-yellow-400', 'fill-current')
      } else {
        svg.classList.remove('text-yellow-400', 'fill-current')
        svg.classList.add('text-gray-300')
      }
    })
  }

  updateLabel(value) {
    if (!this.hasLabelTarget) return

    const max = this.starsTarget.querySelectorAll('[data-rating-star]').length
    this.labelTarget.textContent = value > 0 ? `${value} of ${max}` : 'Not rated'
  }
}
```

**Step 2: Register controller**

The controller will be auto-registered by Rails if using importmap or esbuild with proper conventions.

**Step 3: Commit**

```bash
git add app/javascript/controllers/rating_controller.js
git commit -m "feat: add rating stimulus controller for star ratings"
```

---

## Summary

This implementation plan covers:

1. **Phase 1: Foundation** - Enhanced design tokens and component classes
2. **Phase 2: Property Sidebar Components** - OptionsEditor, ConditionBuilder, FormSettings
3. **Phase 3: New Form Field Components** - Radio, Toggle, Time, FileUpload, Rating
4. **Phase 4: Layout Elements** - Heading, Divider
5. **Phase 5: Stimulus Controller** - Options editor and form settings methods
6. **Phase 6: Integration** - Updated sidebar template and rating controller

Each task follows TDD with bite-sized steps:
- Write failing test
- Run test to verify failure
- Implement minimal code
- Run test to verify pass
- Commit

Total: **16 tasks** covering the core JotForm-style functionality.

---

**Plan complete and saved to `docs/plans/2026-02-14-jotform-page-builder-implementation.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**

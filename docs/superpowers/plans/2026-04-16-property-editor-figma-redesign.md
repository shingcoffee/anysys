# Property Editor Figma-Style Full Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the entire property editor popup to achieve Figma-style density, polish, and usability — covering sidebar, modals, item lists, I/O panel, and join panel — while extracting ViewComponents, consolidating templates, and separating canvas operations.

**Architecture:** Phase 1 creates the ViewComponent foundation and canvas bridge extraction. Phase 2 rewrites the sidebar shell and form fields. Phase 3 redesigns step items/modal. Phase 4 redesigns branch items/modal and join panel. Phase 5 redesigns the I/O panel. Each phase produces a working, testable state.

**Tech Stack:** Rails 8.1, ViewComponent, TailwindCSS, StimulusJS

**Spec:** `docs/superpowers/specs/2026-04-16-property-editor-figma-redesign.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `app/components/property_editor/empty_state_component.rb` | Dashed box empty state with icon + message |
| `app/components/property_editor/empty_state_component.html.erb` | Template for above |
| `app/components/property_editor/section_header_component.rb` | Section label with count badge and add action |
| `app/components/property_editor/section_header_component.html.erb` | Template for above |
| `app/components/property_editor/segmented_control_component.rb` | Toggle between options (tab bar, condition type) |
| `app/components/property_editor/segmented_control_component.html.erb` | Template for above |
| `app/components/property_editor/compact_item_component.rb` | Reusable row with leading/title/subtitle/trailing slots |
| `app/components/property_editor/compact_item_component.html.erb` | Template for above |
| `app/components/property_editor/inline_condition_component.rb` | `[left] [op] [right]` inline row |
| `app/components/property_editor/inline_condition_component.html.erb` | Template for above |
| `app/javascript/controllers/property_editor/canvas_bridge.js` | Canvas operations extracted from branch/join managers |
| `spec/components/property_editor/empty_state_component_spec.rb` | Tests for EmptyStateComponent |
| `spec/components/property_editor/section_header_component_spec.rb` | Tests for SectionHeaderComponent |
| `spec/components/property_editor/segmented_control_component_spec.rb` | Tests for SegmentedControlComponent |
| `spec/components/property_editor/compact_item_component_spec.rb` | Tests for CompactItemComponent |
| `spec/components/property_editor/inline_condition_component_spec.rb` | Tests for InlineConditionComponent |

### Modified Files

| File | Changes |
|------|---------|
| `app/views/flowcharts/_editor.html.erb` | Sidebar structure, header, tabs, footer, panes |
| `app/javascript/controllers/property_editor/templates.js` | Full rewrite — consolidate all templates, add base template functions |
| `app/javascript/controllers/property_editor/form_builder.js` | New field styling, compact inputs |
| `app/javascript/controllers/property_editor/tab_manager.js` | Slimmer tabs, inline badges |
| `app/javascript/controllers/property_editor/step_manager.js` | Remove inline HTML, use template functions |
| `app/javascript/controllers/property_editor/branch_manager.js` | Remove canvas ops and inline HTML |
| `app/javascript/controllers/property_editor/join_manager.js` | Remove graph traversal, use canvas_bridge |
| `app/javascript/controllers/property_editor/io_manager/input_operations.js` | Remove inline HTML, use template functions |
| `app/javascript/controllers/property_editor/io_manager/output_operations.js` | Remove inline HTML, use template functions |
| `app/javascript/controllers/property_editor_controller.js` | Wire canvas_bridge, slimmer |

---

### Task 1: EmptyStateComponent ViewComponent

**Files:**
- Create: `app/components/property_editor/empty_state_component.rb`
- Create: `app/components/property_editor/empty_state_component.html.erb`
- Create: `spec/components/property_editor/empty_state_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/property_editor/empty_state_component_spec.rb
require "rails_helper"

RSpec.describe PropertyEditor::EmptyStateComponent, type: :component do
  it "renders the message" do
    render_inline(described_class.new(message: "No items yet"))
    expect(page).to have_text("No items yet")
  end

  it "renders with dashed border styling" do
    render_inline(described_class.new(message: "No items yet"))
    expect(page).to have_css("div.border-dashed")
  end

  it "renders a custom icon when provided" do
    render_inline(described_class.new(message: "Empty", icon: "plus"))
    expect(page).to have_css("svg")
  end

  it "renders without icon by default" do
    render_inline(described_class.new(message: "Empty"))
    expect(page).not_to have_css("svg")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/property_editor/empty_state_component_spec.rb`
Expected: FAIL — class not found

- [ ] **Step 3: Create the component**

```ruby
# app/components/property_editor/empty_state_component.rb
class PropertyEditor::EmptyStateComponent < ApplicationComponent
  ICONS = {
    "plus" => '<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>',
    "search" => '<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" /></svg>'
  }.freeze

  def initialize(message:, icon: nil)
    @message = message
    @icon = icon
  end

  def icon_svg
    ICONS[@icon]
  end
end
```

```erb
<%# app/components/property_editor/empty_state_component.html.erb %>
<div class="border border-dashed border-slate-200 rounded-md py-3 text-center">
  <% if icon_svg %>
    <div class="flex justify-center mb-1 text-slate-300">
      <%= icon_svg.html_safe %>
    </div>
  <% end %>
  <p class="text-[11px] text-slate-400"><%= @message %></p>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/property_editor/empty_state_component_spec.rb`
Expected: 4 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/components/property_editor/empty_state_component.rb app/components/property_editor/empty_state_component.html.erb spec/components/property_editor/empty_state_component_spec.rb
git commit -m "feat: add PropertyEditor::EmptyStateComponent"
```

---

### Task 2: SectionHeaderComponent ViewComponent

**Files:**
- Create: `app/components/property_editor/section_header_component.rb`
- Create: `app/components/property_editor/section_header_component.html.erb`
- Create: `spec/components/property_editor/section_header_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/property_editor/section_header_component_spec.rb
require "rails_helper"

RSpec.describe PropertyEditor::SectionHeaderComponent, type: :component do
  it "renders the label" do
    render_inline(described_class.new(label: "Inputs"))
    expect(page).to have_text("Inputs")
  end

  it "renders the count badge when provided" do
    render_inline(described_class.new(label: "Steps", count: 3))
    expect(page).to have_text("3")
  end

  it "does not render count badge when count is nil" do
    render_inline(described_class.new(label: "Steps"))
    expect(page).not_to have_css("[data-section-count]")
  end

  it "renders add button when add_action is provided" do
    render_inline(described_class.new(label: "Inputs", add_action: "click->property-editor#addInput"))
    expect(page).to have_css("button")
  end

  it "does not render add button when add_action is nil" do
    render_inline(described_class.new(label: "Inputs"))
    expect(page).not_to have_css("button")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/property_editor/section_header_component_spec.rb`
Expected: FAIL — class not found

- [ ] **Step 3: Create the component**

```ruby
# app/components/property_editor/section_header_component.rb
class PropertyEditor::SectionHeaderComponent < ApplicationComponent
  def initialize(label:, count: nil, add_action: nil)
    @label = label
    @count = count
    @add_action = add_action
  end

  attr_reader :label, :count, :add_action
end
```

```erb
<%# app/components/property_editor/section_header_component.html.erb %>
<div class="flex items-center justify-between mb-1.5">
  <div class="flex items-center gap-1.5">
    <span class="text-xs font-semibold text-slate-700"><%= label %></span>
    <% if count %>
      <span data-section-count class="text-[10px] font-medium text-slate-400"><%= count %></span>
    <% end %>
  </div>
  <% if add_action %>
    <button type="button" data-action="<%= add_action %>" class="inline-flex items-center gap-0.5 text-[11px] text-indigo-600 hover:text-indigo-700">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
      Add
    </button>
  <% end %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/property_editor/section_header_component_spec.rb`
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/components/property_editor/section_header_component.rb app/components/property_editor/section_header_component.html.erb spec/components/property_editor/section_header_component_spec.rb
git commit -m "feat: add PropertyEditor::SectionHeaderComponent"
```

---

### Task 3: SegmentedControlComponent ViewComponent

**Files:**
- Create: `app/components/property_editor/segmented_control_component.rb`
- Create: `app/components/property_editor/segmented_control_component.html.erb`
- Create: `spec/components/property_editor/segmented_control_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/property_editor/segmented_control_component_spec.rb
require "rails_helper"

RSpec.describe PropertyEditor::SegmentedControlComponent, type: :component do
  let(:options) { [{ value: "a", label: "Option A" }, { value: "b", label: "Option B" }] }

  it "renders all options" do
    render_inline(described_class.new(options: options, active_value: "a"))
    expect(page).to have_text("Option A")
    expect(page).to have_text("Option B")
  end

  it "marks the active option with active classes" do
    render_inline(described_class.new(options: options, active_value: "a"))
    active_button = page.find("button[data-segment-value='a']")
    expect(active_button[:class]).to include("bg-white")
    expect(active_button[:class]).to include("shadow-sm")
  end

  it "marks inactive options without active classes" do
    render_inline(described_class.new(options: options, active_value: "a"))
    inactive_button = page.find("button[data-segment-value='b']")
    expect(inactive_button[:class]).to include("text-slate-500")
    expect(inactive_button[:class]).not_to include("shadow-sm")
  end

  it "supports xs size" do
    render_inline(described_class.new(options: options, active_value: "a", size: :xs))
    button = page.find("button[data-segment-value='a']")
    expect(button[:class]).to include("py-1")
    expect(button[:class]).to include("text-[11px]")
  end

  it "supports sm size (default)" do
    render_inline(described_class.new(options: options, active_value: "a"))
    button = page.find("button[data-segment-value='a']")
    expect(button[:class]).to include("py-1")
    expect(button[:class]).to include("text-[11px]")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/property_editor/segmented_control_component_spec.rb`
Expected: FAIL — class not found

- [ ] **Step 3: Create the component**

```ruby
# app/components/property_editor/segmented_control_component.rb
class PropertyEditor::SegmentedControlComponent < ApplicationComponent
  SIZES = {
    xs: { container: "p-0.5 gap-0.5", button: "py-0.5 px-2 text-[10px]" },
    sm: { container: "p-1 gap-1", button: "py-1 px-3 text-[11px]" }
  }.freeze

  ACTIVE_CLASSES = "bg-white text-slate-900 shadow-sm ring-1 ring-black/5".freeze
  INACTIVE_CLASSES = "text-slate-500 hover:text-slate-700 hover:bg-white/50".freeze

  def initialize(options:, active_value:, size: :sm)
    @options = options
    @active_value = active_value.to_s
    @size = size.to_sym
  end

  attr_reader :options, :active_value

  def size_classes
    SIZES[@size] || SIZES[:sm]
  end

  def button_classes(value)
    base = "flex-1 #{size_classes[:button]} font-medium rounded-md transition-all duration-150 whitespace-nowrap text-center"
    if value.to_s == active_value
      "#{base} #{ACTIVE_CLASSES}"
    else
      "#{base} #{INACTIVE_CLASSES}"
    end
  end
end
```

```erb
<%# app/components/property_editor/segmented_control_component.html.erb %>
<div class="flex <%= size_classes[:container] %> bg-slate-100 rounded-lg">
  <% options.each do |opt| %>
    <button type="button"
            data-segment-value="<%= opt[:value] %>"
            class="<%= button_classes(opt[:value]) %>">
      <%= opt[:label] %>
    </button>
  <% end %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/property_editor/segmented_control_component_spec.rb`
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/components/property_editor/segmented_control_component.rb app/components/property_editor/segmented_control_component.html.erb spec/components/property_editor/segmented_control_component_spec.rb
git commit -m "feat: add PropertyEditor::SegmentedControlComponent"
```

---

### Task 4: CompactItemComponent ViewComponent

**Files:**
- Create: `app/components/property_editor/compact_item_component.rb`
- Create: `app/components/property_editor/compact_item_component.html.erb`
- Create: `spec/components/property_editor/compact_item_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/property_editor/compact_item_component_spec.rb
require "rails_helper"

RSpec.describe PropertyEditor::CompactItemComponent, type: :component do
  it "renders with accent color" do
    render_inline(described_class.new(accent_color: "indigo")) do |c|
      c.with_title { "My Item" }
    end
    expect(page).to have_text("My Item")
    expect(page).to have_css(".border-l-2.border-indigo-400")
  end

  it "renders subtitle when provided" do
    render_inline(described_class.new(accent_color: "amber")) do |c|
      c.with_title { "Branch" }
      c.with_subtitle { "ctx[:status] == active" }
    end
    expect(page).to have_text("ctx[:status] == active")
  end

  it "renders trailing slot" do
    render_inline(described_class.new(accent_color: "red")) do |c|
      c.with_title { "Item" }
      c.with_trailing { "<button>X</button>".html_safe }
    end
    expect(page).to have_css("button", text: "X")
  end

  it "renders expandable content when provided" do
    render_inline(described_class.new(accent_color: "blue", expandable: true)) do |c|
      c.with_title { "Item" }
      c.with_content { "Expanded content here" }
    end
    expect(page).to have_text("Expanded content here")
  end

  it "renders leading slot for drag handle" do
    render_inline(described_class.new(accent_color: "green")) do |c|
      c.with_leading { "<div data-drag-handle>drag</div>".html_safe }
      c.with_title { "Item" }
    end
    expect(page).to have_css("[data-drag-handle]")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/property_editor/compact_item_component_spec.rb`
Expected: FAIL — class not found

- [ ] **Step 3: Create the component**

```ruby
# app/components/property_editor/compact_item_component.rb
class PropertyEditor::CompactItemComponent < ApplicationComponent
  renders_one :leading
  renders_one :title
  renders_one :subtitle
  renders_one :trailing
  renders_one :content

  def initialize(accent_color:, expandable: false)
    @accent_color = accent_color
    @expandable = expandable
  end

  def accent_border_class
    "border-#{@accent_color}-400"
  end

  def expandable?
    @expandable
  end
end
```

```erb
<%# app/components/property_editor/compact_item_component.html.erb %>
<div class="border-l-2 <%= accent_border_class %> px-2.5 py-1.5 hover:bg-slate-50 transition-colors group">
  <div class="flex items-center gap-1.5">
    <% if leading? %>
      <%= leading %>
    <% end %>
    <div class="w-2 h-2 rounded-full bg-<%= @accent_color %>-500 flex-shrink-0"></div>
    <div class="flex-1 min-w-0 flex items-center gap-1.5">
      <% if title? %>
        <span class="text-xs font-medium text-slate-800 truncate"><%= title %></span>
      <% end %>
      <% if subtitle? %>
        <span class="text-[11px] text-slate-400 truncate"><%= subtitle %></span>
      <% end %>
    </div>
    <% if trailing? %>
      <div class="flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
        <%= trailing %>
      </div>
    <% end %>
  </div>
  <% if expandable? && content? %>
    <div class="pl-6 mt-1.5" data-compact-item-content>
      <%= content %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/property_editor/compact_item_component_spec.rb`
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/components/property_editor/compact_item_component.rb app/components/property_editor/compact_item_component.html.erb spec/components/property_editor/compact_item_component_spec.rb
git commit -m "feat: add PropertyEditor::CompactItemComponent"
```

---

### Task 5: InlineConditionComponent ViewComponent

**Files:**
- Create: `app/components/property_editor/inline_condition_component.rb`
- Create: `app/components/property_editor/inline_condition_component.html.erb`
- Create: `spec/components/property_editor/inline_condition_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/property_editor/inline_condition_component_spec.rb
require "rails_helper"

RSpec.describe PropertyEditor::InlineConditionComponent, type: :component do
  it "renders left, operator, and right inputs" do
    render_inline(described_class.new(
      left_value: "ctx[:status]",
      operator: "==",
      right_value: "active",
      focus_color: "amber"
    ))
    expect(page).to have_css("input[data-condition-left]")
    expect(page).to have_css("select[data-condition-op]")
    expect(page).to have_css("input[data-condition-right]")
  end

  it "renders all three inline on one row" do
    render_inline(described_class.new(
      left_value: "",
      operator: "==",
      right_value: "",
      focus_color: "indigo"
    ))
    expect(page).to have_css("div.flex.items-center.gap-1\\.5")
  end

  it "sets the operator select to the correct value" do
    render_inline(described_class.new(
      left_value: "",
      operator: "!=",
      right_value: "",
      focus_color: "amber"
    ))
    expect(page).to have_css("option[value='!='][selected]")
  end

  it "uses the correct focus color" do
    render_inline(described_class.new(
      left_value: "",
      operator: "==",
      right_value: "",
      focus_color: "amber"
    ))
    left_input = page.find("input[data-condition-left]")
    expect(left_input[:class]).to include("focus:ring-amber-500/20")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/property_editor/inline_condition_component_spec.rb`
Expected: FAIL — class not found

- [ ] **Step 3: Create the component**

```ruby
# app/components/property_editor/inline_condition_component.rb
class PropertyEditor::InlineConditionComponent < ApplicationComponent
  OPERATORS = [
    { value: "==", label: "==" },
    { value: "!=", label: "!=" },
    { value: ">", label: ">" },
    { value: ">=", label: ">=" },
    { value: "<", label: "<" },
    { value: "<=", label: "<=" },
    { value: "is_empty", label: "empty" },
    { value: "is_not_empty", label: "!empty" },
    { value: "contains", label: "contains" }
  ].freeze

  def initialize(left_value: "", operator: "==", right_value: "", focus_color: "indigo")
    @left_value = left_value
    @operator = operator
    @right_value = right_value
    @focus_color = focus_color
  end

  attr_reader :left_value, :operator, :right_value, :focus_color

  def input_classes
    "flex-1 px-2 py-1.5 text-xs font-mono border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-#{focus_color}-500/20 focus:border-#{focus_color}-400"
  end

  def select_classes
    "w-16 px-1 py-1.5 text-xs border border-slate-200 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-#{focus_color}-500/20 focus:border-#{focus_color}-400"
  end
end
```

```erb
<%# app/components/property_editor/inline_condition_component.html.erb %>
<div class="flex items-center gap-1.5">
  <input type="text"
         data-condition-left
         value="<%= left_value %>"
         placeholder="ctx[:field]"
         class="<%= input_classes %>">
  <select data-condition-op class="<%= select_classes %>">
    <% PropertyEditor::InlineConditionComponent::OPERATORS.each do |op| %>
      <option value="<%= op[:value] %>" <%= "selected" if op[:value] == operator %>><%= op[:label] %></option>
    <% end %>
  </select>
  <input type="text"
         data-condition-right
         value="<%= right_value %>"
         placeholder="value"
         class="<%= input_classes %>">
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/property_editor/inline_condition_component_spec.rb`
Expected: 4 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/components/property_editor/inline_condition_component.rb app/components/property_editor/inline_condition_component.html.erb spec/components/property_editor/inline_condition_component_spec.rb
git commit -m "feat: add PropertyEditor::InlineConditionComponent"
```

---

### Task 6: Add Base Template Functions to templates.js

These JS functions mirror the ViewComponent output for client-side dynamic creation.

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js`

- [ ] **Step 1: Add base template functions at the top of templates.js**

Add these functions after the existing imports and before the `STEP_COLOR_CLASSES` constant in `app/javascript/controllers/property_editor/templates.js`:

```javascript
// ===================
// Base Template Functions (mirror ViewComponent output)
// ===================

/**
 * Build empty state HTML matching PropertyEditor::EmptyStateComponent.
 * @param {string} message - The message to display
 * @param {string|null} iconSvg - Optional SVG string for an icon
 * @returns {string} HTML string
 */
export function buildEmptyState(message, iconSvg = null) {
  const iconHTML = iconSvg
    ? `<div class="flex justify-center mb-1 text-slate-300">${iconSvg}</div>`
    : ""
  return `
    <div class="border border-dashed border-slate-200 rounded-md py-3 text-center">
      ${iconHTML}
      <p class="text-[11px] text-slate-400">${escapeHtml(message)}</p>
    </div>
  `
}

/**
 * Build section header HTML matching PropertyEditor::SectionHeaderComponent.
 * @param {Object} params
 * @param {string} params.label - Section label text
 * @param {number|null} params.count - Optional count badge
 * @param {string|null} params.addAction - Optional Stimulus action for add button
 * @returns {string} HTML string
 */
export function buildSectionHeader({ label, count = null, addAction = null }) {
  const countHTML = count !== null
    ? `<span data-section-count class="text-[10px] font-medium text-slate-400">${count}</span>`
    : ""
  const addHTML = addAction
    ? `<button type="button" data-action="${addAction}" class="inline-flex items-center gap-0.5 text-[11px] text-indigo-600 hover:text-indigo-700">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
        Add
      </button>`
    : ""
  return `
    <div class="flex items-center justify-between mb-1.5">
      <div class="flex items-center gap-1.5">
        <span class="text-xs font-semibold text-slate-700">${escapeHtml(label)}</span>
        ${countHTML}
      </div>
      ${addHTML}
    </div>
  `
}

/**
 * Build segmented control HTML matching PropertyEditor::SegmentedControlComponent.
 * @param {Object} params
 * @param {Array<{value: string, label: string}>} params.options
 * @param {string} params.activeValue
 * @param {string|null} params.action - Optional Stimulus action for buttons
 * @returns {string} HTML string
 */
export function buildSegmentedControl({ options, activeValue, action = null }) {
  const buttonsHTML = options.map(opt => {
    const isActive = opt.value === activeValue
    const stateClasses = isActive
      ? "bg-white text-slate-900 shadow-sm ring-1 ring-black/5"
      : "text-slate-500 hover:text-slate-700 hover:bg-white/50"
    const actionAttr = action ? `data-action="${action}"` : ""
    return `<button type="button" data-segment-value="${escapeHtml(opt.value)}" ${actionAttr}
                    class="flex-1 py-1 px-3 text-[11px] font-medium rounded-md transition-all duration-150 whitespace-nowrap text-center ${stateClasses}">
              ${escapeHtml(opt.label)}
            </button>`
  }).join("")

  return `<div class="flex gap-1 p-1 bg-slate-100 rounded-lg">${buttonsHTML}</div>`
}

/**
 * Build inline condition row HTML matching PropertyEditor::InlineConditionComponent.
 * @param {Object} params
 * @param {string} params.leftValue
 * @param {string} params.operator
 * @param {string} params.rightValue
 * @param {string} params.focusColor - "amber" or "indigo"
 * @returns {string} HTML string
 */
export function buildInlineCondition({ leftValue = "", operator = "==", rightValue = "", focusColor = "indigo" }) {
  const inputClass = `flex-1 px-2 py-1.5 text-xs font-mono border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-${focusColor}-500/20 focus:border-${focusColor}-400`
  const selectClass = `w-16 px-1 py-1.5 text-xs border border-slate-200 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-${focusColor}-500/20 focus:border-${focusColor}-400`

  const operators = [
    { value: "==", label: "==" },
    { value: "!=", label: "!=" },
    { value: ">", label: ">" },
    { value: ">=", label: ">=" },
    { value: "<", label: "<" },
    { value: "<=", label: "<=" },
    { value: "is_empty", label: "empty" },
    { value: "is_not_empty", label: "!empty" },
    { value: "contains", label: "contains" }
  ]

  const optionsHTML = operators.map(op =>
    `<option value="${op.value}"${op.value === operator ? " selected" : ""}>${op.label}</option>`
  ).join("")

  return `
    <div class="flex items-center gap-1.5">
      <input type="text" data-condition-left value="${escapeHtml(leftValue)}" placeholder="ctx[:field]" class="${inputClass}">
      <select data-condition-op class="${selectClass}">${optionsHTML}</select>
      <input type="text" data-condition-right value="${escapeHtml(rightValue)}" placeholder="value" class="${inputClass}">
    </div>
  `
}

/**
 * Build compact item row HTML matching PropertyEditor::CompactItemComponent.
 * @param {Object} params
 * @param {string} params.accentColor - e.g. "indigo", "amber"
 * @param {string} params.title
 * @param {string|null} params.subtitle
 * @param {string|null} params.leadingHTML - Raw HTML for leading slot (e.g., drag handle)
 * @param {string|null} params.trailingHTML - Raw HTML for trailing slot (e.g., remove button)
 * @param {string|null} params.contentHTML - Raw HTML for expandable content
 * @param {string} params.extraClasses - Additional classes for the wrapper
 * @param {string} params.extraAttrs - Additional data attributes for the wrapper
 * @returns {string} HTML string
 */
export function buildCompactItem({ accentColor, title, subtitle = null, leadingHTML = null, trailingHTML = null, contentHTML = null, extraClasses = "", extraAttrs = "" }) {
  const subtitleHTML = subtitle ? `<span class="text-[11px] text-slate-400 truncate">${subtitle}</span>` : ""
  const leadingSlot = leadingHTML || ""
  const trailingSlot = trailingHTML ? `<div class="flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">${trailingHTML}</div>` : ""
  const contentSlot = contentHTML ? `<div class="pl-6 mt-1.5" data-compact-item-content>${contentHTML}</div>` : ""

  return `
    <div class="border-l-2 border-${accentColor}-400 px-2.5 py-1.5 hover:bg-slate-50 transition-colors group ${extraClasses}" ${extraAttrs}>
      <div class="flex items-center gap-1.5">
        ${leadingSlot}
        <div class="w-2 h-2 rounded-full bg-${accentColor}-500 flex-shrink-0"></div>
        <div class="flex-1 min-w-0 flex items-center gap-1.5">
          <span class="text-xs font-medium text-slate-800 truncate">${escapeHtml(title)}</span>
          ${subtitleHTML}
        </div>
        ${trailingSlot}
      </div>
      ${contentSlot}
    </div>
  `
}
```

- [ ] **Step 2: Verify templates.js still loads without errors**

Run: `bin/rails assets:precompile 2>&1 | tail -5` (or open the app in browser and check console for JS errors)
Expected: No JS errors

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: add base template functions mirroring ViewComponents in templates.js"
```

---

### Task 7: Extract Canvas Bridge from Branch Manager

**Files:**
- Create: `app/javascript/controllers/property_editor/canvas_bridge.js`
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
- Modify: `app/javascript/controllers/property_editor/join_manager.js`

- [ ] **Step 1: Create canvas_bridge.js with methods extracted from branch_manager.js**

Create `app/javascript/controllers/property_editor/canvas_bridge.js`:

```javascript
/**
 * Canvas Bridge Module
 * Extracts canvas manipulation operations from branch_manager and join_manager.
 * Provides a clean interface between form managers and canvas DOM operations.
 */

export class CanvasBridge {
  constructor(controller) {
    this.controller = controller
  }

  get canvas() {
    return this.controller.canvas
  }

  // ===================
  // Branch Element Operations
  // ===================

  /**
   * Add a branch element to the canvas and create a connection from the decision.
   * Extracted from BranchManager._addBranchElementToCanvas
   * @param {Object} elementData - The element data object { id, type, label, ... }
   * @param {Object} decisionElement - The parent decision element
   * @param {number} branchIndex - The branch index for port mapping
   * @param {string} connectionLabel - Label for the connection line
   */
  addBranchElement(elementData, decisionElement, branchIndex, connectionLabel) {
    if (!this.canvas) return

    this.canvas.elements.push(elementData)
    this.canvas.renderElement(elementData)

    // Create connection from decision to branch element
    const fromEl = this.canvas.elements.find(el => el.id === decisionElement.id)
    if (fromEl) {
      this.canvas.createConnection(fromEl, elementData, "bottom", "top", {
        fromPort: `port_${branchIndex}`,
        label: connectionLabel
      })
    }
  }

  /**
   * Remove a branch element and its connections from the canvas.
   * Extracted from BranchManager._removeBranchElementFromCanvas
   * @param {string} elementId - The element ID to remove
   */
  removeBranchElement(elementId) {
    if (!this.canvas || !elementId) return

    // Remove connections to/from this element
    this.canvas.connections = this.canvas.connections.filter(
      c => c.from !== elementId && c.to !== elementId
    )

    // Remove element from canvas
    const elementIndex = this.canvas.elements.findIndex(el => el.id === elementId)
    if (elementIndex !== -1) {
      // Remove from DOM
      const elementLayer = this.canvas.elementLayer
      const domElement = elementLayer?.querySelector(`[data-element-id="${elementId}"]`)
      if (domElement) domElement.remove()

      this.canvas.elements.splice(elementIndex, 1)
    }

    this.canvas.updateConnections()
  }

  /**
   * Remap branch connection port indices after a branch is removed.
   * Extracted from BranchManager._remapBranchConnections
   * @param {Object} decisionElement - The decision element
   */
  remapBranchConnections(decisionElement) {
    if (!this.canvas || !decisionElement) return

    const branchConnections = this.canvas.connections
      .filter(c => c.from === decisionElement.id && c.fromPort)
      .sort((a, b) => {
        const aIndex = parseInt(a.fromPort.replace("port_", ""), 10)
        const bIndex = parseInt(b.fromPort.replace("port_", ""), 10)
        return aIndex - bIndex
      })

    branchConnections.forEach((conn, idx) => {
      conn.fromPort = `port_${idx}`
    })

    this.canvas.updateConnections()
  }

  /**
   * Reposition all branch elements connected to a decision.
   * Extracted from BranchManager._repositionAllBranchElements
   * @param {Object} decisionElement - The decision element
   */
  repositionBranches(decisionElement) {
    if (!this.canvas || !decisionElement) return

    const branchConnections = this.canvas.connections
      .filter(c => c.from === decisionElement.id && c.fromPort)
      .sort((a, b) => {
        const aIndex = parseInt(a.fromPort.replace("port_", ""), 10)
        const bIndex = parseInt(b.fromPort.replace("port_", ""), 10)
        return aIndex - bIndex
      })

    const total = branchConnections.length
    branchConnections.forEach((conn, idx) => {
      const branchEl = this.canvas.elements.find(el => el.id === conn.to)
      if (branchEl) {
        const pos = this.calculateBranchPosition(decisionElement, idx, total)
        branchEl.x = pos.x
        branchEl.y = pos.y

        // Update DOM position
        const domEl = this.canvas.elementLayer?.querySelector(`[data-element-id="${branchEl.id}"]`)
        if (domEl) {
          domEl.style.left = `${pos.x}px`
          domEl.style.top = `${pos.y}px`
        }
      }
    })

    this.canvas.updateConnections()
  }

  /**
   * Calculate canvas position for a branch element.
   * Extracted from BranchManager._calculateBranchCanvasPosition
   * @param {Object} decisionElement
   * @param {number} branchIndex
   * @param {number} totalBranches
   * @returns {{x: number, y: number}}
   */
  calculateBranchPosition(decisionElement, branchIndex, totalBranches = 1) {
    const spacing = 220
    const totalWidth = (totalBranches - 1) * spacing
    const startX = decisionElement.x - totalWidth / 2
    return {
      x: startX + branchIndex * spacing,
      y: decisionElement.y + 150
    }
  }

  /**
   * Re-render a decision element on the canvas.
   * Extracted from BranchManager._refreshDecisionElement
   * @param {Object} element
   */
  refreshDecisionElement(element) {
    if (!this.canvas) return
    const domEl = this.canvas.elementLayer?.querySelector(`[data-element-id="${element.id}"]`)
    if (domEl) {
      this.canvas.renderElement(element, domEl)
    }
  }

  /**
   * Notify canvas of before/after changes.
   */
  beforeChange() {
    this.canvas?.onBeforeChange?.()
  }

  afterChange() {
    this.canvas?._hideConnectionHandles?.()
    this.canvas?.updateConnections()
    this.canvas?.onchange?.()
  }

  // ===================
  // Join / Graph Traversal Operations
  // ===================

  /**
   * Find the source Decision element for a Join element.
   * Extracted from JoinManager._findSourceDecision
   * @param {Object} joinElement
   * @returns {Object|null} The source decision element
   */
  findSourceDecision(joinElement) {
    if (!this.canvas) return null

    // Trace back from join through incoming connections
    const incomingConnections = this.canvas.connections.filter(c => c.to === joinElement.id)
    for (const conn of incomingConnections) {
      const result = this._traceBackToDecision(conn.from, new Set())
      if (result) return result
    }
    return null
  }

  /**
   * Trace back through the graph to find a Decision element.
   * Extracted from JoinManager._traceBackToDecision
   * @private
   */
  _traceBackToDecision(elementId, visited) {
    if (visited.has(elementId)) return null
    visited.add(elementId)

    const element = this.canvas.elements.find(el => el.id === elementId)
    if (!element) return null
    if (element.type === "decision") return element

    // Continue tracing back
    const incomingConnections = this.canvas.connections.filter(c => c.to === elementId)
    for (const conn of incomingConnections) {
      const result = this._traceBackToDecision(conn.from, visited)
      if (result) return result
    }
    return null
  }

  /**
   * Get branches from a decision element.
   * Extracted from JoinManager._getDecisionBranches
   * @param {Object} decisionElement
   * @returns {Array} Array of branch connection objects
   */
  getDecisionBranches(decisionElement) {
    if (!this.canvas || !decisionElement) return []

    return this.canvas.connections
      .filter(c => c.from === decisionElement.id && c.fromPort)
      .sort((a, b) => {
        const aIndex = parseInt(a.fromPort.replace("port_", ""), 10)
        const bIndex = parseInt(b.fromPort.replace("port_", ""), 10)
        return aIndex - bIndex
      })
  }

  /**
   * Check if an element is reachable from a start element via connections.
   * Extracted from JoinManager._isReachable
   * @param {string} startId
   * @param {string} targetId
   * @param {string|null} excludeId - Element to skip during traversal
   * @returns {boolean}
   */
  isReachable(startId, targetId, excludeId = null) {
    if (!this.canvas) return false

    const visited = new Set()
    const queue = [startId]

    while (queue.length > 0) {
      const currentId = queue.shift()
      if (currentId === targetId) return true
      if (visited.has(currentId)) continue
      if (currentId === excludeId) continue
      visited.add(currentId)

      const outgoing = this.canvas.connections.filter(c => c.from === currentId)
      for (const conn of outgoing) {
        queue.push(conn.to)
      }
    }
    return false
  }

  /**
   * Find the last element in a branch chain before the join.
   * Extracted from JoinManager._findLastElementInChain
   * @param {string} startId
   * @param {string} joinId
   * @param {string|null} excludeId
   * @returns {string|null} The ID of the last element before the join
   */
  findLastElementInChain(startId, joinId, excludeId = null) {
    if (!this.canvas) return null

    let currentId = startId
    const visited = new Set()

    while (currentId) {
      if (visited.has(currentId)) return currentId
      visited.add(currentId)

      const outgoing = this.canvas.connections.filter(c => c.from === currentId)

      // If one of the outgoing connects directly to the join, return current
      if (outgoing.some(c => c.to === joinId)) return currentId

      // Follow the chain (skip excluded element)
      const next = outgoing.find(c => c.to !== excludeId && c.to !== joinId)
      if (!next) return currentId
      currentId = next.to
    }
    return null
  }

  /**
   * Sort branch keys by their element's x-position on canvas.
   * Extracted from JoinManager._sortBranchesByElementPosition
   * @param {Array<string>} branchKeys - Array of branch element IDs
   * @param {Object} sourceDecision - The decision element
   * @returns {Array<string>} Sorted branch keys
   */
  sortBranchesByElementPosition(branchKeys, sourceDecision) {
    if (!this.canvas) return branchKeys

    return [...branchKeys].sort((a, b) => {
      const elA = this.canvas.elements.find(el => el.id === a)
      const elB = this.canvas.elements.find(el => el.id === b)
      const xA = elA ? elA.x : 0
      const xB = elB ? elB.x : 0
      return xA - xB
    })
  }

  /**
   * Create a connection between two elements on the canvas.
   * @param {Object} fromElement
   * @param {Object} toElement
   * @param {string} fromSide
   * @param {string} toSide
   * @param {Object} options
   */
  createConnection(fromElement, toElement, fromSide = "bottom", toSide = "top", options = {}) {
    if (!this.canvas) return
    this.canvas.createConnection(fromElement, toElement, fromSide, toSide, options)
  }

  /**
   * Remove connections to a specific element.
   * @param {string} toElementId
   */
  removeConnectionsTo(toElementId) {
    if (!this.canvas) return
    this.canvas.connections = this.canvas.connections.filter(c => c.to !== toElementId)
  }

  /**
   * Update all connections on the canvas.
   */
  updateConnections() {
    this.canvas?.updateConnections()
  }

  /**
   * Find an element by ID on the canvas.
   * @param {string} elementId
   * @returns {Object|null}
   */
  findElement(elementId) {
    return this.canvas?.elements?.find(el => el.id === elementId) || null
  }
}

export default CanvasBridge
```

- [ ] **Step 2: Wire canvas_bridge into the main controller**

In `app/javascript/controllers/property_editor_controller.js`, add the import and initialization. Find the existing imports at the top of the file and add:

```javascript
import { CanvasBridge } from "controllers/property_editor/canvas_bridge"
```

In the `connect()` method, after the existing manager initializations, add:

```javascript
this.canvasBridge = new CanvasBridge(this)
```

Also pass it to the branch and join managers. After the line that creates branchManager, add:

```javascript
this.branchManager.canvasBridge = this.canvasBridge
```

After the line that creates joinManager, add:

```javascript
this.joinManager.canvasBridge = this.canvasBridge
```

- [ ] **Step 3: Update the index.js barrel export**

In `app/javascript/controllers/property_editor/index.js`, add:

```javascript
export { CanvasBridge } from "./canvas_bridge"
```

- [ ] **Step 4: Verify the app still loads**

Open the flowchart editor in a browser. Double-click an element. Verify the property editor still opens and the step/branch/join panels still work. The canvas_bridge is created but not yet used — existing code paths are unchanged.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/canvas_bridge.js app/javascript/controllers/property_editor/index.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat: extract CanvasBridge from branch/join managers"
```

---

### Task 8: Redesign Sidebar Shell (ERB + Header + Tabs + Footer)

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:446-554`
- Modify: `app/javascript/controllers/property_editor/tab_manager.js`

- [ ] **Step 1: Update the sidebar container and header in _editor.html.erb**

Replace lines 446-500 in `app/views/flowcharts/_editor.html.erb` (the sidebar container through the end of the header) with:

```erb
    <!-- Right Sidebar - Property Editor (hidden by default, overlays canvas) -->
    <div class="absolute right-0 top-0 bottom-0 z-30 bg-white border-l border-slate-200 shadow-lg transform transition-transform duration-300 ease-in-out hidden"
         style="width: 420px;"
         data-controller="property-editor panel-resize"
         data-panel-resize-min-width-value="360"
         data-panel-resize-max-width-value="520"
         data-panel-resize-default-width-value="420"
         data-property-editor-target="sidebar"
         data-flowchart-canvas-target="propertySidebar">

      <!-- Drag handle for resizing (left edge) -->
      <div class="absolute left-0 top-0 bottom-0 w-1.5 cursor-col-resize group z-50 flex items-center justify-center"
           data-action="mousedown->panel-resize#startResize">
        <div class="w-0.5 h-8 rounded-full bg-slate-300 group-hover:bg-indigo-400 group-hover:h-12 transition-all duration-200"></div>
      </div>

      <!-- Modal Content Container -->
      <div class="relative h-full flex flex-col" data-property-editor-target="modalContent">

        <!-- Property Editor Header -->
        <div class="flex-shrink-0" data-property-editor-target="headerWrapper">
          <div class="px-3 pt-2.5 pb-1.5 flex items-center justify-between">
            <div class="flex items-center gap-2 min-w-0">
              <!-- Type icon -->
              <div data-property-editor-target="typeIndicator"
                   class="w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0 ring-1 ring-black/5"
                   style="background-color: #f0fdf4;">
                <svg data-property-editor-target="typeIcon" class="w-3.5 h-3.5" style="color: #10b981;" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M5 3l14 9-14 9V3z" />
                </svg>
              </div>
              <div class="min-w-0 flex items-baseline gap-1.5">
                <h3 class="text-sm font-semibold text-slate-900 truncate leading-tight" data-property-editor-target="title">
                  Element Properties
                </h3>
                <span class="text-[10px] text-slate-400 font-medium flex-shrink-0" data-property-editor-target="typeLabel">Process</span>
              </div>
            </div>
            <button type="button"
                    data-action="click->property-editor#close"
                    class="p-1 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-md transition-colors">
              <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Tab Bar -->
          <div class="px-3 pb-1.5" data-property-editor-target="tabBar">
            <div class="flex gap-1 p-1 bg-slate-100 rounded-lg">
              <!-- Tabs rendered dynamically by TabManager -->
            </div>
          </div>

          <!-- Subtle divider -->
          <div class="h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>
        </div>
```

- [ ] **Step 2: Update the tab panes and footer**

Replace lines 504-544 (form and footer) with:

```erb
        <!-- Property Editor Form -->
        <form data-property-editor-target="form"
              data-action="submit->property-editor#save"
              class="flex-1 flex flex-col min-h-0">

          <!-- Tab Pane: General -->
          <div class="flex-1 overflow-y-auto px-3 py-2" data-property-editor-target="tabPaneGeneral">
            <div data-property-editor-target="formFieldsGeneral" class="space-y-2"></div>
          </div>

          <!-- Tab Pane: Steps/Branches -->
          <div class="flex-1 overflow-y-auto px-3 py-2 hidden" data-property-editor-target="tabPaneSteps">
            <div data-property-editor-target="formFieldsSteps" class="space-y-2"></div>
          </div>

          <!-- Tab Pane: I/O -->
          <div class="flex-1 overflow-y-auto px-3 py-2 hidden" data-property-editor-target="tabPaneIo">
            <div data-property-editor-target="formFieldsIo" class="space-y-2"></div>
          </div>

          <!-- Tab Pane: Advanced -->
          <div class="flex-1 overflow-y-auto px-3 py-2 hidden" data-property-editor-target="tabPaneAdvanced">
            <div data-property-editor-target="formFieldsAdvanced" class="grid grid-cols-2 gap-2"></div>
          </div>

          <!-- Pinned Footer -->
          <div class="flex items-center justify-end gap-2 px-3 py-2 border-t border-slate-100 bg-slate-50/50 flex-shrink-0">
            <button type="button"
                    data-action="click->property-editor#close"
                    data-property-editor-target="cancelButton"
                    class="px-3 py-1.5 text-xs font-medium rounded-md text-slate-600 bg-white border border-slate-200 hover:bg-slate-50 hover:border-slate-300 transition-colors">
              Cancel
            </button>
            <button type="submit"
                    data-property-editor-target="saveButton"
                    class="px-3 py-1.5 text-xs font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 transition-colors">
              Save
            </button>
          </div>
        </form>
```

- [ ] **Step 3: Update TabManager for slimmer tabs with inline badges**

In `app/javascript/controllers/property_editor/tab_manager.js`, update the `_createTabButton` method (lines 176-208):

```javascript
  _createTabButton(tabKey, label) {
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.tab = tabKey
    button.classList.add(
      "flex-1", "py-1", "px-2", "text-[11px]", "font-medium",
      "rounded-md", "transition-all", "duration-150", "whitespace-nowrap",
      "text-center"
    )

    // Set initial state (general is active by default)
    if (tabKey === "general") {
      button.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
    } else {
      button.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
    }

    // Add click handler
    button.addEventListener("click", () => this.switchTo(tabKey))

    // Set text content — badge will be appended inline
    button.textContent = label
    button.dataset.tabLabel = label

    return button
  }
```

Update the `updateBadges` method (lines 107-141) to use inline text:

```javascript
  updateBadges(counts) {
    const buttons = this.tabBarContainer?.querySelectorAll("button[data-tab]") || []

    buttons.forEach(button => {
      const tabKey = button.dataset.tab
      const baseLabel = button.dataset.tabLabel || button.textContent.trim()

      let badgeText = ""
      if (tabKey === "steps") {
        const count = counts.steps || counts.branches || 0
        if (count > 0) badgeText = ` (${count})`
      } else if (tabKey === "io") {
        const inputCount = counts.inputs || 0
        const outputCount = counts.outputs || 0
        if (inputCount > 0 || outputCount > 0) badgeText = ` (${inputCount}/${outputCount})`
      }

      button.textContent = baseLabel + badgeText
    })
  }
```

Update `_updateTabButtons` (lines 215-234) to match the new class set:

```javascript
  _updateTabButtons() {
    const buttons = this.tabBarContainer?.querySelectorAll("button[data-tab]") || []

    buttons.forEach(button => {
      const tabKey = button.dataset.tab
      const isActive = tabKey === this.activeTab

      button.classList.remove(
        "bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5",
        "text-slate-500", "hover:text-slate-700", "hover:bg-white/50"
      )

      if (isActive) {
        button.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
      } else {
        button.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
      }
    })
  }
```

- [ ] **Step 4: Verify in browser**

Open the flowchart editor. Double-click an element. Verify:
1. Sidebar has lighter shadow
2. Header is compact with title + type inline
3. Tab bar is slimmer
4. Footer buttons are smaller, no icon on Save
5. All tabs switch correctly
6. Save and Cancel still work

- [ ] **Step 5: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb app/javascript/controllers/property_editor/tab_manager.js
git commit -m "feat: redesign sidebar shell with Figma-style compact layout"
```

---

### Task 9: Redesign Form Fields (form_builder.js)

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js:240-368`

- [ ] **Step 1: Update label and input styling in form_builder.js**

In `app/javascript/controllers/property_editor/form_builder.js`, update the `_buildFieldHTML` method. Change line 240:

```javascript
    const labelClass = "font-medium text-slate-500"
```

to:

```javascript
    const labelClass = "font-medium text-slate-500"
```

Then update the label HTML at lines 273-278 to remove uppercase and use tighter spacing:

```javascript
    let fieldHTML = `
      <div class="${hiddenClass}${colSpanClass}"${visibilityAttrs}>
        <label for="prop_${fieldName}" class="block text-[11px] ${labelClass} mb-1">
          ${fieldSchema.label}${fieldSchema.required ? ' <span class="text-red-400">&#x2022;</span>' : ""}
        </label>
    `
```

Update the `_buildInputHTML` method at line 302 — change the input class:

```javascript
    const inputClass = "w-full px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
```

- [ ] **Step 2: Update error handling template in templates.js**

In `app/javascript/controllers/property_editor/templates.js`, update the `buildErrorHandlingFieldTemplate` function (lines 840-873) to remove the red box:

```javascript
export function buildErrorHandlingFieldTemplate(fieldName, currentValue) {
  const config = currentValue || {}
  const mode = config.mode || "route_to_error_end"
  const errorOutputField = config.errorOutputField || "ctx.error"
  const showErrorField = mode === "route_to_error_end" ? "" : "hidden"

  return `
    <div class="col-span-2 space-y-1.5">
      <div>
        <label class="block text-[11px] font-medium text-slate-500 mb-1">On Failure</label>
        <select data-error-handling-mode
                name="${fieldName}[mode]"
                data-action="change->property-editor#handleErrorHandlingModeChange"
                class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
          <option value="halt" ${mode === "halt" ? "selected" : ""}>Halt on Failure</option>
          <option value="route_to_error_end" ${mode === "route_to_error_end" ? "selected" : ""}>Route to Error End</option>
        </select>
      </div>
      <div class="${showErrorField}" data-error-output-field-container>
        <label class="block text-[11px] font-medium text-slate-500 mb-1">Error Output Field</label>
        <input type="text"
               data-error-output-field
               name="${fieldName}[errorOutputField]"
               value="${escapeHtml(errorOutputField)}"
               placeholder="ctx.error"
               class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
        <p class="mt-0.5 text-[10px] text-slate-400">The ctx field where error details will be written</p>
      </div>
    </div>
  `
}
```

- [ ] **Step 3: Update step config field labels in templates.js**

In `templates.js`, update the `buildStepConfigFieldsHTML` function config field label (inside the map at the label line):

```javascript
      return `
        <div class="step-config-field${hiddenClass}"
             data-config-field="${escapeHtml(field.key)}"
             ${field.visibleWhen ? `data-visible-when='${escapeHtml(JSON.stringify(field.visibleWhen))}'` : ""}>
          <label class="block text-[10px] font-medium text-slate-500 mb-0.5">
            ${escapeHtml(field.label)}${requiredMark}
          </label>
          ${inputHTML}
        </div>`
```

- [ ] **Step 4: Verify in browser**

Open property editor for different element types. Check:
1. Labels are `text-[11px]` without uppercase
2. Required fields show red dot instead of asterisk
3. Inputs are compact with `text-xs` and `rounded-md`
4. Error handling in Advanced tab is flat (no red box)
5. All fields still save correctly

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor/templates.js
git commit -m "feat: redesign form fields with Figma-style compact labels and inputs"
```

---

### Task 10: Redesign Step Modal Template

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:45-196`

- [ ] **Step 1: Rewrite buildStepModalTemplate**

In `templates.js`, replace the `buildStepModalTemplate` function (lines 45-196) with:

```javascript
export function buildStepModalTemplate() {
  return `
    <div data-step-modal class="hidden absolute inset-0 z-50 overflow-hidden">
      <!-- Backdrop -->
      <div class="absolute inset-0 bg-slate-900/40 backdrop-blur-[2px] transition-opacity"
           data-action="click->property-editor#closeStepModal"></div>

      <!-- Modal container -->
      <div class="absolute inset-0 flex items-center justify-center p-4 pointer-events-none">
        <div class="relative w-full max-w-sm transform transition-all pointer-events-auto">
          <div class="bg-white rounded-xl shadow-2xl ring-1 ring-black/5 overflow-hidden max-h-[80vh] flex flex-col">

            <!-- Header -->
            <div class="flex items-center justify-between px-4 py-2.5 border-b border-slate-100">
              <div class="flex items-center gap-2">
                <div class="w-2 h-2 rounded-full bg-indigo-500 flex-shrink-0"></div>
                <h3 class="text-xs font-semibold text-slate-900">Add Process Step</h3>
              </div>
              <button type="button"
                      data-action="click->property-editor#closeStepModal"
                      class="text-slate-400 hover:text-slate-600 p-1 rounded-md hover:bg-slate-100 transition-colors">
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Body -->
            <div class="flex-1 overflow-y-auto p-3 space-y-2.5">
              <!-- Dynamic Dropdowns Container -->
              <div data-step-modal-dropdowns class="space-y-2"></div>

              <!-- Keyword Parameters (comma-separated) -->
              <div>
                <label class="block text-[11px] font-medium text-slate-500 mb-1">
                  Keyword Parameters
                  <span class="text-slate-400 font-normal">(optional)</span>
                </label>
                <input type="text"
                       data-step-modal-keyword-params-input
                       placeholder="e.g., user_id, status, role"
                       class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                <p class="mt-0.5 text-[10px] text-slate-400">Comma-separated list of keyword parameter names</p>
              </div>

              <!-- Advanced Section (collapsible) -->
              <div class="border border-slate-200 rounded-md">
                <button type="button"
                        data-action="click->property-editor#toggleStepAdvanced"
                        class="w-full flex items-center justify-between px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-50 transition-colors rounded-md">
                  <span>Advanced</span>
                  <svg data-step-advanced-chevron class="w-3.5 h-3.5 text-slate-400 transition-transform duration-150" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                <div data-step-advanced-body class="hidden px-2.5 pb-2.5 border-t border-slate-200">
                  <div class="grid grid-cols-2 gap-2 pt-2.5">
                    <!-- Retry Count -->
                    <div>
                      <label class="block text-[11px] font-medium text-slate-500 mb-1">Retry Count</label>
                      <input type="number"
                             data-step-modal-retry-count
                             min="0" max="5" value="0"
                             class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                    </div>

                    <!-- Retry Backoff -->
                    <div>
                      <label class="block text-[11px] font-medium text-slate-500 mb-1">Retry Backoff</label>
                      <select data-step-modal-retry-backoff
                              class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                        <option value="none" selected>None</option>
                        <option value="linear">Linear</option>
                        <option value="exponential">Exponential</option>
                      </select>
                    </div>

                    <!-- Timeout -->
                    <div>
                      <label class="block text-[11px] font-medium text-slate-500 mb-1">Timeout (sec)</label>
                      <input type="number"
                             data-step-modal-timeout
                             min="0" value="0"
                             class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                    </div>

                    <!-- Guard Condition -->
                    <div>
                      <label class="block text-[11px] font-medium text-slate-500 mb-1">Guard Condition</label>
                      <input type="text"
                             data-step-modal-guard-condition
                             placeholder='ctx[:role] == "admin"'
                             class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
                    </div>
                  </div>
                </div>
              </div>

              <!-- Description -->
              <div>
                <label class="block text-[11px] font-medium text-slate-500 mb-1">
                  Description
                  <span class="text-slate-400 font-normal">(optional)</span>
                </label>
                <textarea data-step-modal-description
                          rows="2"
                          placeholder="Describe what this step does..."
                          class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md resize-none placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"></textarea>
              </div>
            </div>

            <!-- Footer -->
            <div class="flex items-center justify-end gap-2 px-4 py-2.5 border-t border-slate-100 bg-slate-50/50">
              <button type="button"
                      data-action="click->property-editor#closeStepModal"
                      class="px-3 py-1.5 text-xs font-medium text-slate-600 bg-white border border-slate-200 rounded-md hover:bg-slate-50 hover:border-slate-300 transition-colors">
                Cancel
              </button>
              <button type="button"
                      data-action="click->property-editor#addStepFromModal"
                      data-step-modal-submit
                      class="px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                Add Step
              </button>
            </div>

          </div>
        </div>
      </div>
    </div>
  `
}
```

- [ ] **Step 2: Update buildDropdownFieldTemplate to match new styling**

Replace the `buildDropdownFieldTemplate` function (lines 206-227) with:

```javascript
export function buildDropdownFieldTemplate(level, label, optionsHTML, required = false) {
  return `
    <div data-dropdown-level="${level}" class="dropdown-field">
      <label class="block text-[11px] font-medium text-slate-500 mb-1">
        ${escapeHtml(label)}${required ? ' <span class="text-red-400">&#x2022;</span>' : ""}
      </label>
      <div class="relative">
        <select data-dropdown-select="${level}"
                data-action="change->property-editor#handleDropdownChange"
                class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md appearance-none cursor-pointer focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
          <option value="">Select ${label.toLowerCase()}...</option>
          ${optionsHTML}
        </select>
        <div class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
          <svg class="w-3.5 h-3.5 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </div>
    </div>
  `
}
```

- [ ] **Step 3: Update step_manager.js to collect keyword params from comma-separated input**

In `app/javascript/controllers/property_editor/step_manager.js`, update the `_collectKeywordParams` method to read from the new comma-separated input instead of multiple inputs:

```javascript
  _collectKeywordParams(modal) {
    const input = modal.querySelector("[data-step-modal-keyword-params-input]")
    if (!input || !input.value.trim()) return []

    return input.value
      .split(",")
      .map(p => p.trim())
      .filter(p => p.length > 0)
  }
```

Also update `_resetKeywordParams` to clear the single input:

```javascript
  _resetKeywordParams(modal) {
    const input = modal.querySelector("[data-step-modal-keyword-params-input]")
    if (input) input.value = ""
  }
```

Update `openStepModal` — when pre-populating keyword params for editing, set the comma-separated input value. Find the section where keyword params are populated and replace it with:

```javascript
    // Pre-populate keyword params as comma-separated string
    const keywordInput = modal.querySelector("[data-step-modal-keyword-params-input]")
    if (keywordInput && existingStep?.keywordParams?.length > 0) {
      keywordInput.value = existingStep.keywordParams.join(", ")
    }
```

- [ ] **Step 4: Verify in browser**

Open a Process element's property editor. Click "Add Step". Verify:
1. Modal is narrower (`max-w-sm`)
2. Header uses color dot instead of icon box
3. Keyword params is a single comma-separated input
4. Advanced section uses 2-column grid (retry + backoff on one row)
5. Adding a step still works end-to-end

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js app/javascript/controllers/property_editor/step_manager.js
git commit -m "feat: redesign step modal with compact Figma-style layout"
```

---

### Task 11: Redesign Step Item Template

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (buildStepItemTemplate)

- [ ] **Step 1: Rewrite buildStepItemTemplate to use compact row pattern**

In `templates.js`, replace the `buildStepItemTemplate` function (lines 379-491) with:

```javascript
export function buildStepItemTemplate(params) {
  const {
    index,
    action,
    description,
    actionOptionData,
    selectionLabels,
    suboption,
    keywordParams = [],
    retryCount = 0,
    retryBackoff = "none",
    timeout = 0,
    guardCondition = "",
    configFieldsHTML = "",
    currentConfig = {}
  } = params

  const colors = getColorClasses(actionOptionData?.color)
  const colorName = actionOptionData?.color || "blue"

  // Build sub-option path as plain text
  const pathText = buildSelectionPathText(selectionLabels, suboption, actionOptionData)

  // Build keyword params display
  const keywordParamsText = keywordParams.length > 0
    ? `<div class="mt-1"><span class="text-[10px] text-slate-400">params: ${keywordParams.map(p => escapeHtml(p)).join(", ")}</span></div>`
    : ""

  // Check if step has expandable details
  const hasDetails = description || keywordParams.length > 0 || configFieldsHTML

  // Build expandable details section
  const detailsHTML = hasDetails
    ? `<div data-step-details class="hidden pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-1.5">
        ${configFieldsHTML}
        ${description ? `<div>
          <span class="text-[10px] font-medium text-slate-500">Description</span>
          <p class="text-[10px] text-slate-600 mt-0.5 leading-relaxed">${escapeHtml(description)}</p>
        </div>` : ""}
        ${keywordParamsText}
      </div>`
    : ""

  // Drag handle HTML
  const dragHandleHTML = `
    <div class="flex-shrink-0 cursor-grab active:cursor-grabbing text-slate-300 hover:text-slate-500"
         data-drag-handle title="Drag to reorder">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 8h16M4 16h16" />
      </svg>
    </div>
  `

  // Remove button HTML
  const removeButtonHTML = `
    <button type="button"
            data-action="click->property-editor#removeStep"
            class="p-0.5 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded transition-colors flex-shrink-0"
            title="Remove step">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>
  `

  return `
    <div data-step-item
         draggable="true"
         data-step-index="${index}"
         data-step-action="${escapeHtml(action)}"
         class="border-l-2 border-${colorName}-400 px-2.5 py-1.5 hover:bg-slate-50 transition-colors group border-b border-b-slate-100"
         data-action="dragstart->property-editor#handleStepDragStart dragend->property-editor#handleStepDragEnd click->property-editor#toggleStep">

      <div class="flex items-center gap-1.5">
        ${dragHandleHTML}
        <div class="w-2 h-2 rounded-full bg-${colorName}-500 flex-shrink-0"></div>
        <div class="flex-1 min-w-0 flex items-center gap-1.5">
          <span class="text-xs font-medium text-slate-800 truncate">${escapeHtml(actionOptionData?.label || action)}</span>
          ${pathText ? `<span class="text-[11px] text-slate-400 truncate">${pathText}</span>` : ""}
        </div>
        <div class="flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
          ${removeButtonHTML}
        </div>
      </div>

      ${detailsHTML}

      <!-- Hidden inputs for form submission -->
      <input type="hidden" name="steps[${index}][action]" value="${escapeHtml(action)}">
      <input type="hidden" name="steps[${index}][suboption]" value="${escapeHtml(suboption || "")}">
      <input type="hidden" name="steps[${index}][description]" value="${escapeHtml(description || "")}" data-step-description>
      ${selectionLabels ? `<input type="hidden" name="steps[${index}][selectionLabels]" value="${escapeHtml(JSON.stringify(selectionLabels))}">` : ""}
      <input type="hidden" name="steps[${index}][keywordParams]" value="${escapeHtml(JSON.stringify(keywordParams))}">
      <input type="hidden" name="steps[${index}][retryCount]" value="${retryCount}">
      <input type="hidden" name="steps[${index}][retryBackoff]" value="${escapeHtml(retryBackoff)}">
      <input type="hidden" name="steps[${index}][timeout]" value="${timeout}">
      <input type="hidden" name="steps[${index}][guardCondition]" value="${escapeHtml(guardCondition)}">
      <input type="hidden" name="steps[${index}][config]" value="${escapeHtml(JSON.stringify(currentConfig || {}))}" data-step-config>
    </div>
  `
}

/**
 * Build selection path as plain text (slash-separated).
 * @private
 */
function buildSelectionPathText(selectionLabels, suboption, actionOptionData) {
  if (selectionLabels && selectionLabels.length > 1) {
    return selectionLabels.slice(1).map(l => escapeHtml(l)).join(" / ")
  }

  if (suboption) {
    const suboptionParts = suboption.split("/")
    let currentOptions = actionOptionData?.subOptions || []
    const resolvedLabels = []

    for (const part of suboptionParts) {
      const found = currentOptions.find(opt => opt.value === part)
      if (found) {
        resolvedLabels.push(found.label)
        currentOptions = found.subOptions || []
      } else {
        resolvedLabels.push(part)
        break
      }
    }

    return resolvedLabels.map(l => escapeHtml(l)).join(" / ")
  }

  return ""
}
```

- [ ] **Step 2: Remove the old buildSelectionPathHTML function**

Remove the `buildSelectionPathHTML` function (lines 497-531) since it's been replaced by `buildSelectionPathText` above.

- [ ] **Step 3: Verify in browser**

Open a Process element with existing steps. Verify:
1. Steps display as compact rows with left accent border and color dot
2. Sub-option path shows as plain text with `/` separator
3. Remove button appears on hover only
4. Click to expand still works (shows details)
5. Drag to reorder still works
6. Adding/removing steps still functions correctly

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: redesign step items with compact row pattern"
```

---

### Task 12: Redesign Branch Modal Template

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (buildBranchModalTemplate)

- [ ] **Step 1: Rewrite buildBranchModalTemplate**

In `templates.js`, replace the `buildBranchModalTemplate` function (lines 541-743) with:

```javascript
export function buildBranchModalTemplate() {
  return `
    <div data-branch-modal class="hidden absolute inset-0 z-50 overflow-hidden pointer-events-auto">
      <!-- Backdrop -->
      <div class="absolute inset-0 bg-slate-900/40 backdrop-blur-[2px] transition-opacity"
           data-action="click->property-editor#closeBranchModal"></div>

      <!-- Modal container -->
      <div class="absolute inset-0 flex items-center justify-center p-4 pointer-events-none">
        <div class="relative w-full max-w-sm transform transition-all pointer-events-auto">
          <div class="bg-white rounded-xl shadow-2xl ring-1 ring-black/5 overflow-hidden max-h-[80vh] flex flex-col">

            <!-- Header -->
            <div class="flex items-center justify-between px-4 py-2.5 border-b border-slate-100">
              <div class="flex items-center gap-2">
                <div class="w-2 h-2 rounded-full bg-amber-500 flex-shrink-0"></div>
                <h3 class="text-xs font-semibold text-slate-900">Add Decision Branch</h3>
              </div>
              <button type="button"
                      data-action="click->property-editor#closeBranchModal"
                      class="text-slate-400 hover:text-slate-600 p-1 rounded-md hover:bg-slate-100 transition-colors">
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Body -->
            <div class="flex-1 overflow-y-auto p-3 space-y-2.5">
              <!-- Branch Name + Label on one row -->
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <label class="block text-[11px] font-medium text-slate-500 mb-1">
                    Branch Name
                    <span class="text-red-400">&#x2022;</span>
                  </label>
                  <input type="text"
                         data-branch-name
                         placeholder="e.g. Active, Pending"
                         class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                </div>
                <div>
                  <label class="block text-[11px] font-medium text-slate-500 mb-1">
                    Label
                    <span class="text-slate-400 font-normal">(optional)</span>
                  </label>
                  <input type="text"
                         data-branch-modal-label
                         placeholder="e.g. User is Adult"
                         class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                </div>
              </div>

              <!-- Description -->
              <div>
                <label class="block text-[11px] font-medium text-slate-500 mb-1">
                  Description
                  <span class="text-slate-400 font-normal">(optional)</span>
                </label>
                <textarea data-branch-modal-description
                          rows="2"
                          placeholder="Describe this branch..."
                          class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md resize-none placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"></textarea>
              </div>

              <!-- Branch Condition Section -->
              <div class="border-t border-slate-100 pt-2.5">
                <label class="block text-[11px] font-medium text-slate-500 mb-2">Condition (optional)</label>

                <!-- Condition Type Toggle -->
                <div class="flex gap-0.5 p-0.5 bg-slate-100 rounded-lg mb-2.5" data-condition-type-toggle>
                  <button type="button"
                          data-action="click->property-editor#switchBranchConditionType"
                          data-condition-type="field"
                          class="flex-1 py-1 px-2 text-[11px] font-medium rounded-md transition-all duration-150 bg-white text-slate-900 shadow-sm ring-1 ring-black/5">
                    Field Condition
                  </button>
                  <button type="button"
                          data-action="click->property-editor#switchBranchConditionType"
                          data-condition-type="query_count"
                          class="flex-1 py-1 px-2 text-[11px] font-medium rounded-md transition-all duration-150 text-slate-500 hover:text-slate-700 hover:bg-white/50">
                    Query Count
                  </button>
                </div>

                <!-- Field Condition Panel (inline row) -->
                <div data-branch-condition-field-panel>
                  <div class="flex items-center gap-1.5">
                    <input type="text"
                           data-branch-condition-left
                           class="flex-1 px-2 py-1.5 text-xs font-mono border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"
                           placeholder="ctx[:field]" />
                    <select data-branch-condition-op
                            class="w-16 px-1 py-1.5 text-xs border border-slate-200 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                      <option value="==">==</option>
                      <option value="!=">!=</option>
                      <option value=">">&gt;</option>
                      <option value=">=">&gt;=</option>
                      <option value="<">&lt;</option>
                      <option value="<=">&lt;=</option>
                      <option value="is_empty">empty</option>
                      <option value="is_not_empty">!empty</option>
                      <option value="contains">in</option>
                    </select>
                    <input type="text"
                           data-branch-condition-right
                           class="flex-1 px-2 py-1.5 text-xs font-mono border border-slate-200 rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"
                           placeholder="value" />
                  </div>
                </div>

                <!-- Query Count Panel (hidden by default) -->
                <div data-branch-condition-query-panel class="hidden space-y-2">
                  <!-- Entity Selector -->
                  <div>
                    <label class="block text-[11px] font-medium text-slate-500 mb-1">Entity</label>
                    <select data-branch-qc-entity
                            data-action="change->property-editor#onQueryCountEntityChange"
                            class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                      <option value="">Select entity...</option>
                    </select>
                  </div>

                  <!-- WHERE Filters -->
                  <div>
                    <label class="block text-[11px] font-medium text-slate-500 mb-1">Where (optional)</label>
                    <div data-branch-qc-where-rows class="space-y-1.5">
                      <!-- Populated dynamically -->
                    </div>
                    <button type="button"
                            data-action="click->property-editor#addQueryCountWhereRow"
                            class="mt-1 inline-flex items-center gap-0.5 text-[11px] text-amber-600 hover:text-amber-700">
                      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                      </svg>
                      Add filter
                    </button>
                  </div>

                  <!-- Count Comparison -->
                  <div class="grid grid-cols-2 gap-2">
                    <div>
                      <label class="block text-[11px] font-medium text-slate-500 mb-1">Count Operator</label>
                      <select data-branch-qc-count-op
                              class="w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
                        <option value=">">&gt;</option>
                        <option value=">=">&gt;=</option>
                        <option value="==">==</option>
                        <option value="!=">!=</option>
                        <option value="<">&lt;</option>
                        <option value="<=">&lt;=</option>
                      </select>
                    </div>
                    <div>
                      <label class="block text-[11px] font-medium text-slate-500 mb-1">Count Value</label>
                      <input type="number"
                             data-branch-qc-count-value
                             value="0" min="0"
                             class="w-full px-2 py-1.5 text-xs font-mono border border-slate-200 rounded-md focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400"
                             placeholder="0" />
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Footer -->
            <div class="flex items-center justify-end gap-2 px-4 py-2.5 border-t border-slate-100 bg-slate-50/50">
              <button type="button"
                      data-action="click->property-editor#closeBranchModal"
                      class="px-3 py-1.5 text-xs font-medium text-slate-600 bg-white border border-slate-200 rounded-md hover:bg-slate-50 hover:border-slate-300 transition-colors">
                Cancel
              </button>
              <button type="button"
                      data-action="click->property-editor#addBranchFromModal"
                      data-branch-modal-submit
                      class="px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                Add Branch
              </button>
            </div>

          </div>
        </div>
      </div>
    </div>
  `
}
```

- [ ] **Step 2: Verify in browser**

Open a Decision element's property editor. Click "Add Branch". Verify:
1. Modal is `max-w-sm` (narrower)
2. Header uses amber color dot
3. Branch Name + Label are on one row (2-column grid)
4. Field Condition is inline: `[left] [op] [right]` on one row
5. Query Count panel: count operator + value on one row
6. Segmented toggle switches between panels
7. Adding a branch still works end-to-end

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: redesign branch modal with inline condition and compact layout"
```

---

### Task 13: Redesign Branch Item Template

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` (buildBranchItemTemplate)

- [ ] **Step 1: Rewrite buildBranchItemTemplate**

In `templates.js`, replace the `buildBranchItemTemplate` function (lines 750-828) with:

```javascript
export function buildBranchItemTemplate(params) {
  const {
    index,
    branchValue,
    label,
    description,
    branchElementId,
    condition
  } = params

  const branchName = branchValue || `Branch ${index}`
  const displayLabel = label || branchName

  // Build condition summary as inline mono text
  let conditionSummary = ""
  if (condition) {
    if (condition.conditionType === "query_count") {
      const qc = condition.queryConfig || {}
      const entityName = qc.entityName || `Entity#${qc.entityId || "?"}`
      const countOp = condition.countOperator || ">"
      const countVal = condition.countValue ?? 0
      conditionSummary = `Count ${escapeHtml(entityName)} ${escapeHtml(countOp)} ${escapeHtml(String(countVal))}`
    } else if (condition.leftOperand) {
      conditionSummary = `${escapeHtml(condition.leftOperand || "")} ${escapeHtml(condition.operator || "")} ${escapeHtml(condition.rightOperand || "")}`
    }
  }

  // Label suffix (if different from branch name)
  const labelSuffix = (label && label !== branchName)
    ? ` <span class="text-[11px] text-slate-400">\u00B7 ${escapeHtml(label)}</span>`
    : ""

  // Condition display
  const conditionHTML = conditionSummary
    ? `<span class="text-[10px] font-mono text-slate-400 truncate ml-1">${conditionSummary}</span>`
    : ""

  // Remove button
  const removeButtonHTML = `
    <button type="button"
            data-action="click->property-editor#removeBranch"
            class="p-0.5 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded transition-colors flex-shrink-0"
            title="Remove branch">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>
  `

  return `
    <div data-branch-item
         data-branch-index="${index}"
         ${branchElementId ? `data-branch-element-id="${escapeHtml(branchElementId)}"` : ""}
         class="border-l-2 border-amber-400 px-2.5 py-1.5 hover:bg-slate-50 transition-colors group border-b border-b-slate-100">

      <div class="flex items-center gap-1.5">
        <div class="w-2 h-2 rounded-full bg-amber-500 flex-shrink-0"></div>
        <div class="flex-1 min-w-0 flex items-center gap-1">
          <span class="text-xs font-medium text-slate-800">${escapeHtml(branchName)}</span>
          ${labelSuffix}
          ${conditionHTML}
        </div>
        <div class="flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
          ${removeButtonHTML}
        </div>
      </div>

      ${description ? `<div class="pl-5 mt-0.5"><p class="text-[10px] text-slate-400 leading-snug">${escapeHtml(description)}</p></div>` : ""}

      <!-- Hidden inputs for form submission -->
      <input type="hidden" name="branches[${index}][name]" value="${escapeHtml(branchName)}">
      <input type="hidden" name="branches[${index}][label]" value="${escapeHtml(label || "")}">
      <input type="hidden" name="branches[${index}][description]" value="${escapeHtml(description || "")}">
      ${branchElementId ? `<input type="hidden" name="branches[${index}][elementId]" value="${escapeHtml(branchElementId)}">` : ""}
      ${condition ? `<input type="hidden" name="branches[${index}][condition]" value="${escapeHtml(JSON.stringify(condition))}">` : ""}
    </div>
  `
}
```

- [ ] **Step 2: Verify in browser**

Open a Decision element with existing branches. Verify:
1. Branch items display as compact rows with amber left accent border
2. Condition shows as inline monospace text (not colored badge pills)
3. Remove button appears on hover
4. Description shows below the row if present
5. Removing branches still works

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: redesign branch items with compact row pattern"
```

---

### Task 14: Redesign I/O Panel (Input Operations)

**Files:**
- Modify: `app/javascript/controllers/property_editor/io_manager/input_operations.js`

- [ ] **Step 1: Update buildInputsFieldHTML for compact column layout**

In `input_operations.js`, replace the `buildInputsFieldHTML` method (lines 146-222) with:

```javascript
  buildInputsFieldHTML(fieldName, fieldSchema, currentValue, resolveDynamicOptions) {
    const inputs = Array.isArray(currentValue) ? currentValue : []
    const resolvedSchema = resolveDynamicOptions(fieldSchema, fieldName)
    const options = resolvedSchema.options || []

    const hiddenValues = HIDDEN_IO_VALUES

    const visibleInputs = inputs.filter(input => {
      if (input._hidden) return false
      if (hiddenValues.includes(input.value)) return false
      return true
    })

    const inheritedInputs = visibleInputs.filter(input => input._inheritedFromParent)
    const regularInputs = visibleInputs.filter(input => !input._inheritedFromParent)

    const isStartElement = this.controller.currentElement?.type === "start"
    const hasInheritedCtx = inheritedInputs.some(i => i.value === "ctx")
    const hideAddButton = isStartElement && hasInheritedCtx

    let inputsHTML = `
      <div>
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-xs font-semibold text-slate-700">Inputs</span>
          <button type="button"
                  data-action="click->property-editor#addInput"
                  class="${hideAddButton ? 'hidden ' : ''}inline-flex items-center gap-0.5 text-[11px] text-indigo-600 hover:text-indigo-700">
            <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
            Add
          </button>
        </div>

        <div data-inputs-container class="space-y-1">
    `

    // Render inherited inputs
    inheritedInputs.forEach((input, index) => {
      inputsHTML += this.buildInheritedInputItemHTML(index, input.value || "")
    })

    // Empty state
    inputsHTML += `
          <div data-inputs-empty class="${visibleInputs.length > 0 ? 'hidden' : ''} border border-dashed border-slate-200 rounded-md py-3 text-center">
            <p class="text-[11px] text-slate-400">No inputs yet</p>
          </div>
    `

    // Regular inputs
    if (!hideAddButton) {
      regularInputs.forEach((input, index) => {
        inputsHTML += this.buildInputItemHTML(inheritedInputs.length + index, input.value || "", options)
        this.inputIndex = inheritedInputs.length + index + 1
      })
    }

    inputsHTML += `
        </div>
        <input type="hidden" data-input-options value='${JSON.stringify(options)}'>
      </div>
    `

    // Var Mappings for Start elements of expanded subflows
    const isInsideExpandedSubflow = !!this.controller.currentElement?.properties?._expandedFromSubflow
    if (isStartElement && isInsideExpandedSubflow) {
      inputsHTML += this.buildVarMappingsFieldHTML()
    }

    return inputsHTML
  },
```

- [ ] **Step 2: Update buildInputItemHTML and buildInheritedInputItemHTML**

Replace `buildInputItemHTML` (lines 224-291) with:

```javascript
  buildInputItemHTML(index, value, options = null, excludeValues = []) {
    if (!options) {
      const optionsInput = this.controller.formFieldsTarget?.querySelector("[data-input-options]")
      options = optionsInput ? JSON.parse(optionsInput.value) : []
    }

    let optionsHTML = ""
    if (!value) {
      optionsHTML += `<option value="" selected>-- Select --</option>`
    }

    const isStartElement = this.controller.currentElement?.type === "start"
    const allParamsSelected = excludeValues.includes("all params") || value === "all params"
    const hasSpecificParams = excludeValues.some(v => v && v !== "all params") || (value && value !== "all params")

    options.forEach(opt => {
      if (excludeValues.includes(opt.value) && opt.value !== value) return
      if (isStartElement) {
        if (allParamsSelected && opt.value !== "all params") return
        if (hasSpecificParams && opt.value === "all params" && value !== "all params") return
      }
      const selected = opt.value === value ? "selected" : ""
      optionsHTML += `<option value="${escapeHtml(opt.value)}" ${selected}>${escapeHtml(opt.label)}</option>`
    })

    const changeAction = this.controller.currentElement?.type === "start" ? 'data-action="change->property-editor#onInputChange"' : ""

    const isAllParams = value === "all params"
    const valueDisplay = isAllParams ? "text-[11px] font-medium text-indigo-600" : ""

    return `
      <div data-input-item class="flex items-center gap-1.5 py-0.5">
        <select data-input-value
                name="inputs[${index}][value]"
                ${changeAction}
                class="flex-1 px-2 py-1 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500/20 focus:border-indigo-400 ${valueDisplay}">
          ${optionsHTML}
        </select>
        <button type="button"
                data-action="click->property-editor#removeInput"
                class="p-0.5 text-slate-300 hover:text-red-500 rounded transition-colors flex-shrink-0"
                title="Remove">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `
  },
```

Replace `buildInheritedInputItemHTML` (lines 293-311) with:

```javascript
  buildInheritedInputItemHTML(index, value) {
    return `
      <div data-inherited-input-item class="flex items-center gap-1.5 py-0.5">
        <span class="flex-1 px-2 py-1 text-xs italic text-slate-400">${escapeHtml(value)} <span class="text-[10px]">(inherited)</span></span>
        <input type="hidden" name="inputs[${index}][value]" value="${escapeHtml(value)}">
        <input type="hidden" name="inputs[${index}][_inheritedFromParent]" value="true">
      </div>
    `
  },
```

- [ ] **Step 3: Verify in browser**

Open an element with inputs. Verify:
1. Inputs section has compact header with inline "Add" button
2. Input items are compact rows without background colors
3. Inherited inputs show as italic text with "(inherited)"
4. Empty state uses dashed border pattern
5. Adding/removing inputs still works

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/io_manager/input_operations.js
git commit -m "feat: redesign inputs panel with compact Figma-style rows"
```

---

### Task 15: Redesign I/O Panel (Output Operations)

**Files:**
- Modify: `app/javascript/controllers/property_editor/io_manager/output_operations.js`

- [ ] **Step 1: Update buildOutputsFieldHTML and buildOutputItemHTML**

In `output_operations.js`, replace `buildOutputsFieldHTML` (lines 685-766) with:

```javascript
  buildOutputsFieldHTML(fieldName, fieldSchema, currentValue, resolveDynamicOptions) {
    const isEndElement = this.controller.currentElement?.type === "end"
    const isInsideExpandedSubflow = !!this.controller.currentElement?.properties?._expandedFromSubflow

    if (isEndElement && isInsideExpandedSubflow) {
      let outputsHTML = `
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-xs font-semibold text-slate-700">${fieldSchema.label}</span>
          </div>
          <div class="space-y-3">
      `
      outputsHTML += this.buildSignalWiringSubsectionHTML()
      outputsHTML += this.buildDataMappingsSubsectionHTML()
      outputsHTML += `
          </div>
        </div>
      `
      return outputsHTML
    }

    const outputs = Array.isArray(currentValue) ? currentValue : []
    const resolvedSchema = resolveDynamicOptions(fieldSchema, fieldName)
    const options = resolvedSchema.options || []
    const hiddenValues = HIDDEN_IO_VALUES

    const visibleOutputs = outputs.filter(output => {
      if (output._hidden) return false
      if (hiddenValues.includes(output.value)) return false
      return true
    })

    const selectedValues = visibleOutputs.map(o => o.value).filter(v => v)

    let outputsHTML = `
      <div>
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-xs font-semibold text-slate-700">Outputs</span>
          <button type="button"
                  data-action="click->property-editor#addOutput"
                  class="inline-flex items-center gap-0.5 text-[11px] text-indigo-600 hover:text-indigo-700">
            <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
            Add
          </button>
        </div>

        <div data-outputs-container class="space-y-1">
          <div data-outputs-empty class="${visibleOutputs.length > 0 ? 'hidden' : ''} border border-dashed border-slate-200 rounded-md py-3 text-center">
            <p class="text-[11px] text-slate-400">No outputs yet</p>
          </div>
    `

    visibleOutputs.forEach((output, index) => {
      outputsHTML += this.buildOutputItemHTML(index, output.value || "", options, selectedValues)
      this.outputIndex = index + 1
    })

    outputsHTML += `
        </div>
        <input type="hidden" data-output-options value='${JSON.stringify(options)}'>
      </div>
    `

    return outputsHTML
  },
```

Replace `buildOutputItemHTML` (lines 768-813) with:

```javascript
  buildOutputItemHTML(index, value, options = null, excludeValues = []) {
    if (!options) {
      const optionsInput = this.controller.formFieldsTarget?.querySelector("[data-output-options]")
      options = optionsInput ? JSON.parse(optionsInput.value) : []
    }

    let optionsHTML = ""
    if (!value) {
      optionsHTML += `<option value="" selected>-- Select --</option>`
    }

    options.forEach(opt => {
      if (excludeValues.includes(opt.value) && opt.value !== value) return
      const selected = opt.value === value ? "selected" : ""
      optionsHTML += `<option value="${escapeHtml(opt.value)}" ${selected}>${escapeHtml(opt.label)}</option>`
    })

    return `
      <div data-output-item class="flex items-center gap-1.5 py-0.5">
        <select data-output-value
                name="outputs[${index}][value]"
                class="flex-1 px-2 py-1 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500/20 focus:border-indigo-400">
          ${optionsHTML}
        </select>
        <button type="button"
                data-action="click->property-editor#removeOutput"
                class="p-0.5 text-slate-300 hover:text-red-500 rounded transition-colors flex-shrink-0"
                title="Remove">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `
  },
```

- [ ] **Step 2: Update signal wiring and data mapping templates**

Replace `buildSignalWiringSubsectionHTML` with:

```javascript
  buildSignalWiringSubsectionHTML() {
    let currentSignals = this.controller.currentElement?.properties?.signalWiring || []
    this.signalWiringIndex = 0
    const hiddenValues = HIDDEN_IO_VALUES

    currentSignals = currentSignals.filter(signal => {
      if (signal._hidden) return false
      if (hiddenValues.includes(signal.value)) return false
      if (hiddenValues.includes(signal.keyword)) return false
      return true
    })

    let html = `
      <div class="border-l-2 border-slate-200 pl-2.5">
        <div class="flex items-center justify-between mb-1">
          <span class="text-[11px] font-semibold text-slate-600">Signal Wiring</span>
          <button type="button" data-action="click->property-editor#addSignalWiring"
                  class="inline-flex items-center gap-0.5 text-[10px] text-indigo-600 hover:text-indigo-700">
            <svg class="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
            Add
          </button>
        </div>
        <div data-signal-wiring-container class="space-y-1">
          <div data-signal-wiring-empty class="${currentSignals.length > 0 ? 'hidden' : ''} border border-dashed border-slate-200 rounded-md py-2 text-center">
            <p class="text-[10px] text-slate-400">No signals</p>
          </div>
    `

    currentSignals.forEach((signal, index) => {
      html += this.buildSignalWiringItemHTML(index, signal.keyword || "", signal.value || "")
      this.signalWiringIndex = index + 1
    })

    html += `
          <div data-signal-wiring-end style="display: none;"></div>
        </div>
      </div>
    `
    return html
  },
```

Replace `buildSignalWiringItemHTML` with:

```javascript
  buildSignalWiringItemHTML(index, keyword = "", value = "") {
    return `
      <div data-signal-wiring-item data-signal-wiring-index="${index}" class="flex items-center gap-1 py-0.5">
        <input type="text" data-signal-wiring-keyword name="signalWiring[${index}][keyword]" value="${escapeHtml(keyword)}" placeholder="keyword"
               class="flex-1 px-2 py-1 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500/20 focus:border-indigo-400">
        <span class="text-slate-400 text-[10px]">\u2192</span>
        <input type="text" data-signal-wiring-value name="signalWiring[${index}][value]" value="${escapeHtml(value)}" placeholder="value"
               class="flex-1 px-2 py-1 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500/20 focus:border-indigo-400">
        <button type="button" data-action="click->property-editor#removeSignalWiring" class="p-0.5 text-slate-300 hover:text-red-500 rounded transition-colors" title="Remove">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>
    `
  },
```

Apply the same pattern to `buildDataMappingsSubsectionHTML` and `buildDataMappingItemHTML` — replace the purple color-coded backgrounds with the same compact inline pattern. Replace `buildDataMappingsSubsectionHTML`:

```javascript
  buildDataMappingsSubsectionHTML() {
    const currentMappings = this.controller.currentElement?.properties?.dataMappings || []
    this.dataMappingIndex = 0

    let html = `
      <div class="border-l-2 border-slate-200 pl-2.5">
        <div class="flex items-center justify-between mb-1">
          <span class="text-[11px] font-semibold text-slate-600">Data Mappings</span>
          <button type="button" data-action="click->property-editor#addDataMapping"
                  class="inline-flex items-center gap-0.5 text-[10px] text-indigo-600 hover:text-indigo-700">
            <svg class="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
            Add
          </button>
        </div>
        <div data-data-mappings-container class="space-y-1">
          <div data-data-mappings-empty class="${currentMappings.length > 0 ? 'hidden' : ''} border border-dashed border-slate-200 rounded-md py-2 text-center">
            <p class="text-[10px] text-slate-400">No data mappings</p>
          </div>
    `

    currentMappings.forEach((mapping, index) => {
      html += this.buildDataMappingItemHTML(index, mapping.keyword || "", mapping.value || "")
      this.dataMappingIndex = index + 1
    })

    html += `
          <div data-data-mappings-end style="display: none;"></div>
        </div>
      </div>
    `
    return html
  },
```

Replace `buildDataMappingItemHTML`:

```javascript
  buildDataMappingItemHTML(index, keyword = "", value = "") {
    return `
      <div data-data-mapping-item data-data-mapping-index="${index}" class="flex items-center gap-1 py-0.5">
        <input type="text" data-data-mapping-keyword name="dataMappings[${index}][keyword]" value="${escapeHtml(keyword)}" placeholder="keyword"
               class="flex-1 px-2 py-1 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500/20 focus:border-indigo-400">
        <span class="text-slate-400 text-[10px]">\u2192</span>
        <input type="text" data-data-mapping-value name="dataMappings[${index}][value]" value="${escapeHtml(value)}" placeholder="value"
               class="flex-1 px-2 py-1 text-xs border border-slate-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500/20 focus:border-indigo-400">
        <button type="button" data-action="click->property-editor#removeDataMapping" class="p-0.5 text-slate-300 hover:text-red-500 rounded transition-colors" title="Remove">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>
    `
  },
```

Apply same pattern to `buildVarMappingsFieldHTML` and `buildVarMappingItemHTML` — remove color backgrounds, use compact inline pattern.

- [ ] **Step 3: Verify in browser**

Open elements of different types and check the I/O tab:
1. Inputs/Outputs have compact section headers with inline Add
2. Items are flat rows without colored backgrounds
3. Signal wiring / data mapping use compact key-value rows
4. Var mappings use compact key-value pattern
5. All add/remove operations still work
6. Save still collects I/O correctly

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/io_manager/input_operations.js app/javascript/controllers/property_editor/io_manager/output_operations.js
git commit -m "feat: redesign I/O panel with compact Figma-style rows"
```

---

### Task 16: Redesign Join Panel

**Files:**
- Modify: `app/javascript/controllers/property_editor/join_manager.js`

- [ ] **Step 1: Update buildJoinFieldHTML for compact checkboxes**

In `join_manager.js`, replace the `buildJoinFieldHTML` method (lines 14-97) with a version that uses compact rows. The logic for detecting source decisions and connected branches stays the same; only the HTML output changes:

```javascript
  buildJoinFieldHTML(element) {
    const canvas = this.controller.canvas
    if (!canvas) return ""

    const sourceDecision = this._findSourceDecision(element, canvas)
    if (!sourceDecision) {
      return `
        <div class="border border-dashed border-slate-200 rounded-md py-3 text-center">
          <p class="text-[11px] text-slate-400">No source decision detected</p>
        </div>
      `
    }

    // Get branches from the source decision
    const branches = this._getDecisionBranches(sourceDecision, canvas)
    if (branches.length === 0) {
      return `
        <div class="space-y-2">
          <p class="text-[11px] text-slate-400">Branches from: <span class="font-medium text-slate-600">${sourceDecision.label || "Decision"}</span></p>
          <div class="border border-dashed border-slate-200 rounded-md py-3 text-center">
            <p class="text-[11px] text-slate-400">No branches found</p>
          </div>
        </div>
      `
    }

    // Detect which branches are already connected
    const connectedBranches = this._detectConnectedBranches(element, sourceDecision, branches, canvas)

    // Sort branches by element x-position
    const branchKeys = branches.map(conn => conn.to)
    const sortedBranchKeys = this._sortBranchesByElementPosition(branchKeys, sourceDecision, canvas)

    let html = `
      <div class="space-y-1.5">
        <p class="text-[11px] text-slate-400">Branches from: <span class="font-medium text-slate-600">${sourceDecision.label || "Decision"}</span></p>
        <input type="hidden" data-join-source-decision-id value="${sourceDecision.id}">
        <div data-join-branch-checkboxes class="space-y-1">
    `

    sortedBranchKeys.forEach(branchElementId => {
      const branchEl = canvas.elements.find(el => el.id === branchElementId)
      if (!branchEl) return

      const branchConn = branches.find(c => c.to === branchElementId)
      const branchLabel = branchEl.label || branchConn?.label || "Branch"
      const isConnected = connectedBranches.has(branchElementId)
      const dotColor = isConnected ? "bg-green-500" : "bg-slate-300"
      const connectedBadge = isConnected
        ? `<span class="text-[10px] bg-green-50 text-green-600 rounded px-1">connected</span>`
        : ""

      html += `
          <label class="flex items-center gap-1.5 py-0.5 cursor-pointer hover:bg-slate-50 rounded px-1 -mx-1">
            <input type="checkbox"
                   data-join-branch-checkbox
                   data-branch-element-id="${branchElementId}"
                   data-action="change->property-editor#onJoinBranchCheckboxChange"
                   ${isConnected ? "checked" : ""}
                   class="w-3 h-3 rounded border-slate-300 text-indigo-600 focus:ring-indigo-500/20">
            <div class="w-2 h-2 rounded-full ${dotColor} flex-shrink-0"></div>
            <span class="text-xs text-slate-700">${escapeHtml(branchLabel)}</span>
            ${connectedBadge}
          </label>
      `
    })

    html += `
        </div>
      </div>
    `

    return html
  }
```

- [ ] **Step 2: Verify in browser**

Open a Join element. Verify:
1. Shows "Branches from: [Decision Name]" header
2. Compact checkbox rows with color dot indicators
3. "connected" badge on connected branches
4. Empty state when no source decision found
5. Checking/unchecking still creates/removes connections

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/join_manager.js
git commit -m "feat: redesign join panel with compact checkbox rows"
```

---

### Task 17: Final Verification

- [ ] **Step 1: Full browser verification pass**

Open a flowchart with multiple element types. Verify each:

1. **Process element**: General tab fields are compact, Steps tab shows step items as rows, Step modal is narrower with inline keyword params and 2-col advanced, I/O tab has compact inputs/outputs, Advanced tab error handling is flat
2. **Decision element**: Branches tab shows branches as compact amber rows, Branch modal has inline condition builder, Quick-add still works
3. **Join element**: Shows source decision, compact checkbox rows, connected badges
4. **Start/End elements**: I/O panel with inherited inputs, var mappings for subflows
5. **Connection**: Double-click a connection line — simpler editor still works
6. **Resize**: Drag handle works within 360-520px range
7. **Save/Cancel**: All element types save and cancel correctly
8. **Tab switching**: All tabs switch and badge counts update

- [ ] **Step 2: Run existing test suite**

Run: `bundle exec rspec spec/components/property_editor/ --format documentation`
Expected: All new ViewComponent specs pass

Run: `bundle exec rspec spec/ --format documentation 2>&1 | tail -30`
Expected: No new failures introduced (pre-existing failures documented in memory are acceptable)

- [ ] **Step 3: Commit any final fixes**

If any issues were found in step 1 or 2, fix and commit them individually.

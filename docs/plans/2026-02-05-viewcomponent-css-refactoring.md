# ViewComponent CSS Refactoring Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create reusable ViewComponents for common UI patterns (buttons, badges, forms, modals, cards), standardize CSS, and clean up application.css.

**Architecture:** New components follow the existing AlertComponent pattern - Ruby config hashes map variants to TailwindCSS classes. Components inherit from ApplicationComponent which provides HTML attribute merging.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, TailwindCSS, RSpec

---

## Task 1: Clean up application.css

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Remove duplicate scrollbar CSS**

Lines 356-378 duplicate lines 109-130. Remove the duplicate block at 356-378.

Delete this block (lines 356-378):
```css
/* Property Editor Modal - Scrollable Form Fields */
.property-editor [data-property-editor-target="formFields"] {
  max-height: 500px;
  overflow-y: auto;
}

.property-editor [data-property-editor-target="formFields"]::-webkit-scrollbar {
  width: 6px;
}

.property-editor [data-property-editor-target="formFields"]::-webkit-scrollbar-track {
  background: #f1f5f9;
  border-radius: 3px;
}

.property-editor [data-property-editor-target="formFields"]::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 3px;
}

.property-editor [data-property-editor-target="formFields"]::-webkit-scrollbar-thumb:hover {
  background: #94a3b8;
}
```

**Step 2: Add reusable scrollbar utility class**

Add after line 103 (after `.attribute-item:hover .attribute-remove`):

```css
/* ===================
   Utility Classes
   =================== */

/* Custom Scrollbar - Reusable class for consistent scrollbar styling */
.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: #f1f5f9;
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: #94a3b8;
}
```

**Step 3: Verify CSS changes**

Run: `bin/rails assets:precompile RAILS_ENV=test 2>&1 | head -20`
Expected: No CSS errors

**Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "refactor(css): remove duplicate scrollbar styles, add utility class"
```

---

## Task 2: Create ButtonComponent

**Files:**
- Create: `app/components/button_component.rb`
- Create: `app/components/button_component.html.erb`
- Create: `spec/components/button_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/button_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ButtonComponent, type: :component do
  describe "#initialize" do
    it "sets default variant to primary" do
      component = described_class.new
      expect(component.variant).to eq(:primary)
    end

    it "sets default size to md" do
      component = described_class.new
      expect(component.size).to eq(:md)
    end

    it "sets default tag to button" do
      component = described_class.new
      expect(component.tag).to eq(:button)
    end

    it "accepts custom variant" do
      component = described_class.new(variant: :danger)
      expect(component.variant).to eq(:danger)
    end

    it "converts string variant to symbol" do
      component = described_class.new(variant: "secondary")
      expect(component.variant).to eq(:secondary)
    end
  end

  describe "variant styling" do
    describe "primary variant" do
      let(:component) { described_class.new(variant: :primary) }

      it "has indigo background" do
        expect(component.variant_classes).to include("bg-indigo-600")
        expect(component.variant_classes).to include("text-white")
      end
    end

    describe "secondary variant" do
      let(:component) { described_class.new(variant: :secondary) }

      it "has white background with border" do
        expect(component.variant_classes).to include("bg-white")
        expect(component.variant_classes).to include("border-gray-300")
      end
    end

    describe "danger variant" do
      let(:component) { described_class.new(variant: :danger) }

      it "has red background" do
        expect(component.variant_classes).to include("bg-red-600")
        expect(component.variant_classes).to include("text-white")
      end
    end

    describe "ghost variant" do
      let(:component) { described_class.new(variant: :ghost) }

      it "has transparent background" do
        expect(component.variant_classes).to include("text-gray-600")
        expect(component.variant_classes).to include("hover:bg-gray-100")
      end
    end
  end

  describe "size styling" do
    it "returns small size classes" do
      component = described_class.new(size: :sm)
      expect(component.size_classes).to include("px-3")
      expect(component.size_classes).to include("text-xs")
    end

    it "returns medium size classes" do
      component = described_class.new(size: :md)
      expect(component.size_classes).to include("px-4")
      expect(component.size_classes).to include("text-sm")
    end

    it "returns large size classes" do
      component = described_class.new(size: :lg)
      expect(component.size_classes).to include("px-6")
      expect(component.size_classes).to include("text-base")
    end
  end

  describe "rendering" do
    it "renders as button by default" do
      render_inline(described_class.new) { "Click me" }
      expect(page).to have_button("Click me")
    end

    it "renders as link when tag is :a" do
      render_inline(described_class.new(tag: :a, href: "/test")) { "Go" }
      expect(page).to have_link("Go", href: "/test")
    end

    it "renders with primary styling" do
      render_inline(described_class.new(variant: :primary)) { "Save" }
      expect(page).to have_css(".bg-indigo-600")
    end

    it "renders content from block" do
      render_inline(described_class.new) { "Submit" }
      expect(page).to have_text("Submit")
    end

    it "applies disabled attribute" do
      render_inline(described_class.new(disabled: true)) { "Disabled" }
      expect(page).to have_css("button[disabled]")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(data: { action: "click->test#run" })) { "Test" }
      expect(page).to have_css("[data-action='click->test#run']")
    end

    it "renders full width when specified" do
      render_inline(described_class.new(full_width: true)) { "Wide" }
      expect(page).to have_css(".w-full")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/button_component_spec.rb`
Expected: FAIL with "uninitialized constant ButtonComponent"

**Step 3: Write ButtonComponent Ruby class**

Create `app/components/button_component.rb`:

```ruby
# frozen_string_literal: true

class ButtonComponent < ApplicationComponent
  VARIANTS = {
    primary: "bg-indigo-600 text-white border border-transparent hover:bg-indigo-700 focus:ring-indigo-600",
    secondary: "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50 focus:ring-indigo-500",
    danger: "bg-red-600 text-white border border-transparent hover:bg-red-700 focus:ring-red-600",
    ghost: "text-gray-600 hover:text-gray-900 hover:bg-gray-100 border border-transparent focus:ring-indigo-500"
  }.freeze

  SIZES = {
    sm: "px-3 py-1.5 text-xs",
    md: "px-4 py-2 text-sm",
    lg: "px-6 py-3 text-base"
  }.freeze

  BASE_CLASSES = "inline-flex items-center justify-center font-medium rounded-lg transition-all focus:outline-none focus:ring-2 focus:ring-offset-2"

  attr_reader :variant, :size, :tag, :href, :disabled, :full_width

  def initialize(variant: :primary, size: :md, tag: :button, href: nil, disabled: false, full_width: false, **html_attributes)
    @variant = variant.to_sym
    @size = size.to_sym
    @tag = tag.to_sym
    @href = href
    @disabled = disabled
    @full_width = full_width
    @html_attributes = html_attributes
  end

  def variant_classes
    VARIANTS.fetch(variant, VARIANTS[:primary])
  end

  def size_classes
    SIZES.fetch(size, SIZES[:md])
  end

  def component_classes
    classes = [BASE_CLASSES, variant_classes, size_classes]
    classes << "w-full" if full_width
    classes << "opacity-50 cursor-not-allowed" if disabled
    classes.join(" ")
  end

  def html_attributes
    base = {
      class: component_classes
    }

    if tag == :button
      base[:type] = @html_attributes.fetch(:type, "button")
      base[:disabled] = true if disabled
    elsif tag == :a
      base[:href] = href
    end

    merge_html_attributes(base, @html_attributes)
  end
end
```

**Step 4: Write ButtonComponent template**

Create `app/components/button_component.html.erb`:

```erb
<%= content_tag(tag, html_attributes) do %>
  <%= content %>
<% end %>
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/button_component_spec.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/button_component.rb app/components/button_component.html.erb spec/components/button_component_spec.rb
git commit -m "feat(components): add ButtonComponent with variants and sizes"
```

---

## Task 3: Create BadgeComponent

**Files:**
- Create: `app/components/badge_component.rb`
- Create: `app/components/badge_component.html.erb`
- Create: `spec/components/badge_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/badge_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BadgeComponent, type: :component do
  describe "#initialize" do
    it "sets default variant to default" do
      component = described_class.new
      expect(component.variant).to eq(:default)
    end

    it "sets default size to md" do
      component = described_class.new
      expect(component.size).to eq(:md)
    end

    it "accepts custom variant" do
      component = described_class.new(variant: :success)
      expect(component.variant).to eq(:success)
    end

    it "converts string variant to symbol" do
      component = described_class.new(variant: "danger")
      expect(component.variant).to eq(:danger)
    end
  end

  describe "variant styling" do
    {
      default: %w[bg-gray-100 text-gray-800],
      primary: %w[bg-indigo-100 text-indigo-800],
      success: %w[bg-green-100 text-green-800],
      warning: %w[bg-yellow-100 text-yellow-800],
      danger: %w[bg-red-100 text-red-800],
      info: %w[bg-blue-100 text-blue-800],
      purple: %w[bg-purple-100 text-purple-800]
    }.each do |variant, expected_classes|
      describe "#{variant} variant" do
        let(:component) { described_class.new(variant: variant) }

        it "has correct styling" do
          expected_classes.each do |css_class|
            expect(component.variant_classes).to include(css_class)
          end
        end
      end
    end
  end

  describe "size styling" do
    it "returns small size classes" do
      component = described_class.new(size: :sm)
      expect(component.size_classes).to include("px-2")
      expect(component.size_classes).to include("text-xs")
    end

    it "returns medium size classes" do
      component = described_class.new(size: :md)
      expect(component.size_classes).to include("px-2.5")
      expect(component.size_classes).to include("text-sm")
    end
  end

  describe "rendering" do
    it "renders content from block" do
      render_inline(described_class.new) { "Active" }
      expect(page).to have_text("Active")
    end

    it "renders with correct variant styling" do
      render_inline(described_class.new(variant: :success)) { "Success" }
      expect(page).to have_css(".bg-green-100")
      expect(page).to have_css(".text-green-800")
    end

    it "renders as span element" do
      render_inline(described_class.new) { "Badge" }
      expect(page).to have_css("span")
    end

    it "includes rounded-full for pill shape" do
      render_inline(described_class.new) { "Badge" }
      expect(page).to have_css(".rounded-full")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(data: { test: "value" })) { "Test" }
      expect(page).to have_css("[data-test='value']")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/badge_component_spec.rb`
Expected: FAIL with "uninitialized constant BadgeComponent"

**Step 3: Write BadgeComponent Ruby class**

Create `app/components/badge_component.rb`:

```ruby
# frozen_string_literal: true

class BadgeComponent < ApplicationComponent
  VARIANTS = {
    default: "bg-gray-100 text-gray-800",
    primary: "bg-indigo-100 text-indigo-800",
    success: "bg-green-100 text-green-800",
    warning: "bg-yellow-100 text-yellow-800",
    danger: "bg-red-100 text-red-800",
    info: "bg-blue-100 text-blue-800",
    purple: "bg-purple-100 text-purple-800"
  }.freeze

  SIZES = {
    sm: "px-2 py-0.5 text-xs",
    md: "px-2.5 py-1 text-sm"
  }.freeze

  BASE_CLASSES = "inline-flex items-center font-medium rounded-full"

  attr_reader :variant, :size

  def initialize(variant: :default, size: :md, **html_attributes)
    @variant = variant.to_sym
    @size = size.to_sym
    @html_attributes = html_attributes
  end

  def variant_classes
    VARIANTS.fetch(variant, VARIANTS[:default])
  end

  def size_classes
    SIZES.fetch(size, SIZES[:md])
  end

  def component_classes
    [BASE_CLASSES, variant_classes, size_classes].join(" ")
  end

  def html_attributes
    base = { class: component_classes }
    merge_html_attributes(base, @html_attributes)
  end
end
```

**Step 4: Write BadgeComponent template**

Create `app/components/badge_component.html.erb`:

```erb
<span <%= tag.attributes(html_attributes) %>><%= content %></span>
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/badge_component_spec.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/badge_component.rb app/components/badge_component.html.erb spec/components/badge_component_spec.rb
git commit -m "feat(components): add BadgeComponent with color variants"
```

---

## Task 4: Create CardComponent

**Files:**
- Create: `app/components/card_component.rb`
- Create: `app/components/card_component.html.erb`
- Create: `spec/components/card_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/card_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CardComponent, type: :component do
  describe "#initialize" do
    it "sets default variant to default" do
      component = described_class.new
      expect(component.variant).to eq(:default)
    end

    it "sets default padding to md" do
      component = described_class.new
      expect(component.padding).to eq(:md)
    end

    it "accepts custom variant" do
      component = described_class.new(variant: :bordered)
      expect(component.variant).to eq(:bordered)
    end
  end

  describe "variant styling" do
    describe "default variant" do
      let(:component) { described_class.new(variant: :default) }

      it "has shadow styling" do
        expect(component.variant_classes).to include("shadow")
        expect(component.variant_classes).to include("bg-white")
      end
    end

    describe "bordered variant" do
      let(:component) { described_class.new(variant: :bordered) }

      it "has border styling" do
        expect(component.variant_classes).to include("border")
        expect(component.variant_classes).to include("border-gray-200")
      end
    end

    describe "flat variant" do
      let(:component) { described_class.new(variant: :flat) }

      it "has subtle background" do
        expect(component.variant_classes).to include("bg-gray-50")
      end
    end
  end

  describe "padding styling" do
    it "returns no padding for none" do
      component = described_class.new(padding: :none)
      expect(component.padding_classes).to eq("")
    end

    it "returns small padding" do
      component = described_class.new(padding: :sm)
      expect(component.padding_classes).to include("p-4")
    end

    it "returns medium padding" do
      component = described_class.new(padding: :md)
      expect(component.padding_classes).to include("p-6")
    end

    it "returns large padding" do
      component = described_class.new(padding: :lg)
      expect(component.padding_classes).to include("p-8")
    end
  end

  describe "rendering" do
    it "renders content from block" do
      render_inline(described_class.new) { "Card content" }
      expect(page).to have_text("Card content")
    end

    it "renders as div element" do
      render_inline(described_class.new) { "Content" }
      expect(page).to have_css("div.rounded-lg")
    end

    it "renders with shadow for default variant" do
      render_inline(described_class.new(variant: :default)) { "Content" }
      expect(page).to have_css(".shadow")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(id: "my-card")) { "Content" }
      expect(page).to have_css("#my-card")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/card_component_spec.rb`
Expected: FAIL with "uninitialized constant CardComponent"

**Step 3: Write CardComponent Ruby class**

Create `app/components/card_component.rb`:

```ruby
# frozen_string_literal: true

class CardComponent < ApplicationComponent
  VARIANTS = {
    default: "bg-white shadow",
    bordered: "bg-white border border-gray-200",
    flat: "bg-gray-50"
  }.freeze

  PADDINGS = {
    none: "",
    sm: "p-4",
    md: "p-6",
    lg: "p-8"
  }.freeze

  BASE_CLASSES = "rounded-lg"

  attr_reader :variant, :padding

  def initialize(variant: :default, padding: :md, **html_attributes)
    @variant = variant.to_sym
    @padding = padding.to_sym
    @html_attributes = html_attributes
  end

  def variant_classes
    VARIANTS.fetch(variant, VARIANTS[:default])
  end

  def padding_classes
    PADDINGS.fetch(padding, PADDINGS[:md])
  end

  def component_classes
    [BASE_CLASSES, variant_classes, padding_classes].compact_blank.join(" ")
  end

  def html_attributes
    base = { class: component_classes }
    merge_html_attributes(base, @html_attributes)
  end
end
```

**Step 4: Write CardComponent template**

Create `app/components/card_component.html.erb`:

```erb
<div <%= tag.attributes(html_attributes) %>><%= content %></div>
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/card_component_spec.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/card_component.rb app/components/card_component.html.erb spec/components/card_component_spec.rb
git commit -m "feat(components): add CardComponent with variants and padding"
```

---

## Task 5: Create FormInputComponent

**Files:**
- Create: `app/components/form_input_component.rb`
- Create: `app/components/form_input_component.html.erb`
- Create: `spec/components/form_input_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/form_input_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormInputComponent, type: :component do
  describe "#initialize" do
    it "sets default type to text" do
      component = described_class.new(name: "test")
      expect(component.type).to eq(:text)
    end

    it "accepts custom type" do
      component = described_class.new(name: "email", type: :email)
      expect(component.type).to eq(:email)
    end

    it "requires name parameter" do
      expect { described_class.new }.to raise_error(ArgumentError)
    end
  end

  describe "input types" do
    it "renders text input" do
      render_inline(described_class.new(name: "title", type: :text))
      expect(page).to have_css("input[type='text']")
    end

    it "renders email input" do
      render_inline(described_class.new(name: "email", type: :email))
      expect(page).to have_css("input[type='email']")
    end

    it "renders password input" do
      render_inline(described_class.new(name: "password", type: :password))
      expect(page).to have_css("input[type='password']")
    end

    it "renders textarea" do
      render_inline(described_class.new(name: "description", type: :textarea))
      expect(page).to have_css("textarea")
    end

    it "renders select" do
      render_inline(described_class.new(name: "category", type: :select, options: [["One", 1], ["Two", 2]]))
      expect(page).to have_css("select")
      expect(page).to have_css("option", count: 2)
    end
  end

  describe "label rendering" do
    it "renders label when provided" do
      render_inline(described_class.new(name: "title", label: "Title"))
      expect(page).to have_css("label", text: "Title")
    end

    it "does not render label when not provided" do
      render_inline(described_class.new(name: "title"))
      expect(page).not_to have_css("label")
    end

    it "associates label with input" do
      render_inline(described_class.new(name: "title", label: "Title", id: "title-input"))
      expect(page).to have_css("label[for='title-input']")
    end
  end

  describe "error state" do
    it "renders error message when provided" do
      render_inline(described_class.new(name: "title", error: "is required"))
      expect(page).to have_text("is required")
    end

    it "applies error styling to input" do
      render_inline(described_class.new(name: "title", error: "invalid"))
      expect(page).to have_css(".border-red-300")
    end

    it "does not show error styling when no error" do
      render_inline(described_class.new(name: "title"))
      expect(page).not_to have_css(".border-red-300")
    end
  end

  describe "styling" do
    it "applies base input classes" do
      render_inline(described_class.new(name: "test"))
      expect(page).to have_css(".rounded-md")
      expect(page).to have_css(".shadow-sm")
    end

    it "applies focus classes" do
      render_inline(described_class.new(name: "test"))
      expect(page).to have_css("[class*='focus:border-indigo-500']")
    end
  end

  describe "attributes" do
    it "sets placeholder" do
      render_inline(described_class.new(name: "title", placeholder: "Enter title"))
      expect(page).to have_css("input[placeholder='Enter title']")
    end

    it "sets value" do
      render_inline(described_class.new(name: "title", value: "Test value"))
      expect(page).to have_css("input[value='Test value']")
    end

    it "sets disabled state" do
      render_inline(described_class.new(name: "title", disabled: true))
      expect(page).to have_css("input[disabled]")
    end

    it "sets required state" do
      render_inline(described_class.new(name: "title", required: true))
      expect(page).to have_css("input[required]")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(name: "title", data: { action: "input->test#change" }))
      expect(page).to have_css("[data-action='input->test#change']")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_input_component_spec.rb`
Expected: FAIL with "uninitialized constant FormInputComponent"

**Step 3: Write FormInputComponent Ruby class**

Create `app/components/form_input_component.rb`:

```ruby
# frozen_string_literal: true

class FormInputComponent < ApplicationComponent
  INPUT_TYPES = %i[text email password number url tel].freeze

  BASE_CLASSES = "block w-full rounded-md shadow-sm sm:text-sm"
  NORMAL_CLASSES = "border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
  ERROR_CLASSES = "border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:ring-red-500"
  LABEL_CLASSES = "block text-sm font-medium text-gray-700 mb-1"
  ERROR_MESSAGE_CLASSES = "mt-1 text-sm text-red-600"

  attr_reader :name, :type, :label, :error, :placeholder, :value, :disabled, :required, :options, :id

  def initialize(name:, type: :text, label: nil, error: nil, placeholder: nil, value: nil, disabled: false, required: false, options: [], id: nil, **html_attributes)
    @name = name
    @type = type.to_sym
    @label = label
    @error = error
    @placeholder = placeholder
    @value = value
    @disabled = disabled
    @required = required
    @options = options
    @id = id || "#{name}_input"
    @html_attributes = html_attributes
  end

  def input_classes
    state_classes = error.present? ? ERROR_CLASSES : NORMAL_CLASSES
    [BASE_CLASSES, state_classes].join(" ")
  end

  def input_tag
    case type
    when :textarea then :textarea
    when :select then :select
    else :input
    end
  end

  def input_type_attribute
    INPUT_TYPES.include?(type) ? type : :text
  end

  def input_attributes
    base = {
      class: input_classes,
      name: name,
      id: id,
      placeholder: placeholder,
      disabled: disabled,
      required: required
    }

    case input_tag
    when :input
      base[:type] = input_type_attribute
      base[:value] = value
    when :textarea
      base[:rows] = @html_attributes.fetch(:rows, 3)
    end

    merge_html_attributes(base, @html_attributes).compact
  end

  def render_input?
    INPUT_TYPES.include?(type)
  end

  def render_textarea?
    type == :textarea
  end

  def render_select?
    type == :select
  end
end
```

**Step 4: Write FormInputComponent template**

Create `app/components/form_input_component.html.erb`:

```erb
<div>
  <% if label.present? %>
    <label for="<%= id %>" class="<%= LABEL_CLASSES %>"><%= label %></label>
  <% end %>

  <% if render_input? %>
    <input <%= tag.attributes(input_attributes) %>>
  <% elsif render_textarea? %>
    <textarea <%= tag.attributes(input_attributes) %>><%= value %></textarea>
  <% elsif render_select? %>
    <select <%= tag.attributes(input_attributes) %>>
      <% options.each do |option| %>
        <% option_label, option_value = option.is_a?(Array) ? option : [option, option] %>
        <option value="<%= option_value %>" <%= "selected" if option_value.to_s == value.to_s %>><%= option_label %></option>
      <% end %>
    </select>
  <% end %>

  <% if error.present? %>
    <p class="<%= ERROR_MESSAGE_CLASSES %>"><%= error %></p>
  <% end %>
</div>
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/form_input_component_spec.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/form_input_component.rb app/components/form_input_component.html.erb spec/components/form_input_component_spec.rb
git commit -m "feat(components): add FormInputComponent with types and error states"
```

---

## Task 6: Create ModalComponent

**Files:**
- Create: `app/components/modal_component.rb`
- Create: `app/components/modal_component.html.erb`
- Create: `spec/components/modal_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/modal_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModalComponent, type: :component do
  describe "#initialize" do
    it "sets default size to md" do
      component = described_class.new
      expect(component.size).to eq(:md)
    end

    it "accepts custom size" do
      component = described_class.new(size: :lg)
      expect(component.size).to eq(:lg)
    end
  end

  describe "size styling" do
    {
      sm: "max-w-md",
      md: "max-w-lg",
      lg: "max-w-2xl",
      xl: "max-w-4xl",
      full: "max-w-full"
    }.each do |size, expected_class|
      it "returns #{expected_class} for #{size} size" do
        component = described_class.new(size: size)
        expect(component.size_classes).to include(expected_class)
      end
    end
  end

  describe "slots" do
    it "renders header slot" do
      render_inline(described_class.new) do |modal|
        modal.with_header { "Modal Title" }
        modal.with_body { "Content" }
      end
      expect(page).to have_text("Modal Title")
    end

    it "renders body slot" do
      render_inline(described_class.new) do |modal|
        modal.with_body { "Body content here" }
      end
      expect(page).to have_text("Body content here")
    end

    it "renders footer slot" do
      render_inline(described_class.new) do |modal|
        modal.with_body { "Content" }
        modal.with_footer { "Footer content" }
      end
      expect(page).to have_text("Footer content")
    end
  end

  describe "rendering" do
    it "renders overlay backdrop" do
      render_inline(described_class.new) do |modal|
        modal.with_body { "Content" }
      end
      expect(page).to have_css(".bg-gray-500.bg-opacity-75")
    end

    it "renders modal panel with correct size" do
      render_inline(described_class.new(size: :lg)) do |modal|
        modal.with_body { "Content" }
      end
      expect(page).to have_css(".max-w-2xl")
    end

    it "renders with accessibility attributes" do
      render_inline(described_class.new) do |modal|
        modal.with_body { "Content" }
      end
      expect(page).to have_css("[role='dialog']")
      expect(page).to have_css("[aria-modal='true']")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(data: { controller: "modal" })) do |modal|
        modal.with_body { "Content" }
      end
      expect(page).to have_css("[data-controller='modal']")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/modal_component_spec.rb`
Expected: FAIL with "uninitialized constant ModalComponent"

**Step 3: Write ModalComponent Ruby class**

Create `app/components/modal_component.rb`:

```ruby
# frozen_string_literal: true

class ModalComponent < ApplicationComponent
  SIZES = {
    sm: "max-w-md",
    md: "max-w-lg",
    lg: "max-w-2xl",
    xl: "max-w-4xl",
    full: "max-w-full mx-4"
  }.freeze

  renders_one :header
  renders_one :body
  renders_one :footer

  attr_reader :size

  def initialize(size: :md, **html_attributes)
    @size = size.to_sym
    @html_attributes = html_attributes
  end

  def size_classes
    SIZES.fetch(size, SIZES[:md])
  end

  def panel_classes
    [
      "relative inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl",
      "transform transition-all sm:my-8 sm:align-middle sm:w-full",
      size_classes,
      "sm:p-6"
    ].join(" ")
  end

  def html_attributes
    base = {
      class: "fixed inset-0 z-50 overflow-y-auto",
      role: "dialog",
      "aria-modal": "true"
    }
    merge_html_attributes(base, @html_attributes)
  end
end
```

**Step 4: Write ModalComponent template**

Create `app/components/modal_component.html.erb`:

```erb
<div <%= tag.attributes(html_attributes) %>>
  <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
    <%# Overlay backdrop %>
    <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" aria-hidden="true"></div>

    <%# Modal positioning trick %>
    <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">&#8203;</span>

    <%# Modal panel %>
    <div class="<%= panel_classes %>" data-modal-content>
      <% if header? %>
        <div class="mb-4">
          <%= header %>
        </div>
      <% end %>

      <% if body? %>
        <div>
          <%= body %>
        </div>
      <% end %>

      <% if footer? %>
        <div class="mt-6 pt-4 border-t border-gray-200">
          <%= footer %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/modal_component_spec.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/modal_component.rb app/components/modal_component.html.erb spec/components/modal_component_spec.rb
git commit -m "feat(components): add ModalComponent with slots and sizes"
```

---

## Task 7: Update FlowchartInfoCardComponent to use BadgeComponent

**Files:**
- Modify: `app/components/flowchart_info_card_component.rb`
- Modify: `app/components/flowchart_info_card_component.html.erb`

**Step 1: Read current template**

Run: `cat app/components/flowchart_info_card_component.html.erb`

**Step 2: Update Ruby class**

In `app/components/flowchart_info_card_component.rb`, replace `type_badge_class` method:

```ruby
def type_badge_variant
  flowchart.custom? ? :info : :purple
end
```

**Step 3: Update template to use BadgeComponent**

Replace the badge section in `app/components/flowchart_info_card_component.html.erb` from:
```erb
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium <%= type_badge_class %>">
```

To:
```erb
<%= render BadgeComponent.new(variant: type_badge_variant, size: :sm) do %>
```

**Step 4: Run existing tests**

Run: `bundle exec rspec spec/components/flowchart_info_card_component_spec.rb` (if exists)
Expected: PASS (or skip if no existing tests)

**Step 5: Commit**

```bash
git add app/components/flowchart_info_card_component.rb app/components/flowchart_info_card_component.html.erb
git commit -m "refactor(components): use BadgeComponent in FlowchartInfoCardComponent"
```

---

## Task 8: Update FlowchartListTableComponent to use BadgeComponent

**Files:**
- Modify: `app/components/flowchart_list_table_component.rb`
- Modify: `app/components/flowchart_list_table_component.html.erb`

**Step 1: Read current template**

Run: `cat app/components/flowchart_list_table_component.html.erb`

**Step 2: Add badge variant method to Ruby class**

Add to `app/components/flowchart_list_table_component.rb`:

```ruby
def type_badge_variant(flowchart)
  flowchart.custom? ? :info : :purple
end
```

**Step 3: Update template to use BadgeComponent**

Replace inline badge styling with:
```erb
<%= render BadgeComponent.new(variant: type_badge_variant(flowchart), size: :sm) do %>
  <%= flowchart.custom? ? "Custom" : "System" %>
<% end %>
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/components/flowchart_list_table_component_spec.rb` (if exists)
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/flowchart_list_table_component.rb app/components/flowchart_list_table_component.html.erb
git commit -m "refactor(components): use BadgeComponent in FlowchartListTableComponent"
```

---

## Task 9: Update flowcharts/index.html.erb to use ButtonComponent

**Files:**
- Modify: `app/views/flowcharts/index.html.erb`

**Step 1: Read current view**

Run: `cat app/views/flowcharts/index.html.erb`

**Step 2: Replace inline button styling**

Replace the Trash button (lines 6-11):
```erb
<%= render ButtonComponent.new(tag: :a, href: trash_flowcharts_path, variant: :secondary) do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
    <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
  </svg>
  Trash
<% end %>
```

Replace the New Flowchart button (lines 13-18):
```erb
<%= render ButtonComponent.new(tag: :a, href: new_flowchart_path, variant: :primary) do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
  </svg>
  New Flowchart
<% end %>
```

**Step 3: Verify view renders**

Run: `bin/rails runner "ApplicationController.renderer.render(template: 'flowcharts/index', assigns: { flowcharts: Flowchart.limit(1) })"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/flowcharts/index.html.erb
git commit -m "refactor(views): use ButtonComponent in flowcharts index"
```

---

## Task 10: Update entities/index.html.erb to use ButtonComponent

**Files:**
- Modify: `app/views/entities/index.html.erb`

**Step 1: Read current view**

Run: `cat app/views/entities/index.html.erb`

**Step 2: Replace inline button styling with ButtonComponent**

Follow same pattern as Task 9.

**Step 3: Verify view renders**

Run: `bin/rails runner "ApplicationController.renderer.render(template: 'entities/index', assigns: { entities: Entity.limit(1) })"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/entities/index.html.erb
git commit -m "refactor(views): use ButtonComponent in entities index"
```

---

## Task 11: Update ActivityTraceComponent with custom-scrollbar class

**Files:**
- Modify: `app/components/activity_trace_component.html.erb`

**Step 1: Read current template**

Run: `cat app/components/activity_trace_component.html.erb`

**Step 2: Add custom-scrollbar class to scrollable areas**

Add `custom-scrollbar` class to any element with `overflow-y-auto` or `overflow-auto`.

**Step 3: Commit**

```bash
git add app/components/activity_trace_component.html.erb
git commit -m "refactor(components): use custom-scrollbar utility in ActivityTraceComponent"
```

---

## Task 12: Run full test suite and verify

**Step 1: Run all component tests**

Run: `bundle exec rspec spec/components/`
Expected: All tests PASS

**Step 2: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests PASS

**Step 3: Start server and verify visually**

Run: `bin/rails server -b 0.0.0.0`
Verify: Check flowcharts index, entities index, flowchart editor pages render correctly

**Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address any issues found during verification"
```

---

## Summary

This plan creates 5 new reusable ViewComponents:
- `ButtonComponent` - primary, secondary, danger, ghost variants
- `BadgeComponent` - 7 color variants
- `CardComponent` - shadow, bordered, flat variants
- `FormInputComponent` - text, email, password, textarea, select types
- `ModalComponent` - sm, md, lg, xl, full sizes with slots

CSS cleanup:
- Removed duplicate scrollbar styles
- Added `.custom-scrollbar` utility class

Refactored existing code:
- `FlowchartInfoCardComponent` → uses BadgeComponent
- `FlowchartListTableComponent` → uses BadgeComponent
- `flowcharts/index.html.erb` → uses ButtonComponent
- `entities/index.html.erb` → uses ButtonComponent
- `ActivityTraceComponent` → uses custom-scrollbar class

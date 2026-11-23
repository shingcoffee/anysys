# Page Builder Refactor Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the page builder with floating property panel, conditional logic, calculations, multi-page wizard forms, and entity/flows integration following JotForm patterns.

**Architecture:** Component-first approach building styling foundation first, then ViewComponents, then Stimulus controller updates. All generated output uses ViewComponents with inline TailwindCSS for style isolation.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec

---

## Phase 1: Styling Foundation

### Task 1: Create Design Tokens Module

**Files:**
- Create: `app/components/concerns/design_tokens.rb`
- Test: `spec/components/concerns/design_tokens_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/concerns/design_tokens_spec.rb
require "rails_helper"

RSpec.describe DesignTokens do
  describe "color tokens" do
    it "defines PRIMARY color" do
      expect(DesignTokens::PRIMARY).to eq("indigo-600")
    end

    it "defines PRIMARY_HOVER color" do
      expect(DesignTokens::PRIMARY_HOVER).to eq("indigo-700")
    end

    it "defines SECONDARY color" do
      expect(DesignTokens::SECONDARY).to eq("gray-600")
    end

    it "defines BORDER color" do
      expect(DesignTokens::BORDER).to eq("gray-200")
    end
  end

  describe "spacing tokens" do
    it "defines spacing scale" do
      expect(DesignTokens::SPACING_SM).to eq("2")
      expect(DesignTokens::SPACING_MD).to eq("4")
      expect(DesignTokens::SPACING_LG).to eq("6")
    end
  end

  describe "border radius tokens" do
    it "defines radius scale" do
      expect(DesignTokens::ROUNDED_SM).to eq("rounded")
      expect(DesignTokens::ROUNDED_MD).to eq("rounded-lg")
      expect(DesignTokens::ROUNDED_LG).to eq("rounded-xl")
    end
  end

  describe "shadow tokens" do
    it "defines shadow scale" do
      expect(DesignTokens::SHADOW_SM).to eq("shadow-sm")
      expect(DesignTokens::SHADOW_MD).to eq("shadow-md")
      expect(DesignTokens::SHADOW_LG).to eq("shadow-lg")
    end
  end

  describe "transition tokens" do
    it "defines transition classes" do
      expect(DesignTokens::TRANSITION_DEFAULT).to include("transition-all")
      expect(DesignTokens::TRANSITION_FAST).to include("duration-150")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/concerns/design_tokens_spec.rb -v`
Expected: FAIL with "uninitialized constant DesignTokens"

**Step 3: Write minimal implementation**

```ruby
# app/components/concerns/design_tokens.rb
# frozen_string_literal: true

module DesignTokens
  # Colors
  PRIMARY = "indigo-600"
  PRIMARY_HOVER = "indigo-700"
  SECONDARY = "gray-600"
  BORDER = "gray-200"
  SUCCESS = "green-600"
  WARNING = "yellow-600"
  ERROR = "red-600"

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
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/concerns/design_tokens_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/concerns/design_tokens.rb spec/components/concerns/design_tokens_spec.rb
git commit -m "feat: add design tokens module for consistent styling"
```

---

### Task 2: Create Component Classes Module

**Files:**
- Create: `app/components/concerns/component_classes.rb`
- Test: `spec/components/concerns/component_classes_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/concerns/component_classes_spec.rb
require "rails_helper"

RSpec.describe ComponentClasses do
  describe "button classes" do
    it "defines BTN_PRIMARY with required styles" do
      classes = ComponentClasses::BTN_PRIMARY
      expect(classes).to include("bg-indigo-600")
      expect(classes).to include("text-white")
      expect(classes).to include("rounded-lg")
      expect(classes).to include("hover:bg-indigo-700")
    end

    it "defines BTN_SECONDARY with required styles" do
      classes = ComponentClasses::BTN_SECONDARY
      expect(classes).to include("bg-white")
      expect(classes).to include("border")
      expect(classes).to include("border-gray-300")
    end
  end

  describe "card classes" do
    it "defines CARD with required styles" do
      classes = ComponentClasses::CARD
      expect(classes).to include("bg-white")
      expect(classes).to include("border")
      expect(classes).to include("rounded-lg")
    end

    it "defines CARD_HOVER with hover effects" do
      classes = ComponentClasses::CARD_HOVER
      expect(classes).to include("hover:border-indigo-300")
      expect(classes).to include("hover:shadow-md")
    end
  end

  describe "input classes" do
    it "defines INPUT with required styles" do
      classes = ComponentClasses::INPUT
      expect(classes).to include("border")
      expect(classes).to include("rounded-lg")
      expect(classes).to include("focus:ring-2")
    end
  end

  describe "floating panel classes" do
    it "defines FLOATING_PANEL with required styles" do
      classes = ComponentClasses::FLOATING_PANEL
      expect(classes).to include("absolute")
      expect(classes).to include("bg-white")
      expect(classes).to include("shadow-xl")
      expect(classes).to include("z-50")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/concerns/component_classes_spec.rb -v`
Expected: FAIL with "uninitialized constant ComponentClasses"

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

  # Cards
  CARD = "bg-white border border-gray-200 rounded-lg shadow-sm"

  CARD_HOVER = "bg-white border border-gray-200 rounded-lg shadow-sm " \
               "hover:border-indigo-300 hover:shadow-md transition-all duration-200 cursor-pointer"

  CARD_SELECTED = "bg-indigo-50 border-2 border-indigo-500 rounded-lg shadow-sm"

  # Inputs
  INPUT = "w-full px-3 py-2 border border-gray-300 rounded-lg " \
          "focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 " \
          "transition-all duration-150 placeholder-gray-400"

  INPUT_ERROR = "w-full px-3 py-2 border border-red-300 rounded-lg " \
                "focus:ring-2 focus:ring-red-500 focus:border-red-500 " \
                "transition-all duration-150 bg-red-50"

  # Floating panel
  FLOATING_PANEL = "absolute bg-white border border-gray-200 rounded-xl shadow-xl " \
                   "p-4 z-50 min-w-80 animate-fade-in"

  # Labels
  LABEL = "block text-sm font-medium text-gray-700 mb-1"

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
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/concerns/component_classes_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/concerns/component_classes.rb spec/components/concerns/component_classes_spec.rb
git commit -m "feat: add component classes module for reusable Tailwind patterns"
```

---

### Task 3: Add Animation Utilities to Tailwind CSS

**Files:**
- Modify: `app/assets/stylesheets/application.tailwind.css`

**Step 1: Read current file**

Run: Read `app/assets/stylesheets/application.tailwind.css` to understand current structure

**Step 2: Add animation utilities**

Add the following after existing content:

```css
@layer utilities {
  /* Fade animations */
  .animate-fade-in {
    animation: fadeIn 0.2s ease-out forwards;
  }

  .animate-fade-out {
    animation: fadeOut 0.2s ease-out forwards;
  }

  /* Slide animations */
  .animate-slide-up {
    animation: slideUp 0.2s ease-out forwards;
  }

  .animate-slide-down {
    animation: slideDown 0.2s ease-out forwards;
  }

  /* Scale animations */
  .animate-scale-in {
    animation: scaleIn 0.15s ease-out forwards;
  }

  .animate-scale-out {
    animation: scaleOut 0.15s ease-out forwards;
  }

  /* Bounce animation for drop indicator */
  .animate-bounce-subtle {
    animation: bounceSubtle 0.3s ease-in-out;
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes fadeOut {
    from { opacity: 1; }
    to { opacity: 0; }
  }

  @keyframes slideUp {
    from { opacity: 0; transform: translateY(0.5rem); }
    to { opacity: 1; transform: translateY(0); }
  }

  @keyframes slideDown {
    from { opacity: 0; transform: translateY(-0.5rem); }
    to { opacity: 1; transform: translateY(0); }
  }

  @keyframes scaleIn {
    from { opacity: 0; transform: scale(0.95); }
    to { opacity: 1; transform: scale(1); }
  }

  @keyframes scaleOut {
    from { opacity: 1; transform: scale(1); }
    to { opacity: 0; transform: scale(0.95); }
  }

  @keyframes bounceSubtle {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-4px); }
  }
}
```

**Step 3: Verify CSS compiles**

Run: `bin/rails tailwindcss:build`
Expected: Build completes without errors

**Step 4: Commit**

```bash
git add app/assets/stylesheets/application.tailwind.css
git commit -m "feat: add animation utility classes for smooth transitions"
```

---

## Phase 2: Form Fields Components (Generated Output)

### Task 4: Create FormFields::PageComponent

**Files:**
- Create: `app/components/form_fields/page_component.rb`
- Create: `app/components/form_fields/page_component.html.erb`
- Test: `spec/components/form_fields/page_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/page_component_spec.rb
require "rails_helper"

RSpec.describe FormFields::PageComponent, type: :component do
  let(:page) { create(:page, name: "Test Page") }

  it "renders with content block" do
    render_inline(described_class.new(page: page)) do
      "Test content"
    end

    expect(page).to have_text("Test content")
  end

  it "applies wrapper classes with inline Tailwind" do
    render_inline(described_class.new(page: page)) do
      "Content"
    end

    expect(page).to have_css("div.max-w-4xl")
    expect(page).to have_css("div.mx-auto")
    expect(page).to have_css("div.p-6")
  end

  it "displays page title when show_title is true" do
    render_inline(described_class.new(page: page, show_title: true)) do
      "Content"
    end

    expect(page).to have_text("Test Page")
  end

  it "hides page title when show_title is false" do
    render_inline(described_class.new(page: page, show_title: false)) do
      "Content"
    end

    expect(page).not_to have_text("Test Page")
  end

  it "accepts custom css_class" do
    render_inline(described_class.new(page: page, css_class: "custom-class")) do
      "Content"
    end

    expect(page).to have_css("div.custom-class")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/page_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::PageComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/page_component.rb
# frozen_string_literal: true

module FormFields
  class PageComponent < ApplicationComponent
    include DesignTokens

    def initialize(page:, show_title: false, show_description: false, css_class: nil)
      @page = page
      @show_title = show_title
      @show_description = show_description
      @css_class = css_class
    end

    private

    attr_reader :page, :show_title, :show_description, :css_class

    def wrapper_classes
      [
        "max-w-4xl mx-auto p-6 bg-white",
        css_class
      ].compact.join(" ")
    end

    def title
      page.name
    end

    def description
      page.description
    end

    def settings
      page.configuration.dig("settings") || {}
    end
  end
end
```

```erb
<%# app/components/form_fields/page_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <% if show_title && title.present? %>
    <h1 class="text-2xl font-bold text-gray-900 mb-2"><%= title %></h1>
  <% end %>

  <% if show_description && description.present? %>
    <p class="text-gray-600 mb-6"><%= description %></p>
  <% end %>

  <%= content %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/page_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/page_component.rb app/components/form_fields/page_component.html.erb spec/components/form_fields/page_component_spec.rb
git commit -m "feat: add FormFields::PageComponent for generated page wrapper"
```

---

### Task 5: Create FormFields::FormComponent

**Files:**
- Create: `app/components/form_fields/form_component.rb`
- Create: `app/components/form_fields/form_component.html.erb`
- Test: `spec/components/form_fields/form_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/form_component_spec.rb
require "rails_helper"

RSpec.describe FormFields::FormComponent, type: :component do
  it "renders form tag with content" do
    render_inline(described_class.new(action: "/submit", method: :post)) do
      "<input type='text' name='field'>".html_safe
    end

    expect(page).to have_css("form[action='/submit']")
    expect(page).to have_css("form[method='post']")
    expect(page).to have_css("input[name='field']")
  end

  it "renders submit button with custom text" do
    render_inline(described_class.new(
      action: "/submit",
      submit_text: "Send Form"
    )) { "" }

    expect(page).to have_button("Send Form")
  end

  it "applies default submit text when not provided" do
    render_inline(described_class.new(action: "/submit")) { "" }

    expect(page).to have_button("Submit")
  end

  it "applies inline Tailwind classes to submit button" do
    render_inline(described_class.new(action: "/submit")) { "" }

    expect(page).to have_css("button.bg-indigo-600")
    expect(page).to have_css("button.text-white")
    expect(page).to have_css("button.rounded-lg")
  end

  it "renders CSRF token field" do
    render_inline(described_class.new(action: "/submit")) { "" }

    expect(page).to have_css("input[name='authenticity_token']", visible: :hidden)
  end

  it "accepts custom css_class for form wrapper" do
    render_inline(described_class.new(action: "/submit", css_class: "space-y-6")) { "" }

    expect(page).to have_css("form.space-y-6")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/form_component_spec.rb -v`
Expected: FAIL with "uninitialized constant FormFields::FormComponent"

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/form_component.rb
# frozen_string_literal: true

module FormFields
  class FormComponent < ApplicationComponent
    include ComponentClasses

    def initialize(action: nil, method: :post, submit_text: "Submit", css_class: nil, data: {})
      @action = action
      @method = method
      @submit_text = submit_text
      @css_class = css_class
      @data = data
    end

    private

    attr_reader :action, :method, :submit_text, :css_class, :data

    def form_classes
      ["space-y-6", css_class].compact.join(" ")
    end

    def submit_button_classes
      BTN_PRIMARY + " w-full mt-6"
    end

    def form_method
      method == :get ? :get : :post
    end

    def hidden_method_field?
      %i[put patch delete].include?(method)
    end
  end
end
```

```erb
<%# app/components/form_fields/form_component.html.erb %>
<form
  action="<%= action %>"
  method="<%= form_method %>"
  class="<%= form_classes %>"
  <% data.each do |key, value| %>
    data-<%= key.to_s.dasherize %>="<%= value %>"
  <% end %>
>
  <%= hidden_field_tag :authenticity_token, form_authenticity_token %>

  <% if hidden_method_field? %>
    <%= hidden_field_tag :_method, method %>
  <% end %>

  <div class="space-y-4">
    <%= content %>
  </div>

  <button type="submit" class="<%= submit_button_classes %>">
    <%= submit_text %>
  </button>
</form>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/form_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/form_component.rb app/components/form_fields/form_component.html.erb spec/components/form_fields/form_component_spec.rb
git commit -m "feat: add FormFields::FormComponent for generated form wrapper"
```

---

### Task 6: Create FormFields::WizardComponent

**Files:**
- Create: `app/components/form_fields/wizard_component.rb`
- Create: `app/components/form_fields/wizard_component.html.erb`
- Test: `spec/components/form_fields/wizard_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/wizard_component_spec.rb
require "rails_helper"

RSpec.describe FormFields::WizardComponent, type: :component do
  let(:pages_config) do
    [
      { "id" => "page_1", "name" => "Step 1", "fields" => [] },
      { "id" => "page_2", "name" => "Step 2", "fields" => [] }
    ]
  end

  it "renders wizard container" do
    render_inline(described_class.new(pages: pages_config, action: "/submit")) { "" }

    expect(page).to have_css("[data-controller='wizard']")
  end

  it "renders progress indicator when show_progress is true" do
    render_inline(described_class.new(
      pages: pages_config,
      action: "/submit",
      show_progress: true
    )) { "" }

    expect(page).to have_text("Step 1 of 2")
  end

  it "hides progress indicator when show_progress is false" do
    render_inline(described_class.new(
      pages: pages_config,
      action: "/submit",
      show_progress: false
    )) { "" }

    expect(page).not_to have_text("Step 1 of 2")
  end

  it "renders previous and next buttons" do
    render_inline(described_class.new(pages: pages_config, action: "/submit")) { "" }

    expect(page).to have_button("Previous")
    expect(page).to have_button("Next")
  end

  it "renders submit button on last step" do
    render_inline(described_class.new(
      pages: pages_config,
      action: "/submit",
      submit_text: "Finish"
    )) { "" }

    expect(page).to have_button("Finish")
  end

  it "uses slots for step content" do
    component = described_class.new(pages: pages_config, action: "/submit")
    render_inline(component) do |wizard|
      wizard.with_step(id: "page_1") { "Step 1 content" }
      wizard.with_step(id: "page_2") { "Step 2 content" }
    end

    expect(page).to have_text("Step 1 content")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/wizard_component_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/wizard_component.rb
# frozen_string_literal: true

module FormFields
  class WizardComponent < ApplicationComponent
    include ComponentClasses

    renders_many :steps, "StepComponent"

    def initialize(pages:, action:, method: :post, show_progress: true,
                   allow_back: true, validate_on_next: true, submit_text: "Submit")
      @pages = pages
      @action = action
      @method = method
      @show_progress = show_progress
      @allow_back = allow_back
      @validate_on_next = validate_on_next
      @submit_text = submit_text
    end

    private

    attr_reader :pages, :action, :method, :show_progress, :allow_back,
                :validate_on_next, :submit_text

    def total_steps
      pages.length
    end

    def wizard_data
      {
        controller: "wizard",
        wizard_total_steps_value: total_steps,
        wizard_current_step_value: 1,
        wizard_validate_on_next_value: validate_on_next
      }
    end

    class StepComponent < ApplicationComponent
      def initialize(id:)
        @id = id
      end

      attr_reader :id

      def call
        content_tag :div,
                    content,
                    class: "wizard-step",
                    data: { wizard_target: "step", step_id: id }
      end
    end
  end
end
```

```erb
<%# app/components/form_fields/wizard_component.html.erb %>
<div
  class="wizard-container"
  <% wizard_data.each do |key, value| %>
    data-<%= key.to_s.dasherize %>="<%= value %>"
  <% end %>
>
  <% if show_progress %>
    <div class="mb-6">
      <div class="flex items-center justify-between text-sm text-gray-500 mb-2">
        <span data-wizard-target="progressText">Step 1 of <%= total_steps %></span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2">
        <div
          class="bg-indigo-600 h-2 rounded-full transition-all duration-300"
          data-wizard-target="progressBar"
          style="width: <%= 100 / total_steps %>%"
        ></div>
      </div>
    </div>
  <% end %>

  <form action="<%= action %>" method="<%= method == :get ? :get : :post %>" data-wizard-target="form">
    <%= hidden_field_tag :authenticity_token, form_authenticity_token %>

    <div data-wizard-target="stepsContainer">
      <% steps.each do |step| %>
        <%= step %>
      <% end %>
    </div>

    <div class="flex justify-between mt-8 pt-6 border-t border-gray-200">
      <% if allow_back %>
        <button
          type="button"
          class="<%= BTN_SECONDARY %>"
          data-action="wizard#previous"
          data-wizard-target="prevButton"
        >
          Previous
        </button>
      <% else %>
        <div></div>
      <% end %>

      <div class="flex gap-3">
        <button
          type="button"
          class="<%= BTN_PRIMARY %>"
          data-action="wizard#next"
          data-wizard-target="nextButton"
        >
          Next
        </button>

        <button
          type="submit"
          class="<%= BTN_PRIMARY %> hidden"
          data-wizard-target="submitButton"
        >
          <%= submit_text %>
        </button>
      </div>
    </div>
  </form>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/wizard_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/wizard_component.rb app/components/form_fields/wizard_component.html.erb spec/components/form_fields/wizard_component_spec.rb
git commit -m "feat: add FormFields::WizardComponent for multi-page forms"
```

---

### Task 7: Create FormFields::CalculatedFieldComponent

**Files:**
- Create: `app/components/form_fields/calculated_field_component.rb`
- Create: `app/components/form_fields/calculated_field_component.html.erb`
- Test: `spec/components/form_fields/calculated_field_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/form_fields/calculated_field_component_spec.rb
require "rails_helper"

RSpec.describe FormFields::CalculatedFieldComponent, type: :component do
  it "renders read-only display field" do
    render_inline(described_class.new(
      field_name: "total",
      label: "Total",
      formula: "SUM(price, tax)"
    ))

    expect(page).to have_css("[data-field-name='total']")
    expect(page).to have_text("Total")
  end

  it "stores formula in data attribute" do
    render_inline(described_class.new(
      field_name: "total",
      label: "Total",
      formula: "SUM(price, tax)"
    ))

    expect(page).to have_css("[data-formula='SUM(price, tax)']")
  end

  it "applies format when provided" do
    render_inline(described_class.new(
      field_name: "total",
      label: "Total",
      formula: "SUM(price, tax)",
      format: "currency"
    ))

    expect(page).to have_css("[data-format='currency']")
  end

  it "renders with inline Tailwind styles" do
    render_inline(described_class.new(
      field_name: "total",
      label: "Total",
      formula: "SUM(a, b)"
    ))

    expect(page).to have_css("div.bg-gray-50")
    expect(page).to have_css("div.rounded-lg")
  end

  it "displays placeholder value initially" do
    render_inline(described_class.new(
      field_name: "total",
      label: "Total",
      formula: "SUM(a, b)",
      placeholder: "0.00"
    ))

    expect(page).to have_text("0.00")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/form_fields/calculated_field_component_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/components/form_fields/calculated_field_component.rb
# frozen_string_literal: true

module FormFields
  class CalculatedFieldComponent < BaseFieldComponent
    def initialize(field_name:, label:, formula:, format: nil, placeholder: "-",
                   help_text: nil, width: "full", css_class: nil)
      super(field_name: field_name, label: label, required: false,
            placeholder: placeholder, help_text: help_text, width: width, css_class: css_class)
      @formula = formula
      @format = format
    end

    private

    attr_reader :formula, :format

    def data_attributes
      attrs = super.merge(
        field_name: field_name,
        formula: formula,
        calculated_field_target: "display"
      )
      attrs[:format] = format if format
      attrs
    end

    def display_classes
      "w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg " \
      "text-gray-900 font-medium"
    end
  end
end
```

```erb
<%# app/components/form_fields/calculated_field_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <%= render partial: "form_fields/label", locals: { label: label, field_name: field_name, required: false } %>

  <div
    class="<%= display_classes %>"
    <% data_attributes.each do |key, value| %>
      data-<%= key.to_s.dasherize %>="<%= value %>"
    <% end %>
  >
    <%= placeholder %>
  </div>

  <% if help_text.present? %>
    <p class="mt-1 text-sm text-gray-500"><%= help_text %></p>
  <% end %>

  <input type="hidden" name="<%= field_name %>" data-calculated-field-target="value">
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/form_fields/calculated_field_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/form_fields/calculated_field_component.rb app/components/form_fields/calculated_field_component.html.erb spec/components/form_fields/calculated_field_component_spec.rb
git commit -m "feat: add FormFields::CalculatedFieldComponent for formula-based fields"
```

---

## Phase 3: Page Builder Components - Flows Section

### Task 8: Create PageBuilder::FlowItemComponent

**Files:**
- Create: `app/components/page_builder/flow_item_component.rb`
- Create: `app/components/page_builder/flow_item_component.html.erb`
- Test: `spec/components/page_builder/flow_item_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/flow_item_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FlowItemComponent, type: :component do
  let(:flowchart) { create(:flowchart, name: "Test Flow", flowchart_type: :custom) }

  it "renders flow name" do
    render_inline(described_class.new(flowchart: flowchart))

    expect(page).to have_text("Test Flow")
  end

  it "displays custom badge for custom flowcharts" do
    render_inline(described_class.new(flowchart: flowchart))

    expect(page).to have_text("Custom")
  end

  it "displays blueprint badge for blueprint flowcharts" do
    blueprint = create(:flowchart, name: "Blueprint Flow", flowchart_type: :blueprint)
    render_inline(described_class.new(flowchart: blueprint))

    expect(page).to have_text("Blueprint")
  end

  it "has view link to flowchart" do
    render_inline(described_class.new(flowchart: flowchart))

    expect(page).to have_css("a[href*='flowcharts']")
  end

  it "applies hover styles" do
    render_inline(described_class.new(flowchart: flowchart))

    expect(page).to have_css("div.hover\\:bg-gray-50")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/flow_item_component_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/flow_item_component.rb
# frozen_string_literal: true

module PageBuilder
  class FlowItemComponent < ApplicationComponent
    include ComponentClasses

    def initialize(flowchart:, customer_id: nil)
      @flowchart = flowchart
      @customer_id = customer_id
    end

    private

    attr_reader :flowchart, :customer_id

    def name
      flowchart.name
    end

    def flowchart_type
      flowchart.flowchart_type
    end

    def blueprint?
      flowchart.blueprint?
    end

    def badge_classes
      if blueprint?
        BADGE_SECONDARY
      else
        BADGE_PRIMARY
      end
    end

    def badge_text
      blueprint? ? "Blueprint" : "Custom"
    end

    def flowchart_path
      if customer_id
        "/#{customer_id}/flowcharts/#{flowchart.id}"
      else
        "#"
      end
    end

    def wrapper_classes
      "flex items-center justify-between px-3 py-2 rounded-lg " \
      "hover:bg-gray-50 transition-colors duration-150 group"
    end
  end
end
```

```erb
<%# app/components/page_builder/flow_item_component.html.erb %>
<div class="<%= wrapper_classes %>">
  <div class="flex items-center gap-2 min-w-0">
    <svg class="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7m0 10a2 2 0 002 2h2a2 2 0 002-2V7a2 2 0 00-2-2h-2a2 2 0 00-2 2" />
    </svg>
    <span class="text-sm text-gray-700 truncate"><%= name %></span>
    <span class="<%= badge_classes %>"><%= badge_text %></span>
  </div>

  <a href="<%= flowchart_path %>"
     target="_blank"
     class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-indigo-600 transition-all duration-150"
     title="View flowchart">
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
    </svg>
  </a>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/flow_item_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/flow_item_component.rb app/components/page_builder/flow_item_component.html.erb spec/components/page_builder/flow_item_component_spec.rb
git commit -m "feat: add PageBuilder::FlowItemComponent for displaying flowchart items"
```

---

### Task 9: Create PageBuilder::FlowsSectionComponent

**Files:**
- Create: `app/components/page_builder/flows_section_component.rb`
- Create: `app/components/page_builder/flows_section_component.html.erb`
- Test: `spec/components/page_builder/flows_section_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/flows_section_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FlowsSectionComponent, type: :component do
  let(:entity) { create(:entity, name: "Contact") }
  let(:entity_flows) { create_list(:flowchart, 2, entity: entity, flowchart_type: :custom) }
  let(:blueprint_flows) { create_list(:flowchart, 2, flowchart_type: :blueprint) }

  it "renders section header" do
    render_inline(described_class.new(
      entity_flows: entity_flows,
      blueprint_flows: blueprint_flows,
      entity_name: "Contact"
    ))

    expect(page).to have_text("Flows")
  end

  it "renders entity flows subsection with entity name" do
    render_inline(described_class.new(
      entity_flows: entity_flows,
      blueprint_flows: blueprint_flows,
      entity_name: "Contact"
    ))

    expect(page).to have_text("Contact Flows")
  end

  it "renders blueprint flows subsection" do
    render_inline(described_class.new(
      entity_flows: entity_flows,
      blueprint_flows: blueprint_flows,
      entity_name: "Contact"
    ))

    expect(page).to have_text("Blueprint Flows")
  end

  it "shows empty state when no flows" do
    render_inline(described_class.new(
      entity_flows: [],
      blueprint_flows: [],
      entity_name: nil
    ))

    expect(page).to have_text("No flows available")
  end

  it "renders FlowItemComponent for each flow" do
    render_inline(described_class.new(
      entity_flows: entity_flows,
      blueprint_flows: blueprint_flows,
      entity_name: "Contact"
    ))

    expect(page).to have_css("[class*='hover:bg-gray-50']", count: 4)
  end

  it "is collapsible" do
    render_inline(described_class.new(
      entity_flows: entity_flows,
      blueprint_flows: blueprint_flows,
      entity_name: "Contact"
    ))

    expect(page).to have_css("[data-controller='collapsible']")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/flows_section_component_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/flows_section_component.rb
# frozen_string_literal: true

module PageBuilder
  class FlowsSectionComponent < ApplicationComponent
    include ComponentClasses

    def initialize(entity_flows:, blueprint_flows:, entity_name: nil, customer_id: nil, collapsed: false)
      @entity_flows = entity_flows || []
      @blueprint_flows = blueprint_flows || []
      @entity_name = entity_name
      @customer_id = customer_id
      @collapsed = collapsed
    end

    private

    attr_reader :entity_flows, :blueprint_flows, :entity_name, :customer_id, :collapsed

    def has_flows?
      entity_flows.any? || blueprint_flows.any?
    end

    def has_entity_flows?
      entity_flows.any?
    end

    def has_blueprint_flows?
      blueprint_flows.any?
    end

    def entity_section_title
      "#{entity_name} Flows"
    end

    def section_header_classes
      "flex items-center justify-between px-3 py-2 text-sm font-medium " \
      "text-gray-500 hover:bg-gray-50 rounded-lg cursor-pointer transition-colors duration-150"
    end

    def subsection_header_classes
      "flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-gray-400 uppercase tracking-wider"
    end
  end
end
```

```erb
<%# app/components/page_builder/flows_section_component.html.erb %>
<div class="border-t border-gray-200 pt-4 mt-4" data-controller="collapsible" data-collapsible-open-value="<%= !collapsed %>">
  <button
    type="button"
    class="<%= section_header_classes %> w-full"
    data-action="collapsible#toggle"
  >
    <span class="flex items-center gap-2">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7" />
      </svg>
      Flows
    </span>
    <svg class="w-4 h-4 transition-transform duration-200" data-collapsible-target="icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
    </svg>
  </button>

  <div class="mt-2 space-y-4" data-collapsible-target="content">
    <% if has_flows? %>
      <% if has_entity_flows? && entity_name.present? %>
        <div>
          <div class="<%= subsection_header_classes %>">
            <%= entity_section_title %>
            <span class="<%= BADGE_PRIMARY %>"><%= entity_flows.size %></span>
          </div>
          <div class="space-y-1">
            <% entity_flows.each do |flow| %>
              <%= render PageBuilder::FlowItemComponent.new(flowchart: flow, customer_id: customer_id) %>
            <% end %>
          </div>
        </div>
      <% end %>

      <% if has_blueprint_flows? %>
        <div>
          <div class="<%= subsection_header_classes %>">
            Blueprint Flows
            <span class="<%= BADGE_SECONDARY %>"><%= blueprint_flows.size %></span>
          </div>
          <div class="space-y-1">
            <% blueprint_flows.each do |flow| %>
              <%= render PageBuilder::FlowItemComponent.new(flowchart: flow, customer_id: customer_id) %>
            <% end %>
          </div>
        </div>
      <% end %>
    <% else %>
      <div class="px-3 py-4 text-center">
        <p class="text-sm text-gray-500">No flows available</p>
        <p class="text-xs text-gray-400 mt-1">Select an entity to see related flows</p>
      </div>
    <% end %>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/flows_section_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/flows_section_component.rb app/components/page_builder/flows_section_component.html.erb spec/components/page_builder/flows_section_component_spec.rb
git commit -m "feat: add PageBuilder::FlowsSectionComponent for entity and blueprint flows"
```

---

## Phase 4: Page Builder Components - Floating Panel

### Task 10: Create PageBuilder::FloatingPanelComponent

**Files:**
- Create: `app/components/page_builder/floating_panel_component.rb`
- Create: `app/components/page_builder/floating_panel_component.html.erb`
- Test: `spec/components/page_builder/floating_panel_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/floating_panel_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FloatingPanelComponent, type: :component do
  let(:field) do
    {
      "id" => "field_1",
      "label" => "Email",
      "property_type" => "string",
      "placeholder" => "Enter email",
      "help_text" => "",
      "required" => true,
      "width" => "full",
      "conditions" => [],
      "calculation" => nil
    }
  end

  it "renders panel container with floating styles" do
    render_inline(described_class.new(field: field))

    expect(page).to have_css("div.absolute")
    expect(page).to have_css("div.bg-white")
    expect(page).to have_css("div.shadow-xl")
    expect(page).to have_css("div.rounded-xl")
  end

  it "displays field type header" do
    render_inline(described_class.new(field: field))

    expect(page).to have_text("Text Field")
  end

  it "renders general settings section" do
    render_inline(described_class.new(field: field))

    expect(page).to have_text("General")
    expect(page).to have_field("Label")
    expect(page).to have_field("Placeholder")
  end

  it "renders layout settings section" do
    render_inline(described_class.new(field: field))

    expect(page).to have_text("Layout")
  end

  it "has close button" do
    render_inline(described_class.new(field: field))

    expect(page).to have_css("button[data-action*='close']")
  end

  it "pre-fills form with field values" do
    render_inline(described_class.new(field: field))

    expect(page).to have_field("Label", with: "Email")
    expect(page).to have_field("Placeholder", with: "Enter email")
  end

  it "renders required checkbox checked when field is required" do
    render_inline(described_class.new(field: field))

    expect(page).to have_checked_field("Required")
  end

  it "applies animation class" do
    render_inline(described_class.new(field: field))

    expect(page).to have_css("div.animate-fade-in")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/floating_panel_component_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/floating_panel_component.rb
# frozen_string_literal: true

module PageBuilder
  class FloatingPanelComponent < ApplicationComponent
    include ComponentClasses
    include DesignTokens

    FIELD_TYPE_LABELS = {
      "string" => "Text Field",
      "text" => "Textarea",
      "email" => "Email Field",
      "number" => "Number Field",
      "integer" => "Number Field",
      "boolean" => "Checkbox",
      "date" => "Date Field",
      "datetime" => "Date & Time",
      "select" => "Dropdown",
      "tel" => "Phone Field",
      "url" => "URL Field"
    }.freeze

    WIDTH_OPTIONS = [
      { value: "full", label: "Full Width" },
      { value: "half", label: "Half Width" },
      { value: "third", label: "One Third" }
    ].freeze

    def initialize(field:)
      @field = field
    end

    private

    attr_reader :field

    def field_id
      field["id"]
    end

    def field_type
      field["property_type"]
    end

    def field_type_label
      FIELD_TYPE_LABELS[field_type] || "Field"
    end

    def label
      field["label"]
    end

    def placeholder
      field["placeholder"]
    end

    def help_text
      field["help_text"]
    end

    def required?
      field["required"]
    end

    def width
      field["width"] || "full"
    end

    def conditions
      field["conditions"] || []
    end

    def calculation
      field["calculation"]
    end

    def has_conditions?
      conditions.any?
    end

    def has_calculation?
      calculation.present?
    end

    def panel_classes
      "#{FLOATING_PANEL} animate-fade-in"
    end

    def section_header_classes
      "flex items-center justify-between py-2 text-sm font-medium text-gray-700 " \
      "border-b border-gray-100 cursor-pointer"
    end
  end
end
```

```erb
<%# app/components/page_builder/floating_panel_component.html.erb %>
<div
  class="<%= panel_classes %>"
  data-page-builder-target="floatingPanel"
  data-field-id="<%= field_id %>"
>
  <%# Header %>
  <div class="flex items-center justify-between pb-3 border-b border-gray-200 mb-4">
    <div class="flex items-center gap-2">
      <span class="text-sm font-medium text-gray-900"><%= field_type_label %></span>
    </div>
    <button
      type="button"
      class="<%= BTN_ICON %> -mr-2"
      data-action="page-builder#hideFloatingPanel"
    >
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>
  </div>

  <%# General Section %>
  <div class="mb-4" data-controller="collapsible" data-collapsible-open-value="true">
    <button type="button" class="<%= section_header_classes %> w-full" data-action="collapsible#toggle">
      <span>General</span>
      <svg class="w-4 h-4 transition-transform" data-collapsible-target="icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div class="pt-3 space-y-3" data-collapsible-target="content">
      <div>
        <label class="<%= LABEL %>">Label</label>
        <input
          type="text"
          class="<%= INPUT %>"
          value="<%= label %>"
          data-action="input->page-builder#updateFieldProperty"
          data-property="label"
        >
      </div>
      <div>
        <label class="<%= LABEL %>">Placeholder</label>
        <input
          type="text"
          class="<%= INPUT %>"
          value="<%= placeholder %>"
          data-action="input->page-builder#updateFieldProperty"
          data-property="placeholder"
        >
      </div>
      <div>
        <label class="<%= LABEL %>">Help Text</label>
        <input
          type="text"
          class="<%= INPUT %>"
          value="<%= help_text %>"
          data-action="input->page-builder#updateFieldProperty"
          data-property="help_text"
        >
      </div>
      <div class="flex items-center gap-2">
        <input
          type="checkbox"
          id="required_<%= field_id %>"
          class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
          <%= "checked" if required? %>
          data-action="change->page-builder#updateFieldProperty"
          data-property="required"
        >
        <label for="required_<%= field_id %>" class="text-sm text-gray-700">Required</label>
      </div>
    </div>
  </div>

  <%# Layout Section %>
  <div class="mb-4" data-controller="collapsible" data-collapsible-open-value="true">
    <button type="button" class="<%= section_header_classes %> w-full" data-action="collapsible#toggle">
      <span>Layout</span>
      <svg class="w-4 h-4 transition-transform" data-collapsible-target="icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div class="pt-3" data-collapsible-target="content">
      <div class="flex gap-2">
        <% WIDTH_OPTIONS.each do |option| %>
          <label class="flex-1">
            <input
              type="radio"
              name="width_<%= field_id %>"
              value="<%= option[:value] %>"
              class="sr-only peer"
              <%= "checked" if width == option[:value] %>
              data-action="change->page-builder#updateFieldProperty"
              data-property="width"
            >
            <div class="px-3 py-2 text-center text-sm border border-gray-200 rounded-lg cursor-pointer
                        peer-checked:bg-indigo-50 peer-checked:border-indigo-500 peer-checked:text-indigo-700
                        hover:bg-gray-50 transition-all duration-150">
              <%= option[:label] %>
            </div>
          </label>
        <% end %>
      </div>
    </div>
  </div>

  <%# Conditions Section %>
  <div class="mb-4" data-controller="collapsible" data-collapsible-open-value="false">
    <button type="button" class="<%= section_header_classes %> w-full" data-action="collapsible#toggle">
      <span class="flex items-center gap-2">
        Conditions
        <% if has_conditions? %>
          <span class="<%= BADGE_PRIMARY %>"><%= conditions.size %></span>
        <% end %>
      </span>
      <svg class="w-4 h-4 transition-transform" data-collapsible-target="icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div class="pt-3 hidden" data-collapsible-target="content">
      <div data-page-builder-target="conditionsContainer">
        <%# Conditions will be rendered dynamically %>
      </div>
      <button
        type="button"
        class="<%= BTN_SECONDARY %> w-full mt-2 text-sm"
        data-action="page-builder#addCondition"
      >
        + Add Condition
      </button>
    </div>
  </div>

  <%# Delete button %>
  <div class="pt-3 border-t border-gray-200">
    <button
      type="button"
      class="w-full px-4 py-2 text-sm text-red-600 hover:bg-red-50 rounded-lg transition-colors duration-150"
      data-action="page-builder#deleteSelectedField"
    >
      Delete Field
    </button>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/floating_panel_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/floating_panel_component.rb app/components/page_builder/floating_panel_component.html.erb spec/components/page_builder/floating_panel_component_spec.rb
git commit -m "feat: add PageBuilder::FloatingPanelComponent for field property editing"
```

---

## Phase 5: Page Builder Components - Multi-Page

### Task 11: Create PageBuilder::PageTabsComponent

**Files:**
- Create: `app/components/page_builder/page_tabs_component.rb`
- Create: `app/components/page_builder/page_tabs_component.html.erb`
- Test: `spec/components/page_builder/page_tabs_component_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/components/page_builder/page_tabs_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::PageTabsComponent, type: :component do
  let(:pages) do
    [
      { "id" => "page_1", "name" => "Page 1", "order" => 1 },
      { "id" => "page_2", "name" => "Page 2", "order" => 2 }
    ]
  end

  it "renders tab for each page" do
    render_inline(described_class.new(pages: pages, active_page_id: "page_1"))

    expect(page).to have_text("Page 1")
    expect(page).to have_text("Page 2")
  end

  it "highlights active tab" do
    render_inline(described_class.new(pages: pages, active_page_id: "page_1"))

    expect(page).to have_css("[data-page-id='page_1'].border-indigo-500")
  end

  it "renders add page button" do
    render_inline(described_class.new(pages: pages, active_page_id: "page_1"))

    expect(page).to have_css("button[data-action*='addPage']")
  end

  it "tabs are clickable to switch pages" do
    render_inline(described_class.new(pages: pages, active_page_id: "page_1"))

    expect(page).to have_css("button[data-action*='switchPage']", count: 2)
  end

  it "renders empty state when no pages" do
    render_inline(described_class.new(pages: [], active_page_id: nil))

    expect(page).to have_css("button[data-action*='addPage']")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/page_tabs_component_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/components/page_builder/page_tabs_component.rb
# frozen_string_literal: true

module PageBuilder
  class PageTabsComponent < ApplicationComponent
    include ComponentClasses

    def initialize(pages:, active_page_id:)
      @pages = pages || []
      @active_page_id = active_page_id
    end

    private

    attr_reader :pages, :active_page_id

    def sorted_pages
      pages.sort_by { |p| p["order"] || 0 }
    end

    def active?(page_data)
      page_data["id"] == active_page_id
    end

    def tab_classes(page_data)
      base = "px-4 py-2 text-sm font-medium border-b-2 transition-all duration-150 " \
             "hover:text-indigo-600 focus:outline-none"

      if active?(page_data)
        "#{base} text-indigo-600 border-indigo-500"
      else
        "#{base} text-gray-500 border-transparent hover:border-gray-300"
      end
    end

    def add_button_classes
      "px-3 py-2 text-sm text-gray-400 hover:text-indigo-600 " \
      "border-b-2 border-transparent hover:border-gray-300 transition-all duration-150"
    end
  end
end
```

```erb
<%# app/components/page_builder/page_tabs_component.html.erb %>
<div class="flex items-center border-b border-gray-200 bg-white px-4" data-page-builder-target="pageTabs">
  <div class="flex items-center gap-1 overflow-x-auto">
    <% sorted_pages.each do |page_data| %>
      <button
        type="button"
        class="<%= tab_classes(page_data) %>"
        data-action="page-builder#switchPage"
        data-page-id="<%= page_data['id'] %>"
      >
        <span class="flex items-center gap-2">
          <%= page_data['name'] %>
          <% if sorted_pages.size > 1 %>
            <span
              class="opacity-0 hover:opacity-100 text-gray-400 hover:text-red-500 transition-opacity"
              data-action="click->page-builder#deletePage:stop"
              data-page-id="<%= page_data['id'] %>"
            >
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </span>
          <% end %>
        </span>
      </button>
    <% end %>
  </div>

  <button
    type="button"
    class="<%= add_button_classes %>"
    data-action="page-builder#addPage"
    title="Add page"
  >
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
    </svg>
  </button>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/page_tabs_component_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/page_tabs_component.rb app/components/page_builder/page_tabs_component.html.erb spec/components/page_builder/page_tabs_component_spec.rb
git commit -m "feat: add PageBuilder::PageTabsComponent for multi-page navigation"
```

---

## Phase 6: Services

### Task 12: Create ConditionEvaluator Service

**Files:**
- Create: `app/services/condition_evaluator.rb`
- Test: `spec/services/condition_evaluator_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/condition_evaluator_spec.rb
require "rails_helper"

RSpec.describe ConditionEvaluator do
  describe "#evaluate" do
    let(:field_values) do
      {
        "field_1" => "test",
        "field_2" => 100,
        "field_3" => true,
        "field_4" => ""
      }
    end

    context "with equals operator" do
      it "returns true when values match" do
        conditions = [{ "field_id" => "field_1", "operator" => "equals", "value" => "test" }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end

      it "returns false when values don't match" do
        conditions = [{ "field_id" => "field_1", "operator" => "equals", "value" => "other" }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be false
      end
    end

    context "with not_equals operator" do
      it "returns true when values are different" do
        conditions = [{ "field_id" => "field_1", "operator" => "not_equals", "value" => "other" }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end

    context "with greater_than operator" do
      it "returns true when value is greater" do
        conditions = [{ "field_id" => "field_2", "operator" => "greater_than", "value" => 50 }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end

    context "with less_than operator" do
      it "returns true when value is less" do
        conditions = [{ "field_id" => "field_2", "operator" => "less_than", "value" => 200 }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end

    context "with contains operator" do
      it "returns true when string contains value" do
        conditions = [{ "field_id" => "field_1", "operator" => "contains", "value" => "es" }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end

    context "with is_empty operator" do
      it "returns true when value is empty" do
        conditions = [{ "field_id" => "field_4", "operator" => "is_empty", "value" => nil }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end

    context "with is_not_empty operator" do
      it "returns true when value is not empty" do
        conditions = [{ "field_id" => "field_1", "operator" => "is_not_empty", "value" => nil }]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end

    context "with multiple conditions and AND logic" do
      it "returns true when all conditions match" do
        conditions = [
          { "field_id" => "field_1", "operator" => "equals", "value" => "test", "logic" => "and" },
          { "field_id" => "field_3", "operator" => "equals", "value" => true, "logic" => "and" }
        ]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end

      it "returns false when any condition fails" do
        conditions = [
          { "field_id" => "field_1", "operator" => "equals", "value" => "test", "logic" => "and" },
          { "field_id" => "field_3", "operator" => "equals", "value" => false, "logic" => "and" }
        ]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be false
      end
    end

    context "with multiple conditions and OR logic" do
      it "returns true when any condition matches" do
        conditions = [
          { "field_id" => "field_1", "operator" => "equals", "value" => "wrong", "logic" => "or" },
          { "field_id" => "field_3", "operator" => "equals", "value" => true, "logic" => "or" }
        ]
        result = described_class.new(conditions, field_values).evaluate

        expect(result).to be true
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/condition_evaluator_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/services/condition_evaluator.rb
# frozen_string_literal: true

class ConditionEvaluator
  OPERATORS = %w[equals not_equals contains greater_than less_than is_empty is_not_empty].freeze

  def initialize(conditions, field_values)
    @conditions = conditions || []
    @field_values = field_values || {}
  end

  def evaluate
    return true if conditions.empty?

    results = conditions.map { |condition| evaluate_condition(condition) }
    logic_types = conditions.map { |c| c["logic"] || "and" }

    combine_results(results, logic_types)
  end

  private

  attr_reader :conditions, :field_values

  def evaluate_condition(condition)
    field_id = condition["field_id"]
    operator = condition["operator"]
    expected_value = condition["value"]
    actual_value = field_values[field_id]

    case operator
    when "equals"
      actual_value == expected_value
    when "not_equals"
      actual_value != expected_value
    when "contains"
      actual_value.to_s.include?(expected_value.to_s)
    when "greater_than"
      numeric_compare(actual_value, expected_value) { |a, e| a > e }
    when "less_than"
      numeric_compare(actual_value, expected_value) { |a, e| a < e }
    when "is_empty"
      actual_value.nil? || actual_value.to_s.strip.empty?
    when "is_not_empty"
      actual_value.present? && actual_value.to_s.strip.present?
    else
      false
    end
  end

  def numeric_compare(actual, expected)
    actual_num = actual.to_f
    expected_num = expected.to_f
    yield(actual_num, expected_num)
  rescue
    false
  end

  def combine_results(results, logic_types)
    return results.first if results.size == 1

    # Process from left to right
    combined = results.first

    results[1..].each_with_index do |result, index|
      logic = logic_types[index + 1] || "and"

      combined = if logic == "or"
                   combined || result
                 else
                   combined && result
                 end
    end

    combined
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/condition_evaluator_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/condition_evaluator.rb spec/services/condition_evaluator_spec.rb
git commit -m "feat: add ConditionEvaluator service for field visibility logic"
```

---

### Task 13: Create CalculationEvaluator Service

**Files:**
- Create: `app/services/calculation_evaluator.rb`
- Test: `spec/services/calculation_evaluator_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/calculation_evaluator_spec.rb
require "rails_helper"

RSpec.describe CalculationEvaluator do
  let(:field_values) do
    {
      "price" => 100,
      "quantity" => 5,
      "tax_rate" => 0.1,
      "first_name" => "John",
      "last_name" => "Doe"
    }
  end

  describe "#evaluate" do
    context "with SUM function" do
      it "adds multiple field values" do
        formula = "SUM(price, quantity)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq(105)
      end
    end

    context "with MULTIPLY function" do
      it "multiplies two field values" do
        formula = "MULTIPLY(price, quantity)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq(500)
      end
    end

    context "with DIVIDE function" do
      it "divides first by second value" do
        formula = "DIVIDE(price, quantity)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq(20)
      end

      it "returns nil when dividing by zero" do
        field_values["quantity"] = 0
        formula = "DIVIDE(price, quantity)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to be_nil
      end
    end

    context "with CONCAT function" do
      it "joins text values" do
        formula = "CONCAT(first_name, last_name)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq("JohnDoe")
      end
    end

    context "with IF function" do
      it "returns true value when condition is met" do
        formula = "IF(price > 50, 'expensive', 'cheap')"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq("expensive")
      end

      it "returns false value when condition is not met" do
        field_values["price"] = 30
        formula = "IF(price > 50, 'expensive', 'cheap')"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq("cheap")
      end
    end

    context "with nested functions" do
      it "evaluates nested SUM and MULTIPLY" do
        formula = "MULTIPLY(SUM(price, quantity), tax_rate)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq(10.5)
      end
    end

    context "with literal values" do
      it "handles numeric literals" do
        formula = "SUM(price, 50)"
        result = described_class.new(formula, field_values).evaluate

        expect(result).to eq(150)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid formula" do
      formula = "SUM(price, quantity)"
      expect(described_class.new(formula, field_values).valid?).to be true
    end

    it "returns false for invalid formula" do
      formula = "INVALID(price)"
      expect(described_class.new(formula, field_values).valid?).to be false
    end

    it "returns false for empty formula" do
      formula = ""
      expect(described_class.new(formula, field_values).valid?).to be false
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/calculation_evaluator_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```ruby
# app/services/calculation_evaluator.rb
# frozen_string_literal: true

class CalculationEvaluator
  FUNCTIONS = %w[SUM MULTIPLY DIVIDE CONCAT IF].freeze

  def initialize(formula, field_values)
    @formula = formula.to_s.strip
    @field_values = field_values || {}
  end

  def evaluate
    return nil if formula.blank?

    begin
      parse_and_evaluate(formula)
    rescue StandardError => e
      Rails.logger.error("CalculationEvaluator error: #{e.message}")
      nil
    end
  end

  def valid?
    return false if formula.blank?

    # Check if formula contains valid function
    FUNCTIONS.any? { |func| formula.include?(func) }
  end

  private

  attr_reader :formula, :field_values

  def parse_and_evaluate(expr)
    # Find the outermost function call
    if (match = expr.match(/^(\w+)\((.*)\)$/))
      function_name = match[1].upcase
      args_string = match[2]

      args = parse_arguments(args_string)
      evaluate_function(function_name, args)
    else
      # It's a literal or field reference
      resolve_value(expr)
    end
  end

  def parse_arguments(args_string)
    args = []
    current_arg = ""
    paren_depth = 0

    args_string.each_char do |char|
      case char
      when "("
        paren_depth += 1
        current_arg += char
      when ")"
        paren_depth -= 1
        current_arg += char
      when ","
        if paren_depth == 0
          args << current_arg.strip
          current_arg = ""
        else
          current_arg += char
        end
      else
        current_arg += char
      end
    end

    args << current_arg.strip unless current_arg.empty?
    args
  end

  def evaluate_function(name, args)
    case name
    when "SUM"
      evaluate_sum(args)
    when "MULTIPLY"
      evaluate_multiply(args)
    when "DIVIDE"
      evaluate_divide(args)
    when "CONCAT"
      evaluate_concat(args)
    when "IF"
      evaluate_if(args)
    else
      raise "Unknown function: #{name}"
    end
  end

  def evaluate_sum(args)
    args.map { |arg| parse_and_evaluate(arg).to_f }.sum
  end

  def evaluate_multiply(args)
    args.map { |arg| parse_and_evaluate(arg).to_f }.reduce(1, :*)
  end

  def evaluate_divide(args)
    return nil if args.size < 2

    dividend = parse_and_evaluate(args[0]).to_f
    divisor = parse_and_evaluate(args[1]).to_f

    return nil if divisor.zero?

    dividend / divisor
  end

  def evaluate_concat(args)
    args.map { |arg| parse_and_evaluate(arg).to_s }.join
  end

  def evaluate_if(args)
    return nil if args.size < 3

    condition = args[0]
    true_value = args[1]
    false_value = args[2]

    if evaluate_condition(condition)
      resolve_value(true_value)
    else
      resolve_value(false_value)
    end
  end

  def evaluate_condition(condition)
    # Simple condition parsing: field > value, field < value, field = value
    if (match = condition.match(/(\w+)\s*(>|<|=|>=|<=|!=)\s*(.+)/))
      field = match[1]
      operator = match[2]
      value = match[3].to_f

      field_value = resolve_value(field).to_f

      case operator
      when ">" then field_value > value
      when "<" then field_value < value
      when "=" then field_value == value
      when ">=" then field_value >= value
      when "<=" then field_value <= value
      when "!=" then field_value != value
      else false
      end
    else
      false
    end
  end

  def resolve_value(expr)
    expr = expr.to_s.strip

    # Check if it's a nested function
    if expr.match?(/^\w+\(/)
      return parse_and_evaluate(expr)
    end

    # Check if it's a quoted string
    if expr.match?(/^['"](.*)['"]$/)
      return expr.gsub(/^['"]|['"]$/, "")
    end

    # Check if it's a number
    if expr.match?(/^-?\d+\.?\d*$/)
      return expr.include?(".") ? expr.to_f : expr.to_i
    end

    # It's a field reference
    field_values[expr]
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/calculation_evaluator_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/calculation_evaluator.rb spec/services/calculation_evaluator_spec.rb
git commit -m "feat: add CalculationEvaluator service for formula-based field calculations"
```

---

### Task 14: Update PageContentGenerator for ViewComponent Output

**Files:**
- Modify: `app/services/page_content_generator.rb`
- Test: `spec/services/page_content_generator_spec.rb`

**Step 1: Read current implementation**

Run: Read `app/services/page_content_generator.rb`

**Step 2: Write the failing test**

```ruby
# Add to spec/services/page_content_generator_spec.rb

RSpec.describe PageContentGenerator do
  # ... existing tests ...

  describe "#generate with ViewComponent output" do
    let(:page) { create(:page, configuration: configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Contact",
            "fields" => [
              {
                "id" => "field_1",
                "property_slug" => "email",
                "property_type" => "email",
                "label" => "Email Address",
                "placeholder" => "you@example.com",
                "required" => true,
                "width" => "full"
              }
            ]
          }
        ],
        "settings" => {
          "submit_button_text" => "Send"
        },
        "metadata" => {}
      }
    end

    it "generates ViewComponent render calls" do
      result = described_class.new(page).generate

      expect(result).to include("render FormFields::PageComponent")
      expect(result).to include("render FormFields::FormComponent")
      expect(result).to include("render FormFields::EmailFieldComponent")
    end

    it "includes inline Tailwind classes" do
      result = described_class.new(page).generate

      expect(result).to include("class:")
    end

    it "passes field properties to components" do
      result = described_class.new(page).generate

      expect(result).to include('field_name: "email"')
      expect(result).to include('label: "Email Address"')
      expect(result).to include("required: true")
    end

    it "uses submit_button_text from settings" do
      result = described_class.new(page).generate

      expect(result).to include('submit_text: "Send"')
    end

    it "generates WizardComponent for multi-page forms" do
      configuration["pages"] << {
        "id" => "page_2",
        "name" => "Details",
        "fields" => []
      }
      page.update!(configuration: configuration)

      result = described_class.new(page).generate

      expect(result).to include("render FormFields::WizardComponent")
    end
  end
end
```

**Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/services/page_content_generator_spec.rb -v`
Expected: FAIL (new tests)

**Step 4: Update implementation**

```ruby
# app/services/page_content_generator.rb
# frozen_string_literal: true

class PageContentGenerator
  FIELD_COMPONENTS = {
    "string" => "FormFields::TextFieldComponent",
    "text" => "FormFields::TextareaFieldComponent",
    "email" => "FormFields::EmailFieldComponent",
    "integer" => "FormFields::NumberFieldComponent",
    "number" => "FormFields::NumberFieldComponent",
    "float" => "FormFields::NumberFieldComponent",
    "decimal" => "FormFields::NumberFieldComponent",
    "boolean" => "FormFields::CheckboxFieldComponent",
    "date" => "FormFields::DateFieldComponent",
    "datetime" => "FormFields::DateFieldComponent",
    "select" => "FormFields::SelectFieldComponent",
    "tel" => "FormFields::TextFieldComponent",
    "url" => "FormFields::TextFieldComponent"
  }.freeze

  DEFAULT_COMPONENT = "FormFields::TextFieldComponent"

  def initialize(page)
    @page = page
  end

  def generate
    return "" if page.configuration.blank?

    pages_config = page.configuration["pages"] || legacy_fields_to_pages
    settings = page.configuration["settings"] || {}

    if pages_config.size > 1
      generate_wizard(pages_config, settings)
    else
      generate_single_page(pages_config.first, settings)
    end
  end

  private

  attr_reader :page

  def legacy_fields_to_pages
    # Support old format with flat fields array
    fields = page.configuration["fields"] || []
    [{ "id" => "page_1", "name" => "Form", "fields" => fields }]
  end

  def generate_single_page(page_config, settings)
    fields = page_config&.dig("fields") || []
    submit_text = settings["submit_button_text"] || "Submit"

    <<~ERB.strip
      <%= render FormFields::PageComponent.new(page: @page) do %>
        <%= render FormFields::FormComponent.new(
          action: @form_action,
          submit_text: "#{submit_text}",
          class: "space-y-6"
        ) do %>
          #{generate_fields(fields)}
        <% end %>
      <% end %>
    ERB
  end

  def generate_wizard(pages_config, settings)
    submit_text = settings["submit_button_text"] || "Submit"
    wizard_settings = page.configuration["wizard_settings"] || {}

    steps_content = pages_config.map do |page_data|
      <<~ERB.strip
            wizard.with_step(id: "#{page_data['id']}") do
              #{generate_fields(page_data['fields'] || [])}
            end
      ERB
    end.join("\n      ")

    <<~ERB.strip
      <%= render FormFields::PageComponent.new(page: @page) do %>
        <%= render FormFields::WizardComponent.new(
          pages: @page.configuration["pages"],
          action: @form_action,
          submit_text: "#{submit_text}",
          show_progress: #{wizard_settings['show_progress'] != false},
          allow_back: #{wizard_settings['allow_back'] != false}
        ) do |wizard| %>
          #{steps_content}
        <% end %>
      <% end %>
    ERB
  end

  def generate_fields(fields)
    return "" if fields.empty?

    fields.map { |field| generate_field(field) }.join("\n      ")
  end

  def generate_field(field)
    component = FIELD_COMPONENTS[field["property_type"]] || DEFAULT_COMPONENT
    field_name = field["property_slug"] || field["id"]

    width_class = case field["width"]
                  when "half" then "w-1/2"
                  when "third" then "w-1/3"
                  else "w-full"
                  end

    # Build inline Tailwind classes for style isolation
    input_classes = "px-4 py-2 border border-gray-300 rounded-lg " \
                    "focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 " \
                    "transition-all duration-150"

    options = [
      %(field_name: "#{field_name}"),
      %(label: "#{field['label']}"),
      %(required: #{field['required'] == true}),
      %(placeholder: "#{field['placeholder']}"),
      %(class: "#{width_class} #{input_classes}")
    ]

    options << %(help_text: "#{field['help_text']}") if field["help_text"].present?

    # Add data attributes for conditions if present
    if field["conditions"].present? && field["conditions"].any?
      options << %(data: { conditions: #{field['conditions'].to_json} })
    end

    <<~ERB.strip
          <%= render #{component}.new(
            #{options.join(",\n        ")}
          ) %>
    ERB
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/services/page_content_generator_spec.rb -v`
Expected: PASS

**Step 6: Commit**

```bash
git add app/services/page_content_generator.rb spec/services/page_content_generator_spec.rb
git commit -m "feat: update PageContentGenerator to output ViewComponent render calls"
```

---

## Phase 7: Controller Updates

### Task 15: Update PagesController for Flows Loading

**Files:**
- Modify: `app/controllers/pages_controller.rb`
- Test: `spec/controllers/pages_controller_spec.rb`

**Step 1: Read current implementation**

Run: Read `app/controllers/pages_controller.rb`

**Step 2: Write the failing test**

```ruby
# Add to spec/controllers/pages_controller_spec.rb

RSpec.describe PagesController, type: :controller do
  # ... existing tests ...

  describe "GET #edit" do
    let(:entity) { create(:entity, customer: current_customer) }
    let(:page_record) do
      create(:page, customer: current_customer, configuration: {
        "pages" => [{ "id" => "page_1", "name" => "Form", "fields" => [] }],
        "metadata" => { "entity_id" => entity.id }
      })
    end

    before do
      create_list(:flowchart, 2, entity: entity, customer: current_customer, flowchart_type: :custom)
      create_list(:flowchart, 2, flowchart_type: :blueprint)
    end

    it "loads entity_flows for bound entity" do
      get :edit, params: { customer_id: current_customer.id, id: page_record.id }

      expect(assigns(:entity_flows)).to be_present
      expect(assigns(:entity_flows).size).to eq(2)
    end

    it "loads blueprint_flows" do
      get :edit, params: { customer_id: current_customer.id, id: page_record.id }

      expect(assigns(:blueprint_flows)).to be_present
      expect(assigns(:blueprint_flows).size).to eq(2)
    end

    it "sets entity_flows to empty array when no entity bound" do
      page_record.update!(configuration: { "pages" => [], "metadata" => {} })
      get :edit, params: { customer_id: current_customer.id, id: page_record.id }

      expect(assigns(:entity_flows)).to eq([])
    end
  end

  describe "GET #entity_flows" do
    let(:entity) { create(:entity, customer: current_customer) }

    before do
      create_list(:flowchart, 2, entity: entity, customer: current_customer)
    end

    it "returns flows for given entity as JSON" do
      get :entity_flows, params: {
        customer_id: current_customer.id,
        entity_id: entity.id
      }, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["entity_flows"].size).to eq(2)
    end

    it "includes blueprint flows" do
      create(:flowchart, flowchart_type: :blueprint)

      get :entity_flows, params: {
        customer_id: current_customer.id,
        entity_id: entity.id
      }, format: :json

      json = JSON.parse(response.body)
      expect(json["blueprint_flows"].size).to eq(1)
    end
  end
end
```

**Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/pages_controller_spec.rb -v`
Expected: FAIL

**Step 4: Update implementation**

Add to `app/controllers/pages_controller.rb`:

```ruby
# In edit action, add:
def edit
  @page = current_customer.pages.find(params[:id])
  @entities = current_customer.entities.active.by_name

  load_flows_for_page
end

# Add new action:
def entity_flows
  entity_id = params[:entity_id]

  @entity_flows = if entity_id.present?
                    Flowchart.for_current_customer
                             .where(entity_id: entity_id)
                             .active
                             .recent
                  else
                    []
                  end

  @blueprint_flows = Flowchart.blueprints.active.recent

  respond_to do |format|
    format.json do
      render json: {
        entity_flows: @entity_flows.map { |f| flow_json(f) },
        blueprint_flows: @blueprint_flows.map { |f| flow_json(f) }
      }
    end
  end
end

private

def load_flows_for_page
  entity_id = @page.metadata&.dig("entity_id")

  @entity_flows = if entity_id.present?
                    Flowchart.for_current_customer
                             .where(entity_id: entity_id)
                             .active
                             .recent
                  else
                    []
                  end

  @blueprint_flows = Flowchart.blueprints.active.recent
  @entity_name = @page.metadata&.dig("entity_name")
end

def flow_json(flowchart)
  {
    id: flowchart.id,
    name: flowchart.name,
    flowchart_type: flowchart.flowchart_type,
    entity_id: flowchart.entity_id
  }
end
```

Add route in `config/routes.rb`:

```ruby
resources :pages do
  # ... existing member routes ...
  collection do
    get :entity_flows
    # ... existing collection routes ...
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/pages_controller_spec.rb -v`
Expected: PASS

**Step 6: Commit**

```bash
git add app/controllers/pages_controller.rb config/routes.rb spec/controllers/pages_controller_spec.rb
git commit -m "feat: add entity_flows endpoint and load flows in page editor"
```

---

## Phase 8: Stimulus Controller Updates

### Task 16: Add Multi-Page Support to page_builder_controller.js

**Files:**
- Modify: `app/javascript/controllers/page_builder_controller.js`

**Step 1: Read current implementation**

Run: Read `app/javascript/controllers/page_builder_controller.js` (first 200 lines to understand structure)

**Step 2: Add new values and targets**

Add to static values:

```javascript
static values = {
  // ... existing values ...
  activePage: { type: String, default: "page_1" },
  floatingPanelVisible: { type: Boolean, default: false }
}

static targets = [
  // ... existing targets ...
  "pageTabs",
  "floatingPanel",
  "conditionsContainer"
]
```

**Step 3: Add multi-page methods**

```javascript
// Multi-page management
addPage() {
  const pageId = `page_${Date.now()}`
  const pageNumber = this.configuration.pages.length + 1

  const newPage = {
    id: pageId,
    name: `Page ${pageNumber}`,
    order: pageNumber,
    fields: []
  }

  this.configuration.pages.push(newPage)
  this.activePageValue = pageId
  this.saveHistory()
  this.renderPageTabs()
  this.renderCanvas()
  this.scheduleAutoSave()
}

switchPage(event) {
  const pageId = event.currentTarget.dataset.pageId
  if (pageId && pageId !== this.activePageValue) {
    this.activePageValue = pageId
    this.hideFloatingPanel()
    this.renderPageTabs()
    this.renderCanvas()
  }
}

deletePage(event) {
  event.stopPropagation()
  const pageId = event.currentTarget.dataset.pageId

  if (this.configuration.pages.length <= 1) {
    return // Can't delete last page
  }

  const pageIndex = this.configuration.pages.findIndex(p => p.id === pageId)
  if (pageIndex === -1) return

  this.configuration.pages.splice(pageIndex, 1)

  // Switch to another page if deleted active
  if (this.activePageValue === pageId) {
    this.activePageValue = this.configuration.pages[0].id
  }

  this.saveHistory()
  this.renderPageTabs()
  this.renderCanvas()
  this.scheduleAutoSave()
}

renamePage(pageId, newName) {
  const page = this.configuration.pages.find(p => p.id === pageId)
  if (page) {
    page.name = newName
    this.renderPageTabs()
    this.scheduleAutoSave()
  }
}

get currentPage() {
  return this.configuration.pages.find(p => p.id === this.activePageValue) ||
         this.configuration.pages[0]
}

get currentPageFields() {
  return this.currentPage?.fields || []
}
```

**Step 4: Add floating panel methods**

```javascript
// Floating panel management
showFloatingPanel(fieldId) {
  const field = this.currentPageFields.find(f => f.id === fieldId)
  if (!field) return

  this.selectedFieldValue = fieldId
  this.floatingPanelVisibleValue = true

  // Position panel near the selected field
  const fieldElement = this.element.querySelector(`[data-field-id="${fieldId}"]`)
  if (fieldElement && this.hasFloatingPanelTarget) {
    const rect = fieldElement.getBoundingClientRect()
    const panelWidth = 320

    // Position to the right of the field, or left if not enough space
    let left = rect.right + 16
    if (left + panelWidth > window.innerWidth) {
      left = rect.left - panelWidth - 16
    }

    this.floatingPanelTarget.style.left = `${left}px`
    this.floatingPanelTarget.style.top = `${rect.top}px`
  }

  this.renderFloatingPanel(field)
}

hideFloatingPanel() {
  this.floatingPanelVisibleValue = false
  this.selectedFieldValue = null

  if (this.hasFloatingPanelTarget) {
    this.floatingPanelTarget.innerHTML = ''
    this.floatingPanelTarget.classList.add('hidden')
  }
}

updateFieldProperty(event) {
  const property = event.target.dataset.property
  const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value

  if (!this.selectedFieldValue || !property) return

  const field = this.currentPageFields.find(f => f.id === this.selectedFieldValue)
  if (field) {
    field[property] = value
    this.renderFieldCard(field)
    this.scheduleAutoSave()
  }
}
```

**Step 5: Add condition methods**

```javascript
// Condition management
addCondition() {
  if (!this.selectedFieldValue) return

  const field = this.currentPageFields.find(f => f.id === this.selectedFieldValue)
  if (!field) return

  field.conditions = field.conditions || []
  field.conditions.push({
    field_id: '',
    operator: 'equals',
    value: '',
    logic: 'and'
  })

  this.renderConditionsInPanel(field)
  this.scheduleAutoSave()
}

updateCondition(fieldId, conditionIndex, property, value) {
  const field = this.currentPageFields.find(f => f.id === fieldId)
  if (!field || !field.conditions[conditionIndex]) return

  field.conditions[conditionIndex][property] = value
  this.scheduleAutoSave()
}

removeCondition(fieldId, conditionIndex) {
  const field = this.currentPageFields.find(f => f.id === fieldId)
  if (!field || !field.conditions) return

  field.conditions.splice(conditionIndex, 1)
  this.renderConditionsInPanel(field)
  this.scheduleAutoSave()
}
```

**Step 6: Add entity/flows loading**

```javascript
// Entity and flows
async loadEntityFlows(entityId) {
  if (!entityId) {
    this.entityFlows = []
    this.renderFlowsSection()
    return
  }

  try {
    const response = await fetch(
      `/${this.customerIdValue}/pages/entity_flows?entity_id=${entityId}`,
      { headers: { 'Accept': 'application/json' } }
    )

    if (response.ok) {
      const data = await response.json()
      this.entityFlows = data.entity_flows
      this.blueprintFlows = data.blueprint_flows
      this.renderFlowsSection()
    }
  } catch (error) {
    console.error('Failed to load flows:', error)
  }
}

async onEntityChange(event) {
  const entityId = event.target.value
  const entityName = event.target.selectedOptions[0]?.text || ''

  this.configuration.metadata = this.configuration.metadata || {}
  this.configuration.metadata.entity_id = entityId
  this.configuration.metadata.entity_name = entityName

  await this.loadEntityProperties(entityId)
  await this.loadEntityFlows(entityId)
  this.scheduleAutoSave()
}
```

**Step 7: Commit**

```bash
git add app/javascript/controllers/page_builder_controller.js
git commit -m "feat: add multi-page, floating panel, and flows support to page builder"
```

---

### Task 17: Create Collapsible Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/collapsible_controller.js`

**Step 1: Write implementation**

```javascript
// app/javascript/controllers/collapsible_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]
  static values = {
    open: { type: Boolean, default: true }
  }

  connect() {
    this.render()
  }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.render()
  }

  render() {
    if (this.hasContentTarget) {
      this.contentTarget.classList.toggle("hidden", !this.openValue)
    }

    if (this.hasIconTarget) {
      this.iconTarget.style.transform = this.openValue ? "rotate(0deg)" : "rotate(-90deg)"
    }
  }
}
```

**Step 2: Register controller**

Ensure it's registered in `app/javascript/controllers/index.js`.

**Step 3: Commit**

```bash
git add app/javascript/controllers/collapsible_controller.js
git commit -m "feat: add collapsible Stimulus controller for expandable sections"
```

---

### Task 18: Create Wizard Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/wizard_controller.js`

**Step 1: Write implementation**

```javascript
// app/javascript/controllers/wizard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "prevButton", "nextButton", "submitButton", "progressBar", "progressText", "form"]
  static values = {
    currentStep: { type: Number, default: 1 },
    totalSteps: Number,
    validateOnNext: { type: Boolean, default: true }
  }

  connect() {
    this.render()
  }

  next() {
    if (this.validateOnNextValue && !this.validateCurrentStep()) {
      return
    }

    if (this.currentStepValue < this.totalStepsValue) {
      this.currentStepValue++
    }
  }

  previous() {
    if (this.currentStepValue > 1) {
      this.currentStepValue--
    }
  }

  currentStepValueChanged() {
    this.render()
  }

  render() {
    // Show/hide steps
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("hidden", index + 1 !== this.currentStepValue)
    })

    // Update buttons
    if (this.hasPrevButtonTarget) {
      this.prevButtonTarget.classList.toggle("invisible", this.currentStepValue === 1)
    }

    if (this.hasNextButtonTarget && this.hasSubmitButtonTarget) {
      const isLastStep = this.currentStepValue === this.totalStepsValue
      this.nextButtonTarget.classList.toggle("hidden", isLastStep)
      this.submitButtonTarget.classList.toggle("hidden", !isLastStep)
    }

    // Update progress
    if (this.hasProgressBarTarget) {
      const progress = (this.currentStepValue / this.totalStepsValue) * 100
      this.progressBarTarget.style.width = `${progress}%`
    }

    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `Step ${this.currentStepValue} of ${this.totalStepsValue}`
    }
  }

  validateCurrentStep() {
    const currentStep = this.stepTargets[this.currentStepValue - 1]
    if (!currentStep) return true

    const inputs = currentStep.querySelectorAll("input[required], select[required], textarea[required]")
    let valid = true

    inputs.forEach(input => {
      if (!input.value.trim()) {
        input.classList.add("border-red-500")
        valid = false
      } else {
        input.classList.remove("border-red-500")
      }
    })

    return valid
  }
}
```

**Step 2: Register controller**

**Step 3: Commit**

```bash
git add app/javascript/controllers/wizard_controller.js
git commit -m "feat: add wizard Stimulus controller for multi-step forms"
```

---

## Phase 9: View Integration

### Task 19: Refactor _editor.html.erb to Use ViewComponents

**Files:**
- Modify: `app/views/pages/_editor.html.erb`

**Step 1: Read current implementation**

Run: Read `app/views/pages/_editor.html.erb`

**Step 2: Refactor to use new components**

Replace sidebar flows section with FlowsSectionComponent render call.
Add FloatingPanelComponent container.
Add PageTabsComponent in canvas header.

Key changes:
1. Add flows section using FlowsSectionComponent
2. Add floating panel container
3. Add page tabs for multi-page support
4. Update data attributes for new Stimulus actions

**Step 3: Commit**

```bash
git add app/views/pages/_editor.html.erb
git commit -m "refactor: update page editor to use new ViewComponents"
```

---

## Phase 10: Final Integration & Testing

### Task 20: Run Full Test Suite

**Step 1: Run all specs**

Run: `bundle exec rspec`
Expected: All tests pass

**Step 2: Fix any failures**

Address any test failures found.

**Step 3: Run system tests if available**

Run: `bundle exec rspec spec/system` (if exists)

**Step 4: Manual smoke test**

1. Navigate to page builder
2. Create new page
3. Add fields via drag-drop
4. Select field, verify floating panel appears
5. Add second page
6. Switch between pages
7. Select entity, verify flows section populates
8. Preview generated output
9. Verify auto-save works

**Step 5: Final commit**

```bash
git add .
git commit -m "test: verify full test suite passes after page builder refactor"
```

---

## Summary

This plan covers:

1. **Phase 1**: Styling foundation (design tokens, component classes, animations)
2. **Phase 2**: Form output components (PageComponent, FormComponent, WizardComponent, CalculatedFieldComponent)
3. **Phase 3**: Flows section components (FlowItemComponent, FlowsSectionComponent)
4. **Phase 4**: Floating panel (FloatingPanelComponent)
5. **Phase 5**: Multi-page navigation (PageTabsComponent)
6. **Phase 6**: Services (ConditionEvaluator, CalculationEvaluator, enhanced PageContentGenerator)
7. **Phase 7**: Controller updates (entity_flows endpoint)
8. **Phase 8**: Stimulus controllers (multi-page, floating panel, conditions, wizard, collapsible)
9. **Phase 9**: View integration
10. **Phase 10**: Testing and validation

Each task follows TDD with:
- Write failing test
- Run to verify failure
- Write minimal implementation
- Run to verify pass
- Commit

---

**Plan complete and saved to `docs/plans/2026-02-14-page-builder-refactor.md`.**

**Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**

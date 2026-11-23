# Page Builder Refactor Design

**Date:** 2026-02-14
**Status:** Approved
**Reference:** JotForm form builder platform

## Overview

Refactor the page builder to provide a more polished, JotForm-like experience with enhanced features including floating property panel, conditional logic, field calculations, multi-page wizard forms, and entity/flows integration.

## Requirements

### Core Features
1. **Floating property panel** - appears near selected field instead of fixed right sidebar
2. **Conditional visibility** - show/hide fields based on other field values
3. **Field calculations** - computed fields with formulas (SUM, MULTIPLY, etc.)
4. **Form-level settings** - submit button text, thank you page, styling
5. **Multi-page/wizard forms** - support for forms with multiple pages/steps

### Visual & UX
1. Smooth animations and transitions throughout
2. Better visual feedback (drop zones, selection states, saving indicators)
3. Consistent component styling patterns across all ViewComponents

### Entity & Flows Integration
1. Entity dropdown shows all entities for current customer
2. **Flows section** in sidebar showing:
   - Flowcharts bound to selected entity
   - Blueprint type flowcharts (shared)
3. Entity properties populate as available page builder elements when entity selected

### Technical Requirements
1. Generated ERB templates must be ViewComponents with inline TailwindCSS (style isolation)
2. Strict adherence to Rails v8 conventions and best practices
3. Tech stack: Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent

---

## Architecture

### Overall Layout

```
Page Builder UI
├── Top Toolbar
│   ├── Back button, Page name
│   ├── Entity selector dropdown
│   ├── Device preview toggles
│   └── Undo/Redo, Preview, Save
│
├── Left Sidebar (Component Library)
│   ├── Search box
│   ├── Basic Fields category
│   ├── Choice Fields category
│   ├── Advanced Fields category
│   ├── Layout Elements category
│   ├── Entity Properties (dynamic, from selected entity)
│   └── Flows Section
│       ├── Entity-bound flowcharts
│       └── Blueprint flowcharts
│
├── Center Canvas
│   ├── Form preview with responsive width
│   ├── Multi-page tabs (for wizard forms)
│   ├── Drag-drop zones with animations
│   └── Fields grid
│
└── Floating Property Panel (appears on field selection)
    ├── General settings (label, placeholder, help)
    ├── Layout settings (width)
    ├── Conditional Logic (visibility rules)
    ├── Calculations (formulas)
    └── Form Settings (when no field selected)
```

---

## Data Model

### Page.configuration (Enhanced Structure)

```json
{
  "pages": [
    {
      "id": "page_1",
      "name": "Contact Info",
      "order": 1,
      "fields": [
        {
          "id": "field_xxx",
          "property_slug": "email",
          "property_type": "string",
          "label": "Email",
          "placeholder": "Enter email",
          "help_text": "",
          "required": true,
          "width": "full",
          "conditions": [
            {
              "field_id": "field_yyy",
              "operator": "equals",
              "value": true,
              "logic": "and"
            }
          ],
          "calculation": null
        }
      ]
    }
  ],
  "wizard_settings": {
    "show_progress": true,
    "allow_back": true,
    "validate_on_next": true
  },
  "settings": {
    "submit_button_text": "Submit",
    "thank_you_message": "Thank you for your submission!",
    "thank_you_redirect_url": null,
    "form_title": "",
    "form_description": ""
  },
  "metadata": {
    "entity_id": 123,
    "entity_name": "Contact",
    "flowchart_ids": [1, 2],
    "created_at": "2026-02-14T..."
  }
}
```

### Condition Structure

```json
{
  "conditions": [
    {
      "field_id": "field_123",
      "operator": "equals|not_equals|contains|greater_than|less_than|is_empty|is_not_empty",
      "value": "some_value",
      "logic": "and|or"
    }
  ],
  "action": "show|hide"
}
```

### Calculation Structure

```json
{
  "calculation": {
    "formula": "SUM(field_1, field_2)",
    "result_type": "number",
    "format": "currency|percentage|decimal"
  }
}
```

**Supported functions:**
- `SUM(field1, field2, ...)` - Add values
- `MULTIPLY(field1, field2)` - Multiply values
- `DIVIDE(field1, field2)` - Divide values
- `CONCAT(field1, field2)` - Join text
- `IF(condition, true_value, false_value)` - Conditional

---

## ViewComponent Structure

### Page Builder Components (`app/components/page_builder/`)

| Component | Purpose |
|-----------|---------|
| `EditorLayoutComponent` | Main 3-panel layout container |
| `ToolbarComponent` | Top toolbar with entity selector, actions |
| `SidebarComponent` | Left sidebar with component library |
| `ComponentCategoryComponent` | Collapsible category in sidebar |
| `ComponentItemComponent` | Draggable item in category |
| `FlowsSectionComponent` | Shows entity-bound + blueprint flows |
| `FlowItemComponent` | Individual flow item display |
| `CanvasComponent` | Center canvas with pages (existing, enhanced) |
| `PageTabsComponent` | Multi-page tab navigation |
| `FieldCardComponent` | Field card in canvas (existing, enhanced) |
| `FloatingPanelComponent` | Floating property editor |
| `ConditionBuilderComponent` | Conditional logic UI |
| `CalculationEditorComponent` | Formula editor UI |
| `FormSettingsComponent` | Form-level settings panel |

### Form Fields Components (`app/components/form_fields/`)

| Component | Purpose |
|-----------|---------|
| `PageComponent` | Wraps entire generated page |
| `FormComponent` | Form wrapper with submit button |
| `WizardComponent` | Multi-page wizard container |
| `WizardStepComponent` | Individual wizard step |
| `BaseFieldComponent` | Base class (existing, enhanced) |
| `TextFieldComponent` | Text input (existing) |
| `EmailFieldComponent` | Email input (existing) |
| `NumberFieldComponent` | Number input (existing) |
| `TextareaFieldComponent` | Multi-line text (existing) |
| `CheckboxFieldComponent` | Checkbox/toggle (existing) |
| `DateFieldComponent` | Date picker (existing) |
| `SelectFieldComponent` | Dropdown (existing) |
| `CalculatedFieldComponent` | Display-only calculated value |

### Generated Content Pattern

`PageContentGenerator` generates ViewComponent calls with inline Tailwind:

```erb
<%= render FormFields::PageComponent.new(page: @page) do %>
  <%= render FormFields::FormComponent.new(
    submit_text: "Submit",
    class: "space-y-6"
  ) do %>
    <%= render FormFields::TextFieldComponent.new(
      field_name: "email",
      label: "Email",
      required: true,
      class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
    ) %>
  <% end %>
<% end %>
```

---

## Styling Consistency

### Design Tokens (`app/components/concerns/design_tokens.rb`)

```ruby
module DesignTokens
  # Colors
  PRIMARY = "indigo-600"
  PRIMARY_HOVER = "indigo-700"
  SECONDARY = "gray-600"
  BORDER = "gray-200"

  # Spacing
  SPACING_SM = "2"
  SPACING_MD = "4"
  SPACING_LG = "6"

  # Border radius
  ROUNDED_SM = "rounded"
  ROUNDED_MD = "rounded-lg"
  ROUNDED_LG = "rounded-xl"

  # Shadows
  SHADOW_SM = "shadow-sm"
  SHADOW_MD = "shadow-md"
  SHADOW_LG = "shadow-lg"

  # Transitions
  TRANSITION_DEFAULT = "transition-all duration-200 ease-in-out"
  TRANSITION_FAST = "transition-all duration-150 ease-out"
end
```

### Component Base Classes

```ruby
module ComponentClasses
  # Buttons
  BTN_PRIMARY = "px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700
                 transition-all duration-200 focus:ring-2 focus:ring-indigo-500
                 focus:ring-offset-2 font-medium"

  BTN_SECONDARY = "px-4 py-2 bg-white text-gray-700 border border-gray-300 rounded-lg
                   hover:bg-gray-50 transition-all duration-200"

  # Cards
  CARD = "bg-white border border-gray-200 rounded-lg shadow-sm"
  CARD_HOVER = "bg-white border border-gray-200 rounded-lg shadow-sm
                hover:border-indigo-300 hover:shadow-md transition-all duration-200"

  # Inputs
  INPUT = "w-full px-3 py-2 border border-gray-300 rounded-lg
           focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500
           transition-all duration-150"

  # Floating panel
  FLOATING_PANEL = "absolute bg-white border border-gray-200 rounded-xl shadow-xl
                    p-4 z-50 min-w-80"
end
```

### Animation Utilities (`app/assets/stylesheets/application.tailwind.css`)

```css
@layer utilities {
  .animate-fade-in {
    animation: fadeIn 0.2s ease-out forwards;
  }

  .animate-slide-up {
    animation: slideUp 0.2s ease-out forwards;
  }

  .animate-scale-in {
    animation: scaleIn 0.15s ease-out forwards;
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideUp {
    from { opacity: 0; transform: translateY(0.5rem); }
    to { opacity: 1; transform: translateY(0); }
  }

  @keyframes scaleIn {
    from { opacity: 0; transform: scale(0.95); }
    to { opacity: 1; transform: scale(1); }
  }
}
```

---

## Entity & Flows Integration

### Entity Selection Flow

1. User selects entity from dropdown in toolbar
2. System loads `entity.property_schema_json`
3. Properties populate "Entity Properties" category in sidebar
4. System loads bound flowcharts into "Flows" section
5. Configuration updates with `metadata.entity_id` and `metadata.entity_name`

### Flows Section

**Location:** Left sidebar, below component categories

**Structure:**
```
Flows
├── [Entity Name] Flows (collapsible)
│   ├── Flow 1 (custom, bound to entity)
│   ├── Flow 2 (custom, bound to entity)
│   └── ...
│
└── Blueprint Flows (collapsible)
    ├── Blueprint Flow 1 (shared)
    ├── Blueprint Flow 2 (shared)
    └── ...
```

**Data loading:**
```ruby
# In PagesController#edit
@entity_flows = Flowchart.for_current_customer
                         .where(entity_id: @page.metadata["entity_id"])
                         .active
@blueprint_flows = Flowchart.blueprints.active
```

### Property Type Mapping

Entity property types map to form field types:

| Entity Type | Form Field Component |
|-------------|---------------------|
| `Types::String` | `TextFieldComponent` |
| `Types::Integer` | `NumberFieldComponent` |
| `Types::Float` | `NumberFieldComponent` |
| `Types::Decimal` | `NumberFieldComponent` |
| `Types::Bool` | `CheckboxFieldComponent` |
| `Types::Date` | `DateFieldComponent` |
| `Types::DateTime` | `DateFieldComponent` |
| `Types::Array` | `SelectFieldComponent` (multi) |

---

## Multi-Page/Wizard Forms

### Page Tab Navigation

**PageTabsComponent:**
- Horizontal tabs showing page names
- Add page button (+)
- Drag to reorder pages
- Click tab to switch active page
- Context menu for rename/delete

### Wizard Output

**WizardComponent generates:**
```erb
<%= render FormFields::WizardComponent.new(
  pages: @pages,
  show_progress: true,
  allow_back: true
) do |wizard| %>
  <% @pages.each do |page| %>
    <%= wizard.with_step(name: page.name) do %>
      <%= render_fields(page.fields) %>
    <% end %>
  <% end %>
<% end %>
```

**Features:**
- Progress indicator (Step 1 of N)
- Previous/Next buttons
- Page validation before advancing
- Final submit on last page

---

## Stimulus Controller Updates

### New Values

```javascript
static values = {
  configuration: Object,
  activePage: { type: String, default: "page_1" },
  selectedField: String,
  floatingPanelPosition: Object,
  isDirty: { type: Boolean, default: false }
}
```

### New Methods

```javascript
// Multi-page
addPage()
switchPage(pageId)
reorderPages(order)
deletePage(pageId)
renamePage(pageId, newName)

// Floating panel
showFloatingPanel(fieldId, position)
hideFloatingPanel()
updateFloatingPanelPosition()

// Conditions
addCondition(fieldId)
updateCondition(fieldId, conditionIndex, data)
removeCondition(fieldId, conditionIndex)
evaluateConditions()

// Calculations
setCalculation(fieldId, formula)
evaluateCalculations()
validateFormula(formula)

// Entity/Flows
loadEntityFlows(entityId)
loadBlueprintFlows()
```

---

## File Structure

```
app/
├── components/
│   ├── concerns/
│   │   ├── design_tokens.rb
│   │   └── component_classes.rb
│   ├── page_builder/
│   │   ├── editor_layout_component.rb
│   │   ├── toolbar_component.rb
│   │   ├── sidebar_component.rb
│   │   ├── component_category_component.rb
│   │   ├── component_item_component.rb
│   │   ├── flows_section_component.rb
│   │   ├── flow_item_component.rb
│   │   ├── canvas_component.rb (enhanced)
│   │   ├── page_tabs_component.rb
│   │   ├── field_card_component.rb (enhanced)
│   │   ├── floating_panel_component.rb
│   │   ├── condition_builder_component.rb
│   │   ├── calculation_editor_component.rb
│   │   └── form_settings_component.rb
│   └── form_fields/
│       ├── page_component.rb
│       ├── form_component.rb
│       ├── wizard_component.rb
│       ├── wizard_step_component.rb
│       ├── calculated_field_component.rb
│       └── ... (existing field components)
├── javascript/controllers/
│   └── page_builder_controller.js (enhanced)
├── services/
│   ├── page_content_generator.rb (enhanced)
│   ├── condition_evaluator.rb
│   └── calculation_evaluator.rb
└── views/pages/
    └── _editor.html.erb (refactored to use components)
```

---

## Testing Strategy

### Unit Tests
- ViewComponent specs for all new components
- Service specs for condition and calculation evaluators
- Model specs for enhanced Page configuration validation

### Integration Tests
- Controller specs for entity/flows loading
- System specs for page builder interactions

### JavaScript Tests
- Stimulus controller specs for new methods
- Condition evaluation tests
- Calculation evaluation tests

---

## Success Criteria

1. Floating property panel appears smoothly near selected field
2. Conditional visibility works in both builder preview and generated output
3. Field calculations evaluate correctly in real-time
4. Multi-page forms navigate correctly with validation
5. Entity selection loads properties and flows correctly
6. Generated ViewComponents render with isolated inline styling
7. All animations are smooth (60fps)
8. All components follow consistent styling patterns
9. Full RSpec test coverage for new functionality
10. Strict adherence to Rails v8 conventions

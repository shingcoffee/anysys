# JotForm-Style Page Builder Rebuild Design

**Date:** 2026-02-14
**Status:** Approved
**Approach:** Component-First Rebuild
**Reference:** JotForm form builder platform, Anysys property editor

## Overview

Complete rebuild of the page builder using ViewComponents with strict design patterns, matching the Anysys's styling for consistency. This provides a comprehensive JotForm-like form building experience.

## Requirements

1. Reference JotForm form builder platform for functionality
2. Strictly follow Rails v8 conventions and best practices
3. CSS styling must be consistent with Anysys (property editor popup)
4. Tech stack: Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent

---

## Architecture

### Component Structure

```
Page Builder (ViewComponent-based)
├── PageBuilder::EditorComponent (main container)
│   ├── PageBuilder::ToolbarComponent
│   │   ├── Back button, Page name (editable)
│   │   ├── Entity selector
│   │   ├── Device preview (mobile/tablet/desktop)
│   │   └── Undo/Redo, Preview, Save buttons
│   │
│   ├── PageBuilder::SidebarComponent (left)
│   │   ├── Search input
│   │   ├── PageBuilder::FieldCategoryComponent (repeated)
│   │   │   └── PageBuilder::FieldItemComponent (draggable)
│   │   ├── PageBuilder::EntityFieldsComponent (dynamic)
│   │   └── PageBuilder::FlowsSectionComponent
│   │
│   ├── PageBuilder::CanvasComponent (center)
│   │   ├── PageBuilder::PageTabsComponent (multi-page)
│   │   ├── PageBuilder::FormPreviewComponent
│   │   │   ├── Form header (title, description)
│   │   │   ├── PageBuilder::FieldCardComponent (repeated)
│   │   │   └── Form footer (submit button)
│   │   └── Drop zones with animations
│   │
│   └── PageBuilder::PropertySidebarComponent (right, hidden by default)
│       ├── Header (field type, close button)
│       ├── General settings (label, placeholder, help)
│       ├── Field-specific options (for select/radio: options editor)
│       ├── Validation rules
│       ├── Conditional logic builder
│       ├── Layout (width selection)
│       └── Footer (duplicate, delete)
```

---

## Field Types

### Basic Fields

| Field Type | Component | Icon | Description |
|------------|-----------|------|-------------|
| Text Input | `TextFieldComponent` | Lines | Single-line text |
| Email | `EmailFieldComponent` | Envelope | Email with validation |
| Number | `NumberFieldComponent` | Hash | Numeric input with min/max |
| Phone | `PhoneFieldComponent` | Phone | Phone with country code selector |
| URL | `UrlFieldComponent` | Link | URL with validation |
| Password | `PasswordFieldComponent` | Lock | Masked input |

### Choice Fields

| Field Type | Component | Icon | Description |
|------------|-----------|------|-------------|
| Dropdown | `SelectFieldComponent` | Chevron | Single select dropdown |
| Radio | `RadioFieldComponent` | Circle | Single choice radio buttons |
| Checkbox | `CheckboxFieldComponent` | Check | Multiple choice checkboxes |
| Toggle | `ToggleFieldComponent` | Switch | Yes/No toggle switch |

### Advanced Fields

| Field Type | Component | Icon | Description |
|------------|-----------|------|-------------|
| Textarea | `TextareaFieldComponent` | Align-left | Multi-line text |
| Date | `DateFieldComponent` | Calendar | Date picker |
| Time | `TimeFieldComponent` | Clock | Time picker |
| DateTime | `DateTimeFieldComponent` | Calendar+Clock | Combined date & time |
| File Upload | `FileUploadFieldComponent` | Upload | File attachment |
| Signature | `SignatureFieldComponent` | Pen | Draw signature |
| Rating | `RatingFieldComponent` | Star | Star rating (1-5) |
| Scale | `ScaleFieldComponent` | Slider | Linear scale (1-10) |

### Layout Elements

| Element | Component | Description |
|---------|-----------|-------------|
| Heading | `HeadingElementComponent` | H1-H6 text |
| Paragraph | `ParagraphElementComponent` | Rich text block |
| Divider | `DividerElementComponent` | Horizontal line |
| Section | `SectionElementComponent` | Grouping container |

---

## Property Sidebar

### Structure (matches Anysys)

```
PropertySidebarComponent (width: 384px, hidden by default)
├── Header
│   ├── Field type icon + label
│   ├── Field slug (small text)
│   └── Close button (X)
│
├── Scrollable Content
│   ├── General Section (collapsible)
│   │   ├── Label input
│   │   ├── Placeholder input
│   │   ├── Help text textarea
│   │   └── Default value input
│   │
│   ├── Options Section (for select/radio/checkbox only)
│   │   ├── OptionsEditorComponent
│   │   │   ├── Option row (drag handle, label, value, delete)
│   │   │   ├── Option row...
│   │   │   └── "Add Option" button
│   │   └── "Allow Other" toggle
│   │
│   ├── Validation Section (collapsible)
│   │   ├── Required toggle
│   │   ├── Min/Max length (for text)
│   │   ├── Min/Max value (for number)
│   │   ├── Pattern/Regex input
│   │   └── Custom error message
│   │
│   ├── Conditional Logic Section (collapsible)
│   │   ├── ConditionBuilderComponent
│   │   │   ├── "Show this field when..."
│   │   │   ├── Condition row (field, operator, value, AND/OR)
│   │   │   └── "Add Condition" button
│   │   └── Action: Show/Hide selector
│   │
│   └── Layout Section (collapsible)
│       └── Width: Full / Half / Third (radio buttons)
│
└── Footer
    ├── Duplicate button
    └── Delete button (red)
```

### Options Editor UI

```
┌─────────────────────────────────────┐
│ Options                             │
├─────────────────────────────────────┤
│ ⋮⋮ [Option 1        ] [value1] [×] │
│ ⋮⋮ [Option 2        ] [value2] [×] │
│ ⋮⋮ [Option 3        ] [value3] [×] │
│                                     │
│ [+ Add Option]                      │
│                                     │
│ ☐ Allow "Other" option              │
└─────────────────────────────────────┘
```

---

## Form Settings & Multi-Page Wizard

### Form Settings Panel (shown when no field selected)

```
FormSettingsComponent (in PropertySidebar)
├── Form Details Section
│   ├── Form title input
│   ├── Form description textarea
│   └── Form header background color picker
│
├── Submit Button Section
│   ├── Button text input (default: "Submit")
│   ├── Button alignment (left/center/right)
│   └── Button style (primary/secondary)
│
├── Thank You Page Section
│   ├── Mode: Message / Redirect (radio)
│   ├── Thank you message textarea
│   ├── OR Redirect URL input
│   └── Show submission summary toggle
│
└── Wizard Settings Section (if multi-page)
    ├── Show progress bar toggle
    ├── Progress style: Steps / Bar / Percentage
    ├── Allow back navigation toggle
    └── Validate before next toggle
```

### Multi-Page Tabs UI

```
┌──────────────────────────────────────────────────────┐
│ [Page 1 ▼] │ [Page 2 ▼] │ [Page 3 ▼] │ [+]          │
└──────────────────────────────────────────────────────┘
     ↓ Click shows context menu:
     ┌─────────────┐
     │ Rename      │
     │ Duplicate   │
     │ Delete      │
     └─────────────┘
```

### Progress Bar (in generated output)

```
Step 1 of 3: Contact Info
[████████░░░░░░░░░░░░░░░░] 33%

   ○─────●─────○
 Page 1  Page 2  Page 3
```

### Wizard Data Structure

```json
{
  "wizard_settings": {
    "enabled": true,
    "show_progress": true,
    "progress_style": "steps",
    "allow_back": true,
    "validate_on_next": true
  }
}
```

---

## Stimulus Controller Architecture

### Controller Definition

```javascript
// page_builder_controller.js
export default class extends Controller {
  static targets = [
    // Layout
    "sidebar", "canvas", "propertySidebar",
    // Toolbar
    "pageTitle", "entitySelector", "viewportBtn", "undoBtn", "redoBtn", "saveBtn",
    // Sidebar
    "searchInput", "fieldCategory", "entityFields",
    // Canvas
    "pageTabs", "formPreview", "fieldsContainer", "dropZone", "emptyState",
    // Property Sidebar
    "propertyForm", "fieldTypeLabel", "fieldSlug",
    "optionsEditor", "conditionBuilder", "formSettings"
  ]

  static values = {
    pageId: Number,
    customerId: Number,
    configuration: Object,
    activePage: { type: String, default: "page_1" },
    selectedField: String,
    isDirty: { type: Boolean, default: false },
    viewport: { type: String, default: "desktop" }
  }
}
```

### Key Methods

| Category | Methods |
|----------|---------|
| **Lifecycle** | `connect()`, `disconnect()`, `initializeState()` |
| **Field Management** | `addField()`, `selectField()`, `deselectField()`, `deleteField()`, `duplicateField()`, `reorderFields()` |
| **Drag & Drop** | `dragStart()`, `dragOver()`, `dragLeave()`, `drop()`, `dragEnd()` |
| **Property Sidebar** | `showPropertySidebar()`, `hidePropertySidebar()`, `updateFieldProperty()` |
| **Options Editor** | `addOption()`, `removeOption()`, `reorderOptions()`, `updateOption()` |
| **Conditions** | `addCondition()`, `updateCondition()`, `removeCondition()` |
| **Multi-Page** | `addPage()`, `switchPage()`, `renamePage()`, `deletePage()`, `reorderPages()` |
| **Form Settings** | `updateFormSettings()`, `updateWizardSettings()` |
| **History** | `saveState()`, `undo()`, `redo()` |
| **Persistence** | `save()`, `markDirty()` |
| **Viewport** | `setViewport()` |

### Event Flow

```
User clicks field in canvas
  → selectField(fieldId)
    → Highlight field card
    → showPropertySidebar()
    → populatePropertyForm(field)

User edits property
  → updateFieldProperty(event)
    → Update field in configuration
    → Re-render field card
    → markDirty()

User clicks Save
  → save()
    → POST to /pages/:id/autosave
    → Update save status
```

---

## CSS Styling Consistency

### Design Tokens (matching Anysys)

```ruby
# app/components/concerns/design_tokens.rb
module DesignTokens
  # Colors (same as Anysys)
  PRIMARY = "indigo-600"
  PRIMARY_HOVER = "indigo-700"
  PRIMARY_LIGHT = "indigo-50"
  SECONDARY = "gray-600"
  BORDER = "gray-200"
  BORDER_DARK = "gray-300"
  TEXT = "gray-900"
  TEXT_MUTED = "gray-500"
  TEXT_LIGHT = "gray-400"
  ERROR = "red-600"
  SUCCESS = "green-600"

  # Spacing
  SPACING_XS = "1"
  SPACING_SM = "2"
  SPACING_MD = "4"
  SPACING_LG = "6"

  # Border radius
  ROUNDED_SM = "rounded"
  ROUNDED_MD = "rounded-md"
  ROUNDED_LG = "rounded-lg"

  # Shadows
  SHADOW_SM = "shadow-sm"
  SHADOW_MD = "shadow-md"
  SHADOW_XL = "shadow-xl"

  # Ring (focus)
  RING = "ring-1 ring-gray-200"
  RING_FOCUS = "focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
end
```

### Component Classes (matching Anysys property editor)

```ruby
# app/components/concerns/component_classes.rb
module ComponentClasses
  # Buttons
  BTN_PRIMARY = "px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 " \
                "border border-transparent rounded-md shadow-sm " \
                "hover:bg-indigo-700 focus:outline-none focus:ring-1 " \
                "focus:ring-indigo-600 transition-colors"

  BTN_SECONDARY = "px-3 py-1.5 text-sm font-medium text-gray-700 bg-white " \
                  "border border-gray-300 rounded-md shadow-sm " \
                  "hover:bg-gray-50 focus:outline-none focus:ring-1 " \
                  "focus:ring-indigo-500 transition-colors"

  BTN_DANGER = "px-3 py-1.5 text-sm font-medium text-red-600 bg-white " \
               "border border-gray-300 rounded-md shadow-sm " \
               "hover:bg-red-50 hover:border-red-300 transition-colors"

  # Inputs
  INPUT = "w-full px-3 py-2 text-sm border border-gray-300 rounded-md " \
          "shadow-sm placeholder:text-gray-400 focus:outline-none " \
          "focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"

  # Labels
  LABEL = "block text-sm font-medium text-gray-700 mb-1"
  LABEL_OPTIONAL = "text-gray-400 font-normal"

  # Sidebar
  SIDEBAR = "bg-white border-l border-gray-200 flex-shrink-0"
  SIDEBAR_HEADER = "flex items-center justify-between px-4 py-3 " \
                   "border-b border-gray-200 bg-gray-50"
  SIDEBAR_BODY = "flex-1 overflow-y-auto p-4 space-y-4"
  SIDEBAR_FOOTER = "flex items-center justify-between gap-2 px-4 py-3 " \
                   "border-t border-gray-200 bg-gray-50"

  # Cards
  CARD = "bg-white border border-gray-200 rounded-lg shadow-sm"
  CARD_SELECTED = "ring-2 ring-indigo-500 ring-offset-2"

  # Close button
  CLOSE_BTN = "text-gray-400 hover:text-gray-600 p-1 rounded " \
              "hover:bg-gray-100 transition-colors"

  # Section header (collapsible)
  SECTION_HEADER = "w-full flex items-center justify-between px-4 py-3 " \
                   "hover:bg-gray-50 transition-colors text-left"
  SECTION_TITLE = "text-xs font-semibold text-gray-500 uppercase tracking-wider"
end
```

---

## File Structure

```
app/
├── components/
│   ├── concerns/
│   │   ├── design_tokens.rb (enhanced)
│   │   └── component_classes.rb (enhanced)
│   │
│   ├── page_builder/
│   │   ├── editor_component.rb (NEW - main container)
│   │   ├── toolbar_component.rb (NEW)
│   │   ├── sidebar_component.rb (NEW)
│   │   ├── field_category_component.rb (NEW)
│   │   ├── field_item_component.rb (NEW)
│   │   ├── entity_fields_component.rb (NEW)
│   │   ├── canvas_component.rb (REBUILD)
│   │   ├── page_tabs_component.rb (ENHANCE)
│   │   ├── form_preview_component.rb (NEW)
│   │   ├── field_card_component.rb (REBUILD)
│   │   ├── property_sidebar_component.rb (NEW)
│   │   ├── options_editor_component.rb (NEW)
│   │   ├── condition_builder_component.rb (NEW)
│   │   ├── form_settings_component.rb (NEW)
│   │   ├── flows_section_component.rb (KEEP)
│   │   └── flow_item_component.rb (KEEP)
│   │
│   └── form_fields/
│       ├── base_field_component.rb (ENHANCE)
│       ├── text_field_component.rb (KEEP)
│       ├── email_field_component.rb (KEEP)
│       ├── number_field_component.rb (KEEP)
│       ├── phone_field_component.rb (NEW)
│       ├── url_field_component.rb (NEW)
│       ├── password_field_component.rb (NEW)
│       ├── textarea_field_component.rb (KEEP)
│       ├── select_field_component.rb (ENHANCE)
│       ├── radio_field_component.rb (NEW)
│       ├── checkbox_field_component.rb (ENHANCE)
│       ├── toggle_field_component.rb (NEW)
│       ├── date_field_component.rb (KEEP)
│       ├── time_field_component.rb (NEW)
│       ├── datetime_field_component.rb (NEW)
│       ├── file_upload_field_component.rb (NEW)
│       ├── signature_field_component.rb (NEW)
│       ├── rating_field_component.rb (NEW)
│       ├── scale_field_component.rb (NEW)
│       ├── heading_element_component.rb (NEW)
│       ├── paragraph_element_component.rb (NEW)
│       ├── divider_element_component.rb (NEW)
│       ├── section_element_component.rb (NEW)
│       ├── wizard_component.rb (ENHANCE)
│       ├── form_component.rb (ENHANCE)
│       └── calculated_field_component.rb (KEEP)
│
├── javascript/controllers/
│   └── page_builder_controller.js (REBUILD)
│
├── views/pages/
│   └── _editor.html.erb (REBUILD - just renders EditorComponent)
│
└── services/
    ├── page_content_generator.rb (ENHANCE)
    ├── condition_evaluator.rb (KEEP)
    └── calculation_evaluator.rb (KEEP)
```

---

## Testing Strategy

### Test Coverage

| Test Type | Coverage |
|-----------|----------|
| **ViewComponent Specs** | All 35+ components with rendering tests |
| **Controller Specs** | PagesController actions |
| **Service Specs** | PageContentGenerator, evaluators |
| **System Specs** | Full page builder interactions (Capybara) |

### Test Examples

```ruby
# spec/components/page_builder/property_sidebar_component_spec.rb
RSpec.describe PageBuilder::PropertySidebarComponent, type: :component do
  let(:field) { { id: "field_1", label: "Email", property_type: "email" } }

  it "renders field label" do
    render_inline(described_class.new(field: field))
    expect(page).to have_field("Label", with: "Email")
  end

  it "renders options editor for select fields" do
    select_field = field.merge(property_type: "select", options: [])
    render_inline(described_class.new(field: select_field))
    expect(page).to have_css("[data-options-editor]")
  end
end
```

---

## Success Criteria

1. All ViewComponents render with consistent anysys styling
2. Property sidebar slides in/out like Anysys
3. All field types work with drag-drop
4. Options editor allows add/remove/reorder
5. Condition builder creates valid conditions
6. Multi-page wizard works with progress bar
7. Form settings customize output
8. All tests pass (RSpec)
9. No JavaScript console errors
10. Strict adherence to Rails v8 conventions

# Selection Options Feature Design

**Date:** 2026-02-24
**Status:** Approved

## Overview

When a "selection" HTML type (Dropdown, Radio, Checkbox) is selected in the Add Attribute modal, automatically expand a section to define available options for that field.

## Requirements

1. Auto-expand options section when selection type is chosen
2. Each option has: Label, Value, Default indicator
3. Dynamic add/remove option rows with "+ Add Option" button
4. Default selection logic:
   - Dropdown/Radio: Only one default allowed
   - Checkbox: Multiple defaults allowed
5. Smooth show/hide animation when HTML type changes

## UI/UX Design

### Options Section Location

Collapsible section appears directly below the "HTML Type" dropdown in the attribute modal.

### Behavior

- Hidden by default
- Automatically expands with smooth animation when Dropdown/Radio/Checkbox selected
- Automatically collapses when switching to non-selection type
- Preserves entered options if user switches types and back

### Options Row Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Selection Options                                           │
├─────────────────────────────────────────────────────────────┤
│ ☐ Default   Label [___________]   Value [___________]  [×] │
│ ☐ Default   Label [___________]   Value [___________]  [×] │
│                                                             │
│ [+ Add Option]                                              │
└─────────────────────────────────────────────────────────────┘
```

## Data Structure

### Attribute with options

```javascript
{
  name: "Status",
  name_slug: "status",
  type: "Types::String",
  html_type: "select",
  description: "...",
  validators: [...],
  options: [
    { label: "Active", value: "active", default: true },
    { label: "Inactive", value: "inactive", default: false },
    { label: "Pending", value: "pending", default: false }
  ]
}
```

### Storage

- Options array only present when `html_type` is `select`, `radio`, or `checkbox`
- Stored as JSON in the `property_schema` field alongside other attribute data
- Non-selection types have `options: null` or omit the field entirely
- Hidden form field: `attributes[N][options]` stores JSON string

## Implementation Architecture

### Files to Modify

1. **`app/views/entities/_attribute_modal.html.erb`**
   - Add collapsible options section below HTML Type dropdown
   - Section contains options container + "Add Option" button
   - Hidden by default with `hidden` class
   - Add `data-action="change->entity-form#htmlTypeChanged"` to HTML Type select

2. **`app/javascript/controllers/entity_form_controller.js`**
   - Add new Stimulus targets: `optionsSection`, `optionsContainer`
   - Add method `htmlTypeChanged()` - triggered on HTML Type select change
   - Add methods: `addOption()`, `removeOption()`, `toggleDefaultOption()`
   - Update `collectModalData()` to include options array
   - Update `buildAttributeRowHtml()` to store options in hidden field
   - Update `resetModalFields()` to clear options section

3. **`app/models/concerns/html_type_options.rb`**
   - Add helper method `selection_type?(value)` to check if a type requires options

### Selection Types

The following HTML types require options configuration:
- `select` (Dropdown)
- `radio` (Radio Buttons)
- `checkbox` (Checkboxes)

### Constants

```ruby
SELECTION_TYPES = %w[select radio checkbox].freeze
```

## Testing Considerations

- Test show/hide behavior when changing HTML types
- Test single vs multiple default selection logic
- Test options preservation when switching types
- Test form submission with options data
- Test attribute row displays options correctly

# HTML Type Configuration Feature Design

**Date:** 2026-02-24
**Status:** Approved

## Overview

Extend the attribute modal to show type-specific configuration sections for HTML types that need additional properties beyond basic validators. This builds on the existing selection options feature by generalizing it to support multiple configuration types.

## Scope

**HTML types requiring configuration:**

| Type Category | HTML Types | Configuration Properties |
|---------------|------------|-------------------------|
| Selection | select, radio, checkbox | options array (label, value, default) |
| Numeric | number, range | min, max, step |
| Textarea | textarea | rows |
| File | file | accept (file types), multiple |

**Types without configuration:** text, password, hidden, date, time, datetime-local, email, tel, url, color

## UI/UX Design

### Single Generic Config Section

One collapsible section that shows/hides based on HTML type selection. Content changes dynamically based on type category.

### Configuration Layouts

**Selection types (select, radio, checkbox):**
```
┌─────────────────────────────────────────────────────────────┐
│ Selection Options                                           │
├─────────────────────────────────────────────────────────────┤
│ ☐ Default   Label [___________]   Value [___________]  [×] │
│ [+ Add Option]                                              │
└─────────────────────────────────────────────────────────────┘
```

**Numeric types (number, range):**
```
┌─────────────────────────────────────────────────────────────┐
│ Numeric Settings                                            │
├─────────────────────────────────────────────────────────────┤
│ Min [_______]   Max [_______]   Step [_______]              │
└─────────────────────────────────────────────────────────────┘
```

**Textarea:**
```
┌─────────────────────────────────────────────────────────────┐
│ Textarea Settings                                           │
├─────────────────────────────────────────────────────────────┤
│ Rows [_______]                                              │
└─────────────────────────────────────────────────────────────┘
```

**File upload:**
```
┌─────────────────────────────────────────────────────────────┐
│ File Upload Settings                                        │
├─────────────────────────────────────────────────────────────┤
│ Accepted Types [________________________] (e.g., .pdf,.jpg) │
│ ☐ Allow multiple files                                      │
└─────────────────────────────────────────────────────────────┘
```

## Data Structure

### Unified Config Object

All type-specific configuration stored in a `config` object:

```javascript
// Selection type
{
  name: "Status",
  html_type: "select",
  config: {
    options: [
      { label: "Active", value: "active", default: true },
      { label: "Inactive", value: "inactive", default: false }
    ]
  }
}

// Numeric type (number or range)
{
  name: "Quantity",
  html_type: "number",
  config: {
    min: 0,
    max: 100,
    step: 1
  }
}

// Textarea
{
  name: "Description",
  html_type: "textarea",
  config: {
    rows: 5
  }
}

// File upload
{
  name: "Document",
  html_type: "file",
  config: {
    accept: ".pdf,.doc,.docx",
    multiple: true
  }
}

// Types without config
{
  name: "Email",
  html_type: "email",
  config: null
}
```

### Migration from options to config

Existing attributes with `options` field will be migrated to `config.options` structure.

## Implementation Architecture

### Files to Modify

1. **`app/models/concerns/html_type_options.rb`**
   - Add `CONFIG_TYPES` constant mapping config category to HTML types
   - Add `configurable_type?(value)` helper
   - Add `config_type_for(value)` helper

2. **`app/views/entities/_attribute_modal.html.erb`**
   - Rename `optionsSection` to `configSection`
   - Add config content containers for each type category
   - Show/hide appropriate container based on HTML type

3. **`app/javascript/controllers/entity_form_controller.js`**
   - Rename targets: `configSection`, `selectionConfig`, `numericConfig`, `textareaConfig`, `fileConfig`
   - Update `htmlTypeChanged()` to show appropriate config container
   - Add config collection methods: `getSelectionConfig()`, `getNumericConfig()`, `getTextareaConfig()`, `getFileConfig()`
   - Update `collectModalData()` to build unified config object
   - Update storage/extraction to use `config` instead of `options`

### Configuration Type Constants

```ruby
CONFIG_TYPES = {
  selection: %w[select radio checkbox],
  numeric: %w[number range],
  textarea: %w[textarea],
  file: %w[file]
}.freeze
```

### JavaScript Constants

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

## Backward Compatibility

- Existing attributes with `options` field must continue to work
- Migration: `options` → `config.options` during extraction
- Storage always uses new `config` format

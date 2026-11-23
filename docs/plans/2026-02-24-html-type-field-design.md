# HTML Type Field Design

**Date:** 2026-02-24
**Status:** Approved

## Overview

Add an `html_type` field to entity attributes that specifies how the attribute should be rendered as an HTML form element. No database migration needed since attributes are stored as JSON in `property_schema`.

## HTML Types (Extended Set)

| Category | Label | Value |
|----------|-------|-------|
| **Text** | Text Input | `text` |
| | Textarea | `textarea` |
| | Password | `password` |
| | Hidden | `hidden` |
| **Selection** | Dropdown | `select` |
| | Radio Buttons | `radio` |
| | Checkboxes | `checkbox` |
| **Numeric** | Number | `number` |
| | Range Slider | `range` |
| **Date & Time** | Date | `date` |
| | Time | `time` |
| | DateTime | `datetime-local` |
| **Contact** | Email | `email` |
| | Phone | `tel` |
| | URL | `url` |
| **Other** | Color Picker | `color` |
| | File Upload | `file` |

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `app/models/concerns/html_type_options.rb` | Create | Define HTML types constant |
| `app/views/entities/_attribute_modal.html.erb` | Modify | Add HTML Type dropdown below Type field |
| `app/views/entities/_attributes_table.html.erb` | Modify | Display html_type column, add hidden input |
| `app/javascript/controllers/entity_form_controller.js` | Modify | Handle html_type in modal data and row HTML |
| `spec/models/concerns/html_type_options_spec.rb` | Create | Test the HTML types constant |

## UI Changes

### Add Attribute Modal

New dropdown field below "Type":

```
Name: [____________]
Name Slug: [auto-generated]
Type: [Dropdown: String ▼]
HTML Type: [Dropdown: Text Input ▼]  ← NEW
Validators: [...]
Description: [____________]
```

### Attributes Table

New column after Type:

```
| Name | Slug | Type | HTML Type | Validators | Description | Actions |
```

## Data Structure Change

**Before:**
```json
{
  "name": "Email",
  "name_slug": "email",
  "type": "Types::String",
  "validators": [...]
}
```

**After:**
```json
{
  "name": "Email",
  "name_slug": "email",
  "type": "Types::String",
  "html_type": "email",
  "validators": [...]
}
```

## Default Behavior

- Default `html_type` to `"text"` when not specified (backward compatible with existing data)

## Decision

Approved: Ruby constant approach selected for organizing HTML types, consistent with existing DryTypesExtractor pattern.

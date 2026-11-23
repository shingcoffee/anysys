# Attribute Actions Design

**Date:** 2026-02-24
**Status:** Approved

## Overview

Three improvements to the entity attribute UI:
1. Increase the Add Attribute modal width to prevent overflow
2. Add View (read-only modal) and Copy (pre-fill modal) actions to attribute rows
3. Inline delete confirmation replacing the immediate-remove behavior

## Task 1: Modal Width Fix

**Change:** `max-w-md` (448px) → `max-w-xl` (576px) in `_attribute_modal.html.erb`.

Selection option rows (Default checkbox + Label input + Value input + Remove button) overflow at 448px. 576px provides sufficient room without the modal feeling oversized.

**File:** `app/views/entities/_attribute_modal.html.erb`, line 14.

---

## Task 2: View and Copy Actions

### Actions Column

Both server-rendered partial and JS table builder gain two new icon buttons before the existing delete button:

- **View** (eye icon, gray): opens a read-only view modal with all attribute details
- **Copy** (duplicate icon, indigo): pre-fills the Add Attribute modal with the row's data, allowing the user to modify and add as a new attribute

The actions column width increases from `w-[10%]` to `w-[14%]` to fit three buttons.

### View Modal

A new `_attribute_view_modal.html.erb` partial added to the entity form layout. It contains:
- A backdrop + panel structure matching the Add Attribute modal style
- A `viewModalContent` Stimulus target div populated dynamically
- A close button and "Close" footer button

The controller builds the content HTML when the view button is clicked, inserting it into `viewModalContent` before showing the modal.

**Displayed fields:**
- Name + Name Slug
- Type + HTML Type
- Validators (badges)
- Config section (formatted by type: options list, numeric min/max/step, textarea rows, file accept/multiple)
- Description

**New Stimulus targets:** `viewModal`, `viewModalContent`

**New controller method:** `viewAttribute(event)`
- Extracts attribute data from the clicked row
- Calls `buildAttributeViewHtml(attribute)` to produce the content HTML
- Populates `viewModalContent` and shows `viewModal`

### Copy Action

**New controller method:** `copyAttribute(event)`
- Extracts attribute data from the row via `extractAttributeFromRow`
- Calls `prefillModalWithAttribute(attribute)` to populate all modal fields
- Shows the Add Attribute modal

**New controller method:** `prefillModalWithAttribute(attribute)`
- Sets modalName, modalNameSlug, modalType, modalHtmlType, modalDescription
- Calls `htmlTypeChanged()` to show the correct config section
- Populates config inputs based on config type:
  - selection: inserts option rows via existing option row builder
  - numeric: sets configMin, configMax, configStep
  - textarea: sets configRows
  - file: sets configAccept, configMultiple

---

## Task 3: Inline Delete Confirmation

Replace the immediate `removeAttribute` action on the delete button with `confirmRemoveAttribute`.

### Behavior

**First click (pending state):**
- Store original button HTML in `data-original-html`
- Replace button content with inline confirm/cancel buttons:
  ```
  [✓]  [✗]
  ```
- Set `data-confirm-pending="true"` on the button

**Confirm click (✓):**
- Call existing `removeAttribute` remove logic (row removal + empty state + sync)

**Cancel click (✗):**
- Restore original button HTML from `data-original-html`
- Remove `data-confirm-pending`

**Auto-cancel on outside click:** If user clicks anywhere outside the row while a confirmation is pending, cancel it (via document click listener in the controller, or data-action on the backdrop).

### Controller Changes

- Rename `removeAttribute` → keep as internal method `doRemoveAttribute`
- New `confirmRemoveAttribute(event)` as the action handler
- Both the server-rendered partial and JS table builder use `confirmRemoveAttribute` as the action

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/views/entities/_attribute_modal.html.erb` | Change `max-w-md` to `max-w-xl` |
| `app/views/entities/_attribute_view_modal.html.erb` | New file: view modal partial |
| `app/views/entities/_attributes_table.html.erb` | Add view/copy buttons; update delete action; widen actions column |
| `app/javascript/controllers/entity_form_controller.js` | Add targets, viewAttribute, copyAttribute, prefillModalWithAttribute, buildAttributeViewHtml, confirmRemoveAttribute; update buildAttributeRowHtml |

---

## Data Flow

```
View click
  → viewAttribute(event)
  → extractAttributeFromRow(row)
  → buildAttributeViewHtml(attribute)
  → populate viewModalContent + show viewModal

Copy click
  → copyAttribute(event)
  → extractAttributeFromRow(row)
  → prefillModalWithAttribute(attribute)
    → set all modal field values
    → htmlTypeChanged() → showConfigSection
    → populate config inputs
  → show modal (openModal equivalent without event)

Delete click (first)
  → confirmRemoveAttribute(event)
  → pending state: swap button to confirm/cancel

Delete confirm click
  → confirmRemoveAttribute(event)
  → doRemoveAttribute: row.remove() + sync

Delete cancel click
  → confirmRemoveAttribute(event)
  → restore original button HTML
```

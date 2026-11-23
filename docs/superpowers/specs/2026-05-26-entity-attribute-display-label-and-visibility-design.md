# Entity Attribute Modal — Display Label & Visibility

**Date:** 2026-05-26
**Surface:** `/:cid/admin/maintenance/entities/new` (and `/:cid/admin/maintenance/entities/:id/edit`)
**Modal partial:** `app/views/admin/maintenance/entities/_attribute_modal.html.erb`

## Goal

Add two fields to the "Add / Edit Attribute" modal so customer admins can declare a human-friendly label and per-audience visibility for each attribute.

## Field placement

Modal field order (top to bottom):

1. Name *(unchanged)*
2. **Display Label** *(new — required)*
3. Name Slug *(unchanged, auto-generated, read-only)*
4. HTML Type *(unchanged)*
5. Config section *(unchanged)*
6. Validators *(unchanged)*
7. **Visibility** *(new — three checkboxes, all checked by default)*
8. Description *(unchanged)*

## Display Label behavior

- Required, free text.
- Auto-mirrors the Name field as the user types — same UX as Name Slug, but editable.
- The first time the user types directly into Display Label, mirroring stops (sticky flag `dataset.manuallyEdited = "true"`).
- On modal close / reset, the value clears and the manuallyEdited flag clears, so the next open starts fresh.
- On Edit / Copy of an existing attribute, the saved `display_label` pre-fills and is treated as already-edited (mirroring stays off until the user clears the field).

## Visibility behavior

- Three checkboxes inline: Admin, Member, Public.
- All three default to checked when adding a new attribute.
- No "must check at least one" rule — empty visibility is allowed and means the attribute is hidden from every audience. (Matches the user's literal spec; consumers can decide how to render the all-off case.)

## Persisted shape

Each entry inside `entity.property_schema` (a JSON column already permitted in `entity_params`) gains two keys:

```json
{
  "name": "Email",
  "name_slug": "email",
  "display_label": "Email Address",
  "html_type": "email",
  "validators": [],
  "visibility": { "admin": true, "member": true, "public": true },
  "description": "...",
  "config": null
}
```

- `display_label` — string, required for new/edited attributes via the modal. For legacy rows that don't have it, render falls back to `name`.
- `visibility` — object of booleans with three fixed keys. Legacy rows missing the key are treated as `{ admin: true, member: true, public: true }` so existing entities are not silently hidden.

## Backend impact

None required.

- `params.require(:entity).permit(..., :property_schema, ...)` already allows the schema through as a JSON blob.
- `EntityEntryContract.build_for(entity)` only reads `name_slug` and `validators` from each schema entry, so the new keys ride through untouched.
- Member/public surface filtering by `visibility` is **out of scope** for this change — this change adds the storage and the editing UI only.

## Files to change

### Markup
- `app/views/admin/maintenance/entities/_attribute_modal.html.erb`
  - Add Display Label input below Name.
  - Add Visibility block (label + 3 checkboxes) above the Description block.
- `app/views/admin/maintenance/entities/_attributes_table.html.erb`
  - Add **Display Label** column after Name Slug.
  - Add **Visibility** column after Validators.
  - Adjust column widths so the row still totals ~100% (proposal: Name 12, Slug 12, Display Label 14, HTML Type 10, Validators 18, Visibility 12, Description 12, Actions 10).
  - Add hidden inputs for `display_label` and `visibility` (JSON-encoded) inside the actions cell.

### Stimulus orchestrator
- `app/javascript/controllers/entity_form_controller.js`
  - Register new targets: `modalDisplayLabel`, `modalVisibilityAdmin`, `modalVisibilityMember`, `modalVisibilityPublic`.
  - Extend `updateAttributeNameSlug()` to also mirror Name → Display Label (when `dataset.manuallyEdited` is not set).
  - Add action `markDisplayLabelEdited(event)` that sets the sticky flag.

### Managers
- `app/javascript/controllers/entity_form/attribute_manager.js`
  - `collectModalData()` reads `display_label` and a `visibility` object from the three checkbox targets.
  - `validateAttribute()` rejects empty `display_label` with the same red-ring + message UX as Name.

- `app/javascript/controllers/entity_form/modal_manager.js`
  - `resetModalFields()` clears Display Label, clears the manuallyEdited flag, and re-checks all three Visibility boxes.
  - `prefillModalWithAttribute()` sets Display Label (and marks it as already-edited) and sets the three Visibility checkboxes.

- `app/javascript/controllers/entity_form/schema_manager.js`
  - `extractAttributeFromRow()` reads `display_label` and parses the JSON `visibility` hidden input, with the all-true fallback for legacy data.
  - `updateAttributeRow()` writes the new fields back to row inputs and visible cells.

- `app/javascript/controllers/entity_form/template_builder.js`
  - `buildTableHtml()` adds matching `<th>`s for Display Label and Visibility.
  - `buildAttributeRowHtml()` emits the two new visible cells and the two new hidden inputs.
  - `buildAttributeViewHtml()` shows Display Label next to Name and a Visibility row showing which audiences are enabled.
  - Add small helper `buildVisibilityBadgesHtml(visibility)` that renders three pill badges, dimming the unchecked ones.

### Population from templates / template-builder
- `entity_form_controller#populateAttributesFromTemplate` — when seeding from a template, default `display_label` to the field's `name` and `visibility` to all-true.

## Tests (RSpec)

- **Request spec** `spec/requests/admin/maintenance/entities_spec.rb`
  Posting `entity[property_schema]` with one attribute that includes the two new keys round-trips them through `entity.property_schema_json`.

- **System spec** `spec/system/admin/maintenance/entities_attribute_modal_spec.rb`
  - Open modal, verify all three visibility checkboxes are checked by default.
  - Type into Name, verify Display Label and Name Slug both update.
  - Type into Display Label, then change Name — Display Label stops mirroring, Name Slug continues mirroring.
  - Uncheck Member + Public, save the attribute, verify the row in the table shows only the Admin badge and that the hidden `visibility` JSON matches.

## Out of scope

- Filtering record/page rendering by `visibility` on member or public surfaces.
- Migrations / typed columns — this lives entirely inside the existing JSON `property_schema`.
- Localization of `display_label`.

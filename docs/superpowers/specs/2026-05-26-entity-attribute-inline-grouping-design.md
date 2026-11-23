# Entity Attribute Inline Grouping — Design

**Date:** 2026-05-26
**Status:** Approved
**Surface:** `Maintenance / Entities` admin (entity edit page) and downstream consumers

## Goal

Replace the modal-driven attribute grouping with an inline, list-driven grouping experience on the entity edit page. Add full group lifecycle (create/rename/delete, with description / icon / color metadata), drag-and-drop reordering of rows and groups, and propagate groups to consumer surfaces (page builder, generators, member surface).

## Background

The current implementation (commit `23d9bc8c`) hides grouping behind a textbox in the Add/Edit Attribute modal. The modal field was wired in JS (`AttributeManager.collectModalData` reads `modalGroup`) but never rendered in the ERB, so grouping is currently dead UI. Group state today is a single `group` string per attribute, persisted inside `property_schema`. Headers and re-grouping are reconstructed in `SchemaManager.regroupAttributeRows`.

The design described here treats grouping as a first-class facet of the entity, owned by the attributes list view and visible across consumer surfaces.

## In scope

- Inline grouping UI on the attributes list (selection toolbar, kebab menu on group headers, "Move to group" dropdown).
- Group metadata: `name`, `description`, `icon`, `color`.
- Drag-and-drop:
  - Reorder attribute rows within a group.
  - Move an attribute row across groups.
  - Reorder entire groups by dragging the group header.
- Empty groups persist (with an "Empty" badge) until explicitly deleted.
- Groups visible in:
  - Entity show page (`admin/maintenance/entities/show`)
  - Page builder field picker
  - Member entity surface (`Member::EntitySurfaceBuilder`)
  - Generated form scaffolding (Reform contract groups + view organizer)
- Removal of the dead `Group` field in the Add/Edit Attribute modal.

## Out of scope

- Per-attribute drag handle on touch devices (HTML5 DnD only; touch fallback is Move-to-group dropdown).
- Permission-/visibility-scoped groups (groups are not gated by `visibility` map).
- Group templates / reuse across entities.
- Server push of grouping changes (all changes are client-side until form submit).

## Data model

### New column

Add a `jsonb` column to `entities`:

```ruby
add_column :entities, :attribute_groups, :jsonb, default: [], null: false
```

The column stores an ordered array of group objects. Order in the array = display order.

### Group object schema

```jsonc
{
  "id":          "g_8f3c2",       // string, unique-per-entity, generated client-side (nanoid-style)
  "name":        "Contact Info",  // required, non-empty after trim
  "description": "Primary contact details", // optional
  "icon":        "mail",          // one of the registered icon keys; default "folder"
  "color":       "indigo"         // one of the registered color tokens; default "slate"
}
```

Validation (in `EntitySchemaValidation`):
- `id` is a non-empty string, unique within the entity.
- `name` is present, length 1..60, unique (case-insensitive) within the entity.
- `icon` is one of `EntityAttributeGroupOptions::ICONS` keys.
- `color` is one of `EntityAttributeGroupOptions::COLORS` keys.

### Attribute schema change

Each attribute object inside `property_schema` gains an optional `group_id` key (string, nullable). The legacy `group` (name) key is dropped on write but accepted on read for one-shot migration.

```jsonc
{
  "name": "email",
  "name_slug": "email",
  "display_label": "Email",
  "html_type": "email",
  "validators": [...],
  "visibility": {...},
  "config": null,
  "group_id": "g_8f3c2"           // null/missing = ungrouped
}
```

Order within a group = order of attributes in `property_schema` filtered by `group_id`. Cross-group ordering of attributes is not meaningful (the list is reconstructed group-by-group).

### Migration of legacy `group` strings

A one-time data migration:

1. Read each entity.
2. For every distinct non-empty `attribute["group"]` value, create a group object with auto-generated `id`, `name = group_string`, default icon/color, no description.
3. Replace each attribute's `group` key with the corresponding `group_id`.
4. Persist `attribute_groups` ordered alphabetically (alphabetical is fine — production has near-zero usage given the field was UI-dead).

Idempotent: skip entities whose property_schema attributes already use `group_id`.

## Read API

A new method on `Entity`:

```ruby
def grouped_property_schema
  groups = attribute_groups_json || []
  attrs  = property_schema_json  || []
  by_id  = attrs.group_by { |a| a["group_id"].presence }

  ordered_groups = groups.map do |g|
    { group: g, attributes: by_id[g["id"]] || [] }
  end

  if (ungrouped = by_id[nil]).present?
    ordered_groups << { group: nil, attributes: ungrouped }
  end

  ordered_groups
end
```

Existing `property_schema_json` semantics are preserved — consumers that don't care about grouping keep working unchanged. Consumers that do care call `grouped_property_schema`.

## Frontend architecture

### Stimulus managers (existing pattern)

Add one new manager and adjust two existing ones:

- **`controllers/entity_form/group_manager.js`** (new) — owns:
  - selection set (Set<rowId>)
  - move-to-group dropdown lifecycle
  - inline "New group…" input
  - group rename / delete / edit-metadata via header kebab
  - reading & writing the `attribute_groups` JSON hidden input
- **`controllers/entity_form/dnd_manager.js`** (new) — owns:
  - row drag handlers (`dragstart`/`dragover`/`drop`/`dragend`)
  - group header drag (drags entire group as a unit)
  - drop indicator element rendering
  - calls back into `SchemaManager.moveRowTo(...)` / `moveGroupTo(...)`
- **`controllers/entity_form/schema_manager.js`** — modifications:
  - `regroupAttributeRows` reads order from `attributeGroupsTarget` (the new hidden input) instead of inferring from row data.
  - New `moveRowTo(rowEl, { groupId, beforeRow })` mutates DOM, syncs row's `data-attr-group-id` and hidden `group_id` input, then calls `regroupAttributeRows` + `syncPropertySchema`.
  - New `moveGroupTo(groupId, beforeGroupId)` reorders the groups array, then re-renders.
  - `extractAttributeFromRow` swaps `group` → `group_id`.
  - `syncPropertySchema` writes attributes JSON; new `syncAttributeGroups` writes groups JSON.
- **`controllers/entity_form/attribute_manager.js`** — drop `canonicalizeGroup` and any `modalGroup` references.
- **`controllers/entity_form/modal_manager.js`** — drop `modalGroup` reads in reset/prefill.
- **`controllers/entity_form/template_builder.js`** — row HTML adds checkbox cell + drag grip; group header HTML adds kebab menu, color bar, icon, "Empty" badge support.

### New Stimulus targets / actions on `entity_form_controller.js`

Targets:
- `attributeGroupsInput` (hidden `<input>` for the JSON groups order)
- `groupingToolbar`, `selectionCount`, `moveToGroupMenu`, `moveToGroupBtn`
- `groupEditModal`, `groupEditName`, `groupEditDescription`, `groupEditIcon`, `groupEditColor`

Actions:
- Selection: `toggleAttributeSelection`, `toggleAllAttributesInGroup`, `clearAttributeSelection`
- Move-to-group: `openMoveToGroup`, `chooseGroup`, `startNewGroupInline`, `commitNewGroupInline`, `cancelNewGroupInline`
- Group header kebab: `openGroupMenu`, `editGroup`, `deleteGroup`, `renameGroupInline`
- Group edit modal: `openGroupEditModal`, `closeGroupEditModal`, `saveGroupEdit`
- DnD: `dragStartRow`, `dragStartGroup`, `dragOverRow`, `dragOverGroupHeader`, `drop`, `dragEnd`

## Server-side changes

### Model

- `Entity` adds `json_attribute :attribute_groups, default: []`.
- `Entity#grouped_property_schema` (above).
- `Entity#data_fields` and `Entity#calculated_fields` are unchanged (still flat lists).

### Validation

`EntitySchemaValidation` extended:
- Validates each group object's shape (id/name/icon/color).
- Validates uniqueness of `id` and `name` (case-insensitive).
- Validates each attribute's `group_id` references an existing group (or is null).

### Reform contract

`Maintenance::Entities::Contract` (the `:edit` / `:create` contracts under `app/concepts/maintenance/entities/`) gains `property :attribute_groups`. Strong params in `Admin::Maintenance::EntitiesController` permits `attribute_groups: [:id, :name, :description, :icon, :color]`.

### View

`app/views/admin/maintenance/entities/_attributes_table.html.erb` is restructured:

```
- selection toolbar (hidden until selection > 0)
- table
  - per-group section:
    - group header row (color bar, drag grip, chevron, icon, name, count, description, kebab)
    - attribute rows (color bar, checkbox, drag grip, existing columns, actions)
  - if any ungrouped attributes: ungrouped header (no color bar) + rows
- hidden attribute_groups JSON input
- Group Edit modal (rendered once)
```

The existing `_attribute_modal.html.erb` is updated to remove any group hint (it currently has none in the ERB but references exist in JS).

A new helper module `EntityAttributeGroupingHelper` provides:
- `attribute_group_color_classes(color, variant: :bar | :text | :icon)` — maps token → tailwind classes.
- `attribute_group_icon(icon_key, css_class:)` — renders inline SVG.
- `iterate_grouped_attributes(entity) { |group, attributes| ... }` — server-side equivalent of `regroupAttributeRows`.

A new constants module `EntityAttributeGroupOptions`:

```ruby
module EntityAttributeGroupOptions
  ICONS = {
    "folder"   => :folder,
    "user"     => :user,
    "briefcase"=> :briefcase,
    "map-pin"  => :map_pin,
    "mail"     => :mail,
    "phone"    => :phone,
    "calendar" => :calendar,
    "tag"      => :tag,
    "settings" => :settings,
    "bell"     => :bell,
    "link"     => :link,
    "file"     => :file
  }.freeze

  COLORS = %w[slate indigo sky teal emerald amber rose violet].freeze

  DEFAULT_ICON  = "folder"
  DEFAULT_COLOR = "slate"
end
```

(Used by both the server form rendering and the JS via `data-*` attributes on a `<template>` block, so JS doesn't hardcode tailwind class lists.)

## Consumer surfaces

### Entity show page

`app/views/admin/maintenance/entities/show.html.erb` already calls `_attributes_table` partial with `editable: false`. The grouped rendering needs to work in read-only mode (no checkboxes, no kebab, no DnD), but headers + color bars + descriptions are rendered. Add a `grouping: true` local that renders headers; selection/edit affordances are conditional on `editable`.

### Page builder field picker

`composite_page_renderer` and `page_field_populator` currently iterate `property_schema_json` flat. Update both to call `grouped_property_schema` and emit grouped sections in the field picker. Backwards compatible because the unsplit list is recoverable as `grouped.flat_map { _1[:attributes] }`.

### Member surface

`Member::EntitySurfaceBuilder` filters by `visibility.member` and renders attribute fieldsets. Add a `groups` key to the surface output:

```ruby
{
  groups: [
    { name: "Contact Info", description: "...", icon: "mail", color: "indigo",
      attributes: [...] },
    { name: nil, attributes: [...] }   # ungrouped, last
  ]
}
```

The member view is updated to render a `<fieldset>` per group with the group name as `<legend>`. Empty groups are skipped on the member side (no value in showing them).

### Code generators

- `ContractGenerator` does not need to change shape; groups are presentation, not validation.
- `ModelGenerator` does not need to change shape.
- `EntityFieldOrganizer` adds a `grouped_organized_fields` returning `[{group, fields}]`. Used by generated view scaffolding to render `<fieldset>` per group.

## UX (summary — full mock in conversation)

- **Selection toolbar**: sticky bar above table; appears when selection > 0; shows count + "Move to group ▾" + "Clear selection".
- **Group header row**: 4px colored left bar, drag grip, chevron, icon, name, count, truncated description, kebab menu.
- **Attribute row**: 4px muted color bar (group color at 30%), checkbox, drag grip, existing columns, actions.
- **Ungrouped section**: no color bar. Header still has chevron + count.
- **Move-to-group dropdown**: each option leads with the group's color bar + icon. "Ungrouped" + "New group…" at bottom. "New group…" expands inline with name input only; description/icon/color are set via Edit group later.
- **Edit group modal**: name (required), description, icon picker (4×3 grid), 8-color palette.
- **DnD**: HTML5 native. Drop indicator = 2px accent line at insertion point.

Color palette: `slate`, `indigo`, `sky`, `teal`, `emerald`, `amber`, `rose`, `violet` — 500 weight for headers, /30 alpha for attribute row bars.

## Persistence flow

```
load:
  Entity.attribute_groups_json  -> attributeGroupsInput value (JSON)
  Entity.property_schema_json   -> per-row hidden inputs (existing) + data-attr-group-id

mutate (any of: select, move, dnd, rename, delete, edit metadata):
  group_manager / dnd_manager updates DOM and hidden inputs
  schema_manager.syncPropertySchema rewrites attributes JSON
  schema_manager.syncAttributeGroups rewrites groups JSON

submit:
  controller params permit attribute_groups + property_schema
  Reform contract validates both
  Save activity persists Entity#attribute_groups + Entity#property_schema atomically
```

## Failure modes

- **Group referenced by attribute but missing from groups list**: server validation rejects.
- **Duplicate group name**: server validation rejects.
- **Duplicate group_id from JS**: validation rejects (defense-in-depth; UI generates IDs).
- **Reordering during edit while another tab saved**: last-write-wins; we don't add optimistic locking now.
- **Empty groups on save**: persisted; `EntitySchemaValidation` allows empty groups.

## Testing

### Model & contract specs
- `entity_spec.rb`: `grouped_property_schema` returns ordered groups + ungrouped tail; legacy `group` string still parseable.
- `entity_schema_validation_spec.rb`: rejects duplicate group ids/names, missing icon/color, dangling `group_id`.
- `maintenance/entities/contract_spec.rb`: accepts/rejects group payloads.

### Helper specs
- `entity_attribute_grouping_helper_spec.rb`: header HTML, color classes, icon rendering, iteration order, empty-group handling.

### Request specs
- `maintenance/entities_spec.rb`: PATCH with `attribute_groups` + grouped attributes round-trips.

### System specs (NEW)
- `entities_attribute_grouping_spec.rb`:
  - Select rows → Move to group → New group → name → assert rows in new group, header rendered.
  - Edit group → set description/icon/color → assert color bar / icon update.
  - Delete group → members move to ungrouped, group disappears.
  - Drag row to other group → assert membership change.
  - Drag group header → assert ordering change.
  - Save → reload → assert groups + member order persisted.
  - Empty group → save → reload → group still rendered with "Empty" badge.

### Migration spec
- `data_migration_spec.rb` for the legacy-group migration: idempotent, preserves ordering.

### Consumer specs
- `composite_page_renderer_spec.rb` covers grouped field rendering.
- `member/entity_surface_builder_spec.rb` covers grouped surface output.

## Rollout

Single PR merged to `master` (per project policy). No feature flag — UI is internal admin only and the change is reversible by reverting.

1. Migration: add column, run data migration in same release.
2. Model + validation + helper.
3. Stimulus managers + view restructure.
4. Consumer-surface updates.
5. Specs (system spec last, after the JS surface stabilizes).

# Entity Display Label — Design Spec

**Date:** 2026-07-18
**Surface:** Entity creation/editing and all human-facing entity name displays
**Audience:** admin, platform owner
**Status:** implementation-ready

---

## 1. Goal

When an entity is created, besides the `name` field, admins can provide a separate **Display Label**. The Display Label auto-populates from `name` unless the user manually edits it. All human-facing surfaces that currently show the entity name should use the Display Label instead, while internal/technical uses (name slug, generated model code, API identifiers) continue to use `name`.

## 2. Decisions

| Decision | Choice |
|---|---|
| Storage | New database column `entities.display_label` (identity-level metadata, not versioned content). |
| Backfill | Not required — this is a fresh app and existing data may be truncated. |
| Required? | Yes, validated at the model. Defaults from `name` when blank. |
| Slug source | `name_slug` continues to derive from `name`. |
| Display scope | All human-facing UI uses `display_label` with fallback to `name`; internal uses keep `name`. |
| Auto-population | Client-side mirroring (`name → display_label`) plus server-side fallback. |

## 3. Data Model

### Migration

```ruby
class AddDisplayLabelToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :display_label, :string, null: false, default: ""
  end
end
```

### Entity Model

- Add validation: `validates :display_label, presence: true, length: { maximum: 100 }`.
- Add callback: `before_validation :default_display_label_from_name` to set `display_label = name` when blank.
- Add helper: `def display_name = display_label` for consistency with existing `display_name` patterns in `FeatureModules::Module` and `Authentication::User`.

## 4. Backend

### Controller

In `Admin::Maintenance::EntitiesController`:

- Add `:display_label` to `IDENTITY_KEYS` so it is permitted alongside `name`, `type`, `extended_model`, and `associations`.

## 5. Frontend

### Form

In `app/views/admin/maintenance/entities/_form.html.erb`:

- Add a new form group immediately below the Name field.
- Label: "Display Label" (required).
- Input: `form.text_field :display_label`, with Stimulus target `entityDisplayLabel`.

### Stimulus Controller

In `app/javascript/controllers/entity_form_controller.js`:

- Add `entityDisplayLabel` to `static targets`.
- Add a new `updateEntityDisplayLabel()` action bound to `input` on the Name field.
- Mirror `name → display_label` using the same `manuallyEdited` dataset flag already used for attribute display labels.
- Stop mirroring once the user has typed into the Display Label input.

## 6. View/Component Refactor Plan

Replace human-facing `entity.name` / `@entity.name` / `e.name` with `display_label` (or `display_name`) in:

- `app/views/admin/maintenance/entities/show.html.erb` — page heading and breadcrumb.
- `app/views/admin/maintenance/entities/index.html.erb` — table name column, versions modal name param, delete confirm message.
- `app/views/admin/maintenance/entities/edit.html.erb` — breadcrumb.
- `app/views/admin/maintenance/entities/entries.html.erb` — breadcrumb and title.
- `app/views/admin/maintenance/entities/trash.html.erb` — restored/trashed name and confirm messages.
- `app/components/entities/info_card_component.html.erb` — card header title.
- `app/helpers/application_helper.rb` — `link_to_entity` default text and `grouped_entity_options` labels.

Keep `name` for:

- `name_slug` generation and display.
- Generated model/contract code.
- JSON API identifiers/palette items where consumers expect `name`.
- Internal logs, validations, and uniqueness checks.

## 7. Testing

- **Model spec:** validate presence/max-length of `display_label`; verify default from `name`; verify `display_name`.
- **Factory:** set `display_label` from the sequence `name`.
- **Request spec:** create/update an entity with `display_label`; assert the stored value.
- **Component specs:** update assertions that match entity name text to use `display_label`.
- **JS spec (if exists):** verify name→display_label mirroring and manual-edit stop behavior.

## 8. Rollback / Risks

- The migration adds a column with a default value; rollback is a simple `remove_column`.
- If any consumer relies on `entity.name` for human display and is missed, the UI will still show the internal name, which is acceptable but should be caught by tests.

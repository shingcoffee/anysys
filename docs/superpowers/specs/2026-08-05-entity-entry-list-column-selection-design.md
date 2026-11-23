# Entity Entry List Column Selection — Design

**Date:** 2026-08-05  
**Status:** Draft for implementation  
**Surface:** `GET /:customer_id/admin/entities/:id` (entity entries list)

## Problem

Admins viewing an entity’s entries list get a fixed column set derived from `Entity#searchable_field_keys` (up to three string/text attributes) plus locked system columns `id`, `created_at`, and `updated_at`. Entities have different attribute schemas, so admins need to select/unselect which definition attributes appear as columns on that entity’s entries table.

## Product decisions (locked)

| Topic | Decision |
|-------|----------|
| Persistence | Per-customer + per-entity (shared for all admins of the tenant) |
| Default (no preference) | Keep today’s columns: `searchable_field_keys` + system columns |
| System columns | Always shown and locked: `id`, `created_at`, `updated_at` |
| Chooser options | All non-calculated attributes from the entity’s resolved definition (`data_fields`) |
| Attribute identity | `name_slug` (same as `EntityEntry#valid_attribute_slugs`) |
| Column labels | Prefer attribute `display_label`, fall back to `name`, then humanized slug |
| Reordering | Out of scope for v1 |
| New attributes after a preference exists | Appear in chooser **unchecked** until selected |
| Stale preference keys | Silently ignored at render time |

## Architecture overview

```
Admin::EntitiesController#show
  → resolve Entity (tenant-scoped)
  → EntityIndexSetting.for(customer_id, entity_id)
  → ColumnsBuilder.call(entity, setting) → @columns
  → listable(scope, columns: @columns)

Column picker UI (ViewComponent + Stimulus dropdown)
  → PATCH Admin::EntityIndexSettingsController#update
  → Trailblazer Activity + Reform contract
  → upsert EntityIndexSetting.config["visible_column_keys"]
  → redirect back to entity show
```

## Data model

### `entity_index_settings`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `customer_id` | bigint NOT NULL | indexed; tenant scope |
| `entity_id` | bigint NOT NULL | FK to entities |
| `config` | json NOT NULL DEFAULT `{}` | overlay blob |
| `created_at` / `updated_at` | datetime | |

Unique index: `[customer_id, entity_id]`.

### Model: `EntityIndexSetting`

Mirrors `Member::SurfaceSetting` idiom:

- `belongs_to :customer`, `belongs_to :entity`
- `json_attribute :config, default: {}`
- `self.for(customer_id:, entity_id:)` → existing row or unsaved new record
- `visible_column_keys` → array of symbols when `config` has the key (including `[]` = no attribute columns); `nil` when the key is absent (= use defaults). Do **not** coerce empty array to `nil`.
- `write_overlay(visible_column_keys:)` → writes string keys into `config`
- Cap array size in the contract (same spirit as Member settings oversized rejection)

`config` shape:

```json
{ "visible_column_keys": ["title", "status"] }
```

System column keys are never persisted. Preference stores **attribute slugs only**.

## Column resolution

New service object (e.g. `Admin::Entities::ColumnsBuilder` or `EntityEntries::IndexColumns`):

1. **System columns (always):**  
   `id`, `created_at`, `updated_at` — I18n labels from existing `admin_misc.entities.columns.*`, sortable.
2. **Attribute columns:**  
   - Candidate set = `entity.data_fields` (exclude `type == "Calculated"`), keyed by `name_slug`.  
   - If `setting.visible_column_keys` is `nil`: use today’s default attribute keys = `entity.searchable_field_keys` (intersected with candidate slugs so bad schema keys don’t leak).  
   - If preference is present: use preferred keys ∩ candidate slugs, preserving preference order (definition order as fallback for any ambiguity).  
   - Mark string/text (and any currently searchable) attributes as `searchable: true` when they remain in the visible set so Listable search does not break.  
   - Sortable: attribute columns sortable when Listable/ModuleEntriesResolver already supports sorting that key; otherwise match current behavior for searchable fields + system timestamps.
3. **Invalid sort param:** If `params[:sort]` is not in the resolved visible column keys, Listable/resolver should ignore it (no 500). Implement at the show/columns boundary if the resolver does not already.

Table cell values continue via `EntityEntry` dynamic dispatch / `AdminTableComponent` (existing path).

## Routes & authorization

Under existing admin entities nest:

```ruby
resources :entities, only: %i[index show] do
  resource :index_setting, only: :update,
           controller: "entity_index_settings"
  # existing entries nest unchanged
end
```

Path: `PATCH /:customer_id/admin/entities/:entity_id/index_setting`

- Admin URL category → existing admin `require_admin_or_owner!` (or equivalent ApplicationController / RouteAuthorization guard).
- Load entity with `Entity.for_customer(current_customer.id).find(...)`.
- Upsert setting with `customer_id: current_customer.id` only — never trust client `customer_id`.
- Members and anonymous users denied like other admin resources.
- Owner cross-tenant access follows existing admin path behavior.

## UI

### Placement

On the entity entries show page (`AdminPageComponent` `actions:`), add a **Columns** control (I18n label). Opens a dropdown/popover panel (Stimulus) containing:

- Locked, checked, disabled checkboxes for `id`, `created_at`, `updated_at` with the existing “always shown” hint pattern (`comp_admin.shared.always_shown` or a dedicated key).
- One checkbox per chooser attribute (entity-specific).
- Primary **Apply** submits the PATCH form; cancel/close dismisses without save.

Reuse visual patterns from Member surface column checkboxes where practical, but keep this control **on the list page** (not buried under Settings).

### Components

- `Admin::Entities::ColumnPickerComponent` (ViewComponent + ERB) — choices + form.
- Stimulus controller e.g. `entity_index_columns_controller.js` — open/close popover only; no user-facing string literals in JS (labels via values / server-rendered markup).
- Wire into `app/views/admin/entities/show.html.erb` via `AdminPageComponent` actions or a toolbar slot next to search if actions cannot host interactive markup — prefer page actions / a thin wrapper above `AdminTableComponent` without redesigning `AdminTableComponent` globally.

### Empty / edge UI

- Entity with zero data attributes: picker shows only locked system columns; Apply is a no-op or still persists empty attribute list.
- Many attributes: scrollable checkbox list inside the popover (`max-h` + overflow).

## Backend write path

Trailblazer Activity + Reform (thin controller):

1. Find entity (tenant-scoped) → fail → 404  
2. Build/find `EntityIndexSetting.for(...)`  
3. Contract validates:
   - `visible_column_keys` is an array of strings
   - each key must be in the entity’s current `data_fields` `name_slug` set (reject unknown keys)
   - max length cap (e.g. 100)
4. Persist `write_overlay` + save  
5. Redirect to `admin_entity_path` with success flash (I18n)

No destroy endpoint in v1; clearing all optional attributes means saving an empty attribute list (system columns remain). A “Reset to default” control is **out of scope** for v1.

## I18n

All new copy in both `en` and `zh-CN` under the appropriate area files (likely `admin_misc` / `comp_admin`):

- Columns button / panel title  
- Apply  
- Always-shown hint (reuse `comp_admin.shared.always_shown` if suitable)  
- Flash success / validation errors  

Attribute labels come from the definition, not locale files.

## Testing

- Model: `EntityIndexSetting` for/upsert, nil-vs-empty keys, tenant uniqueness  
- Columns builder: default path, preference path, stale keys ignored, calculated excluded, per-entity isolation  
- Contract/activity: accept valid slugs, reject foreign slugs, cap size, tenant scoping  
- Request: admin can PATCH and see columns change; member/anonymous denied; cross-tenant admin blocked  
- Component: renders locked system cols + entity-specific checkboxes  
- Stimulus: Vitest 100% lines/branches for the new controller  

## Out of scope

- Column reordering / drag-and-drop  
- Per-user preferences  
- Editing entity definition from this page  
- Member entry tables  
- Export/CSV column selection  
- Global `AdminTableComponent` column-picker redesign for all indexes  
- Reset-to-default button (can be a fast follow)  
- Changing `Entity#searchable_field_keys` semantics beyond using it as the no-preference default  

## Implementation notes / known debt

- `Entity#searchable_field_keys` currently maps `f["key"]` and filters `type` in `%w[string text]`, while live schema uses `name_slug` and richer type strings. Columns builder default path should intersect with real `name_slug`s so the feature does not depend on fixing that method in the same change. A follow-up may align `searchable_field_keys` with `name_slug` / html_type — **not required** for this feature if the intersection is defensive.
- Shared entities: entity load + definition already go through versionable head resolution when `Current.customer` is set; chooser must use the same resolved `property_schema` the entries use.

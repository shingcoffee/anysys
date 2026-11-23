# Entity Versioning — Design

**Date:** 2026-06-03
**Area:** Admin → Maintenance → Entities (`/:cid/admin/maintenance/entities`)
**Pattern basis:** existing `flowchart_versions` (model `FlowchartVersion`,
`Flowchart#create_version_snapshot!`, `Admin::Maintenance::FlowchartVersionsController`).

## Goal

Add versioning to entity **definitions**:

1. Every update to an entity that changes its definition creates a new version
   (always-on, for all non-bridge entities).
2. Users can diff any two versions (side-by-side) to see what changed.
3. Users can create a new version based on a specific old version ("fork from
   old"); the new version automatically becomes the **default**, and the default
   version is the entity's live definition.

## Decisions (locked)

- **Always-on** for every non-bridge entity (no per-entity toggle).
- We version the **definition**, not the data entries (`entity_entries` are
  schemaless JSON and are unaffected). The **default** version == the entity's
  live columns; forking from an old version rewrites the live definition that
  pages / entries / generators read.
- Diff presentation: **side-by-side** (version A vs version B).
- Promotion to default happens **only** via fork-from-old (append-only, linear
  history). No standalone "set as default" action.

## Non-goals / out of scope

- Versioning `entity_entries` (data records).
- Per-entity enable/disable toggle.
- Standalone "set arbitrary version as default" / delete-version UI.
- Versioning bridge entities (auto-managed; skipped).

## Data model

New table `entity_versions` (mirrors `flowchart_versions`, adds `is_default`):

| column          | type     | notes                                              |
|-----------------|----------|----------------------------------------------------|
| id              | pk       |                                                    |
| entity_id       | integer  | null: false, indexed, FK-by-convention             |
| customer_id     | integer  | null: false, indexed (multi-tenant, AGENTS.md)     |
| version_number  | integer  | null: false; unique per entity                     |
| snapshot        | text     | null: false; JSON of full definition (see below)   |
| description     | string   | nullable; e.g. "Forked from v2"                    |
| is_default      | boolean  | null: false, default false; exactly one true/entity|
| created_at/updated_at | datetime |                                              |

Indexes: `[entity_id, version_number]` unique, `[entity_id]`, `[customer_id]`,
`[entity_id, is_default]`.

**Snapshot content** (canonical hash, serialized JSON):
`name, name_slug, element_type, icon, color, description, property_schema,
default_properties, associations, attribute_groups, referenced_template`.

`EntityVersion < ApplicationRecord`:
- `belongs_to :entity`
- validates `snapshot` presence; `version_number` presence + uniqueness scope `entity_id`
- scopes: `ordered` (version_number desc), `recent` (ordered.limit(50)),
  `default_version` (where is_default: true)
- `snapshot_hash` → parsed JSON (memoized via JsonSerializable if convenient,
  else `JSON.parse`).

## Versioning behavior — `EntityVersioning` concern (included into `Entity`)

- `has_many :entity_versions, dependent: :destroy`.
- `definition_snapshot` → builds the canonical hash from current columns.
- `after_commit :record_version_if_changed, on: [:create, :update]`:
  - Skip if `bridge_entity?`.
  - On create: always create version 1.
  - On update: only if a versioned column changed (`saved_changes` intersect the
    versioned column set) AND the new `definition_snapshot` differs from the
    latest version's snapshot (guards no-op / cosmetic saves).
  - Writing `entity_versions` does not touch `entities`, so no recursion.
- `create_version_snapshot!(description: nil)` (the actual writer, mirrors
  flowchart's lock+retry approach for `version_number` uniqueness):
  - `transaction { lock! if persisted?; next = max(version_number)+1;
    entity_versions.update_all(is_default: false);
    entity_versions.create!(customer_id:, snapshot:, version_number: next,
    description:, is_default: true) }`
  - rescue `RecordNotUnique` → retry (max 3), as flowchart does.
  - Retention: delete `entity_versions.ordered.offset(50)` (newest/default kept).
- `restore_as_new_version!(source_version)`:
  - Assign the entity's columns from `source_version.snapshot_hash`
    (name, element_type, icon, color, description, property_schema,
    default_properties, associations, attribute_groups, referenced_template;
    `name_slug` is re-derived by Sluggable, not force-copied, to respect
    uniqueness).
  - Set a pending description "Forked from v#{source_version.version_number}".
  - `save!` → the `after_commit` hook records the new default version using the
    pending description. (Use an `attr_accessor :pending_version_description`
    consumed and cleared by the hook so create/update/fork share one code path.)
  - Runs inside the controller transaction; also re-syncs bridge entities like a
    normal update.

Note: name uniqueness — a fork keeps the same `name`, which is fine because it is
the same entity row being updated in place (uniqueness is scoped to customer and
excludes self).

## Diff — `Entities::VersionDiff`

`Entities::VersionDiff.call(version_a, version_b)` (PORO service, returns a value
object / hash; pure, no DB writes). Output shaped for side-by-side rendering:

- `meta`: array of `{ field, a, b, status: :same|:changed }` for the scalar
  definition fields.
- `attributes`: matched by `name_slug` (stable key). Each entry
  `{ key, status: :same|:added|:removed|:changed, a:, b:, field_changes: [...] }`
  where `field_changes` lists per-field before→after (display_label, type,
  html_type, validators, visibility, group_id, config).
- `associations`: matched by a stable key (target entity + name).
- `groups`: matched by group `id`/`name`.
- Ordering: union of keys, preserving B's order then appended A-only removed keys.

The diff is computed from the two snapshots only (works for any two versions,
including the default).

## UI (admin) — entity show page

- A **Versions** panel on `admin/maintenance/entities/show`:
  - `EntityVersionListComponent` — versions newest-first: version number,
    description, created_at (relative + tooltip), a **Default** badge on the
    current one. Two checkboxes/radio to pick A and B for compare. Each
    non-default version row shows **"Create new version from this"**.
  - A **Compare** button → renders `EntityVersionDiffComponent` (side-by-side)
    in a modal or an expandable section. Fetched via the `diff` endpoint
    (HTML partial or JSON consumed by the component).
- Stimulus controller `entity_versions_controller.js` — manage A/B selection
  (enforce two distinct selections), trigger compare (fetch + inject the diff
  HTML, or navigate to a diff view), and POST the fork action with confirm.
- Tailwind only, Stimulus only, encapsulated in ViewComponents (AGENTS.md).
- Responsive: side-by-side collapses to stacked panels on narrow screens.

## Routes & controller

Nested under the existing admin entities resource (admin Maintenance area):

```ruby
resources :entities, controller: "maintenance/entities" do
  # ...existing nested routes...
  resources :versions, only: %i[index create],
            controller: "maintenance/entity_versions" do
    collection { get :diff }   # /versions/diff?a=<n>&b=<n>
  end
end
```

`Admin::Maintenance::EntityVersionsController`:
- `before_action` admin/owner guard (same mechanism the other maintenance
  controllers use) + `find_entity` via `Entity.for_current_customer.find(...)`
  (tenant scoping; raises RecordNotFound for cross-tenant access).
- `index` → `@entity.entity_versions.recent` (HTML panel partial or JSON).
- `diff` → load versions a & b by `version_number` within `@entity`, render
  `EntityVersionDiffComponent` (HTML) or JSON.
- `create` → load source version within `@entity`, call
  `@entity.restore_as_new_version!(source)` in a transaction + bridge sync,
  redirect back to show with notice (or JSON).
- All version lookups go through `@entity.entity_versions`, so tenant isolation
  is enforced by the entity scope.

## Authorization & multi-tenancy

- URL category: **admin** (`/:cid/admin/...`) → admin or owner only; reuse the
  existing admin guard used by sibling maintenance controllers.
- `entity_versions.customer_id` set from the entity; every query scoped through
  `Entity.for_current_customer` → `entity.entity_versions`. Cross-tenant access
  to a version is impossible because the parent entity lookup 404s.

## Testing

- **Concern/model specs**: v1 created+default on entity create; new default
  version on a real definition change; prior default cleared; no version on
  no-op/cosmetic update; bridge entities never versioned; retention keeps last
  50; `restore_as_new_version!` copies snapshot into columns, creates a new
  highest+default version, keeps numbering linear, leaves entries untouched.
- **Diff service specs**: added / removed / changed attributes (by name_slug),
  association + group changes, meta scalar changes, identical versions → all same.
- **Request specs** (emphasis on auth + tenancy): index/diff/create require
  admin/owner; member forbidden; cross-tenant entity_id → 404; fork makes the
  new version default and updates the live definition.
- **Component specs**: list renders default badge + fork action; diff renders
  side-by-side with +/–/~ markers; responsive container classes present.
- Scope: this is a cross-cutting addition (new table + model concern + controller
  + routes + UI). Run the full entity-related suite plus the new specs; run the
  broader suite if model-concern changes risk regressions in entity CRUD.

## Success criteria

- Saving an entity edit produces a new default version; the prior version is
  retained and no longer default; the version list shows them newest-first.
- A no-op save (or bridge entity) creates no version.
- Comparing any two versions shows an accurate side-by-side diff.
- "Create new version from this" on an old version rewrites the live definition,
  creates a new highest version that is now default, and history stays linear.
- All version endpoints are admin/owner-only and tenant-isolated.

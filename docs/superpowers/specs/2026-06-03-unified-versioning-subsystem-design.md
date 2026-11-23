# Unified Versioning Subsystem — Design

**Date:** 2026-06-03
**Status:** Approved (scope confirmed with user)

## Goal

The Flowchart list page (`/:cid/admin/maintenance/flowcharts`) is the gold-standard
versioning experience: a **Default Version** column plus a Stimulus-driven **Versions**
modal offering lineage display, set-as-default, delete-with-default-protection,
restore-as-new, and a client-side side-by-side diff.

Bring the **Entities list** (`/:cid/admin/maintenance/entities`) and **Pages list**
(`/:cid/admin/maintenance/pages`) to full parity with that experience — and do it by
**extracting one reusable versioning subsystem** that Flowchart, Entity, and Page all
share, rather than triplicating code. The existing, divergent entity/page version UIs
are retired.

## Current state (why this is a refactor, not a greenfield build)

| | Flowchart | Entity | Page |
|---|---|---|---|
| Snapshot store | `flowchart_versions.configuration` | `entity_versions.snapshot` (derived definition hash) | `page_versions.configuration` |
| Default pointer | `flowcharts.default_version_id` (FK) | `entity_versions.is_default` (bool) | none (implicit latest) |
| Lineage | `based_on_version_id` | `based_on_version_id` | none |
| Snapshot trigger | manual-save on config change | auto `after_commit` via concern | auto on update |
| List-page UI | Default Version column + **modal** | separate list/diff ViewComponents | full-page HTML index/show |
| Diff | client-side (`version_diff.js`) | server `Entities::VersionDiff` | server `PageVersionDiff` |

The flowchart Stimulus controller and modal markup are already resource-agnostic in
substance — they are driven entirely by values passed at `open` time and a fixed JSON
contract from the server. Only the hard-coded base path and the `flowchart-versions`
identifier tie them to flowcharts.

## Target architecture

### 1. Data model (full flowchart parity for all three)

Every versioned **parent** has `default_version_id` (FK → its versions table,
`on_delete: :nullify`). Every **version row** has `based_on_version_id` (self-FK),
`version_number` (unique per parent), a JSON snapshot payload, `description`,
`customer_id`, timestamps.

Migrations:
- `add_default_version_to_entities` — add `default_version_id` FK; backfill from the
  current `is_default` version per entity.
- `drop_is_default_from_entity_versions` — remove `is_default` column + index (FK on
  parent is now the single source of truth).
- `add_default_version_to_pages` — add `default_version_id` FK; backfill to latest
  version per page.
- `add_based_on_version_to_page_versions` — add self-FK `based_on_version_id`.
- Flowcharts: already migrated — no change.

### 2. Shared model concerns

**`Versionable`** (`app/models/concerns/versionable.rb`) — included by Flowchart,
Entity, Page. Configured per model:

```ruby
acts_as_versionable version_class: "FlowchartVersion",
                     foreign_key:   :flowchart_id,
                     snapshot:      :configuration            # single-column case
# Entity uses reader/writer hooks because its snapshot spans 16 columns:
acts_as_versionable version_class: "EntityVersion",
                     foreign_key:   :entity_id,
                     snapshot_reader: :definition_snapshot_json,
                     snapshot_writer: :apply_definition_snapshot!
```

Provides: `default_version` association, `display_default_version` (explicit default
else most recent), `create_version_snapshot!(description:, based_on_version_id:)` with
the lock + retry + prune-to-50 + lineage-precedence logic, `apply_snapshot(payload)`,
and `restore_as_new!(version)` (the "Before restore" + "Restored from vN" two-snapshot
audit-trail pattern that sets the new snapshot as default).

**`VersionRecord`** (`app/models/concerns/version_record.rb`) — included by
FlowchartVersion, EntityVersion, PageVersion. Provides `based_on_version` self-assoc,
presence/uniqueness validations, `ordered`/`recent` scopes, and a uniform `payload`
accessor mapping to the underlying snapshot column (`configuration` or `snapshot`).

### 3. Shared controller

**`Admin::Maintenance::BaseVersionsController`** — abstract base implementing
`index` / `show` / `create` (restore-as-new) / `default` / `destroy`, preserving the
exact JSON contract the flowchart modal already consumes:

- index → `[{ id, version_number, description, created_at, is_default,
  based_on_version_number }]`
- show → `{ id, version_number, description, created_at, configuration }`
  (`configuration` = `payload` regardless of underlying column, so the client diff is
  uniform)
- default → PUT, sets `default_version_id`, syncs live snapshot
- destroy → blocks when version is the default (`default_version_undeletable`),
  nullifies inbound `based_on_version_id` pointers first
- create → restore-as-new via `restore_as_new!`

Overridable hooks `guard_shared_write!` and `guard_not_draft!` default to no-ops; the
flowchart subclass keeps its existing shared/draft guards.

Subclasses `FlowchartVersionsController`, `EntityVersionsController`,
`PageVersionsController` declare the parent model + finder and implement only the
resource-specific `edit` (open a version in that resource's own editor).

Routes (all three identical):
```ruby
resources :versions, only: %i[index show create edit destroy],
          controller: "maintenance/<x>_versions" do
  member { put :default }
end
```
Server `diff`/`compare`/`restore` routes removed — diff is client-side via two `show`
calls; restore is `create`.

### 4. Shared UI

- `FlowchartVersionsModalComponent` → **`VersionsModalComponent`**
  (`app/components/versions_modal_component.*`) — resource-agnostic.
- Stimulus `flowchart-versions` → **`versions`**
  (`app/javascript/controllers/versions_controller.js`). Replace hard-coded `_base()`
  with `resourceValue` so it builds
  `/${customerId}/admin/maintenance/${resource}/${parentId}/versions`. Open params
  become `versions-id-param` / `versions-name-param`.
- `app/javascript/flowchart/version_diff.js` → `app/javascript/versions/version_diff.js`.
- All three `index.html.erb` (flowcharts, entities, pages) wrap their table in
  `data-controller="versions"` with `resource` + `customer-id` values, add a
  **Versions** row action (`action: "versions#open"`, passing `id` + `name`), and render
  `VersionsModalComponent` once. Their controller `index` actions add a **Default
  Version** column (`display_default_version`) and `.includes(:default_version,
  :<x>_versions)`.

### 5. Retire

- `entity_version_list_component`, `entity_version_diff_component`,
  `entity_versions_controller.js`.
- Page version full-page HTML index/show views; `page_restorations` controller + route.
- `Entities::VersionDiff`, `PageVersionDiff` services (client diff replaces them) — and
  their specs.
- Entity's auto-snapshot `after_commit`; entities & pages adopt manual-save snapshots in
  their `create`/`update` controller actions (mirroring flowchart's "Manual save").
- Fold the bespoke `EntityVersioning` concern logic into the shared `Versionable`.

## Testing

This is a cross-cutting change touching auth, tenant scoping, and three modules →
**full RSpec suite** at the end.

- Shared examples for `Versionable` (snapshot numbering, lineage precedence, prune-to-50,
  default management, restore-as-new) and `VersionRecord` (validations, scopes, payload).
- Per-resource request specs: index/show/create/default/destroy, **multi-tenant
  isolation** (404 on foreign parent/version), **default-deletion protection**.
- One `VersionsModalComponent` component spec.
- Rewrite/remove obsolete entity & page version specs per the stale-test policy.

## Out of scope

- Changing the snapshot *content* of any resource (entity still snapshots its 16-field
  definition; page/flowchart still snapshot `configuration`).
- Member-facing or public version surfaces (admin maintenance only).
- Version history for any resource beyond Flowchart, Entity, Page.

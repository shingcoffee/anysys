# Flowchart Default Version & Version-Based Editing — Design

Date: 2026-06-03
Surface: `/:cid/admin/maintenance/flowcharts` (index) + version-history modal + Anysys editor

## Problem

On the flowchart list page the **Versions** column currently shows a raw count of
snapshots, which is not actionable. There is also no notion of a "current/default"
version, no way to promote an old version back to being the live one from the list,
and no way to open a specific historical version in the full builder editor.

This work introduces a first-class **default version** concept and a
**version-based editing** flow.

## Decisions (confirmed with user)

1. **"Set as default" = publish/restore.** Marking version `vN` as default overwrites
   the flowchart's live (executable) `configuration` with `vN`'s configuration and
   points the flowchart's `default_version_id` at `vN`. Default == the live/published
   state.
2. **Save-from-version = new version + update live.** Saving an edit in the
   version-view editor tab PATCHes the flowchart's live `configuration` AND creates a
   new version whose `based_on_version_id` points at the viewed version. The new
   snapshot becomes the new default (it is the new live state). This matches how the
   editor already behaves (save = live update + snapshot).
3. **Edit gating reused.** The version-view tab is editable only when the flowchart is
   `draft`. If the flowchart is `active`, the tab is read-only with the existing
   "Deactivate to edit" banner — identical to the normal editor.

## Data Model

### Migration 1 — `add_default_version_to_flowcharts`
- `flowcharts.default_version_id` : bigint, nullable, FK → `flowchart_versions`,
  indexed. The version currently published as the live/default definition.
- Nullable because legacy flowcharts (and brand-new ones before first save) have no
  explicit default yet.

### Migration 2 — `add_based_on_version_to_flowchart_versions`
- `flowchart_versions.based_on_version_id` : bigint, nullable, self-FK →
  `flowchart_versions`, indexed. Lineage pointer: the version this snapshot was
  derived from. Null for linear/manual saves with no explicit parent.

Both columns are nullable; no data backfill. The list column falls back to the latest
snapshot when `default_version_id` is null.

## Models

### `Flowchart`
- `belongs_to :default_version, class_name: "FlowchartVersion", optional: true`
- `display_default_version` — returns `default_version` or, if nil, the latest
  snapshot (`flowchart_versions.max_by(&:version_number)` over the preloaded
  association); used by the index column. Returns nil when there are no versions.
- `create_version_snapshot!(description: nil, based_on_version_id: nil)` — extend the
  existing method to accept `based_on_version_id`. Sanitize it: only persist the value
  if it references a version **belonging to this flowchart**
  (`flowchart_versions.exists?(id: based_on_version_id)`); otherwise store nil. This
  prevents cross-flowchart / cross-tenant lineage injection. Returns the created
  version (it already does effectively; ensure the created record is returned).

### `FlowchartVersion`
- `belongs_to :based_on_version, class_name: "FlowchartVersion", optional: true`

## Controllers

### `Admin::Maintenance::FlowchartsController#index`
- Change the `:versions_count` column to display the default version:
  - key `:default_version`, label `"Versions"`, type `:text`, not sortable/searchable
  - `cell: ->(f) { (v = f.display_default_version) ? "v#{v.version_number}" : "—" }`
- Preload to avoid N+1: scope becomes
  `Flowchart.where(customer_id: current_customer.id).includes(:entity, :default_version, :flowchart_versions)`.

### `Admin::Maintenance::FlowchartsController#update`
- After a successful update where the configuration changed:
  ```ruby
  version = @flowchart.create_version_snapshot!(
    description: "Manual save",
    based_on_version_id: params[:based_on_version_id]
  )
  @flowchart.update_column(:default_version_id, version.id)
  ```
- `update_column` is used for the pointer so it bypasses `must_be_draft_to_edit`
  (we are not changing configuration there, only the FK) and avoids re-validation.

### `Admin::Maintenance::FlowchartVersionsController`
- Routes gain `edit` (GET) and a member `default` (PUT).
- **`#edit`** — open a specific version in the full builder editor (new tab target):
  ```ruby
  @version = @flowchart.flowchart_versions.find(params[:id])
  @flowchart.configuration = @version.configuration   # in-memory override only; not saved
  @based_on_version_id = @version.id
  @editing_version = @version
  render template: "admin/maintenance/flowcharts/edit"
  ```
  No not-draft guard (read-only view is fine for active flowcharts); no shared guard
  (saving is what's guarded, via `flowcharts#update`).
- **`#default`** — publish/restore + repoint default. Guards: `guard_shared_write!`
  and `guard_not_draft!` (both already exist).
  ```ruby
  version = @flowchart.flowchart_versions.find(params[:id])
  @flowchart.transaction do
    @flowchart.update!(configuration: version.configuration)
    @flowchart.update_column(:default_version_id, version.id)
  end
  render json: { success: true, default_version_id: version.id, version_number: version.version_number }
  ```
- **`#index`** — add `is_default: v.id == @flowchart.default_version_id` to each row's
  JSON so the modal can badge the current default.
- **`#create`** (existing restore flow) — set the final "Restored from vN" snapshot as
  the new default, and tag its `based_on_version_id` with the source version:
  ```ruby
  @flowchart.create_version_snapshot!(description: "Before restore to v#{n}")
  @flowchart.update!(configuration: version.configuration)
  new_v = @flowchart.create_version_snapshot!(description: "Restored from v#{n}", based_on_version_id: version.id)
  @flowchart.update_column(:default_version_id, new_v.id)
  ```

## Routes

```ruby
resources :versions, only: %i[index show create edit],
          controller: "maintenance/flowchart_versions" do
  member { put :default }
end
```
- `GET  /:cid/admin/maintenance/flowcharts/:flowchart_id/versions/:id/edit`
- `PUT  /:cid/admin/maintenance/flowcharts/:flowchart_id/versions/:id/default`

## Views / Components

### Editor partial (`_editor.html.erb`)
- Add the based-on data attribute only when present:
  `data-flowchart-canvas-based-on-version-id-value="<%= @based_on_version_id %>"`.
- When `@editing_version` is set, render an info banner above the toolbar:
  "Editing based on v{n} — saving will create a new version." (Tailwind, indigo/info
  styling, consistent with the existing amber active banner.)

### Canvas Stimulus controller (`flowchart_canvas_controller.js`)
- Add `static values = { ..., basedOnVersionId: String }`.
- In `_saveToServer`, include it in the PATCH body only when non-empty:
  ```js
  body: JSON.stringify({
    flowchart: { configuration: JSON.stringify(configToSave) },
    ...(this.hasBasedOnVersionIdValue && this.basedOnVersionIdValue
        ? { based_on_version_id: this.basedOnVersionIdValue } : {})
  })
  ```

### Version-history modal (`flowchart_versions_controller.js` + `.html.erb`)
- **View (per row)** → open the editor in a new tab:
  `window.open(`${this._base()}/${id}/edit`, "_blank")`. Remove the in-modal canvas
  preview path (`_renderPreview` and the `FlowchartCanvas` import) — View no longer
  renders inside the modal.
- **Set as default (per row)** → `PUT ${base}/${id}/default`. On success: reload the
  list, re-badge the default row, and refresh the index turbo-frame so the Versions
  column updates. Handle 422 (not draft) and 403 (shared read-only) with the existing
  error banner.
- **Default badge** — rows where `is_default` render a small "Default" pill; the
  "Set as default" button is hidden/disabled on the already-default row.
- **Diff selected** — unchanged (still client-side, still in-modal).
- Remove the "New version from" footer button (superseded by View→edit→save and
  Set-as-default). The backend `create` endpoint stays (still used by the in-editor
  History tab restore).
- Content placeholder copy → "Select two versions to diff."

## Security / Multi-tenant

- `find_flowchart` uses `Flowchart.accessible.find` (customer-scoped + shared).
- All version lookups go through `@flowchart.flowchart_versions.find` → scoped to the
  flowchart, so cross-tenant ids 404.
- `based_on_version_id` is sanitized in the model to this flowchart's versions only.
- `#default` is guarded by `guard_shared_write!` (403 for non-owner on shared) and
  `guard_not_draft!` (422 when active).
- `#edit` renders read-only when the flowchart is active; any actual mutation flows
  through `flowcharts#update`, which keeps its own `guard_shared_write!`.

## Testing

- **Model spec** — `default_version` association; `create_version_snapshot!` sets and
  sanitizes `based_on_version_id` (foreign id stored as nil); returns created version.
- **Request spec (`flowchart_versions`)**
  - `edit` renders the editor with the version's configuration + based-on attribute;
    active flowchart → read-only.
  - `default` syncs live configuration, sets `default_version_id`, returns success;
    not-draft → 422; shared non-owner → 403; cross-tenant id → 404.
  - `index` includes `is_default`.
- **Request spec (`flowcharts#update`)** — save with `based_on_version_id` tags the new
  snapshot and promotes it to default; foreign based-on id is dropped.
- **Component spec** — modal renders Set-as-default + View(new tab) affordances; default
  badge appears for the default row.
- **Stale tests** — update the existing `flowchart_versions` request spec and
  `flowchart_versions_modal_component` spec to match the refactor (rewrite, don't
  delete).

## Out of Scope

- In-editor History tab UX (still uses the existing `create` restore endpoint; may show
  based-on lineage later).
- Any change to shared-flowchart execution semantics beyond existing guards.
- Backfilling `default_version_id` for legacy flowcharts (fallback handles display).

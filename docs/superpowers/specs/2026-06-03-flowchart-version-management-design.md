# Flowchart Version Management (List Page)

**Date:** 2026-06-03
**Status:** Approved (design)
**Surface:** `/:cid/admin/maintenance/flowcharts` (index / list page)

## Summary

Add version management to the flowchart **list page**. From a flowchart's row a
user can open a **version-history modal** that lets them:

1. **View** any past version as a read-only canvas preview.
2. **Create a new version based on a specific version** — copy a chosen
   version's configuration into a brand-new latest version of the *same*
   flowchart (current state preserved in history; flowchart now reflects the
   chosen version).
3. **Diff** two selected versions as a raw, side-by-side JSON comparison.

The versioning backend already exists (`FlowchartVersion`, `index` + restore
`create`, editor History panel). This work makes versions reachable and
actionable from the list page and adds preview + diff.

## Goals / Non-goals

**Goals**
- Reach version history from the list page without leaving it (modal).
- Read-only canvas preview of a version.
- Restore-as-new-version (always leaves an explicit version entry).
- Raw JSON side-by-side diff of any two versions.
- Preserve multi-tenant isolation and admin/owner authorization.

**Non-goals (YAGNI)**
- Version comments / tagging / naming.
- Three-way merge or branching.
- Restoring a version into a *different* flowchart (the existing Copy action
  already forks a flowchart).
- Per-element visual canvas diff (we chose raw JSON side-by-side).
- Autosave (separate concern, out of scope).

## Architecture (Approach A: modal + thin backend + client-side diff)

### Backend — `Admin::Maintenance::FlowchartVersionsController`

Route change:
```ruby
resources :versions, only: %i[index show create], controller: "maintenance/flowchart_versions"
```

- **`index`** (exists) — JSON list of recent versions (id, version_number,
  description, created_at).
- **`show`** (new, `GET …/versions/:id`) — returns
  `{ id, version_number, description, created_at, configuration }`. Scoped via
  `@flowchart.flowchart_versions.find(params[:id])` so a cross-tenant or
  foreign version id 404s. Read-only — **no** draft guard (viewing/diffing an
  active flowchart's history must work). Feeds both preview and diff.
- **`create`** (exists — restore; enhanced) — keeps `guard_shared_write!` and
  `guard_not_draft!`, then performs the **restore-as-new-version** sequence:
  1. `create_version_snapshot!(description: "Before restore to v#{n}")` — preserve current.
  2. `update!(configuration: version.configuration)` — set live config.
  3. `create_version_snapshot!(description: "Restored from v#{n}")` — explicit new latest version entry.
  Returns `{ success: true, configuration:, version_number: }`.
  The editor History "Restore" uses the same endpoint and now also leaves the
  explicit entry (unified semantics — a deliberate, approved change).
- **No diff endpoint** — the diff is computed client-side from two `show`
  payloads.

`Flowchart#create_version_snapshot!` needs **no change** — step 3 snapshots the
now-current (restored) configuration.

### Frontend

- **`FlowchartVersionsModalComponent`** (ViewComponent, Tailwind only) — modal
  shell rendered once (hidden) on the index page; parameterized at open time by
  flowchart id (passed via data attributes / Stimulus value). Regions:
  - Header (flowchart name).
  - Version list: each row has a select control, `vN`, description, timestamp,
    and a **View** button. Selecting two enables Diff; selecting one enables
    New-version-from.
  - Footer actions: **Diff selected** (requires exactly 2), **New version from**
    (requires exactly 1).
  - Content area that swaps between the **canvas preview** and the **JSON diff**.
- **`flowchart_versions_controller.js`** (Stimulus) — actions:
  - `open(flowchartId)` → `loadVersions()` (GET `index`) → render rows.
  - selection state: max 2 for diff, 1 for view / new-from; enable/disable
    footer buttons accordingly.
  - `view()` (GET `show`) → read-only canvas preview.
  - `diff()` (GET `show`×2) → `versionDiff()` → render side-by-side.
  - `newVersionFrom()` (POST `create` with `version_id`) → reload list, bump the
    row's Versions count, toast; on **422** show the existing "Cannot restore
    while active — deactivate to restore" message.
  - `close()`.
- **`version_diff.js`** — pure function: given two configuration strings,
  pretty-print each with **stable (sorted) keys** and 2-space indent, compute an
  **LCS line diff**, and return rows `{ type: "context"|"add"|"del", left, right }`
  for side-by-side rendering. No external library (importmap app, no npm build).
  Pure → unit-testable via a node harness.
- **Read-only canvas preview** — reuse `FlowchartCanvas` constructed with
  `readOnly` into the modal's SVG container; `loadConfiguration(config)` +
  render; interactions disabled (no toolbar, no editing). The version config
  comes from the `show` endpoint.
- **List page wiring** (`index.html.erb` / `AdminTableComponent`) — add a
  **"Versions"** row action and make the existing **Versions count** cell
  clickable; both trigger `flowchart-versions#open` with the flowchart id. No
  page navigation.

### Data flow

```
Open modal ──GET index──▶ version list
View   ──GET show(id)──▶ read-only canvas preview
Diff   ──GET show(a)+show(b)──▶ versionDiff() ──▶ side-by-side JSON
New-from ──POST create{version_id}──▶ (preserve + restore + snapshot) ──▶ reload list, bump count, toast
                                       └─ 422 if active/not-draft ──▶ inline message
```

### Authorization / multi-tenant

- All endpoints under `/:cid/admin/…` → admin/owner guard (RouteAuthorization).
- Versions scoped to the flowchart via `Flowchart.accessible` + nested
  `@flowchart.flowchart_versions`; foreign/cross-tenant version id → 404.
- Shared flowcharts (customer_id NULL) stay read-only except platform owner
  (`guard_shared_write!` on `create`).
- New-version-from requires the flowchart be draft/inactive (`guard_not_draft!`
  → 422 with the existing clear message).

## Components & interfaces (isolation)

| Unit | Purpose | Depends on |
|------|---------|-----------|
| `FlowchartVersionsController#show` | Return one version's config JSON | `@flowchart.flowchart_versions` |
| `FlowchartVersionsController#create` (enhanced) | Restore-as-new-version | `create_version_snapshot!`, `update!` |
| `FlowchartVersionsModalComponent` | Modal markup (list/preview/diff regions) | Tailwind, Stimulus controller |
| `flowchart_versions_controller.js` | Modal orchestration, fetches, selection | `version_diff.js`, `FlowchartCanvas` |
| `version_diff.js` | Pure JSON line-diff | none (pure) |
| read-only preview | Render a version's canvas | `FlowchartCanvas` (readOnly) |

## Testing

- **Request specs** (`spec/requests/maintenance/flowchart_versions_spec.rb`):
  - `show`: returns configuration for an own-customer flowchart's version;
    cross-tenant / foreign version id → 404; shared flowchart version visible.
  - `create` (enhanced): creates the preserve + new-latest snapshots (version
    count increases by 2, live config equals chosen version); blocked (422) when
    the flowchart is active/not-draft; blocked (403) for shared flowchart by a
    non-platform-owner.
- **Component spec**: `FlowchartVersionsModalComponent` renders the list region
  and the Diff / New-version-from action affordances.
- **JS**: `version_diff` node harness — identical configs → all context rows;
  added/removed/changed lines classified correctly; key ordering stable so
  semantically-equal configs with different key order do not show spurious diffs.
- **No system spec** (no browser in this environment) — coverage via request +
  component specs + the diff harness.

## Risks / decisions

- **Unified restore semantics** — the editor History "Restore" now also leaves
  an explicit "Restored from vN" version entry (one extra row). Approved.
  Update the existing versions request spec accordingly (stale-test policy).
- **Canvas-in-modal** — reusing the interactive `FlowchartCanvas` read-only is
  the main implementation risk; mitigated by `readOnly` mode and rendering into
  a dedicated, isolated SVG container with no toolbar wiring.
- **Active flowcharts** — New-version-from is disabled / 422-handled for active
  flowcharts; the modal still allows View and Diff (read-only) for them.

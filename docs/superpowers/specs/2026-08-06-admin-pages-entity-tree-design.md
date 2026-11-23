# Admin Pages Entity Tree — Design

**Date:** 2026-08-06  
**Status:** Approved (proceed without further confirmation)  
**Surface:** `/:customer_id/admin/pages`

## Problem

Admins manage pages that bind to entities via configuration metadata, but All Pages is a flat `AdminTableComponent` with only a dropdown filter. Entity navigation lives separately in the chrome sidebar (`PagesContributor` → `EntityPagesController`). Finding forms by data model requires hopping between chrome nodes or using the dropdown.

## Decisions (locked)

| Topic | Choice |
|--------|--------|
| Tree shape | **C** — Entity filter nodes only (no page leaves). Pages stay in the main table. |
| Chrome relationship | **C** — Unify chrome + in-page tree (same structure and URLs). |
| Empty entities | Show (even with 0 pages). |
| Orphans | **Uncategorized** group (missing/stale/null `metadata.entity_id`). |
| Mobile | Off-canvas left drawer with toggle. |
| Architecture | Single index controller; path-based selection (not query-only) so chrome active matching keeps working. |

## URL model

| Selection | URL | Behavior |
|-----------|-----|----------|
| All Pages | `/:cid/admin/pages` | Full customer page list |
| Entity | `/:cid/admin/pages/entities/:entity_id` | Same index, scoped with `Page.for_entity` |
| Uncategorized | `/:cid/admin/pages/uncategorized` | Pages with blank entity_id or entity_id not in `Entity.for_customer` |
| Legacy | `/:cid/admin/entities/:id/pages` | Redirect to `/:cid/admin/pages/entities/:id` |

All selection URLs are handled by `Admin::PagesController#index`. Chrome `PagesContributor` and the in-page left panel emit the same paths.

## Layout

### Desktop

```
AdminPageComponent (breadcrumbs, title, New Page)
┌─────────────────┬──────────────────────────────────────┐
│ Left filter tree│ AdminTableComponent                  │
│ (entities)      │ search + launch filter + columns +   │
│                 │ pagination + batch actions           │
└─────────────────┴──────────────────────────────────────┘
```

- Left panel ~220–240px, scrollable independently, border-right.
- Selected node: accent-subtle background (match `SidebarNodeComponent` active styles).
- Optional count badge per node (page counts for that selection).
- Drop the entity dropdown filter from the table (tree replaces it). Keep launch filter, search, batch actions, row actions.

### Mobile

- Table is full width.
- Entities control opens a left off-canvas drawer with the same tree component.
- Choosing a node navigates (full page load) and closes the drawer.
- Must not permanently hide the list.

## Shared tree builder

`Admin::Pages::TreeBuilder` builds an ordered list of nav items:

1. All Pages → `admin_pages_path`
2. Each `Entity.for_customer(cid).non_bridge.by_name` → entity filter path
3. Uncategorized — **only when** orphan count > 0

Each item: `{ key:, label:, path:, count:, selected: }`.

`PagesContributor` consumes the same builder (mapping to `SidebarNode`) so chrome and in-page panel cannot drift.

Bridge entities are never parents. Tenant scope: only `Entity.for_customer` / `Page.for_customer`.

## Orphan / Uncategorized semantics

A page is uncategorized when, after joining configuration content:

- `metadata.entity_id` is null/blank, **or**
- `metadata.entity_id` is not in the set of entity ids for that customer (`Entity.for_customer`)

Add `Page.uncategorized_for(customer_id)` scope. Soft-hidden pages remain excluded via `Page` default `visible` scope.

## Controller changes

`Admin::PagesController#index`:

- Resolve selection from route (`entity_id` on entity route, or uncategorized flag).
- Build `@tree` via TreeBuilder with `selected_key`.
- Apply scope: all / `for_entity` / `uncategorized_for`.
- Keep existing columns, launch filter, search, pagination, batch; remove entity dropdown filter.

`Admin::EntityPagesController#index`: redirect to unified entity URL (preserve query string where practical).

## Components

- `Admin::Pages::FilterTreeComponent` — entity nav list (ViewComponent + ERB). Used in index body (desktop aside) and mobile drawer.
- Thin Stimulus controller for mobile open/close (`pages_filter_panel_controller`). English `default:` values + server-passed I18n labels.
- Index view wraps tree + `AdminTableComponent` in a responsive flex layout.

## I18n

All new chrome/tree/empty strings in matching locale files — both `en` and `zh-CN`. No hard-coded UI strings. English values byte-identical to former literals where reusing copy (e.g. "All Pages").

## Auth & tenancy

Unchanged: admin URL requires admin/owner. Entity lookup uses `Entity.for_customer`. Cross-tenant entity id → 404. Owner under platform customer sees only the path customer’s data.

## Out of scope

- Page builder / maintenance editor UX
- New Page↔Entity FK migration (still metadata)
- Drag-and-drop reparent, entity CRUD from tree
- Page leaves in the tree
- Porting entity-entry-list right slide-over / CSV / column picker

## Testing

- TreeBuilder unit: order, bridge exclusion, counts, uncategorized inclusion/exclusion, tenant scope
- FilterTreeComponent: selected state, links, empty entities shown
- PagesContributor: paths point at unified URLs
- Request: all / entity / uncategorized / legacy redirect / auth / cross-tenant 404
- Stimulus: 100% Vitest lines+branches for any new JS
- Update existing `entity_pages` request specs for redirect behavior

## Visual reference

Mockup: brainstorm companion (`pages-entity-tree-layout.html`).

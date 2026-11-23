# Admin Pages — Chrome Tree Only (Design Amendment)

**Date:** 2026-08-06  
**Status:** Approved (Approach A / implementation approach 1)  
**Supersedes (layout only):** `2026-08-06-admin-pages-entity-tree-design.md` chrome + in-page dual tree

## Problem

`/:cid/admin/pages` shows the same entity filter twice: chrome Pages sidebar and an in-page “Entities” panel. The dual tree makes the content area cluttered and unprofessional.

## Decision

| Topic | Choice |
|--------|--------|
| Entity navigation | **Chrome left sidebar only** |
| In-page entity list | **Removed** (no FilterTree, no mobile filter drawer) |
| Page counts | Badge on each chrome sidebar node (`badge: { label: count.to_s }`) |
| Table filters | Launch only (+ search); no entity dropdown |
| URLs / selection | Unchanged path-based All / entity / uncategorized |

## Layout

### Desktop / mobile content

```
AdminPageComponent (breadcrumbs, title, New Page)
└── AdminTableComponent (search + launch filter + rows + pagination)
```

### Chrome sidebar (Pages menu)

Ordered nodes from `Admin::Pages::TreeBuilder` via `PagesContributor`:

1. All Pages — count badge = all pages  
2. Each non-bridge entity — count badge = pages for that entity  
3. Uncategorized — only when orphan count > 0 — count badge

Active highlighting remains path-based (`SidebarNodeComponent`).

## Removals

- `Admin::Pages::FilterTreeComponent` (+ spec)
- `pages_filter_panel_controller` (+ Vitest)
- Index view aside / drawer markup
- `@tree` assignment in `Admin::PagesController#index` (builder stays for chrome)
- Unused `admin_misc.pages.tree.*` locale keys

## Kept

- `Admin::Pages::TreeBuilder`
- Path routes and controller selection scopes
- Launch filter, columns, batch actions

## Copy

Update `admin_misc.pages.description` so it no longer tells users to use an in-page left tree; point at the sidebar entity list instead (en + zh-CN).

## Testing

- `PagesContributor`: each node has numeric count badge; paths unchanged
- Request: index HTML has no in-page Entities filter panel / `pages-filter-panel`; still lists pages; entity/uncategorized paths still scope
- Delete FilterTree / Stimulus specs with their sources
- Vitest suite stays at 100% after JS removal

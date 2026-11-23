# Admin page render link — UX spec

**Date:** 2026-10-21 · **Status:** READY_FOR_FRONTEND

**Goal:** From `/81721200/admin/pages`, open a listed, launched page in the existing backend dashboard layout. The same behavior applies in any visited customer context.

## 1. Surface inventory and reuse

| Surface | Navigation area | Existing implementation |
| --- | --- | --- |
| Forms list: `/:cid/admin/pages`, entity-filtered and uncategorized variants | admin | `AdminPageComponent`, `Admin::Pages::OpsTableComponent`, `Admin::Pages::AudienceReachComponent`, `Admin::PaginationComponent` |
| Destination: `/:cid/admin/maintenance/pages/:id/render` | admin | `Admin::Maintenance::PageRendersController#show`, dashboard layout, `BreadcrumbsComponent`, existing rendered-content card |

Audience: authorized customer admins and the platform owner. Extend the existing per-row kebab dropdown; no new component, controller, modal, or UI surface is needed.

Design reference: [shadcn/ui Dropdown Menu](https://ui.shadcn.com/docs/components/dropdown-menu), consulted by the parent and during this handoff. Adapt its trigger → content → item pattern through the project's existing ViewComponent/Tailwind/Stimulus implementation. The shadcn plugin/skill and brainstorming/writing-plans skills are unavailable in this harness; these artifacts capture the settled design and implementation handoff.

## 2. Layout and wording

In **both** the mobile card (`sm:hidden`) and desktop/tablet table (`hidden sm:block`), insert the new secondary navigation item **immediately after Preview**:

```text
Manage access                         ⋮
                             ┌───────────────────┐
                             │ Preview           │
                             │ Open in admin     │  eligible pages only
                             │ Take Offline      │  Launch for drafts
                             └───────────────────┘
```

The row continues to show `page.name`, the existing entity subtitle, audience reach from `visible_audiences`, status from `launched?`, and relative `updated_at`. Manage access remains the inline action; Preview and launch/take-offline retain their positions and behavior around the added item.

| Wording | Key | English | Simplified Chinese | Decision |
| --- | --- | --- | --- | --- |
| New item | `admin_misc.pages.open_in_admin` | `Open in admin` | `在后台打开` | Add to `config/locales/admin_misc.en.yml` and `config/locales/admin_misc.zh-CN.yml` |
| Preview | `maint_core.pages.preview` | `Preview` | `预览` | Reuse the current key |

Inspection found no existing exact `Open in admin` label. `comp_misc.distribution.open` is `Open` / `打开` and depends on an adjacent audience heading; the standalone dropdown item needs its own audience-specific key. Render translations at call time with `t(...)`.

## 3. Availability and navigation contract

| Page state | Open in admin | Preview |
| --- | --- | --- |
| Launched, `visible_to?(:admin)` true | Show | Show |
| Draft/offline | Omit | Show, including draft preview |
| Launched, `visible_to?(:admin)` false | Omit | Preserve existing Preview |

Use **`page_row.launched? && page_row.visible_to?(:admin)`**, not `visibility == "admin"`. All valid visibility levels (`admin`, `member`, `public`) include the admin audience; unknown stored visibility fails closed.

- Destination helper: `helpers.admin_maintenance_page_render_path(customer_id, page_row)` in `OpsTableComponent`, using its existing `customer_id` prop from `current_customer.id`.
- For owned and shared pages, preserve the visited `:cid`; a shared page's NULL `customer_id` must never supply the URL tenant. The owner visiting another customer also keeps that customer's prefix. Shared rendering resolves that customer's effective definition.
- Link attributes match Preview exactly: `target="_blank"`, `rel="noopener noreferrer"`, `data-turbo-frame="_top"`. Use a normal GET link.
- Outcome: a full dashboard document in a new tab, including navigation, breadcrumbs, and the existing rendered page. `ApplicationController#dashboard_layout` suppresses dashboard chrome on Turbo-Frame requests, so escaping the list/publishing frames is essential.

## 4. Interaction and states

1. At `/81721200/admin/pages`, open a launched row's kebab using pointer/touch or the native summary control.
2. Activate **Open in admin** → new tab at `/81721200/admin/maintenance/pages/<id>/render` with backend dashboard navigation and page content. The original list retains its filters, pagination, and scroll position.
3. At `/:cid/admin/pages`, repeat for an owned or shared page → the same visited `:cid` in the render URL.
4. On a draft row, use **Preview** → the existing `/:cid/admin/maintenance/pages/<id>/preview` in a new tab.

Empty list/search states remain those of `OpsTableComponent`; an empty rendered page uses `maint_core.page_renders.show.no_content`. Navigation uses the browser's ordinary new-tab loading state. A page taken offline/deleted after the list loads returns the existing 404; an expired session follows existing sign-in behavior; denied roles/tenants follow the destination's existing authorization response. This navigation introduces no validation or vendor-down state.

## 5. Tailwind, Stimulus, and accessibility

- Copy Preview's item classes: `block px-3 py-2 text-sm font-medium text-text-primary hover:bg-surface-hover transition-base`.
- Reuse the existing panel classes: `absolute right-0 z-20 mt-1 min-w-[11rem] rounded-lg border border-border-subtle bg-canvas-elevated py-1 shadow-md text-left`.
- Reuse `<details data-controller="menu-placement" data-action="toggle->menu-placement#reposition">` and its `panel` target. Existing fixed placement escapes clipping and flips upward when space permits; retain the table's overflow-visible arrangement.
- Use the same item order and condition in both responsive branches. Verify at 375px, 768px, and 1280px, including a bottom-row menu and both locales.
- Keep the translated More label on the native summary and a text-labeled anchor. Verify native keyboard activation, Tab access, visible focus, and touch selection with the existing dropdown behavior. The new item uses the same text-only treatment as Preview.

Implementation lanes and regression checks: [implementation plan](../plans/2026-10-21-admin-page-render-link.md).

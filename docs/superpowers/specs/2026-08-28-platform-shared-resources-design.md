# Platform Shared Resources

Date: 2026-08-28

## Problem

The platform owner manages shared Constants, Entities, and Flowcharts from tenant maintenance (`/:cid/admin/maintenance/`) by picking type = shared. That mixes tenant-owned and platform-wide records. Pages have no shared identity (`pages.customer_id` is required). The owner needs a dedicated Shared Resources area under `/81721200/admin/maintenance/platform/` that creates records with `customer_id` NULL (visible to every tenant, read-only except fork).

## Decisions

- Shared Pages are **live for every tenant** when launched (same public/member/admin consumption as a tenant page).
- Tenants may **fork** any shared resource into a local copy. They cannot edit or destroy the global record. Entity per-tenant **definition overrides** stay.
- Shared create/edit UI lives **only** under Shared Resources. The tenant **type = shared** picker is removed. Tenant create is always customer-specific.
- Tenant maintenance lists **still show** shared rows (badge, read-only, Copy available). Owner Edit on those rows goes to the platform URL.
- Approach: **same controllers**, mounted again under `platform/`, switched by request path.

## Navigation, URLs, access

On customer `81721200`, only `platform_owner?` sees a **Shared Resources** section header after existing Platform leaves, with Constants, Entities, Flowcharts, Pages:

- `/81721200/admin/maintenance/platform/constants`
- `/81721200/admin/maintenance/platform/entities`
- `/81721200/admin/maintenance/platform/flowcharts`
- `/81721200/admin/maintenance/platform/pages`

Nested routes match tenant maintenance (copy, versions, trash, launch, preview, …) except **entity entries** are not remounted (entries stay tenant data).

Auth: anything under `/admin/maintenance/platform/` requires `platform_owner?`. Gate on **request path**, not `controller_path` — reused controllers stay `admin/maintenance/constants` etc. Anonymous, member, and admin (including an admin under `81721200`) are denied.

## Shared mode

`shared_resources_mode?` is true when the path matches `/admin/maintenance/platform/(constants|entities|flowcharts|pages)`.

| | Platform path | Tenant path |
|---|---|---|
| List | shared rows only | local + shared |
| Find | shared only (tenant id → 404) | `accessible` (local + shared) |
| Create | force shared, `customer_id` NULL, skip billing quota | force customer-specific, stamp current customer |
| Copy | another shared record | local customer-specific record |
| Trash | `customer_id` NULL deleted rows | that tenant's deleted rows |

URL helpers: when in shared mode, `admin_maintenance_*` named helpers for these four resources remap to `admin_maintenance_platform_*` so existing views/redirects stay.

Stimulus editors still call hardcoded `/admin/maintenance/...` JSON URLs. Tenant finders therefore use `accessible`, and the owner may still mutate shared records through those tenant JSON endpoints (HTML Edit from tenant lists links to the platform URL). Versions modal on platform indexes sets `pathPrefix` to `admin/maintenance/platform`.

`TenantScoped#set_customer_from_current` is cleared by existing `clear_customer_for_shared` callbacks; Pages gain the same pattern.

## Pages

Pages gain the same sharing model as Entity/Flowchart:

- `type` enum `customer_specific` / `shared` (`inheritance_column` disabled)
- `customer_id` nullable; NULL when shared
- `accessible` scope: current customer OR shared
- Unique name among shared pages; per-tenant unique among customer-specific
- Shared page binds **only** to a **shared** entity
- `Page#entity` resolves shared entities when `customer_id` is NULL; tenant pages may bind to local or shared entities

Live consumption: public `/:cid/page/:uuid`, member page show, and admin Pages tree/list use `Page.accessible` (launched + visibility still apply). Batch write on admin Pages stays `where(customer_id: current_customer.id)` so tenants cannot launch/unlaunch a shared page from that surface.

## Tenant UI

- Remove shared from Constants / Entities / Flowcharts type pickers. Show read-only Shared vs Customer-specific on edit.
- Platform forms lock type to shared (read-only). Shared flowchart has no entity binding. Shared entity still offers the extend-base-model field.
- Tenant row actions: Copy always; Edit/Destroy of shared only for owner (Edit → platform path) except non-owner **entity definition override** (existing).
- Constants already list shared for every tenant. Entities and Flowcharts currently mix shared only under `81721200`; change them (and Pages) to `accessible` for every tenant.

## Out of scope

- New roles; tenant admins creating shared records
- Per-tenant overrides for Constants, Flowcharts, or Pages
- Shared FieldTemplates
- Cross-tenant EntityEntry browser
- Bulk-converting `81721200` customer-specific records
- Changing Industry Templates, Billing, Module Settings

## Testing

Request specs: platform owner CRUD on each of the four platform URLs asserts `customer_id` NULL; admin/member/anonymous denied; tenant-owned id on platform URL 404s; tenant create cannot set shared; launched shared page renders at another tenant's public URL; tenant Copy of shared creates a local row. Model spec for Page shared identity and entity binding. Sidebar contributor spec for the new section. RouteAuthorization spec that an `81721200` admin cannot open Shared Resources.

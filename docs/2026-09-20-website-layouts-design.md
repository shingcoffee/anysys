# Website layouts & Pages-menu pivot

**Date:** 2026-09-20  
**Status:** Locked (user: no confirmation; Grok 4.6 Extra High; complete the work)  
**Module key:** `website`

## Problem

The first Website slice treated skeletons as frozen Ruby and let tenant admins add/remove/reorder sections. That is the wrong split: beauty and structure belong to the platform; tenants fill in copy. Site pages also sat under Modules / Website instead of the Pages menu next to form pages.

## Locked decisions

1. **Layout** = a named page composition: ordered section types + default props. Platform-owned (`customer_id` NULL). Owner CRUD including edit.
2. **Skeleton** = a named multi-page site starter. Each page references a `layout_key` plus starter copy. Platform-owned. Owner CRUD including edit.
3. **Tenant admin** picks the default skeleton in Settings (replace is destructive + confirmed). For a new inner page they pick a layout. After that they **only edit section content** (props and in-section arrays). No add/remove/reorder of section types. No kit picker.
4. **Owner** edits layout/skeleton **structure** only at platform module settings (`81721200`). Visiting a tenant composer is still content-only.
5. **Pages menu:** `/:cid/admin/pages/website` is a first-class Pages sidebar node (alongside All / entities / Uncategorized). Form `Page` records stay on All + entity filters. Do **not** merge `WebsitePage` into AR `Page`.
6. **Modules / Website** entry path redirects to the Pages website list (four URL areas preserved).
7. **Catalog is DB**, seeded from Ruby. Seed upserts missing keys; owner edits are not overwritten.
8. **Rich catalog (this slice):** 12 layouts, 6 skeletons, still the existing 13-type section kit (no new CSS/JS frameworks).
9. **Public URLs unchanged:** `GET /:cid/site` and `/:cid/site/:slug`. No forms, no custom domains, no member builder.
10. **Existing tenant pages:** set `layout_key` when it can be inferred; otherwise keep sections and lock structure as content-only (`layout_key` may be blank).

## Out of scope

Custom domains, forms on the site, merging AR models, freeform HTML/canvas, member builder, auto-translating authored copy, media library, new roles.

## Surfaces

| Area | Path | Audience |
|---|---|---|
| Pages (entries) | `/:cid/admin/pages/website` | admin / owner |
| Composer | `/:cid/admin/modules/website/pages/:id/edit` (and new) | admin / owner; content-only |
| Settings | `/:cid/admin/settings/modules/website` | admin / owner; pick skeleton + theme |
| Enable | `/:cid/admin/maintenance/modules` | admin / owner |
| Platform layouts | `/:cid/admin/maintenance/platform/module_settings/website/layouts` | owner `81721200` |
| Platform skeletons | `.../website/skeletons` | owner `81721200` |
| Public | `/:cid/site`, `/:cid/site/:slug` | anyone |

## Data

### `website_layouts`

- `key` string unique not null
- `name`, `description` strings
- `customer_id` null (platform shared)
- `position` integer
- `archived` boolean default false
- `sections` json not null default `[]` — same `{id,type,props}` shape as pages
- timestamps

### `website_skeletons`

- `key` string unique not null
- `name`, `description` strings
- `customer_id` null
- `position` integer
- `archived` boolean default false
- `pages` json not null — `[{title, slug, home, nav_visible, layout_key, sections?}]`
- timestamps

### `website_pages`

- add `layout_key` string (nullable, indexed)

## Authoring rules

- **SavePage (tenant):** merge incoming props onto existing sections by `id`; drop unknown ids; never change `type` or order; restore missing layout slots from the layout template.
- **SaveLayout / SaveSkeleton (owner, platform path only):** full structure via the section kit.
- **ReplaceSkeleton:** destroy tenant pages and re-clone from the skeleton (existing confirm).
- **New inner page:** require `layout_key`; instantiate sections from that layout.

## Catalog (seed)

Layouts: `presence_home`, `presence_about`, `presence_services`, `presence_team`, `presence_contact`, `saas_home`, `saas_about`, `cinematic_home`, `cinematic_story`, `editorial_home`, `editorial_stories`, `article`.

Skeletons: `presence`, `saas_landing`, `cinematic`, `editorial`, `studio`, `product`.

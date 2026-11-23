# Website module — design

**Date:** 2026-09-20  
**Status:** Locked (user: authoring B, beauty first, no further confirmation, implement)  
**Module key:** `website`  
**Display name:** Website

## Problem

Tenant admins have no way to publish an introduction/marketing site. Existing `Page` records are form documents: they require an entity, launch requires fields, public POST runs a flowchart, public chrome is a centered card with `noindex`. Static marketing sites are a different product: multi-page public presence, shared nav/footer, no forms.

This module is a **capability**. Anysys does not ship a finished site for any one customer. It ships skeletons and a section kit cloned from famous marketing sites so each tenant can build their own.

## Locked decisions

1. **New Feature Module `website`.** Do not extend `Page` / `Entity` / `Flowchart`. No conversion either way in this slice.
2. **Authoring = B.** A skeleton is a starting composition. Admins add, remove, and reorder sections from a **shared marketing section kit**. They cannot inject arbitrary HTML/CSS/JS.
3. **Beauty over infinite flexibility.** Section ViewComponents clone proven layouts (Apple cinematic tiles, Stripe/Linear SaaS landing, Nike editorial blocks, classic presence). Theme tokens change color/type/density; they do not invent a sixth layout language.
4. **One site per customer.** Unique `websites.customer_id`.
5. **Publish host:** in-app public URLs only. No custom domain, DNS, TLS, CDN, or static zip in this slice.
6. **No member builder.** Members visit the published site as public visitors.
7. **No forms** on the public site (including contact forms). Contact is address/email/phone/hours text.
8. **Skeletons are code**, not a platform-owner drawing tool. Owner platform settings pick the default skeleton and preview the catalog. Tenants cannot mutate the global catalog.
9. **Starter copy is stored in the page JSON at provision time** (English strings in the DB). Builder chrome is I18n `en` + `zh-CN`. Authored body is not auto-translated.
10. **Images are URL strings** in this slice. Blank image fields render a tasteful gradient placeholder, never a broken icon.
11. **Handoff disabled.** This module is not a flowchart handoff target.
12. **Module starts inactive** (`register!` default). Enabling it provisions the site.

## Out of scope (this slice)

Custom domains, static export, blog/CMS, ecommerce, search, analytics, A/B, sitemaps.xml, media library, AI generate-entire-site, embedding form Pages, payments/captcha on the site, multi-site, member-only sections, freeform canvas, new roles, CSS/JS frameworks other than Tailwind + Stimulus.

## Four module surfaces

Paths follow the live app (`/:cid/admin/...`), not the shorthand in AGENTS.md.

| Area | Path | Audience |
|---|---|---|
| Entries | `/:cid/admin/modules/website` (pages CRUD, composer, preview, publish) | admin / owner |
| Settings | `/:cid/admin/settings/modules/website` (identity, theme, SEO, nav, publish site) | admin / owner |
| Enable/disable | existing `/:cid/admin/maintenance/modules` | admin / owner |
| Platform | `/:cid/admin/maintenance/platform/module_settings/website` + `.../website/skeletons` | owner on `81721200` only |

Public visitors (no auth):

- `GET /:cid/site` — published home page
- `GET /:cid/site/:page_slug` — published inner page

Public POST is not routed. Disabled module or unpublished site/page → 404 with no body leak.

## Data model

### `websites`

| Column | Type | Notes |
|---|---|---|
| `customer_id` | bigint, not null, unique, FK customers, indexed | one site per tenant |
| `name` | string, not null | site name in nav |
| `tagline` | string | optional subtitle |
| `published` | boolean, not null, default false | site-level gate |
| `skeleton_key` | string, not null | last applied starter; does not lock composition |
| `theme` | json, not null, default `{}` | see Theme |
| `seo` | json, not null, default `{}` | `{ "title", "description" }` |
| `footer` | json, not null, default `{}` | `{ "blurb", "columns": [{ "heading", "links": [{ "label", "url" }] }] }` |

`TenantScoped`. No `entity_id`. No flowchart.

### `website_pages`

| Column | Type | Notes |
|---|---|---|
| `customer_id` | bigint, not null, indexed, FK | isolation |
| `website_id` | bigint, not null, indexed, FK | parent |
| `title` | string, not null | |
| `slug` | string, not null | unique per website; home slug is `""` internally, URL is `/site` |
| `position` | integer, not null, default 0 | nav + admin order |
| `published` | boolean, not null, default false | page-level gate |
| `home` | boolean, not null, default false | exactly one home per site |
| `nav_visible` | boolean, not null, default true | omit from public nav when false |
| `sections` | json, not null, default `[]` | ordered section list |

Indexes: unique `(website_id, slug)`; unique `(website_id)` where `home = true` (partial).

Slug rules: `[a-z0-9]+(?:-[a-z0-9]+)*`, max 64, not in `WebsitePage::RESERVED_SLUGS` (`new`, `edit`, `preview`, `site`). Home page slug is blank.

### Section JSON

```json
{ "id": "sec_01h...", "type": "hero_split", "props": { } }
```

`id` is a unique string per page. Unknown `type` is skipped at render (never raises on public GET). Props validated by `Websites::Contracts::Section` on save.

## Section kit (shared, cloned from famous sites)

| `type` | Source | Props (all strings unless noted) |
|---|---|---|
| `hero_cinematic` | Apple / Nike full-bleed chapter | `kicker`, `headline`, `subhead`, `primary_label`, `primary_href`, `secondary_label`, `secondary_href`, `image_url`, `tone` (`light`/`dark`) |
| `hero_split` | Stripe / Linear | `headline`, `subhead`, `primary_label`, `primary_href`, `secondary_label`, `secondary_href`, `visual_url`, `eyebrow` |
| `proof_strip` | Stripe logo/stats row | `items` array of `{ "label", "value" }` (4–6) |
| `bento_grid` | Notion / Linear / Vercel / Apple feature bento | `heading`, `cells` array of `{ "span": "hero"\|"wide"\|"unit", "title", "body", "image_url" }` |
| `alternating_features` | Product “what it does” | `heading`, `items` array of `{ "title", "body", "image_url" }` (image side alternates) |
| `card_grid` | Airbnb-style / services | `heading`, `subhead`, `cards` array of `{ "title", "body", "image_url", "href" }` |
| `team_grid` | About/team | `heading`, `people` array of `{ "name", "role", "bio", "image_url" }` |
| `quote` | Stripe/Linear case | `quote`, `attribution`, `role` |
| `faq` | SaaS FAQ | `heading`, `items` array of `{ "question", "answer" }` — public uses `<details>`, no JS |
| `cta_band` | Final CTA | `headline`, `body`, `button_label`, `button_href` |
| `rich_text` | About body | `heading`, `body` (plain text, `\n\n` → paragraphs; **escape HTML**) |
| `split_image_text` | Dual-audience / about split | `heading`, `body`, `image_url`, `image_side` (`left`/`right`) |
| `contact_info` | Presence contact (no form) | `heading`, `address`, `email`, `phone`, `hours` |

Href fields accept an internal slug (`about`) or an absolute `https://` URL. Internal slugs resolve to `/site/:slug` on the same customer. `javascript:` and `http://` (non-https) are rejected on save.

## Skeletons (starting compositions)

Default: `presence`. Platform `configuration_schema.default_skeleton_key` may override the default used at provision.

### `presence` — classic introduction/marketing (most tenants)

Pages: Home (`home`), About (`about`), Services (`services`), Team (`team`), Contact (`contact`).

- Home: `hero_split` → `proof_strip` → `card_grid` → `cta_band`
- About: `split_image_text` → `rich_text` → `quote`
- Services: `hero_cinematic` (light, shorter) → `alternating_features` → `bento_grid`
- Team: `team_grid`
- Contact: `contact_info` → `cta_band`

### `saas_landing` — Stripe / Linear

Pages: Home, About, Contact.

- Home: `hero_split` → `proof_strip` → `bento_grid` → `alternating_features` → `quote` → `faq` → `cta_band`
- About: `rich_text` → `team_grid`
- Contact: `contact_info`

### `cinematic` — Apple stacked chapters

Pages: Home, About, Contact.

- Home: three `hero_cinematic` (alternating `dark`/`light`) → `bento_grid` → `cta_band`
- About: `split_image_text` → `rich_text`
- Contact: `contact_info`

### `editorial` — Nike campaign stack

Pages: Home, Stories (`stories`), About.

- Home: three `hero_cinematic` (dark) → `card_grid` → `cta_band`
- Stories: `card_grid` → `rich_text`
- About: `split_image_text` → `quote`

Starter `props` live in `Websites::Skeletons::<Key>::PAGES` as English copy. Provision writes them into `website_pages.sections`.

Applying a skeleton **after** provision is an explicit admin action (“Replace pages with skeleton”) that destroys existing pages and recreates them. Settings copy must warn. First provision is silent.

## Theme

`websites.theme`:

```json
{
  "appearance": "light",
  "accent": "azure",
  "type": "sans",
  "density": "spacious"
}
```

| Token | Values | Effect |
|---|---|---|
| `appearance` | `light` (default), `dark` | page background + text |
| `accent` | `azure` (default), `ink`, `gold`, `forest`, `rose` | links, buttons, kicker |
| `type` | `sans` (default), `serif`, `display` | Tailwind font stack (`font-sans` / `font-serif` / a display pairing already in the app) |
| `density` | `spacious` (default), `compact` | section vertical padding |

Public layout uses these tokens as Tailwind classes resolved by `Websites::Theme`. Do **not** reuse `ThemeResolver` (form-card presets).

## Public rendering

- Layout: `layouts/website.html.erb` — full-bleed, **no** form card, **no** `noindex`. Title = page title + site name. Meta description from `websites.seo.description` or page-derived.
- Chrome: `Websites::NavComponent` (sticky, logo/name, published+nav_visible pages, locale switcher, mobile sheet) + `Websites::FooterComponent` (blurb + columns + legal-ish compact row with site name).
- Body: `Websites::PageComponent` maps `sections[]` to `Websites::Sections::<Type>Component`.
- Home: `Websites::Website#home_page`.
- 404: unpublished, missing slug, module disabled, or no home page.
- Responsive: every section stacks to one column below `md`; bento becomes a vertical stack of cards; cinematic heroes keep min-height but shrink type.

Nav links only include `published && nav_visible` pages of **this** customer. Home is always first if published.

## Admin builder

Entries landing is the page list (`AdminTableComponent` via `Admin::Modules::PageComponent`).

Page composer (`/:cid/admin/modules/website/pages/:id/edit`):

- Left: ordered section list (add from kit, reorder, delete, edit props in place).
- Right (desktop) / below (mobile): live preview iframe or in-page preview of the same section components, framed in the public theme. Preview is admin-only (`.../preview`) and ignores `published`.
- Save persists via `Websites::Activities::SavePage`.

Site publish toggle lives on Settings and as a badge/action on the entries header.

## Activities & contracts

PORO `.call` + `Result` struct (same shape as `Captcha::Activities` / `Pages::Activities`), Reform under `app/services/websites/contracts/`.

| Activity | Does |
|---|---|
| `Websites::Activities::Provision` | create website + skeleton pages if none exist |
| `Websites::Activities::SaveSite` | identity, theme, seo, footer, published, skeleton replace |
| `Websites::Activities::SavePage` | title, slug, published, nav_visible, home, sections |
| `Websites::Activities::DestroyPage` | refuse if `home`; otherwise destroy |
| `Websites::Activities::ReorderPages` | positions |

Contracts: `Websites::Contracts::Site`, `Websites::Contracts::Page` (including section array). Model stays thin: associations, `TenantScoped`, scopes `published`, `in_nav`.

## Registration

```
module_key         = "website"
module_name        = "Website"
module_description = "Customer introduction and marketing website — static pages, no forms"
inactive, not required, handoff_enabled false
configuration_schema = { "default_skeleton_key" => { "type" => "string", "default" => "presence" } }
```

`provision!` → `Websites::Activities::Provision`.  
`deprovision!` → set `website.published = false` (keep rows so re-enable restores).  
`sidebar_contributions`: entries → pages index; settings → site settings.  
`entries_for("pages")` → tenant-scoped `WebsitePage` table config.  
`entry_path` → admin pages index.

## Auth / tenancy

- Admin routes inherit `RouteAuthorization` (admin/owner). Controllers add `require_website_module!` → 404 if disabled (same as payments).
- Record loads via `Website.for_current_customer` / `WebsitePage.for_current_customer`. Cross-tenant URL customer is already isolated by `TenantContext`.
- Platform skeleton gallery is under `/admin/maintenance/platform/` (owner-only).
- Public controllers load by `params[:customer_id]` + `published` gates; no auth.
- Owner on a tenant URL edits **that** tenant’s site, never the code catalog.

## I18n

Area files: `config/locales/website.en.yml` + `website.zh-CN.yml`, plus `feature_modules.website.*` in existing feature-module locale files. No hard-coded user-facing strings. Skeleton **catalog labels** (skeleton name, section type name) are I18n. Starter body copy in DB is English.

## JavaScript

- `website_nav_controller.js` — mobile nav open/close, Escape, overlay click. Values: none required beyond defaults; open/close labels passed from server as Stimulus values.
- `website_builder_controller.js` — add section (append JSON), remove, move up/down (and SortableJS like countable-items if reused), keep a hidden input of sections JSON for the form. 100% Vitest lines+branches.

FAQ uses `<details>`. No other public JS.

## Tests (minimum)

- Model: tenant scope, one-home, slug uniqueness, reserved slugs.
- Contract: reject form-like props, reject `javascript:` hrefs, unknown section type.
- Activity: provision idempotent; deprovision unpublishes; save page; destroy home refused.
- Request admin: anon redirect, member 403/redirect, admin 200, other-tenant 404, module-disabled 404.
- Request public: unpublished 404, published 200, no POST route, nav omits unpublished, disabled module 404.
- Component: each section renders headline; contact_info has no `<form>` / `<input>`.
- Registration shared example: key `website`, name `Website`, inactive, not required.
- System (happy): enable module → open entries → preview home.

## Beauty bar (product fail if missed)

Public site must not look like the form `public_page` layout. No centered card, no `noindex`, no entity/flowchart chrome. Desktop **and** mobile. Spacious density default. Section kit must be obviously “marketing site,” not “admin table.”

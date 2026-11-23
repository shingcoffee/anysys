---
title: "Websites"
summary: "The website feature module provisions a tenant site, publishes it on public routes, and stores named themes, skeleton choices and per-page theme overrides; the page composer is website-builder."
---

## Summary

Website is a feature module. `FeatureModules::Website::Registration` uses the key `website`, provisions through `FeatureModules::Website::Provisioner`, and contributes a pages entry plus a site settings link. The four surfaces follow [module-framework](module-framework): a page list, customer site settings, the maintenance enablement toggle, and platform skeleton and layout catalogs.

This page is the module: how a site row is created, how theme and publication work, and which URLs serve the public site. Section editing, the composer, and layout section fields are [website-builder](website-builder).

`Website` is one row per customer (`customer_id` unique). `WebsitePage` belongs to that site and to the same customer. `WebsiteSkeleton` and `WebsiteLayout` are platform catalogs. They are not tenant-scoped.

## Flow

```text
Enable module "website"
        |
        v
FeatureModules::Website::Provisioner
        |
        v
Websites::Activities::Provision
        |  Website published: false
        |  Websites::Skeletons.apply!  (pages also unpublished)
        v
/:cid/admin/settings/modules/website
        |  SaveSite (name, theme, seo, footer, published)
        |  ReplaceSkeleton (destroys pages, applies a skeleton)
/:cid/admin/modules/website/pages/:id/edit
        |  composer — see website-builder
        v
GET /:cid/site
GET /:cid/site/:page_slug
        |
        |  module enabled AND Website#published? AND page published
        v
Websites::PagesController   (otherwise head 404)
```

## Implementation

`Provisioner.call` delegates to `Websites::Activities::Provision`. An existing `Website.for_customer` is returned as-is. Otherwise `Catalog.sync!` runs, then a site is created with the customer's name, `published: false`, empty `seo` and `footer`, and a skeleton key. The key comes from the module configuration field `default_skeleton_key` (default `"presence"`), or `"presence"` when that key is blank or unknown. Theme tokens come from `Websites::Theme.for_catalog(key).to_stored`: the skeleton's paired named theme (see Themes below). `Websites::Skeletons.apply!` copies the skeleton's pages onto the site. Each new page is `published: false`. `Provisioner.deprovision` sets `published` to false and leaves the rows in place.

Customer settings are `Admin::Settings::Modules::Website::SitesController` at `/:customer_id/admin/settings/modules/website`. `Websites::Activities::SaveSite` writes `name`, `tagline`, `published`, `theme`, `seo` (`title`, `description`), `footer`, and `default_layout_key`. Theme keys are sliced to `Websites::Theme::TOKENS`: `appearance`, `accent`, `type`, `density`, `corners`, `neutral`, plus `preset` when it names a known `Websites::ThemePresets` key. `Contracts::Site` rejects a token value outside `Theme::OPTIONS`. An unknown layout key is dropped. Replacing the starter set is `POST` to the settings skeleton resource, `Admin::Settings::Modules::Website::SkeletonsController`, which calls `Websites::Activities::ReplaceSkeleton`. That transaction destroys every page on the site, applies the new skeleton, and replaces `skeleton_key`, `default_layout_key`, and `theme`.

The settings screen is `Websites::Admin::SettingsFormComponent`. Its cards, in order:

1. Publishing: a status card whose `website[published]` switch is applied on Save. It shows the host-aware address from `PageShortcuts::PublicPath.website_home` (`/` or `/:customer_id/`, or a chosen live alias), linked while the site is published, and a secondary **Manage page shortcuts** link.
2. Site identity.
3. Appearance: a preset gallery (`website[theme][preset]` radios, each card a mini preview in that preset's fonts, colors and corners) followed by **Fine-tune**, where each theme token is a visual radio (`ThemeOptionComponent`) beside `ThemePreviewSwatchComponent`. Picking a preset checks its token radios (`website-theme-picker#applyPreset`); changing any token afterwards shows a **Customized** badge on the checked preset. The card loads every `Websites::Fonts` family so specimens render in their real faces.
4. Search appearance.
5. Footer columns, as reorderable cards.
6. Page defaults: the `default_layout_key` select, grouped into `<optgroup>`s by `Websites::LayoutFamily`.
7. Starter template: `SkeletonReplaceComponent`. It shows the current starter with a thumbnail. Inside a disclosure, it lists one card per starter, each with a home-page thumbnail in that starter's catalog theme and its own `ReplaceSkeleton` form.

Every card except Publishing is a `SettingsSectionComponent`, which registers as a `website-theme-picker` section. The "On this page" nav is a sticky right column from `xl` up and a sticky chip strip below it.

The browse list is `Admin::Modules::Website::PagesController#index` at `/:customer_id/admin/modules/website` (also `/pages`), which is also `Registration`'s `entry_path`, module card destination, Modules sidebar entry, and Content → Website Pages shortcut. CRUD, preview, reorder, and media upload stay under that module namespace; `/admin/pages/website` no longer routes to Website (the generic Pages show route returns 404 for that id). The shortcut is shown only when Website is enabled for the URL customer. `edit` is the composer; follow [website-builder](website-builder) for that screen. `Admin::Modules::Website::BaseController` answers 404 when `FeatureModules::Module.enabled?` is false for `website`. Site-wide publication is saved with `website[published]` by `PATCH /:customer_id/admin/settings/modules/website/site` (`Admin::Settings::Modules::Website::SitesController`); the page list and module pages do not offer publishing or settings shortcuts.

Public website delivery is unauthenticated and supports GET/HEAD. Clean paths and chosen aliases, including nested paths, are generated by `PageShortcuts::PublicPath` for settings, studio, editor and navigation. Any eligible website or public form page can be mapped to a chosen address, including `/`; this is not limited to replacing the home page. [Custom domains](custom-domains) are the optional domain on the customer, read live without restart; inactive customers return 404. Saving a new or changed domain requires a direct CNAME from that domain to `anysys.net`; failure blocks that save, while clearing the domain does not check DNS. Deployment publishes DNS and separately manages TLS/ingress/HostAuthorization. Tenant prefixes, collisions and offline behavior are [Page shortcuts](page-shortcuts). Website aliases do not accept POST. The canonical endpoints below remain available:

- `GET /:customer_id/site` → `Websites::PagesController#home`
- `GET /:customer_id/site/:page_slug` → `#show` (`page_slug` is lowercase segments separated by hyphens)
- `GET /:customer_id/site/media/:signed_id` → `Websites::AssetsController#show`

`PagesController` renders only when the module is enabled, `current_website` is `published?`, and the page is `published?`. Canonical home uses `Website#home_page`; a canonical inner slug ignores the home page. Shortcut requests instead load the trusted resolved record ID within the current customer and website, preserving destination identity across concurrent slug reuse or home changes and rechecking publication. Anything else is `head :not_found` with an empty body. Nav links are pages that are published and `nav_visible`. The page renders with `Websites::Theme.for_page(website:, page:)`: the page's own `theme_key` preset when set, else the site theme. `Websites::Theme` maps the tokens to Tailwind classes and to CSS variables on `<html>` (`root_style`). Appearance is a stored token. The class comment says not to use `dark:` media queries and not to reuse `ThemeResolver`.

## Themes

A theme is six tokens. `Websites::Theme::OPTIONS` lists their values:

| Token | Values |
|-------|--------|
| `appearance` | `light`, `dark` |
| `accent` | `azure`, `ink`, `gold`, `forest`, `rose`, `violet`, `copper`, `indigo`, `teal`, `crimson`, `plum`, `olive` |
| `type` | `sans`, `serif`, `display`, `grotesk`, `classic`, `modern`, `geometric`, `elegant`, `gallery`, `technical`, `expressive` |
| `density` | `spacious`, `compact` |
| `corners` | `sharp`, `soft`, `round` |
| `neutral` | `neutral`, `warm`, `cool` |

Each `type` is a font pairing from `Theme::PAIRINGS` (heading, body and accent families plus headline weight and tracking). `Websites::Fonts` holds the 15 families, their fallback stacks, and the `fonts.bunny.net` stylesheet URL. `Theme#root_style` writes `--font-site-heading`, `--font-site-body`, `--font-sans` and `--font-serif`, one `--radius-*` set per `corners` value, and, for `warm`/`cool`, a remapped `--color-neutral-*` ramp (stone or slate). Section templates use `font-site-heading`, `font-site-body`, `rounded-*` and `neutral-*` utilities, so a theme restyles every section without template branches. The public layout links one stylesheet covering the theme's families plus any font picked in section styles (`websites_font_stylesheet`).

`Websites::ThemePresets` registers 27 named themes (`DEFAULT_KEY` `"meridian"`). Each has a token set plus localized `website.themes.<key>.name` and `.description`. `Theme.preset(key)` builds one; `Theme#to_stored` adds `"preset"` so settings can show which preset the site started from, and `Theme#customized?` reports drift from it.

`Websites::ThemePairing` pairs every skeleton and layout with the preset that suits it best. Layouts cut from a skeleton inherit its preset; standalone layouts carry their own. Platform owners can pin a different preset per row with `website_skeletons.theme_key` / `website_layouts.theme_key` (the **Theme** select in the skeleton and layout editors; blank keeps the pairing). `Websites::Contracts::Layout` and `Websites::Contracts::Skeleton` validate the pinned key via the `Websites::Contracts::ThemeKey` mixin. `#theme_preset_key` returns the pinned key or the pairing, and `Theme.for_catalog(key)` / `Theme.for_record(record)` resolve it. Card loops preload their rows once and pass them as `Theme.for_catalog(key, records:)` to avoid a query per card. Catalog thumbnails, provisioning and `ReplaceSkeleton` all use that preset.

`website_pages.theme_key` is an optional per-page override, validated against `ThemePresets.keys` by `Websites::Contracts::Page`. The page editor's **Theme** select offers **Site theme** (blank) and every preset; the new-page form also offers **Layout's paired theme**, the `SavePage::LAYOUT_THEME` sentinel `"layout"`, which `SavePage` resolves to the chosen layout's `theme_preset_key` before validation. The draft preview honors an unsaved `theme_key`.

Public marketing reads also admit signed-in visitors from another tenant. Site/page lookup still uses the URL or trusted shortcut-selected tenant, never the visitor's tenant or forged query parameters; protected admin routes retain their tenant guards.

`AssetsController` requires module enablement, valid signed ID and `MediaPolicy.public_image?(blob, customer_id:)`: matching tenant, explicit website-media classification, positive size within 8 MB and raster MIME. It downloads/rechecks byte size and Marcel-identified MIME before inline serving, adds `X-Content-Type-Options: nosniff`, and returns empty 404 for private/unclassified/foreign/non-raster/missing storage. Site publication is not a media gate.

Platform catalogs sit at `/:customer_id/admin/maintenance/platform/module_settings/website/skeletons` and `.../layouts`, owner-gated by the platform prefix. `Admin::Maintenance::Platform::Website::SkeletonsController` and `LayoutsController` call `Websites::Catalog.sync!`. `sync!` inserts missing keys and, for rows that already exist, keeps the stored name, description, and section copy, filling only blank media. `Catalog.refresh!` overwrites platform skeleton and layout rows from the Ruby seeds and does not touch tenant `Website` rows. Skeleton keys are the `Websites::Skeletons::KEYS` list (`presence` through `quarterly`). The famous-site starters `voltage`, `wellspring`, `summit`, `manor`, `bloom`, `roast`, `atrium`, `canvas`, `harbor`, `calm`, `marque`, `tempo`, and `quarterly` sit in the product, nonprofit, events, business, commerce, hospitality, culture, product, commerce, wellness, product, culture, and editorial categories. Layout rows also include the extra keys in `Catalog::EXTRA_LAYOUTS` (`article`, `manifesto`, `gallery`, `longform`, `launch`, `pricing`, `portfolio`, `menu`, `journal`, `process`, `showcase`, `compare`, `newsroom`, `listings`, `stores`, `heritage`, `conference`, `spotlight`, `campaign`, `tour`, `impact`, `why_us`, `launch_note`). Because `sync!` keeps existing rows, a seed change to an existing skeleton or layout reaches a database only through `refresh!` or an owner edit.

`WebsitePage` reserves slugs `new`, `edit`, `preview`, `site`, and `media` except on the home page, whose slug may be blank. Home is unique per website.

## Where to pay attention

### Route audit: catalog, slug and media invariants

Whole skeleton/layout writes validate before media decoration or persistence through `Contracts::Skeleton`, `Layout`, `Sections` and JSONSchemer-backed `PropSchema`. Skeletons require exactly one home, unique valid slugs, known layouts and valid typed sections/props/options/lists; malformed JSON is rejected rather than normalized into empty content. Provision/direct apply/replacement share the customer shortcut lock and validate structure plus every slug collision before deleting old pages. Replacement returns controlled failure and preserves the existing site/pages. `SavePage` reloads persisted tenant/site-scoped state inside that lock, so explicit unpublish applies to the latest row; structural locks use the current template.

`SavePage` resolves saved section IDs/types before decoration, so an ignored incoming type cannot add unrelated media props. Metadata-only saves preserve stored sections without refilling templates/media; unchanged invalid stored content can be taken offline. New pages, changed section content and explicit publication still receive complete section validation. Array cardinality failures report localized field/bounds messages, and the assistant does not duplicate an already precise normalization error.

Upload/import and public serving share actual-byte raster classification and tenant/website-media identity; generic signed attachments are not public website media. The provisioner propagates failed Results as ProvisioningError, allowing enablement rollback. AI document apply rechecks draft status and captures detached Undo snapshots under conversation → customer → ordered page locks; Undo reloads message/provenance and validates fingerprints under the same customer boundary. See [Website builder](website-builder), [Page shortcuts](page-shortcuts), [AI assistant](ai-assistant).

:::note
Website services, requests, models, module hooks and the storage-isolation regression passed 572 targeted examples with no failures on an isolated database/upload root. This includes real MIME bytes and Disk downloads, catalogs, stale saves and assistant schema validation. Test storage setup and worker-safe cleanup are documented in [Background jobs](background-jobs). On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Browser results still require their own run.
:::

:::attention
`Websites::PagesController` returns an empty 404 unless `FeatureModules::Module` is enabled for `website`, `Website#published?` is true, and the `WebsitePage` is published. A disabled module, an unpublished site, and a missing slug share that response so titles and the site name are not leaked.
:::

:::attention
`ReplaceSkeleton` validates the complete replacement and shortcut reservations first, then `Skeletons.apply!(site, key, replace: true)` removes/recreates pages transactionally. Successful replacement still removes edited copy; rejected replacement does not. Deprovision only unpublishes the site.
:::

:::attention
`Website` validates `customer_id` uniqueness, so a tenant has one site. `WebsiteSkeleton` and `WebsiteLayout` have no `customer_id`. `Websites::Catalog.sync!` keeps owner edits on those platform rows. `Catalog.refresh!` overwrites the platform rows from code and leaves tenant sites alone.
:::

:::attention
`Websites::Activities::Provision` and `Websites::Skeletons.apply!` create pages with `published: false`. `Admin::Settings::Modules::Website::SitesController` publishes the site through `Websites::Activities::SaveSite`. A published site still hides a page whose own `published` flag is false. The composer that edits sections is [website-builder](website-builder).
:::

## Key code

```ruby
# app/services/websites/activities/provision.rb
site = Website.create!(
  customer_id: customer.id,
  name: customer.name,
  skeleton_key: default_skeleton_key,
  default_layout_key: default_layout_key_for(default_skeleton_key),
  theme: Websites::Theme.for_catalog(default_skeleton_key).to_stored,
  seo: {},
  footer: {},
  published: false
)
Websites::Skeletons.apply!(site, site.skeleton_key)
```

```ruby
# app/controllers/websites/pages_controller.rb
def public_site_available?
  return false unless website_module_enabled?

  @website = current_website
  @website&.try(:published?)
end
```

```ruby
# app/services/websites/activities/replace_skeleton.rb
result = Websites::Activities::ReplaceSkeleton.call(site: site, skeleton_key: key)
# result.success? / result.errors; invalid replacement preserves current pages.
```

```ruby
# app/services/feature_modules/website/provisioner.rb
def self.deprovision(customer)
  site = ::Website.for_customer(customer.id).first
  site&.update!(published: false)
  site
end
```

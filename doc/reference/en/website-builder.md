---
title: "Website builder"
summary: "How the Website feature module composes a tenant marketing site from skeletons, layouts, pages, and media."
---

## Summary

The website builder is the Website feature module: one `Website` per customer, many `WebsitePage` rows, and platform catalogs of `WebsiteSkeleton` and `WebsiteLayout`. It publishes static marketing pages. It does not store a `Page` configuration, bind `form_settings.flowchart_id`, or submit to `/page/:uuid`. That editor is [Page builder](page-builder).

Enabling the module runs `FeatureModules::Website::Provisioner`, which calls `Websites::Activities::Provision`. Provision inserts an unpublished site named after the customer, copies the default skeleton (configuration default `"presence"`), and applies the skeleton's paired named theme (`Websites::Theme.for_catalog(key).to_stored`; see [websites](websites)). Disabling the module sets `published` to false and leaves the rows in place. While the module is off, `Admin::Modules::Website::BaseController`, `Websites::PagesController`, and `Websites::AssetsController` respond 404. The platform skeleton and layout controllers do not use that check.

Public URLs need no authentication. Website pages have host-aware clean paths (`/`, `/pricing`, or customer-prefixed equivalents) and can have arbitrary chosen aliases such as `/campaign/register`; see [Page shortcuts](page-shortcuts). Canonical `GET /:customer_id/site`, `GET /:customer_id/site/:page_slug`, and `GET /:customer_id/site/media/:signed_id` remain available. An unpublished site or page is an empty 404.

[Custom domains](custom-domains) select unprefixed public tenants from the domain stored on the customer. Explicit customer prefixes win; inactive customers return 404. Domain changes require no restart. Saving a new or changed domain requires a direct CNAME from that domain to `anysys.net`; verification failure blocks that save. Clearing the domain does not check DNS. Deployment publishes DNS and separately manages TLS/ingress/HostAuthorization; a domain does not provision those layers.

## Flow

```text
FeatureModules::Website::Registration
        |  provision! / deprovision!
        v
Websites::Activities::Provision
        |  Website + Websites::Skeletons.apply!
        v
Website (one per customer_id)
        |
        +-- WebsitePage (title, slug, sections JSON, layout_key, home, published)
        |
        +-- theme / seo / footer

Tenant admin
        |
        +-- GET  /:cid/admin/modules/website         page list (Admin::Modules::Website::PagesController)
        +-- /:cid/admin/modules/website/pages       composer CRUD, preview, reorder
        +-- POST /:cid/admin/modules/website/media  UploadMedia
         +-- /:cid/admin/settings/modules/website    SaveSite (including publication) + ReplaceSkeleton
        +-- /:cid/admin/assistant                  apply_website -> Websites::Assistant::Processor
                                                   (SavePage + ImportMedia, drafts only)

Platform owner
        |
        +-- /:cid/admin/maintenance/platform/module_settings/website/skeletons
        +-- /:cid/admin/maintenance/platform/module_settings/website/skeletons/:key/preview
        +-- /:cid/admin/maintenance/platform/module_settings/website/layouts
        +-- /:cid/admin/maintenance/platform/module_settings/website/layouts/:key/preview
                |
                v
        Websites::Activities::SaveSkeleton / SaveLayout
        Websites::Catalog.sync!

Public
        |
        v
Websites::PagesController   layout "website"
        |  published site + published page
        v
section components from WebsitePage#sections
```

The tenant page editor mounts `website-builder` through `Websites::Admin::ComposerComponent`. New pages are `identity_only`, and the composer hands its form to `Websites::Admin::NewPageComponent`. Edit locks structure (`structure_locked: true`). Platform layout and skeleton screens pass `structure_locked: false`.

## Implementation

### Records

`Website` validates a unique `customer_id`, `name`, and `skeleton_key`. `DEFAULT_THEME` is `Websites::Theme::DEFAULTS`: appearance `light`, accent `azure`, type `sans`, density `spacious`, corners `soft`, neutral `neutral`. `has_many :pages` is `WebsitePage` ordered by `position`. `home_page` is the row with `home: true`.

`WebsitePage` belongs to `website`, validates title, unique slug per site, and a single home page. `RESERVED_SLUGS` are `new`, `edit`, `preview`, `site`, and `media` (home and blank slug are exempt). `layout` is `WebsiteLayout.find_by(key: layout_key)`. Optional `theme_key` must be a `Websites::ThemePresets` key; `Websites::Contracts::Page` checks it through the shared `Websites::Contracts::ThemeKey` mixin. Sections are a JSON array of `{ id, type, props }`; `props.styles` holds Design overrides.

Links stored in section `props` under a `*_href`/`href`/`url` key are validated and resolved by `Websites::Href`. A value may be blank, a kebab-case page slug (resolved through `PageShortcuts::PublicPath.website_slug`), a root-relative path (single leading `/`, e.g. `/auth/sign_up` or `/path?query#frag`), or an absolute `https://` URL. `resolve` accepts optional `host:` and translates canonical local website and public Page destinations at render time; unrelated application paths keep their existing handling. Addressable preserves repeated query parameters and fragments, public components retain locale, and the presentation helper adds `SCRIPT_NAME` for mounted deployments. The editor's native form validation accepts the same root-relative paths. Protocol-relative (`//host`), backslash escapes (`/\host`), `http:`, `javascript:`, and `data:` values are rejected. Both editor validation and Ruby validation/resolution reject backslashes and control characters (including tabs and newlines) before trimming or URL parsing can normalize them into an external host; root-relative paths cannot contain whitespace. `Websites::Href.media?` is intentionally stricter — it accepts `https://` image URLs, tenant media paths (`/:cid/site/media/:signed_id`), and narrowly validated bundled Anysys SVG and `anysys-photo-*.webp` paths under `/site-images/anysys/`. Arbitrary root-relative paths are not accepted as media.

Canonical form links (`/:cid/page/:uuid`) resolve through `PageShortcuts::PublicPath.public_page_uuid`, using immutable scalar identities. The public-rendering lookup batches all eligible owned/shared UUID identities, including forms without aliases, alongside website and shortcut identities. Mixed navigation/footer link queries remain bounded as destinations grow; no Page instances or after-find definition loads are needed for link generation. Outside that request scope or for a different explicit tenant, fresh scalar queries preserve eligibility checks. Forms without aliases retain their canonical paths; unknown or ineligible links remain unchanged. See [Page shortcuts](page-shortcuts).

`WebsiteLayout` and `WebsiteSkeleton` are platform rows keyed by `key` (`[a-z0-9]+(?:_[a-z0-9]+)*`). They are not tenant-scoped. `WebsiteLayout#instantiate_sections` calls `Websites::Skeletons.decorate_sections`. Display names prefer `website.layouts.<key>.name` and `website.skeletons.<key>.name` when the I18n key exists.

`Websites::Skeletons::KEYS` lists the starter compositions (`presence`, `saas_landing`, `cinematic`, `editorial`, `studio`, `product`, `ledger`, `signal`, `atelier`, `campus`, `gazette`, `lumen`, `monograph`, `terrain`, `supper`, `clinic`, `folio`, `voyage`, `kinetic`, `voltage`, `wellspring`, `summit`, `manor`, `bloom`, `roast`, `atrium`, `canvas`, `harbor`, `calm`, `marque`, `tempo`, `quarterly`). Each one lives in `app/services/websites/skeletons/<key>.rb` and borrows the page patterns of a well-known site, named in `website.skeletons.<key>.inspired_by` and shown as "Inspired by …" in the skeleton gallery and editor. Brands and copy are fictional. `CATEGORY_BY_KEY` files each key under a gallery category. Every internal href in a skeleton points at a slug of that same skeleton, and each skeleton has exactly one home page. `pages_for` prefers an active `WebsiteSkeleton` row and otherwise the Ruby seed `PAGES`. `apply!` creates `WebsitePage` rows; the home page gets a blank slug.

`Websites::SectionKit::TYPES` is the section vocabulary (`announcement`, `hero_cinematic`, `hero_split`, `hero_centered`, `product_spotlight`, `image_banner`, `ai_preview`, `statement`, `proof_strip`, `metrics`, `logo_cloud`, `showcase_tiles`, `bento_grid`, `feature_tabs`, `alternating_features`, `feature_grid`, `split_checklist`, `steps`, `timeline`, `card_grid`, `collection_rail`, `story_index`, `gallery`, `team_grid`, `quote`, `testimonials`, `pricing`, `comparison_table`, `price_list`, `listing_grid`, `agenda`, `faq`, `cta_band`, `cta_split`, `rich_text`, `split_image_text`, `contact_info`, `locations`). Each type renders through `Websites::Sections::<Type>Component`. The newer patterns are:

- `showcase_tiles` — full-bleed product tiles with a headline and two links; `size` is `full` or `half` (`TILE_SIZES`), `tone` is `light` or `dark`.
- `timeline` — dated milestones on a vertical rail.
- `story_index` — a lead story plus a headline list, for newsrooms and front pages.
- `comparison_table` — up to four plan columns (`COMPARISON_COLUMNS`) and feature rows; it scrolls sideways on narrow screens.
- `listing_grid` — photo cards with price, meta, rating, and badge; `aspect` is `square`, `portrait`, or `landscape` (`ASPECTS`).
- `agenda` — a time-ordered session list with an optional track chip.
- `locations` — store or venue cards with address, hours, and a link.

Brand-reference sections, each modelled on a well-known site's signature pattern:

- `announcement` (Vercel / Linear) — a slim pill with `badge`, `body`, and an arrow link (`link_label`, `href`).
- `product_spotlight` (Apple) — centred reveal over a large framed `image_url`, then up to four `specs` of `{ value, label }`.
- `image_banner` (Nike / Patagonia) — full-bleed photograph with white copy over a scrim; `height` is `tall` or `medium` (`BANNER_HEIGHTS`), `placement` is `bottom` or `center` (`PLACEMENTS`).
- `metrics` (Stripe) — up to four oversized `{ value, label, body }` figures.
- `feature_tabs` (Linear / Notion) — up to five `{ label, title, body, image_url }` tabs switched by `website_feature_tabs_controller.js`; the first tab is active in the server render, so the section reads without JavaScript.
- `split_checklist` (Mailchimp / Shopify) — pitch and button beside up to eight checked `{ title, body }` items.
- `collection_rail` (Spotify / Airbnb) — horizontally scrolling snap row of `{ title, meta, image_url, href }` cards; `aspect` reuses `ASPECTS`.
- `cta_split` (Airbnb) — closing panel with a photo on `image_side` and two buttons.

#### Section style overrides

Every section accepts optional look-and-feel props on top of its content. `Websites::SectionFields.style_fields(type)` lists them and `full_schema_for(type)` (content + style) is the schema used by `PropSchema`, `Contracts::Section`, the assistant's `SchemaValidator`, and its section-kit prompt table. `schema_for` stays content-only.

| Prop | Values (`SectionKit`) | Effect |
| --- | --- | --- |
| `surface` | `SURFACES`: `default`, `muted`, `contrast`, `accent` | Band behind the section. `contrast` renders the section with the inverted appearance (`Theme#for_surface`); `muted` uses `band_class`; `accent` a soft accent tint. |
| `spacing` | `SPACINGS`: `default`, `tight`, `roomy` | Overrides vertical padding through `SectionComponent#spacing_class`. Not offered for full-bleed types (`UNSPACED`). |
| `align` | `ALIGNS`: `default`, `start`, `center` | Heading alignment via `SectionComponent#header_align`; only for header-led types (`ALIGNABLE`). |

Blank or unknown values read as `default` (`SectionKit.style_value`). `Websites::PageComponent#section_wrapper` adds the band class and `data-section-surface`; the platform marketing presentation's specialised sections ignore surfaces. In the editor the fields appear as segmented controls at the top of the section's **Design** panel, opened from the paintbrush in the inspector header (hidden for the platform marketing presentation).

#### Design overrides (`props.styles`)

`styles` (`Websites::SectionStyles::PROP`) is a reserved prop that restyles parts of one section: `{ target => { attribute => value } }`. `SectionStyles.targets_for(type)` derives the targets from `SectionFields.schema_for`:

| Target | Kind | Attributes |
| --- | --- | --- |
| `section` | section | `background` (hex), `heading_font`, `body_font`, `scale` |
| each text field, e.g. `headline` | element | `color`, `font`, `size`, `weight`, `italic`, `align` |
| `buttons` (types with button labels) | buttons | `shape`, `fill`, `text` |
| each list, e.g. `items` | items | `background`, `text` |
| each list-item text field, e.g. `items.title` | element | as element |

Text fields are string and textarea fields other than links, image URLs and button labels. Values: colors are a theme token (`COLOR_TOKENS`: `accent`, `ink`, `body`, `muted`, `inverse`; item backgrounds use `BACKGROUND_TOKENS`: `band`, `accent_soft`, `accent`, `ink`, `canvas`) or a `#rrggbb` hex; the section background is hex only. Fonts are `Websites::Fonts` keys; `size`/`scale` are `xs`, `sm`, `lg`, `xl`, `2xl`; `weight` is `regular`–`bold`; `italic` is `italic`/`normal`; `align` is `start`/`center`/`end`; `shape` is `pill`/`rounded`/`square`. Blank means "theme default", and the builder omits it.

`PropSchema` merges `SectionStyles.json_schema(type)` (no unknown targets or attributes) and `Contracts::Section` re-checks each value with `SectionStyles.valid_value?`, so CSS text never reaches a template unvalidated. The assistant's `SchemaValidator` keeps only sanitized styles.

`Websites::StyleResolver` turns validated values into inline CSS. Templates mark styleable nodes with `SectionComponent#el_attrs(target)` and `#item_attrs(array)`, which emit `data-site-el` plus the resolved `style`; `SectionHeaderComponent` marks `kicker`/`heading`/`subhead` and `SectionButtonsComponent` marks `buttons`. Theme tokens resolve through `Theme#color`, so they follow the page theme. A size override rescales the `--text-site-*` variables, keeping responsive steps. A custom section background flips the section's appearance by WCAG luminance (`StyleResolver.section_appearance`), so default text stays readable; button fills get an automatic contrasting label. The platform marketing presentation's specialised sections ignore styles.

The reusable product-led sections are available to every website:

- `ai_preview` lives in the `showcase` picker group. Props are `kicker`, `heading`, `subhead`, `example_label`, `prompt_label`, `prompt`, `review_note`, `output_label`, and `items` of `{ title, body, status }`. The editor/assistant schema specifies 1–4 items. Rendering omits blank optional labels and hides the output group when items are empty. A violet request panel and neutral output cards stack on small screens; all meaningful text comes from props, decorative icons are hidden from assistive technology, and the illustration has no live AI interaction.
- `hero_centered.media_mode` accepts `image` or `none` (`MEDIA_MODES`). Omitted or blank means `image`, retaining the image/placeholder frame. `none` renders a compact text-only hero with smaller heading sizing and padding, omitting the entire media frame even if `image_url` is stored.
- `pricing.featured_label` overrides the badge on a tier whose `highlight` is `featured`. Omitted or blank uses `website.public.pricing.featured` in the request locale. Standard tiers have no badge.

`SectionEditorComponent` treats only complete `primary_label`/`primary_href`, `secondary_label`/`secondary_href`, and `button_label`/`button_href` pairs as buttons. Other labels, including preview labels and `featured_label`, remain copy fields with their own translated labels. Select fields such as `media_mode` appear under options. The assistant's section-kit table derives these props, choices, and list bounds from the same schema; its purpose descriptions explain the static preview, text-only hero, and featured badge override.

`Websites::SectionFields.schema_for` describes each type's fields for the composer, the AI prompt, and validation. `Websites::Contracts::Section` validates props, including the select values above. `Websites::Theme` maps stored tokens (`APPEARANCES`, `ACCENTS`, `TYPES`, `DENSITIES`, `CORNERS`, `NEUTRALS`) to Tailwind classes and `<html>` CSS variables, and does not use `dark:` media queries. Each `TYPES` entry is a font pairing. Catalog previews render in the row's paired preset (`Theme.for_catalog` / `Theme.for_record`); the composer renders a page in `Theme.for_page`. Tokens, presets and pairing are in [websites](websites).

`Websites::Media` fills blank stock image URLs from `images.unsplash.com`. The palette is the layout or skeleton key prefix before `_`. A palette can list its own shots for heroes, features, tiles, stories, listings, and places; a collection it does not list falls back to the palette's other scene shots, and list items cycle through those URLs. `fill_sections` keeps a per-page set of placed photo ids: single-image sections (`SINGLE_SLOTS`) take their preferred shot only if it is still unused, otherwise the first unused shot in `SHOT_FALLBACKS` order, and lists cycle unused shots before repeating any already on the page. Only blank or stock URLs are ever replaced, so authored images stay put. Tenant uploads are a different path: `Websites::Activities::UploadMedia` (JPEG, PNG, WebP, GIF, at most 8 megabytes) stores an `ActiveStorage::Blob` with `customer_id` and returns `/:customer_id/site/media/:signed_id`. `Websites::AssetsController#show` sends the blob only when the signed id is valid and `blob.customer_id` matches the URL customer.

`Websites::Catalog.sync!` seeds layout and skeleton rows from the Ruby catalogs. Existing rows keep owner copy; blank media is filled from `Websites::Media`.

`Websites::Media.fill("hero_centered", props, palette)` skips all image filling/replacement when `media_mode` is `none`: an absent image key stays absent, and any stored blank, stock, or authored image value stays intact. `fill_sections` and `fill_pages` inherit this behavior. Omitted, blank, or `image` media mode retains normal palette filling; neighboring image sections are processed as usual.

### Activities

These are plain classes with `.call` and a `Result`. They are not `Trailblazer::Activity` graphs.

- `Provision` — create the site once; a second call returns the existing row.
- `SaveSite` — `name`, `tagline`, `published`, `theme`, `seo`, `footer`, `default_layout_key`, checked by `Websites::Contracts::Site`. `skeleton_key` is not in `SaveSite::KEYS`.
- `ReplaceSkeleton` — destroys every page on the site, runs `Skeletons.apply!`, and rewrites `skeleton_key`, `default_layout_key`, and `theme`.
- `SavePage` — `Websites::Contracts::Page`. With `structure_editable: false` (the tenant controller default), a persisted page keeps its `layout_key`, and `locked_sections` copies incoming `props` onto the existing section ids and types before media decoration. New section ids in the payload are dropped. Metadata-only updates preserve existing sections; new pages, changed sections and explicit `published: true` validate the full content. Unpublishing unchanged invalid stored content remains possible. Home cannot be cleared in place; setting home blanks the slug and demotes the previous home. Destroy of the home page fails in `DestroyPage`.
- Page validation, automatic slug generation, home demotion and persistence run inside `PageShortcuts::Collisions.with_customer_lock`, shared with shortcut saves. This prevents concurrent website/shortcut writes from claiming the same customer-relative path; failed writes roll back home demotion. See [Page shortcuts](page-shortcuts) for the write boundary and trusted record-ID dispatch.
- `ReorderPages` — rewrites `position` from `ordered_ids`, then appends pages that were omitted.
- `SaveSkeleton` / `SaveLayout` — platform catalog writes.
- `UploadMedia` — tenant image upload.
- `ImportMedia` — copies an existing blob (an AI assistant attachment) into tenant website media, with the same type and size rules as `UploadMedia`. The copy records `assistant_source_blob_id` in its metadata, so a second import of the same source returns the first copy. The copy's bytes come from `Websites::ImageFit.rendition`, run once at import. It keeps the attachment's bytes when the long edge already reaches 1920 pixels. Otherwise it enlarges the photo uniformly, at most 4×, and never crops or downscales it. The attachment itself is left untouched. `Websites::FittedPhotoComponent` shows these imports whole over a blurred fill.

`Websites::CurrentSite#call_website_activity` constantizes `Websites::Activities::<name>`.

### AI assistant

The [AI assistant](ai-assistant) writes website pages through `Websites::Assistant::Processor` when the model returns an `apply_website` document. `Websites::Assistant::SchemaValidator` checks each page against `SectionKit` and `SectionFields` before anything is saved. Pages are saved with `SavePage` and `structure_editable: true`, because the assistant composes the section list itself. New pages are unpublished drafts, and published pages are never modified. Attached photos are referenced as `upload:<attachment id>` tokens, imported with `ImportMedia`, and stored in `sections` as `/:customer_id/site/media/:signed_id` URLs, the same form the composer's upload produces. The admin reviews the draft in the assistant's artifact pane or opens it in the page editor, then publishes from the site as usual. Until then, the reply's Undo button (`Websites::Assistant::Undo`) deletes the pages it created and puts back the pages it revised, provided none of them has been edited or published since.

### Platform marketing-site source restore

`Websites::HomeSite` is the reproducible source for customer **81721200 only**. The marketing redesign composes five published, builder-backed public pages, presented at `/` and clean slugs on the shared host by default (canonical `/81721200/site` endpoints remain available). Theme tokens remain `light / violet / sans / compact`; the section types and order follow this map:

| Page | Count | Types in saved source order | Source role suffixes |
|---|---:|---|---|
| Home | 11 | `hero_centered, proof_strip, logo_cloud, ai_preview, feature_grid, card_grid, feature_grid, split_image_text, steps, faq, cta_band` | `hero, stats, industries, preview, assistant, desktop, capabilities, website, steps, faq, cta` |
| Platform | 9 | `hero_centered, ai_preview, feature_grid, card_grid, feature_grid, split_image_text, comparison_table, steps, cta_band` | `hero, preview, assistant, desktop, capabilities, website, comparison, steps, cta` |
| Pricing | 5 | `hero_centered, pricing, feature_grid, faq, cta_band` | `hero, plans, foundation, faq, cta` |
| About | 6 | `hero_centered, proof_strip, rich_text, feature_grid, split_image_text, cta_band` | `hero, stats, mission, principles, craft, cta` |
| Contact | 3 | `hero_centered, rich_text, cta_band` | `hero, availability, cta` |

Source ids are `home_site_<page>_<role>`; Home's page key is `home` even though its saved slug is blank. These ids identify source roles, not presentation selectors. Saved `{ id, type, props }` objects remain the editable rendering contract. About and Contact heroes use `media_mode: "image"` with bundled photos; Home, Platform and Pricing use `media_mode: "none"`. Home and About offer “Start building free” plus “Explore the platform”; Platform offers “Start building free” plus “See pricing”; Pricing and Contact store both hero action pairs as blank strings. Every closing band links “Create your free workspace” to signup.

Source copy and image paths live under `website.home_site.*` in the paired `config/locales/website_home_site.en.yml` and `.zh-CN.yml`. `definition(locale: :en)` returns a fresh, deterministic hash with call-time I18n strings; it performs no filesystem/network IO or database access. `apply!(locale: :en)` explicitly persists that definition through the existing activities, including navigation titles, footer and SEO. Shared tagline/SEO/footer positioning and the illustration translation keys from the preceding copy refresh are retained. Decorative chrome that is not a saved prop — the Home hero badge (“New” / “全新”), the trust row, About/Contact hero chips, story chips, the product mockup and Contact route descriptions — is translated at request time from `website.home_site.{hero_badge,trust,hero_chips,story_chips,mockup,contact.routes}`.

#### Marketing copy and connected drafts

The copy uses a confident, promotional voice. Every page headline stores intentional newlines except where noted: Home `Describe your business.\nAI builds the rest.` / `说出你的业务，\n其余交给 AI。`, Platform `Everything your business runs on.\nOne brilliant workspace.`, Pricing `Simple pricing.\nLimitless ambition.` / `定价简单，\n雄心无限。`, About `We build tools for\npeople who build.` / `我们为创造者，\n打造创造的工具。`, Contact `Let's build something\nremarkable together.` / `携手共创，\n成就非凡。`. No HTML or additional accent prop is stored. The scoped renderer escapes each line into a block span joined by a bare newline, so the heading's text content equals the saved headline; the final line of a multiline headline uses the violet–fuchsia–sky gradient, while a single-line owner headline stays white. The target composer uses a textarea for the existing `headline` field so a save preserves newlines.

The two headline features are the **AI assistant** and the **locally hosted Windows desktop app**. The Home hero eyebrow (“AI assistant built in · Windows desktop app coming soon” / “内置 AI 助手 · Windows 桌面应用即将推出”), subhead, trust row (“AI assistant built in” / “内置 AI 助手”), SEO and footer blurb name both. Home proceeds from the hero and product mockup to a four-figure stats band, an industries marquee, the connected-draft board, the six-card AI assistant showcase (`home_site_home_assistant`), the upcoming Windows panel, the capability index, one website story, a three-step process, a five-question FAQ (including “What can the AI assistant do?”) and the closing band. Platform expands the membership example into the same assistant showcase and Windows panel, then capabilities, a website story, a seven-row comparison of “Anysys” against “The usual patchwork” / “常见的拼凑方案” (including “Host it on your own computer” → “Coming soon”) and the process. Both pages share one `website.home_site.assistant` definition, just as they share the Windows panel. Pricing keeps `home_site_pricing_foundation` immediately after plans (“More than a plan. A complete, connected workspace.” / “不止一个方案，更是完整贯通的工作空间。”), describing what every plan includes — AI assistant; records, forms & websites; members, payments & messaging — rather than plan entitlements.

The assistant showcase only claims shipped [AI assistant](ai-assistant) behavior: typed, dictated or photo briefs with `@` record mentions; record types with fields, links and calculated values, with confirmation before changing existing ones; form pages generated from record types; up to five drafted website pages with attached photos placed; one-click Undo of an unpublished, unedited website draft; nothing published without the admin; English/Simplified Chinese and resumable conversations. It names no model vendor, because the provider is platform-configured.

About leads with a photo hero and two actions, then a stats band, the mission (two paragraphs), three principles, and `home_site_about_craft` as a `split_image_text` story with its own photo. Contact leads with a photo hero, then an availability note pointing existing customers to the workspace Help menu (“Open the Help menu in your workspace to start a support conversation”), followed by next-step cards. Home has no plan cards; only Pricing compares plans.

Stats figures (“3” ways to brief the assistant, “< 5 min” from brief to connected drafts, “0” lines of code, “100%” of AI drafts reviewed, “∞” ways to shape it) and the industries list are marketing copy stored as ordinary props, not measured metrics or customer logos. Review them before relying on them in campaigns.

The `ai_preview` props remain `kicker`, `heading`, `subhead`, `example_label`, `prompt_label`, `prompt`, `review_note`, `output_label` and `items[{title,body,status}]`. Both source boards leave kicker/subhead blank. Shared labels are “Illustrative example” / “产品示意”, “Your brief” / “你的需求”, “Connected drafts” / “关联草稿”, and “Draft” / “草稿”. The review note is “AI proposes. You review the details and decide what goes live.” / “AI 提出方案，由你审核细节、决定何时发布。” Item bodies are two-line proposed field/page outlines, escaped and presented with preserved newlines; they are not deployed records, interactive forms or live application links.

All marketing text remains in paired locale definitions and is persisted as ordinary editable props. Actions are Start building free / 免费开始构建, Explore the platform / 了解平台, Create your free workspace / 免费创建工作空间 and See pricing / 查看价格. AI proposes reviewable drafts; people refine and publish deliberately. Platform qualifies voice input by a configured speech provider, and payment/messaging services by their required configuration. No testimonials, customer logos, contact details or live-demo controls are invented.

#### Scoped presentation and editor contract

The implemented frontend integration is `Websites::HomeSite::Presentation.for(website:, page:)`, returning a presentation or nil. It exposes `role`, `component_class(type)`, `variant_for(type, id: nil)`, `header_class` and `footer_class`; `matches_page?(page)` revalidates page identity and `nav_pages(pages)` filters the supplied saved navigation. The validated context drives public rendering, same-page admin preview and the target composer.

- Both actual records must have `customer_id == HomeSite::CUSTOMER_ID`. Saved identities require a nonnil website id and `page.website_id == website.id`, including localized/preview copies whose `persisted?` is false. Genuinely unsaved pages must reference the supplied website object. Eligibility never uses Current, a URL substring, section id or wording.
- `:home` comes only from `page.home?`; other eligible slugs are `platform`, `pricing`, `about`, `contact`. Extra pages and other customers receive generic sections and chrome. Explicit presentation input cannot bypass these checks.
- `PageComponent` checks `SectionKit.known?` first, then uses the mapped class or the generic component. It iterates saved order unchanged, retains custom inserted known types, skips unknown types, and never synthesizes sections, couples neighboring sections, writes records or restores source on read.
- Public show and same-page admin preview pass actual website/page context, localized read-only copies, and same-site published/nav-visible navigation in saved order. Contact's closing renders purpose-led route cards for the existing Platform/Pricing records in that order, then the saved signup action. Page titles and signup labels/hrefs remain authoritative. Each card has one anchor, a runtime-localized description and a decorative arrow; unpublished/hidden destinations and invalid/blank signup are omitted, and remaining cards reflow without placeholders. Descriptions use `website.home_site.contact.routes.{platform,pricing,workspace}` at request time, not new saved props. Signup is a next step, not an enquiry submission.
- Scoped Header/Footer and MobileNavSheet reuse the existing locale and href helpers, saved website name/footer and mobile-nav controller. Desktop and sheet include the runtime-translated signup action; the sheet stays a sibling of the blurred sticky header. Scoped pixel-size Tailwind utilities, responsive stacked layouts, native FAQ details and existing media helpers supply the presentation. The header and footer brand mark is `Branding::SapphireLogoComponent` — the same violet diamond as `/81721200/admin/dashboard` — rendered decoratively at `h-7` beside the saved site name.
- The edit view passes `presentation:` through Composer → ComposerSections → every SectionEditor. Only the eligible page's existing top-level `headline` control becomes a textarea in a fresh schema copy. All `[data-prop]` controls, values and field keys remain present; shared SectionFields metadata is not mutated. Generic editors retain their existing controls.

| Stored type | Scoped component under `Websites::HomeSite` | Consumed props / internal variant |
|---|---|---|
| `hero_centered` | `HeroComponent` | Existing eyebrow/headline/subhead, media and action pairs; Home/Platform `:lead` (renders `ProductMockupComponent` and the trust row), Pricing `:pricing`, About `:about`, Contact `:contact` (split photo layouts) |
| `proof_strip` | `StatsComponent` | `items[{value,label}]`; `:stats`, a one-to-four-column figure band |
| `logo_cloud` | `MarqueeComponent` | `heading, items[{name}]`; `:marquee`, an endless industries ribbon whose duplicate run is `aria-hidden` |
| `comparison_table` | `ComparisonComponent` | `kicker, heading, subhead, column_1..n, rows[{title,value_n}]`; `:comparison`, first named column highlighted |
| `ai_preview` | `DraftComponent` | Existing board labels, brief, review note and draft items |
| `feature_grid`, `steps` | `IndexComponent` | `kicker, heading, subhead, items[{title,body}]`; capabilities/principles/foundation/process variants, plus `:assistant` for the page's `home_site_<page>_assistant` section (a violet-tinted bento whose six cards span four desktop columns: a dark aurora first card and a violet–fuchsia gradient last card each span two; other counts use an even grid) |
| `split_image_text`, `rich_text` | `StoryComponent` | `heading, body`, optional `image_url, image_side`; `:story`, `:editorial`, `:contact_note`; stories add up to two decorative chips from `website.home_site.story_chips.<role>` |
| `card_grid` | `PerspectiveComponent` | `kicker, heading, subhead, cards[{title,body,image_url,href}]` |
| `pricing` | `PlansComponent` | `kicker, heading, subhead, featured_label, tiers` with existing price/features/action fields |
| `faq` | `FaqComponent` | `kicker, heading, items[{question,answer}]`; native details |
| `cta_band` | `CtaComponent` | `headline, body, button_label, button_href`; `:closing` or `:contact_next_steps` with localized nav context |

The specialized base takes `props:, theme:, customer_id:, variant: nil, page_role: nil, nav_pages: []`. Variants are internal Ruby symbols, not new stored marketing props. Blank optional content, empty lists and missing/invalid media omit cleanly; invalid CTA destinations render plain label text. Routes, schema, controllers and global theme retain their existing contracts. The mobile-modal refinement extends the existing `website_nav_controller.js` rather than adding a controller.

Every hero is a dark `bg-slate-950` stage with blurred violet/fuchsia/sky aurora blobs and staggered fade-up entrances. The Home/Platform lead hero adds a localized, decorative `ProductMockupComponent` (a workspace window with sidebar, stat tiles and a records table, exposed as one labelled image; its SVGs are `aria-hidden` and `focusable="false"`). About and Contact heroes split copy and a glowing photo frame with floating chips; they stack copy before photo on mobile. Capability panels use cycling gradient icon tiles; the draft board, process rail, gradient stats figures, marquee and comparison table follow the same violet palette. Pricing's centered hero flows into four equal-height plan cards; the featured card sits inside a violet–fuchsia–sky gradient frame (`p-0.5`) over a deep-indigo surface with white text, lifted on desktop, and carries the “Most popular” badge. Its foundation is a soft-tinted three-card band. Contact uses an informational availability panel and three route cards. Shared closings use white-on-dark branded surfaces with the trust row, and the footer retains saved columns and Coming soon. Styling is chosen by page role and section type, never by wording or position. The one ID-sensitive choice is the assistant showcase: `variant_for("feature_grid", id:)` returns `:assistant` only for the exact source role id `home_site_<page>_assistant`, so owner-added or opaque feature grids keep the page-role variant.

Animations (`animate-marquee`, `animate-float`, `animate-aurora`, `animate-fade-up`) are declared in `app/assets/tailwind/application.css` with Tailwind v4 `@utility`, so `motion-reduce:animate-none` overrides them. Under reduced motion the marquee stops, its list wraps and centers inside the viewport, and its edge mask is removed.

All card groups stack naturally on small screens; three-card groups use one/two/three responsive columns and plan cards become four columns on desktop. The comparison table keeps two-column comparisons within the viewport on phones (stacked icon-over-text cells, narrower padding, a logo-free hero pill) and scrolls horizontally only when more than two columns are present. Maintain 44 px targets, readable text, visible focus and contrast at 320/390/768/1024/1440 px and 200% zoom. Decorative geometry/icons are noninteractive and hidden from accessibility output; they add no image assignments, testimonials or product controls. Saved section order and owner-edited props remain authoritative.

#### Native mobile navigation and verification

`Websites::HomeSite::MobileNavSheetComponent` renders a native `<dialog>` beside the header. The transparent dialog fills the viewport; its right-aligned inner sheet is `min(20rem,88vw)` wide with scrollable navigation. The saved site name supplies `aria-labelledby`; the translated close button has `autofocus`. Published saved navigation and signup remain ordinary locale-aware anchors. Generic `Websites::MobileNavSheetComponent` retains its div panel and separate backdrop.

The shared `website-nav` controller detects a DIALOG with `showModal`/`close` support, opens it in the browser's modal top layer, and synchronizes trigger `aria-expanded` and translated label values. Native modal focus starts on close and makes background controls inert, including programmatic focus attempts. Tab/Shift+Tab stay out of background controls; browser chrome may receive focus at the sequential-navigation boundary. No hand-written focus trap is used. Escape dispatches native `cancel`; `cancel->website-nav#close:prevent` routes closure through controller state/scroll cleanup without a second document-keydown close. The close button and clicks whose target is the transparent dialog itself dismiss it; clicks inside the sheet do not.

Opening locks `<html>` while preserving its previous inline overflow value; closing restores that value and returns focus to the trigger when it is visible. Resize to the desktop breakpoint (1024 px) closes/unlocks, while compact resize keeps the modal open. Disconnect removes global listeners, closes any retained open native-dialog reference even when Stimulus targets have disappeared, and unlocks the root so the page cannot remain inert. Non-dialog panels retain visibility toggling, backdrop dismissal and document-keydown Escape behavior.

The unit contract in `spec/javascript/controllers/website_nav_controller.test.js` requires **100% lines, branches and functions** under `npx vitest run --coverage`, covering native API/state/cleanup and generic-panel behavior. Its mocked dialog API establishes open-state behavior, not browser focus guarantees. `spec/e2e/website_native_dialog.app.spec.js` uses Playwright against `APP_BASE_URL`: EN/zh-CN at 320/390/768 px exercise real `:modal` state, close autofocus, inert-background focus rejection, sequential Tab/Shift+Tab and Escape/focus return. It also covers self-only backdrop versus inner-sheet clicks, close-button dismissal, desktop resize and controller disconnect restoring background interactivity. The browser suite allows native browser-chrome Tab boundaries and blocks non-GET/HEAD requests.

#### Release-driven visual refinement

The application's `text-base/sm/xs/lg/xl/2xl` tokens are compact admin sizes, not standard Tailwind sizes. The isolated marketing presentation therefore uses explicit pixel utilities: body/actions 16 px, lead and card headings 18 px, supporting/nav/footer copy 14 px, badges/copyright 12 px, wordmark 20 px, and compact section headings 24 px. Pricing's reference note uses readable 16 px text. Normal-width hero headings scale 36–66 px (the lead hero reaches 84 px on desktop) and section headings 30–52 px. Hero and dark closing headings explicitly use `text-white`. Global typography/theme tokens are not retuned.

The 1280 px container and 20 px mobile gutters remain. Home, Platform, Pricing, About and Contact share that container's inner width: hero copy, section introductions, card grids, FAQ rows, editorial columns, Contact route cards and the closing band use the same left and right edges. The FAQ heading sits above a full-width list, so its rows line up with the plan cards, foundation cards and closing band. Heroes are full-bleed dark stages whose content stays in that container; the stats band is white with gradient figures and desktop dividers; tinted bands and the footer use the same content width. The header's bottom rule is the same content width. Main sections and closings use `py-16 lg:py-24`, the stats band `py-14 lg:py-20` and the marquee `py-12 lg:py-14`. Draft panels and footer have tighter padding; plan cards use `gap-4`, natural mobile body height, and 14 px features with 20 px leading and 6 px gaps. Footer columns become three at 380 px, two at 280 px, and one below; every footer link is at least 44×44 px. Below 280 CSS pixels, the header puts the full wordmark above wrapping controls with automatic height, headline/price sizes step down, nested panels reduce padding, and `min-w-0`/`overflow-wrap:anywhere` permit reflow without hiding content.

The scoped native-details language popup stays `right-0` at normal widths. Below 280 CSS pixels, `max-[280px]:-right-12` compensates for the adjacent 44 px menu button and 4 px gap; its viewport-bounded width then fits within both 20 px gutters, retaining full language labels and keyboard GET links. The native sheet's title/close row uses 12 px gutters below 240 px, 20 px from 240 px and 32 px from `sm`, aligning its close button with the tablet header trigger. `spec/e2e/website_language_popup.app.spec.js` checks opened popup/link/text bounds and keyboard locale navigation at 150/160/195 CSS px in both languages, blocking non-GET/HEAD requests; the existing responsive tablet test covers close/trigger alignment.

Pricing's hero subhead carries the reference note: **“Start free and upgrade only when you're ready to grow. Reference monthly prices in USD — plans, trials, currency and charges are confirmed in workspace billing.” / “免费起步，准备好增长时再升级。以下为美元月度参考价格，具体方案、试用、币种与费用以工作空间账单为准。”** Its extended bottom padding lets the plan cards overlap the dark hero. A copy-only leaf patch cannot add the stats, marquee or comparison sections or the photos; the redesign requires explicit structural application after a fresh content/media comparison. Fresh release captures must verify first-viewport, content-driven page lengths and zoom after rebuilding assets.

#### Bundled photos and illustrations

The redesign assigns six bundled **WebP photos** under `public/site-images/anysys/`, served at `/site-images/anysys/anysys-photo-<name>.webp` and shared by both locales:

| Photo | Default role |
|---|---|
| `anysys-photo-studio-owner.webp` | Home website story |
| `anysys-photo-team-collab.webp` | Platform website story |
| `anysys-photo-desktop-night.webp` | Home and Platform Windows panels |
| `anysys-photo-about-team.webp` | About hero |
| `anysys-photo-craft.webp` | About craft story |
| `anysys-photo-contact.webp` | Contact hero |

`Websites::Href.media?` accepts these through `Websites::Href::BUNDLED_PHOTO_PATH` (`/site-images/anysys/anysys-photo-[a-z0-9-]+.webp`, whole value, no query/fragment). `SectionComponent#valid_media?` additionally requires the file to exist under `public/`, so a missing photo omits its frame instead of rendering a broken image. Photos render as native `<img>` elements, not through `IllustrationComponent`.

The source has **11 image assignments / 6 unique photos**: one per website story, About hero, About craft and Contact hero, plus both Windows panels explicitly repeating `anysys-photo-desktop-night.webp` in all three `cards[*].image_url` fields. This prevents `Media.fill` from filling blank card images with stock photos. All card hrefs are blank. Foundation, capabilities, the assistant showcase, principles, process entries, stats, marquee, comparison and the Home/Platform/Pricing heroes have no assigned media.

The scoped frontend's default budget is **seven rendered placements**: Home 2, Platform 2, Pricing 0, About 2, Contact 1. Each Windows panel renders its first repeated image once. Stories, panels and split heroes use 4:3 frames; hero media is eager. Distinct owner uploads/HTTPS images on later Windows cards remain meaningful supplementary media. This default budget does not restrict custom content.

All **15** original SVG illustrations also remain in `public/site-images/anysys/`, served at `/site-images/anysys/<filename>.svg`, but the redesign assigns none of them by default; owners can still choose them. The static base files are word-free, without scripts, external resources, embedded text or outlined word glyphs. Uploads/imports still accept JPEG, PNG, WebP and GIF (8 MB maximum), not SVG. Asset security checks cover every file.

| SVG filename | In-scene labels (en) |
|---|---|
| `anysys-home-workspace-hero.svg` | Records; Website |
| `anysys-platform-workspace-hero.svg` | Records |
| `anysys-pricing-growth-hero.svg` | Plan |
| `anysys-about-idea-hero.svg` | Idea |
| `anysys-contact-conversation-hero.svg` | Idea; Goals |
| `anysys-ai-draft.svg` | Draft |
| `anysys-website-draft.svg` | Draft |
| `anysys-brand-studio.svg` | Theme |
| `anysys-review-publish.svg` | Preview |
| `anysys-records-forms.svg` | Records; Forms |
| `anysys-members-payments.svg` | Members; Payments |
| `anysys-email-sms.svg` | Email; SMS |
| `anysys-local-desktop.svg` | Local data |
| `anysys-record-control.svg` | Records |
| `anysys-local-privacy.svg` | Local data |

After `Href.media?` validation, `SectionComponent#render_media` selects `IllustrationComponent.new(src:, alt:, css_class:, eager: false)` only for an exact path in its complete 15-scene map. HTTPS images and uploads retain their native-image or `FittedPhotoComponent` path. Rendering never reads or inlines owner-supplied SVG. The composed frame aligns the native `<img>` with an SVG nameplate overlay using the source viewBox and centered crop. Stored src/alt, loading and `decoding="async"` remain intact; the overlay is noninteractive, `aria-hidden="true"`, `focusable="false"`, and the native image is the sole image accessibility node. Essential meaning stays in adjacent HTML and alt context.

All 15 overlay definitions and **20 labels** are retained. Metadata holds stable I18n keys, translated and escaped per request, including `website.home_site.illustration.local_data` (“Local data” / “本地数据”), `.idea` (“Idea” / “想法”), `.goals` (“Goals” / “目标”) and `preview.draft`. Labels are independent of saved section text/order and add no live status, price or privacy guarantee. Overlay rendering performs no record write, seed or source restore.

#### Localization and saved content

`HomeSiteLocalization` creates read-only Website/WebsitePage copies for customer 81721200. Current English/Chinese source definitions supply exact-match translations for page/nav titles, section leaves, tagline, footer and SEO. Pages match by saved slug; sections match by type and stable source id, with unambiguous same-type text fallback for retained ids. Nested list matching uses field paths and source text, not list positions. Conflicting translations and owner text differing from both source locales remain literal. IDs, URLs, controls, theme, saved order, additions/deletions and flags are not rewritten.

Eligible admin previews assign those read-only copies to the view's `@website` and `@page` after the controller applies any POST draft overlay. The document layout therefore uses localized page/SEO titles and meta descriptions in both regular and embedded previews, while owner literals remain literal. Rendering does not write records; other tenants and ineligible pages retain their existing metadata behavior.

**Deploying source files does not update old saved wording or composition.** Text from an earlier revision that matches neither current source locale remains literal. Structural changes use explicit saved-content application; the earlier copy-only leaf patcher cannot change the section map. The builder edits stored strings. The scoped admin-preview contract localizes only in-memory copies, just like public presentation; neither path saves or restores content.

Native language-switch GET links retain full accessible language names. `PublicComponent#href_for` propagates locale through home/nav, section/footer actions and signup when the request explicitly selects a valid locale or differs from the default. Explicit English therefore survives an older Chinese cookie. Addressable merges the parameter once, preserving other query values/fragments; external HTTPS destinations/media remain unchanged, and stored URLs are never rewritten.

#### Explicit structural application and identity preservation

```ruby
# Preview either source locale without database writes:
Websites::HomeSite.definition(locale: :en)
Websites::HomeSite.definition(locale: :"zh-CN")

# Deliberate full restore after content/media review:
Websites::HomeSite.apply!(locale: :en)
```

`apply!` also accepts `locale: :"zh-CN"`; it has no `customer_id:` argument. The platform customer and an active global Website module must already exist. Missing/inactive global module errors do not activate/register the module or alter global configuration. `Current.customer` does not change the target.

The customer lock encloses site writes, assignment enablement, provisioning and five page writes in one transaction. `SaveSite` saves a missing site before provisioning, avoiding starter pages; assignment configuration is retained. Each page is validated through `SavePage(..., structure_editable: true)`. A **full source restore intentionally resets** the five source pages' text, structure, source order, publication/nav flags and source-site metadata/theme. Website/WebsitePage row identities and existing site skeleton/default-layout and page layout keys survive; missing source pages are recreated. Extra pages retain their complete content, flags and positions. Other tenants and media blobs are not mutated. Any later validation failure rolls back the whole restore.

Section ID preservation is page-local and independent of positions/copy:

1. Reserve all exact source-ID matches first, including changed types. Then reserve matching semantic source roles before any type fallback. Role extraction accepts only actual `home_site_<page>_<role>` ids with a recognized page prefix; arbitrary owner/opaque suffixes are not semantic evidence.
2. A known source ID for a different or removed role cannot be borrowed by another role just because the type matches. Home's `home_site_home_website` survives `bento_grid` → `split_image_text`, and `home_site_home_hero` survives `hero_cinematic` → `hero_centered`. About's `home_site_about_craft` survives `rich_text` → `split_image_text` without consuming mission identity. New roles (`home_site_home_stats`, `home_site_home_industries`, `home_site_home_assistant`, `home_site_platform_assistant`, `home_site_platform_comparison`, `home_site_about_stats`) receive their source ids; surviving plan/foundation/FAQ/CTA IDs retain their mappings.
3. Only unambiguous remaining opaque predecessors can fall back by current or documented legacy type: Home cinematic hero/website bento, Platform capability bento/alternating process, About principle bento/craft rich text. There must be one candidate and one remaining role for that type. Two unmatched About rich-text roles cannot guess ownership of one opaque rich-text predecessor. Ambiguous mappings use stable source ids; the application report records them for review.
4. Each predecessor id is consumed once. Source IDs are reserved against fallback, blank ids are excluded, and duplicate legacy ids cannot appear twice in the result. Repeated application keeps unique deterministic ids.

For the reviewed existing site, the release/content operation must:

1. Export site metadata, five source pages, extra-page snapshots, section roles/ids and all custom media references before writes. Review the intentional source resets and removed slots against that backup.
2. Explicitly apply the approved source, then rehome reviewed custom media through SavePage in the same outer transaction. Map surviving website/desktop/About/Contact roles; the default photos replace earlier SVG assignments, and custom assignments need an explicit reviewed destination. Resolve ambiguous media mappings before applying; preserve blobs, layout keys and record removed-slot references in the report.
3. Report before/after role/ID/media mappings and intentional resets/removals. Verify source defaults, no stock additions, stable site/page IDs, unique section IDs and untouched extra pages/other tenants. Repeated-apply checks belong in specs/disposable data, rather than applying again over reviewed live custom media.
4. Preview saved content in both locales and verify builder multiline save/reload, publication-aware Contact links, responsive page lengths and the seven-placement default budget. Source hashes alone do not establish live appearance.

`db:seed` restores only if customer 81721200 exists and its Website is missing. Existing sites, owner edits and missing individual pages are left alone. No migration or public read automatically applies the redesign.

#### Reference plans and availability qualifications

Only Pricing generates tiers from `Billing::StandardPlans::CATALOG`; Home contains none. Every price, page/entity/member limit and trial comes from that catalog, using the existing interpolated I18n quota/trial keys. Both request languages show USD, not a locale-driven currency switch.

| Plan | USD / month | Page-builder pages | Custom record types | Member seats | Trial |
|---|---:|---:|---:|---:|---|
| Free | $0 | 10 | 5 | 1 | None |
| Starter | $29 | 50 | 25 | 5 | 14 days |
| Pro | $99 | 500 | 200 | 25 | 14 days |
| Enterprise | $499 | Unlimited | Unlimited | Unlimited | 14 days |

The visible hero subhead states that prices are USD monthly references confirmed in workspace billing. The plans section stores blank kicker/heading/subhead, so the cards follow the hero directly. Tier names are Free / 免费版, Starter / 入门版, Pro / 专业版 and Enterprise / 企业版, each with a promotional one-line body; Starter is `highlight: "featured"` with the “Most popular” / “最受欢迎” badge. All four CTA labels are “Start building free” / “免费开始构建” and link only to `/auth/sign_up`, with no plan parameter, selection or purchase implication.

Free/trial figures are reference-guide data. Actual billing counts Page/form pages rather than WebsitePage marketing pages, entity definitions rather than records, and member-role accounts rather than admins. Workspace billing governs accepted offers/currency/trials/limits. HomeSite does not query/update live plans or seed billing on read. The source FAQ still says administrator accounts are counted; that marketing copy differs from the enforced member counter, as noted below.

Windows panels (“Windows desktop app · Coming soon” / “Windows 桌面应用 · 即将推出”), the Home hero, SEO description, Platform comparison row and footer all say **Coming soon** whenever they mention the desktop app. The shared panel explains local hosting on a Windows machine the customer manages, record control and intended privacy from Anysys for locally hosted records in the upcoming app. The Home FAQ explicitly says no download is available; the Home FAQ covers forthcoming AI connections, external services and backup details. There is no offline guarantee, launch date, download or waitlist action. Contact points existing customers to the workspace Help menu's support conversation and new visitors to signup; it collects no enquiry and invents no email, phone or address. Its closing offers published Platform/Pricing navigation and signup.

### Controllers

`FeatureModules::Website::Registration` key is `"website"`. Its entry path, module card, Modules sidebar, and Content → Website Pages shortcut point at `/:customer_id/admin/modules/website`. The list, new page, and editor select **Content → Website Pages** in the top menu, while their record sidebar stays under Modules. The Forms sidebar contains only form records. The Website Pages shortcut appears only when the URL customer's Website module is available. Settings point at `/:customer_id/admin/settings/modules/website`. `entries_for("pages")` lists `WebsitePage.for_current_customer`. Each list row shows the page's public address from `PageShortcuts::PublicPath.website_page` (mounted under `SCRIPT_NAME`), the same address the editor shows — for example `/` and `/pricing` for customer 81721200 rather than `/81721200/site` and `/81721200/site/pricing`.

`Admin::Modules::Website::PagesController#index` renders the list at both `/admin/modules/website` and `/admin/modules/website/pages`; `/admin/pages/website` no longer routes to a Website action (the generic Pages show route returns 404 for that id). `Admin::Modules::Website::BaseController` 404s unless `FeatureModules::Website::Registration.enabled_for?(current_customer_id)`. Role checks stay in `RouteAuthorization`: these admin URLs are admin or owner. The platform catalog is under `/admin/maintenance/platform/` and is `platform_owner?` only.

`Admin::Modules::Website::PagesController` creates and updates through `SavePage`. A request with header `X-Website-Composer: 1` gets JSON `{ ok: true }` or 422. `preview` accepts POST body sections onto the in-memory page (`apply_draft_preview`) and renders layout `website`. `reorder` calls `ReorderPages`. `destroy` calls `DestroyPage`. Reordering and deleting return to the module list.

`MediaController#create` calls `UploadMedia` directly and returns `{ url }` or 422. Site publication is saved by `Admin::Settings::Modules::Website::SitesController#update` with `website[published]`; `/admin/modules/website/publication` has no route.

`Admin::Settings::Modules::Website::SitesController` updates the site, including its publication switch. `SkeletonsController#create` calls `ReplaceSkeleton` with `skeleton_key`. Replacing a skeleton deletes the current pages. The website pages status strip reports site status and page count without exposing site settings or a publishing control.

Platform: `Admin::Maintenance::Platform::Website::SkeletonsController` (`show`, `edit`, `update`, `preview`) and `LayoutsController` (`index`, `new`, `create`, `edit`, `update`, `preview`). Both call `Websites::Catalog.sync!` on the index/show. Layout forms render `ComposerComponent` with `structure_locked: false`.

`preview` (via `Websites::CatalogPreview#render_catalog_preview`) renders a catalog entry full size in layout `website`, themed with `Theme.for_catalog(key)`, inside an owner toolbar (`Websites::Admin::CatalogPreviewBarComponent`: back, name, page switcher, edit). Skeleton previews take `?page=<slug>` (unknown slugs fall back to home) and `Websites::Admin::CatalogPreviewNavComponent` keeps nav links inside the preview. The `Website` is built in memory and nothing is saved. Gallery cards show Preview (new tab) beside Edit. Both routes sit under the owner-only `/admin/maintenance/platform/` prefix.

### Admin screens

New page (`/:customer_id/admin/modules/website/pages/new`) has two steps side by side. From `lg` up the details card sticks beside the gallery; below `lg` it follows the gallery.

- Step one is `Websites::Admin::LayoutPickerComponent`. It groups the catalog layouts with `Websites::LayoutFamily.group`, putting the site's own starter first and standalone layouts last under "General pages". `LayoutFamily.of` maps a layout key to the longest starter key that prefixes it (`saas_*` maps to `saas_landing`); any other key is `standalone`.
- The filter chips are:
  - Suggested: the site's `default_layout_key` plus its starter's layouts. This is the initial filter whenever it is not empty.
  - All.
  - Each category in `Websites::Skeletons.categories`, plus general.
- Each card is a `website_page[layout_key]` radio inside a `<label>`. Its thumbnail is a `CatalogThumbnailComponent` of the first three sections in the site's own theme. The thumbnail is `aria-hidden` and its preview is `inert`, so screen readers do not read its copy as part of the radio's name and keyboard focus skips its links.
- Step two is a card with `PageIdentityComponent` (identity only), `LayoutSummaryComponent` (name, description, section list), and a submit button.

Edit page:

- The header is the page title, one Published/Draft pill, and `Websites::Admin::PageAddressComponent` (the public path), with Preview and Save on the right. The path becomes a new-tab link only when both the site and the page are published. The same path labels the preview frame through `ComposerComponent`'s `public_path:`; the frame sits on `bg-canvas` with an icon-only device switcher.
- The locked workspace side panel has two levels. The default is a vertical outline (`[data-workspace-outline]`): a Page settings row, then one numbered row per section with its type and a one-line preview. Choosing a row drills into the inspector for that section (or for page identity).
- `ComposerSectionsComponent#step_for` passes `step: { number:, total:, previous:, next: }` to `SectionEditorComponent`. The inspector header has a back button (`website-builder#showOutline`), the type name with a muted inline "X of N" (`data-section-position`) and the type description as its `title` tooltip, up/down Previous and Next buttons (`data-section-step`) that call `website-builder#focusSection`, the section Design trigger, and reset.
- **The inspector stays clean-minimal.** Workspace field blocks (`[data-field-section]`) are separated by quiet dividers with no group headings, and secondary controls stay hidden until needed. With a mouse (`pointer-fine`), these controls fade in only on hover or focus: field and list Design triggers (on their `group/design` element), the list-item move/duplicate/remove toolbar (on `group/item`, wide panels only), the photo **Remove** button and image-link button (on `group/media`), and the link field's **Choose page** toggle (on `group/link`). The rich-text hint shows only while its field has focus. Touch devices always show every control. Open (`aria-expanded`) and edited (`data-edited`) triggers stay visible.
- **Design sits beside each element.** `SectionEditorComponent` builds one `StylePanelComponent` per element. `FieldHeaderComponent` renders that element's `StyleTriggerComponent` (a paintbrush icon, `reveal: true`) at the right edge of its label row: each text field (`field_design`), the first button label (the shared `buttons` target), and each list header (`list_design`: the `items` target plus every list-item text field, one accordion row each, after the add button). The section trigger (`section_design`) sits in the inspector header and is always visible; its panel opens directly under the header. Every trigger has the same size (`size-7`, `size-9` on touch). Elements with overrides show an accent dot (`data-edited`). `FieldHeaderComponent` gives every label row the same minimum height, so triggers line up in one column.
- Each panel is a hidden inline card under its element with the target name, **Reset design** (resets that panel only; content reset leaves styles alone) and a close button. The section panel also holds the segmented `surface`, `spacing` and `align` controls from `SectionFields.style_fields`, followed by **Custom background**, fonts and text scale. Colors use `StyleColorFieldComponent`: a theme-default swatch, the theme tokens drawn in the page theme's real colors, a 16-color palette and a custom color picker. Sizes, italics, alignment and button shape are segmented controls; fonts and weight are selects. The platform marketing presentation has no Design panels. Layout and skeleton editors (non-workspace composer) use the same panels, with the section trigger in each section's summary row.
- Page settings include a **Theme** select (`website_page[theme_key]`, or `website_layout[theme_key]` for platform layouts) described in [websites](websites).
- An unlocked composer (platform catalog) gets no step navigation.

### Stimulus

`website_builder_controller.js` (`website-builder`) keeps `website_page[sections_json]` aligned with the sortable section list (SortableJS, unless `structureLockedValue`), reloads the preview iframe, uploads images to `uploadUrl`, and confirms setting a new home page. Targets include `list`, `row`, `json`, `previewFrame`, and `previewStage`. The server passes labels as Stimulus values. In the locked workspace, `focusSection` switches the side panel to the inspector level and scrolls `[data-workspace-inspector]` to the top; `showOutline` returns to the outline and focuses the row of the section just edited, and `focusIdentity` opens page settings. When the click came from a `data-section-step` button, focus also moves to the matching section tab, because the clicked button is now hidden. An AJAX save keeps the open inspector.

Design controls carry `data-style-prop` inside a `[data-style-target]` group instead of `data-prop`; `#propsFromRow` folds checked or chosen non-blank values into `props.styles` and omits the key when nothing is set. Each `[data-style-panel]` starts `hidden`; `toggleStyle` opens or closes the panel named by the clicked button's `aria-controls`, syncs `aria-expanded` on its `[data-style-trigger]`, opens any collapsed `<details>` around it, and returns focus to the trigger when closed from inside the panel. `pickStyleColor` copies the color input into its sibling custom radio, `resetStyles` returns the controls of its own panel to the theme default, and `markDirty` refreshes the list accordion dots and the triggers' `data-edited` flag. After each preview load, `#bindPreviewPicking` adds one capture click listener to the same-origin iframe document: clicking a `[data-site-el]` node opens that section's inspector, opens the matching Design panel (and list accordion row), focuses its first control, and outlines the node in `highlightColorValue`. Clicks on unmarked nodes, or on targets without a Design group, pass through.

Live-preview POSTs carry the complete current form without persisting it. Every content edit invalidates earlier preview responses immediately, including during the debounce interval. Only the current revision may replace the iframe or dismiss its loading state; slower responses cannot restore an older partial draft. The revision counter is initialized once in Stimulus `initialize()` and remains monotonic across reconnects of the same controller instance. Saved-preview reloads and controller disconnect invalidate pending draft HTML and cancel the debounce timer; reconnecting cannot make a response from the previous connection current again, including non-OK responses, network failures and response-body errors. Lifecycle unit regressions exercise real disconnect/reconnect with deferred responses and preserve the separate image-upload guard through failures and invalid JSON. The composer browser regression checks the successful matching POST, its exact sections payload, all edited sections in the iframe, and saved-value restoration after reload.

In source, `initialize()` sets `previewRevision = 0` once; `connect()` does not reset it. `markDirty()` reaches `#scheduleLivePreview`, which increments before debounce. `reloadPreview()` and `disconnect()` increment again and clear the timer. `#pushLivePreview` captures that revision before fetch, checks it after reading HTML, and gates non-OK/exception cleanup before `previewLoaded()`. The 2026-10-12 follow-up added 8 real lifecycle/upload regressions: the controller suite passed 175/0 at 100% lines/branches/functions, and the completed full JS run passed 6,956/0. Exact artifacts are in `docs/audits/2026-10-11-javascript-verification.md`; final combined RSpec/Playwright outcomes belong to their execution reports.

Scalar image previews and array-item thumbnails accept bundled artwork consistently with `Websites::Href.media?`: the whole raw value must match `/site-images/anysys/anysys-[a-z0-9-]+.svg` (literal `.svg` suffix) or a bundled photo `/site-images/anysys/anysys-photo-[a-z0-9-]+.webp` (literal lowercase `.webp` suffix), without surrounding whitespace, controls, backslashes, traversal, nested directories, queries or fragments. HTTPS and tenant-media previews retain their existing surrounding-whitespace handling.

`website_layout_picker_controller.js` (`website-layout-picker`) runs the new-page gallery:

- It filters cards by chip (`filterValue`: `all`, `suggested`, or a category) and by the lowercase `data-layout-search` text.
- It hides family groups that end up empty, and shows the empty state with a reset button.
- It writes the visible count from `countFormatsValue` (`{ one, other }` templates with `{count}`).
- It copies the checked card's `data-layout-*` values into the `summary*` targets.
- Escape clears the search.

`website_theme_picker_controller.js` previews theme tokens on the settings screen (writing the chosen pairing, corner and tone CSS variables onto the preview), applies a preset's token set from its `data-tokens` JSON (`applyPreset`), toggles the **Customized** badge when tokens drift from the checked preset, and drives its "On this page" scrollspy. Below `xl` that nav is a horizontal chip strip, and `revealNav` scrolls the active chip into view without moving the page. `website_nav_controller.js` handles both the scoped native modal and generic div sheet as described above, with desktop-resize/disconnect cleanup. Open/close labels are translated Stimulus values with English defaults.

## Where to pay attention

### Route audit: validated writes and actual-byte media

`SaveSkeleton`/`SaveLayout` and catalog models now validate whole structures before decoration. `Contracts::Sections` validates known types, unique IDs and JSONSchemer prop shapes/list bounds/options; skeletons require exactly one blank-slug home, valid unique inner slugs and known layouts. Apply/provision/replace validate all shortcut reservations under the same customer lock before destructive replacement. `SavePage` reloads current scoped state before applying submitted fields; explicit false publication and locked template merges cannot rely on stale dirty tracking. HomeSite source restore explicitly reapplies page positions after that reload.

Incoming locked-section types are not decorated before the saved type is resolved: changing a quote's incoming type to a hero cannot add hero image fields to the quote. Metadata-only saves leave content and empty templates untouched, including legacy-invalid content when taking a page offline. The Page contract's `validate_sections:` option is chosen server-side from newness, section dirty state and explicit publication; callers cannot disable it through submitted params.

Array bounds and missing required lists report localized count/bounds errors through `website.errors.array_count`; malformed prop shape uses `website.errors.invalid_props`. The assistant's schema validator keeps its precise field/count error instead of adding a second generic contract failure. Test uploads use worker-aware roots and explicitly stamped source fixtures; see [Background jobs](background-jobs).

Upload/import classify actual raster bytes and stamp tenant/website-media identity. Public AssetsController enforces MediaPolicy, verifies downloaded size/MIME, serves validated raster content with nosniff, and rejects generic/legacy unclassified signed blobs. Provisioner raises ProvisioningError on a failed Result. AI apply validates fresh draft rows and captures deep-copied Undo state under conversation → customer → ordered page locks; Undo reloads provenance and checks conflicts within the same write boundary. See [Websites](websites), [AI assistant](ai-assistant), [Module framework](module-framework).

Marketing reference prices remain monthly USD catalog data, not subscription selection. Billing now counts member-role accounts only; the existing saved/source FAQ wording describing admins as counted accounts is stale and still needs copy integration. Seed offerings remain monthly; annual catalog offerings are owner-created and only usable through a compatible billing provider. See [Billing](billing).

:::note
The targeted Website service/request/model/module-hook and storage-isolation cohort passed 572 examples with no failures. It exercises real Disk storage and MIME bytes, catalog contracts, locked overlays, stale unpublish and assistant validation. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Browser results still require their own run.
:::

:::attention
`Websites::Admin::ComposerComponent` and `website_builder_controller.js` edit `WebsitePage` sections. They do not write `Page#configuration` or `form_settings.flowchart_id`. Maintenance forms stay on [Page builder](page-builder). Public form submit stays on [Page rendering](page-rendering).
:::

:::attention
`Websites::Activities::SavePage` defaults `structure_editable: false`. `locked_sections` keeps the layout's section ids and types and replaces `props` only. `Admin::Modules::Website::PagesController` does not pass `structure_editable: true`. The tenant edit view sets `ComposerComponent` `structure_locked: true`. Adding a section type is a platform layout or skeleton edit (`SaveLayout`, `SaveSkeleton`), where the composer is unlocked. Two tenant-side callers pass `structure_editable: true`: `Websites::Assistant::Processor`, only after `SchemaValidator` has accepted the whole document, and `Websites::Assistant::Undo#revert!`, which only puts back the sections a page had before an assistant reply revised it. The platform-only `Websites::HomeSite.apply!` source restore also passes this flag deliberately.
:::

:::attention
`ReplaceSkeleton` validates structure/collisions before `Skeletons.apply!(..., replace: true)` deletes old pages. `SaveSite` still excludes `skeleton_key`; the settings skeleton POST performs replacement.
:::

:::attention
`FeatureModules::Website::Provisioner.deprovision` sets `published` to false. `Websites::PagesController` then 404s without rendering the site name. `Websites::AssetsController` still requires `blob.customer_id` to match the URL, even though the signed id is unguessable.
:::

:::attention
`Websites::NavComponent` mounts `website-nav` on a `contents` wrapper and renders the mobile sheet beside the `<header>`. The generic fixed div sheet must stay outside the blurred header, whose containing block would otherwise shrink it to header height. The scoped native dialog also stays a sibling, but `showModal()` puts it in the browser's viewport-sized top layer. The controller locks scrolling on `<html>`, not `<body>`, and restores the previous root overflow on close/disconnect. The layout's `overflow-x-clip` on `<html>` prevents body-only locking from controlling viewport scrolling.
:::

## Key code

```ruby
# app/services/feature_modules/website/registration.rb
      def self.module_key         = "website"
      def self.module_name        = "Website"
      def self.module_description = "Customer introduction and marketing website — static pages, no forms"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.deprovision(customer)
```

```ruby
# app/models/website.rb
  has_many :pages, -> { order(:position) },
           class_name: "WebsitePage",
           dependent: :destroy,
           inverse_of: :website

  validates :customer_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :skeleton_key, presence: true
```

```ruby
# app/services/websites/activities/save_page.rb
        unless structure_editable
          if page.persisted? && page.layout_key.present?
            attrs.delete(:layout_key)
          elsif page.persisted? && attrs.key?(:sections)
            inferred = Websites::Catalog.infer_layout_key(page.sections)
            if inferred.present?
              attrs[:layout_key] = inferred
            else
              attrs.delete(:layout_key)
            end
          elsif page.persisted?
            attrs.delete(:layout_key)
          else
            attrs[:layout_key] = resolve_layout_key(page, attrs)
          end
          attrs[:sections] = locked_sections(page, attrs) if attrs.key?(:sections) || !page.persisted?
        end

        if attrs.key?(:sections) && (!page.persisted? || attrs[:sections] != page.sections)
          attrs[:sections] = Websites::Skeletons.decorate_sections(attrs[:sections])
        end

        page.assign_attributes(attrs)
        validate_sections = !page.persisted? || page.will_save_change_to_sections? || attrs[:published] == true
        contract = Websites::Contracts::Page.new(page, validate_sections: validate_sections)
```

```ruby
# app/services/websites/activities/replace_skeleton.rb
result = Websites::Activities::ReplaceSkeleton.call(site: site, skeleton_key: key)
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
# app/controllers/concerns/websites/current_site.rb
    def call_website_activity(name, **kwargs)
      "Websites::Activities::#{name}".constantize.call(**kwargs)
    end
```

Related: [Module framework](module-framework), [Websites](websites), [Page builder](page-builder), [Member and public](member-and-public).

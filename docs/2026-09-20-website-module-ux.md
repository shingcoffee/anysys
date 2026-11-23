# Website module — UX spec

**Date:** 2026-09-20  
**Audience:** frontend developer. ViewComponent + Tailwind + Stimulus only. There is no React shadcn in the runtime.  
**Follows:** `docs/2026-09-20-website-module-design.md` (locked). Do not reopen product questions.

Visual language splits in two. **Admin** must look like every other module: `AdminPageComponent` / `Admin::Modules::PageComponent`, `AdminTableComponent`, `.card`, `section-header`, `form-label`, `input-field`, `BadgeComponent`, `ButtonComponent`, `EmptyStateComponent`, `SectionNavComponent`, `AlertComponent`. **Public** must look like a marketing site cloned from Apple / Stripe / Linear / Nike / Airbnb cards — full-bleed, large type, real hierarchy. Public **must not** use `layouts/public_page.html.erb` (centered form card, `noindex`).

shadcn analog (mental map only — deliver as project ViewComponents + Tailwind):

| shadcn | Project delivery |
|---|---|
| Card | `CardComponent` / `.card` + `card-header` |
| Button | `ButtonComponent` (`primary` / `secondary` / `danger` / `ghost`) |
| Badge | `BadgeComponent` |
| Tabs | `SectionNavComponent` (real paths, underline) |
| Empty | `EmptyStateComponent` |
| Separator | `border-t border-border-subtle` (no new CSS framework) |
| Sheet | Public mobile nav panel (new `Websites::MobileNavSheetComponent` + Stimulus `website_nav`). Do **not** reuse the admin entity `slide-over` turbo-frame. |
| ToggleGroup | Segmented `inline-flex` bordered group (same pattern as payments mode tabs) for theme tokens |

All chrome strings: I18n `en` + `zh-CN` in `config/locales/website.en.yml` / `website.zh-CN.yml`, plus `feature_modules.website.*` and one platform nav key. English value = the string that would otherwise have been hard-coded. Authored section body copy lives in JSON (English at provision); do not auto-translate it. Never bake `t()` into a Ruby constant.

Roles: `owner` / `admin` may build. `member` is not a builder. Public visitors are an audience, not a role.

Out of scope (no screens): media library, custom domain / DNS / TLS, blog, search, analytics, sitemaps, AI generate-entire-site, embedding form Pages, payments/captcha on the site, freeform HTML/CSS/JS.

---

## 1. Surface inventory

Paths follow the live app (`/:cid/admin/...`).

| # | Surface | Nav area | URL | Audience | Notes |
|---|---|---|---|---|---|
| A | Pages index | Modules | `GET /:cid/admin/modules/website` | `admin` / `owner` | Page list. Site publish badge + actions in the header. |
| B | New page | Modules | `GET/POST /:cid/admin/modules/website/pages/new` | same | Identity only; lands on C after create. |
| C | Page composer | Modules | `GET/PATCH /:cid/admin/modules/website/pages/:id/edit` | same | Authoring B: add / remove / reorder kit sections. |
| D | Admin preview | Modules | `GET /:cid/admin/modules/website/pages/:id/preview` | same | Same public components; **ignores** `published`. Not a public URL. |
| E | Site settings | Settings | `GET/PATCH /:cid/admin/settings/modules/website` | same | Identity, theme, SEO, footer, site publish, replace-skeleton. |
| F | Enable / disable | Maintenance / Modules | existing `GET /:cid/admin/maintenance/modules` | same | **No redesign.** Website row appears after `register!`. |
| G | Platform Overview / Configuration / Developer | Maintenance / Platform / Module Settings | existing `/:cid/admin/maintenance/platform/module_settings/website` (numeric id OK) | `owner` on `81721200` | **No redesign** of Overview / Configuration / Developer. Configuration already renders `default_skeleton_key`. |
| H | Skeletons gallery | Maintenance / Platform / Module Settings | `GET /:cid/admin/maintenance/platform/module_settings/website/skeletons` | `owner` on `81721200` | **New tab.** Read-only catalog of the four code skeletons. |
| P | Public home | public | `GET /:cid/site` | anonymous (and signed-in users as visitors) | Beauty-critical. Published home only. |
| Q | Public inner page | public | `GET /:cid/site/:page_slug` | same | Published, non-home page. |

Sidebar (after the module is enabled):

- **Modules / Website** → A (`entry_path`)
- **Settings / Website** → E

No member builder surface. Members who open A–E get the existing member 403/redirect. Members may load P/Q like anyone else.

Public POST is not routed. Disabled module, unpublished site, unpublished page, missing slug, or missing home → **404 with no body leak** (standard app 404; do not render the site name, nav, or page title).

---

## 2. Layout spec per surface

### Shared admin chrome

Entries (A–C) wrap `Admin::Modules::PageComponent` with `module_key: "website"` so the identity tile uses `MODULE_ICON_PATHS` + `module_color_classes`.

Add to `Admin::Maintenance::Platform::ModuleSettingsHelper`:

```
MODULE_ICON_PATHS["website"] =
  "M12 21a9 9 0 100-18 9 9 0 000 18zm0 0c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3M3.6 9h16.8M3.6 15h16.8"

module_color_classes("website") → "bg-purple-100 text-purple-700"
```

(Globe path matches the locale-switcher mark. Purple is unused by the six existing module tints.)

Breadcrumbs always start with Modules (hub-linked by `Admin::Modules::PageComponent`) or Settings.

Flash stays in the dashboard layout (do not duplicate inside these components).

Width:

| Surface | `content_for :container_width` |
|---|---|
| A, B | default admin `:full` |
| C | `:full` (explicit) |
| E | default settings `:wide` |
| G, H | existing module-settings shell |
| D, P, Q | **not** dashboard — `layouts/website.html.erb` |

---

### A — Pages index (`Modules / Website`)

**Components:** `Admin::Modules::PageComponent` → `AdminTableComponent`.

**Header**

- Title: `website.admin.pages.index.title` → `Website`
- Description: `website.admin.pages.index.description` → `Build the public introduction site for this organization.`
- Badges (after title, `AdminPageComponent#badges`):
  - Site published → `{ label: t("website.admin.pages.index.site_live"), variant: :success }`
  - Site unpublished → `{ label: t("website.admin.pages.index.site_unpublished"), variant: :warning }`
- Actions (right of title):
  1. If unpublished: secondary **Publish site** → PATCH settings `published=true` (or `path` to E with anchor `#publish` if PATCH from index is awkward — prefer a `button_to` in the header using `AdminPageComponent` `form:` / `data: { turbo_method: :patch }`). Label: `website.admin.pages.index.publish_site` → `Publish site`.
  2. If published: secondary **View site** (`tag: :a`, `target: _blank`, `rel: noopener`) → `/:cid/site`. Label: `website.admin.pages.index.view_site` → `View site`.
  3. Primary **New page** (`icon: :plus`) → B. Label: `website.admin.pages.index.new_page` → `New page`.

Do **not** put skeleton-replace on this header (that lives on E, warned).

#### ASCII — desktop

```
[Modules > Website]
[globe tile] Website  [Site live | Unpublished]     [View site] [Publish site] [+ New page]
             Build the public introduction site for this organization.

+--------------------------------------------------------------------------+
| Search pages...                                      5 results           |
+----------+--------+------------+---------+------+------------------------+
| Title    | Slug   | Published  | In nav  | Home | Updated                |
+----------+--------+------------+---------+------+------------------------+
| Home     | /      | Draft      | Yes     | Home | Sep 20, 2026           |
| About    | about  | Draft      | Yes     | —    | Sep 20, 2026           |
| Services | services | Draft    | Yes     | —    | Sep 20, 2026           |
| …        |        |            |         |      |                        |
+--------------------------------------------------------------------------+
```

Column mapping (`WebsitePage`):

| Column | Field | Type | Notes |
|---|---|---|---|
| Title | `title` | text | Leading document icon (`leading: { icon: :document, tone: :accent }`). Subtitle: public path (`/site` or `/site/:slug`). |
| Slug | `slug` | text | Home shows `t("website.admin.pages.index.home_slash")` → `/`. Else the slug. `font-mono text-caption`. |
| Published | `published` | badge | `common.status.published` / `common.status.draft` (`success` / `default`). |
| In nav | `nav_visible` | boolean | `common.labels.yes` / `no`. |
| Home | `home` | badge | Home row: `{ variant: :primary, label: t("website.admin.pages.index.home_badge") }` → `Home`. Others: em dash. |
| Updated | `updated_at` | datetime | relative + `time` title. |

Row click → C (`row_path` to edit).

Row actions:

- **Edit** → C
- **Preview** → D (`target: _blank`)
- **Delete** → `DELETE`, `tone: :danger`, `data-turbo-confirm`. Hidden/disabled on `home` (DestroyPage refuses). Confirm: `website.admin.pages.destroy.confirm` → `Delete this page? This cannot be undone.`

Optional up/down in the row menu call `Websites::Activities::ReorderPages` (positions). First row: Move up omitted; last: Move down omitted. Labels: `website.admin.pages.index.move_up` / `move_down` → `Move up` / `Move down`.

Search: `q` on `title` and `slug`. Placeholder: `website.admin.pages.index.search_placeholder` → `Search pages...`

Filter (optional chip, one select): Published / Draft / All. Key `published`. Labels reuse `common.status.*`.

**Empty** (`EmptyStateComponent` via `empty_state:`): title `website.admin.pages.index.empty_title` → `No pages yet`; description `website.admin.pages.index.empty_description` → `Pages appear here after the Website module is enabled.`; action New page. (Should not appear after successful provision — home always exists.)

**Empty after search:** AdminTableComponent built-in empty-after-search.

**Loading:** server-rendered table. No skeleton.

**Error:** standard flash. Module disabled → 404 (controller `require_website_module!`), not an in-page empty.

**Mobile:** table already horizontally scrolls. Header actions wrap (`flex-col gap-4 sm:flex-row`). Keep all three actions visible; do not hide New page behind a menu.

---

### B — New page

**Components:** `Admin::Modules::PageComponent` + one `.card` form (`max-w-xl`).

Breadcrumbs: Modules > Website > New page.  
Title: `website.admin.pages.new.title` → `New page`.  
Description: `website.admin.pages.new.description` → `Add a page to this site, then compose its sections.`  
Primary header action: Save bound to the form (`common.actions.create` → `Create`). Secondary: Cancel → A.

Fields (Reform `Websites::Contracts::Page`):

| UI | Model | Control |
|---|---|---|
| Title | `title` | `input-field`, required |
| Slug | `slug` | `input-field`, `font-mono`, hint below |
| Show in navigation | `nav_visible` | checkbox, default on |
| Published | `published` | checkbox, default off |

Slug hint: `website.admin.pages.form.slug_hint` → `Lowercase letters, numbers, and hyphens. The home page uses /site with a blank slug.`

Do **not** offer “this is the home page” on create (exactly one home already exists).

#### ASCII

```
[Modules > Website > New page]
New page                              [Cancel] [Create]
Add a page to this site, then compose its sections.

+--------------------------------------+
| Title                                |
| [                                ]   |
| Slug                                 |
| [                                ]   |
| Lowercase letters, numbers, and …    |
| [x] Show in navigation               |
| [ ] Published                        |
+--------------------------------------+
```

**Validation error:** inline `text-sm text-danger` under the field + stay on B.  
**Success:** redirect to C. Flash: `website.admin.flash.page_created` → `Page created.`

**Mobile:** single column, same card, full-width buttons in the header strip (existing AdminPageComponent wrap).

---

### C — Page composer (Authoring B)

This is the builder. Beauty of the **preview** matters; the **editor** stays admin-dense.

**Components:** `Admin::Modules::PageComponent` (width `:full`) wrapping `Websites::Admin::ComposerComponent`.

Breadcrumbs: Modules > Website > `{page.title}`.  
Title: page title (record, not I18n).  
Description: `website.admin.pages.edit.description` → `Add, reorder, and edit sections from the marketing kit.`  
Badges: Published / Draft; Home if `home`.  
Actions:

1. Ghost **Preview** → D (`target: _blank`). `common.labels.preview` → `Preview`.
2. Primary **Save** bound to form `website-page-form`. `common.actions.save`.

Body: two-pane on `lg+`; stacked below.

```
lg+ (grid grid-cols-[minmax(20rem,26rem)_minmax(0,1fr)] gap-6 items-start)

+---------------------------+  +------------------------------------------+
| PAGE IDENTITY             |  | PREVIEW                                  |
| Title / Slug / toggles    |  | iframe → D?embed=1                       |
|                           |  | framed in public theme, rounded-xl       |
| SECTIONS (sortable)       |  | border border-border-subtle shadow-sm    |
| [Add section ▾]           |  | min-h-[40rem] bg-neutral-100             |
| 1. hero_split      [↑↓🗑] |  |                                          |
|    fields…                |  |  (same Nav + sections + Footer as P/Q)   |
| 2. proof_strip     [↑↓🗑] |  |                                          |
| …                         |  |                                          |
+---------------------------+  +------------------------------------------+

< lg: identity → sections → preview (preview below, iframe min-h-[28rem])
```

Stimulus host: `data-controller="website-builder"` on the form.

Hidden field: `website_page[sections_json]` (or equivalent) kept in sync by the controller. Server validates via `Websites::Contracts::Section`.

#### C.1 Identity card (`.card p-4 flex flex-col gap-4`)

Heading: `website.admin.pages.edit.identity` → `Page`.

| UI | Field | Notes |
|---|---|---|
| Title | `title` | required |
| Slug | `slug` | disabled + blank when `home`; hint as on B |
| Show in navigation | `nav_visible` | checkbox. Label `website.admin.pages.form.nav_visible` → `Show in navigation` |
| Published | `published` | checkbox. Label `website.admin.pages.form.published` → `Published`. Hint: `website.admin.pages.form.published_hint` → `The public URL 404s until both this page and the site are published.` |
| Home | `home` | If already home: checked, disabled, caption `website.admin.pages.form.home_locked` → `This is the home page (/site).` If not home: checkbox with `data-turbo-confirm` on save is insufficient — show a confirm only when checking. Copy: `website.admin.pages.form.set_home_confirm` → `Make this the home page? The current home will become an inner page and must keep its slug.` |

#### C.2 Section list

Toolbar:

- Heading `website.admin.pages.edit.sections` → `Sections`
- Primary-sm **Add section** opens the kit picker. `website.admin.pages.edit.add_section` → `Add section`

Kit picker (not a new URL):

- Desktop: popover panel under the button (`absolute z-20 mt-2 w-full sm:w-[28rem] card p-3 shadow-lg`).
- Mobile: full-width panel immediately below the toolbar (same markup, not `fixed` — avoid fighting the admin sidebar). Do **not** use a second Stimulus controller; `website-builder#toggleKit` is enough.

Picker contents: 12 kit types as a `grid grid-cols-1 sm:grid-cols-2 gap-2`. Each cell is a button:

```
[ Cinematic hero     ]
[ Full-bleed chapter with kicker, headline, and optional image. ]
```

`text-left rounded-lg border border-border-subtle px-3 py-2 hover:border-accent-muted hover:bg-surface-hover`. Title = section type name (I18n). Caption = one-line description (I18n). Click → append `{ id, type, props: empty-defaults }`, close picker, expand the new row.

Empty section list (page with `sections: []`):

```
+--------------------------------------+
|  (document icon tile)                |
|  No sections yet                     |
|  Add a section from the kit to       |
|  start this page.                    |
|  [Add section]                       |
+--------------------------------------+
```

`website.admin.pages.edit.no_sections_title` → `No sections yet`  
`website.admin.pages.edit.no_sections_description` → `Add a section from the kit to start this page.`

Each section row (`.rounded-lg border border-border-subtle bg-surface`):

```
[≡]  Cinematic hero                    [↑] [↓] [🗑]
     {headline or first prop preview}
────────────────────────────────────────────────
(expanded) prop fields — see §2.P section editors
```

- Drag handle: `data-website-builder-target="handle"`, `cursor-grab`, 20px grip icon, `aria-label` `website.admin.pages.edit.drag` → `Drag to reorder`.
- Type name: `BadgeComponent` default + I18n type name.
- Collapse/expand the body via `<details>` (no JS) **or** `website-builder#toggleSection`. Prefer `<details open>` for the newly added row and the first row; others collapsed so the list scans.
- Up / Down: also present for keyboard and for when drag is unavailable. `aria-label` Move up / Move down. Disabled at ends.
- Delete: ghost danger. Confirm `website.admin.pages.edit.delete_section_confirm` → `Remove this section from the page?` (client `confirm()` is OK here because it is an in-form edit, not a server destroy; alternatively `data-confirm` via Stimulus. Do not silently drop.)

Unknown `type` in stored JSON: skip on public render (locked). In the builder, show a warning row: `website.admin.pages.edit.unknown_section` → `Unknown section type` + remove button. Do not crash.

#### C.3 Prop editors (in-row)

All labels I18n. Controls: `form-label` + `input-field` / `textarea` (`rows=3`) / select. Image fields are **URL strings** (no uploader). Empty image → preview uses gradient placeholder.

Href fields: placeholder `website.admin.pages.form.href_placeholder` → `about or https://example.com`. Hint: `website.admin.pages.form.href_hint` → `A page slug on this site, or an https:// URL.`

Array props: stacked mini-cards with Add / Remove. Respect contract min/max (proof_strip 4–6). Disable Add at max, Remove at min; do not silently ignore.

| type | Fields (admin labels → English) |
|---|---|
| `hero_cinematic` | Kicker, Headline, Subhead, Primary label, Primary link, Secondary label, Secondary link, Image URL, Tone (`light` / `dark` select) |
| `hero_split` | Eyebrow, Headline, Subhead, Primary label, Primary link, Secondary label, Secondary link, Visual URL |
| `proof_strip` | Items[]: Label, Value (4–6) |
| `bento_grid` | Heading; Cells[]: Span (`hero` / `wide` / `unit`), Title, Body, Image URL |
| `alternating_features` | Heading; Items[]: Title, Body, Image URL |
| `card_grid` | Heading, Subhead; Cards[]: Title, Body, Image URL, Link |
| `team_grid` | Heading; People[]: Name, Role, Bio, Image URL |
| `quote` | Quote, Attribution, Role |
| `faq` | Heading; Items[]: Question, Answer |
| `cta_band` | Headline, Body, Button label, Button link |
| `rich_text` | Heading, Body (textarea; hint: blank lines become paragraphs. HTML is escaped.) |
| `split_image_text` | Heading, Body, Image URL, Image side (`left` / `right`) |
| `contact_info` | Heading, Address, Email, Phone, Hours |

Tone / span / image_side: native `<select class="input-field">`, not a third JS widget.

Rich text hint: `website.admin.pages.form.rich_text_hint` → `Plain text. Blank lines become paragraphs. HTML is escaped.`

#### C.4 Preview pane

Right pane (below on mobile):

- Chrome label `website.admin.pages.edit.preview_label` → `Preview`
- Caption when form dirty (Stimulus adds/removes `.hidden`): `website.admin.pages.edit.unsaved` → `Unsaved changes — save to refresh the preview.`
- `<iframe>` `src` = D with `?embed=1`, `title` = preview label, `class="w-full min-h-[40rem] rounded-xl border border-border-subtle bg-white"`.
- On successful Turbo save, reload the iframe (`website-builder#reloadPreview`).

Do **not** try to live-bind keystrokes into the iframe in this slice.

**Empty / error / loading (preview):**

- Iframe loading: a sibling overlay `flex items-center justify-center text-caption text-text-muted` `website.admin.pages.edit.preview_loading` → `Loading preview…` hidden on iframe `load`.
- Save validation error: stay on C, expand the first invalid section, inline errors. Preview stays on last good save.
- Destroy home: cannot happen here (no destroy control on composer). Index delete is refused with flash `website.admin.flash.page_destroy_home` → `The home page cannot be deleted.`

**Success:** flash `website.admin.flash.page_saved` → `Page saved.`

---

### D — Admin preview

**Layout:** `layouts/website.html.erb` (the public layout). **Not** the dashboard. **Not** `public_page`.

Ignores `website.published` and `website_page.published`. Still tenant-scoped. Member/anon → existing auth redirect/403 then not this action.

`?embed=1`: omit the admin ribbon so the composer iframe is clean.

Without embed: a slim ribbon above the public nav, `bg-warning-subtle text-warning text-caption px-4 py-2 text-center`:

`website.admin.preview.banner` → `Admin preview — unpublished pages are visible here.`

Plus a text link **Edit page** → C (`website.admin.preview.edit` → `Edit page`).

Body: identical to P/Q — `Websites::NavComponent` (nav includes pages that are `nav_visible`, **including unpublished**, so the admin can click through the draft site) + `Websites::PageComponent` + `Websites::FooterComponent`. Theme tokens from the saved site.

Unknown section types skipped.

**Mobile:** same as public (§2.P).

---

### E — Settings / Website

**Components:** `AdminPageComponent` (not `Admin::Modules::PageComponent` — match Captcha settings). Optional identity tile via `icon_path` / `icon_class` from the same helper so the page is recognizable.

Breadcrumbs: Settings > Website.  
Title: `website.admin.settings.title` → `Website`.  
Description: `website.admin.settings.description` → `Site identity, theme, SEO, footer, and publish.`  
Primary header action: Save bound to `website-settings-form`.  
Secondary: **View site** (new tab) — disabled styling + `aria-disabled` when unpublished, still a link only when published.

Body: vertical stack `flex flex-col gap-6`. One `form_with` wrapping identity + theme + SEO + footer + publish. Skeleton replace is a **separate** `button_to` so it cannot ride along with Save.

shadcn analog: Card + FieldGroup + ToggleGroup + Separator between cards.

#### ASCII

```
[Settings > Website]
Website                                          [View site] [Save]
Site identity, theme, SEO, footer, and publish.

+-- Site identity ----------------------------------------+
| Site name   [ Acme Institute                         ]  |
| Tagline     [ Craft, research, and public programs   ]  |
+---------------------------------------------------------+

+-- Theme ------------------------------------------------+
| Appearance   ( Light | Dark )                           |
| Accent       ( Azure | Ink | Gold | Forest | Rose )     |
| Type         ( Sans | Serif | Display )                 |
| Density      ( Spacious | Compact )                     |
| [ live swatch strip: primary btn + kicker + page bg ]   |
+---------------------------------------------------------+

+-- SEO --------------------------------------------------+
| SEO title          [                                   ]|
| Meta description   [                                   ]|
+---------------------------------------------------------+

+-- Footer ------------------------------------------------+
| Blurb  [                                               ]|
| Columns                                                 |
|  [ Heading: Visit ]  links: Label / URL  [+ Add link]   |
|  [ Heading: Legal ]  …                                  |
|  [+ Add column]                                         |
+---------------------------------------------------------+

+-- Publish ----------------------------------------------+
| Site published                    [ toggle ]            |
| When off, every public /site URL returns 404.           |
+---------------------------------------------------------+

+-- Replace with skeleton  (danger card) -----------------+
| Destroys every page on this site and recreates them     |
| from a starter. This cannot be undone.                  |
| Skeleton  [ Presence ▾ ]                                |
| Current starter: Presence                               |
| [Replace pages with skeleton]   btn-danger              |
+---------------------------------------------------------+
```

**Data mapping (`Website`):**

| Card | Fields |
|---|---|
| Identity | `name`, `tagline` |
| Theme | `theme.appearance`, `theme.accent`, `theme.type`, `theme.density` |
| SEO | `seo.title`, `seo.description` |
| Footer | `footer.blurb`, `footer.columns[]` `{ heading, links[] { label, url } }` |
| Publish | `published` |
| Skeleton | `skeleton_key` used as the replace target (select), display-only current key |

Theme controls: segmented groups (payments mode-tab pattern):

```
inline-flex w-full sm:w-auto flex-wrap rounded-md border border-border overflow-hidden
each option: btn btn-sm rounded-none px-3 py-2
selected: bg-accent text-white
unselected: bg-surface text-text-secondary hover:bg-surface-hover
```

Hidden input stores the current token. Clicking a segment sets it (tiny Stimulus action on `website-builder` is the wrong controller — this is settings). Use **server-rendered radio inputs visually skinned as a toggle group** (no JS): visually hidden radio + label. That keeps Vitest at 100% without a settings controller.

Live swatch (server-rendered from current saved values, updates after Save — not live): a row showing a fake primary chip in the accent color + a 40×24 page-bg chip. Optional; if skipped, still OK. Prefer including it so admins see Light/Dark + Azure before opening the public site.

Footer columns: reuse the countable-items mental model (`SortableJS` via `countable-items-reorder` **or** fold footer-column reorder into a small `website-builder` subset). Prefer **reusing `countable-items-reorder`** on the column list so we do not invent a third sortable. Each column card: heading input, nested links (label + url), Add link, Remove column. Max columns: 4. Max links per column: 8.

Publish toggle: `Admin::Maintenance::Platform::ModuleToggleComponent` is PATCH-immediate and platform-specific — **do not reuse it here**. Use a checkbox + Save, with the existing switch Tailwind from `ModuleToggleComponent` copied into a settings checkbox label **or** a simple checkbox in the card. Keep it on Save so publish is an explicit primary action. Index header “Publish site” is the one-click path.

**Skeleton replace card**

- Container: `border-danger/20 bg-danger-subtle/40` (still `.card`).
- Heading: `website.admin.settings.skeleton.heading` → `Replace with skeleton`
- Description: `website.admin.settings.skeleton.description` → `Destroys every page on this site and recreates them from a starter. This cannot be undone.`
- Select of four keys, labels from `website.skeletons.*.name`.
- Caption current: `website.admin.settings.skeleton.current` → `Current starter: %{name}`
- Submit: `ButtonComponent variant: :danger` `website.admin.settings.skeleton.action` → `Replace pages with skeleton`
- `data-turbo-confirm`: `website.admin.settings.skeleton.confirm` → `Replace all pages with the %{name} skeleton? Existing pages and their sections will be deleted. This cannot be undone.`

First provision is silent (no warning). This card is the only warned path.

**Empty:** not applicable (one site row after provision). If the module is enabled but provision failed, show `AlertComponent` error `website.admin.settings.missing_site` → `This organization has no website record yet.` and no form. Do not invent a create-site wizard.

**Validation error:** inline + flash `website.admin.flash.site_save_failed` → `Website settings could not be saved.`  
**Success:** flash `website.admin.flash.site_saved` → `Website settings saved.`  
**Replace success:** redirect to A, flash `website.admin.flash.skeleton_replaced` → `Pages replaced with the skeleton.` New pages are unpublished (`published` default false). Site `published` flag is left unchanged; if the site was live, public `/site` 404s until the new home is published. Mention that in the flash description if a second sentence is needed: `website.admin.flash.skeleton_replaced_hint` → `New pages are unpublished. Publish the home page to put the site back on /site.`

**Mobile:** cards stack; segmented groups wrap (`flex-wrap`); footer column cards full width.

---

### F — Maintenance / Modules

**Do not redesign.** After `register!`, the existing list grows a row:

- Title: feature module display name `Website`
- Description: `Customer introduction and marketing website — static pages, no forms`
- Enable / Disable as today (`common.actions.enable` / `disable`)
- Enable → `provision!` (silent first site from `presence` or platform `default_skeleton_key`)
- Disable → `deprovision!` (unpublish site, keep rows)

No Website-specific empty/error on this index.

---

### G — Platform Overview / Configuration / Developer

**Do not redesign.** Overview / Developer stay generic.

Configuration already renders `configuration_schema.default_skeleton_key` as a string field. Leave it. The Skeletons tab (H) is the visual catalog; this field is the provision default.

Add a `SectionNavComponent` tab **Skeletons** for `module_key == "website"` (see H). Overview / Configuration / Developer labels unchanged (`maint_platform.module_settings.show.nav.*`).

New nav key: `maint_platform.module_settings.show.nav.skeletons` → `Skeletons`.

---

### H — Platform Skeletons gallery

**Audience:** owner on `81721200` only. Tenants never mutate the catalog.

**Shell:** existing `Admin::Maintenance::Platform::ModuleSettings::ShellComponent` with `current: :skeletons`.

**Body:** `Websites::Admin::SkeletonsGalleryComponent`.

Title in the pane (not the page h1 — shell already shows “Website”): section header `website.platform.skeletons.heading` → `Skeletons`.  
Description: `website.platform.skeletons.description` → `Read-only starters cloned into a customer site at provision. Tenants cannot edit this catalog.`

#### ASCII

```
[Overview | Configuration | Skeletons | Developer]

Skeletons
Read-only starters cloned into a customer site at provision. …

+---------------------------+  +---------------------------+
| Presence        [Default] |  | SaaS landing              |
| Classic introduction …    |  | Product landing in the    |
| Pages: Home About …       |  | Stripe / Linear register. |
| +-----------------------+ |  | Pages: Home About Contact |
| | mini Home preview     | |  | +-----------------------+ |
| | (pointer-events-none, | |  | | mini Home preview     | |
| |  scale-50 origin-top) | |  | +-----------------------+ |
| +-----------------------+ |  |                           |
+---------------------------+  +---------------------------+
| Cinematic                 |  | Editorial                 |
| …                         |  | …                         |
+---------------------------+  +---------------------------+
```

Grid: `grid grid-cols-1 lg:grid-cols-2 gap-4`.

Each card (`.card overflow-hidden`):

- Header `px-4 py-4 sm:px-6`: name + optional Default badge (`website.platform.skeletons.default_badge` → `Default` when `key == configuration default_skeleton_key`) + description + page chips (`BadgeComponent` default, page titles from skeleton `PAGES` — these are catalog labels, I18n page role names: Home / About / Services / Team / Contact / Stories — `website.platform.skeletons.pages.*`).
- Preview frame: `h-64 overflow-hidden bg-neutral-100`. Inside: render **Home** sections of that skeleton with starter props, `Websites::PageComponent` only (no public nav), wrapped in `pointer-events-none select-none origin-top scale-[0.45]`. Use the **default public theme** (light / azure / sans / spacious) so previews compare layout, not tenant tokens.
- Entire card is **not** a link to edit. Optional: click expands a `<details>` **Home preview** below the grid (still read-only, larger scale). Do not add an editor.

No Save. No “apply to tenant” (that is tenant settings replace). No drawing tool.

**Empty:** impossible (four code constants). If a key is missing in code, omit the card.

**Loading / error:** server-rendered. Unauthorized → existing owner gate.

**Mobile:** one column; preview height `h-56`; scale may be `scale-[0.35]`.

---

### P / Q — Public site (beauty-critical)

**Layout:** new `layouts/website.html.erb`.

Must:

- Full viewport width. No centered form card. No `max-w-*` wrapping the whole page (sections set their own inner widths).
- **No** `noindex`.
- `<title>`: `{page.title} · {seo.title presence || website.name}`.
- Meta description: `website.seo.description` if present, else page headline/subhead derived (first non-blank section headline).
- `html` class from `Websites::Theme` (appearance + type). `body` class: appearance background + type font + `antialiased`.
- Locale switcher in the nav (reuse `LocaleSwitcherComponent`).
- Sticky nav + footer on every page.

Must not:

- Dashboard chrome, admin sidebar, `btn-primary` admin indigo (public buttons use **site accent**, not `--color-accent`).
- `ThemeResolver` form-card presets.
- Any `<form>` / `<input>` / `<textarea>` / `<select>` on P/Q (locale switcher POST is the sole exception, in the nav).
- `layouts/public_page.html.erb`.

404: render the app’s generic 404. Do **not** show this layout.

#### Theme tokens → Tailwind (`Websites::Theme`)

Do not use `dark:` media queries. Appearance is a stored token.

**Appearance**

| Value | Page | Nav | Footer | Muted text |
|---|---|---|---|---|
| `light` (default) | `bg-white text-neutral-950` | `bg-white/80 backdrop-blur-xl border-b border-neutral-200/70` | `bg-neutral-50 border-t border-neutral-200` | `text-neutral-600` |
| `dark` | `bg-neutral-950 text-white` | `bg-neutral-950/80 backdrop-blur-xl border-b border-white/10` | `bg-neutral-950 border-t border-white/10` | `text-neutral-300` |

**Accent** (kicker, links, filled buttons, FAQ marker)

| Value | Filled button | Text/kicker (light page) | Text/kicker (dark page) |
|---|---|---|---|
| `azure` (default) | `bg-sky-600 hover:bg-sky-500 text-white` | `text-sky-700` | `text-sky-400` |
| `ink` | light page: `bg-neutral-950 hover:bg-neutral-800 text-white`; dark page: `bg-white hover:bg-neutral-200 text-neutral-950` | `text-neutral-950` | `text-white` |
| `gold` | `bg-amber-700 hover:bg-amber-600 text-white` | `text-amber-800` | `text-amber-400` |
| `forest` | `bg-emerald-700 hover:bg-emerald-600 text-white` | `text-emerald-800` | `text-emerald-400` |
| `rose` | `bg-rose-600 hover:bg-rose-500 text-white` | `text-rose-700` | `text-rose-400` |

Ghost/secondary button: `border` current accent at 30% + transparent fill, hover tint. Cinematic chapters on `tone=dark` invert: filled button becomes `bg-white text-neutral-950 hover:bg-neutral-100` regardless of accent (Apple pattern); kicker still uses accent.

**Type**

| Value | Body | Headlines |
|---|---|---|
| `sans` (default) | `font-sans` (Inter) | `font-sans tracking-tight` |
| `serif` | `font-serif` (Iowan / Palatino — already in `@theme`) | `font-serif tracking-tight` |
| `display` | `font-sans` | `font-serif tracking-tighter` (the Inter + Iowan pairing already in the app; do not add a third font file) |

**Density** (section vertical padding + inner gaps)

| Value | Section padding | Stack gaps |
|---|---|---|
| `spacious` (default) | `py-20 md:py-28` | `gap-10 md:gap-16` |
| `compact` | `py-12 md:py-16` | `gap-6 md:gap-10` |

Cinematic heroes **ignore** density for min-height (they are chapters) but still shrink type on mobile.

**Image placeholder** (blank `image_url` / `visual_url`): a `div` with `aria-hidden="true"`, **never** `<img src="">`.

- Light: `bg-gradient-to-br from-neutral-200 via-neutral-100 to-neutral-300`
- Dark: `bg-gradient-to-br from-neutral-800 via-neutral-700 to-neutral-900`

Optional 8% accent wash: `after:absolute after:inset-0 after:bg-{accent}/10` is nice; not required.

**Shared type scale (marketing, not admin `text-subtitle`)**

| Role | Classes |
|---|---|
| Cinematic headline | `text-5xl md:text-7xl font-semibold tracking-tight leading-[1.05]` |
| Split hero headline | `text-4xl md:text-6xl font-semibold tracking-tight leading-[1.1]` |
| Section heading | `text-3xl md:text-4xl font-semibold tracking-tight` |
| Card title | `text-xl md:text-2xl font-semibold tracking-tight` |
| Subhead | `text-lg md:text-xl leading-relaxed` + muted color |
| Kicker / eyebrow | `text-xs md:text-sm font-semibold uppercase tracking-[0.18em]` + accent |
| Body | `text-base md:text-lg leading-relaxed` |
| Proof value | `text-3xl md:text-4xl font-semibold tabular-nums tracking-tight` |
| Proof label | `text-xs uppercase tracking-[0.16em]` + muted |

Inner measure for non-bleed sections: `max-w-6xl mx-auto px-4 sm:px-6 lg:px-8`.

**Mobile (all sections):** below `md`, one column. Bento becomes a vertical stack of cards. Cinematic keeps `min-h-[70vh]` but type steps down (`text-4xl` not `text-7xl`). Nav collapses to a Sheet. Footer columns stack.

---

#### Public chrome — Nav (`Websites::NavComponent`)

Sticky `sticky top-0 z-30`. Height `h-16 md:h-20`.

```
desktop (md+):
+------------------------------------------------------------------+
| {name}                 Home  About  Services  Team  Contact  文A |
| text-sm font-semibold                                            |
| tracking-tight                                                   |
+------------------------------------------------------------------+

mobile:
+------------------------------------------------------------------+
| {name}                                              [☰ Open menu]|
+------------------------------------------------------------------+
| Sheet (right, shadcn analog):                                    |
|  Close                                                           |
|  Home                                                            |
|  About                                                           |
|  …                                                               |
|  Language                                                        |
+------------------------------------------------------------------+
```

- Left: site `name` as a link to `/site`. If `tagline` present, hide it in the nav (tagline is a hero concern, not a subtitle cramped into 64px). Optional `sr-only` tagline.
- Center/right links: `published && nav_visible` pages of **this** customer, Home first if published. Current page: `text-{accent}` + `aria-current="page"`. Others: muted hover `text-neutral-950` / `text-white`.
- Locale: `LocaleSwitcherComponent` (`align: :right`).
- Mobile control: icon button, `md:hidden`. `aria-expanded`, `aria-controls` pointing at the sheet. Labels passed as Stimulus values (English defaults):  
  `website.public.nav.open` → `Open menu`  
  `website.public.nav.close` → `Close menu`
- Sheet: `fixed inset-0 z-40`. Backdrop `bg-black/40`. Panel `absolute inset-y-0 right-0 w-[min(20rem,88vw)]` appearance-matched (`bg-white` / `bg-neutral-950`) `flex flex-col gap-1 p-6 pt-16 shadow-xl`. Links `text-lg font-medium py-2`. Close button top-right. Stimulus `website-nav`: open, close, Escape, backdrop click, restore `aria-expanded`. **No other public JS.**

Home link href: `/:cid/site`. Inner: `/:cid/site/:slug`.

---

#### Public chrome — Footer (`Websites::FooterComponent`)

```
+------------------------------------------------------------------+
| {name}                 {col heading}   {col heading}             |
| {blurb, max-w-sm,      link            link                      |
|  text-sm muted}        link            link                      |
|                                                                  |
| ---------------------------------------------------------------  |
| {name}                                                           |
+------------------------------------------------------------------+
```

- Top: `py-16 md:py-20 grid grid-cols-1 md:grid-cols-12 gap-10`. Blurb `md:col-span-5`. Columns `md:col-span-7` as `grid sm:grid-cols-2 lg:grid-cols-3 gap-8`.
- Column heading: `text-xs font-semibold uppercase tracking-[0.16em]`. Links: `text-sm` muted hover accent.
- Bottom compact row: `border-t … py-6 text-xs` muted, site `name` only (no invented legal entity, no fake © year).
- Empty columns: omit the grid; blurb can stand alone. Empty blurb + empty columns: still render the compact name row so the page does not die in whitespace.

---

#### Section kit — desktop ASCII + mobile note

Each section is `Websites::Sections::<Type>Component`. Public and admin preview share them. Unknown types skipped.

Horizontal padding as above unless noted full-bleed.

##### `hero_cinematic` (Apple / Nike chapter)

Full-bleed. `min-h-[85vh] md:min-h-[92vh]` when `tone=dark`; `min-h-[56vh] md:min-h-[70vh]` when `tone=light`. Background: image `bg-cover bg-center` **or** placeholder gradient. Dark tone: `text-white` with `bg-black/35` overlay so type reads. Light tone: `text-neutral-950` overlay `bg-white/20` if image exists.

```
+------------------------------------------------------------------+
|  (full-bleed image / gradient)                                    |
|                                                                   |
|     PRODUCT                          kicker tracking-widest       |
|     Designed to be                   text-5xl md:text-7xl         |
|     remembered.                                                   |
|     Subhead one or two lines, max-w-2xl, text-lg md:text-xl       |
|                                                                   |
|     [ Primary CTA ]   Text secondary link                         |
|                                                                   |
|                                              (min-h chapter)      |
+------------------------------------------------------------------+
```

CTAs sit in the lower third (`mt-auto` inside a flex column `justify-end pb-16 md:pb-24 px-6 md:px-16`). Primary: `rounded-full px-7 py-3 text-sm font-semibold`. Secondary: text link underline-offset-4.

**Mobile:** keep min-height `min-h-[70vh]`; stack CTAs (`flex-col gap-3 items-start`); headline `text-4xl`.

##### `hero_split` (Stripe / Linear)

Not full-bleed. Inner measure. `grid md:grid-cols-2 gap-10 md:gap-16 items-center`.

```
+--------------------------------------+  +--------------------------+
| EYEBROW                              |  |                          |
| Infrastructure for                   |  |   visual / gradient      |
| ambitious teams.                     |  |   rounded-2xl            |
|                                      |  |   min-h-[22rem]          |
| Subhead, text-lg md:text-xl muted,   |  |   aspect-[4/3]           |
| max-w-xl.                            |  |   overflow-hidden        |
|                                      |  |   shadow-xl              |
| [ Get started ]  [ Secondary ]       |  |                          |
|  rounded-full filled    text link    |  |                          |
+--------------------------------------+  +--------------------------+
```

**Mobile:** copy first, visual second; visual `min-h-[16rem]`; headline `text-4xl`.

##### `proof_strip` (Stripe stats)

Inner measure. Optional hairline `border-y border-neutral-200/80` (dark: `border-white/10`).

```
+--------+--------+--------+--------+--------+
|  12k+  |  99.9% |   50   |  4.9   |  24/7  |
| Orgs   | Uptime | States | Rating | Care   |
+--------+--------+--------+--------+--------+
```

`grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6` depending on count (4–6). Centered, `py` half of density. Values accent-colored optional; prefer inheriting text color and using weight for hierarchy (less carnival).

**Mobile:** 2 columns.

##### `bento_grid` (Linear / Apple feature bento)

Heading above, then CSS grid `grid-cols-1 md:grid-cols-6 auto-rows-[minmax(12rem,auto)] gap-4`.

Span mapping:

| `span` | Desktop |
|---|---|
| `hero` | `md:col-span-4 md:row-span-2` |
| `wide` | `md:col-span-4` |
| `unit` | `md:col-span-2` |

```
+------------------------------------+  +-------------+
| HERO cell                          |  | UNIT        |
| title + body + image/gradient      |  | title       |
| rounded-2xl overflow-hidden        |  +-------------+
| min-h-[20rem]                      |  | UNIT        |
+------------------------------------+  +-------------+
| WIDE                               |  | UNIT        |
+------------------------------------+--+-------------+
```

Cell chrome: `rounded-2xl border border-neutral-200/80` (dark: `border-white/10`) `p-6 md:p-8` with image as cover on the lower half or a right wash. Title `text-xl md:text-2xl`. Body muted `text-sm md:text-base`.

**Mobile:** every cell `col-span-1`; stack; image `h-40` on top of each card.

##### `alternating_features`

Heading, then each item `grid md:grid-cols-2 gap-10 md:gap-16 items-center py-10 md:py-14`. Even index: image left; odd: image right (`md:[&:nth-child(even)]:direction` via passing `image_side` from the enumerator). Image `rounded-2xl min-h-[18rem] overflow-hidden`. Copy: title `text-2xl md:text-3xl`, body muted.

**Mobile:** image always above copy.

##### `card_grid` (Airbnb / services)

Heading + subhead centered `text-center max-w-2xl mx-auto mb-10 md:mb-14`. Cards `grid sm:grid-cols-2 lg:grid-cols-3 gap-6 md:gap-8`.

```
+------------------+  +------------------+  +------------------+
| [image 16:10]    |  |                  |  |                  |
| Title            |  |                  |  |                  |
| Body two lines.  |  |                  |  |                  |
| Learn more →     |  |                  |  |                  |
+------------------+  +------------------+  +------------------+
```

Card: `group rounded-2xl overflow-hidden border … hover:shadow-lg transition`. Image `aspect-[16/10] object-cover` or placeholder. If `href` present, the whole card is an `<a>` (no nested links). Title `text-xl`. Body `text-sm md:text-base` muted. Footer chevron `opacity-0 group-hover:opacity-100` on desktop; always visible on mobile.

**Mobile:** one column.

##### `team_grid`

Heading left-aligned. `grid sm:grid-cols-2 lg:grid-cols-3 gap-8 md:gap-10`.

```
+--------+  name                 +--------+
| photo  |  role (accent/muted)  |        |
| 1:1    |  bio, two lines max   |        |
+--------+                       +--------+
```

Photo `aspect-square rounded-2xl object-cover` or placeholder. Name `text-lg font-semibold`. Role `text-sm` accent. Bio muted `text-sm leading-relaxed`.

**Mobile:** one column; photo `max-w-[12rem]`.

##### `quote`

```
+------------------------------------------------------------------+
|  “They rebuilt how we show up                                    |
|   in public — quiet, confident,                                  |
|   exact.”                                                        |
|     — Attribution, Role                                          |
+------------------------------------------------------------------+
```

Centered, `max-w-3xl mx-auto text-center`. Quote `text-2xl md:text-4xl font-medium tracking-tight leading-snug`. Attribution `mt-8 text-sm` muted. Optional large decorative quotation mark `text-7xl` accent at 20% opacity behind — keep it subtle or skip if it fights the type token.

**Mobile:** `text-xl`; padding density.

##### `faq` (SaaS)

Heading, then a `max-w-3xl` list. **Public uses `<details>` / `<summary>`. No Stimulus. No accordion JS.**

```
Frequently asked questions
+------------------------------------------------------------------+
| ▸ What is included?                                              |
+------------------------------------------------------------------+
| ▾ How do we publish?                                             |
|   Answer as paragraph text, escaped.                             |
+------------------------------------------------------------------+
| ▸ Can members edit the site?                                     |
+------------------------------------------------------------------+
```

`divide-y`. Summary: `cursor-pointer py-5 text-base md:text-lg font-medium flex justify-between gap-4`. Marker: native disclosure triangle, or a plus that rotates via `group-open:rotate-45` **CSS only** (`<details class="group">`). Answer `pb-5 text-base` muted. Do not pull in the admin `accordion` controller.

**Mobile:** same; larger tap targets (`py-5` is enough).

##### `cta_band`

Full-bleed band in accent wash:

- Light + azure: `bg-sky-600 text-white`
- Dark appearance: still a filled band (accent at full), `text-white` except ink-on-dark which uses `bg-white text-neutral-950`

```
+------------------------------------------------------------------+
|     Ready when you are.                                          |
|     One line of supporting copy.                                 |
|     [ Talk to us ]                                               |
+------------------------------------------------------------------+
```

`py-16 md:py-24 text-center px-6`. Headline `text-3xl md:text-5xl`. Body `text-lg mt-4 max-w-2xl mx-auto opacity-90`. Button `rounded-full px-8 py-3 bg-white text-neutral-950` (or inverse on ink-dark).

**Mobile:** stack; button full width `max-w-xs mx-auto`.

##### `rich_text`

`max-w-3xl mx-auto`. Heading `text-3xl md:text-4xl`. Body: `\n\n` → `<p class="mt-4 text-base md:text-lg leading-relaxed">`. **Escape HTML** (`ERB::Util.h` / `sanitize` stripped to text). No markdown.

**Mobile:** same measure with page padding.

##### `split_image_text`

`grid md:grid-cols-2 gap-10 md:gap-16 items-center`. `image_side` `left`/`right` uses `md:order-first` / `md:order-last`. Image `rounded-2xl min-h-[22rem]`. Copy heading + body.

**Mobile:** image first regardless of `image_side` (reading order). Use `order-first` on the image at all breakpoints, then `md:order-none` according to side.

##### `contact_info` (no form)

```
Get in touch
+---------------------+  +----------------------+
| Address             |  | Email                |
| 1200 Market Street  |  | hello@example.com    |  mailto:
| Hours               |  | Phone                |
| Mon–Fri, 9–5        |  | +1 415 555 0100      |  tel:
+---------------------+  +----------------------+
```

`grid sm:grid-cols-2 gap-8 md:gap-12 max-w-4xl`. Each term `text-xs uppercase tracking-[0.16em]` muted; value `text-base md:text-lg`. Email / phone are links. **Zero** `<form>`, `<input>`, `<textarea>`, `<button type=submit>`. Blank fields omitted (do not render empty rows).

**Mobile:** one column.

---

#### Public empty / error / loading

| State | Treatment |
|---|---|
| Module disabled | Generic 404, no site chrome |
| Site unpublished | Generic 404 |
| Page unpublished / unknown slug | Generic 404 |
| No published home | Generic 404 for `/site` |
| Published page with zero sections | Nav + empty `<main>` min-height + footer. Do not show an admin empty state. A published blank page is allowed; it looks like a quiet branded shell. |
| Missing image URLs | Gradient placeholder |
| Broken image URL | `<img>` `onerror` is JS — **do not**. Server treats blank/whitespace as placeholder. If a URL is present, render `<img>`; a 404 image is an authoring mistake. Alt = section title or `""` if decorative. |
| Loading | Server-rendered. No public skeleton screens. |

---

## 3. Interaction flows

### 3.1 Enable module → first site from Presence

1. `admin`/`owner` opens `/:cid/admin/maintenance/modules` (F).
2. Clicks **Enable** on Website (`common.actions.enable`). No extra confirm (existing index only confirms Disable).
3. Server: enable + `Websites::Activities::Provision`. If no site exists, creates `websites` row (`skeleton_key` = platform `default_skeleton_key` or `presence`) and skeleton pages (Presence: Home, About, Services, Team, Contact). Pages `published: false`. Site `published: false`. Silent — no skeleton warning.
4. Redirect/stay on F with existing enable flash. Sidebar now includes Modules / Website and Settings / Website.
5. Admin opens A. Table shows five pages, all Draft, Home badge on Home, site header badge **Unpublished**.
6. Failure (module already enabled): existing enablement behavior. Provision is idempotent — second enable does not duplicate pages.
7. Permission: member hitting F is already blocked by maintenance auth. Cross-tenant: `TenantContext` 404.

### 3.2 Compose a page

1. From A, click **About** (or New page B → Create → C).
2. URL: `/:cid/admin/modules/website/pages/:id/edit`.
3. Admin expands a section, edits Headline, **Save**. Flash `Page saved.` Iframe reloads D.
4. **Add section** → kit picker → e.g. Quote. New row appears expanded with empty fields. Save persists JSON.
5. Drag or Move up/down. Save.
6. Delete section → confirm → row gone. Save.
7. Toggle Published / In nav. Save.
8. **Preview** opens D in a new tab (unpublished visible, warning ribbon).
9. Validation failure (bad href `javascript:`, unknown type, proof_strip count): stay on C, inline errors, no JSON persist.
10. Member: 403/redirect. Module disabled: 404. Other tenant id: 404.

### 3.3 Publish site + page

1. On C, check **Published** on Home, Save.
2. Public `GET /:cid/site` still **404** (site unpublished).
3. On A header, **Publish site** (or E publish checkbox + Save).
4. Site `published: true`. Header badge **Site live**. **View site** enabled.
5. `GET /:cid/site` → 200, Presence home composition, theme tokens from E.
6. Inner `GET /:cid/site/about` 404 until About is published; then 200. Nav omits unpublished and `nav_visible=false`.
7. Unpublish site from E: all public URLs 404 again; pages remain published in admin.
8. Failure: validation on E stays on E. Permission/module: as above.

### 3.4 Public visit

1. Visitor (anon or any role) `GET /:cid/site`.
2. Gates: module enabled, site published, home exists and published → 200.
3. Nav: Home first, then other `published && nav_visible` in `position` order.
4. Click About → `/:cid/site/about`.
5. Click locale globe → existing `PATCH /locale`, return to the same public URL (chrome I18n only; authored English body stays English).
6. Mobile: Open menu → Sheet → link → Sheet closes on navigate (full page load; controller `disconnect` is enough).
7. FAQ: tap `<summary>`, native expand. No JS.
8. Contact email/phone: `mailto:` / `tel:`. No form post.
9. Internal href `services` resolves to `/:cid/site/services`. External `https://` opens same tab unless author set… **same tab** (do not invent `target=_blank` unless we add a prop — we do not).
10. POST to `/site` → routing 404/405, not a flowchart.

### 3.5 Unpublished / missing / disabled → 404

| Condition | `GET /:cid/site` | `GET /:cid/site/about` |
|---|---|---|
| Module disabled | 404, no leak | 404 |
| Site unpublished | 404 | 404 |
| Home unpublished | 404 | About 200 only if page+site published |
| About unpublished | home 200 | 404 |
| Unknown slug | — | 404 |
| Reserved slug (`new`, `edit`, `preview`, `site`) | — | 404 (never a page) |
| Wrong customer id | 404 | 404 |

404 body is the generic app 404. No site name, no “this page is unpublished”, no admin edit link.

Admin preview D still 200 for those pages.

### 3.6 Replace with skeleton (warned)

1. Admin on E, danger card. Selects `cinematic`. Clicks **Replace pages with skeleton**.
2. Browser `turbo_confirm` with `Replace all pages with the Cinematic skeleton? Existing pages and their sections will be deleted. This cannot be undone.`
3. Cancel → no change.
4. Confirm → `Websites::Activities::SaveSite` replace path: destroy all `website_pages`, recreate from `Websites::Skeletons::Cinematic::PAGES`, set `skeleton_key=cinematic`. New pages unpublished. Site `published` unchanged.
5. Redirect A. Flash replaced + hint that pages are unpublished.
6. If site was live, public `/site` 404s until Home is published (3.3).
7. Failure (contract): stay on E, flash failed, pages intact.
8. First provision on Enable does **not** show this confirm.

---

## 4. Component reuse map

### Reuse as-is

| Piece | Component |
|---|---|
| Entries header, identity tile, breadcrumbs | `Admin::Modules::PageComponent` → `AdminPageComponent` + `BreadcrumbsComponent` |
| Settings header | `AdminPageComponent` |
| Page list | `AdminTableComponent` |
| Empty table / empty sections | `EmptyStateComponent` |
| Buttons, badges, flashes-in-page | `ButtonComponent`, `BadgeComponent`, `AlertComponent` |
| Platform shell + underline tabs | `Admin::Maintenance::Platform::ModuleSettings::ShellComponent` + `NavComponent` + `SectionNavComponent` |
| Platform section cards (if H wants a heading card) | `SectionCardComponent` |
| Locale switcher (public nav + admin already) | `LocaleSwitcherComponent` |
| Footer column reorder | `countable-items-reorder` Stimulus (reuse) |
| Enable row | existing maintenance modules index — **no new component** |
| Config default skeleton field | existing configuration pane |

### New ViewComponents (frontend lane)

| Component | Role | Props (conceptual) |
|---|---|---|
| `Websites::Admin::ComposerComponent` | C two-pane builder | `page:`, `website:`, `form_url:` |
| `Websites::Admin::SectionEditorComponent` | One builder row | `section:` hash, `index:` |
| `Websites::Admin::KitPickerComponent` | Add-section catalog | `types:` |
| `Websites::Admin::SettingsFormComponent` | E form cards | `website:` |
| `Websites::Admin::SkeletonReplaceComponent` | E danger card | `website:`, `skeletons:` |
| `Websites::Admin::SkeletonsGalleryComponent` | H | `skeletons:`, `default_key:` |
| `Websites::NavComponent` | Public + preview nav | `website:`, `pages:`, `current_slug:`, `embed:` |
| `Websites::FooterComponent` | Public + preview footer | `website:` |
| `Websites::PageComponent` | Maps `sections[]` | `page:`, `theme:` |
| `Websites::MobileNavSheetComponent` | Sheet markup for nav | `pages:`, `open_label:`, `close_label:` |
| `Websites::ThemePreviewSwatchComponent` | Optional E swatch | `theme:` |
| `Websites::PlaceholderImageComponent` | Gradient when URL blank | `appearance:`, `class:` |
| `Websites::Sections::HeroCinematicComponent` | kit | props |
| `Websites::Sections::HeroSplitComponent` | kit | props |
| `Websites::Sections::ProofStripComponent` | kit | props |
| `Websites::Sections::BentoGridComponent` | kit | props |
| `Websites::Sections::AlternatingFeaturesComponent` | kit | props |
| `Websites::Sections::CardGridComponent` | kit | props |
| `Websites::Sections::TeamGridComponent` | kit | props |
| `Websites::Sections::QuoteComponent` | kit | props |
| `Websites::Sections::FaqComponent` | kit | props (`<details>`) |
| `Websites::Sections::CtaBandComponent` | kit | props |
| `Websites::Sections::RichTextComponent` | kit | props (escaped) |
| `Websites::Sections::SplitImageTextComponent` | kit | props |
| `Websites::Sections::ContactInfoComponent` | kit | props (no form) |

Thin ERB wrappers under `app/views/admin/modules/website/` and `app/views/websites/` should only render these components.

Do **not** add `Dashboard::TableComponent` — that name is not in this app; lists use `AdminTableComponent`.

---

## 5. Tailwind & Stimulus notes

### Admin Tailwind

Match siblings: `card`, `card-header`, `section-header`, `form-label`, `input-field`, `text-body`, `text-body-sm`, `text-caption`, `text-subtitle` (page h1 via AdminPageComponent), `text-text-primary`, `text-text-secondary`, `text-text-muted`, `border-border-subtle`, `divide-y divide-border-subtle`, `gap-*` (prefer `flex flex-col gap-6` over `space-y-*` on new markup), `btn btn-primary` via `ButtonComponent`.

Composer preview iframe: `rounded-xl border border-border-subtle shadow-sm min-h-[40rem] w-full bg-canvas`.

Danger skeleton card: `border border-danger/20`.

### Public Tailwind (do not leak admin tokens)

Use Neutral + accent palette in §2.P. Do **not** paint public CTAs with `btn-primary` / `--color-accent` indigo. Do **not** use `text-subtitle` / `section-header` on the marketing site.

Spacious density default is the beauty bar: `py-20 md:py-28`, headlines `text-5xl md:text-7xl tracking-tight`. Compact is an opt-in.

Every section `md:` two-column / bento grid collapses to one column below `md`.

### Stimulus

**`website_nav_controller.js`** (public + preview only)

- Targets: `panel`, `backdrop`, `trigger` (optional).
- Values: `openLabel` default `"Open menu"`, `closeLabel` default `"Close menu"` — server passes `data-website-nav-open-label-value="<%= t("website.public.nav.open") %>"` (and close). Never hard-code visible strings in JS; read the values.
- Actions: `open`, `close`, `toggle`. Escape and backdrop click close. Set `aria-expanded` on trigger. Body scroll lock while open (`overflow-hidden` on `document.body`, restore on disconnect).
- FAQ must **not** use this controller.

**`website_builder_controller.js`** (composer C only)

- Targets: `list`, `row`, `handle`, `kit`, `json`, `previewFrame`, `unsaved`, `previewLoading`.
- Actions: `addSection` (from kit button `data-type`), `removeSection`, `moveUp`, `moveDown`, `toggleKit`, `markDirty`, `reloadPreview`.
- SortableJS on `list`, handle `. handle` target, same options as `countable-items-reorder` (`animation: 150`, `ghostClass: "opacity-40"`).
- Keep `json` hidden input as a stringified array of `{ id, type, props }` for the form. New ids: `crypto.randomUUID()` prefixed `sec_` if available, else `sec_${Date.now()}_${n}` (must be unique per page).
- 100% Vitest lines + branches (`spec/javascript/controllers/website_builder_controller.test.js` and `website_nav_controller.test.js`).

No other public JS. Do not add a settings Stimulus controller; theme tokens are radios.

### I18n keys (English = intended copy)

Area files: `website.en.yml` / `website.zh-CN.yml`. Also add `feature_modules.website.*` and `maint_platform.module_settings.show.nav.skeletons`, plus `admin_settings.catalog.modules.website` and `admin_settings.breadcrumbs.website`.

```yaml
# feature_modules.website
name: "Website"
entries.pages: "Pages"
settings.site: "Website"

# admin_settings
breadcrumbs.website: "Website"
catalog.modules.website: "Site identity, theme, and the public introduction website."

# maint_platform.module_settings.show.nav
skeletons: "Skeletons"

# website.* (chrome — not authored body)
admin.pages.index.title: "Website"
admin.pages.index.description: "Build the public introduction site for this organization."
admin.pages.index.search_placeholder: "Search pages..."
admin.pages.index.empty_title: "No pages yet"
admin.pages.index.empty_description: "Pages appear here after the Website module is enabled."
admin.pages.index.new_page: "New page"
admin.pages.index.view_site: "View site"
admin.pages.index.publish_site: "Publish site"
admin.pages.index.unpublish_site: "Unpublish site"
admin.pages.index.site_live: "Site live"
admin.pages.index.site_unpublished: "Unpublished"
admin.pages.index.home_badge: "Home"
admin.pages.index.home_slash: "/"
admin.pages.index.columns.title: "Title"
admin.pages.index.columns.slug: "Slug"
admin.pages.index.columns.published: "Published"
admin.pages.index.columns.nav: "In nav"
admin.pages.index.columns.home: "Home"
admin.pages.index.columns.updated: "Updated"
admin.pages.index.move_up: "Move up"
admin.pages.index.move_down: "Move down"
admin.pages.new.title: "New page"
admin.pages.new.description: "Add a page to this site, then compose its sections."
admin.pages.edit.description: "Add, reorder, and edit sections from the marketing kit."
admin.pages.edit.identity: "Page"
admin.pages.edit.sections: "Sections"
admin.pages.edit.add_section: "Add section"
admin.pages.edit.no_sections_title: "No sections yet"
admin.pages.edit.no_sections_description: "Add a section from the kit to start this page."
admin.pages.edit.delete_section_confirm: "Remove this section from the page?"
admin.pages.edit.drag: "Drag to reorder"
admin.pages.edit.unknown_section: "Unknown section type"
admin.pages.edit.preview_label: "Preview"
admin.pages.edit.preview_loading: "Loading preview…"
admin.pages.edit.unsaved: "Unsaved changes — save to refresh the preview."
admin.pages.destroy.confirm: "Delete this page? This cannot be undone."
admin.pages.form.slug_hint: "Lowercase letters, numbers, and hyphens. The home page uses /site with a blank slug."
admin.pages.form.nav_visible: "Show in navigation"
admin.pages.form.published: "Published"
admin.pages.form.published_hint: "The public URL 404s until both this page and the site are published."
admin.pages.form.home_locked: "This is the home page (/site)."
admin.pages.form.set_home_confirm: "Make this the home page? The current home will become an inner page and must keep its slug."
admin.pages.form.href_placeholder: "about or https://example.com"
admin.pages.form.href_hint: "A page slug on this site, or an https:// URL."
admin.pages.form.rich_text_hint: "Plain text. Blank lines become paragraphs. HTML is escaped."
admin.preview.banner: "Admin preview — unpublished pages are visible here."
admin.preview.edit: "Edit page"
admin.settings.title: "Website"
admin.settings.description: "Site identity, theme, SEO, footer, and publish."
admin.settings.identity.heading: "Site identity"
admin.settings.identity.name: "Site name"
admin.settings.identity.tagline: "Tagline"
admin.settings.theme.heading: "Theme"
admin.settings.theme.appearance: "Appearance"
admin.settings.theme.accent: "Accent"
admin.settings.theme.type: "Type"
admin.settings.theme.density: "Density"
admin.settings.theme.light: "Light"
admin.settings.theme.dark: "Dark"
admin.settings.theme.azure: "Azure"
admin.settings.theme.ink: "Ink"
admin.settings.theme.gold: "Gold"
admin.settings.theme.forest: "Forest"
admin.settings.theme.rose: "Rose"
admin.settings.theme.sans: "Sans"
admin.settings.theme.serif: "Serif"
admin.settings.theme.display: "Display"
admin.settings.theme.spacious: "Spacious"
admin.settings.theme.compact: "Compact"
admin.settings.seo.heading: "SEO"
admin.settings.seo.title: "SEO title"
admin.settings.seo.description: "Meta description"
admin.settings.footer.heading: "Footer"
admin.settings.footer.blurb: "Blurb"
admin.settings.footer.columns: "Columns"
admin.settings.footer.column_heading: "Heading"
admin.settings.footer.add_column: "Add column"
admin.settings.footer.add_link: "Add link"
admin.settings.footer.remove_column: "Remove column"
admin.settings.footer.link_label: "Label"
admin.settings.footer.link_url: "URL"
admin.settings.publish.heading: "Publish"
admin.settings.publish.site_published: "Site published"
admin.settings.publish.site_published_hint: "When off, every public /site URL returns 404."
admin.settings.skeleton.heading: "Replace with skeleton"
admin.settings.skeleton.description: "Destroys every page on this site and recreates them from a starter. This cannot be undone."
admin.settings.skeleton.label: "Skeleton"
admin.settings.skeleton.action: "Replace pages with skeleton"
admin.settings.skeleton.confirm: "Replace all pages with the %{name} skeleton? Existing pages and their sections will be deleted. This cannot be undone."
admin.settings.skeleton.current: "Current starter: %{name}"
admin.settings.missing_site: "This organization has no website record yet."
admin.flash.site_saved: "Website settings saved."
admin.flash.site_save_failed: "Website settings could not be saved."
admin.flash.page_saved: "Page saved."
admin.flash.page_created: "Page created."
admin.flash.page_deleted: "Page deleted."
admin.flash.page_destroy_home: "The home page cannot be deleted."
admin.flash.skeleton_replaced: "Pages replaced with the skeleton."
admin.flash.skeleton_replaced_hint: "New pages are unpublished. Publish the home page to put the site back on /site."
public.nav.open: "Open menu"
public.nav.close: "Close menu"
platform.skeletons.heading: "Skeletons"
platform.skeletons.description: "Read-only starters cloned into a customer site at provision. Tenants cannot edit this catalog."
platform.skeletons.default_badge: "Default"
platform.skeletons.pages.home: "Home"
platform.skeletons.pages.about: "About"
platform.skeletons.pages.services: "Services"
platform.skeletons.pages.team: "Team"
platform.skeletons.pages.contact: "Contact"
platform.skeletons.pages.stories: "Stories"
skeletons.presence.name: "Presence"
skeletons.presence.description: "Classic introduction site — home, about, services, team, and contact."
skeletons.saas_landing.name: "SaaS landing"
skeletons.saas_landing.description: "Product landing in the Stripe / Linear register — proof, bento, FAQ, and CTA."
skeletons.cinematic.name: "Cinematic"
skeletons.cinematic.description: "Stacked full-bleed chapters in the Apple register."
skeletons.editorial.name: "Editorial"
skeletons.editorial.description: "Campaign stack in the Nike register — dark chapters and story cards."
sections.hero_cinematic.name: "Cinematic hero"
sections.hero_cinematic.description: "Full-bleed chapter with kicker, headline, and optional image."
sections.hero_split.name: "Split hero"
sections.hero_split.description: "Copy on one side, visual on the other."
sections.proof_strip.name: "Proof strip"
sections.proof_strip.description: "A row of stats or proof points."
sections.bento_grid.name: "Bento grid"
sections.bento_grid.description: "Feature tiles in a bento layout."
sections.alternating_features.name: "Alternating features"
sections.alternating_features.description: "Image and copy that swap sides."
sections.card_grid.name: "Card grid"
sections.card_grid.description: "Image cards for services or stories."
sections.team_grid.name: "Team grid"
sections.team_grid.description: "People, roles, and short bios."
sections.quote.name: "Quote"
sections.quote.description: "A large pull quote with attribution."
sections.faq.name: "FAQ"
sections.faq.description: "Questions that expand in place."
sections.cta_band.name: "CTA band"
sections.cta_band.description: "A full-width closing call to action."
sections.rich_text.name: "Rich text"
sections.rich_text.description: "A heading and plain-text body."
sections.split_image_text.name: "Split image and text"
sections.split_image_text.description: "Image on one side, text on the other."
sections.contact_info.name: "Contact info"
sections.contact_info.description: "Address, email, phone, and hours — no form."
```

Reuse, do not duplicate: `common.actions.save|cancel|create|delete|enable|disable`, `common.status.published|draft`, `common.labels.yes|no|preview`, `locale_switcher.label`, `admin_modules.nav.modules`, `admin_settings.breadcrumbs.settings`, `maint_core.nav.modules`.

**zh-CN** (idiomatic, full-width punctuation; keys in parity):

| Key (short) | zh-CN |
|---|---|
| Website (module / titles) | 网站 |
| Build the public introduction site for this organization. | 为当前组织搭建对外介绍网站。 |
| New page | 新建页面 |
| View site | 查看网站 |
| Publish site | 发布网站 |
| Site live | 已上线 |
| Unpublished | 未发布 |
| Add, reorder, and edit sections from the marketing kit. | 从营销区块套件中添加、排序并编辑内容。 |
| Add section | 添加区块 |
| No sections yet | 还没有区块 |
| Site identity, theme, SEO, footer, and publish. | 站点名称、主题、SEO、页脚与发布。 |
| Replace with skeleton | 用骨架替换 |
| Replace pages with skeleton | 替换为骨架页面 |
| Open menu / Close menu | 打开菜单 / 关闭菜单 |
| Skeletons | 骨架 |
| Cinematic hero / Split hero / … | 电影感主视觉 / 分栏主视觉 / 数据条 / 便当格 / 交替图文 / 卡片栅格 / 团队栅格 / 引用 / 常见问题 / 行动条 / 正文 / 图文分栏 / 联系方式 |

Frontend lands both locale files in the same change as the components.

### Icon + catalog copy

Settings catalog card uses `admin_settings.catalog.modules.website`. Feature module `module_description` remains the registration English string (byte-identical) and is what F displays.

---

## Frontend constraints (checklist)

- Tailwind only, Stimulus only, ViewComponent encapsulation.
- Admin builder uses `AdminPageComponent` / `Admin::Modules::PageComponent` / `AdminTableComponent`.
- Public layout is marketing, not `layouts/public_page.html.erb`.
- FAQ public = `<details>`, no JS.
- Mobile nav = `website_nav`; builder = `website_builder`.
- No member builder; no extra screens (media library, DNS, blog).
- Beauty fail if public looks like an admin table or a form card.

# Website builder studio — UX spec

**Date:** 2026-09-21  
**Audience:** frontend developer. ViewComponent + Tailwind + Stimulus only. No React.  
**Follows:** locked product brief (restyle only). Do not reopen product, routes, models, or public marketing sections.  
**Design system:** Swiss Modernism 2.0 + Minimalism. Inter (already in app). Variance 3. Density 6. 8px grid. High contrast. Single admin accent = existing indigo `--color-accent`. Hairline borders. No nested cards. No fake macOS traffic lights. No emoji as icons. No new color system.

This is a **visual restyle** of the existing Website builder. Every current capability stays visible. The Stimulus `website-builder` HTML contract is frozen.

---

## Locked product (do not reopen)

- No new roles (`owner` / `admin` / `member` only). Tenant `admin`/`owner` build; `member` is not a builder.
- No new URL areas. Surfaces stay in Modules / Settings / Maintenance/Platform as they are today.
- No new backend (no new activities, models, routes, or controllers) except a view wrapper may read existing assigns (`@website`, `@pagination`).
- Do **not** restyle Maintenance/Modules toggle, platform Overview/Configuration/Developer tabs, or public marketing section components (the preview iframe already renders them).
- English I18n values stay byte-identical when reusing keys. New keys need `en` + `zh-CN`.
- Do **not** use `aside.w-60` (e2e forbids it).
- Do **not** use uppercase COPY / LINKS / MEDIA group chrome on the tenant workspace.
- Quiet selected states: `bg-surface` + hairline + `shadow-sm`. Not filled-accent pills for every toggle.

shadcn mental map → project delivery:

| shadcn | Project |
|---|---|
| Card | `.card` / `CardComponent` |
| Button | `ButtonComponent` |
| Badge | `BadgeComponent` |
| Tabs | pill `inline-flex` ToggleGroup (`bg-canvas p-0.5`, pressed = `bg-surface shadow-sm`) |
| Empty | `EmptyStateComponent` |
| Separator | `border-t border-border-subtle` |
| Sheet | keep identity as `details[data-identity-panel]` |
| Command list | hover rows, no bordered mini-card grid |

---

## Design language

Use existing semantic tokens only:

| Role | Token |
|---|---|
| Page canvas | `bg-canvas` |
| Raised surface | `bg-surface` |
| Primary text | `text-text-primary` |
| Secondary / muted | `text-text-secondary` / `text-text-muted` |
| Hairline | `border-border` / `border-border-subtle` |
| Admin accent | `bg-accent` / `text-accent` / `ring-accent` (indigo `--color-accent`) |
| Danger | `text-danger` / `border-danger/20` / `bg-danger-subtle` |
| Warning pill | `bg-warning-subtle text-warning` |

**Type (admin chrome, not public marketing):** `text-subtitle` only via `AdminPageComponent` h1. Body `text-body` / `text-body-sm`. Captions `text-caption`. Headlines inside the writing inspector may step up (`text-lg` / `text-xl tracking-tight`) for `headline` / `quote` only.

**Spacing:** 8px grid. Prefer `gap-2` / `gap-4` / `gap-6`. Density 6 = comfortable but not sparse: inspector fields `gap-4`, outline items `py-1.5`, toolbars `h-11`.

**Radius:** `rounded-lg` for frames and pills. Do not introduce `rounded-2xl` chrome on admin studio frames (public marketing inside the iframe may still use its own radii).

**Motion:** 150–200ms color/opacity/shadow. Respect `prefers-reduced-motion`. No layout-shifting press transforms.

**Icons:** existing Heroicon-style 20/24 outline SVGs (same stroke as current composer). Never emoji. Icon-only controls need `aria-label`.

**Anti-patterns (this pass):** nested `.card` inside `.card`, filled-accent toggle pills, uppercase section group labels on tenant workspace, traffic-light dots, abstract color bars as layout thumbnails, `aside.w-60`, new hex palettes, custom CSS files.

---

## 1. Surface inventory

| # | Surface | Nav area | URL | Restyle |
|---|---|---|---|---|
| A | Pages index | Modules | `GET /:cid/admin/pages/website` | Add quiet studio status strip **above** existing `AdminTableComponent`. Do not replace the table. |
| B | New page | Modules | `GET/POST /:cid/admin/modules/website/pages/new` | Layout radio cards become live miniature `PageComponent` previews. Identity form stays one surface. |
| C | Page composer workspace | Modules | `GET/PATCH /:cid/admin/modules/website/pages/:id/edit` | **Main pain.** Outline + inspector + living preview. Drop fake browser chrome. |
| D | Site settings | Settings | `GET/PATCH /:cid/admin/settings/modules/website` | One canvas + sticky in-page nav. Theme chips. Quiet footer list. Calm danger zone. |
| E | Platform layouts + skeletons galleries | Maintenance / Platform / Module Settings | existing layouts / skeletons gallery paths (owner, `81721200`) | Device-like preview frames; hover-revealed Edit. Keep default badge + skeleton `details`. |
| F | Shared chrome | used by B, C, platform layout editor | kit picker, array item toolbar, prop fields, layout picker | Command-list kit; compact array icons; writing-first fields; live layout thumbs. |

**Out of inventory (do not touch):** Maintenance/Modules enable row; platform Overview / Configuration / Developer tabs; public `layouts/website.html.erb` and `Websites::Sections::*`; admin preview ribbon on D-without-embed.

Roles: `admin` / `owner` on these URLs. Cross-tenant 404 via existing `TenantContext`. Members stay blocked by existing controller guards.

---

## 2. Layout spec per surface

### Shared admin chrome

Keep `AdminPageComponent` / existing breadcrumbs / flashes.

| Surface | Width |
|---|---|
| A, B, D | default (not `:edge`) |
| C | **keep** `width: :edge` — the sticky header strip stays (`sticky top-0 z-20 border-b border-border bg-surface`). Do not invent a second page header. |
| E | existing platform module-settings shell |

Composer C still binds Save to `website-page-form` and Preview (`common.labels.preview`) to the admin preview tab. Header badges stay Published/Draft + Home.

---

### A — Pages index (`/:cid/admin/pages/website`)

**Today:** `AdminPageComponent` + `AdminTableComponent` only.

**Change:** insert a quiet studio status strip between the page header and the table. Keep search, sort, row click → composer, row actions (Edit / Preview / Delete), empty state, pagination.

#### ASCII — desktop

```
[Pages > Website]
Website                                         [Publish site | View site] [+ New page]
Build the public introduction site for this organization.

+------------------------------------------------------------------------+
| [Site live | Unpublished]   /:cid/site            5 pages              |
+------------------------------------------------------------------------+

+------------------------------------------------------------------------+
| Search pages...                                                        |
| Title | Slug | Layout | Published | Updated                    [⋯]     |
+------------------------------------------------------------------------+
```

**Status strip data** (existing assigns only):

| Region | Source | Presentation |
|---|---|---|
| Site status | `@website.published?` | `BadgeComponent` `:success` + `website.admin.pages.index.site_live` **or** `:warning` + `website.admin.pages.index.site_unpublished` |
| Public path | `"/#{current_customer_id}/site"` (home URL) | `font-mono text-caption text-text-secondary` |
| Page count | `@pagination[:total]` | `website.admin.pages.index.page_count` → `%{count} pages` |

Strip chrome: one row, `rounded-lg border border-border bg-surface px-4 py-3`, `flex flex-wrap items-center gap-x-6 gap-y-2`. No second card stack. No nested table chrome. Separators are vertical hairlines (`h-4 w-px bg-border`) between the three facts — or simple gaps if that is quieter.

If `@website` is missing: omit the strip (table empty state already covers it).

**Empty:** existing `EmptyStateComponent` via AdminTable (`empty_title` / `empty_description` stay).  
**Loading:** server-rendered. No skeleton.  
**Error:** flash / module-disabled 404. No in-strip error.

**Mobile:** strip stacks to two lines (badge + path, then count). Table still horizontal-scrolls. Header actions wrap as today.

**Do not:** replace the table, add a card grid of pages, or move Publish/New page into the strip (they stay in `AdminPageComponent` actions).

---

### B — New page

**Today:** `ComposerComponent` `identity_only: true` — layout radio cards with abstract accent bars + identity fields in a card.

**Change:** same form, one surface (`max-w-3xl` stays). Replace abstract bars with a **live miniature** of `Websites::PageComponent` (layout `sections`, default catalog theme via `Websites::Theme.for_catalog(layout.key)`). Keep native radio semantics.

#### ASCII

```
[Pages > Website > New page]
New page                                        [Cancel] [Create]
Pick a layout, name the page, then fill in the copy.

Layout
Choose how this page is structured. …

+---------------------------+  +---------------------------+
| (○)                       |  | ( )                       |
| +-----------------------+ |  | +-----------------------+ |
| | scaled PageComponent  |  | | | scaled PageComponent  |  |
| +-----------------------+ |  | +-----------------------+ |
| Presence about            |  | Article                   |
| A cinematic chapter…      |  | One heading and a long…   |
+---------------------------+  +---------------------------+

Title  [                                        ]
Slug   [                                        ]
[x] Show in navigation   [ ] Published
```

**Radio card:**

- `relative` label, radio visually at top-right (keep the existing radio input).
- Preview well: `h-28 overflow-hidden rounded-md border border-border-subtle bg-canvas`. Inner: `pointer-events-none select-none origin-top-left scale-[0.22] w-[454%]`.
- Title + one-line description under the well.
- Badges: **optional / minimal**. Prefer none. If a layout has many section types, do **not** dump four `BadgeComponent`s — at most one muted caption (`text-caption`, first section type name) or omit.
- Selected: `bg-surface border-border shadow-sm`. Unselected: `border-border-subtle hover:border-border`. **No** `has-[:checked]:bg-accent-subtle` fill, **no** `ring-2 ring-accent`.

Identity fields stay writing-first (`form-label` + `input-field`). Visibility checkboxes stay a quiet list — not filled tiles on this page either (`flex items-start gap-2.5`, no bordered checkbox cards).

**Empty layouts:** if `layouts` is empty, hide the picker (same as today).  
**Validation:** inline `text-sm text-danger` + stay on B.  
**Success:** redirect to C. Flash `website.admin.flash.page_created`.

**Mobile:** one-column radio grid (`grid-cols-1`). Preview height `h-24`.

---

### C — Page composer workspace (main)

**Today:** `xl:w-[min(26rem,38%)]` writing rail + iframe in a fake browser (traffic-light dots). Section outline stacked above fields in the same column. Mobile Edit/Preview buttons are filled-accent when pressed.

**Required desktop (`xl+`):**

```
[existing AdminPageComponent edge sticky header — keep]
+-- editorPane (data-website-builder-target="editorPane") --+-- previewPane aside (NOT w-60) --------+
| flex row, min-h-0, bg-surface                               | bg-canvas                              |
|                                                             |                                        |
| nav w-52                 | inspector flex-1                 | h-11 toolbar:                          |
| outline of sections      | overflow-y-auto                  |  Preview label                         |
| (sectionNav buttons,     |                                  |  unsaved pill                          |
|  aria-current)           | details[data-identity-panel]     |  viewport ToggleGroup                  |
|                          | Page settings (collapsed)        |  preview_live TEXT                     |
| data-workspace-rail      |                                  |                                        |
| is the field list, not   | one section's fields             | iframe full height in                  |
| a second outline         | (other rows stay .hidden)        | rounded-lg border frame                |
|                          |                                  | NO traffic-light dots                  |
+--------------------------+----------------------------------+----------------------------------------+
```

**Do not** put `w-60` on the preview `aside`. Preview stays `flex-1 min-w-0`. Outline is `nav.w-52` (13rem), not an `aside`.

#### C.1 Editor pane

`data-website-builder-target="editorPane"`

```
xl: flex flex-row min-h-0 flex-1
     border-r border-border
     (drop the current 26rem cap — the pane is now outline + inspector)

< xl: flex-col; outline becomes horizontal chips
```

**Outline (`nav`, `w-52` at `xl+`):**

- `aria-label` = existing `website.admin.pages.edit.section_nav`.
- `border-r border-border-subtle bg-canvas` (quiet, not a second card).
- Heading: reuse `website.admin.pages.edit.content` (locked tenant) or `website.admin.pages.edit.sections` (unlocked). Sentence case. **No uppercase tracking-wider.**
- Each `sectionNav` button keeps `data-website-builder-target="sectionNav"`, `data-section-id`, `data-action="click->website-builder#focusSection"`, `aria-current`.
- Selected: `bg-surface text-text-primary shadow-sm border border-border`. Idle: `text-text-secondary hover:bg-surface-hover`. Truncate the type name. Optional second line (`text-caption truncate`) = first of headline/heading/quote — only if it fits without wrapping the row taller than `py-2`.
- When structure is **unlocked** (platform layout editor): Add section (`website-builder#toggleKit`) sits at the **bottom** of this nav as `ButtonComponent` `:secondary` `:sm`. Kit panel (`#website-kit-picker`, `data-website-builder-target="kit"`) opens as a popover to the right of the button (`absolute z-20 … card p-2 shadow-lg`), **command-list** contents (see F).
- When structure is **locked** (tenant C): no Add section. Outline is read-only navigation.

**Inspector (`flex-1 overflow-y-auto px-6 py-6 flex flex-col gap-6`):**

1. `details[data-identity-panel]` — **collapsed by default** (do not add `open`). Summary = `website.admin.pages.edit.page_settings` + identity summary caption. Chevron SVG as today. Body = title, slug, visibility checkboxes (quiet, not tiles). Keep all existing fields, hints, `confirmSetHome`, home lock.
2. **One** section’s fields — existing workspace behavior: non-active `row` targets stay `.hidden`. The visible row is a writing column, not a card:
   - Type name as `text-base font-medium tracking-tight text-text-primary` (not a purple badge).
   - Fields via `PropFieldComponent` (see F). No COPY/LINKS group headers.
   - `reset_section` remains a ghost control at the bottom when locked.
   - Unlocked: drag `handle`, move up/down, remove stay icon-only with existing `aria-label`s and `data-action`s.

`data-website-workspace` stays on the form. `data-workspace-rail` stays on the section **list** (`data-website-builder-target="list"`), even though the outline is now a sibling nav. Do not move `data-workspace-rail` onto the outline.

**Empty sections:** `data-website-builder-target="empty"` + `EmptyStateComponent` with existing no-sections copy. Show in the inspector; outline can be an empty quiet column.

**Unknown type:** warning caption + existing unknown badge. Do not crash.

#### C.2 Preview pane

`aside` with `data-website-builder-target="previewPane"`. Classes conceptually:

```
flex min-h-0 min-w-0 flex-1 flex-col bg-canvas max-xl:hidden
```

**Never** `w-60`.

**Toolbar (`h-11`):** `flex shrink-0 items-center gap-3 border-b border-border bg-surface px-4`

| Item | Spec |
|---|---|
| Preview label | `h2` `text-sm font-medium text-text-primary` = `website.admin.pages.edit.preview_label` |
| Unsaved | `data-website-builder-target="unsaved"` — keep existing warning pill (`rounded-full bg-warning-subtle …`). There is also a mobile unsaved target in the pane switcher; **keep both** (controller already has two). |
| Viewport | `viewportBtn` × desktop/tablet/mobile. Restyle as quiet ToggleGroup: wrapper `inline-flex rounded-lg bg-canvas p-0.5`, each button `size-8 rounded-md`, pressed = `bg-surface shadow-sm text-text-primary`, idle = `text-text-muted hover:bg-surface-hover`. **No** `aria-pressed:bg-accent`. Keep icons + `aria-label` = `preview_desktop` / `preview_tablet` / `preview_mobile`. Group `aria-label` = `preview_viewport`. |
| Live preview text | `text-caption text-text-muted` = `website.admin.pages.edit.preview_live`. This **replaces** the fake URL bar. Do not drop the string. |

**Stage:** `data-website-builder-target="previewStage"` still receives viewport `maxWidth` from JS. Frame:

```
relative mx-auto flex h-full min-h-0 w-full flex-col overflow-hidden
rounded-lg border border-border bg-surface
```

- **No** traffic-light row. **No** `shadow-lg ring-1 ring-black/5` macOS window.
- `iframe` `previewFrame` + `previewLoaded` + `data-preview-src` / `data-draft-url` / `src` unchanged. `title` = preview label. `class="h-full min-h-0 w-full flex-1 bg-surface"`.
- `previewLoading` overlay stays: `absolute inset-0 … bg-surface/80 text-caption`.

If `preview_url` is blank (should not happen on tenant C): keep the dashed empty well with `preview_label`.

#### C.3 Mobile / tablet (`< xl`)

Keep Edit | Preview pane switcher (`paneBtn`, `data-pane="editor|preview"`, `setWorkspacePane`).

Restyle as pill tabs:

```
[  Edit  |  Preview  ]   (unsaved pill)
  ^ wrapper: rounded-lg bg-canvas p-0.5
    pressed: bg-surface shadow-sm text-text-primary
    idle:    text-text-secondary
```

`role="group"` `aria-label` = `workspace_panes`. Do **not** use filled accent.

**Section chips** on small screens: the outline `nav` becomes `flex gap-2 overflow-x-auto` horizontal chips (`shrink-0 rounded-lg px-3 py-1.5`). Same `sectionNav` targets. Vertical outline only at `xl`.

Editor and preview still show/hide via existing pane JS (`max-xl:hidden` / pane classes). Do not add a second Stimulus controller.

#### C.4 Empty / loading / error

| State | Treatment |
|---|---|
| Iframe loading | existing `previewLoading` overlay |
| Unsaved | existing unsaved pills; live preview debounce unchanged (450ms) |
| Validation | `AlertComponent` at top of form (existing `errors_message`) + stay on C |
| Photo upload fail | existing `data-image-status` + `image_upload_failed` |
| Permission / module | existing 403 / 404 — no in-composer empty |

Keep: photo upload/drop, use-a-link, href picker, char counts, reset section, add/remove/reorder when unlocked, Cmd-S persist, live preview debounce.

---

### D — Site settings

**Today:** stacked generic `.card` sections (identity, theme, SEO, footer, layout, publish) + a loud danger card.

**Change:** one canvas. Sticky in-page nav. Existing `h2` **ids stay**:

| Nav item | Existing `h2` id | Reuse / new label |
|---|---|---|
| Identity | `website-settings-identity-heading` | new short key `website.admin.settings.nav.identity` → `Identity` |
| Theme | `website-settings-theme-heading` | `…nav.theme` → `Theme` |
| SEO | `website-settings-seo-heading` | `…nav.seo` → `SEO` |
| Footer | `website-settings-footer-heading` | `…nav.footer` → `Footer` |
| Layout | `website-settings-layout-heading` | `…nav.layout` → `Layout` |
| Publish | `website-settings-publish-heading` | `…nav.publish` → `Publish` |

Heading **visible** text on each `h2` stays the existing long keys (`Site identity`, `Theme`, … `Default layout`, `Publish`). Nav is the short labels.

#### ASCII — desktop

```
[Settings > Website]
Website                                            [View site] [Save]
Site identity, theme, SEO, footer, and publish.

+-- nav w-44 sticky --+-- one canvas (bg-surface border border-border rounded-lg) --+
| Identity            | Site identity                                               |
| Theme               | name / tagline                                              |
| SEO                 | ----------------------------------------------------------- |
| Footer              | Theme                                                       |
| Layout              | appearance chips · accent chips with color dots             |
| Publish             | type · density · existing ThemePreviewSwatch                |
|                     | ----------------------------------------------------------- |
|                     | SEO / Footer (dividers, not nested cards) / Layout / Publish|
+---------------------+-------------------------------------------------------------+

Calm danger zone (separate form, bottom):
Replace with skeleton … [select] [Replace pages with skeleton]
```

**Canvas:** wrap the existing `form_with` (`#website-settings-form`) in **one** surface. Each block is a `section` with `scroll-mt-24`, `px-6 py-6`, separated by `border-t border-border-subtle`. Drop per-section `.card` + `card-header`.

**Nav:** `<nav>` (not `aside.w-60`). `hidden lg:flex lg:w-44 lg:flex-col lg:gap-0.5 lg:sticky lg:top-24`. Links are `<a href="#website-settings-identity-heading">`. Do **not** add a settings Stimulus controller. Idle `text-text-secondary hover:text-text-primary`; no filled pills. On `<lg`, a horizontal chip scroller above the canvas (`flex gap-2 overflow-x-auto`).

**Theme radios:** keep native radios (`sr-only` + label). Visual = chips, not filled-accent segments.

- Appearance / Type / Density: quiet ToggleGroup (`inline-flex flex-wrap rounded-lg bg-canvas p-0.5`). Selected label = `bg-surface shadow-sm text-text-primary`.
- Accent: same group, but each option shows a **color dot** (`size-2.5 rounded-full`) plus the existing I18n name (`Azure`, `Ink`, …). Dot colors map public theme tokens with existing Tailwind palettes (not a new system):

  | Token | Dot |
  |---|---|
  | azure | `bg-sky-600` |
  | ink | `bg-neutral-950` |
  | gold | `bg-amber-700` |
  | forest | `bg-emerald-700` |
  | rose | `bg-rose-600` |
  | violet | `bg-violet-600` |
  | copper | `bg-orange-800` |

  Selected accent chip still uses quiet surface+shadow (the dot carries the color). Do not paint the whole chip `bg-accent` (admin indigo).

Keep `Websites::ThemePreviewSwatchComponent` under the groups (server-rendered after Save).

**Footer list:** drop nested `rounded-lg border … p-4` column cards. Each column is a row in a `divide-y divide-border-subtle` list. Drag handle + up/down stay (`countable-items-reorder` targets unchanged). Add-column slot: a simple dashed **row**, not a dashed card (`border-t border-dashed border-border-subtle pt-4`).

**Publish:** same checkbox/switch markup (keep the existing toggle span). Place it as the last canvas section.

**Skeleton replace:** stay a **separate** `button_to` / `form_with` so it cannot ride Save. Restyle as a **calm danger zone** below the canvas — not a pink nested card:

```
border-t border-danger/20 pt-8 mt-8
h2 + caption (existing copy)
select + danger ButtonComponent
```

Keep `data-skeleton-replace`, `data-turbo-confirm`, `website-settings-skeleton-heading`.

**Missing site:** existing `AlertComponent` + no form.  
**Validation:** inline + flash `site_save_failed`.  
**Mobile:** nav chips wrap; canvas full width; theme chips wrap.

---

### E — Platform galleries (owner)

**Today:** card grid; scaled `PageComponent` in a flat `bg-neutral-100` crop; Edit always visible; skeletons already have `scale-[0.45]` and `details summary` Home.

**Change:** make the preview feel like a **device frame**, not a cheap cropped screenshot. Keep data, default badge, page-role chips, and skeleton disclosure.

#### ASCII — layouts

```
Layouts                              [New layout]
+------------------+  +------------------+  +------------------+
| ┌──────────────┐ |  |                  |  |                  |
| │  bezel       │ |  |                  |  |                  |
| │  scaled page │ |  |                  |  |                  |
| └──────────────┘ |  |                  |  |                  |
| Presence home    |  | …                |  |                  |
|                  |  |                  |  |                  |
|          [Edit] ← hover / focus / mobile always               |
+------------------+  +------------------+  +------------------+
```

**Device frame** (both galleries):

```
relative overflow-hidden rounded-xl border border-border bg-canvas
px-3 pt-3 pb-0   (thin bezel, NO traffic lights)
inner stage: rounded-md border border-border-subtle bg-surface overflow-hidden h-40 (layouts) / h-56 lg:h-64 (skeletons)
```

Keep `pointer-events-none select-none origin-top-left` scale wrappers.

**Skeletons (required):** keep a node whose class list includes the literal `scale-[0.45]` (component spec asserts `[class*='scale-[0.45]']`). Keep `<details><summary>…Home…` using `website.platform.skeletons.pages.home`. Default badge (`BadgeComponent` `:primary`) stays next to the name.

**Edit:** `ButtonComponent` `:ghost`/`:secondary` `:sm`. Desktop: `opacity-0 group-hover:opacity-100 group-focus-within:opacity-100`. Mobile (`max-md`): always `opacity-100`. Do not remove the link.

**Empty:** not applicable (catalog is code-seeded).  
**Unauthorized:** existing owner gate.

**Mobile:** one column; slightly shorter stage (`h-36` / `h-56`).

---

### F — Shared chrome

#### F.1 Kit picker (`Websites::Admin::KitPickerComponent`)

**Today:** `grid sm:grid-cols-2` of bordered mini-cards.

**Change:** command list.

```
Cinematic hero
Full-bleed chapter with kicker, headline, and optional image.
────────────────────────────────
Split hero
Copy on one side, visual on the other.
```

- Wrapper: `flex flex-col` `role="list"`.
- Each button: full-width `role="listitem"`, `px-3 py-2 text-left rounded-md hover:bg-surface-hover`. **No** `border` / `shadow-sm` on the row.
- Title `text-body-sm font-medium`. Description `text-caption text-text-muted`.
- Keep `data-type`, `data-action="click->website-builder#addSection"`.
- Popover chrome (parent) stays `#website-kit-picker` + `kit` target; restyle padding to `p-1` so rows feel like a menu, not a card grid.

#### F.2 Array item toolbar

**Today:** four labeled ghost buttons (Move up / Move down / Duplicate / Remove).

**Change:** compact **icon** buttons in one `inline-flex gap-0.5`. Visible label text goes away; **`aria-label` stays** (same I18n: `move_up`, `move_down`, `duplicate_item`, `common.actions.remove`).

Keep:

- `data-action="click->website-builder#moveItemUp|moveItemDown|duplicateItem|removeItem"`
- `data-remove-item` on remove
- disabled-at-min on remove

Do **not** wrap each array item in a shadowed mini-card. Item chrome: `py-4 border-t border-border-subtle` (first item: no top border). Toolbar right-aligned under the fields.

#### F.3 Prop fields

Writing-first. Same `data-prop`, `data-href-field`, `data-image-field`, `data-count-field`, and all existing actions.

| Field | Treatment |
|---|---|
| `headline`, `quote` | Larger type: `text-xl tracking-tight` input / textarea. Light chrome (`border-0 border-b border-border-subtle rounded-none px-0 shadow-none focus:ring-0 focus:border-accent`). |
| `kicker`, `eyebrow` | `text-sm tracking-wide` — still an `input-field`, not uppercase chrome around it. |
| `body`, `subhead`, `answer` | Standard `input-field` textarea. |
| Segmented (`tone`, `span`, `image_side`) | Quiet ToggleGroup (`bg-canvas p-0.5`, selected `bg-surface shadow-sm`). Keep radios + `data-prop` + `markDirty`. **No** `peer-checked:bg-accent`. |
| Image | Dropzone: **solid** hairline (`border border-border bg-canvas`), not a busy dashed box. Empty copy stays `image_empty`. Preview `aspect-[16/10] object-cover`. Add/Replace photo, Remove, **Use a link instead** `<details>` all stay. Drag/drop/upload actions unchanged. |
| Href | Input + site-page picker unchanged. |
| Char count | Keep `data-char-count` + `char_count` / `char_count_template`. |

#### F.4 Layout picker

Shared by New page (B). Spec in §B. Platform surfaces that reuse this component get the same live miniature + quiet selected state.

---

## 3. Interaction flow

Flows are unchanged; only chrome changes. Click-by-click for the restyle.

### 3.1 Browse pages (A)

1. `admin`/`owner` opens `/:cid/admin/pages/website`.
2. Status strip shows live/unpublished, `/:cid/site`, page count.
3. Search / sort / pagination work as today.
4. Row click or **Edit** → C.
5. **Preview** → admin preview (new tab).
6. **New page** → B.
7. **Publish site** / **View site** stay in the page header.
8. Empty table: existing empty state. Missing website: no strip.
9. Member / other tenant / module off: existing 403/404.

### 3.2 Create page (B)

1. Choose a layout radio (miniature preview, quiet selected).
2. Title required; slug optional.
3. **Create** → C. Validation stays on B with inline errors.

### 3.3 Compose (C)

1. Land on C. Identity `details` is **closed**. First section is focused (`aria-current` on first `sectionNav`; other rows hidden).
2. Click an outline item → that section’s fields fill the inspector; preview does not navigate.
3. Edit headline / drop a photo / pick an href / watch char count. Unsaved pills appear. Live preview debounces (existing 450ms) into the iframe.
4. Viewport ToggleGroup resizes `previewStage` (desktop / tablet / mobile).
5. **Cmd-S** / header **Save** → persist; iframe reloads; unsaved hides.
6. **Restore original copy** → confirm → defaults. Unlocked layouts: add/remove/reorder/drag as today (kit is now a command list).
7. Open **Page settings** → edit title/slug/visibility/home (confirm on set-home).
8. `< xl`: **Edit | Preview** pills switch panes. Horizontal section chips replace the `w-52` outline.
9. Validation fail: alert at top, stay on C, last good preview remains until the next successful persist/debounce.
10. Upload fail: inline image status. Permission/module: existing redirects.

### 3.4 Settings (D)

1. Open Settings / Website. One canvas + nav.
2. Click **Theme** → scroll to `#website-settings-theme-heading`. Choose accent chip (color dot). Swatch updates after **Save**.
3. Footer: reorder via existing handles; no nested cards.
4. Publish switch + **Save**.
5. Skeleton: confirm → redirect A + existing flashes. Cancel → no change.
6. Missing site: error alert, no canvas.

### 3.5 Galleries (E)

1. Owner opens Layouts or Skeletons tab (shell unchanged).
2. Hover a frame → **Edit** fades in. Keyboard focus also reveals it. Mobile: Edit always visible.
3. Skeletons: Default badge as today; expand **Home** `<details>` for the larger preview (`scale-[0.45]` still present in markup).
4. Non-owner: existing gate.

### 3.6 Failure matrix (all surfaces)

| Failure | Outcome |
|---|---|
| Validation | Stay; inline + flash. No new dialog. |
| Permission | Existing 403/redirect. |
| Cross-tenant | 404. |
| Module disabled | 404. |
| Vendor-down | N/A (no vendor). Image upload fail uses existing `image_upload_failed`. |
| Preview iframe error | Loading overlay hides on `load`; a broken preview is an authoring/URL issue — do not invent a retry chrome. |

---

## 4. Component reuse map

### Reuse as-is

| Piece | Component |
|---|---|
| Page header, breadcrumbs, edge sticky chrome | `AdminPageComponent` |
| Pages table, search, sort, row actions | `AdminTableComponent` |
| Buttons / badges / empty / alerts | `ButtonComponent`, `BadgeComponent`, `EmptyStateComponent`, `AlertComponent` |
| Platform shell + tabs | existing module-settings shell / `SectionNavComponent` (do not restyle Overview/Configuration/Developer) |
| Theme swatch | `Websites::ThemePreviewSwatchComponent` |
| Public page inside thumbs / iframe | `Websites::PageComponent` (do not restyle sections) |
| Footer column reorder | `countable-items-reorder` |

### Restyle in place (same class names, new markup/classes)

| Component | What changes |
|---|---|
| `Websites::Admin::ComposerComponent` | editor = outline + inspector; preview toolbar + simple frame; pane pills |
| `Websites::Admin::ComposerSectionsComponent` | outline `nav.w-52` / horizontal chips; no uppercase heading |
| `Websites::Admin::SectionEditorComponent` | writing column; no group chrome on workspace |
| `Websites::Admin::KitPickerComponent` | command list |
| `Websites::Admin::LayoutPickerComponent` | live `PageComponent` miniature; quiet selected |
| `Websites::Admin::PropFieldComponent` | writing-first type; quiet segments; calmer dropzone |
| `Websites::Admin::ArrayItemToolbarComponent` | icon buttons + aria-labels |
| `Websites::Admin::SettingsFormComponent` | one canvas + sticky nav + theme chips + divider footer |
| `Websites::Admin::SkeletonReplaceComponent` | calm danger zone (no nested danger card) |
| `Websites::Admin::LayoutsGalleryComponent` | device frame; hover Edit |
| `Websites::Admin::SkeletonsGalleryComponent` | device frame; hover Edit; keep `scale-[0.45]` + Home `details` |

### New (small)

| Component | Role | Props |
|---|---|---|
| `Websites::Admin::StudioStatusStripComponent` | A strip above the table | `website:`, `page_count:`, `public_path:` |

Do **not** add `Dashboard::TableComponent`. Do not extract a second Stimulus controller.

Settings in-page nav may live **inside** `SettingsFormComponent` (preferred) rather than a new file, as long as the markup is one `nav` + one canvas.

---

## 5. Tailwind & Stimulus notes

### Tailwind recipes (match siblings)

**Quiet ToggleGroup** (pane switcher, viewport, theme appearance/type/density, prop segments):

```
inline-flex items-center rounded-lg bg-canvas p-0.5
item idle:    rounded-md text-text-secondary hover:bg-surface-hover
item pressed: rounded-md bg-surface text-text-primary shadow-sm
```

Use `aria-pressed` / `aria-current` / `peer-checked` — not a JS tab widget.

**Quiet selected outline / radio card:**

```
bg-surface border border-border shadow-sm text-text-primary
```

**Hairline separators:** `border-t border-border-subtle` or `w-px self-stretch bg-border`.

**Preview iframe frame:** `rounded-lg border border-border bg-surface` — no ring, no traffic lights, no `shadow-lg`.

**Composer split:**

```
form[data-website-workspace]: flex h-full min-h-0 flex-col
shell xl: flex-row
editorPane xl: flex flex-row min-h-0 flex-1 border-r border-border
outline: hidden xl:flex xl:w-52 xl:flex-col …   /  flex xl:hidden overflow-x-auto
inspector: flex-1 overflow-y-auto
previewPane: flex min-h-0 min-w-0 flex-1 flex-col bg-canvas   /* NOT w-60 */
```

Prefer `gap-*` over `space-y-*`. Prefer `size-8` for square icon buttons.

### Stimulus — frozen `website-builder` contract

Host: `data-controller="website-builder"` on the form. Workspace forms keep `data-website-workspace`.

**Targets (all required, do not rename):**  
`list`, `row`, `handle`, `kit`, `json`, `previewFrame`, `unsaved`, `previewLoading`, `empty`, `toggleAll`, `previewStage`, `viewportBtn`, `sectionNav`, `editorPane`, `previewPane`, `paneBtn`

**Placement constraints:**

- `previewStage`, `viewportBtn`, `previewFrame`, `unsaved` (desktop instance) live **inside** the preview `aside`.
- `sectionNav` buttons keep `aria-current`.
- `list` keeps `data-workspace-rail` on the workspace.
- `details[data-identity-panel]` stays collapsed by default.
- Do not add `aside.w-60` anywhere.

**Actions (do not rename):**  
`addSection`, `removeSection`, `moveUp`, `moveDown`, `toggleKit`, `markDirty`, `reloadPreview`, `previewLoaded`, `addItem`, `removeItem`, `confirmSetHome`, `applyHref`, `checkHref`, `previewImage`, `imageError`, `clearImage`, `countChars`, `duplicateItem`, `moveItemUp`, `moveItemDown`, `resetSection`, `toggleAllSections`, `setPreviewViewport`, `saveShortcut`, `persist`, `focusSection`, `setWorkspacePane`, `allowImageDrop`, `dropImage`, `uploadImage`

No new Stimulus controller for settings nav or theme chips. Values / i18n defaults on `website-builder` stay; English `default:` values remain the current English strings.

JS tests stay at 100% lines + branches (`npx vitest run --coverage`). Do not change controller JS unless a restyle accidentally breaks a selector — prefer keeping selectors (`[data-website-builder-target=…]`, `[data-workspace-rail]`, `[data-identity-panel]`, `[data-array-item]`, `[data-image-field]`, etc.).

### New I18n keys (en = intended English; add zh-CN in the same change)

Reuse everything else (`site_live`, `preview_live`, `page_settings`, `workspace_edit`, theme value names, …).

```yaml
# website.en.yml
admin.pages.index.public_path: "Public path"
admin.pages.index.page_count: "%{count} pages"
admin.settings.nav.identity: "Identity"
admin.settings.nav.theme: "Theme"
admin.settings.nav.seo: "SEO"
admin.settings.nav.footer: "Footer"
admin.settings.nav.layout: "Layout"
admin.settings.nav.publish: "Publish"
```

```yaml
# website.zh-CN.yml
admin.pages.index.public_path: "公开地址"
admin.pages.index.page_count: "%{count} 个页面"
admin.settings.nav.identity: "身份"
admin.settings.nav.theme: "主题"
admin.settings.nav.seo: "SEO"
admin.settings.nav.footer: "页脚"
admin.settings.nav.layout: "版式"
admin.settings.nav.publish: "发布"
```

`public_path` is the strip **label** if a label is shown; the value is the path itself. If the strip can read as badge + mono path + count without a “Public path” label, still add the key and use it as `aria-label` on the path span.

---

## Frontend constraints (checklist)

- Tailwind only. Stimulus only. ViewComponent encapsulation.
- Semantic tokens only (`bg-surface`, `text-text-primary`, `border-border`, `bg-accent`, …). No new color system.
- No emoji icons. No `aside.w-60`. No traffic lights. No uppercase COPY/LINKS on tenant workspace.
- Quiet selected states, not filled-accent pills.
- Do not change routes / controllers / models / activities except reading existing assigns for the status strip.
- Do not restyle public section components or Maintenance/Modules / platform Overview-Configuration-Developer.
- Keep `website-builder` targets, actions, `data-website-workspace`, `data-workspace-rail`, `details[data-identity-panel]`, preview-stage contract.
- Skeletons gallery markup still includes `scale-[0.45]` and `details summary` Home.
- English reused keys stay byte-identical. New keys land in both locales.
- Responsive: 375 / 768 / 1024 / 1440. Composer pills + horizontal chips below `xl`; outline `w-52` at `xl+`.
- Touch targets ≥ 32px (icon buttons `size-8`); 44px where they stand alone (pane pills).
- Focus rings `focus-visible:ring-2 focus-visible:ring-accent`. `cursor-pointer` on clickable labels.

---

## Success

An admin opening the Website module sees a Swiss-modern studio: a quiet index strip, layout cards that look like real pages, a composer with a section outline + writing inspector + living preview (no toy browser), settings on one canvas, and owner galleries in device frames — with every existing feature still visible and the `website-builder` contract intact.

---
title: "Customer documentation"
summary: "Bilingual customer task guides with visible task navigation, search that preserves reading context, a responsive reader, and safe screenshot figures."
---

## Summary

**Help → Documentation** opens the internal customer guide at `/:cid/admin/help/docs`. It is for signed-in customer administrators and the platform owner. The guides explain everyday tasks: navigating the workspace, managing users and records, using forms and websites, operating modules, changing customer settings, reviewing billing, and getting support.

Customer content lives in `doc/customer/<locale>/<slug>.md`, with its own `CustomerDocs::Catalog`. Developer reference content stays in `doc/reference/<locale>/<slug>.md`, under the owner-only `/81721200/admin/maintenance/platform/developer_docs` surface. The two audiences share rendering infrastructure, with separate catalogs, content roots, translations, and route helpers. See [developer reference](overview), [support tickets](support-tickets), [internationalization](internationalization), and [tenancy and roles](tenancy-and-roles).

## Flow

```text
Admin Help menu -> Documentation
  GET /:cid/admin/help/docs or /:cid/admin/help/docs/:slug
        |
        v
ApplicationController
  TenantContext: URL customer; reject non-owner cross-tenant access
  RouteAuthorization: sign-in, admin-or-owner role, CanCan route check
        |
        v
Admin::Help::DocsController
  index -> overview; show -> params[:slug]
  Cache-Control: private, no-store
        |
        v
CustomerDocs::Repository < DeveloperDocs::Repository
  CustomerDocs::Catalog -> doc/customer/<locale>/<slug>.md
  page + guide_groups (homepage only; metadata independent of q)
  Page.current_group: unfiltered context; Page.groups: genuine contents results
  previous_page / next_page: Link(slug, title, path), catalog order
        |
        v
DeveloperDocs::Renderer (catalog: CustomerDocs::Catalog)
  screenshot_root: /help/docs/screenshots
  Kramdown GFM -> callouts, anchors, links, screenshot figures -> Loofah
        |
        v
DeveloperDocs::ReaderComponent
  header slot: AdminPageComponent inside the central reading column
  translation_scope: customer_docs; locale: current_locale
  article_variant: customer; home_groups: groups on overview, otherwise nil
  CustomerDocs::HomeGuidesComponent -> grouped panels with 12 guide rows, then the article
```

An unknown or unavailable slug renders the localized missing-page view with status 404. Both rendered articles and missing-page responses set `Cache-Control: private, no-store`.

## Implementation

### Routes and access

`config/routes.rb` declares read-only `index` and `show` routes in `admin/help`, with `param: :slug` and a lowercase kebab-case slug constraint. `admin_help_docs_path(customer_id)` opens the overview; `admin_help_doc_path(customer_id, slug)` opens an article.

`Admin::Help::DocsController` inherits the centralized `TenantContext` and `RouteAuthorization` guards from `ApplicationController`. Anonymous readers must sign in; members cannot read these admin URLs; customer admins may read only within their own customer. The platform owner may open the guide in another customer's URL context. The controller uses `current_customer_id` for the repository and adds no duplicate authentication or role filter.

`HelpMenuComponent#show_docs?` requires `user.admin_or_owner?` and a customer id. Its `docs_url` calls `admin_help_docs_path(customer_id, locale: I18n.locale)`, and the menu link navigates within the app in the effective language. This visibility check complements the controller-layer guards. The developer reference retains its existing platform-owner gate and platform navigation entry.

### Customer catalog and content contract

The catalog has 13 operational guide slugs, each published in both `en` and `zh-CN`:

| Group key (top menu item) | Slugs |
| --- | --- |
| `home` | `overview`, `getting-started` |
| `assistant` | `assistant` |
| `users` | `users` |
| `payments` | `payments` |
| `communication` | `email`, `sms` |
| `entities` | `records` |
| `content` | `forms`, `websites` |
| `settings` | `settings`, `billing`, `support` |

Group labels match `chrome.menu_bar.items` (`Home`, `AI Assistant`, `Users`, `Payments`, `Communication`, `Entities`, `Content`, `Settings`). Contents follows that left-to-right order. There is no customer **Modules** group (those guides sit under their menu items) and no **Maintenance** group (owner-only builders stay out of this catalog).

Every guide has YAML front matter with a goal-based `title` and concise outcome `summary`. `AdminPageComponent` uses those values for the full page header; homepage rows, same-group footer links, and bottom sequence links also retain full titles. Customer contents, article breadcrumbs, the mobile location bar, and search context use short I18n task labels, with full-title accessible descriptions on short navigation links. Do not add an H1 to the article body. `CustomerDocs::Catalog::REQUIRED_HEADINGS` defines these second-level headings, retained once each in this order:

| English | Simplified Chinese |
| --- | --- |
| Before you start | 开始前 |
| Steps | 操作步骤 |
| What to expect | 预期结果 |
| Troubleshooting | 常见问题 |
| Related guides | 相关指南 |

Keep both languages aligned in sections, examples, and callouts. Explain customer-visible operations and prerequisites, including module availability. Platform implementation details and owner-only tooling belong in developer reference. Add customer pages to `CustomerDocs::Catalog`, not `DeveloperDocs::Catalog`; this implementation reference is registered in the developer catalog's `operations` group.

### Homepage metadata contract

`CustomerDocs::Repository#guide_groups` returns `Array<DeveloperDocs::Repository::Group>` in catalog order. This complete homepage directory is separate from article context and filtered contents metadata:

- Group: `key: String`, `entries: Array<CustomerDocs::Repository::Guide>`.
- Immutable Guide: `slug: String`, `title: String`, `summary: String`, `path: String`.
- Metadata uses the same allow-listed sources and localized front matter as article lookup, including English fallback. Exclude `Catalog::HOME_SLUG`, omit unavailable sources and empty groups. The complete publication has 12 guide rows across eight groups; `home` contributes only `getting-started`.
- `q` filters contents only. The grouped directory remains complete even when search has no matches.
- Generate `path` through the existing repository route resolver with the URL customer and effective locale: `admin_help_doc_path(C, slug, locale: L)`, for example `/81721200/admin/help/docs/forms?locale=en`. Do not carry `q`, use the author's account customer, or accept arbitrary front-matter destinations.
- Assemble metadata outside the rendered-article cache. A new request sees saved title/summary changes without requiring article-fragment invalidation.

`Admin::Help::DocsController` reuses one repository per request for article lookup and groups. Both index and explicit `/docs/overview` supply home groups; other guides supply `nil`. The grouped panels carry the directory, so overview Markdown contains compact orientation and recovery guidance rather than repeating the 12-guide list.

### Article context and navigation metadata

Both repositories use the shared request-local data contract:

- `Page` contains `slug`, `title`, `summary`, `html`, `headings`, `groups`, `current_group`, `previous_page`, `next_page`, `query`, and `search_path`.
- `Group(key, entries)` contains `Entry(slug, title, path, active)` metadata in catalog order. `Page.current_group: Group | nil` is the complete unfiltered group owning the current slug, with one active entry. Missing sources are omitted; no current group means no group breadcrumb or same-group footer.
- `Page.groups` contains only genuine matches for the normalized query. Never append the current guide, its siblings, or a synthetic context group to results. A current guide that actually matches remains a result, without active styling or current-page semantics in the rendered results list.
- `previous_page` and `next_page` are `Link(slug, title, path) | nil`, following published catalog order and skipping unavailable sources. The slug supports label lookup without parsing URLs. The footer sequence uses these links, regardless of query.
- Build unfiltered groups once per `page` call, select the owning group, then filter the same entries by localized title, summary, and body. Reuse request-local source metadata and render only the requested article; do not pass a second complete catalog or copied article bodies to the component. The independent homepage `guide_groups` and developer `hub_groups` remain complete.
- Contents, current-group and sequence destinations omit both symbol and string `q` routing options while preserving established options, especially the URL customer and effective customer locale. `page.search_path` is the controller-supplied query-free current index/article URL. Context and sequence metadata are outside the rendered-fragment cache and need no renderer cache-version change.

### Shared reader configuration

`DeveloperDocs::Repository` accepts `catalog:`, `content_root:`, `translation_scope:`, `route_helper:`, optional `route_options: {}`, and opt-in `screenshot_root: nil` with optional `screenshot_labels: nil`. Defaults preserve developer reference behavior: `DeveloperDocs::Catalog`, `doc/reference`, `"developer_docs"`, `:admin_maintenance_platform_developer_doc_path`, no added locale query, and stripped images. `CustomerDocs::Repository` supplies `CustomerDocs::Catalog`, `doc/customer`, `"customer_docs"`, `:admin_help_doc_path`, and `screenshot_root: "/help/docs/screenshots"`, plus render-time localized screenshot labels. The customer controller passes `locale: current_locale` and `route_options: { locale: current_locale }`; the repository forwards route options as keywords for contents, related guides, and previous/next links, including fragments.

The repository validates slugs against the injected catalog before reading files, verifies paths remain within the configured root, parses front matter with `YAML.safe_load`, and selects the requested supported locale. Unsupported locales use English; a missing localized source falls back to the English source. Callout and anchor labels use the repository's selected locale and translation scope, including when the source falls back to English.

`DeveloperDocs::Renderer.call` accepts `catalog:` (defaulting to `DeveloperDocs::Catalog`). Internal bare-slug links are validated against that catalog and rewritten with the repository's route helper. A developer-only slug cannot become a customer article link. The existing Kramdown, Rouge, callout, anchor, and Loofah sanitization pipeline is shared.

`DeveloperDocs::ReaderComponent` accepts `page:`, `translation_scope:` (default `"developer_docs"`), `locale: nil`, `article_variant: :reference`, `home_groups: nil`, and `home_path: nil`. The customer view passes `translation_scope: "customer_docs"`, `locale: current_locale`, `article_variant: :customer`, and the Help docs index as `home_path`. The developer overview now also supplies `home_groups` from `DeveloperDocs::Repository#hub_groups` and the platform reference index as `home_path`.

The reader has an optional `header` slot (`renders_one :header`). Both show views supply `AdminPageComponent` with their existing breadcrumbs, front-matter title/summary, `wrap_title: true`, and `width: "full"`. Breadcrumbs, the single page H1, summary, directory, article, and continuation links share the central column's left edge and measure. The breadcrumb supplies group context without a repeated title badge; calls without a header remain valid.

`home_groups: nil` omits the homepage surface; `[]` renders its localized directory-unavailable message in a neutral panel and keeps the overview article. `CustomerDocs::HomeGuidesComponent` requires `groups:` and optional `translation_scope:` (default `"customer_docs"`). It renders the localized directory heading/intro and one rounded `CardComponent` per catalog group: a group heading and description above a rule, then native guide-row anchors separated by thin rules. Each row retains its title/summary IDs, title-based accessible name, full (unclamped) summary description, same-tab destination, decorative arrow, visible focus, and natural wrapping. Cards carry a light shadow that deepens on hover, ring when targeted by their fragment, align at the top, and keep natural heights. Each panel has a stable `customer-doc-guide-group-<key>` or `developer-doc-guide-group-<key>` ID and heading scroll offset. Group breadcrumbs and pinned context attach this fragment to the view-supplied `home_path`, preserving locale before the fragment; for example, `/81721200/admin/help/docs?locale=zh-CN#customer-doc-guide-group-content`. The grid uses a nested `@container/hub` with 16px gaps: one column, two from 576px of hub width, three from 832px. The component performs no module-status/database lookup or route construction.

The shared reader is capped at 1200px (`@container/docs`) inside existing shell gutters; the central column is capped at 704px on articles and 960px on the home hub (whose overview prose stays at 704px). Let W be the actual reader-container width after app-sidebar space and gutters. At viewport height H ≥640px, below W=832px use one column, a sticky top bar with the Contents trigger and "group / page" location, and the Contents drawer; from 832px show a 240px contents rail with a 40px gap; from 1056px articles with headings also show a 192px heading rail with another 40px gap. Width modes use named container queries. At H <640px, use one column, the bar, the drawer and inline article TOC regardless of W; the complementary height condition covers grid, both rails, bar, drawer, backdrop and TOC visibility. Tall-screen container modes remain unchanged. Rails stick 24px below the scrollable main's top. Hubs and articles without headings never reserve a right rail. Hub panels sit outside the Markdown wrapper, before overview prose; `page.headings` still describes only article headings. Eligible articles show exactly one TOC: inline native `details` when the right rail is unavailable, otherwise the right rail; hubs show none. Both TOCs mark the section being read with `aria-current="location"` (see the `docs-reader` controller below), and the right rail ends with **Back to top**.

Both audiences use the application type scale and `font-sans` (the same family as `body`). Type size does not change with reader width. Sizes and line heights are in pixels:

| Element | Size / line height |
| --- | --- |
| Page H1 (`text-subtitle`) | 20 / 27.5 |
| Summary, directory intro, guide summaries (`text-body-sm`) | 13 / 19.5 |
| Article prose, lists, tables, callout body (`text-base`) | 14 / 21 |
| Markdown H2 (`text-2xl`, tight leading) | 20 / 25 |
| Markdown H3 and directory H2 (`text-xl`, snug leading) | 18 / 24.75 |
| Hub group headings (`text-md`, snug leading) | 15 / 20.625 |
| Hub guide titles (`text-base`, medium weight) | 14 / 19.25 |
| Contents, TOC, sequence titles, breadcrumbs (`text-sm`) | 13 / 19.5 |
| Contents group labels (`text-xs`, semibold) | 11 / 14.67 |
| Code blocks (`text-sm`, relaxed leading, `font-mono`) | 13 / 21.125 |

Search inputs use `input-field` (14px): 40px tall on the desktop rail, 44px in the drawer. Drawer links keep at least 44px targets. Prose code blocks are wrapped with a **Copy** button by `docs-reader`; tables and inline code sit on `bg-surface` with subtle borders. Callout labels are sentence-case `text-sm`. Reader utilities lock those sizes over global paragraph defaults and renderer classes. Inline code keeps the application `0.9em` size on `font-mono`. `.docs-page`, `.customer-doc`, and `.developer-doc` remain semantic/test hooks; custom docs CSS in `app/assets/tailwind/application.css` is replaced by component-owned utilities. Heading IDs/permalinks, bullets, article links and syntax highlighting remain intact. Both customer and developer tables use `block max-w-full overflow-x-auto`; code blocks scroll locally without token wrapping. `min-w-0` and long-token wrapping bound prose/navigation; breadcrumbs may scroll locally. Screenshots retain natural ratios, with wrapping captions/full-size links.

Contents uses a bounded flex column with a fixed control header and an independently scrolling list. Desktop fills the main scroll area: `docs-reader` writes main's `clientHeight` to `--docs-pane-height` and the rail is `calc(var(--docs-pane-height) - 3rem)` tall (fallback `100dvh - 10rem`); the header is `shrink-0`, and only the `min-h-0 flex-1 overflow-y-auto overscroll-contain` list scrolls. The drawer uses `h-dvh`, preferred width 320px capped at 85vw, 16px insets and safe-area allowances. Its doc-set title (a home link when `home_path` is given), close control and search stay above the list. The desktop header starts with the same doc-set home link (book icon + `breadcrumb.reference`). Neither header shows a Contents label. On the desktop rail the submit is a leading icon button named **Search** inside the field, with a `/` keyboard hint while the field is empty. The drawer keeps a visible text submit, stacked with the field, and below 640px height places that button beside the field. Conditional **Clear search** and **Reading now** follow, then a light separator. The input and submit are at least 44px high; Clear is at least 32px on desktop and 44px in the drawer. Clear depends on the applied normalized query, not draft input edits.

At H <640px the drawer compacts spacing, pairs input with the still-visible text Search button, and, when both are present, places home and Clear beside each other. DOM/form order and 44px controls remain intact; Reading now stays above a list with at least 64px reserved height. At H ≥640px the normal full-width stacked controls and existing width-container modes remain. This is a Tailwind height escape, not a client-side search state.

`DeveloperDocs::ContentsNavComponent` accepts `page:`, `translation_scope:`, `navigate: false`, and `surface: :desktop` (`:mobile` in the drawer). Both audiences render each group as `<section aria-labelledby>` with an `h3` label and an indented `ul/li/a` list on a thin left rule, so every published entry is reachable without disclosures; searching keeps only groups with matches. Normal current links have accent styling, `aria-current="page"` and `data-docs-current-guide`. Group labels are quiet captions. The current page is an accent pill with a short marker, matching the app sidebar. Heading links share one guide line; nested headings indent and use tertiary text. With a query, the fixed **Reading now** block owns the sole current link in each contents surface; the separate **Search results** list uses only `page.groups` and has no active/current styling or marker. Customer results show the short task label plus the full title when different. No-result copy is a neutral outlined message with a visible query-free Clear recovery link. The complete directory, current article and context remain available.

`ReaderComponent#current_group` delegates to `page.current_group`; article group breadcrumbs and `section_entries` use that unfiltered group. Customer article breadcrumbs keep Help context, **All guides**, linked group and a plain short current label. Developer breadcrumbs retain their maintenance/reference context and full title. During search, Reading now links the group to its home panel and the current guide to its query-free repository path; selecting the guide clears search on the same article. If the group is unavailable, current slug/title and `page.search_path` provide recovery. Without a query, omit pinned context and let the normal contents item own current-page semantics. Desktop and mobile may each have one current anchor in the DOM; uniqueness is per visible contents surface, with the closed drawer inert/hidden.

Previous/next appear once, in the **Reading order** footer nav (`data-docs-footer-sequence`) after the prose and **More in this section**; there is no sequence row above the article. Each target is a bordered card with a small Previous/Next label above the full title; Next aligns end and keeps the second column even when Previous is missing. Targets are query-free catalog neighbors on both hubs and articles. Missing endpoints render no disabled link or placeholder. The cards stack below 480px of center width (`@container/hub`). **More in this section** follows a light top separator and lists full-title cards from `page.current_group.entries.reject(&:active)` (two columns from 640px) even during search, omitting the block only when there are no other entries.

`docs-reader` (`app/javascript/controllers/docs_reader_controller.js`) is mounted beside `developer-docs-nav` on `.docs-page`. It sets `--docs-pane-height` from the closest `main`; scroll-spies TOC links (`tocLink` targets), marking the last heading above a 120px reading line (or the last heading at the end of the scroll) with `aria-current="location"`; focuses and selects the first visible `search` target when `/` is pressed outside editable fields with no modifiers; and wraps each `pre` in the `prose` target with a clone of the `copyTemplate`. Copy uses `navigator.clipboard.writeText`, falling back to a hidden textarea with `execCommand("copy")` on insecure origins, swaps the `aria-live` label to `copied_code` and resets after 2s. Labels arrive as `data-docs-reader-copy-label-value` / `copied-label-value`. Without a `main` ancestor only the shortcut and copy buttons are active.

Markup hooks are `data-docs-nav-header`, `data-docs-nav-list`, and one `data-docs-current-guide` anchor per contents surface. The drawer's list also carries `data-developer-docs-nav-target="drawerList"`. Short navigation links keep their visible label as the accessible name and add a full-title `aria-describedby`: `<audience>-doc-nav-<surface>-<slug>-title` for contents, and `<audience>-doc-context-<surface>-<slug>-title` for pinned context (`audience` is `customer` or `developer`). Description IDs are unique across surfaces. Full titles remain visible in the H1, complete hub, customer search results, same-group footer and bottom sequence; they do not rely on tooltips.

On initial desktop layout and when the reader enters desktop mode, `developer-docs-nav` reveals the normal current-guide row by scrolling only the desktop contents list. A late-catalog current guide is therefore visible immediately. This reveal preserves the focused element and the window/main/article scroll position; it is separate from drawer reveal, which runs when the drawer opens. During search, current context remains pinned above the results rather than becoming a synthetic result.

The `developer-docs-nav` drawer is inert and `aria-hidden` while closed. Opening focuses the close control with `preventScroll`, then reveals the canonical current-guide marker using the optional `drawerList` target. If the marker is in the list, scroll only that list just enough to reveal the entire row; if a row is taller than the list viewport, keep its beginning visible. If search pins the marker in the header, start the results list at the top. Missing targets or markers leave modal opening usable. Do not use unrestricted `scrollIntoView`, refocus the guide, or move the main/article scroll position. Tab/Shift+Tab stay within rendered, enabled controls. Escape, the close button, and the backdrop return focus to the opener; home/clear/context/guide navigation closes without interrupting the native link. Closing restores the body's previous overflow. A `ResizeObserver` watches the reader and checks the trigger's actual visibility: switching to the desktop rail closes the drawer and moves focus to the rail if the opener is hidden. No numeric JS breakpoint is added for short-height mode. Disconnect cancels pending animation/timers, removes listeners and the observer, and releases the scroll lock.

`reader_text` translates navigation and accessibility text at render time. Paired locale files are `config/locales/customer_docs.en.yml` and `customer_docs.zh-CN.yml`. Supplied locale becomes a hidden field in desktop/mobile GET search forms; the developer default adds none. Drawer labels reach the `developer-docs-nav` Stimulus controller, and copy labels the `docs-reader` controller, through data values. Homepage/figure additions use `customer_docs.home.guides_title`, `home.guides_intro`, `home.guides_empty`, `screenshots.full_size`, and `screenshots.open` (`%{caption}`). Section navigation uses `home_link`, `more_in_section`, and `group_descriptions.*`. Customer breadcrumbs use `customer_docs.home_link` for the home crumb, `customer_docs.groups.*` for the group crumb, and `DeveloperDocs::NavigationHelper#docs_navigation_label` for the short final article crumb.

Both `customer_docs` and `developer_docs` add paired `search_results` (**Search results**／**搜索结果**), `current_context` (**Reading now**／**当前阅读**), `sequence_label` (**Reading order**／**阅读顺序**), `back_to_top` (**Back to top**／**返回顶部**), `copy_code` (**Copy**／**复制**), and `copied_code` (**Copied**／**已复制**). Sequence cards use the existing `previous` / `next` labels (customers: 上一篇／下一篇; developers: 上一页／下一页). The doc-set home link uses `breadcrumb.reference`. Reuse existing `search_submit`, `search_clear`, `search_empty`, and navigation keys.

The customer-only `customer_docs.nav_labels` map is resolved at render time by `DeveloperDocs::NavigationHelper#docs_navigation_label(slug, title:, translation_scope:)` in `app/helpers/developer_docs/navigation_helper.rb`, shared by reader, contents and views. Missing customer labels fall back to the supplied full title; developer or other scopes keep full titles. No translated constants, duplicated maps or URL-parsing lookup are needed. Every published customer slug must have both locale keys:

| Slug | English label | Simplified Chinese label |
| --- | --- | --- |
| `overview` | Guide overview | 指南概览 |
| `getting-started` | Get started | 快速入门 |
| `assistant` | Use the assistant | 使用助手 |
| `users` | Manage users | 管理用户 |
| `payments` | Take payments | 收款管理 |
| `email` | Send email | 发送邮件 |
| `sms` | Send SMS | 发送短信 |
| `records` | Find records | 查找记录 |
| `forms` | Review forms | 查看表单 |
| `websites` | Publish website | 发布网站 |
| `settings` | Workspace settings | 工作区设置 |
| `billing` | Subscription & invoices | 订阅与账单 |
| `support` | Get help | 获取帮助 |

Search trims `q` to 80 characters and filters the contents list by localized title, summary, and body; short task labels do not introduce a separate search engine. It keeps the current article, unfiltered context, section footer and catalog-ordered previous/next links. The controller builds `search_path` with the index or article helper and only `locale: current_locale`, so clearing search removes `q` while preserving the language. Both desktop and mobile GET forms retain distinct input IDs, `maxlength=80`, `autocomplete=off`, and visible native submit controls. Hidden locale fields are essential because browsers replace a GET form action's query string with the submitted fields. Customer breadcrumbs and missing-page recovery links also include `locale: current_locale`.

An explicit `?locale=zh-CN` is request-local: `SetLocale` does not persist it to the user or cookie. Carrying the effective locale through customer guide navigation therefore keeps an English-preference administrator in Chinese until they choose another language. This also preserves English explicitly and uses the resolved locale when the requested value is unsupported or absent.

The global `LocaleSwitcherComponent` submits `PATCH /locale`. `LocalesController` validates the requested language, saves it to the cookie and signed-in user's profile, and replaces any existing `locale` query on the same-origin return URL. Switching an article from English to Chinese and back therefore retains the URL tenant, article, search and other query values, and fragment while rendering the newly selected language. Unsupported choices leave both the preference and a safe return URL unchanged; an absent, malformed, or off-origin referer falls back to the root. See [internationalization](internationalization) for the redirect contract.

### Help menu layout

Below `sm` (640px), the Help menu root uses `static` positioning so its absolute dropdown is anchored to the existing relative Topbar header. The panel sits below the header with a 0.5rem top margin, 1rem left and right insets, and automatic width bounded by `calc(100vw - 2rem)`. From `sm` upward, the root uses `relative` positioning and the panel returns to a 20rem-wide, right-aligned dropdown beside the Help button; its left and top insets reset to `auto`. Tailwind responsive utilities supply this layout.

### Screenshot authoring and safe rendering

Store assets at `public/help/docs/screenshots/<locale>/<basename>.png`; served URLs omit `public`. Author one standalone Markdown image paragraph, with nonblank meaningful alt text and a quoted title consumed as the visible caption:

```markdown
![Form access panel with launch status and member and public audience controls.](/help/docs/screenshots/en/forms-publishing.png "Check launch status and audience before sharing a form link.")

![表单访问面板中的上线状态及会员、公开访问控件。](/help/docs/screenshots/zh-CN/forms-publishing.png "分享表单链接前，先核对上线状态和访问范围。")
```

The six subjects per locale are `workspace-help.png` in getting-started, `records-list.png` in records, `forms-publishing.png` in forms, `website-publishing.png` in websites, `email-audience.png` in email, and `payment-settings.png` in payments. Place each beside its relevant procedure. If email uses a new-list capture, place it at audience creation, not beside a claim of resolved send-activity recipients.

`DeveloperDocs::Renderer.call` accepts `screenshot_root: nil` and `screenshot_labels: nil`. With no root, images retain existing stripping behavior. The only supported opt-in root is `"/help/docs/screenshots"`; enabled rendering requires localized `full_size` and `open` labels. Valid standalone Markdown images become semantic `figure` markup with an image anchor, `img`, `figcaption`, and native **View full size** link. Both links use the identical checked source in the same tab; browser Back returns to the guide. The image-link accessible label includes the caption. Renderer-owned image attributes use `loading="lazy"` and `decoding="async"`; alt/caption are escaped text, not trusted HTML or tooltip-only wording.

The entire raw source must match this policy before rendering and again during sanitization:

```text
\A/help/docs/screenshots/(?:en|zh-CN)/[a-z0-9]+(?:-[a-z0-9]+)*\.png\z
```

No external, protocol-relative, data/blob, SVG, relative, nested, query, fragment, percent-encoded, whitespace-padded, backslash, or traversal URL qualifies. Do not decode rejected input into an accepted path or fetch remote image content. Tag-specific sanitization permits only appropriate figure/image/link attributes, with controlled classes/loading/decoding; author event/style/srcset attributes are discarded. Raw HTML images do not qualify as authored figures. Unsafe or malformed images fall back to escaped alt text without image/full-size anchors. Screenshot links are a separate allow-listed static category, not guide slugs or a blanket allowance for root-relative destinations.

A valid path with a missing PNG can still fail in the browser. Publication checks require the file to exist and each locale to use its own image directory. Captions must describe the actual captured controls/state, including empty or disabled states; adjacent text carries all essential instructions. Static PNGs are public: capture publishable demo data with a real admin-role session, localized UI, and no owner-only chrome, credentials, recovery codes, or payment details. Do not fabricate success or population states.

`script/capture_help_doc_screenshots.mjs` drives Playwright Chromium against a running server and writes the six subjects to `tmp/help-doc-screenshots/<locale>/` (override with `SCREENSHOT_DIR`). It signs in through the real `/auth/sign_in` form with `DOCS_CAPTURE_EMAIL` and `DOCS_CAPTURE_PASSWORD` for a customer-admin demo workspace identified by `DOCS_CAPTURE_CUSTOMER_ID`. Do not point it at a `SKIP_AUTH=1` server: that stub can resolve the platform owner even on another tenant's URL. The script switches language through the real locale switcher, because the Manage access drawer link omits `?locale=`. Optional `DOCS_CAPTURE_ENTITY` (default `Workshop registrations`) and `DOCS_CAPTURE_PROVIDER` (default `Stripe`) choose the records list and the provider whose test environment is opened. Pass a locale (`en`, `zh-CN`, or `both`) and optional subject basenames to recapture a subset.

Captures use a 1440 × 1600 CSS-pixel light viewport at `DOCS_CAPTURE_SCALE` device pixel density (default **2**). The reader stretches every figure to the full prose column (up to 704px), so 1× captures of narrower crops are upscaled and blurry; 2× keeps text sharp in the column, on high-density displays, and at **View full size**. Each crop is measured from live elements (breadcrumb, target card or drawer, plus a 24px margin) rather than fixed coordinates, so layout changes do not cut off controls. The mouse is parked off-target before each capture so hover tooltips do not appear. Review the files before copying them over `public/help/docs/screenshots`. `spec/e2e/documentation_reader.app.spec.js` checks the reader chrome (grouped directory, section links, mobile drawer) when `APP_BASE_URL` is set.

### Editorial procedure and focused verification

Negative repository-search fixtures use a deterministic, namespaced nonce absent from the documentation corpus, shorter than the repository's 80-character query limit. Ordinary prose can become valid searchable content as guides evolve. Positive title/summary/body matches, query-independent hub cards and mixed-order navigation/cache checks remain part of the repository specs.

1. Keep all five H2s in order and add task H3s. Give a starting screen, exact visible actions, numbered field-level substeps, a useful example, nearby result checks, and practical recovery.
2. Verify consequential behavior against controllers/services and action labels against locale/component sources before translating. Keep en/zh-CN sections, examples, related targets, callouts, and image subjects aligned.
3. Put `:::note` beside save/activation/publication distinctions and test evidence; use `:::attention` for consequential supported actions. Alipay/WeChat probes do not prove a real vendor journey. Test-email context is current_user; tenant MFA applies to admins/owners and account-specific timeout/failed-attempt settings are enforced through Settings/TenantSecurityPolicy. Page Save, page Published and site publication remain distinct; see [Authentication](authentication).
4. Check captures and captions together; preserve stable basenames when using an honest fallback. Required alt/title and standalone placement are authoring checks, not evidence that the depicted operation succeeded.
5. Run focused content/repository/renderer/component/request checks, then inspect both audiences/locales at 320/390/768/1024/1440px and 200% zoom, including expanded/collapsed developer app sidebars. Measure container-based rail modes, the 704px bound, H1/prose alignment and typography; check complete hubs under matching/no-result queries, one article TOC, keyboard guide/full-size links, image navigation/Back, mobile contents, search/locale recovery, and local table/code scrolling without page/main horizontal overflow.
6. Check cross-group navigation without disclosures for both audiences. Exercise queries including/excluding the current article and zero results: retain group breadcrumbs, one canonical current link per visible contents surface, section footer and footer sequence targets. At 1440px verify full-height rails, scroll-spy, the `/` shortcut, Back to top and code copy. Verify visible Search/Enter/Clear, locale-safe group fragments, fixed header/list scrolling, and late-guide drawer reveal with close focus and unchanged main scroll. At wide W, verify single-column/drawer mode at H=550px and restoration of container modes at H=640px.

`spec/services/customer_docs/published_guides_spec.rb` covers every source, metadata, required headings, related-link/fragment parity, and screenshot locale/path/alt/caption/file checks. Repository specs cover all 12 guide entries, fallback, missing/empty groups, query independence, URL-customer/locale links, fresh metadata, and cache-policy isolation. Renderer specs exercise both locale paths, caption/alt escaping, malformed and adversarial URLs/attributes, identical native links, and image-stripping defaults. Home-guide/reader/contents component specs cover normal/empty states, accessible grouped rows, the optional central header, TOC eligibility, navigation and locale contracts. Request specs cover home and explicit overview groups, non-home omission, tenant/role guards, localized navigation, search and 404 recovery. Browser evidence verifies actual geometry and computed typography.

Navigation verification adds repository checks for unfiltered `current_group`, real results, missing siblings, neighbor slugs and symbol/string `q` removal; helper checks for render-time labels, fallback and locale-key completeness; component/request checks for fixed controls, unique descriptions, static groups for both audiences, query-independent context/section/footer targets and the reading-aid wiring. The `developer-docs-nav` Vitest suite covers optional list/marker paths, reveal decisions and the modal lifecycle; the `docs-reader` suite covers pane measurement, scroll-spy, the `/` shortcut, code wrapping and both copy paths. Actual row visibility, rail height and unchanged main scroll require the app browser spec. Both controllers must retain 100% lines, branches and functions under configured coverage. These are focused checks for this slice, not a full Rails-suite requirement.

The app browser checks allow 90 seconds per journey and finish the shell's initial importmap preload burst before interacting. Contents search is a native GET form, not a debounced client filter: Enter must produce a completed same-origin 200 response at the form action with both `q` and `locale`, update the address bar, and finish the final Turbo render/controller mount. Both input values, complete hub links, localized results and Clear recovery are still checked. Lazy screenshot checks scroll the image into view, await `HTMLImageElement.decode()`, then require positive natural dimensions and the original aspect ratio; a missing or invalid image rejects decoding. This avoids treating queued requests as missing query parameters or broken PNGs. Run the documentation and [top navigation](dashboard) browser files together with `--workers=4` and a unique output directory; keep the shared application/static servers running.

```bash
bundle exec rspec spec/services/customer_docs spec/services/developer_docs/renderer_spec.rb spec/services/developer_docs/repository_spec.rb spec/helpers/developer_docs/navigation_helper_spec.rb spec/components/customer_docs/home_guides_component_spec.rb spec/components/developer_docs/reader_component_spec.rb spec/components/developer_docs/contents_nav_component_spec.rb spec/requests/admin/help/docs_spec.rb spec/requests/admin/maintenance/platform/developer_docs_spec.rb
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/developer_docs_nav_controller.test.js spec/javascript/controllers/docs_reader_controller.test.js
npx vitest run --config config/javascript/vitest.config.js --coverage
bin/rails tailwindcss:build
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/documentation_reader.app.spec.js --project chromium
git diff --check
```

## Where to pay attention

:::attention
Authorization comes from the admin URL prefix and the inherited centralized guards. Hiding the Help link is not authorization. Customer documentation must not expose the owner-only developer reference or bypass tenant checks. Keep the developer controller under `/admin/maintenance/platform/`.
:::

:::attention
Catalog injection must reach both repository and renderer. Customer internal cross-links use customer catalog slugs such as `getting-started`, not developer slugs or filesystem paths. A safe HTTP(S) external link is still supported by the shared renderer; the injected catalog governs internal article links.
:::

:::attention
Rendered-fragment caching is distinct from HTTP caching. `Renderer::CACHE_VERSION` is `documentation/v6`; the key includes `SCREENSHOT_POLICY_VERSION` (`screenshots/v1`), screenshot root and localized labels, catalog name, translation scope, route helper/options, customer id, selected locale, source path, and subsecond `mtime`. Policy changes cannot reuse old image-stripped or differently allowed output. Component-only header/layout/Tailwind changes do not alter renderer-emitted HTML and need no cache-version change. Saving Markdown invalidates its fragment without restart; homepage metadata is assembled outside that cache. Customer HTML remains `private, no-store`.
:::

:::attention
Locale fallback is a runtime convenience, not a publishing substitute. Every customer slug needs both language files and all five required headings. `spec/services/customer_docs/published_guides_spec.rb` checks the published content contract; the developer repository spec checks this implementation reference against the separate developer headings.
:::

## Key code

```ruby
# app/services/developer_docs/repository.rb — shared customer/developer metadata
Page = Data.define(
  :slug, :title, :summary, :html, :headings, :groups, :current_group,
  :previous_page, :next_page, :query, :search_path
)
Group = Data.define(:key, :entries)
Entry = Data.define(:slug, :title, :path, :active)
Link = Data.define(:slug, :title, :path)
```

```ruby
# app/helpers/developer_docs/navigation_helper.rb
def docs_navigation_label(slug, title:, translation_scope:)
  return title unless translation_scope == "customer_docs"

  I18n.t("#{translation_scope}.nav_labels.#{slug}", default: title)
end
```

```ruby
# app/services/customer_docs/repository.rb
class Repository < DeveloperDocs::Repository
  def initialize(customer_id:, locale: I18n.locale,
                 screenshot_root: DeveloperDocs::Renderer::SCREENSHOT_ROOT, **options)
    super(
      customer_id:, locale:, catalog: Catalog,
      content_root: Rails.root.join("doc/customer"), translation_scope: "customer_docs",
      route_helper: :admin_help_doc_path, screenshot_root:, **options
    )
  end
end
```

```ruby
# app/controllers/admin/help/docs_controller.rb
def render_page(slug)
  response.headers["Cache-Control"] = "private, no-store"
  repository = CustomerDocs::Repository.new(
    customer_id: current_customer_id, locale: current_locale, route_options: { locale: current_locale }
  )
  @page = repository.page(
    slug,
    query: params[:q],
    search_path: search_path
  )
  if @page
    @guide_groups = @page.slug == CustomerDocs::Catalog::HOME_SLUG ? repository.guide_groups : nil
    render :show
  else
    render :missing, status: :not_found
  end
end

def search_path
  if action_name == "index"
    helpers.admin_help_docs_path(current_customer_id, locale: current_locale)
  else
    helpers.admin_help_doc_path(current_customer_id, params[:slug], locale: current_locale)
  end
end
```

```erb
<%# app/views/admin/help/docs/show.html.erb %>
<%
  current_group = @page.current_group
  home = @page.slug == CustomerDocs::Catalog::HOME_SLUG
  home_path = admin_help_docs_path(current_customer_id, locale: current_locale)
  doc_crumbs = [
    { label: t("chrome.help_menu.help") },
    { label: t("customer_docs.home_link"), path: home_path }
  ]
  if current_group && !home
    doc_crumbs << { label: t("customer_docs.groups.#{current_group.key}"), path: "#{home_path}#customer-doc-guide-group-#{current_group.key}" }
  end
  doc_crumbs << { label: docs_navigation_label(@page.slug, title: @page.title, translation_scope: "customer_docs") } unless home
%>
<%= render DeveloperDocs::ReaderComponent.new(
  page: @page, translation_scope: "customer_docs", locale: current_locale,
  article_variant: :customer, home_groups: (home ? @guide_groups : nil),
  home_path: home_path
) do |reader| %>
  <% reader.with_header do %>
    <%= render AdminPageComponent.new(
      breadcrumbs: doc_crumbs, title: @page.title, description: @page.summary,
      wrap_title: true, width: "full"
    ) %>
  <% end %>
<% end %>
```

The catalog and heading contract are in `app/services/customer_docs/catalog.rb`. Shared configuration and link validation are in `app/services/developer_docs/repository.rb` and `renderer.rb`; reader translations are selected in `app/components/developer_docs/reader_component.rb` and its template. The Help entry is in `app/components/help_menu_component.rb` and its template. Focused checks live in `spec/services/customer_docs/`, `spec/services/developer_docs/repository_spec.rb`, and the Help-menu and reader component specs. `spec/requests/admin/help/docs_spec.rb` follows generated Chinese guide links with an English-preference account, submits both search forms without reusing the action query, clears search, and follows missing-page recovery and Help links. It also submits the rendered global locale-switch forms sequentially from English to Chinese and back, follows each redirect, verifies localized content and retained URL context, and checks unsupported choices. `spec/requests/locales_spec.rb` covers query preservation and unsafe-referer root fallbacks.

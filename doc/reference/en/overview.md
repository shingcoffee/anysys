---
title: "Developer reference"
summary: "How this reference is written, rendered, browsed by topic, and who is allowed to read it."
---

## Summary

This is the maintained guide to how Anysys works. It is for the platform owner and for engineers changing the product. Each page covers one capability: what it is, how a request or edit moves through the code, where the implementation lives, and the spots that are easy to get wrong.

The pages are Markdown under `doc/reference/en` and `doc/reference/zh-CN`. [Kramdown](https://kramdown.gettalong.org/) with its GFM parser turns a page into HTML, assigns ids to headings, and highlights fenced code with Rouge. The Rails page at `/:customer_id/admin/maintenance/platform/developer_docs` hosts that HTML. Historical notes in `docs/` are design records; when they disagree with the code, trust the code and update this reference.

Start with the [system map](system-map), then open the builder you are changing: [entity builder](entity-builder), [flowchart builder](flowchart-builder), or [page builder](page-builder).

Customer administrators read a separate set of operational guides from **Help → Documentation** at `/:cid/admin/help/docs`. Those pages live under `doc/customer`, use `CustomerDocs::Catalog`, and share the rendering infrastructure described here. Their admin-or-owner access does not grant access to this owner-only reference. See [customer documentation](customer-documentation).

## Flow

```text
doc/reference/<locale>/<slug>.md
        |
        |  YAML front matter + Markdown
        v
DeveloperDocs::Repository
        |  slug must be in DeveloperDocs::Catalog
        v
DeveloperDocs::Renderer
        |  Kramdown GFM, Rouge, callouts, heading ids
        v
Loofah allow-list
        v
DeveloperDocs::ReaderComponent
        |  sticky mobile Contents bar | full-height left rail (home/search/context + list)
        |  central header slot | grouped topic hub (home) | article
        |  scroll-spied "On this page" | unfiltered section + footer sequence
        v
GET /:cid/admin/maintenance/platform/developer_docs/:slug
        |
        |  RouteAuthorization: platform_owner? only
        v
Platform owner session
```

The home directory groups topic links in bordered cards, one per catalog group. Both audiences' Contents show every group as a static labelled section (`<section aria-labelledby>` + `<h3>` + indented list); there is no collapsing. Searching shows only the groups that still have matches. Filtering Contents never reduces either home directory. "On this page" appears only on articles with headings, with exactly one inline or right-rail TOC visible, and the reader highlights the section being read. Hubs reserve no right rail. "More in this section" lists the other pages in the unfiltered current group as cards, including during search. Previous/next cards appear once, after the article; there is no sequence row above the prose.

## Implementation

`DeveloperDocs::Catalog` is the ordered list of slugs and groups. A slug that is not in the catalog is a 404, and the repository will not join it onto a filesystem path.

`DeveloperDocs::Repository` reads `doc/reference/<locale>/<slug>.md` by default, parses the front matter, and renders the body. The locale is `I18n.locale` when it is supported by the configured catalog; anything else falls back to English. A missing localized source also falls back to its English source. Search matches the title, summary, and body and only filters the contents list.

`Repository::Page` carries an unfiltered `current_group` independently of query-filtered `groups`. Sequence/section/context navigation clears both forms of `q` while preserving tenant and effective locale. Developer destinations now retain `locale`, rather than discarding a request-only language override. Do not add fake search results or another full directory on Page.

The repository accepts `catalog:`, `content_root:`, `translation_scope:`, and `route_helper:`. Defaults are `DeveloperDocs::Catalog`, `Rails.root.join("doc/reference")`, `"developer_docs"`, and `:admin_maintenance_platform_developer_doc_path`. `CustomerDocs::Repository` supplies its own catalog, `doc/customer` root, `"customer_docs"` translation scope, and `:admin_help_doc_path`. Rendered-fragment cache keys include catalog name, translation scope, route helper, customer id, selected locale, source path, and subsecond file `mtime`, keeping both readers' content and links separate. Saving a source file refreshes its rendered fragment without a server restart.

`DeveloperDocs::Renderer` is the only Markdown entry point. It pulls `:::attention` and `:::note` blocks out of the source (fenced code is left alone), renders them with Kramdown, and puts them back as asides. Heading ids are written onto the Kramdown tree before HTML conversion so the table of contents and the article share one target. Its injected `catalog:` defaults to `DeveloperDocs::Catalog`; catalog-slug links are rewritten by the supplied link resolver to the platform route for this reference, or the customer Help route for customer guides. The result is scrubbed with Loofah: scripts and unexpected attributes do not survive.

`DeveloperDocs::ReaderComponent` uses `translation_scope: "developer_docs"` by default. The customer view passes `"customer_docs"` to select its own contents, search, group, navigation, and accessibility labels. Both readers share responsive chrome, fixed controls, query-independent section links, sequence and the `developer-docs-nav` + `docs-reader` Stimulus controllers. The developer overview also passes `home_groups` from `Repository#hub_groups`, independently of `q`, and the platform reference index as `home_path`. Index and explicit `/developer_docs/overview` show the same complete hub. `home_groups: nil` omits the directory; `[]` retains overview prose with the localized unavailable message.

The optional `header` slot contains the existing `AdminPageComponent` (`wrap_title: true`, `width: "full"`), wrapped in a bordered `<header>` so breadcrumbs, the single H1 and the summary sit above the article. Articles use a central column capped at 704px (`max-w-[44rem]`); the home hub widens to 960px so its cards can sit three across, while its prose stays at 704px. The reader is capped at 1200px inside shell gutters. At viewport height ≥640px, named container queries use its actual available width after app-sidebar space: Contents appears at 832px (`@min-[52rem]/docs`) in a 240px rail; articles with headings gain a 192px right rail at 1056px (`@min-[66rem]/docs`); gaps are 40px. Below 832px a sticky bar at the top of the main scroll area holds the Contents trigger and the current "group / page" location; below 1056px eligible articles use the collapsible inline TOC. At viewport height <640px, grid/rails/bar/drawer/backdrop/TOC use a complementary single-column/drawer mode regardless of reader width. Hub cards switch to two columns at 576px and three at 832px of hub width; "More in this section" cards use two columns at 640px; footer previous/next cards sit side by side at 480px.

Desktop Contents sticks 24px below the top of the main scroll area and fills its height: `docs-reader` writes the main element's `clientHeight` to `--docs-pane-height` (kept current by a `ResizeObserver`), and the rail uses `calc(var(--docs-pane-height) - 3rem)` with a `100dvh - 10rem` fallback. Header/controls stay fixed above a scrolling `min-h-0` list. The `h-dvh` drawer shares that split with safe-area insets. The desktop header starts with a doc-set home link (book icon + `breadcrumb.reference`) when `home_path` is given, and the drawer header uses the same title as a home link. A 40px search field with a leading Search button and a `/` hint follows, plus a visible Clear link while searching. GET search retains its 80-character normalization; both readers preserve effective locale through hidden search fields and clear/navigation links, without changing the user's global language preference.

The developer controller builds `Page#search_path` from the current route parameters and the effective `locale`, without `q`. Both pinned Clear controls and the empty-results recovery link use that URL. Clearing a Chinese search therefore stays on the same Chinese index or article even when the account preference is English; the two forms also submit their hidden locale values.

At viewport height <640px the drawer reduces spacing and pairs input/Search, plus home/Clear when both exist, to preserve list space. The controls keep visible wording and 44px targets, context stays fixed, and the list reserves at least 64px. At height ≥640px normal full-width stacked controls and the retained width-container modes apply.

During search, fixed **Reading now** retains the unfiltered group/current guide, with the only `aria-current="page"` / `data-docs-current-guide` anchor in that contents surface. **Search results** uses only genuine `page.groups` matches, with no active semantics even if the current page matches. Without a query, the normal active list row owns those semantics. Reader context, both show-view group breadcrumbs and `section_entries` read `page.current_group`. Group links append `developer-doc-guide-group-<key>` or `customer-doc-guide-group-<key>` to the supplied home URL, preserving customer locale before the fragment. Selecting current context clears search on the same guide; section and sequence links also clear `q`.

`DeveloperDocs::ContentsNavComponent` adds `surface: :desktop` / `:mobile` while retaining `page:`, `translation_scope:` and `navigate:`. `DeveloperDocs::NavigationHelper#docs_navigation_label(slug, title:, translation_scope:)` provides render-time customer `customer_docs.nav_labels.<slug>` lookup with full-title fallback; developer links keep full metadata titles. Short customer contents/context links use uniquely scoped full-title `aria-describedby` IDs; the H1, hub and footers retain full titles. Both namespaces supply `search_results`, `current_context`, `sequence_label`, `previous`/`next`, `back_to_top`, `copy_code` and `copied_code`. The footer sequence (`data-docs-footer-sequence`) follows the prose and "More in this section"; its query-free cards show a Previous/Next label above the full title.

`docs-reader` (`app/javascript/controllers/docs_reader_controller.js`) adds the reading aids. Scroll-spy marks the TOC link of the last heading above a 120px reading line with `aria-current="location"`; the last heading wins at the end of the scroll. Pressing `/` outside an editable field focuses and selects the visible search field (`aria-keyshortcuts="/"`). Each `pre` in the prose is wrapped from a `<template>` with a Copy button (shown on hover/focus on pointer devices, always on touch) that uses the Clipboard API with an `execCommand` fallback for plain-HTTP origins and announces "Copied" through `aria-live`. The right rail ends with a **Back to top** link to the article id. Listeners, the observer, the animation frame and copy timers are removed on disconnect.

Navigation hooks are `data-docs-nav-header`, `data-docs-nav-list`, and the canonical `data-docs-current-guide` anchor. On initial desktop layout and entry into desktop mode, the normal current-guide row is revealed by scrolling only the desktop list, making late-catalog guides immediately visible without changing focus or the window/main/article position. Drawer reveal runs separately on opening: the optional `data-developer-docs-nav-target="drawerList"` list scrolls while the close control retains focus with `preventScroll`. Search context is already fixed in the header, so drawer results start at the top. Closed drawers remain inert/aria-hidden; focus trapping/return, native navigation, scroll restoration and resize/disconnect cleanup are retained. Actual trigger visibility remains the JS mode authority, including short-height fallback.

Reader-owned Tailwind utilities replace custom docs CSS; `.docs-page`, `.customer-doc` and `.developer-doc` remain semantic/test hooks. Both audiences use `font-sans` and the application type scale at every width: H1 20px/27.5px, summary 13px/19.5px, prose 14px/21px, H2 20px/25px, H3 18px/24.75px, and navigation 13px/19.5px. Code stays `font-mono` at the application `pre` size. Both readers' tables and code scroll locally; screenshots retain natural ratios and wrapping captions. Component-only layout/header utilities do not change renderer HTML or its cache version. See [customer documentation](customer-documentation) for the full component, locale and screenshot contracts.

`Admin::Maintenance::Platform::DeveloperDocsController` is a thin reader. The index action renders the `overview` slug. The show action renders `params[:slug]`. Both sit under `/admin/maintenance/platform/`, which `RouteAuthorization` already limits to `platform_owner?`. There is no second role check in the controller. The controller reuses one repository per request for the article and, on the home slug, the grouped topic directory.

The shell link is `MaintenanceContributor`, shown only when the URL customer is `81721200` and the user is a platform owner.

### Adding a page

1. Add the slug to `DeveloperDocs::Catalog::GROUPS` in the group it belongs to.
2. Add `doc/reference/en/<slug>.md` and `doc/reference/zh-CN/<slug>.md`.
3. Front matter needs `title` and `summary`. Do not add an H1; the page header renders the title.
4. Use the five required second-level headings for that locale.
5. Put sharp edges in `:::attention` blocks and cite the file you mean in `Key code`.

### Reader verification

Use the [focused checks](customer-documentation) for content, components and requests. After building Tailwind, run the existing browser spec against a running app:

```bash
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/documentation_reader.app.spec.js --project chromium
```

Inspect both audiences/locales at 320/390/768/1024/1440px and 200% zoom, including expanded/collapsed developer app sidebars. Verify measured container modes, the central bound and H1/prose alignment, computed typography, complete hubs under matching/no-result searches, TOC/navigation/drawer keyboard behavior, and local rich-content scrolling without page/main horizontal overflow. Add focused 390/1440px navigation checks for static groups in both audiences, visible Search/Enter/Clear, query-independent context/section links and footer sequence targets, plus a 1440px reading-aids check (full-height rails, scroll-spy, `/`, Back to top, code copy). Verify fixed controls while the list scrolls, locale-safe group fragments and 320px late-guide reveal with close focus and unchanged main position. At wide reader width, H=550px uses the drawer and H=640px restores container modes. Repository/helper/component/request checks and the touched controller's 100% Vitest lines/branches/functions complement real browser geometry; see the linked focused commands. A run skipped without `APP_BASE_URL` is not browser evidence.

## Where to pay attention

### Route audit: documentation identity and evidence

The developer reader uses the existing Catalog allowlist, locale-aware repository/Reader input and mtime cache. Owner plus actual outer platform CID `81721200` is required for index/show, including formats. Generated links, hub/context/sequence and search keep the selected locale. See [Tenancy and roles](tenancy-and-roles), [Customer documentation](customer-documentation).

:::note
The current RC-01–RC-18 APIs and caller integrations are source-documented in both locales. Historical October 11 outstanding lists describe earlier snapshots; current implementation determines the reference. On 2026-10-12, after the development database applied pending migrations `20261011000100`, `20261011173041`, `20261011184517`, and `20261011190000`, `bin/rails parallel:prepare && bin/rails parallel:spec` ran 1,576 spec files on 8 workers and finished with **25,266 examples, 0 failures** (exit 0, 321 seconds). `npx vitest run --config config/javascript/vitest.config.js --coverage` finished with **290 files, 6,956 tests, 0 failures** and 100% statements, branches, functions, and lines. These suite results do not certify live provider, deployment, or browser journeys the suites do not exercise.
:::

:::attention
Only the pinned owner may open this namespace, on outer CID `81721200`. Tenant admins, including those of that customer, fail the central role gate.
:::

:::attention
Both locales are required. A key or a page in `en` without `zh-CN` is incomplete. The English heading texts and the Chinese heading texts are fixed by `DeveloperDocs::Catalog::REQUIRED_HEADINGS` so the table of contents stays predictable.
:::

:::attention
Do not render a slug that did not come from the configured catalog. `Repository#existing_path` also refuses a path that escapes the configured content root (`doc/reference` by default), but the allow-list is the real guard. Cross-links in Markdown must be bare slugs such as `entity-builder`, not filesystem paths. Customer guide slugs and required headings belong to `CustomerDocs::Catalog`; developer reference pages belong to `DeveloperDocs::Catalog`.
:::

:::note
Callout markers inside a fenced code block are documentation, not callouts. The extractor skips lines that sit between ``` fences.
:::

## Key code

```ruby
# app/controllers/concerns/route_authorization.rb
def enforce_route_role!
  if platform_namespace? || flowchart_namespace?
    return if current_user.platform_owner?
    raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required")
  end
  # ...
end
```

```ruby
# app/models/authentication/user.rb
PLATFORM_CUSTOMER_ID = 81_721_200

def platform_owner?
  owner? && eligible_for_owner_role?
end
```

```ruby
# app/services/developer_docs/catalog.rb
HOME_SLUG = "overview"
LOCALES = %w[en zh-CN].freeze
```

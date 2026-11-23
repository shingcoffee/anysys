# Documentation reader — UX specification

- Date: 2026-10-11
- Status: READY_FOR_FRONTEND
- Implementation: [documentation-reader plan](../plans/2026-10-11-documentation-reader.md)
- Design basis: current working-tree components, views, repositories, dashboard shell, locale files, and `spec/e2e/documentation_reader.app.spec.js`.

## 1. Decision and design basis

Use a **quiet editorial reader**: a compact grouped contents rail, a bounded central column with its own breadcrumb/title/summary, and a small heading rail only when the available content width supports it. The hub uses one neutral panel per catalog group, with simple guide rows inside, instead of a box around every guide. Hierarchy comes from type, whitespace, and thin separators.

Brainstorm resolution: enlarging the present full-width header leaves it disconnected from the article; shrinking type to accommodate three viewport-triggered columns undermines readability. Center-column chrome plus content-width breakpoints directly addresses both problems and also works when the developer reader's app sidebar is expanded.

The shadcn skill/MCP is unavailable. The agent consulted the official [Sidebar](https://ui.shadcn.com/docs/components/sidebar) and [Typography](https://ui.shadcn.com/docs/components/typography) pages (Typography redirects to Typeset). Adapt their grouped Sidebar/Collapsible, neutral Card, Breadcrumb, Sheet, and Separator patterns through existing Rails ViewComponents, Tailwind utilities, and Stimulus. Use the existing Inter/system sans family and app color tokens.

Current-source findings:

- `AdminPageComponent` currently places the header above the entire reader. Its default subtitle/body-small scale is 20px/13px; docs CSS raises it separately.
- The reader currently allocates 280px left + 224px right + two 40px gaps at viewport `xl`. The developer app sidebar can consume another 288px.
- Customer Help uses the `home` dashboard menu and has no persistent app sidebar. Developer reference uses `maintenance`, with a session-persisted 48px collapsed rail or expanded sidebar.
- Global `text-base` is 14px, `text-sm` is 13px, and paragraphs have explicit base font sizes. A wrapper font size alone cannot establish document typography.
- Complete hub metadata already exists independently of `q`: customer `guide_groups`, developer `hub_groups`. Treat the current working tree as the integration baseline, including its untracked contents component and e2e spec.

## 2. Surface inventory and composition

| Surface | Navigation area | URL | Composition |
| --- | --- | --- | --- |
| Customer hub | admin → Help → Documentation | `/:cid/admin/help/docs`, explicit `/docs/overview` | Contents, central header, complete grouped directory, compact overview Markdown, continuation links |
| Customer article | admin → Help → Documentation | `/:cid/admin/help/docs/:slug` | Contents, central header, heading navigation, Markdown, section links, previous/next |
| Developer hub/article | admin → Maintenance → Platform → Developer reference | `/81721200/admin/maintenance/platform/developer_docs[/:slug]` | Same reader geometry/type; separate catalog, translations, and existing owner gate |
| Small-screen contents | same parent admin surface | Existing reader drawer | Home, search, grouped links, close control |

```text
Existing dashboard chrome and scrollable main
┌────────────────────────────────────────────────────────────────────┐
│ CONTENTS (224)   │ CENTRAL READING COLUMN (max 704) │ PAGE TOC (160) │
│ Home / Search   │ Breadcrumb                      │ On this page   │
│ Group ▾         │ H1: localized title             │ H2 link        │
│   Active guide  │ Outcome summary                 │   H3 link      │
│ Group ▸         │                                 │                │
│                 │ HUB: directory heading          │ absent on hub  │
│                 │ [Group: title + guide rows]     │                │
│                 │ [Group: title + guide rows]     │                │
│                 │ overview prose                  │                │
│                 │ OR ARTICLE: inline TOC if needed │                │
│                 │ H2 / body / H3 / figures / code │                │
│                 │ More in this section            │                │
│                 │ Previous                 Next   │                │
└────────────────────────────────────────────────────────────────────┘
Below rail threshold: central column + existing Contents drawer trigger.
```

Header, hub, inline TOC, article, and continuation navigation share the same left edge and reading measure. Exactly one page H1; Markdown remains H2+.

## 3. Exact geometry

All dimensions are CSS pixels at the existing 16px root. Use Tailwind v4 **named container queries**, not viewport `lg`/`xl`, for reader rail visibility. Let **W** be the reader container width after app-sidebar space and existing shell gutters.

| Region/rule | Specification |
| --- | --- |
| Reader wrapper | `w-full min-w-0 max-w-[75rem] mx-auto @container/docs` (1200px cap); no second set of horizontal gutters |
| W < 896px | One column; desktop Contents hidden, drawer trigger available |
| 896px ≤ W < 1152px | `224px minmax(0,1fr)`, 32px gap; inline article TOC |
| W ≥ 1152px, article with headings | `224px minmax(0,1fr) 160px`, 32px gaps; heading rail visible and inline TOC hidden |
| Hub / article without headings | Maximum two columns; never reserve a right rail |
| Central strip | `w-full min-w-0 max-w-[44rem] mx-auto` (704px cap), wrapping rather than truncation |
| Rails | `min-w-0`; contents has a subtle right separator with 16px inner right padding; TOC has left separator with 16px padding; widths include padding/border |
| Rail scrolling | Sticky 24px inset relative to `#main-content`; inner `max-h-[calc(100dvh-16rem)] overflow-y-auto`; vertical page scrolling stays in the existing main |
| Hub panels | One column below **central-strip** width 640px; two `minmax(0,1fr)` columns from 640px, 24px gaps; query a nested `@container/hub`, not viewport width |
| Previous/next | One column below central width 640px; two above; no empty placeholder taking vertical space on mobile |
| Small-screen drawer | Keep 320px preferred width capped at 85vw; 16px insets; search and close control at least 44px high; existing Contents trigger bottom/right 16px, minimum 44px height |

Use `@min-[56rem]/docs:` for contents and `@min-[72rem]/docs:` for the right rail. Make all desktop/mobile rail, TOC, trigger, backdrop, and drawer visibility rules complementary at these same thresholds. Place container variants on descendants, since a container cannot query itself.

Expected horizontal budget, retaining `LayoutHelper` gutters (12px below `sm`, 16px from `sm`, 32px from `lg`):

| Viewport | Customer W / mode / central strip | Developer with expanded app sidebar | Developer with collapsed app rail |
| --- | --- | --- | --- |
| 320 | 296 / one column / 296 | Sidebar hidden; 296 / one | Sidebar hidden; 296 / one |
| 390 | 366 / one column / 366 | Sidebar hidden; 366 / one | Sidebar hidden; 366 / one |
| 768 | 736 / one column / 704 | 496 / one / 496 | 688 / one / 688 |
| 1024 | 960 / two columns / 704 | 704 / one / 704 | 912 / two / 656 |
| 1440 | 1200 capped / three on article / 704 | 1088 / two / 704 | 1200 capped / three on article / 704 |

These budgets precede any scrollbar allocation; mode selection follows measured W. Two rails first appear only when the central track can retain 704px. One left rail first appears with at least 640px of central space. Hub panels fit independently of app-sidebar state.

## 4. Typography, spacing, and visual treatment

Use explicit rem sizes: the app's standard size utilities do not represent standard Tailwind sizes. W ≥ 640px selects the wide reader type scale; narrower W uses the compact scale. Both audiences use the same scale.

| Element | Compact size / line height | Wide size / line height | Weight / color |
| --- | --- | --- | --- |
| Page H1 | 28 / 34 | 32 / 40 | 600, primary, tight tracking; wrap |
| Summary and article prose | 16 / 28 | 17 / 30 | 400, secondary |
| Markdown H2 / hub directory H2 | 22 / 30 | 24 / 32 | 600, primary, tight tracking |
| Markdown H3 | 18 / 26 | 20 / 28 | 600, primary |
| Hub group H3 | 18 / 26 | 18 / 26 | 600, primary |
| Hub guide title H4 | 16 / 24 | 16 / 24 | 500, primary; hover accent |
| Hub descriptions and summaries | 16 / 24 | 16 / 24 | 400, secondary |
| Contents/home/TOC/breadcrumb links | 14 / 20 | 14 / 20 | 400; active 500, accent text |
| Search input | 16 / 24 | 16 / 24 | 400, primary; 44px control height |
| Rail labels, group summaries, continuation labels | 14 / 20 | 14 / 20 | 600, secondary; sentence case |
| Tables, captions, code blocks | 16 / 26 | 16 / 26 | Normal; code uses existing mono family |

Inline code inherits prose size. Callout body inherits prose size; its existing localized label may use 14/20 semibold. Body/list/blockquote/table-cell/callout paragraphs receive explicit inherited font-size **and** line-height utilities, overriding global paragraph defaults. Avoid uppercase/tracked navigation labels, especially for Chinese. Primary/secondary/tertiary tokens provide hierarchy; do not use the low-contrast muted token for essential navigation text.

- Header bottom gap 32px; breadcrumbs bottom gap 16px; summary top gap 12px. Use the breadcrumb group context instead of repeating it as an info badge beside H1.
- Paragraphs `my-4`; H2 `mt-10 mb-3`, first direct H2 `mt-0`; H3 `mt-7 mb-2`; H4 `mt-6 mb-2`. No rule under every H2.
- Lists `my-4 pl-6`; customer sibling items 12px apart, reference items 8px; nested lists 8px vertical gap. Preserve bullets/numbers, strong text, underlined article links, heading IDs, permalink links, and scroll offsets.
- Hub H2/intro precede the panel grid with 24px gap. One `CardComponent` per **group**: border-subtle, surface background, 12px radius, 16px padding on compact screens / 20px wide, no shadow. Group description follows H3 by 8px; rows start 16px below it. Each guide is one native anchor with its existing title/summary IDs, trailing decorative arrow, `py-3`, 8px title/summary gap, thin separators between rows, subtle neutral hover, and visible focus. No separate card per guide, truncation, or clamping. Panels have natural heights and top-align in the grid.
- Keep overview Markdown after the full directory with 40px separation. Preserve all required source headings and all existing metadata/content.
- Inline TOC uses existing native `details`, 1px border and 8px radius, 12–16px padding, 24px bottom gap. TOC H3 links indent 12px beyond H2. Show exactly one visible TOC on eligible articles, none on either hub.
- Contents rows/group summaries have at least 32px height in the desktop rail and 44px in the drawer. The 16px search input prevents small-input automatic zoom on mobile browsers.
- Section links use a top separator, 24px inset and 40px top gap rather than another filled box. Previous/next keep restrained bordered links, 16px padding, 16px title text, 40px top gap. Keep catalog order and endpoint behavior.

### Overflow and rich content

Every grid/flex child in the reader has `min-w-0`; prose/title/navigation links use `[overflow-wrap:anywhere]` where long tokens require it. Breadcrumbs may scroll locally within their bounded nav. Both customer and developer tables use `block max-w-full overflow-x-auto`; code uses `max-w-full overflow-x-auto whitespace-pre` with normal token wrapping disabled inside `pre`. Syntax highlighting remains intact. Screenshots retain `w-full h-auto`, natural ratio, caption wrapping and native full-size links. Page/main overflow must be solved by these bounds, not by hiding clipped content with `overflow-x-hidden`.

## 5. Data, states, actions, and flows

Data map: header `page.title`/`page.summary`; breadcrumbs existing view crumbs; contents `page.groups`/entry `title`, `path`, `active`; TOC `page.headings`; Markdown `page.html`; hub separate `home_groups`/group `key`/guide `slug`, `title`, `summary`, `path`; section mates existing `current_group`/`section_entries`; sequence `page.previous_page`/`next_page`. Paths stay repository-generated, in the current URL customer context.

- **Hub → guide:** Help → Documentation → `/C/admin/help/docs?locale=L` → select a guide row → existing localized article URL. All 12 non-overview customer guides appear once in the directory across eight current groups (`home`, `assistant`, `users`, `payments`, `communication`, `entities`, `content`, `settings`). Developer hub follows its own complete catalog. Explicit overview routes behave identically.
- **Search:** desktop rail or drawer GET form → only Contents filters; hub directory and current article remain. Groups open for active entries or all matching groups while searching. Zero matches displays existing translated search-empty copy. Clear returns to `page.search_path`. Preserve both search field IDs, maxlength 80, hidden customer locale fields, and developer's existing query-free link convention.
- **Navigate:** active link retains `aria-current="page"`; group `details` remain keyboard-operable; home returns to the audience index. TOC/permalinks use existing fragments. Section mates retain existing omission during a contents query; previous/next remain available in catalog order.
- **Mobile:** existing Contents trigger → drawer with home/search/groups → guide choice closes drawer and navigates; backdrop/close dismiss. Keep visible focus and translated accessible names. Verify closed drawer links cannot intercept keyboard navigation; any necessary modal-accessibility correction belongs in the existing controller.
- **Language:** existing locale switcher and request/user locale conventions remain. All chrome uses the appropriate `customer_docs` or `developer_docs` namespace; reuse existing paired en/zh-CN labels, no new copy required.
- **Empty directory:** `home_groups: []` shows its existing localized unavailable message in a neutral panel and retains overview prose/navigation. `nil` means no directory. Missing sources remain omitted by the repository.
- **Loading/error:** normal server navigation; no new skeleton. Unknown/missing slug retains existing localized 404/recovery link. Permission failures remain governed by existing admin/tenant/platform guards. The reader issues no vendor request or documentation write; validation/provider errors remain explained by guide content. Primary action is opening a guide; secondary actions are search, contents/TOC, home, section, sequence, and full-size image links.

## 6. Component reuse and implementation boundaries

| Piece | Implementation contract |
| --- | --- |
| Reader layout and typography | Extend `DeveloperDocs::ReaderComponent` and its ERB; retain existing props, add optional `renders_one :header` slot, central-strip wrapper, and static Tailwind descendant utility strings |
| Central header | Both show views supply existing `AdminPageComponent` to the header slot with their crumbs/title/summary, `wrap_title: true`, `width: "full"`; reader-owned wrapper utilities set header typography/spacing. Its width declaration still supplies the shell container. Compose existing `BreadcrumbsComponent`; no shared AdminPage API change is needed |
| Grouped hub | Refine existing `CustomerDocs::HomeGuidesComponent` for both translation scopes; one existing `CardComponent` per group; no new public props |
| Contents | Refine existing `DeveloperDocs::ContentsNavComponent` font, spacing, wrapping, contrast; retain current group-open logic |
| TOC / separators / continuation | Reader template + Tailwind border utilities and native `details`/anchors |
| Drawer | Existing `developer-docs-nav` Stimulus targets/actions and localized values; no additional controller |
| Rich Markdown | Move reader-specific rules at the end of `app/assets/tailwind/application.css` into reader-owned Tailwind utilities; retain `.docs-page`, `.customer-doc`, `.developer-doc` as semantic/test hooks, not styling implementations |

No new component is necessary. Preserve the extensive working-tree implementation and treat earlier October 8 design records as historical where the current source differs. Implementation must update `doc/reference/{en,zh-CN}/customer-documentation.md` and `overview.md` together with the new reader geometry, typography, slot contract, and verification guidance.

## 7. Acceptance evidence

QA covers hub + representative H2/H3 article, both audiences and locales, at 320/390/768/1024/1440px. Check measured font sizes/leading, a single H1 aligned with bounded article prose, complete hub under matching and no-result contents queries, active navigation, one visible article TOC, home/section/previous-next, keyboard and drawer behavior, local table/code scrolling, uncropped figures, and no document/main horizontal overflow. Include expanded/collapsed developer app sidebar, 200% zoom, and resizing across both container thresholds. Extend the existing e2e spec rather than creating a second harness. The implementation plan specifies focused checks and lane ownership.

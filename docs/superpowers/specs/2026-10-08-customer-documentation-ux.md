# Customer documentation — UX specification

Date: 2026-10-08  
Status: Ready for frontend  
Audience: Logged-in customer admins and the platform owner  
Navigation area: Admin → Help → Documentation

## 1. Design basis

Provide task-oriented, bilingual guides inside the backend. Customers enter through Help, browse or search the guide catalog, read an article, and move between related guides without leaving their customer context.

The agreed routes are:

- `/:customer_id/admin/help/docs` — documentation home, rendering the customer catalog's home guide.
- `/:customer_id/admin/help/docs/:slug` — one allow-listed customer guide.

### shadcn consultation

The shadcn skill and MCP tools are unavailable in this environment. Official shadcn documentation was consulted before specifying the surface:

- [Sidebar](https://ui.shadcn.com/docs/components/sidebar): grouped navigation, independently scrollable contents, active links, and mobile offcanvas composition.
- [Dropdown Menu](https://ui.shadcn.com/docs/components/dropdown-menu): button-triggered menus with grouped, icon-supported items.

Apply those composition patterns through the existing Rails ViewComponents, Tailwind tokens, and Stimulus behavior. `DeveloperDocs::ReaderComponent` already supplies the matching responsive reading layout; `HelpMenuComponent` already supplies the entry menu.

## 2. Surface inventory

| Surface | Navigation area | URL / location | Audience |
| --- | --- | --- | --- |
| Documentation item in Help | admin | Existing backend Help dropdown | `admin_or_owner?` user with a customer ID |
| Documentation home | admin | `/:customer_id/admin/help/docs` | Same-tenant admin; owner |
| Guide reader | admin | `/:customer_id/admin/help/docs/:slug` | Same-tenant admin; owner |
| Search state | admin | Current documentation route with `?q=…` | Same as reader |
| Mobile contents drawer | admin | Overlay within home / reader | Same as reader |
| Missing guide | admin | Unknown guide URL; HTTP 404 | Authorized reader |

This is a top-level admin Help surface, not a module configuration screen. It uses the normal dashboard shell and `dashboard_menu_item :home`, allowing the documentation's own contents rail to be the navigation beside the article.

### Access contract

- An authenticated admin may read guides only under their own customer ID.
- The reserved owner may read guides across customer contexts. Links retain the customer ID in the current URL, including when the owner visits another customer.
- Anonymous users, members, and cross-tenant admins do not receive documentation content. Direct requests must pass the controller-level admin/owner and tenant guards before catalog lookup or rendering.
- The Help item is shown only when both `user.admin_or_owner?` and a customer ID are present. Missing either condition hides the item; hiding is not the authorization mechanism.

## 3. Layout specifications

### 3.1 Help entry

Keep the existing Help icon trigger, dropdown header, menu spacing, and documentation book icon. The documentation row occupies its existing position after the support actions that are available to that user.

```text
Help
  [available support actions]
  [book icon] Documentation
              Guides & how-tos
```

- Use the existing `chrome.help_menu.docs.label` and `.sub` translations.
- Point the row to `/:customer_id/admin/help/docs` in the same tab.
- Activating it closes Help through the existing `help-menu#close` action and follows the internal link.
- Remove the external-link arrow and new-tab treatment from this row: its appearance must match internal navigation.
- The dropdown remains right-aligned, `w-80`, and constrained by `max-w-[calc(100vw-2rem)]`.
- No loading or empty state is needed for this static entry. The destination handles server-rendered success and error states.

### 3.2 Documentation home and guide reader

Wrap the reader with `AdminPageComponent`, `width: "full"`. Supply the localized guide title and summary to its header, with no header action buttons. Use Documentation as the root breadcrumb, linked to the current customer's documentation home; append the current guide title for non-home guides. Do not add a Help breadcrumb that points to a nonexistent Help landing page.

Desktop (`xl`, 1280px and above):

```text
Existing dashboard chrome / customer context / Help
Documentation > Current guide
Guide title
Short outcome-oriented summary

+----------------------+--------------------------------+--------------------+
| Contents             | Article                        | On this page       |
| [Search guides     ] | Intro / steps / helpful notes  | Heading links      |
|                      |                                |                    |
| Group label          | Section heading                | Section heading    |
|   Guide              | Content                        | Nested heading     |
| > Current guide      |                                |                    |
|   Guide              | [Previous]        [Next]       |                    |
+----------------------+--------------------------------+--------------------+
```

| Region | Data contract | Presentation |
| --- | --- | --- |
| Header | `page.title`, `page.summary` | Existing AdminPage title and description typography; wrapping summary |
| Breadcrumbs | Customer documentation home path; `page.title`, home-slug comparison | Existing `BreadcrumbsComponent` through AdminPage |
| Left contents | `page.groups`; `group.key`; `entry.title`, `.path`, `.active` | Localized group labels, ordered guide links, active guide tint and `aria-current="page"` |
| Search | `page.search_path`, `page.query` | GET form; search input, 80-character limit; desktop clear link when query exists |
| Article | `page.html` | Existing reader typography, links, lists, tables, and callouts |
| Section navigation | `page.headings` with `text`, `id`, `level` | Same-page anchors; deeper headings indented |
| Reading sequence | `page.previous_page`, `page.next_page`, each with `title`, `path` | Existing bottom cards; absent neighbors omitted |

The reader consumes a page-shaped object; there is no customer-editable documentation model or record form. Localized Markdown front matter supplies the titles and summaries. The customer catalog supplies ordered groups and the guide sequence. The renderer supplies HTML and heading anchors. Every article, catalog, breadcrumb, search, and neighboring-guide path resolves within the customer Help documentation routes.

#### Responsive regions

- **Below `lg` (1024px):** article uses the available width. A floating Contents button opens the existing left drawer. Same-page headings appear in a native, initially collapsed `details` panel above the article when headings exist.
- **`lg` to below `xl`:** persistent 16rem contents rail and flexible article, separated by `gap-10`. Same-page headings still use the inline `details` panel.
- **`xl` and above:** 16rem contents rail, `minmax(0,1fr)` article, and 14rem section rail. Heading links move to the right rail.
- Desktop rails retain `sticky top-24`, bounded viewport height, and independent `overflow-y-auto` scrolling.
- Full-width shell padding remains `px-3 sm:px-4 lg:px-8`. The article retains `min-w-0`; long content must not widen the page. Keep customer guide tables short and avoid implementation-oriented code listings.
- Previous/next cards stack on small screens and use `sm:grid-cols-2` from 640px.

#### Actions and states

- **Primary:** select a guide in Contents, or submit search with Enter / the native search submit action.
- **Secondary:** follow section anchors, use previous/next cards, clear search on desktop, or return through Documentation in the breadcrumb.
- **Destructive:** none.
- **Normal loading:** Rails navigation renders the complete article and catalog together. Retain the existing page during navigation; no new skeleton, asynchronous search, or client-side loading mode.
- **No search matches:** replace the contents groups with the localized dashed-border empty message. Keep the current article, section links, and reading sequence visible. This is not a 404.
- **No headings:** omit both the inline section panel and the right-side links.
- **First/last guide:** omit the unavailable previous/next card while retaining the reader's existing alignment.
- **Missing guide/source:** use the localized 404 surface described below, rather than an empty article or a raw slug as the title.

### 3.3 Mobile contents drawer

Use the existing `developer-docs-nav` mounting element, targets, and action wiring.

```text
+---------------------------+      Dimmed article
| Contents              [×] |      underneath
|---------------------------|
| [Search guides          ] |
| Group                     |
|   Guide                   |
| > Current guide           |
|   Guide                   |
| ... scrollable ...        |
+---------------------------+
```

- Floating trigger: existing fixed bottom-right rounded button, visible below `lg`.
- Drawer: left edge, `w-80 max-w-[85vw]`, full viewport height, `z-50`; backdrop `z-40`.
- Header: localized Contents label and icon-only close button with localized accessible label.
- Body: mobile GET search and the same filtered groups as desktop, independently scrollable.
- Open locks body scrolling. Close button, backdrop activation, and guide selection dismiss the drawer; selecting a guide then navigates to that guide.
- Search remains server-submitted. Its mobile field has no separate clear icon in the existing reader; erase the query and submit to restore all groups. After navigation, reopen Contents to review results.
- Drawer behavior is the current controller contract. Escape handling, focus trapping, and focus restoration are not supplied by that controller and must not be described as implemented interactions.

### 3.4 Missing guide

An authorized request for an unknown slug, or an unavailable guide source, returns HTTP 404 in the normal admin shell. Reuse `AdminPageComponent`, `width: "full"`, with the Documentation breadcrumb, translated missing title, and translated description. The breadcrumb provides recovery to the documentation home.

The screen shows neither a partial article nor a filesystem/error detail. Authentication and permission failures use the existing application guard responses; they do not become missing-guide messages.

## 4. Content and bilingual labels

### Guide language

- Every customer guide has English and Simplified Chinese versions with matching intent, sections, examples, and links.
- Titles describe a customer task or outcome. Examples of the tone: **Get started / 开始使用**, **Manage your records / 管理记录**, **Set up payments / 配置支付**, **Send an email campaign / 发送邮件营销活动**. These examples illustrate wording, not a mandatory inventory of new module capabilities.
- Group guides by customer goals, with localized catalog group keys. Avoid developer-reference categories such as implementation, runtime, code generators, and platform operations.
- Use practical introductions, prerequisites, numbered steps, expected results, and troubleshooting where useful. Link to other customer guides for related tasks.
- Customer-facing headings, summaries, navigation, search results, and article prose must not expose developer implementation details or the word “flowchart”. The existing developer catalog must not become the customer contents list or search corpus.
- Locale follows the existing application locale selection. Keep the same slug and customer context when changing locale. Both locale sources are required at release; a fallback is not a substitute for the Chinese guide.

### Translation namespace contract

Parameterize `DeveloperDocs::ReaderComponent` with `translation_namespace`, defaulting to `"developer_docs"`. The customer reader passes `"customer_docs"`. Resolve all reader labels at render time, including both desktop and mobile copies, group labels, aria labels, titles, and the server-passed Stimulus label values.

Customer translations belong in `config/locales/customer_docs.en.yml` and `config/locales/customer_docs.zh-CN.yml`, with identical key sets and interpolation variables. Renderer callout and anchor labels also use the customer namespace. Reuse the existing Help-row wording from `chrome`.

| Customer key suffix | English | Simplified Chinese |
| --- | --- | --- |
| `breadcrumb.documentation` | Documentation | 文档 |
| `contents` | Contents | 目录 |
| `nav_open` | Open contents | 打开目录 |
| `nav_close` | Close contents | 关闭目录 |
| `on_this_page` | On this page | 本页内容 |
| `search_placeholder` | Search guides | 搜索指南 |
| `search_submit` | Search | 搜索 |
| `search_clear` | Clear search | 清除搜索 |
| `search_empty` | No guides match that search. | 没有匹配的指南。 |
| `previous` | Previous | 上一篇 |
| `next` | Next | 下一篇 |
| `anchor` | Link to this section | 本节链接 |
| `missing_title` | Page not found | 未找到页面 |
| `missing_body` | That guide does not exist. | 该指南不存在。 |
| `callouts.attention` | Important | 重要提示 |
| `callouts.note` | Note | 说明 |

`customer_docs.groups.<key>` must cover every customer catalog group in both locales. Guide front matter and Markdown are the localized content source; UI strings are translated through I18n, never embedded as Ruby or ERB literals or translated at constant load time.

## 5. Interaction flows

### Enter from Help

1. Start on any backend admin page under customer `C`.
2. Activate Help, then Documentation.
3. Help closes and the same tab opens `/C/admin/help/docs`.
4. The customer home guide renders with the complete catalog; the home guide is active.

### Browse and continue reading

1. Start at `/C/admin/help/docs` or a guide URL.
2. Select a guide from Contents; on mobile first open the drawer.
3. Navigate to `/C/admin/help/docs/<slug>`; update title, summary, active item, article, headings, and neighbors together.
4. Select a section link to navigate to `#<heading-id>` on the same guide.
5. Select Previous or Next to move through the customer catalog's complete ordered guide sequence.

### Find a task

1. Start at a documentation URL and type into Search guides.
2. Submit the GET form to `page.search_path` with `q`.
3. Reuse existing catalog-search behavior: trim the query, limit it to 80 characters, and perform a case-insensitive substring match against localized guide title, summary, and body.
4. Show only matching guide links, grouped in catalog order; omit empty groups. Keep the current guide article visible even if it does not match.
5. Select a result to open its guide. Existing reader entry links navigate to the canonical guide URL without retaining `q`; previous/next remains based on the complete catalog, not the filtered set.
6. If there are no results, show the localized contents message. Clear via the desktop clear link or erase and resubmit the mobile query.

Search filters the catalog; it is not an article highlighter, live autocomplete, separate results page, or new JavaScript interaction.

### Open a bookmark or recover from a bad link

1. Request `/C/admin/help/docs/<slug>` directly.
2. Run authentication, role, and tenant checks.
3. An authorized, known slug opens its localized guide. An authorized, unknown slug produces the localized HTTP 404 screen.
4. Select the Documentation breadcrumb to return to `/C/admin/help/docs`.
5. Anonymous requests follow the existing sign-in handling; members and cross-tenant admins receive the existing access-denied response without any guide content. Owner requests retain the requested customer context.

There are no write validations or external documentation/vendor requests in these reading flows. Normal application error handling covers infrastructure failures.

## 6. Component reuse map

| Piece | Existing component / service | Required integration |
| --- | --- | --- |
| Backend chrome and customer context | `ShellComponent` via dashboard layout | Set `dashboard_menu_item :home` on the customer docs controller |
| Help Documentation row | `HelpMenuComponent` | Role/customer visibility predicate; internal same-tab destination; existing Help close action |
| Header, full-width container, missing screen | `AdminPageComponent` | `width: "full"`; customer-localized title/summary/breadcrumbs |
| Breadcrumb trail | `BreadcrumbsComponent` through AdminPage | Documentation home link and current guide title |
| Three reading regions, search forms, sequence cards, mobile drawer | `DeveloperDocs::ReaderComponent` | Existing `page:` contract plus `translation_namespace: "customer_docs"` |
| Drawer interaction | Existing `developer-docs-nav` Stimulus controller | Retain targets/actions; provide translated open/close values from customer namespace |
| Help interaction | Existing `help-menu` Stimulus controller | Existing toggle and close actions |
| Article rendering and catalog search | Existing `DeveloperDocs::Renderer` and repository search pattern | Customer catalog, content sources, label namespace, and customer Help link resolution |

No new ViewComponent or Stimulus controller is required. Backend implementation supplies a customer-specific catalog/repository integration with the reader's existing page contract; the design does not prescribe a new persistence schema. Existing developer-reader callers continue to receive `developer_docs` labels by default.

## 7. Tailwind, Stimulus, and accessibility notes

- Retain the reader's responsive grids, sticky rails, article utility classes, drawer widths, and transitions. Use existing `bg-surface`, `text-text-primary`, `text-text-secondary`, `text-text-muted`, `border-border-subtle`, and accent tokens.
- Preserve active-guide styling: `bg-accent-subtle font-medium text-accent-text`; other links use `hover:bg-surface-hover` and `hover:text-text-primary`.
- Help uses the existing `ITEM_CLASSES`, `dropdown-panel`, `icon-button`, and icon tile styling.
- Retain labelled search fields with unique desktop/mobile IDs, native links, heading anchors, and native `details` / `summary`. Search is usable by keyboard submission; icons remain `aria-hidden` when their control has a text or accessible label.
- Preserve named navigation landmarks, `aria-current="page"`, translated close/open labels, and the drawer's existing dialog semantics.
- Stimulus contract remains `drawer` / `backdrop` targets; `openDrawer`, `closeDrawer`, and `navigate` actions; `openLabel` / `closeLabel` string values. Pass translated values from the component mount. No JavaScript changes are needed.

## 8. Acceptance and implementation handoff

- Help opens the internal Documentation route in the same tab for admins/owner with a customer ID; its row does not appear for anonymous users, members, or absent customer context.
- Both routes enforce logged-in admin/owner access and tenant scoping, including direct requests. The owner can read another customer's route; an admin cannot.
- Home, known guides, search, section links, and reading-sequence links retain the URL customer context and use the customer catalog.
- English and Simplified Chinese guides, front matter, reader labels, group labels, callouts, and missing-page messages are complete and consistent.
- Unknown slugs return an actual localized HTTP 404 after authorization.
- Mobile/tablet/desktop match the existing below-`lg`, `lg`, and `xl` reader behaviors without page-wide horizontal overflow.
- Search-empty state preserves the current article; catalog filtering and previous/next behavior match the reuse contract above.
- The default namespace still renders the existing developer reader correctly. Verify every label occurrence, including the mobile drawer and renderer labels, in both locales.
- Implementation should run focused component/request/content checks for Help visibility, namespace defaults, customer routes, role/tenant isolation, locale parity, search, and 404 behavior, plus browser checks for the responsive regions and mobile drawer.
- Any production source changes made during implementation must update the matching developer reference pages under both `doc/reference/en/` and `doc/reference/zh-CN/` in the same change.

This artifact is the UX handoff; no production code is part of this design deliverable.

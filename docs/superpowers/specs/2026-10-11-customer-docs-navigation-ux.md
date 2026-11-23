# Customer docs navigation — second focused refinement

- Date: 2026-10-11
- Status: READY_FOR_FRONTEND
- Plan: [customer docs navigation](../plans/2026-10-11-customer-docs-navigation.md)
- Audience: customer administrators and the owner in the URL customer's context; shared-reader regression surface: owner-only developer reference.
- Integration baseline: the current working tree, including the untracked contents component and existing reader/e2e work.

## 1. Brainstorm resolution — make the next guide obvious

The first October 11 pass established a bounded, readable article. This pass makes navigation between customer guides readily discoverable: **all customer groups are open, links use short task labels, and home/search remain in a fixed navigation header above the scrolling guide list**. Articles gain small previous/next links near the title. During search, an explicitly separated current-context block identifies the guide being read, even if it is absent from results.

### Findings and decisions

| Observed friction | Settled solution |
| --- | --- |
| `ContentsNavComponent#group_open?` opens only the active group outside search. Seven other customer groups can conceal the next task, including several single-guide groups. | Render the customer catalog as eight permanently expanded, labelled groups with ordinary lists. “Open all groups” is the presentation policy: no customer disclosure step or redundant one-item chevrons. Developer groups remain native collapsible `details`. |
| Front-matter titles are good article headings, but several occupy two or three rail lines. | Add `customer_docs.nav_labels.<slug>` in both locales. Use these concise task labels in contents, article breadcrumbs, search context, and top sequence links. Full titles remain article/home-directory/footer content and accessible descriptions. |
| Desktop rail scrolls its heading, home link, and search away; mobile scrolls home/search with the list. Search submit is visually hidden; mobile has no explicit clear link. | Translate shadcn's `SidebarHeader` / `SidebarContent` split into a bounded flex column. Header has a full-width outlined home link, input, full-width outlined **Search** button, and visible **Clear search** when a query is applied. Only the guide/results list scrolls. |
| Both show views and `ReaderComponent#current_group` derive context from filtered `page.groups`; `section_entries` is explicitly disabled by `q`. | Backend exposes **one unfiltered `Page.current_group`**. Use it for current guide/group context, article breadcrumbs, and same-group footer, independently of results. |
| Search can make a user appear to be “nowhere”, or introduce two active links when the current guide is also a result. | While searching, a pinned **Reading now** block is the only canonical current-page link in each contents surface. The result list is separately labelled **Search results** and never renders `aria-current="page"` or active styling. It still includes the current guide if it actually matches. |
| Reading sequence is available only after the article. | Add a light, compact sequence row below the header summary, before TOC/prose. Use existing catalog neighbors; customer labels need neighbor slugs. Keep full-title footer sequence links. |
| The drawer focuses its close control but does not reveal the active item in a long list. | Keep close-control initial focus and the existing modal behavior. On opening, reveal the active guide within **only the drawer list**; during search the current context is already pinned, so start results at the top. |

These decisions supersede only the first pass's customer collapse policy, whole-rail scrolling, hidden search submit, query-dependent section omission, and long navigation labels. They retain its typography, article measure, grouped complete hub, TOC, rich-content bounds, and app-shell scroll owner.

### shadcn consultation, before design

The shadcn skill and MCP tools are unavailable. Consulted official documentation with `webfetch` on 2026-10-11:

- [Sidebar](https://ui.shadcn.com/docs/components/sidebar): fixed header, scrolling content, labelled groups, menu items, active styling; optional collapsible groups for the larger developer catalog.
- [Input Group](https://ui.shadcn.com/docs/components/base/input-group): input/addon/action composition and input-first DOM order. Use a search-icon addon and a block-end submit button so a 224px rail keeps a usable input.
- [Item](https://ui.shadcn.com/docs/components/base/item): small linked items grouped into lists; light separators rather than a card around every guide.

Use the outline Button, InputGroup, SidebarMenu/Item, Separator, and restrained Card vocabulary through **ViewComponent + Tailwind + native HTML + Stimulus**. No React installation or custom CSS is needed. Existing `ButtonComponent(variant: :secondary)` is the outlined-button starting point; explicit reader utilities establish the required type/target size. Existing `CardComponent` continues to own hub panels.

Inputs reviewed: `.cursor/agents/anysys-ux-designer.md`; October 11 reader UX/plan; October 8 customer polish UX/plan and screenshot handoff; current reader, contents, home directory, controllers/views, repositories/catalogs, locales, shell/breadcrumb/button/card components, component/repository/browser/JS specs, and runtime reference pages. The older `/tmp/opencode/customer-docs-contents-en-mobile.png` illustrates long-label density but predates the current eight-group catalog; current source governs. No new browser capture or implementation validation is claimed here.

## 2. Surface inventory

| Surface | Navigation area | URL | Refinement |
| --- | --- | --- | --- |
| Customer guide home / explicit overview | admin → Help → Documentation | `/:cid/admin/help/docs`, `/docs/overview` | All customer contents groups visible; pinned search/home; complete grouped directory preserved; group anchors for contextual navigation |
| Customer article | admin → Help → Documentation | `/:cid/admin/help/docs/:slug` | Short-label contents/breadcrumbs, persistent current context and same-group footer, top compact sequence |
| Customer contents drawer | same admin parent | Existing drawer on either route | Fixed control region, independently scrolling list, current-item reveal, visible submit/clear/recovery |
| Developer hub/article and drawer | admin → Maintenance → Platform → Developer reference | `/81721200/admin/maintenance/platform/developer_docs[/:slug]` | Shared fixed controls, context/recovery and sequence behavior; preserve collapsible larger catalog and existing owner gate |

Primary action: open another guide. Secondary actions: search, clear, guide home, section/TOC links, previous/next, existing screenshot links. There are no destructive actions.

## 3. Layout and exact geometry

```text
DESKTOP, unchanged horizontal reader budget
┌─ CONTENTS: 224px ────┬─ CENTRAL: max 704px ───────────┬─ TOC: 160px ─┐
│ Contents            │ All guides / Content / Forms  │ On this page │
│ [⌂ All guides     ] │ Full article title            │ H2 / H3      │
│ [⌕ Search guides  ] │ Outcome summary               │              │
│ [  Search         ] │ ← Previous: Records           │              │
│ Clear search        │                Next: Website →│              │
│ Reading now         │ ───────────────────────────── │              │
│ Content / Forms ●   │ inline TOC when appropriate   │              │
├─ light separator ───┤ article                       │              │
│ Search results      │                               │              │
│ OR unfiltered list  │ More in this section          │              │
│ Home                │ Full-title same-group links   │              │
│   Guide overview    │ Full-title Previous / Next    │              │
│   Get started       │                               │              │
│ Communication       │                               │              │
│   Send email        │                               │              │
│   Send SMS       ↕  │                               │              │
└─ only list scrolls ─┴───────────────────────────────┴──────────────┘

MOBILE / narrow reader (320px preferred drawer, capped at 85vw)
┌─ Contents ───────── × ┐
│ [⌂ All guides       ]│  header/controls do not scroll
│ [⌕ Search guides    ]│
│ [  Search           ]│
│ Clear search         │  when an applied query exists
│ Reading now          │  only during search
│ Content / Forms ●    │
├──────────────────────┤
│ labelled groups      │
│   short task links   │  only this region scrolls
│ active item revealed │  close control retains initial focus
│                    ↕ │
└──────────────────────┘
```

### Retained reader geometry

- Reader cap **1200px**, center cap **704px**, contents **224px**, heading rail **160px**, gaps **32px**. W is measured reader width after shell gutters/app-sidebar allocation.
- W < **896px**: one-column reader and drawer; 896 ≤ W < **1152px**: contents + center; W ≥ 1152px: add heading rail on eligible articles. Hubs never reserve the heading rail. Keep the existing 640px central-container breakpoint for hub/footer grids.
- Preserve the first pass's explicit typography: H1 28/34 → 32/40, H2 22/30 → 24/32, H3 18/26 → 20/28, prose 16/28 → 17/30 at W=640px. Navigation **14/20**; search input **16/24**. Full article titles wrap; rich content scrolls locally.
- Desktop sticky panel: 24px inset, definite height `calc(100dvh - 16rem)`, `min-h-0 flex flex-col`; existing right separator/padding included in its 224px width. Header is `shrink-0`; list is `min-h-0 flex-1 overflow-y-auto overscroll-contain`. Remove overflow from the panel/header themselves. Give list 12px top spacing, 8px bottom inset.
- Short-height escape: at viewport height **below 640px**, use the existing single-column/drawer mode even when W is wide. Apply this complementary height condition to reader grid, both desktop rails, inline TOC, trigger, drawer and backdrop. This prevents pinned controls from exhausting the desktop list. At H ≥640px the prior horizontal modes are unchanged. The controller already uses actual trigger visibility, so no new JS breakpoint is required.
- Drawer: `h-dvh`, preferred 320px/cap 85vw, existing z-index/backdrop/transition. Combine title/close and all controls into one `shrink-0` header with 16px insets, safe-area top inset through a Tailwind utility; list fills the remainder with `min-h-0 overflow-y-auto overscroll-contain`, 16px horizontal/bottom insets and safe-area bottom allowance. Keep drawer/background modal scroll ownership.

### Fixed navigation header

Order in both surfaces: **Contents label → full-width home anchor → search input → full-width Search submit → Clear search (conditional) → Reading now (conditional) → separator**. Mobile adds the existing close button alongside Contents. Use 8px between home/input/submit; 12px before the content separator. No essential control is icon-only except the established translated close control.

- Home/search submit: minimum **44px** high, full width, 8px radius, 1px `border-border-subtle`, `bg-surface`, `text-text-primary`; leading home/search icon 16px, decorative; neutral hover and accent focus ring. Home is a native anchor; Search is `type="submit"`.
- Input: `input-field`, 44px high, no shadow, full width, `min-w-0`, icon in noninteractive leading addon. Input appears before addon/actions in DOM. Keep separate desktop/mobile IDs, `maxlength=80`, `autocomplete=off`, localized label and placeholder. Do not squeeze an icon-only submit into the input's trailing edge.
- Clear: visible text **Clear search**, native query-free link to `page.search_path`, 32px minimum desktop / 44px mobile; do not rely on browser search-input clear affordances. It is conditional on the **applied** normalized query; draft edits remain normal native form input.
- Header treatment: quiet neutral surface and thin separator; use `text-text-secondary` for Contents and primary text for actionable controls. Avoid large filled accent slabs. Reading-now context uses a small `bg-canvas-elevated rounded-lg` region, 8px inset, localized 14/20 label and a wrapping breadcrumb. Group and guide text are each at most two visible lines in this narrow context; the guide link's full title is available to assistive technology and as the page H1.

### Guide list, context and full titles

- Customer groups are static headings + `ul/li/a`, all published entries discoverable by scrolling, without expanding anything. Eight labels keep their catalog order and existing top-menu wording. Group separation 12px; heading 14/20 semibold, 8px horizontal inset; entry gap 2px. No uppercase/tracking.
- Customer normal rows: short task label, wrapping if needed (no forced ellipsis), 32px minimum desktop / 44px mobile, 8px horizontal padding, 6px radius. Active row has accent-subtle background, accent text, semibold, and 2px leading accent marker. Neutral rows use secondary text and neutral hover. Focus is visible.
- Developer groups retain native `details/summary`, current group open by default and other groups closed; search opens matching groups. Keep full front-matter labels for developer links; do not create a second 36-entry translation map.
- With `q`: pin **Reading now** above the separator; below it label the list **Search results**. Render only real matches from `page.groups`. Customer results show short task label plus the full front-matter title as secondary 14/20 text when different; developer results show full title. No result has active/current styling or `aria-current`, even if its slug equals the article slug.
- Without `q`: no pinned context duplication. The current normal contents item is the single `aria-current="page"` link in that surface. With `q`: the pinned current guide is the single such link, whether results include it or exclude it. Desktop/mobile may each have one in the DOM; scope uniqueness to the visible desktop rail or open dialog. Closed drawer stays inert/hidden. H1, breadcrumbs and home button do not add current-page anchors.
- Full-title accessibility: short-label links use a uniquely scoped `aria-describedby` full-title description (desktop/mobile/context/top IDs cannot collide). Use `<audience>-doc-nav-<surface>-<slug>-title` for list descriptions, `<audience>-doc-context-<surface>-<slug>-title` for pinned context, and `<audience>-doc-top-<previous|next>-title` for top sequence. Keep the short visible label in the accessible name; do not replace it with an unrelated `aria-label`. Full titles are also visible in article H1, unchanged complete hub rows, search results, same-group footer and bottom sequence. No essential information depends on hover/tooltips.

### Concise contextual breadcrumbs

Customer article header: existing Help context → **All guides** (index link) → **group** (index plus group fragment) → **short current label** (plain final crumb). Developer keeps Maintenance/reference context and full title but gets the unfiltered group. Resolve groups from `page.current_group`, never filtered results.

During search, Reading now is a separate labelled context region: **group** (index/group fragment) `/` **current label** (current entry's query-free repository path, `aria-current="page"`). Selecting the current label clears search while staying on the guide. This is context, not a synthetic match.

Add a stable ID to each existing hub group panel: `customer-doc-guide-group-<key>` / `developer-doc-guide-group-<key>`, with the existing heading scroll offset. Generate the fragment from the catalog group key, attach it to the view-supplied `home_path`, and preserve customer locale query before the fragment. A customer `home` group targets the existing home panel (its directory includes getting-started). No group route or extra page is required. If no current group exists, omit only the group crumb; current slug/title/search recovery remain usable.

### Top article sequence and footer

- Top sequence appears on **non-home articles**, directly after header summary and before inline TOC/Markdown, with 12px top gap, 16px bottom gap, thin bottom separator. Render it inside the reader-owned header wrapper after the supplied header slot, adjusting that article header's trailing spacing so the existing `mb-8` does not add a second 32px gap before the sequence. Standalone calls without a header slot can render it before TOC/prose. It is not sticky and does not intrude into article prose.
- Two equal `minmax(0,1fr)` cells, 12px gap; links minimum 44px high, 14/20. Previous aligns start, Next aligns end. Customer content: direction label + short task label, e.g. **Previous: Find records** / **Next: Publish website**. At 320px allow two or more natural text lines, never a horizontal scroller. Developer uses full neighbor titles, wrapped without clamping. Icons are decorative. No reduced-font microtext.
- Name this nav with new localized `sequence_label` (**Reading order**); keep separate `data-docs-top-sequence` / `data-docs-footer-sequence` hooks for scoped checks. Accessible description supplies the full neighbor title where a short label is shown. Missing endpoints render no disabled link or placeholder element; a sole next link aligns end. Hubs keep their existing footer sequence only.
- Top and footer link to **identical catalog neighbors**, not neighbors within results, and clear `q`. Customer paths preserve URL tenant and effective locale. Developer links keep their existing query-free convention.
- Footer **More in this section** uses the complete unfiltered current group, excluding only the active entry, even during search. Preserve catalog order, full titles, light separator and existing stacked/responsive footer sequence cards. Single-guide groups omit the empty same-group block.

## 4. Copy and locale contract

Frontend owns both locale files per namespace. Translate at render time; keep keys stable, no load-time translated constants. Reuse `contents`, `home_link`, `search_placeholder`, `search_submit`, `search_clear`, `search_empty`, `previous`, `next`, `more_in_section`, `nav_open`, `nav_close` and existing group labels.

Add paired keys under **both** `customer_docs` and `developer_docs`:

| Key | en | zh-CN |
| --- | --- | --- |
| `search_results` | Search results | 搜索结果 |
| `current_context` | Reading now | 当前阅读 |
| `sequence_label` | Reading order | 阅读顺序 |
| `sequence_previous` | Previous: %{title} | 上一篇：%{title} (customer), 上一页：%{title} (developer) |
| `sequence_next` | Next: %{title} | 下一篇：%{title} (customer), 下一页：%{title} (developer) |

Use `%{title}` interpolation for top link wording. Add the following **customer-only** map under `customer_docs.nav_labels`; hyphenated slug keys are literal YAML keys:

| Slug | en | zh-CN |
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

Full titles/summaries remain localized Markdown metadata, not copied into this map. Customer short-label lookup has a render-time fallback to the supplied full title; QA verifies every current catalog slug has both keys, so fallback does not hide a missing publication key. Shared reader callers may use other translation scopes without acquiring customer labels. Reuse a local reader navigation-label helper between reader/contents/views; avoid independent maps or URL-parsing heuristics.

## 5. Minimal backend handoff and data map

**Proposed API, fixed for parallel work:**

1. Add `current_group: Group | nil` to `DeveloperDocs::Repository::Page`. It contains only the unfiltered group that owns the current slug, with the existing `Entry(slug, title, path, active)` entries in catalog order. Use existing locale fallback and omit unavailable sources as today. One active entry corresponds to `page.slug` when a current group exists.
2. Keep `Page.groups` as the genuine filtered results; do not append the current guide, its siblings or a special group to results.
3. Extend `Repository::Link` from `(title, path)` to **`(slug, title, path)`** for previous/next. The slug lets the frontend resolve the task-label map without parsing a URL or shipping a second neighbor lookup.

Build unfiltered groups once during `page`, select the current group from that metadata, and filter the same entries with existing localized title/summary/body matching and normalized 80-character query. Use request-local `source_for` metadata; render the requested article only. Expose no `all_groups`, duplicate `Page`, repository instance, additional full directory prop, or copied HTML/body to the reader. Customer repository inherits the contract; home `guide_groups` and developer `hub_groups` stay independently complete.

Current-group and sequence destinations are repository-generated and query-free (remove symbol/string `q` from navigation route options); preserve other established routing options, especially customer locale. `page.search_path` remains the current query-free index/article path supplied by its controller. Repository matching remains title/summary/body; this pass does not introduce a second label-based search engine. No renderer/cache version change is needed: these are request-local metadata/component changes.

| Region | Data |
| --- | --- |
| Main heading/summary/prose/TOC | Existing `page.title`, `summary`, `html`, `headings` |
| Normal contents / search results | `page.groups`, `query`; each entry's slug/title/path/active |
| Current context / article group crumb | `page.current_group`, current active entry; `page.slug/title` fallback; view `home_path` |
| Same-group footer | `page.current_group.entries.reject(&:active)` |
| Top + bottom sequence | `page.previous_page` / `next_page`: slug/title/path |
| Full hub directory | Existing complete `home_groups`, guide slug/title/summary/path; panel IDs from group key |
| Search/clear/recovery | Existing `page.search_path`, customer `locale` hidden fields |

## 6. Interaction and state flows

1. **Find another task:** `/C/admin/help/docs/forms?locale=L` → see Content's short current label and all other customer group links → select Send email → existing `/C/admin/help/docs/email?locale=L`. H1 supplies the full task title. No expand click is required.
2. **Search excluding the current guide:** same article → type query → click visible Search (Enter also works) → same slug with `q`; article, heading navigation, current group breadcrumb, Reading-now link, same-group footer and catalog sequence remain. Only results filter. A current guide that matches is displayed as an ordinary result, without duplicate active semantics.
3. **Zero matches:** results area contains existing localized `search_empty` in a small neutral outlined region plus visible **Clear search** recovery link to `page.search_path`. Pinned home/search/clear/current context remain. No synthetic guide is counted as a match. Clear returns to the same article/index and effective customer locale with `q` removed. Home goes to the complete directory. No-result copy is server-rendered, not an assertive live alert.
4. **Group navigation:** click group crumb in article or Reading-now context → query-free audience home with group fragment → existing group panel is in view. Directory stays complete; no special search state is imposed.
5. **Continue reading:** top Next → next published catalog guide, no `q` → Previous returns to the same predecessor. Footer targets are identical; unavailable sources continue to be skipped. On the final guide only Previous appears; hubs do not gain top sequence.
6. **Open mobile contents:** article → Contents trigger → modal opens, close button receives initial focus with `preventScroll`, active customer item is revealed in the list (developer owning `details` opens first if manually closed). While searching, current context remains in header and results start at their top. List scrolling never moves home/search/close/current context. Search submission follows native server navigation and the next page starts with the drawer closed; reopen shows the preserved context. Clear/current/home/guide anchors close through existing navigate action.
7. **Keyboard and resize:** retain Tab/Shift+Tab containment, Escape/backdrop/close focus return, disabled/closed-details exclusion, inert/aria-hidden closed drawer, scroll restoration, resize/disconnect cleanup. Opening reveals context without stealing focus from close or scrolling `#main-content`. Changing to the desktop mode closes the modal using actual trigger visibility. No new keyboard shortcut or persistence storage is introduced.

Normal loading is server navigation; no extra skeleton or client search state. Missing/unavailable sources use existing localized 404/recovery; a missing current group omits its crumb/same-group links without hiding article/navigation. Empty directory uses existing unavailable copy. Search has no validation beyond existing normalization/maxlength. Permission errors use existing admin/tenant/platform guards. No vendor request occurs; guide procedures continue to explain external task failures.

## 7. Component reuse and implementation boundaries

| Piece | Component / contract |
| --- | --- |
| Reader geometry, header/content split, search/context, sequence/footer | Refine `DeveloperDocs::ReaderComponent` Ruby/ERB. Keep header slot and current props; `current_group` now delegates to the new page field. |
| Normal groups / real results / current-item marker | Refine `DeveloperDocs::ContentsNavComponent`. Add `surface: :desktop` (`:mobile` for drawer) to scope full-title description IDs; retain `navigate:`. Customer presentation selected by translation scope; developer stays collapsible. |
| Shared short-label lookup | Small new `DeveloperDocs::NavigationHelper` module in `app/helpers/developer_docs/navigation_helper.rb`, used by reader/contents/views: `docs_navigation_label(slug, title:, translation_scope:)`. I18n at call time; fallback full title. No state, query, routes, or duplicated slug map. |
| Article header / concise crumbs | Existing `AdminPageComponent` + `BreadcrumbsComponent` supplied by both show views; unfiltered group and customer short final crumb. |
| Group fragment target | Existing `CustomerDocs::HomeGuidesComponent` Ruby/ERB; add scoped group-panel IDs only, retain complete directory and full-title rows. |
| Outlined home/submit, quiet context/empty region | Existing `ButtonComponent` secondary variant / native anchors + reader-owned Tailwind; Separator via border utilities. Do not change global button/card APIs to achieve docs geometry. |
| Active-list reveal and modal lifecycle | Existing `developer-docs-nav` controller; add optional `drawerList` target and `[data-docs-current-guide]` marker contract. No JS-generated wording. |

Tailwind: existing color/focus tokens, `min-w-0`, explicit rem type, flex/header shrink behavior, `min-h-0`, `overflow-y-auto`, `overscroll-contain`, container queries plus complementary short-height variants. Keep `.docs-page`, article classes, `data-docs-reader-center` and existing drawer targets. Use new semantic `data-docs-nav-header`, `data-docs-nav-list`, current-guide and sequence hooks for meaningful scoped assertions. No production code is edited by this design artifact.

## 8. Acceptance evidence and docs handoff

QA demonstrates real discoverability and behavior, not Tailwind class-string equality: all 13 customer catalog entries across eight groups are rendered without disclosures; short labels and full-title descriptions work in both locales; developer default expansion remains limited to its current group. Search matching/nonmatching the current guide and zero results leaves context/footer/sequence intact with one current link per visible contents surface. Both search forms expose clickable submit and clear/recovery. Opening the drawer actually reveals a late-catalog active item while close retains focus; scrolling list leaves header controls stationary and article/main scroll unchanged.

Extend the existing browser spec with focused 390/1440 navigation flows and a 320px late-guide/short-height geometry check. Retain the existing 320/390/768/1024/1440px, both-locale, expanded/collapsed developer-sidebar, 200% effective reflow and rich-content checks; adapt assumptions about customer `details`, sequence nav selectors and filtered footer omission. The plan assigns backend, frontend, JS, QA and bilingual runtime docs to disjoint files.

Implementation must update `doc/reference/{en,zh-CN}/customer-documentation.md` and `overview.md`, plus `doc/customer/{en,zh-CN}/overview.md` (it currently instructs customers to expand groups). Document current-group/Link contracts, fixed controls, customer static groups versus developer collapse, labels/full-title accessibility, query-independent context/footer/top sequence, drawer reveal and focused verification. Preserve bilingual sections/examples/callouts and required H2s. This planning-only change adds the UX doc and plan; runtime behavior descriptions are updated when implementation lands.

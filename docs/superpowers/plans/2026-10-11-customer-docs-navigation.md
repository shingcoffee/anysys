# Customer docs navigation — focused implementation plan

- Date: 2026-10-11
- Status: Ready for coordinated implementation
- UX: [customer docs navigation UX](../specs/2026-10-11-customer-docs-navigation-ux.md)
- Outcome: customers can see and reach other guides without group expansion, use pinned search/home controls, and retain their reading context while searching.
- This file plans implementation; it does not claim production edits or passing tests.

## 1. Integration baseline, contracts and collision-free lanes

Read `git status --short` and the current diff before touching assigned files. The first reader pass already modifies components, repository/renderer, catalogs/controllers/views, locales, docs/specs and built assets; contents component and browser spec are currently untracked work. Preserve that working tree. This plan supersedes the earlier reader plan only for the navigation behaviors identified in the UX; keep its bounded layout/type/hub/rich-content work.

Freeze these contracts before parallel dispatch:

- `Page.current_group: Repository::Group | nil`, unfiltered owning group with existing `Entry(slug,title,path,active)` metadata; `Page.groups` remains real filtered results.
- `Repository::Link(slug,title,path)` for both catalog neighbors. Navigation paths drop symbol/string `q`; customer locale/URL tenant remains preserved.
- `ContentsNavComponent(surface: :desktop)` plus `:mobile`, retaining existing arguments; used for unique accessible-description IDs.
- Shared `docs_navigation_label(slug, title:, translation_scope:)` helper: customer I18n map, otherwise supplied full title.
- Markup hooks: `data-docs-nav-header`, `data-docs-nav-list`; mobile scrolling element also `data-developer-docs-nav-target="drawerList"`; **one** `[data-docs-current-guide]` anchor in each contents surface, normal active row without `q`, pinned context with `q`. Never place that marker or `aria-current` on search results.
- Sequence hooks: `data-docs-top-sequence`, `data-docs-footer-sequence`. Hub group IDs: `customer-doc-guide-group-<key>` / `developer-doc-guide-group-<key>`.

| Lane | Role | Exclusive write ownership |
| --- | --- | --- |
| Backend | `anysys-backend-developer` | `app/services/developer_docs/repository.rb`; `spec/services/developer_docs/repository_spec.rb`; `spec/services/customer_docs/repository_spec.rb` |
| Frontend + I18n | `anysys-frontend-developer` | `app/components/developer_docs/{reader_component,contents_nav_component}.{rb,html.erb}`; `app/helpers/developer_docs/navigation_helper.rb` (new); `app/components/customer_docs/home_guides_component.{rb,html.erb}`; `app/views/admin/help/docs/show.html.erb`; `app/views/admin/maintenance/platform/developer_docs/show.html.erb`; all four `config/locales/{customer_docs,developer_docs}.{en,zh-CN}.yml` |
| JavaScript + its unit tests | `anysys-frontend-developer` in a separately scoped JS task | `app/javascript/controllers/developer_docs_nav_controller.js`; `spec/javascript/controllers/developer_docs_nav_controller.test.js`. This writer does not edit ERB or Ruby. |
| QA + browser | `anysys-qa-engineer` | `spec/components/developer_docs/{reader_component,contents_nav_component}_spec.rb`; `spec/components/customer_docs/home_guides_component_spec.rb`; `spec/helpers/developer_docs/navigation_helper_spec.rb` (new); `spec/requests/admin/help/docs_spec.rb`; `spec/requests/admin/maintenance/platform/developer_docs_spec.rb`; `spec/e2e/documentation_reader.app.spec.js` |
| Bilingual runtime docs | `anysys-tech-lead`, dedicated docs task | `doc/reference/{en,zh-CN}/customer-documentation.md`; `doc/reference/{en,zh-CN}/overview.md`; `doc/customer/{en,zh-CN}/overview.md` |
| Release / verification | `anysys-release-engineer` | Generated `app/assets/builds/tailwind.css` through build command; test/screenshot output only. No manual asset-source edits. |
| Review | `anysys-tech-lead`, `anysys-code-reviewer` | Read-only convention/correctness review; fixes return to the owning lane. |

Dispatch backend, frontend, JS, QA scenario preparation and docs drafting in parallel against these interfaces. QA alone owns the two component specs whose `Page.new`/`Link.new` fixtures need new fields; backend must not update those files. JS owns its unit spec, QA owns the browser spec. Frontend alone owns locale files; docs requests copy changes through that lane. Review starts after docs writing completes if the same tech-lead role is reused. No two writers edit the same file.

Controllers, routes, catalogs, renderer/highlighter, shared shell/breadcrumb/button APIs and `app/assets/tailwind/application.css` require no changes for this slice. If a concrete integration issue expands scope, assign ownership explicitly before editing, rather than silently sharing a file. Human review handles commits.

## 2. Backend — keep current context independent of filtering

1. Extend `Repository::Page` with `current_group`; extend `Link` with `slug`. Populate both from allow-listed catalog/source metadata. Customer repository inherits this; no duplicate customer implementation or controller variable is necessary.
2. Assemble unfiltered groups once per page call, select the owning group, then filter the same entries with the existing normalized query/title/summary/body rule. Omit unavailable sources and empty result groups as today. Do not append the current entry to results or expose a complete second catalog on Page. Reuse request-local sources and render only the requested article.
3. Build contents/current-group/neighbor metadata paths with navigation route options excluding symbol/string `q`, preserving all other established options. Keep supplied `search_path`, locale fallback, catalog order/skip-missing neighbors, content caching and hub metadata behavior.
4. Add focused repository examples: a matching query excludes the current guide but returns another group; a query yields no results; current group still contains all available siblings and exactly one active entry; neighbor slug/title/path are unchanged by query; customer tenant/locale preserved, developer query-free convention preserved; missing sibling skipped; title/body/summary matching and 80-character normalization retained. Check the query-free contract with both `:q` and `"q"` route options without altering renderer semantics.
5. Run the two assigned repository specs and hand frontend/QA/docs a concise API result and sample metadata shape. No new repository/page/body copy goes to the frontend.

## 3. Frontend — visible task navigation and fixed controls

### Task A: labels, context and sequence

1. Add the customer `nav_labels` map exactly as specified in the UX, with all 13 slug keys in both locales. Add paired `search_results`, `current_context`, `sequence_label`, `sequence_previous`, `sequence_next` keys to both namespaces; interpolation variables remain identical. Existing wording is reused where keyed.
2. Implement the small helper in `app/helpers/developer_docs/navigation_helper.rb`, translating on every call with the provided full title as fallback; use it from views/reader/contents. No I18n values in constants and no neighbor slug extraction from paths.
3. `ReaderComponent#current_group` delegates to `page.current_group`. `section_entries` returns its inactive entries even when `q` is present. Both show views use this same unfiltered group. Customer header's last breadcrumb uses the short label; full H1/summary remain metadata. Link group crumbs to the view-supplied index + stable group fragment, preserving locale-before-fragment.
4. Give existing hub panels their scoped group IDs and scroll offset, retaining full titles/summaries and all complete directory entries. No new group route or group component.
5. On articles only, render compact top sequence inside the reader-owned header after the supplied slot and before TOC/prose (or directly before TOC when no slot exists), using neighbor slugs for customer labels and full titles for developer. Adjust only the article header's trailing gap to avoid adding its old 32px margin before this row. Two equal cells, 12px gap, 44px minimum link height, 14/20 type, natural wraps; missing endpoints have no placeholder DOM. Top and footer use identical hrefs independent of `q`. Keep full-title same-group and footer links and previous responsive footer grid. Add semantic hooks for test scoping.

### Task B: fixed header and scrolling contents

1. Split both contents surfaces into `shrink-0` header and `min-h-0 flex-1 overflow-y-auto overscroll-contain` list. Desktop parent has definite `calc(100dvh - 16rem)` height and 24px sticky inset; drawer uses `h-dvh` and safe-area padding. Only the list scrolls. Preserve existing horizontal dimensions, container thresholds, header slot/prose utilities, rich-content treatment and TOC/hub behavior.
2. Add the complementary short-height mode from UX: H <640px uses one column, inline article TOC and existing drawer/trigger, regardless of W. Apply the same height condition to grid and all rail/drawer/trigger/backdrop visibility variants, including the right rail. At H ≥640px keep W=896/1152 modes. Do not add a JS numeric breakpoint.
3. Header: Contents/title-close row, full-width outlined home anchor, 44px 16/24 input with leading decorative addon, full-width outlined visible Search submit, visible Clear search when applied query exists; separator. Preserve distinct field IDs, GET form action, maxlength/autocomplete, hidden customer locale fields and developer default omission. Native Enter submission remains.
4. During `q`, add pinned Reading-now group/current breadcrumb from the unfiltered group. Give its current-guide anchor `aria-current="page"` and marker; query-free current entry path clears search. Without a group, use `page.slug/title` and `page.search_path` fallback. Group link uses the index fragment. Without `q`, omit this block so the normal active contents item owns the marker/current semantics.
5. Customer list: static group headings and ordered native lists, with every published entry available by scrolling. Developer list: existing native collapsible groups, current group open, other groups closed; search opens matches. Use `surface:` to produce unique description IDs for desktop/mobile. Drawer links retain native navigation and the existing navigate action.
6. During search, label results separately, use only filtered `page.groups`, and suppress active/current semantics on all result anchors. Customer results visibly pair short label and full title when different. Short-label normal/context/top links expose full titles via descriptions; do not replace their short accessible names. Full-title H1/hub/footer remain visible and wrapping.
7. Empty results: existing localized message in a neutral outlined block plus visible Clear search link to the current `search_path`. Header remains usable. The recovery link and pinned home/current links use the drawer navigate action on mobile. No client-only search/filter/reset feature is added.

Provide JS/QA the final markup hook locations before they integrate. Frontend does not edit component/request/JS tests; report changed assertions to their owners.

## 4. JavaScript — reveal context while preserving the modal

1. Read the current controller and its tests: it already implements inert/aria-hidden state, focus wrapping, Escape/focus return, scroll restoration, ResizeObserver-based mode changes, pending-frame cancellation and disconnect cleanup. Preserve those contracts.
2. Add optional `drawerList` target. In the existing opening frame, keep close-control focus with `preventScroll`; then locate the drawer's canonical `[data-docs-current-guide]`. If inside the list, open its owning developer `details` if needed, then scroll **only that list** just enough to bring the whole active row into its viewport. If the canonical marker is in the pinned header (search), reset list to its top. Missing targets/markers safely preserve opening and focus behavior.
3. Do not use an unrestricted `scrollIntoView` that also scrolls the main article/window. Do not refocus the active link, auto-open all developer groups, introduce persistence/localStorage or write user-facing text. Existing translated values suffice.
4. Update the owned Vitest spec in the same change. Cover normal active-item reveal invocation, search-header marker, no active marker, absent optional list target, developer closed owning group, repeated open/close, cancellation before opening frame and disconnect. Exercise any testable selection/branch logic; mock the browser layout boundary deliberately for decision coverage, not assertions on happy-dom's zero rectangles. QA's real browser owns actual positioning and unchanged main scroll.
5. Keep existing keyboard/modal tests. Run targeted Vitest while developing, then full configured coverage once integration is stable; touched controller must be **100% lines, branches and functions**. No new exclude or ignore pragma is warranted for this small controller addition.

## 5. QA — meaningful behavior and focused browser evidence

### Ruby/component/request checks

- Update the `Page.new` and `Link.new` fixtures in the two owned component specs with the new data contract; represent a current group independent of filtered results rather than fake active rows in unrelated groups.
- Helper spec: render-time en/zh-CN short labels, full-title fallback, developer scope retains supplied titles; all customer catalog slugs have paired label keys. No copied implementation map in the spec.
- Contents component: customer entries are reachable without disclosures; developer default active group only and search-match expansion; short accessible names with full-title descriptions; unique surface IDs; real result entries remain present including current match, but no results get current/active semantics; drawer native-link action preserved.
- Reader component: visible submit/clear in both forms, locale fields/clear URLs; context remains when query excludes current or has zero matches; current link belongs to context during search, list otherwise; section mates stay available in original order, single-guide group omitted; article-only top sequence and footer share correct neighbors/endpoints; full title remains H1/footers; optional header standalone calls still work. Assert semantic containment/actions/hrefs and DOM accessibility relationships, not literal utility strings.
- Home component: group IDs resolve from both scopes and full-title directory stays complete under unrelated queries; no layout redesign assertions.
- Requests: customer and developer article with exclusion/no-result queries retain unfiltered group breadcrumb/current link/footer and top/footer sequence; customer locale/URL tenant preserved and query clears on navigation. Keep existing real-role tenant/admin/member/owner/404 cases as regression evidence. These URLs add no new auth surface.
- Replace old expectations that customers use `summary/details`, section mates disappear during search, or one generic sequence nav selector identifies both top/footer. Scope current-link checks to a contents surface; two responsive DOM copies are expected, two current links in one surface are not.

### Extend only `spec/e2e/documentation_reader.app.spec.js`

Reuse its existing geometry matrix; adapt selectors rather than creating a second harness. Add a small focused navigation set:

1. **Customer en/zh-CN, 1440px and 390px:** navigate between guides in different groups directly via visible short links, without a disclosure click. Click the visible Search submit for an exclusion query and a zero-result query; test Enter once. Article H1, group breadcrumb, pinned context, same-group footer, top/footer hrefs persist. Use a multi-guide article such as forms for footer coverage. Current guide matching a query produces one canonical current link in the visible surface, no active result. Clear/recovery keeps slug/locale and restores all contents; home reaches complete directory.
2. **Real scroll split:** with enough contents to overflow, capture header/control positions before/after moving the list to its bottom; home/input/submit/clear/context remain stationary (±1px), only list `scrollTop` changes. Assert last customer guide can be reached. Exercise a desktop short-height H=640 case and a 390px drawer; developer larger catalog proves actual desktop list scrolling where the customer list naturally fits. Query is applied while checking clear/context.
3. **Mobile active reveal at 320px:** open the drawer on late-catalog support without `q`; entire active row lies within list bounds immediately after opening, close control is focused, main/article scroll does not change. Repeat with `q` excluding support: pinned context is visible, results list starts at top. For developer, close the owning group, dismiss/reopen and confirm that group/active row is revealed, while unrelated groups stay collapsed.
4. **Keyboard regression:** keep focus trap, Shift+Tab, Escape/backdrop/focus return, inert closed drawer exclusion, resize and cleanup tests. Move customer disclosure-keyboard checks to the developer surface, since customer groups no longer disclose. Verify short links/input/buttons focus visibly and all mobile targets are at least 44px.
5. **Sequence/context destination:** top and footer resolve to identical query-free neighbors; endpoints and hubs omit inappropriate top controls. Click group breadcrumb and verify the matching hub panel is reached by fragment with customer locale intact. Review 320px wrapped top links and full H1/hub/footer titles in both locales.
6. **Retained bounds:** keep the existing W-based 896/1152 expectations at H ≥640, both audiences/locales at 320/390/768/1024/1440, developer app-sidebar states, 200% effective reflow, one visible TOC and local rich-content scrolling. Add wide W / H=550 evidence for the new one-column/drawer escape and transition back at H=640. Assert actual measurements, no document/main horizontal overflow, and center ≤704px. Record screenshots for normal customer rail, searched article and open mobile context in each locale, plus developer collapse regression; reuse existing capture output convention.

Do not multiply every new interaction across the entire existing geometry matrix. The targeted navigation scenarios supplement it. A skipped app suite without `APP_BASE_URL` is missing browser evidence.

## 6. Runtime docs — one bilingual writer

Docs lane updates all six assigned Markdown files in the implementation change:

- `doc/reference/{en,zh-CN}/customer-documentation.md`: update Page/Link types and component/helper contracts, request-local unfiltered context versus real results, static customer groups, short-label I18n/full-title accessibility, fixed header/list geometry and short-height escape, top/footer sequence, query-independent section footer, mobile reveal/focus behavior, locale-safe clear/group fragments and focused test guidance. Correct statements that navigation titles always come from front matter or section links disappear during search.
- `doc/reference/{en,zh-CN}/overview.md`: reflect shared reader search/context/header split/sequence and API, explicitly retain developer collapse; update verification instructions and shared-reader description without describing the developer catalog as forced-expanded.
- `doc/customer/{en,zh-CN}/overview.md`: replace “expand groups” instructions with visible grouped task links; explain Search/Clear and retained current guide, group/sequence links. Preserve required H2s and useful existing procedures; use “task rows” where current “task cards” copy would otherwise misdescribe the grouped directory.

Keep front matter accurate and en/zh-CN sections/examples/callouts in parity. Frontend supplies finalized locale wording; backend supplies Page/Link shape; JS supplies reveal behavior. No new runtime-doc slug/catalog registration or renderer cache bump is required. Historical October 8/first-pass design files remain historical; this UX/plan defines the override.

## 7. Integration checks and release

After backend/frontend/JS land, QA integrates its assertions and docs writer reconciles actual behavior. Run focused Rails checks:

```bash
bundle exec rspec spec/services/developer_docs/repository_spec.rb spec/services/customer_docs/repository_spec.rb spec/helpers/developer_docs/navigation_helper_spec.rb spec/components/developer_docs/reader_component_spec.rb spec/components/developer_docs/contents_nav_component_spec.rb spec/components/customer_docs/home_guides_component_spec.rb spec/requests/admin/help/docs_spec.rb spec/requests/admin/maintenance/platform/developer_docs_spec.rb spec/services/customer_docs/published_guides_spec.rb
```

JS lane development check, then mandatory coverage evidence:

```bash
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/developer_docs_nav_controller.test.js
npx vitest run --config config/javascript/vitest.config.js --coverage
```

Release owns the normal asset build and browser verification:

```bash
bin/rails tailwindcss:build
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/documentation_reader.app.spec.js --project chromium
git diff --check
```

Before any required server restart, follow AGENTS.md: remove `public/assets/.manifest.json`; use `SKIP_AUTH=1`. If digested assets shadow source, run `bin/rails assets:clobber`, rebuild Tailwind (clobber removes the tracked build), then start the dev server. Use real-role request specs for authorization evidence, not SKIP_AUTH screenshots. Scope is a reader-navigation slice; no full RSpec run is called for. Repeat or broaden checks only for new failures/concerns.

Final review checks intentional changes against the initial dirty baseline; bilingual keys and runtime docs; no customer disclosure barrier; no duplicate current-result semantics; pinned controls with independent scrolling; no lost modal keyboard behavior; preserved article bounds and developer collapse. Record actual commands/results, controller coverage, screenshot paths and any unresolved failures. Return for human review without committing.

Completion: both planning artifacts are ready; implementation is complete only after all owning lanes deliver, focused checks and real browser evidence pass, and bilingual runtime docs match the result.

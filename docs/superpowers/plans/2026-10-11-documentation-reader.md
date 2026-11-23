# Documentation reader — implementation plan

- Date: 2026-10-11
- Status: Ready for coordinated implementation
- UX: [documentation-reader UX](../specs/2026-10-11-documentation-reader-ux.md)
- Goal: clean, readable customer hub/articles and the shared developer reader, using existing ViewComponent/Tailwind/Stimulus contracts.

## 1. Integration baseline and ownership

Before implementation, inspect `git status --short` and diffs for every intended file. Current changes already span reader/home components, repositories/renderer/highlighter/catalog, controllers/views, locales, Markdown, specs, built assets, and untracked contents-nav/e2e/script files. Preserve these as the baseline; patch individual regions rather than replacing files from HEAD. Both new design documents are planning artifacts; they do not claim the visual implementation or tests have run.

| Lane | Assigned role | Scope and dependency |
| --- | --- | --- |
| Frontend | `anysys-frontend-developer` | Reader/header composition, container geometry, hub/contents/type utilities, docs CSS consolidation, paired runtime docs; owns reader/view/style files |
| Backend, only as needed | `anysys-backend-developer` | Renderer-emitted styling consolidation if frontend utilities cannot fully own it; coordinate cache/spec consequences. No repository, catalog, route, controller, schema, or authorization feature work is needed |
| QA | `anysys-qa-engineer` | Focused component/request checks and extension of existing browser spec after structural contract is fixed |
| Release | `anysys-release-engineer` | Asset build, dev-server asset protocol, focused browser/visual evidence, final diff review |
| Review | `anysys-tech-lead`, `anysys-code-reviewer` | Convention, locale/docs parity, working-tree preservation, correctness review after QA |

Agree ownership of `reader_component.rb/.html.erb`, CSS, and runtime docs before parallel build work. Backend is conditional, not an independent feature lane; QA may prepare scenarios while frontend builds. Do not dispatch two writers to the same file.

## 2. Frontend — align the header and bound the reader

Files:

- `app/components/developer_docs/reader_component.rb`
- `app/components/developer_docs/reader_component.html.erb`
- `app/views/admin/help/docs/show.html.erb`
- `app/views/admin/maintenance/platform/developer_docs/show.html.erb`

Tasks:

1. Add an optional `header` slot to the reader. In both show views, supply `AdminPageComponent` to that slot, retaining existing crumbs, localized title/summary, wrapping, and `width: "full"`. Render it inside the central strip before hub/inline TOC/Markdown. Replace the current outer AdminPage render with this composition; remove the redundant group badge. Exactly one H1 remains in rendered pages. Keep standalone reader calls without a slot valid.
2. Give the reader a 1200px capped named container, inside existing shell gutters. Use a 704px capped central strip, 224px contents rail, 160px heading rail, 32px gaps. Preserve `.docs-page`, `.customer-doc`, and `.developer-doc` hooks alongside utility classes.
3. At measured reader width 896px, enable contents/two columns. At 1152px, enable article heading rail/three columns. Hubs always omit the right column; pages without headings omit both TOC variants. Use complementary container visibility rules for desktop contents, drawer/trigger/backdrop, and inline/right TOC. Remove obsolete reader viewport `lg`/`xl` gates rather than combining incompatible gates.
4. Apply `min-w-0` throughout; give sticky rails 24px inset relative to scrollable main and bounded local vertical scrolling. Keep the existing shell/sidebar/scroll owner. A newly expanded developer app sidebar must immediately switch to the suitable mode via CSS container queries.
5. Use a nested central container for the directory and sequence breakpoints (640px), independent of reader/viewport width. Follow the UX geometry budget table exactly, allowing scrollbar rounding.

`AdminPageComponent`, `BreadcrumbsComponent`, `ShellComponent`, dashboard layout, and `LayoutHelper` are composition references; this implementation needs no shared API/style change in those files. Reader-scoped Tailwind descendant utilities style the existing header classes, including H1, description, and breadcrumb spacing.

## 3. Frontend — grouped directory and typography consolidation

Files:

- `app/components/customer_docs/home_guides_component.rb`
- `app/components/customer_docs/home_guides_component.html.erb`
- `app/components/developer_docs/contents_nav_component.rb`
- `app/components/developer_docs/contents_nav_component.html.erb`
- `app/components/developer_docs/reader_component.rb/.html.erb`
- `app/assets/tailwind/application.css`

Tasks:

1. Render one neutral `CardComponent` per supplied catalog group, with group H3/description and a list of native guide-row anchors. Preserve every guide's title/summary IDs, accessible name/description, route, ordering, focus treatment, and decorative arrow. Use natural-height panels, one column below central width 640px and two above. Remove per-guide cards and their shadow treatment. The complete customer directory still has 12 guide anchors across eight current groups; developer groups use the same component with their existing namespace.
2. Apply explicit compact/wide type: H1 28/34 → 32/40, H2 22/30 → 24/32, article H3 18/26 → 20/28, prose 16/28 → 17/30; wide starts at reader width 640px. Contents/TOC/home/breadcrumbs are 14/20; hub titles/summaries 16/24; group H3 18/26. Search inputs are 16/24 with 44px height; drawer group/link targets are at least 44px high. Use primary/secondary/tertiary text tokens and sentence-case labels. Follow UX spacing values.
3. Centralize static Tailwind utilities in the reader component for Markdown descendants (paragraphs, lists, headings, links, strong, tables, code, blockquotes, callouts, figures, captions). Explicitly override paragraph font-size/leading. Override the renderer's 15px callout wrapper to inherit the reader prose scale, while preserving its localized 14px label hierarchy. Keep heading anchors' visibility/focus behavior and syntax-token colors.
4. Make **both** variants' tables locally scrollable; code/pre locally scrollable with monospace at 16px; captions 16px; images natural ratio. Use token-aware wrapping for ordinary prose/nav and `[overflow-wrap:anywhere]` for long destinations/titles, with a code-block exception. Bound breadcrumbs locally.
5. Replace section-mates' filled box with a separator and ordinary links; retain current `section_entries` behavior. Keep previous/next cards restrained and stacked below central width 640px. Empty previous/next endpoints must not reserve blank mobile rows.
6. Remove only the reader-specific `.docs-page`/`.customer-doc`/`.developer-doc` CSS block at the end of `application.css`, after every supported rich-content treatment has a Tailwind replacement. Preserve unrelated rules, theme/global sizes, existing source safelist, and the enclosing layer's closing brace. Do not hand-write replacement CSS or add a typography plugin/framework. Use complete utility literals so Tailwind discovers them.
7. Reuse current `customer_docs` / `developer_docs` locale keys. If any new accessibility wording is necessary, add it to both corresponding en/zh-CN files with interpolation parity and render-time translation. Keep customer search locale fields and developer's existing query-free defaults.

### Conditional backend handoff

If renderer-owned callout/heading markup needs a small styling change, backend owns only `app/services/developer_docs/renderer.rb` and its focused spec, coordinated with frontend. Retain sanitizer/link/screenshot contracts and emitted anchor IDs. Increment `Renderer::CACHE_VERSION` if cached emitted HTML/classes change, documenting the exact new value in both runtime locales. A component-only utility/CSS change does not need cache invalidation. Avoid touching highlighter or repository behavior to solve reader sizing.

### Existing drawer integration

Keep `developer-docs-nav` actions, targets, and localized values. Browser-check trigger/close/backdrop/navigation and hidden-drawer keyboard reachability. If the current modal implementation requires focus, Escape, hidden/inert-state, or focus-return corrections, make the minimum correction in `app/javascript/controllers/developer_docs_nav_controller.js` with corresponding `spec/javascript/controllers/developer_docs_nav_controller.test.js` coverage. No new controller or search feature. Any changed JS must demonstrate 100% lines/branches/functions in the existing coverage run.

## 4. Update the matching runtime developer documentation

Owner: frontend; backend supplies any cache/renderer details. Files in **both** `en` and `zh-CN`:

- `doc/reference/<locale>/customer-documentation.md`
- `doc/reference/<locale>/overview.md`

Replace the obsolete per-guide card/grid, full-width AdminPage header, custom docs-CSS, 66ch customer-only measure, and 20px developer-H2 descriptions. Document the shared 704px bound, 896/1152px container rail thresholds, central header slot, explicit typography, grouped neutral panels, complete hub independence from `q`, scoped Tailwind ownership, and focused e2e command with the real config path. Preserve current content/link/locale/screenshot contracts and keep both locales' sections/examples/callouts aligned. Keep existing required H2s and accurate front matter; no new catalog slug is needed for this refinement.

Customer overview prose already calls the directory entries “task cards”; group panels still contain selectable tasks, so no content rewrite is required. Update bilingual wording only if final row terminology makes it misleading, retaining all existing guide procedures and required headings.

## 5. QA — focused behavioral and visual evidence

RSpec files to update where markup changes affect assertions:

- `spec/components/developer_docs/reader_component_spec.rb`: optional header slot, header inside central region, Markdown-only typography wrapper, hub/no-hub/empty states, TOC eligibility, retained search/locale/drawer/section/sequence contracts. Replace exact `class` equality and brittle direct-child assertions with semantic containment; preserve their original behavioral intent.
- `spec/components/customer_docs/home_guides_component_spec.rb`: one neutral group panel rather than `.card` under every anchor; all ordered metadata links, paired labels, accessible rows, empty state, metadata escaping. Replace viewport-class assertions with behavior/structure checks; browser tests own real sizing.
- `spec/components/developer_docs/contents_nav_component_spec.rb`: keep group-open, active link, localized labels, search-empty and drawer-action coverage.
- `spec/requests/admin/help/docs_spec.rb` and `spec/requests/admin/maintenance/platform/developer_docs_spec.rb`: preserve current guard/tenant/locale/404/navigation assertions; assert one H1 in the reader center and complete hubs with filtered/no-result Contents. Stop depending on the exact `class="docs-page"` serialization.
- Renderer spec only if emitted markup/classes change. Repository specs need no new implementation-mirroring tests; run their existing hub-independence coverage as regression evidence.

Extend **`spec/e2e/documentation_reader.app.spec.js`**, retaining existing hub→article, mobile drawer, developer topic, and Chinese-home scenarios:

1. Matrix: customer hub + `getting-started`/`records`; developer hub + `system-map`, en/zh-CN, widths 320/390/768/1024/1440. Use a representative H3 and a screenshot/table/code-bearing article where needed. Include expanded/collapsed developer app-sidebar states at 768/1024/1440; clear/set the existing sidebar session state deliberately for repeatability.
2. Wait for `document.fonts.ready`. Measure reader W and assert mode from W, not viewport; assert central width ≤704px (+1px rounding), a single H1, and H1 alignment with the article. Read computed paragraph/list/callout/table font sizes and line heights, and H1 > H2 > H3 > navigation sizes. Screenshot both locales' hub/article at each target size for visual review.
3. Assert document and `#main-content` `scrollWidth <= clientWidth + 1`; check reader/central bounds, not just the shell's already-clipped root. Wide tables/code may overflow **their local** scrollers, not central/main. Ignore the intentionally offscreen closed drawer when inspecting element bounds. Verify figures are uncropped and caption/full-size links wrap.
4. Compare directory guide hrefs before/after matching and no-result `q`; all customer non-home entries remain exactly once in the directory, and the developer directory remains complete. Search both desktop/mobile forms; clear restores contents. Scope active links to the visible nav; assert active group opens. Test customer language preservation and existing developer locale conventions without imposing new URL behavior.
5. Articles: one visible TOC if headings exist, none on hubs; native inline details opens and anchor navigation reaches the correct heading within scrollable main. Home, section mates, and previous/next resolve correctly. Preserve the current rule that section mates disappear while contents is filtered.
6. Open/close/navigate the mobile drawer; verify transform/backdrop state rather than `toBeVisible()` alone (offscreen translated panels can pass that assertion). Keyboard-check links, focus indication, group details, closed drawer exclusion, and any implemented modal corrections. Resize across W=896 and W=1152 and test 200% browser zoom for reflow; screenshots and measured bounds determine success.

Run focused checks after integration:

```bash
bundle exec rspec spec/components/customer_docs/home_guides_component_spec.rb spec/components/developer_docs/reader_component_spec.rb spec/components/developer_docs/contents_nav_component_spec.rb spec/requests/admin/help/docs_spec.rb spec/requests/admin/maintenance/platform/developer_docs_spec.rb spec/services/customer_docs/repository_spec.rb spec/services/developer_docs/repository_spec.rb
bin/rails tailwindcss:build
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/documentation_reader.app.spec.js --project chromium
git diff --check
```

If renderer changes, also run `bundle exec rspec spec/services/developer_docs/renderer_spec.rb`. If JavaScript changes, run `npx vitest run --config config/javascript/vitest.config.js --coverage` and verify touched source files reach 100% lines/branches/functions. This bounded reader slice does not call for the full Rails suite.

## 6. Release and handoff

1. Build Tailwind and inspect real generated sizes/container rules before browser evidence. Preserve/rebuild the already modified tracked `app/assets/builds/tailwind.css` using the normal build, never a manual edit.
2. Use a running `SKIP_AUTH=1` dev server for ordinary visual smoke work; request specs with actual roles remain the authorization evidence. Before any restart remove `public/assets/.manifest.json`. If digested assets shadow current sources, run `bin/rails assets:clobber`, rebuild Tailwind, then start `SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` according to AGENTS.md.
3. Review bilingual screenshots for hierarchy, title/prose alignment, manageable line length, quiet panels, rail contrast, and sidebar expansion/reflow. Treat browser-test skips without `APP_BASE_URL` as missing evidence, not a pass. Record commands/results and screenshot paths.
4. Review only intentional diffs against the starting working tree, including locale/runtime-doc parity and retained untracked work. Reviewers check no custom docs CSS, hard-coded UI wording, new URL/role contract, or lost working-tree feature. Resolve concrete failures, then hand off for human review without committing.

Completion: both hubs remain complete and task-oriented; both article readers have bounded 16px+ prose and clearly distinct heading/navigation sizes; all required navigation works in both locales; every target width and developer-sidebar state avoids horizontal page overflow; focused tests and browser evidence verify the result; runtime docs match implementation.

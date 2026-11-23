# Home-site marketing polish — executable UX handoff

- Date: 2026-10-06 · Role: anysys-ux-designer · Status: READY_FOR_FRONTEND
- Scope: all five public pages for customer 81721200; prioritize Pricing, About and Contact.
- Baseline: parent-reviewed current screenshots and source/DB parity, including existing uncommitted work. This is the focused visual refinement of the marketing-redesign handoff; its older surface treatments are superseded below.
- References: the parent consulted official shadcn [Card](https://ui.shadcn.com/docs/components/card), [Button](https://ui.shadcn.com/docs/components/button) and [Accordion](https://ui.shadcn.com/docs/components/accordion). Skill/MCP tools are unavailable. Translate their hierarchy into existing ViewComponents, Tailwind and native FAQ details.

## 1. Surface inventory and visual system

All surfaces are public: `/81721200/site`, then `/platform`, `/pricing`, `/about`, `/contact` beneath that path. Shared header, footer and closing CTA are included. No new routes, JavaScript, product controls or contact collection.

**Identity:** slate ink, confident violet, softly tinted atmospheric backgrounds, purposeful cards and small abstract geometric motifs. Current pricing is four plain white cards; About reads as a text wall with late artwork; Contact needs clear routes rather than a note followed by buttons.

- Keep the scoped `max-w-[1280px]` container, `px-5 sm:px-8 lg:px-10`; sections generally `py-10 lg:py-14`, compact hero `pt-10 pb-6 lg:pt-12 lg:pb-8`. Pricing hero `pt-8 pb-5 lg:pt-10 lg:pb-6`; plans start immediately after it.
- Heading ink `text-slate-950`; body `text-slate-600`; violet accents `text-violet-700`. Inner h1 40 px mobile / 48 px tablet / 56 px desktop; existing 64 px Home/Platform scale remains. Respect Chinese normal tracking and existing very-narrow-screen fallbacks.
- Hero atmosphere: `relative isolate bg-gradient-to-br from-violet-50 via-white to-slate-50`. Optional clipped, static decorative circles/diamonds inside an absolute, `pointer-events-none` background layer; content stays in document flow. No full-screen hero or animated blobs.
- Cards: `rounded-2xl border border-slate-200/80 bg-white p-5 lg:p-6 shadow-sm`; violet-tinted icon wells and small top-edge accents give hierarchy. Avoid wrapping every section in the same panel.
- Keep violet primary, outline secondary and white-on-dark CTA hierarchy, 44 px minimum targets, wrapping labels and visible violet focus rings. Use existing icon infrastructure only; icons/motifs are `aria-hidden`, never substitutes for labels.
- Responsive: `grid-cols-1 md:grid-cols-2 lg:grid-cols-3` for three-card groups (the third naturally wraps at tablet); plans use `lg:grid-cols-4`. Splits activate at `lg`. All children `min-w-0`; readable bodies at least 14 px. At 320 px and 200% zoom allow natural stacking and height growth, never crop copy or use horizontal card scrolling.

## 2. Layout per page

Saved `WebsitePage#sections` order remains authoritative. Source order below is the explicit application target; components never synthesize, move or merge saved sections at render time.

| Page | Source section sequence / final count | Default rendered images |
|---|---|---:|
| Home | hero → preview → capabilities → website → steps → desktop → FAQ → CTA / **8** | 2 |
| Platform | hero → preview → capabilities → website → steps → desktop → CTA / **7** | 2 |
| Pricing | hero → plans → **foundation** → FAQ → CTA / **5** | 0 |
| About | hero → mission → principles → craft → CTA / **5** | 1 |
| Contact | hero → availability → CTA / **3** | 0 |

### Pricing — compact promise, visibly differentiated plans

```text
Centered eyebrow / compact headline / USD reference note
Free             Starter [Recommended]      Pro             Enterprise
$0               $29                       $99             $499
checkmark rows   dark violet, white text    checkmark rows  checkmark rows
[saved CTA]      [white saved CTA]          [saved CTA]     [saved CTA]
More than a plan. A connected workspace.
[Records & forms]   [Website builder]   [Configured services]
Plan details / native FAQ rows
Dark branded closing CTA / footer
```

- Center Pricing hero with `mx-auto text-center`; keep its reference note visible directly above plans, no hero actions or image. Plan section heading stays compact, 24 px.
- Four equal-stretch cards, `gap-4`, natural height, `flex flex-col`; CTA `mt-auto`. Free/Pro/Enterprise use subtle white surfaces. Starter uses `bg-gradient-to-br from-violet-950 to-violet-800 border-violet-800 shadow-lg shadow-violet-950/10`; white titles/prices, `text-violet-100` secondary text, white CTA with violet ink, pale violet Recommended badge. No elevation transform or protruding ribbon.
- Render each existing newline-separated feature as a semantic list row with a decorative checkmark, `flex items-start gap-2`, not checkboxes. Feature separators adapt to dark treatment. Price and cadence occupy separate lines; heading/badge wrap.
- Insert exactly one `feature_grid`, semantic id **`home_site_pricing_foundation`**, from `pricing.foundation`. Three capability cards below a concise header in a soft violet/slate band. They describe product capabilities, not new plan entitlements or quota promises.
- Keep catalog-derived $0/$29/$99/$499, plan identities, quotas, trial wording, reference-price note and four FAQ answers unchanged. All plan buttons remain saved signup actions, with no purchase or plan-selection state.

### About — idea artwork leads, philosophy remains substantive

```text
Eyebrow / shorter headline + subhead  | existing idea illustration
Mission heading                      | two compact paragraphs
Principles heading / three finely bordered icon cards
Craft heading as editorial statement / saved explanatory body
Branded closing CTA / footer
```

- Existing `hero_centered` gains `media_mode: image`, `image_url: /site-images/anysys/anysys-about-idea-hero.svg`. Desktop hero is a 6/6 split, `items-center gap-8 lg:gap-12`; text left, native landscape media right. Mobile text then art. Keep image eager via existing media helper; no hero actions.
- Mission remains `rich_text`: heading 4/12, compact two-paragraph body 8/12, max 680 px. It is explanatory prose, not a full-width wall or accordion.
- Principles remain `feature_grid`: three white cards with violet icon wells, clear titles, saved body and discreet ordinal detail on a tinted band. Preserve the three current principles verbatim.
- **`home_site_about_craft` changes `split_image_text` → `rich_text`, keeping its semantic id.** Move its image assignment to hero (do not duplicate it). Retain its saved heading and body; remove the now-unused image props. Present the heading as a large editorial pull-quote-style statement with violet border/accent and body beneath. Use normal heading/prose semantics, not an attributed testimonial or fabricated quotation.

### Contact — honest availability, three purposeful routes

```text
Compact welcome headline + subhead   | small abstract linked geometric motif
[Public contact channel / saved honest availability note]
Find your starting point. / saved CTA body
[Platform title + description →] [Pricing title + description →]
[saved signup label + workspace description →]
Compact branded footer
```

- Hero remains `media_mode: none`. Decorative motif is a few connected shapes, not a chat bubble, contact form, inbox, address card or support indicator; small right-hand area at desktop, unobtrusive background detail on mobile.
- Availability `rich_text` is immediately below hero, in `rounded-2xl border border-slate-200 bg-white/90 p-5 lg:p-6`; modest 20–24 px heading and saved availability body. It is an informational panel, not an error alert.
- Existing `cta_band` becomes an intro followed by three **purpose-led route cards**, `grid-cols-1 md:grid-cols-2 lg:grid-cols-3`. Platform/Pricing cards use saved localized published, nav-visible page titles and existing resolved hrefs. Workspace card uses saved `button_label/button_href`, violet-tinted emphasis. Each card has one semantic anchor, a title, runtime-localized description and decorative arrow; no nested links or buttons.
- Runtime descriptions use `website.home_site.contact.routes.{platform,pricing,workspace}`. No new saved prop. Respect saved nav order for Platform/Pricing, then saved signup. Omit an unavailable/unpublished page; omit invalid/blank signup through existing action validation. Remaining cards reflow without placeholder slots.

### Home and Platform — stronger product composition

- Preserve current hero wording, actions and section counts; enrich the hero atmosphere without delaying the draft board.
- Draft board: lightly tinted shell, restrained shadow, titlebar using existing `example_label` plus decorative dots. Brief panel in violet tint; three white output cards with records/form/website decorative glyphs, saved titles/status/body. A purely decorative connector line ties the cards together on desktop and disappears on mobile. Existing labels and review note remain prominent; no fake interactive inputs or browser URL.
- Capabilities: deliberate icon-led bordered panels, three on Home and four in a 2×2 Platform grid. Saved titles/bodies are authoritative. Process: visually distinct ordered rail with violet numbered nodes and soft slate background; connectors desktop only, stacked numbered rows on mobile.
- Website story and Windows perspective retain media and copy; use lighter art frames and differentiated soft surfaces. Keep Windows Coming soon visible alongside its future-scoped privacy/local-hosting statements; services remain explicitly configured.
- Shared closing: inset `bg-gradient-to-br from-slate-950 to-violet-950`, white heading/CTA, restrained violet geometric corner detail. Footer: slate-950 base, white brand, slate-300 blurb/links, violet accent and existing saved columns/tagline; preserve Coming soon and accessible contrast. No new proof, company claims, download or legal destinations.

## 3. Exact paired copy

Only changes below replace existing content. Existing Home/Platform/Pricing heroes, principles, craft, contact availability/CTA and commercial qualifications stay verbatim in both locales. `\n` denotes a stored newline; body paragraph breaks are stored as blank lines. Translate at call time, never in constants.

| Locale key beneath `website.home_site` | English | Simplified Chinese |
|---|---|---|
| `about.hero.headline` | `Built for the way\nyour business works.` | `围绕你的业务方式，\n而构建。` |
| `about.hero.subhead` | Custom records, forms and websites belong together. Anysys gives your expertise one connected workspace to take shape. | 专属记录、表单与网站，本应相互贯通。Anysys 让你的业务经验，在同一个工作空间中落地。 |
| `about.mission.heading` | Your expertise is the starting point. | 你的业务经验，就是起点。 |
| `about.mission.body` paragraph 1 | Every business has its own information, processes and public story. Anysys connects custom records, forms and website pages so your system and public presence can grow from the same idea. | 每个业务都有自己的信息、流程与品牌故事。Anysys 将专属记录、表单与网站页面连接起来，让业务系统与品牌呈现从同一份构想出发。 |
| `about.mission.body` paragraph 2 | AI proposes a first draft. You refine it with visual editors, configure the services you need and decide when pages are ready to publish. Your expertise sets the direction; your judgement stays in charge. | AI 提出初稿，你用可视化编辑器完善细节、配置所需服务，并决定页面何时发布。业务经验定方向，判断权始终在你手中。 |
| `contact.hero.headline` | `Your next idea.\nA clear place to start.` | `你的下一个构想，\n从这里起步。` |
| `contact.hero.subhead` | Explore the platform, compare reference plans or create a workspace for your next idea. | 了解平台、比较方案参考，或为下一个构想创建工作空间。 |
| `pricing.foundation.heading` | More than a plan. A connected workspace. | 不止一个方案，更是贯通业务的工作空间。 |
| `pricing.foundation.items[0].title` | Records & forms | 记录与表单 |
| `pricing.foundation.items[0].body` | Define your record types and the forms that collect the information your business needs. | 定义记录类型，设计表单，收集业务所需的信息。 |
| `pricing.foundation.items[1].title` | Website builder | 网站构建器 |
| `pricing.foundation.items[1].body` | Shape editable pages, choose a theme and preview your website before publishing. | 打磨可编辑页面、选择主题，发布前预览网站。 |
| `pricing.foundation.items[2].title` | Configured services | 按需配置服务 |
| `pricing.foundation.items[2].body` | Use member accounts, payments, email and SMS with the required services configured. | 配置所需服务，使用会员账号、支付、邮件与短信。 |
| `contact.routes.platform` | See how records, forms and websites work together. | 了解记录、表单与网站如何相互贯通。 |
| `contact.routes.pricing` | Compare reference plans and understand their limits. | 比较方案参考，了解各项额度。 |
| `contact.routes.workspace` | Create a workspace and start shaping your idea. | 创建工作空间，让构想开始落地。 |

Foundation `kicker` and `subhead` are empty strings, with three `items[{title,body}]`. Reuse existing identical title keys when building props; the table defines rendered copy, not a requirement to duplicate an existing translation. Add paired locale leaves and matching interpolation variables for every new string.

## 4. Source interface and component reuse

**Source:** `Websites::HomeSite.definition(locale: :en)` (also `:"zh-CN"`) returns normal `{id,type,props}` sections. `Websites::HomeSite.apply!(locale: :en)` explicitly persists the source via SaveSite/SavePage for customer 81721200; it is never invoked on a read. Preserve existing section ids through the source matcher. DB currently matches source; inspect again before applying to avoid overwriting intervening owner edits.

- In `app/services/websites/home_site.rb`, make About hero's media conditional on page role, move the existing asset out of `about.craft`, change craft's type with its id unchanged, and insert `content(page, "foundation", "feature_grid")` after Pricing plans.
- Stored assignments remain **9**: Home website + three desktop fields; Platform website + three desktop fields; About hero. Rendered placements remain **2/2/0/1/0**. Windows duplicate assignments still prevent stock-image fill and render once per panel. Abstract inline decoration does not add stored/image-tag placements.
- `HomeSiteLocalization` remains the paired source overlay; ensure changed craft type and hero image work for the newly persisted source without runtime restoration or content synthesis.
- Frontend owns **all** `app/components/websites/home_site/**`, `app/services/websites/home_site/presentation.rb` and their specs. Reuse Hero, Draft, Index, Story, Plans, Perspective, FAQ, CTA, Header/Footer, SectionComponent, Navigation, language/mobile-nav and media helpers; **no new ViewComponent is required**.
- Existing props suffice: Hero's media/headline/actions; Plans' tiers/newline features/highlight/featured_label; Index's heading/items; Story's heading/body; CTA's headline/body/button and localized nav context. Add only internal layout variants as needed: About hero `:about`, Contact hero `:contact`, Pricing feature grid `:foundation`. Existing `:pricing` becomes centered.
- Distinguish About craft within `rich_text` only through its existing semantic section role (`HomeSite.section_role` may need an intentional resolver-facing accessor); do not match body text or section array position. Unknown/opaque roles use generic editorial layout. Resolver/helper changes belong to frontend; coordinate any accessor in `home_site.rb` with backend's sole writer.

## 5. Interactions, states and acceptance

- Any public page → header/footer nav → existing published localized page. Language switch retains current page; mobile navigation keeps existing focus/dismissal behavior. Same-page admin preview has identical section styling and its established preview-link behavior.
- Home/Platform hero, plan or closing signup → saved `/auth/sign_up` action with existing locale resolution → existing signup flow. This is workspace creation, not purchase/contact submission; authentication/validation outcomes belong to that destination.
- Contact → Platform/Pricing route card → published existing page; workspace route → saved signup. Missing routes disappear rather than returning a dead link. No permission gate is added to these public pages.
- Pricing/Home FAQ → native summary activation → answer expands in place; keyboard activation works and multiple answers may stay open. No loading state, vendor call or form-submit result is introduced by this static polish.
- Empty edited lists/actions remain omitted; blank copy creates no empty card. Invalid media uses existing media validation and text-first fallback. Existing unavailable-page handling remains authoritative. Provider outages do not create a marketing-page spinner or invented support response.
- Verify EN/zh-CN at 320, 390, 768, 1024 and 1440 px, plus 200% desktop zoom: no horizontal document overflow, clipped labels, cropped meaningful art or missing keyboard focus. Starter dark text/badge contrast passes; icons are hidden from accessibility output; one h1 per page.
- Assert counts, nine stored assignments/five rendered placements, unchanged billing catalog/disclaimers, saved order/id preservation, unpublished-link omission and generic tenant isolation. Screenshot all five pages in both locales, prioritizing first-view pricing cards, split About hero and full Contact composition. Documentation parity is required when implementation lands.

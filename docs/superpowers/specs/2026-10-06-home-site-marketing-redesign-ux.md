# Anysys marketing redesign — executable UX specification

- Date: 2026-10-06
- Role: anysys-ux-designer
- Status: READY_FOR_FRONTEND
- Scope: design/research only; customer 81721200's five public WebsitePage surfaces.

## 1. Decision

**Identity: “Your business. Built your way.”** An editorial, product-led SaaS website: confident slate typography, restrained violet emphasis, generous but bounded spacing, a readable connected-draft demonstration, and distinctly composed supporting pages. The visual signature is a two-line typographic home hero above a structured HTML draft board. Artwork supports the story in selected sections rather than carrying every section.

This supersedes the copy-refresh baseline's layout, section order and image-slot counts. Keep the product positioning: AI-assisted custom business systems and public websites in one workspace; proposals are drafts, people review, pages are published deliberately, and external services require configuration. Windows is upcoming. Pricing is a reference guide. Contact has no public channel yet.

Deliver using Rails ViewComponent + Tailwind and the existing saved section dispatcher. Every page remains a sequence of ordinary `{ id, type, props }` objects in `WebsitePage#sections`. All marketing text is sourced through paired EN/zh-CN I18n definitions, persisted as editable props, and presented through `HomeSiteLocalization`. No full-page hardcoded replacement, new route, live-demo control or new JavaScript is needed.

## 2. Research and observed baseline

### Official shadcn consultation

The required shadcn skill/MCP tools are unavailable in this harness. Consulted official sources directly before selecting the composition:

- [Card](https://ui.shadcn.com/docs/components/card): header/content/footer hierarchy, compact card spacing, restrained boundaries. Adapt to semantic `<article>` and ViewComponent parts for drafts and plans; do not frame every editorial section as a card.
- [Button](https://ui.shadcn.com/docs/components/button): default/outline/link hierarchy and accessible focus. Navigation CTAs remain semantic anchors styled as buttons; preserve their link role.
- [Accordion](https://ui.shadcn.com/docs/components/accordion): separated question rows, clear trigger/content hierarchy. Adapt the appearance to the existing native `<details>/<summary>` FAQ, supporting several expanded answers.
- [Badge](https://ui.shadcn.com/docs/components/badge): small secondary/outline status labels. Use only for meaningful Draft, Recommended and Coming soon states.

These are composition references, not React dependencies. Implement spacing with Tailwind utilities, not the docs' custom CSS or React primitives.

### Fresh appearance inspection

Captured localhost:3000 **after the latest copy refresh**, both locales and all five pages, at 1440×1000 and 390×844. All 20 responses returned 200. Scrolled each page, decoded every image, then captured at the top; all main images decoded successfully. Older `wording-final-*` images are not the appearance baseline for this specification.

Evidence: `/tmp/opencode/marketing-redesign-current-{home,platform,pricing,about,contact}-{en,zh-CN}-{1440,390}.png`; desktop first-view captures end in `-en-1440-top.png`. Capture script: `/tmp/opencode/marketing-redesign-capture.cjs`.

| Surface | Current EN full height: desktop / mobile | Specific visual observation |
|---|---:|---|
| Home | 7,583 / 10,779 px | Large centered headline, then a separate wide illustration, then another introduction above the HTML preview. The product explanation arrives late. Three illustrated website cards, three desktop illustrations and full pricing cards make the page repetitive. |
| Platform | 7,132 / 8,687 px | A 1,500 px hero and three alternating image stories dominate. The same floating-panel art vocabulary recurs through almost every capability. |
| Pricing | 4,104 / 5,109 px | The 1,469 px illustrated hero delays the actual prices beyond the first viewport. Another large heading precedes four tall cards. |
| About | 4,122 / 4,450 px | A 1,583 px hero precedes two mission paragraphs and three familiar illustrated cards. It reads like another landing page rather than a substantive product philosophy. |
| Contact | 2,982 / 2,482 px | A 1,469 px hero illustration outweighs the contact-status information. The large closing CTA repeats the hero's invitation. |

Existing strengths: consistent bilingual navigation, real editable draft-preview text, clear plan numbers, native FAQ interactions, elegant vector assets, Inter typography and responsive stacking. Weaknesses: little section rhythm, many headings repeat abstract ambition language, excessive image framing, extremely long mobile pages, and no persistent desktop signup CTA. Chinese copy is naturally shorter, but the same oversized frames still dominate.

Implementation inspected: `HomeSite`, `HomeSiteLocalization`, `SectionKit`, `SectionFields`, `Contracts::Section`, `SavePage`, `PageComponent`, public chrome, all relevant section templates, `IllustrationComponent`, and `Billing::StandardPlans`. Important constraints:

- The composer rebuilds props from `[data-prop]` controls; undisplayed new props would be lost on Save. Use existing props throughout this design.
- Single-line headline inputs normalize away newlines. In the target site's composer only, render the existing headline field as a textarea so the deliberate line treatment survives Save; this needs no new prop or JavaScript.
- `Media.fill` fills every blank `card_grid` image with stock photography. The Windows source cards must all carry the same selected SVG path; the scoped component displays the first instance only, preserving distinct authored media separately.
- `HomeSiteLocalization` matches exact source text by page slug, section type/id and leaf path. Newly composed bilingual text must be persisted explicitly; shipping locale files alone does not update old records.
- Tenant edits lock structure. Source application may use `SavePage(..., structure_editable: true)` for this authorized redesign.
- The bundled-image helper overlays localized SVG nameplates. Reuse it at native landscape ratios and keep essential meaning in adjacent HTML.

## 3. Surface inventory and shared chrome

All five surfaces are **public**, open to anonymous visitors:

| Page | Existing URL | Visitor task |
|---|---|---|
| Home | `/81721200/site` | Understand the offer, see the draft process, start or explore. |
| Platform | `/81721200/site/platform` | Understand records/forms, website building and configured services. |
| Pricing | `/81721200/site/pricing` | Compare reference plans and understand what quotas count. |
| About | `/81721200/site/about` | Understand why the product exists and how it approaches building. |
| Contact | `/81721200/site/contact` | Understand channel availability and find a useful next step. |

Keep the existing nav titles: Home / Platform / Pricing / About / Contact; 首页／平台／价格／关于／联系我们. The brand also links home. Use saved, published, nav-visible pages in saved order; never add links for unpublished pages.

### Header

- Container specification below; `h-16 lg:h-[72px]`, `sticky top-0 z-30 border-b border-slate-200/70 bg-white/95 backdrop-blur-md`.
- Wordmark at left: saved `Website#name`, `text-xl font-semibold tracking-[-0.035em] text-slate-950`. No invented logo asset.
- Desktop: wordmark / page navigation / language switch + **Start building**. Nav: `hidden lg:flex items-center gap-1`; anchors `min-h-11 px-3 text-sm font-medium text-slate-600 hover:text-slate-950 rounded-lg`. Current item `bg-violet-50 text-violet-800` and `aria-current="page"`.
- Desktop signup: `/auth/sign_up`, `min-h-11 rounded-lg bg-violet-700 px-4 text-sm font-semibold text-white hover:bg-violet-800`. Copy uses the existing actions.start key at call time. Preserve locale through `href_for`.
- Below `lg`: wordmark + existing language dropdown + 44 px mobile-nav trigger. Signup lives in the existing sheet and hero rather than squeezing the 320 px header. Reuse existing `website-nav` controller and MobileNavSheet behavior, focus management and dismissal. The sheet must use the same page set and include the signup link once.
- Keep the sheet outside the blurred sticky header, as the current component already does. Language choices remain native GET links on the current page, retaining full accessible language names.

### Footer

- `border-t border-slate-200 bg-slate-50`; `py-10 lg:py-12`, not another 96 px content section.
- `grid grid-cols-1 gap-8 lg:grid-cols-12`; brand/blurb `lg:col-span-5`; saved columns `lg:col-span-7 grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-6`.
- Brand `text-xl font-semibold`; blurb `max-w-sm text-sm leading-6 text-slate-600`. Column headings `text-sm font-semibold text-slate-950`, links `min-h-11 inline-flex items-center text-sm text-slate-600 hover:text-violet-800`.
- Preserve Product, Company and Desktop column roles. Windows link uses existing `platform` destination and **Windows app — Coming soon** / **Windows 应用 — 即将推出**; it is not a download link.
- Bottom rule `mt-8 border-t border-slate-200 pt-5`; copyright with current year/name, and saved tagline in wrapping `text-xs leading-5 text-slate-500`. No new privacy/legal routes or unverifiable business details.

### CTA system

Hero actions: primary violet anchor + outline secondary; gap 12 px, `flex flex-col sm:flex-row`, full-width below `sm`. Base: `inline-flex min-h-12 items-center justify-center gap-2 rounded-lg px-6 py-3 text-base font-semibold leading-6 transition-colors`. Use minimum height, not a fixed height that clips translated text.

- Primary: `bg-violet-700 text-white hover:bg-violet-800`.
- Secondary: `border border-slate-300 bg-white text-slate-800 hover:bg-slate-50`.
- All: `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-600 focus-visible:ring-offset-2`.
- Closing band: inset slate panel, horizontal on desktop, `rounded-2xl bg-slate-950 p-7 lg:p-10`, left copy `lg:max-w-[760px]`, right white CTA `shrink-0`. Heading 28/36 px, body 16 px `text-slate-300`. Outer `py-10 lg:py-14`; no glow or enormous centered heading.
- Contact closing uses a quiet `bg-slate-50 border border-slate-200` panel with a violet signup anchor. It is a next-step invitation, not a contact submission.
- No destructive actions, sales scheduler, email input, plan-selection purchase action, download control or fake demo button on these pages.

## 4. Exact visual system

### Containers, rhythm and responsive rules

| Role | Tailwind specification |
|---|---|
| Default container | `mx-auto w-full max-w-[1280px] min-w-0 px-5 sm:px-8 lg:px-10` — 1,200 px content at 1440; 20 px mobile gutters. |
| Reading measure | `max-w-[680px]`; hero subhead `max-w-[640px]`; section intro `max-w-[600px]`. |
| Normal section | `py-12 lg:py-20`; headline-to-content `mt-7 lg:mt-9`. |
| Adjacent compact section | `py-8 lg:py-12`; use for process and the start of pricing. |
| Home/Platform hero | `pt-12 pb-8 lg:pt-14 lg:pb-9`; no `vh`/minimum-height hero. |
| Inner-page hero | `pt-12 pb-8 lg:pt-16 lg:pb-10`; maximum text width 900 px. |
| Demo section | `pt-0 pb-12 lg:pb-16`; intro-to-board 24 px. |
| Section split | `grid grid-cols-1 items-center gap-8 lg:grid-cols-12 lg:gap-12`; copy 5 columns, visual/prose 7 columns. |
| Standard boundary | `border-slate-200`; radii `rounded-xl` compact panels, `rounded-2xl` major panels. |
| Body surface | `bg-white text-slate-950 font-sans antialiased`; restrained slate-50 section bands. |

At `md` (768–1023), capabilities and pricing use two columns; text/media stories remain stacked; no sticky editorial titles. At `lg` (1024+), activate 12-column stories, three-column draft/process layouts and four-plan pricing. All grid children have `min-w-0`. Keep native document scrolling; no carousel or horizontal scroller for plans/features. Do not hide overflow to disguise text-layout bugs.

Use **standard Tailwind font sizes rather than `text-site-*`** in the isolated presentation; existing global site typography/theme classes must not be retuned. Keep Inter 400/500/600/700 already loaded; system sans fallback for Chinese. English headings use tight tracking; for zh-CN use `tracking-normal` (chosen at render time, not custom CSS). Never stretch Chinese glyphs or force Latin word spacing onto them.

| Text | Tailwind specification |
|---|---|
| Home/Platform h1 | `text-[40px] leading-[1.1] font-semibold tracking-[-0.04em] text-balance sm:text-[56px] lg:text-[64px] lg:leading-[1.06]` |
| Pricing/About/Contact h1 | Same mobile base; `sm:text-[48px] lg:text-[56px]`; About maximum 800 px. |
| Section h2 | `text-[30px] leading-[1.15] font-semibold tracking-[-0.03em] text-balance lg:text-[40px]` |
| Demo h2 / FAQ h2 | `text-2xl leading-tight font-semibold tracking-[-0.025em] lg:text-[30px]` |
| Card/index h3 | `text-lg leading-7 font-semibold text-slate-950` |
| Lead paragraph | `text-lg leading-7 text-slate-600 text-pretty` |
| Body | `text-base leading-7 text-slate-600 text-pretty` |
| Demo / plan detail | `text-sm leading-6 text-slate-600`; never below 14 px for meaningful details. |
| Eyebrow | `text-sm leading-5 font-medium text-violet-800`; sentence case, no tiny uppercase tracking. |
| Status badge | `inline-flex w-fit max-w-full rounded-full border border-violet-200 bg-violet-50 px-2.5 py-1 text-xs leading-4 font-medium text-violet-800` |
| Plan price | `text-[40px] leading-none font-semibold tracking-[-0.03em] tabular-nums text-slate-950` |

Violet is limited to the home headline's final line, buttons, status badges and small ordinal accents. Slate carries the rest. No site-wide grid backdrop, gradient typography, large blur blobs, continuous purple backgrounds or hover enlargement of artwork. One static `bg-gradient-to-b from-violet-50/60 to-white` lead background is permitted on Home/Platform only, applied per section without coupling their rendering.

Headline line treatment: Home source stores `Your business.\nBuilt your way.` and `你的业务，\n由你定义。` in the existing `headline` string. Escape and render its lines as block spans; the final line is violet only on Home. Owner single-line headlines render normally in slate. No raw HTML inside props or locale values, and no new accent-text field.

## 5. Page composition and exact content

The table ids below are source ids. Preserve a saved semantic predecessor's existing id where possible; use these stable ids for newly introduced sections. Do not use the current ids beginning `sec_*` as presentation selectors. Types, props and saved order remain authoritative.

### A. Home — promise → demonstration → breadth → craft → control → action

**8 sections**. Remove the redundant AI-builder split and full home pricing cards. Pricing remains prominent in header/footer and its dedicated page. Add a concise, unboxed capability index; concentrate the website story into one illustration rather than three.

| Order / source id | Stored type | Composition and data |
|---|---|---|
| 1 `home_site_home_hero` | `hero_centered` | Text-only centered hero, `media_mode: none`, eyebrow/headline/subhead plus signup/platform buttons. |
| 2 `home_site_home_preview` | `ai_preview` | Compact connected HTML board; real readable request and three draft outputs. |
| 3 `home_site_home_capabilities` | `feature_grid` | Header + three border-top editorial columns; no images/cards. |
| 4 `home_site_home_website` | `split_image_text` | Copy left, brand-studio vector right at 8:5. |
| 5 `home_site_home_steps` | `steps` | Three-step numbered rail, no images. |
| 6 `home_site_home_desktop` | `card_grid` | Upcoming-status compact perspective panel: one image and three text entries. |
| 7 `home_site_home_faq` | `faq` | Three native questions; text title left, answers right. |
| 8 `home_site_home_cta` | `cta_band` | Horizontal slate closing, signup. |

Exact Home hero:

| Prop | EN | zh-CN |
|---|---|---|
| eyebrow | AI-assisted systems & websites | AI 辅助构建系统与网站 |
| headline | Your business. / Built your way. | 你的业务，／由你定义。 |
| subhead | Build custom records, purpose-built forms and a standout website in one workspace. Start with AI-assisted drafts. Refine the details. Decide what goes live. | 在同一个工作空间中，构建专属记录、贴合业务的表单与出众网站。用 AI 起草方案，亲自打磨细节，决定何时发布。 |

The slash in this table means a stored newline, not displayed punctuation. Primary: existing Start building / 开始构建 → `/auth/sign_up`. Secondary: existing Explore the platform / 了解平台 → `platform`.

Exact board shared labels: `example_label` **Illustrative example / 产品示意**; `prompt_label` **Your brief / 你的需求**; `output_label` **Connected drafts / 关联草稿**; each item `status` **Draft / 草稿**. `review_note`: **AI proposes. You review the details and decide what goes live. / AI 提出方案，由你审核细节、决定何时发布。**

Home board `heading`: **One brief. Three connected drafts. / 一份需求，三份关联草稿。**; `kicker` and `subhead` blank. `prompt`: **Build a membership workspace with signup and a public website. / 创建会员管理工作空间，配备注册表单和公开网站。**

| Draft item title | EN body (newlines preserved) | zh-CN title / body |
|---|---|---|
| Member records | Name · Email\nMembership level · Renewal date | 会员记录：姓名 · 邮箱\n会员等级 · 续费日期 |
| Registration form | Contact details\nMembership options | 注册表单：联系方式\n会员选项 |
| Public website | Home · Membership · Contact\nEditable page drafts | 公开网站：首页 · 会员介绍 · 联系我们\n可编辑的页面草稿 |

These are sample proposed field/page outlines, not actual member records or deployed UI. Body text is escaped, `whitespace-pre-line`; do not parse punctuation into an invented form/table. No inputs, play buttons, tabs, browser address field, live status, working application link or “Generate” button.

Capabilities `kicker`: **One connected workspace / 一个空间，贯通业务**; `heading`: **The system behind your business. The website in front of it. / 业务运作与品牌呈现，一并构建。**; blank subhead. Items:

1. **Records & forms / 记录与表单** — **Define the information you manage and the forms that collect it. / 定义业务所需的信息，用贴合实际的表单收集。**
2. **Your public presence / 你的品牌网站** — **Shape editable pages, choose a theme and add your own imagery. / 打磨可编辑的页面，选择主题，换上自己的图片。**
3. **Configured services / 按需配置服务** — **Bring member accounts, payments, email and SMS into your workspace with the required services configured. / 配置所需服务，在工作空间中使用会员账号、支付、邮件与短信。**

Website story `heading`: **Make the first impression yours. / 让第一印象，展现你的独特。** `body`: **Your website is part of the workspace—not an afterthought. Refine the message, choose your theme and bring your own images. Preview each page, then publish when it represents your business. / 网站是工作空间的一部分，也是业务价值的公开表达。打磨文案、选择主题、添加自己的图片；逐页预览，达到你的标准再发布。** `image_url`: `/site-images/anysys/anysys-brand-studio.svg`, `image_side: right`.

Process `kicker`: **From idea to reviewed pages / 从构想到审核发布**; `heading`: **Start with your expertise. / 从你的业务经验出发。** Items:

- **Describe / 描述需求** — **Tell the assistant what your business needs to manage and what visitors should discover. / 告诉助手你要管理什么，以及希望访客了解什么。**
- **Review / 审核完善** — **Check the proposed records, forms and page drafts. Refine them with visual tools. / 审核提出的记录、表单与页面草稿，用可视化工具完善。**
- **Publish / 发布页面** — **Preview your website pages, publish when ready and configure the services you need. / 预览网站页面，准备就绪后发布，并配置所需服务。**

Windows content is specified once below and shared with Platform. Home FAQ uses the three entries in §7. Closing `headline`: **Build around what makes your business different. / 围绕业务的独特之处，开始构建。** `body`: **Give your custom system and public website a workspace of their own. / 为专属系统与品牌网站，创建自己的工作空间。** Button: existing Create your workspace / 创建工作空间 → signup.

### B. Platform — one example, then the actual building blocks

**7 sections**. Replace the three oversized alternating image stories with one website story and a compact process rail. Maintain configured-service qualifications in visible body text.

| Order / source id | Stored type | Composition |
|---|---|---|
| 1 `home_site_platform_hero` | `hero_centered` | Text-only, centered, signup + pricing. |
| 2 `home_site_platform_preview` | `ai_preview` | Same board component; a more detailed membership brief. |
| 3 `home_site_platform_capabilities` | `feature_grid` | Four unboxed index entries, `md:grid-cols-2`. |
| 4 `home_site_platform_website` | `split_image_text` | Website authoring story, one review-publish illustration. |
| 5 `home_site_platform_steps` | `steps` | Reuse Home's three process entries; compact rail. |
| 6 `home_site_platform_desktop` | `card_grid` | Shared upcoming-Windows perspective panel. |
| 7 `home_site_platform_cta` | `cta_band` | Horizontal slate signup closing. |

Hero `eyebrow`: **The Anysys platform / Anysys 平台**; `headline`: **Your operations and your website.\nBuilt together. / 业务系统与品牌网站，\n在同一处构建。**; `subhead`: **Define your records, shape your forms and create your public presence. AI-assisted drafts and visual editors help you build around the way your business works. / 定义记录、设计表单、打造品牌网站。结合 AI 辅助草稿与可视化编辑器，让工具围绕你的业务方式而构建。** `media_mode: none`. Primary Start building → signup; secondary See pricing / 查看价格 → `pricing`.

Preview `heading`: **Follow one idea through the workspace. / 看一份构想，如何贯通工作空间。**; `prompt`: **Build a community membership system. Track renewal dates, collect applications and draft a website explaining membership options. / 创建社区会员系统，记录续费日期、收集入会申请，并起草介绍会员方案的网站。**; shared labels/review note as Home; items:

- **Membership records / 会员记录** — **Contact details · Membership level\nRenewal date / 联系方式 · 会员等级\n续费日期**.
- **Application form / 入会申请表** — **Applicant details\nMembership options / 申请人信息\n会员选项**.
- **Membership website / 会员网站** — **Introduction · Membership options\nApplication link to review / 机构介绍 · 会员方案\n待审核的申请链接**. The phrase describes a proposed link; render it as text, not an anchor.

Capabilities `kicker`: **Building blocks / 业务构建工具**; `heading`: **A workspace shaped around your work. / 围绕实际业务，构建工作空间。**; `subhead`: **Work in English or Simplified Chinese. Brief the assistant by typing, or use voice input when a speech provider is configured. / 支持英语与简体中文。输入文字描述需求；配置语音服务后，也可使用语音输入。**

| Item | EN body | zh-CN title / body |
|---|---|---|
| Custom records & forms | Define your record types and the forms that capture the information your business needs. | 自定义记录与表单：定义记录类型，设计表单，收集业务真正需要的信息。 |
| Website builder | Refine page copy, themes and imagery. Preview editable drafts and publish reviewed pages. | 网站构建器：打磨文案、主题与图片；预览可编辑草稿，发布已审核的页面。 |
| Members & payments | Use member accounts and configured payment services. Manage access with sign-in, permissions and captcha. | 会员与支付：使用会员账号与已配置的支付服务，通过登录验证、访问权限与验证码管理访问。 |
| Email & SMS | Use configured messaging services and follow message status with delivery tracking. | 邮件与短信：使用已配置的消息服务，通过送达追踪掌握消息状态。 |

Website story `heading`: **A public presence you can keep shaping. / 品牌网站，持续由你塑造。**; `body`: **Ask AI to propose pages around your offer. Make the copy, theme and imagery your own in the visual builder. Preview each page before publishing, then return to refine it as your business evolves. / 请 AI 围绕业务价值提出页面方案。在可视化构建器中完善文案、主题与图片，发布前逐页预览，并随业务发展持续更新。** `image_url`: `/site-images/anysys/anysys-review-publish.svg`, `image_side: left` (visual left at `lg`, copy first on mobile).

Process heading: **Describe. Review. Publish. / 描述需求，审核完善，发布页面。**; blank kicker; Home's same items. Closing: **Put your way of working at the centre. / 让你的业务方式，成为构建的中心。** + **Create a workspace for your custom system and public website. / 为专属系统与品牌网站，创建工作空间。** + signup.

### C. Pricing — plans first, explanations second

**4 sections**, preserving existing roles and ids: `hero_centered`, `pricing`, `faq`, `cta_band` (`home_site_pricing_{hero,plans,faq,cta}`). No hero artwork, billing toggle or separate repeated comparison table.

Hero (release-refined): `eyebrow` **Pricing / 价格**; `headline` **Space to start. Room to grow. / 轻松起步，从容成长。**; `subhead` **Reference monthly prices in USD. Plans, trials, currency and charges are confirmed in workspace billing. / 美元月付参考价格。方案、试用、币种与费用，以工作空间账单设置为准。**; `media_mode: none`; both action pairs blank. Hero `lg:pb-6`; see §12 for its compact measures.

Pricing props: blank `kicker`; `heading` **Compare reference plans / 方案参考** (visible h2 at 24 px, left aligned, not a second giant headline); blank `subhead` because the reference note is immediately above the cards. `featured_label`: existing Recommended / 推荐方案. Generate every tier price, limit and trial from `Billing::StandardPlans::CATALOG`, retaining existing interpolation-based locale keys:

| Tier | Reference USD / month | Page-builder pages | Record types | Workspace accounts | Trial | Exact EN / zh-CN body |
|---|---:|---:|---:|---:|---|---|
| Free | $0 | 10 | 5 | 1 | None | A foundation for your first idea. / 为第一个构想，打好基础。 |
| Starter | $29 | 50 | 25 | 5 | 14 days | For a small team's next step. / 为小团队的下一步而设。 |
| Pro | $99 | 500 | 200 | 25 | 14 days | More room for a growing business. / 为成长中的业务，留出更多空间。 |
| Enterprise | $499 | Unlimited | Unlimited | Unlimited | 14 days | A broader foundation for your organisation. / 为整个机构，构建更广阔的基础。 |

Names stay Free/Starter/Pro/Enterprise in both locales as existing plan identities. All CTAs retain Start building / 开始构建 → `/auth/sign_up`; no plan query parameter, selection state or implicit purchase. Cadence remains USD / month / 美元／月 in both request languages. Keep the existing quota and trial wording from `pricing.limits.*` / `pricing.trial`; the heading “reference” and visible hero note qualify the cards.

Grid `grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4 items-stretch`. Each card `rounded-xl border border-slate-200 bg-white p-5 xl:p-6 flex flex-col gap-5`. Starter `border-violet-500 bg-violet-50/30 ring-1 ring-violet-500`; no raised card or height-changing ribbon. Heading/badge row wraps. Price and cadence are separate lines so $499 fits at 1024. Body minimum two-line rhythm using flex spacing, not clipping. Feature list `border-t border-slate-200 pt-4 space-y-2`; CTA `mt-auto w-full min-h-11 text-sm`. Desktop card budget approximately 390–430 px, natural height. At 390, target roughly 360–400 px per card; full contents always visible.

FAQ: **Plan details / 方案细节**, existing four pricing questions/answers retained verbatim in both locales. In particular retain that page limits count `Page` including form pages, **not WebsitePage marketing pages**, and seats count registered workspace accounts including admins. Retain available-trial and usage-charge qualifications. Closing: **Start with your workspace. / 从工作空间起步。** + **Explore the plans available in workspace billing. / 在工作空间的账单设置中，了解当前可用方案。** + signup.

### D. About — a clear product philosophy, not invented company proof

**5 sections**:

| Order / source id | Type | Composition |
|---|---|---|
| 1 `home_site_about_hero` | `hero_centered` | Text-only, left aligned; no hero buttons. |
| 2 `home_site_about_mission` | `rich_text` | Heading left 4/12; substantive prose right 8/12, max 680 px. |
| 3 `home_site_about_principles` | `feature_grid` | Three numbered editorial columns in a slate-50 band. |
| 4 `home_site_about_craft` | `split_image_text` | One illustration + short practical product philosophy. |
| 5 `home_site_about_cta` | `cta_band` | Horizontal signup closing. |

Hero `eyebrow`: **About Anysys / 关于 Anysys**; `headline`: **Good software should make room\nfor your way of working. / 好的软件，\n容得下你的业务方式。**; `subhead`: **Anysys brings custom system building and website creation into one workspace—so your operations and your public presence can start from the same idea. / Anysys 将专属系统构建与网站创建汇聚到一个工作空间，让业务运作与品牌呈现从同一份构想出发。** `media_mode: none`.

Mission `heading`: **Your expertise is the starting point. / 你的业务经验，就是起点。** `body` is two paragraphs:

> Every business has its own information, processes and public story. Anysys is built around a simple idea: the tools should take their shape from that work. Custom records, forms and website pages belong in a connected workspace, where the business system and its public presence can be developed together.
>
> AI helps propose a first draft. Visual editors let you examine and refine it. You decide which records and forms fit your process, configure the services you need, and choose when website pages are ready to publish. The product gives your expertise a place to become a system—not a reason to hand over your judgement.

zh-CN:

> 每个业务都有自己的信息、流程与品牌故事。Anysys 的出发点很简单：工具应当围绕实际工作而构建。专属记录、表单与网站页面汇聚到同一个工作空间，让业务系统与公开形象能够协同塑造。
>
> AI 协助提出初稿，可视化编辑器帮助你检查与完善。你判断哪些记录和表单适合业务，配置所需服务，决定网站页面何时发布。产品让业务经验有机会成为系统，判断权始终握在你手中。

Principles `kicker`: **How we approach the product / 我们的产品理念**; `heading`: **Powerful tools. Human direction. / 强大工具，由人掌舵。**; items:

- **Start with the work / 从实际工作出发** — **Describe what your business manages before deciding how the software should look. / 先明确业务要管理什么，再决定工具如何呈现。**
- **Keep drafts reviewable / 草稿始终可审核** — **AI proposals are a starting point. Review the details, change the content and choose when pages go live. / AI 方案只是起点。审核细节、修改内容，页面何时发布由你决定。**
- **Connect the inside and outside / 贯通业务内外** — **Build your business system and public website in one workspace, with services configured for your needs. / 在一个工作空间中构建业务系统与品牌网站，按需配置服务。**

Craft `heading`: **A workspace, not a finished template. / 是工作空间，也是你的构建起点。**; `body`: **Anysys gives you records, forms, website pages and configurable services to shape. The work remains editable, because your business keeps evolving. Your expertise sets the direction; the tools help you express it. / Anysys 提供记录、表单、网站页面与可配置的服务，由你塑造细节。业务持续发展，内容也能不断完善。你的经验定方向，工具帮助它落地。** `image_url`: `/site-images/anysys/anysys-about-idea-hero.svg`, `image_side: right`.

Closing: **Make your way of working the blueprint. / 让你的业务方式，成为设计蓝图。** + **Create a workspace around your expertise and your next idea. / 围绕业务经验与下一个构想，创建工作空间。** + signup. Do not invent founders, offices, founding year, team portraits, customer logos, growth metrics or mission outcomes.

### E. Contact — welcoming, honest and short

**3 sections**, preserving role ids: `home_site_contact_hero` (`hero_centered`), `home_site_contact_availability` (`rich_text`), `home_site_contact_cta` (`cta_band`). No artwork or contact-form simulation.

- Hero: `eyebrow` **Contact / 联系我们**; `headline` **A clear next step\nfor your next idea. / 下一个构想，\n从清晰的下一步开始。**; `subhead` **Explore what Anysys can do, understand the reference plans or start shaping your own workspace. / 了解 Anysys 的功能，查看方案参考，或开始构建自己的工作空间。**; `media_mode: none`; **both action pairs blank**. Left aligned, 800 px maximum.
- Availability: `heading` **Public contact channel / 公开联系渠道**; `body` **A public contact channel is not yet available. You can explore the platform and reference pricing using the links below. / 目前尚无公开联系渠道。你可以通过下方链接了解平台与方案参考。** Render as a compact editorial note with a 24 px h2, not an alert/error. It is fully visible before the next-step actions.
- Closing: `headline` **Find your starting point. / 找到适合你的起点。**; `body` **Explore the platform and pricing, or create a workspace to start building. / 了解平台与价格，或创建工作空间，开始构建。**; existing Create your workspace → signup, quiet panel.
- Within the Contact closing component, display existing **published nav links** to Platform and Pricing as two outline anchors alongside signup. Pass the localized saved nav-page records/hrefs as render context, not new marketing props or hardcoded destinations/copy. Only these two existing published pages qualify. Stack below `sm`; use a wrapping action group at desktop. If either is unpublished, omit that link rather than introducing a dead destination.
- There is no submitted/sent/loading/success state because this page collects no enquiry. Never imply that signup contacts a sales team, reserves a demo or joins a Windows waiting list.

## 6. Shared Windows panel and artwork policy

Both Home and Platform keep `card_grid` props and render a compact “perspective” layout: `kicker` as status badge, `heading`, `subhead`, three plain text entries from `cards`, one primary image from the first card. Layout: `rounded-2xl bg-slate-50 border border-slate-200 p-6 lg:p-9`; copy `lg:col-span-7`, image `lg:col-span-5`, native 8:5. Stack copy before image on mobile. It is an upcoming-product note, not a second main hero.

| Prop | EN | zh-CN |
|---|---|---|
| kicker | Windows .exe · Coming soon | Windows .exe · 即将推出 |
| heading | Your workspace. Your own hardware. | 你的工作空间，运行在自有设备。 |
| subhead | The upcoming Windows app is being built for local hosting. It is not yet available to download. | 即将推出的 Windows 应用面向本地部署，目前尚未提供下载。 |
| cards[0].title | Local hosting | 本地部署 |
| cards[0].body | Run your workspace on a computer you manage in the upcoming app. | 在即将推出的应用中，将工作空间部署在自己管理的电脑上。 |
| cards[1].title | Control of your records | 自主掌控记录 |
| cards[1].body | Keep locally hosted records on hardware you control. | 将本地部署的记录保存在自己掌控的设备上。 |
| cards[2].title | Private—even from Anysys | 私密，Anysys 也无法访问 |
| cards[2].body | The upcoming app is intended to keep locally hosted records outside Anysys's access. | 即将推出的应用旨在让本地部署记录对 Anysys 同样保持私密。 |

Assign `/site-images/anysys/anysys-local-desktop.svg` to all three `cards[*].image_url` fields in the source. This prevents existing `Media.fill` from inventing stock images on Save. The scoped panel renders the first image once; repeated image paths are not repeated placements. All card href fields are blank. Distinct custom media on later cards renders as compact supplementary content; other bundled artwork is not a supplementary authored image. Text entries are `space-y-4`, h3 16 px, body 14 px. Keep the future/local-hosting scope together with the privacy statement. Existing FAQ notes cover forthcoming AI/external-service/backup details; no offline guarantee, launch date or download CTA.

**Default artwork budget: five rendered placements, four unique assets.** Home: brand-studio + local-desktop; Platform: review-publish + local-desktop; About: about-idea; Pricing/Contact: none. There are nine stored image assignments because the two Windows sections each repeat their chosen path in three card props; only their first image renders. Preserve all 15 bundled assets physically; not being assigned is not a reason to delete them. None is attached to steps or capability entries.

Art frame `relative aspect-[8/5] w-full overflow-hidden rounded-2xl`, `border border-violet-100/70` only if the asset needs a visible edge. No added inner browser title bar or double card frame. The illustration itself supplies dimensionality; use no outer shadow, or at most `shadow-sm`. Reuse `render_media` for custom media and localized labels. Do not render the full home SVG into an 8:5 crop: its viewBox is wide and it is no longer a selected slot.

Custom uploads/HTTPS images remain meaningful authored content. During explicit application, map custom media on surviving website/desktop/about roles to the new media-bearing sections. If multiple custom images must survive in a desktop section, render supplementary image-bearing cards compactly after its lead, with real stored alt context; do not silently discard them. Export existing content before restructuring, retain media blobs, and record any removed-slot media in the content-application report. The five-placement budget is for the source defaults, not a license to erase authored media.

## 7. FAQ content and interaction

Home has **three** entries, exact paired copy:

1. **Do I need to know how to code? / 需要会编程吗？** — **Start with your expertise in plain language. AI helps draft your system and website; visual editors let you review and refine them. / 从业务经验出发，用自然语言描述需求。AI 协助起草系统与网站，可视化编辑器帮助你审核和完善。**
2. **Can I review pages before publishing? / 发布前可以审核页面吗？** — **Yes. AI website proposals are editable drafts. Preview and revise each page before publishing. / 可以。AI 提出的网站方案是可编辑草稿，发布前可逐页预览与修改。**
3. **Can I download the Windows app? / 可以下载 Windows 应用吗？** — **The Windows .exe app is coming soon and is not yet available to download. Details on AI connections, external services and backups will be shared before release. / Windows .exe 应用即将推出，目前尚未提供下载。AI 连接、外部服务与备份的具体说明，将在发布前提供。**

Home title: **A few things worth knowing. / 开始前，了解这几件事。**; blank kicker. Pricing keeps the current four detailed entries, as specified above.

Layout `grid gap-6 lg:grid-cols-12 lg:gap-12`; heading 4 columns, question list 8. No sticky FAQ title. Rows `border-b border-slate-200`; `<summary>` `flex min-h-14 items-center justify-between gap-4 py-4 text-base leading-6 font-medium text-slate-900 cursor-pointer` with focus ring. Plus icon `size-4 shrink-0 text-slate-500`, rotate on open with `motion-safe:transition-transform`; answer `pb-5 pr-8 text-base leading-7 text-slate-600 whitespace-pre-line`. All closed initially; multiple rows may open. Preserve native keyboard behavior, no accordion JS or manually conflicting expanded state.

## 8. Desktop and mobile region mockups

ASCII conveys hierarchy, not literal fixed heights. Desktop is 1440; mobile is 390. Every region grows with copy and zoom.

### Home

```text
DESKTOP
Anysys       Home Platform Pricing About Contact       EN v  [Start building]
             AI-assisted systems & websites
                         Your business.
                        Built your way.             <- violet second line
               Specific offer + reviewable-draft explanation
                   [Start building] [Explore the platform]
One brief. Three connected drafts.
+---------------------------- Illustrative example -------------------------+
| Your brief           | Connected drafts                                   |
| Membership request   | Member records    Registration form   Public website|
| (readable text)      | [Draft] fields    [Draft] fields       [Draft] pages |
|------------------------ AI proposes. You review. --------------------------|
+---------------------------------------------------------------------------+
The system behind your business. The website in front of it.
01 Records & forms       02 Your public presence       03 Configured services
------------------       -----------------------       ----------------------
Make the first impression yours.      [one brand-studio artwork, 8:5]
Specific authoring paragraph
Start with your expertise.
01 Describe ---------------- 02 Review ---------------- 03 Publish
+---------------------- Windows .exe · Coming soon --------------------------+
| Heading + status + three short benefits       [one local-desktop artwork] |
+---------------------------------------------------------------------------+
A few things worth knowing.           Question + / Question + / Question +
+------------------------- slate closing panel -----------------------------+
| Build around what makes your business different.       [Create workspace] |
+---------------------------------------------------------------------------+
Brand / concise blurb                         Product / Company / Desktop

MOBILE
Anysys                                        EN v  menu
             Eyebrow
          Your business.
         Built your way.
          Offer paragraph
        [Start building]
     [Explore the platform]
One brief. Three connected drafts.
+----------------------------+
| Illustrative example       |
| Your brief + request       |
| Connected drafts           |
| Member records     [Draft] |
| field outline              |
| Registration form  [Draft] |
| field outline              |
| Public website     [Draft] |
| page outline               |
| AI review note             |
+----------------------------+
Capability title + 3 ruled entries
Website story text
[one landscape artwork]
Process title + 3 numbered rows
Windows status + text entries
[one landscape artwork]
FAQ title + 3 native details
Short closing + [Create workspace]
Compact stacked footer
```

### Platform

```text
DESKTOP                                  MOBILE
Shared header                            Header
Centered text hero + signup/pricing       Text hero + stacked actions
Detailed brief -> three draft outlines   Brief / three draft outlines
Capability title + language/voice note   Capability intro + note
01 Records/forms | 02 Website builder    Four ruled capability entries
03 Members/payments | 04 Email/SMS       Website story text
[review artwork] | Website story text   [one landscape review artwork]
Describe -------- Review ------- Publish Three numbered process rows
Windows compact two-column perspective  Windows text + landscape image
Horizontal closing / footer             Closing / footer
```

### Pricing

```text
DESKTOP                                  MOBILE
Header                                  Header
Pricing / concise h1                    Pricing / concise h1
Visible USD reference note              Visible reference note
Compare reference plans                 Compare reference plans
Free    Starter [Recommended] Pro Ent.   Free / $0 / limits / CTA
$0      $29                 $99 $499     Starter / $29 / limits / CTA
limits  limits              ... ...     Pro / $99 / limits / CTA
[CTA]   [CTA]               ... ...     Enterprise / $499 / limits / CTA
Plan details | four FAQ rows             Plan details / four FAQ rows
Short closing / footer                   Short closing / footer
```

### About

```text
DESKTOP                                  MOBILE
Header                                  Header
Left-aligned text hero                  Left-aligned text hero
Mission title | two substantive paras   Mission title + paragraphs
Slate-50 band: principles 01 / 02 / 03   Principles title + three ruled entries
Craft text | one idea artwork           Craft text / landscape idea artwork
Horizontal closing / footer             Closing / footer
```

### Contact

```text
DESKTOP                                  MOBILE
Header                                  Header
Contact / left-aligned text hero         Contact / text hero
Channel title | honest availability     Channel title / availability note
Quiet next-step panel                   Quiet next-step panel
Starting-point copy | Platform Pricing   Starting-point copy
                    | Create workspace  [Platform] [Pricing] [Create workspace]
Compact footer                           Compact footer
```

## 9. Component, dispatcher and props contract

### Chosen integration

Add `Websites::HomeSite::Presentation` in `app/services/websites/home_site/presentation.rb` as a thin, non-mutating presentation resolver. It applies **only** when the rendered website/page belongs to `HomeSite::CUSTOMER_ID` and the page is the saved home row or has slug `platform`, `pricing`, `about`, or `contact`. Use the actual record customer/site identity, not `Current.customer`, a substring of the request path, section ids or English wording. Pass this resolved context explicitly through public and same-page admin preview rendering.

`Websites::PageComponent` still iterates normalized saved sections in their saved order, first checking `SectionKit.known?`. For known mapped types in this scoped context, resolve the isolated component below; otherwise use `SectionKit.component_class(type)`. Never synthesize missing sections, pair adjacent sections into a hidden layout, restore props on read, or remove custom inserted known section types. Header/footer select their scoped presentations using the same context. No new stored presentation token, schema field, route, database column or globally revised Theme/PublicComponent constants.

Proposed `Websites::HomeSite::SectionComponent` extends the existing SectionComponent and centralizes the isolated container, typography and CTA utilities. It uses existing prop/list/href/media helpers. Pass `variant:` as an internal Ruby enum from the resolver (not saved marketing text). `hero_centered` variants: `:lead`, `:pricing`, `:editorial`; `feature_grid`: `:capabilities`, `:principles`; `steps`: `:process`; `rich_text`: `:editorial`, `:contact_note`; `cta_band`: `:closing`, `:contact_next_steps`. Variant changes spacing/composition only. All render-visible copy comes from stored props, localized nav records or existing runtime I18n chrome keys.

| Stored type | New isolated component | Exact consumed props / context |
|---|---|---|
| `hero_centered` | `Websites::HomeSite::HeroComponent` | `eyebrow`, `headline`, `subhead`, `media_mode`, `image_url`, `primary_label/href`, `secondary_label/href`; `variant`, page role. With `none`, render no image frame. |
| `ai_preview` | `Websites::HomeSite::DraftComponent` | `kicker`, `heading`, `subhead`, `example_label`, `prompt_label`, `prompt`, `review_note`, `output_label`; `items[{title,body,status}]`. |
| `feature_grid`, `steps` | `Websites::HomeSite::IndexComponent` | `kicker`, `heading`, `subhead`, `items[{title,body}]`; variant capabilities/principles/process. Decorative ordinal derives from saved array index. |
| `split_image_text`, `rich_text` | `Websites::HomeSite::StoryComponent` | `heading`, `body`; optional `image_url`, `image_side`; variant story/editorial/contact_note. Escaped blank-line-separated paragraphs. |
| `card_grid` | `Websites::HomeSite::PerspectiveComponent` | `kicker`, `heading`, `subhead`, `cards[{title,body,image_url,href}]`; optional media on first card, supplementary authored media retained. No Windows-specific literal copy in component. |
| `pricing` | `Websites::HomeSite::PlansComponent` | `kicker`, `heading`, `subhead`, `featured_label`, `tiers[{name,price,cadence,body,features,button_label,button_href,highlight}]`. Features remain newline-separated strings. |
| `faq` | `Websites::HomeSite::FaqComponent` | `kicker`, `heading`, `items[{question,answer}]`; native details. |
| `cta_band` | `Websites::HomeSite::CtaComponent` | `headline`, `body`, `button_label`, `button_href`; variant closing/contact_next_steps; latter receives resolved localized nav-link context. |
| Chrome | `Websites::HomeSite::HeaderComponent`, `FooterComponent` | Existing website, theme, saved localized nav pages/current slug, preview/embed context; header signup uses runtime existing actions.start I18n key. Footer consumes saved footer columns/blurb/tagline. |

Thus **eight section ViewComponents**, two chrome components and a shared scoped base are sufficient; the renderer dispatches content types, not a bespoke full website. Reuse `LanguageSwitcherComponent`, `MobileNavSheetComponent`, `IllustrationComponent`, `FittedPhotoComponent`, and the `PublicComponent#href_for` behavior. The existing generic sections/components and admin design tokens retain their styles. Embed preview continues to omit inappropriate chrome according to its existing conventions.

### Layout specifics for the eight section components

- **Hero:** one h1, naturally wrapping text; Home centered with the explicit line treatment; Platform centered slate; other pages left aligned. Blank action labels/hrefs omit their group, not a spacer. `media_mode: none` is stored on all five source heroes. Hero images may remain stored/custom, but none mode does not display them; move meaningful custom media to a story during application.
- **Draft:** heading outside the board, left aligned. Board `rounded-2xl border border-slate-200 bg-white shadow-sm`; top caption row `px-5 py-3 border-b`; content `p-5 lg:p-6 grid gap-5 lg:grid-cols-12`. Prompt 4 columns, right output 8. Prompt `rounded-xl bg-violet-50 p-5`, label 14 px, request `text-lg leading-7 font-medium text-slate-900`. Outputs `grid gap-3 lg:grid-cols-3`, each `rounded-xl border border-slate-200 p-4`; title/status row wraps, body 14 px. Output caption outside these cards. Bottom full-width review note `border-t px-5 py-3 text-sm leading-6 text-slate-600`. No fake window dots or image assets. On mobile outputs stack, retaining compact heights and full text. Every nonblank heading/label remains readable without hover.
- **Index:** header left; body `grid gap-x-8 gap-y-6 md:grid-cols-2 lg:grid-cols-3` for 3 entries; four entries stay 2×2. Each `border-t border-slate-200 pt-5`, ordinal `text-sm font-medium text-violet-800`, h3 `mt-2`, body `mt-2`. Process uses semantic `<ol>` and a horizontal rule, not three closed cards. Principles uses a full-width slate-50 band; no icon art. Do not claim any card is a working module shortcut.
- **Story:** with media use 5/7 split and native 8:5 artwork; copy first on mobile, `image_side` controls desktop order. Without media use 4/8 title/prose editorial split. Paragraph gap 20 px. Contact note `py-6 lg:py-8` and a 24 px heading. Invalid/blank story image omits the image column and expands readable copy; do not introduce a stock photo or placeholder demo.
- **Perspective:** copy-first 7/5 panel specified above. Optional first image fits native 8:5; no tripled artwork default. All card bodies are shown in an unboxed list; do not derive an upcoming badge from body-text matching.
- **Plans:** four compact cards, actual props, source-derived data and styling specified in Pricing. Blank badge text falls back to existing translated featured-label behavior. Empty tiers produce just supplied section copy, with no fabricated plan or price.
- **FAQ:** native semantics and exact row styling in §7. No answer truncation or read-more navigation.
- **CTA:** wrapping horizontal layout `flex flex-col gap-6 lg:flex-row lg:items-center lg:justify-between`; h2 and body stacked on left, anchor on right. Contact resolved nav links follow the visible availability note and preserve locale.

Optional fields omit cleanly. Empty lists do not produce phantom filler cards. Missing/invalid media keeps the text and accessible action; missing or invalid CTA href produces ordinary label text without button styling. There are no async marketing loading states. Preserve existing empty 404 for disabled/unpublished/missing public pages; do not introduce an authorization interstitial for public content.

## 10. Localization, source application and edit ownership

### Source/backend owner

- Update `app/services/websites/home_site.rb`: new section sequences/types above, role-specific hero actions/media mode, compact shared Windows props, and **pricing tiers only on Pricing**. Preserve `PAGE_KEYS`, tenant hard lock, signup destination, call-time I18n and StandardPlans derivation. No live-billing query or seed alignment.
- Update both `config/locales/website_home_site.en.yml` and `.zh-CN.yml` with every exact string in this document. Preserve interpolation variables and key/array parity. Reuse existing keys for identical wording; existing generic action labels remain byte-identical. Do not bake translated strings into Ruby constants.
- Header source I18n key, current-year footer output, mobile-nav open/close labels and locale accessibility labels resolve at request time. All display text in section components remains prop-backed; no demo field labels or marketing copy hidden inside Ruby/ERB.
- Keep `HomeSiteLocalization` exact-match, read-only behavior. All chosen leaf names are already in `TEXT_KEYS`; URLs, image paths and control props are not translated. Test newline bodies/headlines and new feature-grid arrays in both locales, including reordered items and literal owner edits. Do not localize by saved list position.
- Explicitly apply the authorized new composition to the five target saved pages. The existing `HomeSite.apply!` is a full source restore and can replace structure; review/update its id preservation so repeated same-type sections map by semantic role, not accidentally by “first section of this type.” Match saved old ids/source ids before structural replacement; new semantic sections get stable source ids. Do not reuse the old copy-only leaf patcher for a structural redesign.
- Take a before-content export, rehome meaningful custom media as above, and write a role/id/media application report. Save through the existing activities/transaction path. Source definition changes and persisted content application are both required for live bilingual output. Preserve the Website/WebsitePage row identities; other tenants and extra target-site pages are outside this source replacement.

### Frontend owner

- Implement `app/components/websites/home_site/` with the component map above and complete class literals for Tailwind discovery.
- Add the presentation resolver and the small explicit dispatcher/chrome hook in `PageComponent` / `app/views/websites/pages/show.html.erb`; ensure existing admin preview uses the same scoped page identity. No admin layout/theme changes, general public Theme retuning or new route.
- Reuse native details, existing locale-switch links and existing mobile navigation. No additional Stimulus controller or JavaScript edit is required.
- All content editing remains through current `SectionFields` keys; no new hidden prop, editor tab, universal catalog section or assistant schema vocabulary is necessary. The source only rearranges known section types and fills their existing fields. Pass the same scoped presentation context to the target composer and override only the existing `headline` control's kind to `:textarea` in its field-schema presentation. Other tenants retain their current input/schema/UI. This preserves stored headline newlines without changing `website_builder_controller.js`.

### QA/release owner

- Update affected `spec/services/websites/home_site_spec.rb` expectations: section counts **8/7/4/5/3**, five text-only heroes, nine source image assignments yielding five rendered placements, catalog-derived plans only on Pricing and revised source copy. Retain artwork-content/security assertions for all existing assets without requiring every asset to be assigned to a page. Verify a real builder Save retains multiline headlines and adds no stock photo.
- Cover scoped dispatcher/chrome behavior, other-tenant fallbacks, arbitrary known inserted sections, literal owner copy, locale propagation and custom-media rendering in relevant component/request/localization specs. Run only affected layers; no JS coverage run needed when JS is unchanged.
- Update **both** `doc/reference/en/website-builder.md` and `doc/reference/zh-CN/website-builder.md` in implementation: section counts, page compositions, scoped components/dispatch, image-role table/budget, text-only heroes, dedicated pricing, localization and authorized structural-application workflow. The current claims that order/types/27 assignments remain unchanged become obsolete.
- Rebuild Tailwind, follow the existing development asset-shadowing/server procedure if needed, and verify fresh fully loaded screenshots. This UX artifact itself changes no production source, records or developer reference behavior.

## 11. Interaction flows, accessibility and acceptance

### Real visitor flows

| Start → action | Outcome / next URL |
|---|---|
| Any page → header/mobile-sheet Start building | Existing `/auth/sign_up`, with selected locale. Existing signup validation remains owned by auth; no promise of a purchased/free plan. |
| Home → Explore the platform | Existing `/81721200/site/platform`, same locale. |
| Platform → See pricing | Existing `/81721200/site/pricing`, same locale. |
| Pricing → any tier CTA | Signup only; no checkout or preselected plan. |
| Contact → Platform / Pricing | Existing published marketing page in the same locale; unavailable nav item omitted. |
| Any page → language choice | Same current URL in selected request locale; source-identical copy translates, custom wording remains literal. |
| FAQ → summary | Native open/close in place; several answers may remain open. |
| Mobile → menu / nav link | Existing accessible sheet opens, link navigates; Escape/close restores focus per existing controller. |

The illustrative board has no click-to-generate flow. Service-provider failures and form validation do not occur on static marketing pages. An unavailable/unpublished site or page retains its existing empty 404; external font/image failure must leave usable text, actions and layout. No modal is introduced.

### Accessibility

- One h1 per page; sensible h2/h3 nesting. Give the sole `<main>` `id="site-main"` and `tabindex="-1"`. Scoped header skip link targets `#site-main`, reusing `chrome.skip_to_content` (**Skip to main content / 跳到主要内容**). Classes: `sr-only focus:not-sr-only focus:fixed focus:left-5 focus:top-3 focus:z-50 focus:rounded-lg focus:bg-white focus:px-4 focus:py-3 focus:text-slate-950 focus:ring-2 focus:ring-violet-600`.
- All navigation/action targets ≥44×44 px; FAQ summaries span their entire row. No opacity-only disabled links or decorative controls with button semantics.
- Text contrast: normal text ≥4.5:1; large text and meaningful boundaries/focus ≥3:1. Use slate-600 body on white/slate-50, violet-800 status on violet-50, white on violet-700. Verify computed colors, including hover/focus states.
- Keep focus rings visible. Native details retain keyboard interaction; decorative icons/ordinals/artwork overlays are `aria-hidden`. Draft and Coming soon meanings are visible words, not color alone.
- Art adjacent to equivalent text may be decorative (`alt=""`); otherwise use the localized stored heading/title as existing helper context. Do not repeat every SVG nameplate to screen readers. Preserve meaningful authored media context.
- No reduced-motion-dependent content, automatic animation, parallax, hover-only explanation, cropped text, line clamp or tiny pseudo-UI label. Use motion-safe only for minor transition effects. At 200% zoom, allow every region/card/action to grow and reflow.

### Objective visual acceptance

Evaluate at **320, 390, 768, 1024 and 1440 px**, both locales. Capture full page and first viewport after scrolling/loading all images. These are acceptance targets for the unedited source copy at normal zoom, not fixed heights to enforce in CSS:

1. **Material change:** Home's first view contains a text-first hero and visible connected HTML draft content; none of the five pages begins with a giant browser-framed illustration. The board starts by approximately y=600 at 1440×900; the brief and three draft titles/statuses are visible before the viewport ends.
2. **Pricing immediacy:** At 1440×900 all four names, prices, reference note, quotas and CTAs fit in the first viewport; plan cards start by y=360. At 390×844, the reference note and at least the first plan's name/price are visible without scrolling. No annual/monthly selector or purchase implication.
3. **Length budget:** At 1440, full Home ≤3,800 px, Platform ≤3,800, Pricing ≤2,100, About ≤2,700 and Contact ≤1,300. At 390, Home/Platform ≤5,200, Pricing ≤3,100, About ≤3,400 and Contact ≤1,700. Do not achieve this by hiding content or shrinking body text; tighten gaps and remove redundant wrappers. Chinese need not match English pixel heights.
4. **Artwork restraint:** Default placements exactly Home 2 / Platform 2 / Pricing 0 / About 1 / Contact 0. All 15 existing artwork files remain available. Each selected art frame is native 8:5 and subordinate to the text; no hover crop changes.
5. **Section rhythm:** Home clearly alternates typographic lead → bordered draft board → unboxed ruled index → single media story → compact numbered process → quiet upcoming-product panel → native FAQ → horizontal slate closing. No three consecutive illustrated-card sections or repeated giant centered h2s.
6. **Contact clarity:** At 1440×900 and 390×844 the actual availability note is visible. Platform/Pricing/signup actions are useful real destinations, and none is labeled Send, Book, Chat or Download.
7. **Readability:** Body ≥16 px except clearly secondary draft/plan/detail text ≥14 px and status labels ≥12 px. No text overlaps its parent/action box; headings have intentional balanced line lengths in both languages. Chinese normal tracking, full-width punctuation and professional terminology.
8. **Responsive integrity:** No document horizontal overflow; no clipping at 320 or 200% zoom. Pricing is 1/2/4 columns, draft outputs 1/3, capability entries 1/2/3 (four-item grid stays 2×2), and all stories stack copy-first below `lg`.
9. **Behavioral integrity:** Every CTA resolves through existing link helpers and preserves explicit locale. Drafts stay visible/static. Windows status remains future-scoped. Reference plan data match StandardPlans without reading live offers.
10. **Isolation/editability:** A control tenant's website and admin screenshots remain unchanged. Saving a target section in the builder preserves every displayed text/image/action field and its id/type. Public rendering performs no database write, seed or source restore. Review all five pages as saved content, not source hashes alone.

Final visual review should compare the fresh baseline files named in §2 with implementation screenshots at identical viewport/locale. This is a precise design specification; the proposed appearance has not yet been implemented or browser-validated.

## 12. Approved release refinement — 2026-10-06

The first release capture found compact admin font tokens, invisible closing headings, overlong mobile pages, and overflow/wordmark collisions at 150–195 CSS px. This amendment supersedes the utility names and spacing above where specified; content, saved section order, artwork and visual acceptance targets remain authoritative. It is an implementation refinement, not a fresh visual-pass claim.

- Use explicit `text-[16px]` body/action, `text-[18px]` lead/card-title, `text-[14px]` detail/nav/footer, `text-[12px]` badge/copyright, `text-[20px]` wordmark and `text-[24px]` compact-heading utilities. Body leading is 26 px, lead 28 px, draft/detail 22 px; pricing features use 20 px leading and 6 px gaps. The app's named text utilities have smaller values. Do not retune global tokens.
- Closing h2 explicitly uses `text-white` on slate-950, or `text-slate-950` for Contact. Normal-width headline sizes remain unchanged; below 280 CSS px, h1 is 28 px, section/closing headings 26 px and plan prices 32 px, with anywhere wrapping and `min-w-0`.
- Main section padding becomes `py-10 lg:py-14`; indexes/perspective/FAQ `py-8 lg:py-14`; process `py-6 lg:py-10` with decorative numbers beside the title/prose; Pricing FAQ/closing `py-6 lg:py-10`. Draft outer padding is `pb-8 lg:pb-12`, compact mobile cards/prompt use 12/16 px padding, and captions use 8 px vertical padding. Closing outer spacing is `py-8 lg:py-10`; footer `py-6 lg:py-8` with three columns from 380 px, two from 280 px, otherwise one. Plan cards use 16 px gaps and no mobile body minimum-height spacer.
- Pricing uses §5C's shortened paired headline/note, `pt-8 pb-5 lg:pt-10 lg:pb-6`, a 1040 px headline measure and 900 px reference-note measure; note font is 16 px/24 px leading. The comparison title-to-cards gap is 20 px. All prices, trials, limits and qualifiers remain fully visible.
- Below 280 CSS px, header brand is a full first row and controls wrap on a second row; use automatic height, explicit 20 px wordmark, and minimum 44 px touch targets. Locale menus are viewport-bounded, nested panel/button padding reduces, and footer links have `min-w-11` as well as `min-h-11`. Reflow must work at 150 px without hiding content or masking document overflow.
- Apply only the two pricing-hero text leaves that exactly match the previous EN/zh-CN source, through SavePage, preserving IDs, order and all other content. Release rebuilds/captures afterwards and rechecks §11's first-viewport and length budgets with the corrected readable sizes.

## 13. Approved native mobile-navigation refinement — 2026-10-06

The implemented scoped mobile sheet uses a native `<dialog>` to give the existing navigation browser-owned modal focus and an inert background. This supersedes the original no-JavaScript-change/no-new-modal assumptions in §§1, 10 and 11; §12's typography, spacing and pricing refinements remain intact. Public rendering, admin preview and the composer integration are implemented; source application remains explicit rather than a render-time operation.

The existing `website_nav_controller.js` now detects native dialog support and calls `showModal()`/`close()`. The close button has autofocus; native `cancel` handles Escape through controller cleanup. Only direct clicks on the transparent full-viewport dialog dismiss the backdrop, not inner-sheet clicks. Close restores root overflow and visible-trigger focus; resize to 1024 px and controller disconnect close/unlock the modal. The browser owns Tab/Shift+Tab navigation and background inertness, including rejection of programmatic background focus; browser-chrome focus at the Tab boundary is permitted. Generic div sheets retain their existing presentation, with no new controller or saved props.

Controller state/API/cleanup coverage belongs to `spec/javascript/controllers/website_nav_controller.test.js` with mandatory 100% Vitest lines/branches/functions. Actual modal focus, inertness and sequential navigation are covered by `spec/e2e/website_native_dialog.app.spec.js` at 320/390/768 px in both locales, together with backdrop/close, desktop-resize and disconnect behavior. The browser spec blocks non-GET/HEAD requests; unit API mocks are not evidence of native focus behavior.

# Anysys home-site refresh — product brief and UX specification

Date: 2026-10-03 · Scope: research/design · Customer: `81721200`

## Decision

Build a premium, product-led SaaS site with **eight home sections**, a white/neutral canvas, restrained violet accents, a concrete AI-to-system-and-website illustration, and useful pricing. Keep all five published, builder-backed pages and `Websites::HomeSite.apply!` as the reproducible source backup. Recommend **one optional reusable section**, `ai_preview`; every other section uses the current kit with small generic improvements.

## 1. Product-owner brief

### Problem statement

Prospective customer admins need to understand how Anysys helps them build a working system and its public website, judge the offering, and create a workspace. The current 15-section home repeats capabilities, uses unrelated villa/lake photography and invented testimonials, and presents an unavailable desktop download as released. Replace this with concrete product storytelling, a shorter decision path, accurate pricing, and an unmistakably upcoming local-data Windows app.

### User stories and acceptance criteria

1. **As an admin, I want to understand what AI creates, so I can judge whether Anysys fits my organisation.**
   - The hero names both the system and website outcomes.
   - One labeled illustrative example connects a plain-language request to records, a registration form, and public pages.
   - The example describes reviewable drafts, without promising instantaneous completion.
2. **As an admin, I want to compare plans and start registration, so I can evaluate Anysys.**
   - Home shows three self-service plans; Pricing shows all four catalog plans.
   - Each signup CTA reaches `/auth/sign_up`; no CTA implies a plan was selected or charged.
   - Currency, cadence, and limits agree across both pages and with the approved billing catalog.
3. **As a member, I want to understand desktop availability and privacy, so I do not mistake a planned feature for today's cloud service.**
   - Every desktop mention includes “Coming soon” in the current locale.
   - The feature names Windows `.exe` and the planned local-workspace-data benefit.
   - No download link, fake waitlist, or present-tense absolute privacy guarantee is rendered.
4. **As the owner, I want five editable, reproducible marketing pages, so I can maintain the site through the builder.**
   - Home, Platform, Pricing, About, and Contact retain their routes and builder records.
   - Reapplying the source recreates the five pages without duplicates.
   - Both locales cover navigation, page content, pricing labels, preview text, accessibility labels, and SEO.

### Edge cases and error scenarios

- Anonymous visitors can read all five public pages; marketing links grant no admin/member permissions.
- Signed-in visitors follow the existing signup controller's role-appropriate redirect.
- Invalid email, expired confirmation, signup disabled, throttling, and email-provider failures stay in the existing authentication flow; marketing must not claim registration has succeeded.
- Missing verified contact information has an honest fallback below. Long Chinese copy must wrap without truncation.
- Builder edits remain authoritative during ordinary reads; visiting a page or changing language must never reseed it. Explicit source reapplication remains a deliberate owner operation.

### Out of scope

Desktop implementation/distribution, signup redesign, billing changes, live AI execution, lead-capture forms, new routes, analytics implementation, testimonials, and template-catalog redesign.

### Open questions

None blocking UX. Before publication, verify the deployed billing catalog and a real contact channel. The design provides a contact fallback and uses source-confirmed prices rather than invented offers.

## 2. Research and component constraints

- Read `home_site.rb`, Website public rendering/chrome, section registry/schema, theme, relevant section components, customer registration, and `Billing::StandardPlans`. The excluded page-layout-template directory was not used.
- Current `display` typography is serif. Set stored theme to **`light / violet / sans / compact`** for a clean product interface; use existing theme mappings rather than a customer-specific palette.
- `hero_centered` always renders a large 16:10 media frame. Introduce a generic opt-in `media_mode: none` (default remains `image`) for text-only heroes; omitting `image_url` alone creates a placeholder, not a compact hero. Register the field in the kit/schema with translated editor labels.
- `statement` is oversized editorial display typography; do not use it as a compact page introduction. `showcase_tiles`, `bento_grid`, and photo-led features would reintroduce large image slots.
- `pricing` already provides rounded, ringed cards, aligned subgrid rows, responsive columns, and a highlighted tier. `faq` already uses accessible native `details/summary`; retain that interaction.
- `Href` accepts page slugs and root-relative URLs. It does not accept bare fragment links. Use existing page slugs, not invented `#desktop` links.
- Billing source defines Free $0, Starter $29, Pro $99, Enterprise $499 **monthly**, with CNY equivalents ¥0 / ¥299 / ¥999 / ¥4999. Paid plans have 14-day trials. The current “Custom / annual” Enterprise and dedicated-success-manager promises are not supported by that source.
- shadcn MCP/skill tools are unavailable. Apply the parent's official Card guidance (ring-1, rounded cards, structured header/content/footer, consistent padding), plus official [Button](https://ui.shadcn.com/docs/components/button), [Badge](https://ui.shadcn.com/docs/components/badge), and [Accordion](https://ui.shadcn.com/docs/components/accordion) guidance consulted here. Translate the patterns into ViewComponent/Tailwind/native HTML, without introducing React.

## 3. Surface inventory and page maps

All five surfaces are **public**. Editing stays at the existing Website builder under `/:cid/admin/modules/website/pages`; its authorization remains owner/admin scoped.

### Shared chrome

Reuse `NavComponent`, `MobileNavSheetComponent`, `FooterComponent`, and `LocaleSwitcherComponent`. Keep the five page links in their current order. Brand links home. Footer has Product (Platform, Pricing, Start building), Company (About, Contact), and Desktop (a link labeled “Windows app — Coming soon” to `platform`). Remove the Download category. Use one short brand blurb; avoid repeating the hero paragraph.

Keep conversion actions in the hero, plans, footer, and final CTA; a new nav-action configuration is unnecessary. No destructive public actions.

### Home — `/81721200/site` — 8 sections

| # | Kit type | Content and layout |
|---|---|---|
| 1 | `hero_centered`, media off | Eyebrow “AI-powered system & website builder”; H1 “Your next system. Your next website. Built with AI.” One short subhead. Filled “Start building” → signup; outlined “Explore the platform” → `platform`. |
| 2 | `ai_preview` (recommended) | The visual centerpiece: one membership-business request becomes editable records, a signup form, and a public website. See specification below. |
| 3 | `feature_grid`, 3 items | “A website that belongs to your business.” Three outcomes: draft your pages, refine your brand, publish when ready. Keep each body to two short sentences; describe actual review/edit/publish controls. |
| 4 | `steps`, 3 items | “From idea to something you can use.” Describe → Review → Publish. One sentence per step; do not repeat the complete capability list. |
| 5 | `feature_grid`, 3 items | Eyebrow “Windows .exe · Coming soon”; heading “Your workspace. On your computer.” Subhead explicitly describes planned local workspace storage. Items: local records, control of local files, cloud available today. This is the only home desktop block. |
| 6 | `pricing`, 3 tiers | Free / Starter / Pro; Starter highlighted. Heading “Start small. Build what comes next.” Enterprise remains on the dedicated Pricing page, reachable in nav/footer. |
| 7 | `faq`, 4 items | Coding knowledge; review before publishing; what signup does; desktop availability. Answers are short and factual. |
| 8 | `cta_band` | “Make room for a better way to work.” One sentence and “Create your workspace” → signup. The only full dark accent panel on Home. |

### Platform — `/81721200/site/platform` — 6 sections

1. Text-only `hero_centered`: “One idea. A connected system and website.” Signup primary; Pricing secondary.
2. `ai_preview`: reuse the exact component with a more specific example, clearly labeled as illustrative; no second preview implementation.
3. `feature_grid` (3): records/forms, members/payments, email/SMS. Describe capabilities as configurable, without “single toggle” or delivery guarantees.
4. `steps` (3): draft the site, edit copy/theme, publish. Make the website outcome as prominent as business-system functionality.
5. `feature_grid` (3): the same upcoming Windows/local-data story, expanded to distinguish planned local storage from cloud and external services.
6. `cta_band`: create a workspace.

### Pricing — `/81721200/site/pricing` — 4 sections

1. Text-only `hero_centered`: “A clear starting point. Room to grow.” Concise cadence explanation; signup primary, Platform secondary.
2. `pricing` (4): Free / Starter / Pro / Enterprise, using catalog facts below.
3. `faq` (4): free limits; paid trial duration; what the counted resources mean; plan/currency details. Clarify that marketing-site pages and the separately counted page resource must not be conflated without verifying billing semantics.
4. `cta_band`: create a workspace; explain that plan selection happens after signup where supported.

### About — `/81721200/site/about` — 4 sections

1. Text-only `hero_centered`: “Software should fit the way you work.” Signup primary, Platform secondary.
2. `rich_text`: a short product mission, maximum two paragraphs. No invented founder biography, team photographs, or placeholder story.
3. `feature_grid` (3): start with your idea; stay in control; build a connected experience. Concrete principles rather than numerical proof.
4. `cta_band`: create a workspace.

### Contact — `/81721200/site/contact` — 3 sections

1. Text-only `hero_centered`: “Let's talk about what you want to build.” Platform secondary; signup primary.
2. `contact_info` only with a verified public email; hide absent address/phone/hours. If none is configured, use `rich_text`: “A public contact channel will be listed here when available. You can explore the platform or create a workspace today.” Preserve the page without a dead contact action. No `hello@example.com`, invented office hours, or decorative form.
3. `cta_band`: try the product. No promised response time.

## 4. Exact visual direction

- **Canvas:** white, neutral-950 headings, neutral-600 body, neutral-50 supporting panels. Violet-600 primary actions, violet-50 status/prompt surfaces, violet-950 final CTA. Accent is for decisions and hierarchy, not every paragraph.
- **Measure:** existing `max-w-7xl mx-auto min-w-0 px-5 sm:px-8 lg:px-12`. Hero headline `max-w-4xl`; reading copy `max-w-2xl`. No full-viewport photography.
- **Typography:** existing `text-site-*` tokens; hero `text-site-4xl sm:text-site-5xl lg:text-site-6xl`, sans semibold with tight tracking and `text-balance`. Section headings `text-site-3xl md:text-site-4xl`. Body 16–18px-equivalent tokens and relaxed line height; no forced English line breaks that break Chinese.
- **Rhythm:** standard sections use compact `py-16 md:py-24`; text-only hero `pt-14 pb-8 md:pt-20 md:pb-10`; preview `pt-4 pb-16 md:pb-24` so hero and preview read as one opening. Add the smaller heading/padding rules to the generic media-off hero variant, not a customer selector. Eight varied sections replace the repeated large-image sequence.
- **Cards:** `rounded-2xl md:rounded-3xl ring-1 ring-neutral-900/10 p-6 md:p-8`; 24px desktop gaps. Keep the existing pricing card geometry/subgrid. Only preview and featured pricing get a restrained shadow. No floating ornaments, fake activity counters, autoplay, or parallax.
- **Actions:** preserve the project's rounded-full 48px buttons. Primary filled, secondary outlined, supplementary actions plain links. Navigation remains semantic anchors; status badges are noninteractive text. Visible `focus-visible` ring, sufficient contrast, and minimum 44px interactive targets.
- **Responsive:** at 375px, one column with full-width CTAs; at 768px, preview may remain stacked while three short feature columns fit; at 1024px+, preview becomes 5/7 columns and full pricing is four columns. At 320px and 200% zoom, text wraps and body has no horizontal scroll. Avoid fixed card heights and clipped Chinese labels.

### Optional single reusable section: `Websites::Sections::AiPreviewComponent`

**Recommendation: include it.** This is the product evidence the existing photo-centric kit lacks. It is an illustrative, static HTML composition, not a working assistant.

```text
             From a short brief to a useful first draft
 [Illustrative example]
 ┌ Your request ──────────────┐  ┌ Workspace preview ─────────────────┐
 │ Build a membership        │  │ Member records              Draft │
 │ workspace with signup     │  │ Names, contact details, status     │
 │ and a public website.     │  ├────────────────────────────────────┤
 │                           │  │ Registration form           Draft │
 │ Review and refine         │  │ Collect the details you need       │
 │ before publishing.        │  ├────────────────────────────────────┤
 └───────────────────────────┘  │ Public website              Draft │
                                │ Home, membership, contact         │
                                └────────────────────────────────────┘
```

Props: `kicker`, `heading`, `subhead`, `example_label`, `prompt_label`, `prompt`, `review_note`, `output_label`, and one `items` array of `{ title, body, status }` (1–4 entries). All text comes from props resolved through I18n; no Anysys name, membership-specific text, tenant id, or English fallback embedded in the renderer. Fields stay within the existing string-plus-array schema pattern. Render the public-website outcome as one of the same output cards, not a second custom engine.

Use a neutral framed surface, violet-tinted request card, white result cards, subtle dividers, and small secondary/outline-style Draft badges. Reading order is heading → request → review note → results. On mobile, stack naturally; don't miniaturize a desktop screenshot. Section heading is H2; no fake input, clickable Send button, tab bar, generation spinner, or success announcement. Decorative chrome is `aria-hidden`; meaningful text remains accessible.

Blank optional labels are omitted. Empty items hide the output group; no loading state is needed because rendering is server-side. Invalid props follow the existing composer validation flow. If the optional section is deferred, use a `steps` section for this example and keep the eight-section map; never substitute stock photography.

## 5. Copy, pricing, and localization

### Anchor copy — mandatory paired keys

Use `website.home_site.*` under `config/locales/website_home_site.en.yml` and `website_home_site.zh-CN.yml`. Extend these catalogs for every section field, feature line, status, footer link, page title, alt/ARIA label, and SEO field. The following establishes voice and exact primary messages:

| Key suffix | English | 简体中文 |
|---|---|---|
| `hero.eyebrow` | AI-powered system & website builder | AI 驱动的业务系统与网站构建平台 |
| `hero.headline` | Your next system. Your next website. Built with AI. | 用 AI，打造你的业务系统与网站。 |
| `hero.subhead` | Describe what your organisation needs. Use AI to draft your system and website, then review, refine, and publish. | 描述你的业务需求，让 AI 起草业务系统与网站，再由你审核、完善并发布。 |
| `actions.start` | Start building | 开始构建 |
| `actions.explore` | Explore the platform | 了解平台 |
| `actions.create` | Create your workspace | 创建工作空间 |
| `preview.example` | Illustrative example | 产品示意 |
| `preview.draft` | Draft | 草稿 |
| `preview.prompt_label` | Your request | 你的需求 |
| `preview.prompt` | Build a membership workspace with signup and a public website. | 创建会员管理工作空间，配备注册表单和公开网站。 |
| `preview.output_label` | Workspace preview | 工作空间预览 |
| `desktop.status` | Windows .exe · Coming soon | Windows .exe · 即将推出 |
| `desktop.headline` | Your workspace. On your computer. | 你的工作空间，运行在你的电脑上。 |
| `desktop.body` | A Windows desktop app is on the way, designed to keep workspace records on your computer. Local data privacy is the goal; details about AI, connected services, and backups will be shared before release. | Windows 桌面应用正在开发中，计划将工作空间记录保存在你的电脑上，注重本地数据隐私。AI、外部服务及备份的具体方式将在发布前说明。 |
| `desktop.availability` | Coming soon. No download is available yet. | 即将推出，暂未开放下载。 |
| `pricing.heading` | Start small. Build what comes next. | 轻松起步，随业务成长。 |
| `pricing.recommended` | Recommended | 推荐方案 |

Use “records”, “forms”, “pages”, “your workspace”, and “reviewable drafts”. Remove public references to entities, schemas, migrations, multi-tenancy, engines, generators, and flowcharts. Translate billable `entity` as “custom record types” / “自定义记录类型” without changing the resource being counted. Avoid universal guarantees such as “nothing ever leaves your device”, “even we can never see it”, “no lock-in”, or “every confirmation always lands”.

### Pricing treatment

- Home: Free $0 / Starter $29 / Pro $99 per month, explicitly USD; highlight **Starter** as “Recommended”, not unverified “Most popular”. Dedicated Pricing adds Enterprise $499/month. Use USD in both locales for the first version so language does not imply billing-currency selection; Chinese cadence explicitly says “美元／月”. If showing CNY later, use the configured currency rather than an inferred exchange rate.
- Show three factual limit rows in the same order: pages / custom record types / member seats. Catalog values: 10/5/1; 50/25/5; 500/200/25; unlimited for Enterprise. Verify what billing counts as a page before drafting its FAQ explanation.
- Paid-trial information can appear as body copy after verifying active catalog settings. Buttons say “Create your workspace”, not “Start Pro trial”: the existing signup route does not select a plan. Do not invent annual discounts, savings toggles, priority-support entitlements, or all-inclusive usage pricing.
- Add a generic optional `featured_label` prop to Pricing if needed, defaulting to its current I18n label for other uses; this site passes the translated “Recommended”. Do not change every tenant's badge copy.

### Persistence and locale behavior

`HomeSite` currently stores literal strings, while public components render those strings directly. Merely calling `I18n.t` once in `apply!` would freeze one language into the database. The refresh must resolve source-authored copy in the **request locale**, including nav/footer/SEO, without reconstructing pages on every request.

Recommended narrow approach: explicit translation references for seed-owned text leaves, resolved by one generic Website content resolver shared by public rendering and composer previews. Plain owner-authored literals pass through. Preserve references for untouched fields during editor save; a deliberate text edit becomes an ordinary literal override and is not replaced during reads. Both catalogs remain the source for bilingual default wording. Do not infer translations from English string equality, translate at constant-load time, or substitute entire page trees when `customer_id == 81721200`.

This is a localization seam, not a second marketing renderer. Keep layout, section ids/types, publication, editable props, and theme on the existing Website/WebsitePage records. Explicit `apply!` may restore source defaults as it does today.

## 6. Interaction and state flows

- **Understand → inspect:** Home → “Explore the platform” → `/81721200/site/platform` → Pricing or signup. The AI illustration is readable without JavaScript; it performs no requests.
- **Compare → register:** Home/Pricing → plan CTA → `/auth/sign_up` → enter email → existing check-email screen → confirmation link → normal onboarding/sign-in destination. Invalid email stays on the existing form; expired/reused links, resend throttling, disabled signup, and provider failure retain existing auth handling. Never show a marketing-only completion message or provision a second tenant for an authenticated visitor.
- **Desktop interest:** Home desktop block or footer → Platform → visible upcoming status and privacy explanation. No `/download/desktop` anywhere in rendered links, metadata, section props, or footer. No disabled element styled as a tempting download button and no promised release date.
- **Contact:** Contact → verified mail link opens the email client; if contact details are unavailable, the page gives the honest fallback and working Platform/signup actions. No form submission/loading state.
- **FAQ:** summary click, Enter, or Space toggles the answer; multiple answers may remain open. Respect reduced-motion preferences for the indicator.
- **Mobile menu:** trigger opens existing sheet; Escape/backdrop/link closes it; focus returns to trigger and page scroll is restored. Locale switch retains the current page and translates source-owned content without changing site records.
- **Editor:** owner opens existing page composer → edits a text field → previews → saves through current activities. Validation errors retain entered content. Other customers cannot edit these pages; members cannot enter admin editing routes. Missing/unpublished public pages retain existing 404 handling.

## 7. Implementation file recommendations

| Files | Recommended work |
|---|---|
| `app/services/websites/home_site.rb` | Replace five page compositions/copy references; new theme; remove obsolete download constant, testimonials, stock media, and unsupported claims; preserve reproducible `apply!` and existing page identities. |
| `config/locales/website_home_site.{en,zh-CN}.yml` (new) | Complete paired marketing-copy catalogs; only stable references in source constants. |
| `app/components/websites/sections/ai_preview_component.{rb,html.erb}` (optional new pair) | The single new reusable section described above. |
| `app/services/websites/section_kit.rb`, `section_fields.rb`; `app/services/websites/contracts/section.rb` as needed | Register/validate preview props, optional text-only hero media mode, and optional pricing featured label. Use existing validation patterns. |
| `app/components/websites/sections/hero_centered_component.{rb,html.erb}` | Generic opt-in compact text-only variant, including semantic H1; preserve existing media default. |
| `app/components/websites/sections/pricing_component.rb` | Optional translated featured-label override; retain existing card/subgrid treatment. |
| `app/services/websites/content_resolver.rb` (suggested), existing public/composer presentation entry points | Small, explicit I18n-reference resolution; apply consistently to sections, page titles, chrome, and SEO. No tenant-id-specific layout path. |
| `config/locales/website_editor.{en,zh-CN}.yml`, `website_kit.{en,zh-CN}.yml` as appropriate | Paired editor labels and kit descriptions for new generic fields/type. |
| `spec/services/websites/home_site_spec.rb`, affected Website component/service/request specs | Replace current assertions requiring 15 sections and the nonexistent download; verify localized rendering, signup targets, source reapplication, and generic component behavior. |
| `doc/reference/en/website-builder.md`, `doc/reference/zh-CN/website-builder.md` | Document composition, any new props/type, localization-reference behavior, and owner source-backup workflow alongside eventual code. |

Reuse `SectionHeaderComponent`, `SectionButtonsComponent`, existing Pricing/FeatureGrid/Steps/Faq/RichText/ContactInfo/CtaBand components, and Website chrome. No new Stimulus controller is needed. If existing navigation JavaScript changes during implementation, update its tests and meet the mandated line/branch coverage. Existing unrelated working-tree changes must be preserved.

## 8. Acceptance checklist for the implementation handoff

- Exactly five published builder-backed pages, ordered Home → Platform → Pricing → About → Contact. Source reapplication preserves ids where possible and never duplicates pages.
- Home has eight sections. Product illustration and website-building outcomes are identifiable before pricing; there are no decorative stock photos, fake customer names/quotes, or fabricated statistics.
- One H1 per page; text-only inner heroes contain no empty image frame. All five pages work at 375, 768, 1024, and 1440px in both locales; additionally check 320px and 200% zoom for overflow.
- Buttons wrap or stack cleanly; pricing cards retain readable features and aligned actions. Starter highlight is visible through text and ring, not color alone.
- Signup links resolve to `/auth/sign_up`; page links stay under `/81721200/site`; there are no broken download/contact/anchor links. Exercise anonymous and signed-in signup behavior.
- Every desktop mention, including footer and FAQ/SEO if present, communicates Coming soon. The `.exe` is described as planned Windows distribution; local-record privacy is distinct from unverified AI/network behavior.
- Locale switching translates seed-owned headings, nav, footer, preview labels, pricing words, and metadata immediately without reseeding. Edited literals remain intact; English/Chinese key sets and interpolation variables match.
- Keyboard navigation, menu focus restoration, visible focus rings, native FAQ toggling, reduced motion, and mobile tap targets work. Static content is usable without JavaScript.
- Targeted HomeSite, section/schema, localization, and public-request tests pass; include regression coverage that another customer's literal Website content renders normally. No test execution is claimed by this research-only document.

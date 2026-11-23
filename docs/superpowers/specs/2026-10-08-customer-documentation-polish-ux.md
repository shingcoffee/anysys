# Customer documentation polish — UX specification

- Date: 2026-10-08
- Status: Ready for frontend, backend, content, and screenshot capture
- Audience: Customer administrators; owner may read in the current customer context
- Navigation area: **admin → Help → Documentation**

## 1. Decision and design basis

Make `/81721200/admin/help/docs?locale=en` an inviting, goal-based guide homepage within the existing reader. Use localized guide metadata for cards, more readable article typography, concrete procedures, and six captioned screenshots. Apply the same experience at every authorized customer's documentation URL.

This is an additive polish specification. The earlier `2026-10-08-customer-documentation-ux.md` and implementation plan remain historical inputs. **Current source is the contract where terminology differs:** the reader uses `translation_scope`, the breadcrumb key is `customer_docs.breadcrumb.reference`, and customer links preserve `locale`. The PO's review covers all 13 guides; the agreed approach preserves the responsive reader shell, contents navigation, server search, and reading sequence.

### shadcn consultation, completed before design

The skill/MCP is unavailable here. Consulted the official pages directly:

- [Card](https://ui.shadcn.com/docs/components/card): Card → Header → Title/Description composition, bordered rounded surfaces, consistent inset and spacing. Translate this into existing Rails components.
- [Typography](https://ui.shadcn.com/docs/components/typography): the current page redirects to Typeset; adopt its size/leading/flow rhythm and layout-owned reading measure using Tailwind utilities.
- [Alert](https://ui.shadcn.com/docs/components/alert): clear title/description hierarchy for important information. Reuse existing `:::note` and `:::attention` callouts for action-specific explanations.

Local references: `DeveloperDocs::ReaderComponent`, `AdminPageComponent`, `CardComponent`, and the restrained surfaces/focus treatment in `Admin::Dashboard::ModuleCardComponent`. The app's `text-base` is **14px**, `text-sm` **13px**, and `text-xs` **11px**; explicit reading sizes below are intentional.

## 2. Surface inventory and layout

| Surface | Area | Location | Change |
| --- | --- | --- | --- |
| Customer documentation home | admin | `/:cid/admin/help/docs` and `/docs/overview` | Metadata-driven cards before the compact overview article |
| Customer guide reader | admin | `/:cid/admin/help/docs/:slug` | Reading typography; embedded screenshot figures |
| Native full-size screenshot | public static asset | `/help/docs/screenshots/{en,zh-CN}/<file>.png` | Browser image navigation from a native link |

Retain the dashboard chrome, AdminPage header/breadcrumb, 16rem contents rail from `lg`, 14rem heading rail from `xl`, below-`lg` Contents drawer, below-`xl` native section `details`, sticky rails, GET search, and previous/next cards. The only reader layout insertion is the home cards inside the center column, after existing inline section navigation and before `page.html`.

```text
Customer guide / current guide                 Existing AdminPage header
Title and outcome summary

Contents + Search    | [On this page: native details below xl] | On this page
Existing groups     | HOME ONLY                               | Existing anchors
and active item     | Choose your next task                    |
                    | Group label                              |
                    | [Task title         ] [Task title      ] |
                    | [Outcome description] [Outcome         ] |
                    | Other groups / cards                     |
                    |                                          |
                    | ARTICLE                                  |
                    | Before you start                         |
                    | Steps                                    |
                    |   Task subsection; numbered actions      |
                    |   [Screenshot, natural aspect ratio]     |
                    |   Caption             View full size     |
                    | What to expect / troubleshooting / links |
                    | [Previous]                     [Next]    |
```

### Homepage cards

- Show all **12 non-overview guides**, once each, in `CustomerDocs::Catalog.groups` order. Keep existing group keys/labels: `orientation`, `workspace`, `modules`, `administration`. The orientation group contains only `getting-started` in the card area.
- Titles are goal-based localized front-matter `title`; descriptions are localized front-matter `summary`. The content agent should make each summary a concise outcome rather than repeat its title.
- One full-card native anchor, same tab, containing title, summary, and a decorative trailing arrow. No nested links/buttons. Accessible name comes from the title; description from the summary. Example IDs: `customer-doc-guide-records-title` / `customer-doc-guide-records-summary`.
- Layout: `grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2`. A sole card spans the group width. Groups use `space-y-8`; heading-to-grid gap `3`. This avoids two cramped cards when the persistent contents rail first appears.
- Card: reuse `CardComponent(variant: :bordered, padding: :none)` inside a `block h-full rounded-xl` anchor. Inner padding `p-4 sm:p-5`; heading `text-[16px] font-semibold leading-6 text-text-primary`; description `mt-2 text-[14px] leading-6 text-text-secondary`. Natural height, wrapping, no truncation or line clamp. Use `bg-surface`, `border-border-subtle`, `shadow-xs`; hover accent border/subtle tint; anchor focus `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2`. No lift/scale animation.
- Section heading: `text-[20px] font-semibold leading-7 tracking-tight`; group label `text-[14px] font-medium text-text-secondary`. Keep cards outside the Markdown typography wrapper. The card area has its own labelled section; `page.headings` continues to describe Markdown sections only.
- Remove the 12-item duplicated guide list from both overview Markdown files. Retain all five required overview H2 sections as short orientation/recovery paragraphs and a few purposeful related links. The cards carry the directory; the article explains who the guide is for, how to choose a task, and what to do if a feature is missing.

### Article typography and figures

Use an explicit customer article variant, scoped to the Markdown wrapper. Reading measure `w-full max-w-[72ch] min-w-0`; body `text-[16px] leading-7 text-text-secondary`. H2 `text-[22px] font-semibold leading-8 tracking-tight text-text-primary`, top gap `mt-10`, bottom `mb-3`, without the current rule under every H2. H3 `text-[18px] font-semibold leading-7 text-text-primary`, `mt-7 mb-2`. Keep heading IDs, anchor links, and scroll offset. Paragraphs `my-4`; lists `my-4 pl-6 space-y-3`; nested lists `mt-2 space-y-2`; strong text in primary color. Links remain visibly underlined with accent tokens and visible keyboard focus.

Each procedure gets a task H3 and short numbered actions, with field-level substeps where needed. Avoid burying several unrelated actions in one numbered sentence. Prefer prose/lists over wide tables; retained tables scroll within a bounded wrapper rather than widening the document.

Figures: `my-8 min-w-0`; image frame `overflow-hidden rounded-xl border border-border bg-canvas-elevated shadow-xs`; image `block h-auto w-full max-w-full`. Keep natural aspect ratio and all relevant controls; no fixed height or cropped `object-cover`. Caption row `mt-3 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between`, caption `text-[14px] leading-6 text-text-secondary`, full-size link `inline-flex min-h-11 shrink-0 items-center self-start text-[14px] leading-6 text-accent-text underline underline-offset-2` with visible focus. Image and caption must remain useful at 320px and 200% zoom; full size is available for small UI labels.

Use `:::note` for distinctions such as save versus publish and test-email personalization. Use `:::attention` immediately before a consequential action already supported by the application, such as Send Now, site replacement, or disabling password reset. Preserve existing localized callout titles and renderer composition; static guidance is not an assertive live alert. Essential instructions always appear as text, independently of the image.

## 3. Exact integration contracts

### Repository and card links

Keep the existing `DeveloperDocs::Repository::Page` and sidebar `Entry` shapes. Add a customer-repository public method **`guide_groups`**, returning `Array<DeveloperDocs::Repository::Group>` with a new immutable `CustomerDocs::Repository::Guide` entry type:

- Group: `key: String`, `entries: Array<Guide>`.
- Guide: `slug: String`, `title: String`, `summary: String`, `path: String`.
- Sources: the same allow-listed catalog and localized front matter used for article lookup, including its existing locale fallback. Exclude `Catalog::HOME_SLUG`; omit unavailable sources and empty groups.
- This is the complete directory, independent of `q`. Search continues to filter only the existing contents navigation. Cards link to guides even when the homepage contents has no search matches.
- Path must be generated by the repository's existing route resolver with the URL customer and effective locale: `admin_help_doc_path(C, slug, locale: L)`. Example: `/81721200/admin/help/docs/forms?locale=en`. Do not derive the customer from the author's account, use front matter as an arbitrary destination, hard-code 81721200, or carry `q` into card links.
- `guide_groups` is assembled from current metadata, outside the current article fragment cache. A summary edit must update a card on the next request. Cached rendering of images must include the image-policy configuration and a revised renderer cache version.

### Components and view

| Piece | Contract |
| --- | --- |
| `DeveloperDocs::ReaderComponent` | Existing `page:`, `translation_scope:`, `locale:` plus **`article_variant: :reference`** and **`home_groups: nil`** defaults. Customer view passes `article_variant: :customer`; it supplies `home_groups` only when `page.slug == CustomerDocs::Catalog::HOME_SLUG`. |
| `CustomerDocs::HomeGuidesComponent` (new) | **`groups:`** required; renders localized home heading, catalog group labels, and native cards using `CardComponent`. No database/module-status lookups or route construction. |
| `Admin::Help::DocsController` | Reuse one customer repository instance per request for `page` and `guide_groups`; index and explicit overview show both receive groups. Non-home guides pass `nil`. |
| Screenshot figure | Generated by `DeveloperDocs::Renderer`, like existing callout markup; customer reader owns Tailwind figure styling. No screenshot modal/controller. |

`nil` home groups means no home surface; an empty array means render the localized directory-unavailable message below its heading and keep the overview article/contents. Shared developer-reader callers use the reference variant and no home groups.

### Screenshot authoring and safety

Files live at `public/help/docs/screenshots/<locale>/<name>.png`; served URLs have no `public` prefix. Use one **standalone Markdown image paragraph** per figure. The image title is the caption; alt text describes the visible controls or state, not the filename:

```markdown
![Forms access panel with launch status and member and public audience controls.](/help/docs/screenshots/en/forms-publishing.png "Check launch status and audience before sharing a form link.")

![表单访问面板，包含发布状态及会员、公开访问选项。](/help/docs/screenshots/zh-CN/forms-publishing.png "分享表单链接前，先核对发布状态和访问范围。")
```

The renderer generates a semantic `figure`, image anchor, `img`, and `figcaption` with a native **View full size** link. Both anchors use the identical checked source path in the same tab; browser Back returns to the guide. Image-link aria label is localized with the caption. Set server-owned `loading="lazy"` and `decoding="async"`; measured width/height may be emitted if available, without constraining responsive display. Alt/caption are localized Markdown content, escaped as text. Consume the Markdown title as the visible caption rather than relying on a tooltip.

Add an explicit **`screenshot_root: nil`** renderer/repository option; the customer repository supplies `"/help/docs/screenshots"`. With `nil`, existing image-stripping behavior applies. With the option, the entire raw URL must match:

```text
\A/help/docs/screenshots/(?:en|zh-CN)/[a-z0-9]+(?:-[a-z0-9]+)*\.png\z
```

Apply the identical policy to image sources and full-size links before rendering and again in sanitization. Permit the new image/figure attributes only on the appropriate elements and validate their values; discard author-supplied event/style/srcset attributes. Renderer-owned classes/loading/decoding are controlled values. Keep existing catalog-slug link rewriting and safe external text links. No external, protocol-relative, data, blob, SVG, relative, nested, query, fragment, percent-encoded, whitespace-padded, backslash, or traversal image URL qualifies. Never decode a rejected URL into an accepted one or fetch remote image content.

Malformed/unsafe image markup yields escaped alt text only, with no `img` or full-size anchor; required nonblank alt/caption and standalone placement are publishing checks. A valid path whose file is missing can produce a browser image failure; alt, caption, and essential adjacent instructions remain, and the broken file must be fixed before publication. Image links are a distinct allowed static-asset category in content validation, not a customer guide slug. Both locale files must reference their own locale images. Static images are publicly retrievable and therefore contain only publishable demonstration data.

### Localized UI additions

Add these matching keys in `config/locales/customer_docs.{en,zh-CN}.yml`; resolve at render time. Reuse existing group, empty-search, and callout labels.

| Key under `customer_docs` | en | zh-CN |
| --- | --- | --- |
| `home.guides_title` | Choose your next task | 选择下一项任务 |
| `home.guides_empty` | Guides are temporarily unavailable. Please try again later. | 指南暂时不可用，请稍后重试。 |
| `screenshots.full_size` | View full size | 查看原图 |
| `screenshots.open` | View full size: %{caption} | 查看原图：%{caption} |

## 4. States, actions, and interaction flow

- **Home:** Help → Documentation → `/C/admin/help/docs?locale=L` → choose a card → `/C/admin/help/docs/<slug>?locale=L`; contents highlights the destination. Explicit `/docs/overview` has identical cards.
- **Search:** submit existing desktop/mobile GET form → current article remains; only contents groups filter. Home cards stay complete. No matches uses the existing translated contents message. Clear keeps locale and restores groups. Non-home readers keep normal previous/next behavior.
- **Read:** follow an existing section anchor, read substeps and note, open screenshot/full-size link → static PNG in same tab → Back. No write occurs through documentation actions. Native open-in-new-tab remains available through browser link controls.
- **Language:** existing switcher → same customer/slug/query context in the new locale; metadata, prose, captions, and screenshot path change together.
- **Loading:** normal server-rendered navigation; no new client loading/skeleton state. Image lazy loading retains adjacent text.
- **Unavailable guide:** existing localized HTTP 404 and customer-home recovery breadcrumb. Missing card source is omitted; all missing sources use the directory message.
- **Permission denied:** inherited admin/owner and tenant guards, before content is served. Members/anonymous/cross-tenant admins do not receive the guide. Static demo images do not expose protected data.
- **Validation/provider failure in the documented task:** documentation explains where the current screen's error appears, how to correct it, how to confirm the saved/processed result, and when to use Support. It does not show a live vendor-status badge or execute a test itself.
- Primary action is selecting a task; secondary actions are section links, related guides, full-size images, and reading sequence. There are no destructive documentation actions.

## 5. Content handoff — all 13 guides in both locales

Retain the five required H2 headings from `CustomerDocs::Catalog::REQUIRED_HEADINGS` in order. Add task H3s and concrete substeps beneath them. Every guide needs a clear starting screen, example input where useful, exact visible action label, saved/processed result, and practical recovery. Keep sections/examples/callouts/image subjects aligned across languages. Titles/summaries stay in front matter; article bodies have no H1. Link to customer guide slugs rather than owner tools or fixed tenant destinations.

| Slug | Required editorial improvement |
| --- | --- |
| `overview` | Replace directory prose/list with compact orientation around the card area; explain roles, language, availability, and next task. |
| `getting-started` | Separate sign-in, organization check, navigation, first task, and account-security actions; show how Help returns to guides. |
| `users` | Split creation/editing and security controls; preserve password-blank behavior, confirmation versus invitation, deactivation, MFA reset and device revocation outcomes. |
| `records` | Distinct find/detail/columns/export procedures with a sample query; distinguish review from form editing and permanent deletion from hidden columns. |
| `forms` | Explain preview versus real submission; launch status versus audience; autosaved visibility, public/member coupling, shared restrictions, and admin member-preview being read-only. |
| `websites` | Separate edit → Save → page Published → site Make site public → signed-out check; distinguish navigation visibility. Put replacement consequence beside that optional action. |
| `payments` | Add the customer provider-setup procedure before transaction/refund steps: provider gallery, correct environment, merchant identifier/required credentials, Save, saved-connection test, activation, and actual checkout/result validation. Distinguish collection setup from service Billing. |
| `email` | Separate content/personalization/test, list creation/resolved audience, and send activity; clearly distinguish template Save/Active from Send Now submitting real delivery. |
| `sms` | Make approved-template/task prerequisites concrete; test task is a real send; explain log search, receipt states, and opt-out follow-up. |
| `assistant` | Separate focused request, attachments/dictation, proposed updates and review; distinguish immediate creation, Apply changes, website drafts, and chat deletion. |
| `settings` | Concrete registration/password-reset/MFA/public-form-protection procedures; separate immediate switches from Save and managed limits from editable preferences. |
| `billing` | Separate plan comparison/change, payment authorization/default, end-of-period cancellation/resume, and invoice check/download; confirm state before retry. |
| `support` | Show customer-visible Help actions, reproducible problem details, safe attachments, submit success and same-ticket follow-up; distinguish in-app conversation from email. |

### Verified details content agents must preserve

- Payment configuration: `MerchantAccountsController` edits distinct provider/mode rows; blank credential values retain stored secrets. The gallery owns enable/disable; config **Save changes** persists fields. Connection testing uses saved values, so save first. Current Alipay/WeChat connection checks do not ping the vendor; success never proves checkout, refund, or signed notifications. App Sandbox does not automatically select a vendor sandbox. Explain required vendor setup using the current gateway fields and verified reference; platform module/provider availability is managed by support.
- Test email: `TemplatesController#test_send` uses `Emails::VariableContext.for(user: current_user)` for every entered destination, not the destination user's profile. Standalone preview shows token labels. Real activity personalization uses each resolved recipient. Make this a short note and a concrete example using the available token picker; an arbitrary external test address does not test recipient-specific values. Testing unsaved content is not saving the template.
- Account security: the tenant MFA policy currently enforces admins/owners; members opt in to their own MFA. `session_timeout` and `max_login_attempts` are stored settings without runtime readers; do not claim saving them changes the enforced timeout/lockout. Password-reset disable affects already-issued links and administrators too. Confirm these details against `Authentication::MfaObligation`, settings controllers and current reference before final wording.
- Public page protection: describe the tenant's own public-form request limits and actual provider readiness; customer settings do not configure platform captcha keys or guarantee a working challenge. Shared forms remain managed. Do not add owner-only setup steps to customer prose.

## 6. Screenshot handoff — six representative captures per locale

Capture **real customer-visible screens** at consistent desktop width (approximately 1440 CSS px, 100% zoom, optionally 2× pixel density), cropped to useful content with enough breadcrumb/navigation context. Use an authenticated **admin-role** session, including when viewing customer 81721200. `SKIP_AUTH=1` may select an owner; it is not evidence of customer-visible chrome. No Maintenance/Platform links, developer tooling, reserved-owner identity, or flowchart editor/mentions in any capture. Customer-visible Help wording such as Notify platform owner is a legitimate customer action.

Use demonstration names/addresses only; keep credential inputs blank/masked, remove secrets, recovery codes, payment/card details and private notifications. No fabricated success indicators or overlaid product controls. Capture each locale with matching UI language; captions must describe the actual captured state, including empty or disabled states. Filename stays stable when using an alternative of the same subject.

| PNG basename (in both locale directories) | Primary real capture | Honest alternative if empty/unavailable | Place beside |
| --- | --- | --- | --- |
| `workspace-help.png` | Customer Home with Help open, Documentation visible | Customer guide page with Help open; an empty dashboard is acceptable | `getting-started`: find Help; reuse in `support` if useful |
| `records-list.png` | `/C/admin/entities/<id>` with a demo record list, search/column/export controls | Existing empty record list or opened column picker, captioned as empty; if no record type exists, use a prepared disposable demo customer | `records`: find and customize a list |
| `forms-publishing.png` | `/C/admin/pages` with Manage access open for an existing customer-owned form, showing status and audience | Existing offline customer-owned form; use a disposable demo customer's form if only shared forms exist. An empty list alone does not illustrate publishing controls | `forms`: launch and select audience |
| `website-publishing.png` | `/C/admin/settings/modules/website/site`, publication setting and Save visible | Draft site's real settings, captioned as not public; if no site/module exists, use a provisioned disposable demo customer | `websites`: publish the site after saving/publishing pages |
| `email-audience.png` | `/C/admin/modules/emails/send_activities/new`, Audience step with a small demo list selected, before final submission | Real `/C/admin/modules/emails/lists/new` static/dynamic audience form, captioned as creating a list; existing empty list screen is last fallback, not a populated audience claim | `email`: build/check the resolved audience |
| `payment-settings.png` | `/C/admin/settings/modules/payments/merchant_accounts/<id>/edit`, environment, blank/masked fields, Save and saved-connection control | Real provider gallery with disabled/unconfigured demo rows; if none are available, capture its honest empty state and readiness instruction | `payments`: configure a provider |

Exact deployed paths: `/help/docs/screenshots/en/<basename>` and `/help/docs/screenshots/zh-CN/<basename>`. Capture agent supplies 12 PNGs under matching `public/` directories and a handoff noting source URL, locale, role, actual state, crop/dimensions, and any fallback. Captures need not trigger sends, payments, activation, launch, or site publication. Prefer existing demo data; prepared sample records/forms/sites belong to a disposable demo customer, with setup recorded separately. Content agent places images only once the actual subject/state is known.

## 7. Acceptance and lane ownership

- **Backend:** `guide_groups` metadata/link contract; explicit screenshot policy through repository/renderer; tag-aware scrub; cache invalidation; static-asset link validation. Guide authorization remains controller-enforced.
- **Frontend:** new HomeGuides component and reader props; customer-only typography, figure styles and empty state; paired I18n keys; native screenshot links. Existing Stimulus stays sufficient.
- **Content:** all 26 Markdown files, verified substeps/distinctions, coherent front matter, localized alt/captions, and matching image placement. Update `doc/reference/{en,zh-CN}/customer-documentation.md` with new contracts in the implementation change.
- **Capture:** the 12 actual PNGs and state handoff above.
- **QA/release:** metadata cards resolve to the current customer's localized guides; all 13 sources exist in both locales; images/links safely survive scrub; malformed sources never fetch or link; developer reference still renders; home, guide, no-result and empty-directory states work. Check 320/390/768/1024/1440px and 200% zoom, wrapping/overflow, keyboard card/full-size links, mobile Contents, and localized figures.

The concrete implementation sequence and focused checks are in `docs/superpowers/plans/2026-10-08-customer-documentation-polish.md`.

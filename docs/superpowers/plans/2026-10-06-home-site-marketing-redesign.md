# Home-site marketing redesign — implementation plan

**Date / role:** 2026-10-06 · anysys-tech-lead, planning capacity  
**Status:** Approved design; ready for parallel implementation. This change creates the plan only.  
**Locked design:** [UX specification](../specs/2026-10-06-home-site-marketing-redesign-ux.md), including exact bilingual copy and visual acceptance in §§5–11.

**Goal:** Redesign customer **81721200**'s five saved public WebsitePage surfaces: `/81721200/site` and `/platform`, `/pricing`, `/about`, `/contact`. Ordinary saved `{ id, type, props }` sections, their order, and owner-editable content remain the rendering contract.

## 1. Baseline and lane ownership

Retain the five intentional uncommitted baseline files; their owners extend them in place:

- `config/locales/website_home_site.en.yml`
- `config/locales/website_home_site.zh-CN.yml`
- `doc/reference/en/website-builder.md`
- `doc/reference/zh-CN/website-builder.md`
- `spec/services/websites/home_site_spec.rb`

The untracked locked UX specification is also retained. Capture the starting diff before implementation; never revert baseline work. No commits or agent dispatch are part of this planning task.

| Lane | Exclusive write ownership / output |
|---|---|
| **BACKEND** | `app/services/websites/home_site.rb`; both home-site locale files; both website-builder reference docs; `spec/services/websites/home_site_spec.rb`. Delivers source composition, semantic ID preservation, bilingual copy, structural-restore documentation. |
| **FRONTEND** | `app/services/websites/home_site/presentation.rb`; `app/components/websites/home_site/**`; `app/components/websites/page_component.{rb,html.erb}`; `app/views/websites/pages/show.html.erb`; `app/views/admin/modules/website/pages/preview.html.erb`; `app/views/admin/modules/website/pages/edit.html.erb`; targeted `app/components/websites/admin/{composer,composer_sections,section_editor}_component.{rb,html.erb}` changes as needed; resolver and component specs listed below. |
| **SECURITY** | Read-only audit of resolver identity checks, existing controller/CurrentSite tenant scopes and guards, link/media helpers, rendering/asset safety. Reports concrete findings to the owning lane; no auth or route changes are required. |
| **QA** | Existing localization service spec and affected request specs; new marketing browser spec. Coordinates source assertion requirements with BACKEND and component requirements with FRONTEND without simultaneous edits to their files. |
| **RELEASE** | Temporary backup/application/report/capture scripts under `/tmp/opencode/`; source application, assets/server operations and browser evidence after integration. No production migration. |

BACKEND and FRONTEND can build against §2 concurrently. QA integrates after their outputs; SECURITY can audit in parallel. BACKEND incorporates the finalized frontend interfaces into both reference docs before review.

Use the official shadcn references already consulted in UX §2: [Card](https://ui.shadcn.com/docs/components/card) for draft/plan hierarchy, [Button](https://ui.shadcn.com/docs/components/button) for semantic anchor hierarchy/focus, [Accordion](https://ui.shadcn.com/docs/components/accordion) for native FAQ rows, and [Badge](https://ui.shadcn.com/docs/components/badge) for meaningful statuses. Skill/MCP is unavailable; these references inform ViewComponent + Tailwind composition. The locked design requires no React dependency, custom CSS or JavaScript change.

## 2. Frozen integration interfaces

### Scoped resolver and dispatch

```ruby
Websites::HomeSite::Presentation.for(website:, page:) # eligible object or nil
# Returned object:
presentation.role                 # :home, :platform, :pricing, :about, :contact
presentation.component_class(type) # mapped specialized class or nil
presentation.variant_for(type)     # internal symbol or nil
presentation.header_class          # optional specialized class
presentation.footer_class          # optional specialized class

Websites::PageComponent.new(
  page: page, theme: theme, website: nil, nav_pages: [], presentation: nil,
  sections: nil, customer_id: nil  # existing overrides retained; page stays optional
)

# Specialized section base; generic section initializers retain their interface:
Websites::HomeSite::SectionComponent.new(
  props: props, theme: theme, customer_id: customer_id,
  variant: nil, page_role: nil, nav_pages: []
)
```

- Require actual website **and** page records with `customer_id == HomeSite::CUSTOMER_ID`; missing context returns nil. Use the supplied records, never `Current.customer`, URL substrings, section IDs or copy as eligibility selectors.
- Check saved identity with `website.id` and `page.website_id`: when either record carries saved identity, require a nonnil website ID and `page.website_id == website.id`. Localization/preview copies can have an ID while `persisted?` is false; do not reject valid copies or skip the association check because of that flag. For genuinely unsaved records, require their actual website association to be the supplied object, rather than accepting `nil == nil`.
- Resolve `:home` only from `page.home?`; otherwise accept only `platform`, `pricing`, `about`, `contact`. An arbitrary blank slug or slug `home` is ineligible. Other slugs/tenants use generic sections **and** generic chrome entirely. Explicit presentation input cannot bypass these record checks.
- PageComponent resolves context from website/page when no object is supplied. Normalize each saved section, confirm `SectionKit.known?(type)` **before** consulting the specialized resolver, then select its mapped class or the generic `SectionKit.component_class(type)`. Pass specialized-only kwargs only to specialized classes. Unknown types retain skip behavior; unmapped known types remain visible through generic components.
- Iterate saved order unchanged. The resolver chooses class/variant only: no content-order assumptions, adjacent-section coupling, synthesized content, mutation, database writes or restore on render. Header/footer use the same validated context.

| Stored type | Scoped component under `Websites::HomeSite` | Variant by page role |
|---|---|---|
| `hero_centered` | `HeroComponent` | Home/Platform `:lead`; Pricing `:pricing`; About/Contact `:editorial` |
| `ai_preview` | `DraftComponent` | nil |
| `feature_grid` | `IndexComponent` | About `:principles`; otherwise `:capabilities` |
| `steps` | `IndexComponent` | `:process` |
| `split_image_text` | `StoryComponent` | `:story` |
| `rich_text` | `StoryComponent` | Contact `:contact_note`; otherwise `:editorial` |
| `card_grid` | `PerspectiveComponent` | nil |
| `pricing` | `PlansComponent` | nil |
| `faq` | `FaqComponent` | nil |
| `cta_band` | `CtaComponent` | Contact `:contact_next_steps`; otherwise `:closing` |

### Chrome, views and editor

- `HomeSite::HeaderComponent < Websites::NavComponent` keeps `initialize(website:, pages: [], current_slug: nil, embed: false, theme: nil)`; `HomeSite::FooterComponent < Websites::FooterComponent` keeps `initialize(website:, theme: nil)`. Reuse existing helpers and runtime I18n chrome keys. Add scoped `MobileNavSheetComponent < Websites::MobileNavSheetComponent` with the existing sheet signature to include signup once; retain all `website-nav` targets/actions, sheet sibling placement and focus/dismissal behavior.
- In public show and admin preview views, resolve once from controller-supplied `@website`/`@page`, select scoped-or-generic chrome, and pass `website`, `nav_pages` and presentation to PageComponent. Controllers already supply actual site context; no controller edits are needed. Public records are already localized copies. For eligible admin previews, use read-only `HomeSiteLocalization` copies of website/page/nav records in the view so both locales render the same source-aware presentation without changing saved/draft props. Preserve current embed behavior.
- Supply only same-site, published, nav-visible page records in saved order to the scoped header/sheet and section context; admin preview's existing `in_nav` collection needs a presentation-time published filter. Contact's next-step variant selects only Platform/Pricing from this localized context and uses existing href helpers; omit unavailable links. Do not invent destinations or labels.
- Target composer flow: edit view passes `presentation:` resolved with `@website`/`@page` → optional Composer keyword/reader → ComposerSections delegation → `presentation:` on every SectionEditor instantiation, including non-workspace/template branches. SectionEditor creates a fresh field-schema presentation, replacing only the existing top-level `headline` field's kind with `:textarea` when eligible; never mutate shared SectionFields metadata. Preserve key/value/default/label and all `[data-prop]` controls. Layout editors, extra pages and other tenants keep the current controls; no global schema or builder JS edits.
- Scoped main gets `id="site-main"`, `tabindex="-1"` and the existing translated skip-link key. Use complete Tailwind class literals, standard font sizes and render-time Chinese tracking. Props remain escaped; headline lines become block spans, with only Home's final multiline line violet. Single-line Home owner copy stays slate.

## 3. Implementation steps

### Step 1 — BACKEND: source definition, restore and paired docs

- [ ] Implement the exact UX copy and these ordinary section sequences, using existing field schemas:

| Page | Count | Types in saved source order |
|---|---:|---|
| Home | 8 | `hero_centered, ai_preview, feature_grid, split_image_text, steps, card_grid, faq, cta_band` |
| Platform | 7 | `hero_centered, ai_preview, feature_grid, split_image_text, steps, card_grid, cta_band` |
| Pricing | 4 | `hero_centered, pricing, faq, cta_band` |
| About | 5 | `hero_centered, rich_text, feature_grid, split_image_text, cta_band` |
| Contact | 3 | `hero_centered, rich_text, cta_band` |

- [ ] All source heroes use `media_mode: none`; Pricing/About/Contact have blank hero action pairs. Preserve literal headline/body newlines, paired locale key/array/interpolation parity and call-time I18n. Keep pricing only on Pricing, derived from `Billing::StandardPlans::CATALOG`, existing quota/trial qualifications and signup-only CTAs. Retain exact pricing FAQ wording and future-scoped Windows/configured-service claims.
- [ ] Keep steps and capability image fields absent. Three story assignments plus two Windows sections × three repeated `anysys-local-desktop.svg` card assignments = **9 stored images / 5 rendered placements / 4 unique selected assets**. Paths: Home brand-studio/local-desktop; Platform review-publish/local-desktop; About about-idea-hero; Pricing/Contact none. Blank card hrefs; repeat the first art explicitly so `Media.fill` cannot substitute stock photos. Preserve all **15** bundled files.
- [ ] Improve `preserve_section_ids` within each source page: reserve exact source-ID matches first, then match source semantic suffix IDs (e.g. `_hero`, `_website`, `_capabilities`, `_steps`, `_principles`) independently of changed types, then fall back to remaining same-type predecessors. Complete/reserve semantic matches before type fallback can consume a later role's predecessor. Consume each predecessor once, track used IDs, reserve new stable source IDs, and guarantee unique deterministic IDs on repeated application. Never match page positions or copy. Report ambiguous opaque-ID mappings in the application report.
- [ ] Keep `HomeSite.apply!` customer-hard-locked and explicit, using existing customer lock/transaction, SaveSite and `SavePage(..., structure_editable: true)`. Full source restore intentionally resets the five source-page contents/publication and source site metadata; preserve Website/WebsitePage row identities, extra pages (including content/flags/positions), other tenants and media blobs. No automatic migration or read-path apply.
- [ ] Extend `spec/services/websites/home_site_spec.rb`: counts/types, text-only/action contracts, catalog-only Pricing, bilingual/newline parity, absent step media and stock-free saved defaults; semantic suffix/type-change ID retention, repeated apply/duplicate-ID prevention, rollback and extra-page/tenant preservation. Replace old 27-assignment and Home pricing assertions. Asset membership asserts selected paths are a subset of the complete 15-file inventory; XML/content/security checks iterate **all 15 files**, not only currently assigned images.
- [ ] Update both reference docs together: new compositions/counts, scoped resolver/dispatch/chrome/editor contract, image-role table/budget, localization and explicit structural restore/backup/media-review workflow. Replace obsolete copy-only-deployment and unchanged-order/type/27-assignment claims; keep locale sections/examples/callouts aligned.

### Step 2 — FRONTEND: resolver, eight section components and chrome

- [ ] Add the resolver and shared base, eight section classes/templates from §2, Header/Footer and scoped MobileNavSheet. Follow UX container, typography, responsive rhythm, native FAQ, compact draft/plan and editorial layouts exactly; keep optional/empty fields cleanly omitted.
- [ ] Reuse `href_for`, media validation, Illustration/FittedPhoto and LanguageSwitcher. Guard blank/invalid media before calling `render_media` so it cannot create a placeholder. Invalid CTAs render ordinary label text. Perspective shows default repeated art once and preserves distinct custom uploads/HTTPS media on later cards as compact supplementary media with stored alt context; other bundled art is not supplementary authored media.
- [ ] Wire dispatcher/views/editor context as §2. Preserve arbitrary inserted known section types, owner literals, list reorder, saved field controls and generic fallback. Add focused specs using current naming:
  - `spec/services/websites/home_site/presentation_spec.rb` (new): target roles, home predicate, missing/mismatched site/customer, saved identity and copied records, extra-page/other-tenant fallback, non-mutation.
  - `spec/components/websites/home_site/{hero,draft,index,story,perspective,plans,faq,cta,header,footer,mobile_nav_sheet}_component_spec.rb` (new): meaningful props/empty-state/escaping/link/media/accessibility/variant behavior, source image placement budget, custom media and unpublished Contact link omission.
  - `spec/components/websites/page_component_spec.rb`: saved order/IDs, known-first dispatch, mapped/unmapped/unknown types, validated explicit presentation and generic-only fallback.
  - `spec/components/websites/admin/composer_component_spec.rb` and `section_editor_component_spec.rb` in the same directory: full propagation, target headline textarea preserving newlines, generic single-line controls, immutable shared schema and unchanged data controls.

### Step 3 — SECURITY read-only audit and QA integration

- [ ] Audit `app/controllers/websites/pages_controller.rb`, `app/controllers/admin/modules/website/{base,pages}_controller.rb`, `app/controllers/concerns/websites/current_site.rb`, existing routes, `app/services/websites/href.rb`, media helpers and new presentation output. Confirm actual-record tenant/site isolation, existing admin guards, public empty 404, escaped props and validated links/media. Keep source apply off request paths; confirm no invented auth role/URL or cross-tenant write. Report findings to file owners.
- [ ] Extend `spec/services/websites/home_site_localization_spec.rb` for new source roles, feature arrays, multiline leaves, reordered items and literal owner text, keeping HomeSiteLocalization's existing exact-match/read-only behavior.
- [ ] Update `spec/requests/websites/home_site_localization_spec.rb`, `public_pages_spec.rb` and `admin_pages_spec.rb` in `spec/requests/websites/`: all five pages in both locales, no render writes, other-tenant/extra-page isolation, publication/disabled/missing empty 404, GET/POST admin draft preview parity and nonpersistence, guarded cross-tenant preview/save, explicit locale links, Contact publication filtering and real locked SavePage multiline round-trip. Replace fixed hero-image/overlay counts and old bento/cinematic selectors with per-role selected-image assertions; inspect block headline lines rather than requiring raw newline text in flattened DOM.
- [ ] Add `spec/e2e/home_site_marketing.app.spec.js` using existing Playwright conventions and discovered page IDs. Capture the matrix in Step 5 and exercise the actual composer textarea/serialized payload/draft preview. Real browser save/reload verification uses a disposable test fixture/site with cleanup, not writes to the live reviewed content. Existing `website_page_composer.app.spec.js` / `website_responsive.app.spec.js` are conventions, not fixed-ID fixtures to blindly reuse.
- [ ] Run the affected layers; resolve failures before source deployment:

```bash
bundle exec rspec spec/services/websites/home_site_spec.rb spec/services/websites/home_site/presentation_spec.rb spec/services/websites/home_site_localization_spec.rb spec/services/websites/activities/save_page_spec.rb spec/services/websites/contracts/section_spec.rb
bundle exec rspec spec/components/websites/home_site spec/components/websites/page_component_spec.rb spec/components/websites/nav_component_spec.rb spec/components/websites/footer_component_spec.rb spec/components/websites/mobile_nav_sheet_component_spec.rb spec/components/websites/illustration_component_spec.rb spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb spec/components/websites/admin/prop_field_component_spec.rb
bundle exec rspec spec/requests/websites/home_site_localization_spec.rb spec/requests/websites/public_pages_spec.rb spec/requests/websites/admin_pages_spec.rb
```

JavaScript source is unchanged, so no Vitest coverage run is required for this slice. An implementation that introduces JS changes must revisit ownership and meet the project's 100% line/branch coverage requirement.

### Step 4 — RELEASE: explicit saved-content application

- [ ] Export current site metadata, five source pages, extra-page snapshots, section IDs/roles and all custom media references to `/tmp/opencode/` before writes. Review removed-slot media and the intended source metadata/content reset against the backup.
- [ ] Write a temporary application script that invokes `Websites::HomeSite.apply!(locale: :en)` explicitly, then rehomes reviewed custom media through the existing SavePage activity within the same outer transaction. Map surviving website/desktop/about roles; move meaningful former hero media into an appropriate media-bearing story. Stop for unresolved media mappings rather than losing content. Keep removed-slot references/blobs in the backup/report; do not use the old copy-only leaf patcher.
- [ ] Record before/after role/ID/media mappings, intentional removals and metadata resets; verify stable site/page rows, unique section IDs, exact source defaults when unedited, extra-page/other-tenant snapshots and no unexpected stock media. Exercise repeated apply in specs/disposable data, not by reapplying over reviewed custom media on the live site. Source file changes alone cannot update saved text or bilingual exact-match localization.

### Step 5 — RELEASE/QA: fresh browser evidence and review

- [ ] Build `bin/rails tailwindcss:build`. If restarting development, verify the asset directory and remove `public/assets/.manifest.json` first; restart with `SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`. If digested assets shadow sources, run `bin/rails assets:clobber`, regenerate Tailwind (clobber deletes its build), then follow manifest-removal/restart order. Confirm the browser receives fresh HTML/assets.
- [ ] Run `APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/home_site_marketing.app.spec.js --project=chromium`; run save/reload against its isolated fixture environment. Produce actual full-page **and first-viewport** screenshots for all five saved pages × `en`/`zh-CN` × **320/390/768/1024/1440** widths (50 combinations). Scroll/load/decode images and wait for fonts before capture; use 390×844 and 1440×900 for explicit viewport targets.
- [ ] Verify UX §11: Home board begins near y=600 at 1440; Pricing cards begin by y=360 and all four names/prices/reference note/quotas/CTAs fit at 1440×900; reference note plus first plan name/price visible at 390×844. Meet specified page-length budgets and 2/2/0/1/0 default placements; Contact availability visible in both target viewports. No horizontal overflow or clipped content at 320 or 200% zoom.
- [ ] Keyboard-check native FAQ with multiple open answers, mobile menu/close/Escape/focus return, nav/signup/Contact links, locale round-trips and skip link. Check ≥44 px targets, heading hierarchy, focus/contrast and Chinese tracking. Compare control-tenant public/admin screenshots and builder save payloads for isolation.
- [ ] Review fresh images against `/tmp/opencode/marketing-redesign-current-*` UX baseline evidence. Iterate composition/spacing with the owning lane, rerun only impacted checks and recapture changed combinations until visual acceptance passes. Final tech-lead/code review checks paired I18n/docs, lane boundaries, saved editability and security findings; return test evidence, screenshots and content-application report.

## 4. Key execution concern

`HomeSite.apply!` is a full source restore: it can reset source metadata and owner text, and changed section types cannot always be semantically identified from opaque legacy IDs. Backup/custom-media review and the role/ID report are required before explicit application. Copied-record identity checks and reserving semantic ID matches before type fallback are the principal integration risks; neither requires a new persisted token or schema.

## 5. Approved final refinement — native mobile navigation, 2026-10-06

Scoped presentation, preview and composer integration are implemented. UX §13 supersedes the initial no-JavaScript-change assumption in §1 and the unchanged-JavaScript verification exemption in Step 3. The scoped sheet is a native `<dialog>` using the existing `website_nav_controller.js`; `showModal()` supplies modal top-layer focus and background inertness without a hand-written focus trap. Generic div-sheet rendering remains in place; no new controller, marketing prop or URL is introduced. UX §12's typography/spacing/pricing refinement is retained.

The finalized behavior is close-button autofocus, native `cancel` routed through controller close/cleanup, self-only transparent-dialog backdrop dismissal, visible-trigger focus return, root-overflow restoration, and close/unlock at desktop resize or disconnect even when targets disappear. Native Tab/Shift+Tab excludes background controls while allowing browser-chrome boundaries.

Verification combines `spec/javascript/controllers/website_nav_controller.test.js` at mandatory 100% Vitest lines/branches/functions with `spec/e2e/website_native_dialog.app.spec.js` for actual native modal/focus/inertness behavior in EN/zh-CN at 320/390/768 px, plus backdrop/close, desktop resize and disconnect. The browser spec uses `APP_BASE_URL` and blocks non-GET/HEAD requests. Both website-builder locale references describe this implemented contract; source service verification remains the targeted `bundle exec rspec spec/services/websites/home_site_spec.rb --no-color` run.

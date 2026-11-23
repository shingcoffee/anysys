# Home-site imagery — UX specification

Date: 2026-10-06 · Role: anysys-ux-designer · Scope: research/design only

## 1. Decision and research

Commission **12 original vector scene designs**, with **five page-specific hero compositions**. Use polished, dimensional product/browser illustrations: luminous violet and indigo, porcelain surfaces, small teal/peach accents, and recognisable records, forms and website layouts. Images should feel like premium editorial product renders, with the business system and public website equally prominent.

No image-generation tool is available in this session. This document is an art-direction and implementation handoff; artwork has not been generated. Author editable SVG masters without embedded words; publish matching WebP exports through the existing Website media workflow.

Consulted first: the official [shadcn new-york-v4 Card registry](https://ui.shadcn.com/r/styles/new-york-v4/card.json). Its `rounded-xl`, border, `shadow-sm`, structured header/content/footer, generous padding and consistent gaps inform the **drawn card vocabulary**. Translate these into vector geometry, not React or new page styling.

Source of truth: `app/services/websites/home_site.rb`, both `config/locales/website_home_site.{en,zh-CN}.yml`, and current Website section/media components. This imagery-only brief takes precedence over the earlier refresh spec's proposed text-only heroes and section substitutions.

## 2. Surface inventory and layout

All surfaces are **public**, for anonymous and authenticated visitors. Preserve current navigation, content, section order, responsive frames and actions. Artwork occupies only the existing `image_url` placements.

| Surface | Existing media regions | Source placements |
|---|---|---:|
| `/81721200/site` | Cinematic hero; AI-builder split; website bento ×3; workflow steps ×3; desktop cards ×3 | 11 |
| `/81721200/site/platform` | Centered hero; capabilities bento ×3; alternating website features ×3; desktop cards ×3 | 10 |
| `/81721200/site/pricing` | Centered hero above existing plan comparison | 1 |
| `/81721200/site/about` | Centered hero; principles bento ×3 | 4 |
| `/81721200/site/contact` | Centered hero above existing contact-availability copy | 1 |
| **Total** | **27 assignments; 24 currently rendered image slots** | **27** |

**Observed constraints:** Home `StepsComponent` renders numbers and text, not `image_url`. Its three assignments are mapped below as reserved square-ready art, but remain non-rendering under the current component. Do not add a media region to that component for this task. Desktop `CardGridComponent` is **4:3**, not 16:9. Bento images use fixed heights, so their ratio varies with viewport width.

Region model: existing HTML heading/body/actions → existing responsive image frame → static artwork. Content remains sourced from `Websites::HomeSite::Definition` and its locale catalogs; persisted media URLs live in `WebsitePage.sections[*].props`, including nested `cells`, `cards` and `items`. There are no new data fields, panels or forms.

## 3. Visual system and crop rules

- **Palette, inside artwork only:** porcelain `#FAF9FF`, lavender `#EDE9FE`, violet `#7C3AED`, indigo `#4338CA`, deep ink `#252044`, teal `#2DD4BF`, peach `#FDBA9A`. Rough balance: 60% pale space/surfaces, 30% violet/indigo structure, 10% accent. Fade edges into the existing light-violet site.
- **Depth:** translucent lavender glass behind opaque white cards; fine lavender edges; broad low-opacity violet ambient shadows; sharper contact shadows beneath the nearest panel; one consistent upper-left light source. Use restrained gradients and SVG filters, not photorealistic raster textures embedded in SVG.
- **Shape language:** softly rounded browser/workspace shells, clear sidebar/content divisions, inset form fields, profile discs, envelopes, record stacks and layered site sections. Small line segments stand in for content. No text, digits, currency symbols, logos or pseudo-writing. No charts/statistics that imply real results.
- **Composition:** one dominant subject plus at most two secondary panels; connectors subordinate to the subject. Alternate horizontal fan, diagonal cascade, frontal editor, split comparison, stacked layers and hardware still life. Do not turn every placement into a floating generic dashboard or oversized icon.
- **Hero hierarchy:** Home is the most expansive composition. Platform has more system structure; Pricing is calmer; About is warmer and craft-led; Contact is open and conversational. Existing centered heroes already supply browser chrome, so their art uses workspace interiors and inset panels rather than a second full-width browser title bar.
- **Shared export canvas:** ordinary scenes `1600 × 1000` (16:10). Main subjects generally occupy 70–80% of the canvas; their meaningful core stays centered within `x=25–75%`, `y=18–82%`, so peripheral chrome can crop without losing the story. The AI-draft scene must remain legible at **4:5** as well as 5:4. Reserve square-safe cores for the latent Home steps.
- **Home hero:** `2400 × 1030` (approximately 21:9); keep the complete semantic core within `x=26–74%`, `y=15–85%`. Peripheral website panels and light arcs can extend outward. Center-crop previews must work at 4:3 mobile, 16:9 small screens and 21:9 desktop without different markup.
- **Other heroes:** `2400 × 1500` (16:10). Centered workspace imagery, quiet margins and medium-scale details; no upper-right-only subject. Standard compositions must survive 16:9-ish bento frames, 4:3 desktop/mobile features, 16:10 alternating features and square previews. Account for the existing bento 1.03× hover crop.
- **Finish:** fully painted backgrounds, crisp vectors at small size, restrained glows, consistent corner radii and lighting. Avoid empty-looking gray placeholders, stock photography, robots, sparkles-as-the-subject and dark neon sci-fi scenes.

## 4. Exact asset inventory and composition direction

Names below are **SVG master filenames**; their published exports have the identical basename with `.webp`. Twelve scene designs produce **15 masters/exports**: the 12 base compositions plus three tailored hero derivatives. Home and Pricing base compositions are already heroes. These are planned deliverables, not files created by this research task.

| ID | Base master filename | Composition direction |
|---|---|---|
| A01 | `anysys-home-workspace-hero.svg` | Hero-scale workspace constellation: central records/form workspace, a public website rising behind its right edge, a small request panel at left. Indigo foundation, luminous lavender rim light, one teal form detail; balanced horizontal fan with a crop-safe center. |
| A02 | `anysys-ai-draft.svg` | Compact request bubble at lower left feeds an ascending diagonal cascade of records, form and website draft panels. Peach request accent; outputs are visually unfinished, with outlined slots and editable handles. No instant-publish or all-done imagery. |
| A03 | `anysys-website-draft.svg` | A tactile stack of three web-page layouts: prominent landing page, two quieter page sheets behind. Pale violet paper, indigo section blocks and a small teal media rectangle; minimal surrounding chrome. |
| A04 | `anysys-brand-studio.svg` | Frontal website editor interior: prominent page preview, slim theme rail and floating peach/violet/teal swatches. A selected image region and small handles suggest deliberate refinement; polished glass depth without excessive tilt. |
| A05 | `anysys-review-publish.svg` | Two offset page panels: lavender editable draft behind, clean public-page preview forward. A restrained connecting arrow and review lens/check detail communicate review followed by publication; no live deployment meter or automatic-success claim. |
| A06 | `anysys-records-forms.svg` | Record table at rear and a form sheet at front right, joined by a thin violet path. Distinct field shapes, selection controls and profile discs, with enough depth to read as a connected business workflow. |
| A07 | `anysys-members-payments.svg` | Staggered member-profile cards beside a small payment-method panel; one foreground profile anchors the scene. Teal access/check accent and peach panel inset. No card numbers, balances, processor branding or transaction totals. |
| A08 | `anysys-email-sms.svg` | Offset envelope panel and rounded mobile-message panel above a restrained workspace base; dotted violet connector and two small status nodes. Teal/peach punctuation; composition reads as two configured communication channels, not a support inbox. |
| A09 | `anysys-local-desktop.svg` | Elegant three-quarter desktop monitor on a low lavender plinth, with a workspace interior and a local record stack tucked behind its base. Quiet porcelain background; hardware is the dominant silhouette. |
| A10 | `anysys-record-control.svg` | Close-up local record sheets emerging from an organised drawer/tray alongside a small device corner. One highlighted editable field and adjustment handles make ownership/control concrete; warm peach foreground, violet structure. |
| A11 | `anysys-local-privacy.svg` | Record stack held inside a translucent violet protective enclosure next to a small device outline. The records remain visible; subtle shield geometry supports the scene. Local-storage metaphor, no universal offline/no-network symbol. |
| A12 | `anysys-pricing-growth-hero.svg` | Four gently ascending workspace tiers, each holding a small page/record/profile composition. The second has a restrained violet halo; broad negative space, no prices, plan names, percentages or invented entitlement badges. |

### Tailored hero derivatives

| Exact master filename | Derived from | Page-specific direction |
|---|---|---|
| `anysys-platform-workspace-hero.svg` | A01 | Recompose at 16:10 as a slightly elevated workspace hub: records at center, form and site on opposite sides, small member/message panels at the periphery. Emphasise connected capabilities rather than repeat Home's horizontal fan. |
| `anysys-about-idea-hero.svg` | A02 | Recompose at 16:10 as a warm, spacious editorial still life: one idea panel and three coherent tool/page layers on a low curved foundation. Fewer connectors, more peach light; the subject is thoughtful software craft. |
| `anysys-contact-conversation-hero.svg` | A08 | Recompose at 16:10 around two open conversation panels and an empty page/form silhouette, with peach/teal light and generous breathing room. Remove delivery-status motifs; no headset, agent portrait, send control or support-availability implication. |

## 5. Complete placement mapping

For heroes, the selector is `home_site_<page>_hero.props.image_url` in the generated definition; all five currently receive `placeholder` from `hero(page)`. For other rows, selectors are relative to **`website.home_site` in both locale catalogs**. Array indices are zero-based. Publish the named `.webp` export and assign its returned media URL, not the literal filename.

| # | Page | Exact source selector | Export filename |
|---:|---|---|---|
| 1 | Home | `home_site_home_hero.props.image_url` | `anysys-home-workspace-hero.webp` |
| 2 | Home | `home.ai_builder.image_url` | `anysys-ai-draft.webp` |
| 3 | Home | `home.website.cells[0].image_url` | `anysys-website-draft.webp` |
| 4 | Home | `home.website.cells[1].image_url` | `anysys-brand-studio.webp` |
| 5 | Home | `home.website.cells[2].image_url` | `anysys-review-publish.webp` |
| 6 | Home | `home.steps.items[0].image_url` — latent | `anysys-ai-draft.webp` |
| 7 | Home | `home.steps.items[1].image_url` — latent | `anysys-brand-studio.webp` |
| 8 | Home | `home.steps.items[2].image_url` — latent | `anysys-review-publish.webp` |
| 9 | Home | `desktop.home.cards[0].image_url` | `anysys-local-desktop.webp` |
| 10 | Home | `desktop.home.cards[1].image_url` | `anysys-record-control.webp` |
| 11 | Home | `desktop.home.cards[2].image_url` | `anysys-local-privacy.webp` |
| 12 | Platform | `home_site_platform_hero.props.image_url` | `anysys-platform-workspace-hero.webp` |
| 13 | Platform | `platform.capabilities.cells[0].image_url` | `anysys-records-forms.webp` |
| 14 | Platform | `platform.capabilities.cells[1].image_url` | `anysys-members-payments.webp` |
| 15 | Platform | `platform.capabilities.cells[2].image_url` | `anysys-email-sms.webp` |
| 16 | Platform | `platform.steps.items[0].image_url` | `anysys-website-draft.webp` |
| 17 | Platform | `platform.steps.items[1].image_url` | `anysys-brand-studio.webp` |
| 18 | Platform | `platform.steps.items[2].image_url` | `anysys-review-publish.webp` |
| 19 | Platform | `desktop.platform.cards[0].image_url` | `anysys-local-desktop.webp` |
| 20 | Platform | `desktop.platform.cards[1].image_url` | `anysys-record-control.webp` |
| 21 | Platform | `desktop.platform.cards[2].image_url` | `anysys-local-privacy.webp` |
| 22 | Pricing | `home_site_pricing_hero.props.image_url` | `anysys-pricing-growth-hero.webp` |
| 23 | About | `home_site_about_hero.props.image_url` | `anysys-about-idea-hero.webp` |
| 24 | About | `about.principles.cells[0].image_url` | `anysys-ai-draft.webp` |
| 25 | About | `about.principles.cells[1].image_url` | `anysys-brand-studio.webp` |
| 26 | About | `about.principles.cells[2].image_url` | `anysys-platform-workspace-hero.webp` |
| 27 | Contact | `home_site_contact_hero.props.image_url` | `anysys-contact-conversation-hero.webp` |

## 6. Component reuse, interaction and states

- **Reuse:** `Websites::PageComponent`, `SectionComponent#render_media`, `Sections::{HeroCinematic,HeroCentered,SplitImageText,BentoGrid,AlternatingFeatures,CardGrid,Steps}Component`. Existing `SectionHeaderComponent`, `SectionButtonsComponent`, `NavComponent`, `MobileNavSheetComponent`, `LanguageSwitcherComponent` and `FooterComponent` retain their presentation and behavior. `AiPreviewComponent` remains its existing readable HTML example. **New components: none.**
- **Tailwind/Stimulus:** retain the current `object-cover`, responsive aspect/frame classes, rounded frames and existing hover behavior. Artwork colors/shadows are SVG geometry exported into the image, not custom page CSS. No new utilities, JavaScript, Stimulus controllers or frameworks are needed.
- **Actions:** Home → existing Explore action → `/81721200/site/platform`; Platform → existing pricing action → `/81721200/site/pricing`; primary/plan/final CTA → `/auth/sign_up`. About/Contact retain Platform and signup actions. Artwork is noninteractive; no decorative editor handles become real controls. No destructive actions.
- **Desktop flow:** Home/Platform desktop sections keep the existing localized **Windows .exe · Coming soon** heading and all current body text. Illustrations represent planned local hosting; no download badge, release date or downloadable-app visual.
- **Failure/loading:** retain existing server rendering, eager hero loading and lazy secondary images. Empty/invalid media values use the current `PlaceholderImageComponent`. A broken valid URL has no custom public error recovery today; verify assets before publication. Page/registration/permission/vendor failures remain with their existing handlers; illustration adds no request or loading state.
- **Accessibility/locales:** maintain current alt text supplied from localized heading/title props. All essential meaning remains in the adjacent HTML. Images contain no visible or accessibility wording embedded in SVG; the same artwork works for `en` and `zh-CN`. Preserve every current string and translation key.

## 7. Production handoff plan and acceptance

1. **Art proof:** create A01 (Home), A04 (brand studio) and A09 (local desktop) first. Review a contact sheet at actual hero/card sizes for attractiveness, recognisable product storytelling and consistent depth; these establish the remaining collection's finish.
2. **Asset production:** complete the 12 scene designs and three hero derivatives. Deliver the 15 named SVG masters plus matching WebP exports and a crop contact sheet. SVGs use only native vector shapes/gradients/filters; no embedded words, raster images or external dependencies. Target WebP ≤300 KB per hero and ≤150 KB per ordinary scene while keeping edges/shadows clean.
3. **Publish through existing media:** `UploadMedia` currently accepts JPEG/PNG/WebP/GIF, not SVG. Upload the WebP exports under customer `81721200` using the normal Website media workflow and record each returned `/81721200/site/media/<signed_id>` URL against the filenames above. Do not use bare `/assets/...` paths: `Href.media?` does not recognise them. Normal upload retains centered `object-cover`; assistant-imported media uses whole-photo fitting and is not the intended path here.
4. **Apply exact mapping:** a later implementation updates the five hero media assignments and 22 locale-catalog media leaves, identically in both locales. Preserve all wording, props, section types and order. Validate the source definition before any deliberate source restore; `HomeSite.apply!` replaces source-page owner edits, so publication must use the existing owner review workflow. Add matching imagery/media notes to `doc/reference/en/website-builder.md` and `doc/reference/zh-CN/website-builder.md` with that future source change.
5. **Visual acceptance:** check all five pages at 375, 768, 1024 and 1440px in both locales; also check 320px and 200% zoom. Main subjects survive center cropping, browser chrome is not doubled, adjacent cards have different silhouettes, shadows are smooth, no extra overflow appears, and Coming soon remains clearly visible. Confirm 27 mapped props and **24 rendered images**, with the three Home step assignments still latent.
6. **Implementation verification:** run the targeted HomeSite service spec and existing affected public/component request specs; verify media URLs resolve and wording/action targets remain unchanged. This design-only task does not claim production implementation, generated assets or runtime test results.

**Handoff status: READY_FOR_FRONTEND** — asset composition, names and placement mapping are specified; artwork production precedes media integration.

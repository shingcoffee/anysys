# Embedded illustration wording — UX handoff

Date: 2026-10-06 · Role: anysys-ux-designer · Design only

## 1. Decision and evidence

**Add 20 short, translated labels across all 15 bundled illustrations, using one new `Websites::IllustrationComponent`.** Integrate wording into existing panel headers, conversation panels and physical nameplates. Labels identify the subject or draft stage; surrounding HTML continues to explain the product.

Recommended delivery: the component pairs the existing native `<img>` with an aligned, inline **SVG text-and-nameplate layer**. Both layers share the same center crop and transforms. This looks embedded in the illustration, while retaining native image alt text, eager/lazy loading and browser caching. Select it in `SectionComponent#render_media` for the exact 15 known bundled paths, using the existing media validation. Labels are translated at render time, not saved into page props.

The user's request supersedes the earlier prohibition on wording inside illustrations. Static artwork can remain a shared, word-free base; the rendered illustration includes localized SVG `<text>`. The older instruction requiring any labels to sit in separate HTML is superseded.

Design reference supplied by the parent: [shadcn Card](https://ui.shadcn.com/docs/components/card), specifically CardTitle's short subject heading and Badge's restrained state hierarchy. Apply that hierarchy inside the drawn scene through ViewComponent, Tailwind and native SVG geometry. The shadcn skill/MCP is unavailable in this session; this handoff uses the parent's consultation.

Reviewed:

- `.cursor/agents/anysys-ux-designer.md`, project frontend/I18n conventions, all 15 SVG sources.
- Existing imagery specifications dated 2026-10-06; English and Chinese `website-builder.md` bundled-imagery guidance.
- `SectionComponent#render_media`, public section templates, `FittedPhotoComponent`, public helpers, both HomeSite locale catalogs and reusable label keys.
- Existing native contact sheet `/tmp/opencode/anysys-art-native-sheet.png`, tablet crop sheet `/tmp/opencode/anysys-ux-live-crops-768.png`, and updated mobile art proof `/tmp/opencode/anysys-imagery-review-after.png`.

These are existing proofs, including pre-refinement imagery in the native/tablet sheets. Coordinates below use the **current source transforms**, including the approved Home, AI and privacy refinements. The initial handoff did not browser-render the wording. The release refinement in §5.1 incorporates the implemented label contact sheets, clipping proofs and fresh temporary-DOM font measurements; frontend application and release crop acceptance of the revised geometry remain pending.

### Narrow-delivery alternatives

| Approach | Assessment |
|---|---|
| Native image + inline SVG wording, inside one ViewComponent | **Recommended.** Source-unit coordinates, natural rotations, native image accessibility/loading, no asset variants or runtime file parsing. |
| One inline SVG containing an `<image>` and translated `<text>` | Equally natural visual composition, but SVG `<image>` does not preserve the existing native `loading="lazy"` contract. The two-layer version is a smaller integration. |
| Positioned HTML badges | Easy screen-size typography, but labels look like page chrome floating over art; matching source crops and rotations requires extra positioning logic. |
| Separate English/Chinese asset exports | Duplicates 15 assets, complicates stored URL preservation and freezes wording into files. |

## 2. Surface inventory and layout

All affected marketing surfaces are **public**; anonymous and authenticated visitors see the request-locale presentation.

| Surface | Existing rendered media | Slots |
|---|---|---:|
| `/81721200/site` | Cinematic hero; AI split; website bento ×3; desktop cards ×3 | 8 |
| `/81721200/site/platform` | Centered hero; capability bento ×3; alternating website features ×3; desktop cards ×3 | 10 |
| `/81721200/site/pricing` | Centered hero | 1 |
| `/81721200/site/about` | Centered hero; principles bento ×3 | 4 |
| `/81721200/site/contact` | Centered hero | 1 |
| **Total** | **15 shared assets, 24 rendered slots** | **24** |

The definition has 27 media assignments. Home's three Steps image props remain latent because `StepsComponent` renders numbers and text. The existing full-section preview receives the same component treatment wherever it calls `render_media`.

Region contract:

```text
Existing section/card HTML: localized heading, explanation and actions
┌ Existing responsive, rounded, clipped image frame ──────────┐
│ Existing artwork                                          │
│   Drawn panel header / bubble / drawer plate               │
│   └ Translated short SVG label, rotated with that subject  │
└───────────────────────────────────────────────────────────┘
```

- Artwork source: saved `WebsitePage.sections[*].props.image_url`, including nested cells/cards/items.
- Alt: the existing caller's headline, heading or item title, including literal owner copy.
- Wording: stable illustration metadata maps the known source to I18n keys. It is independent of saved section copy and nested item ordering.
- The noun label has CardTitle prominence. `Draft` is the only state wording and is confined to draft illustrations. Nameplates have soft corners and no action affordance.
- Existing HTML supplies primary and secondary actions. Illustration labels are read-only, with no focus, links, tooltip or click target. There is no destructive illustration action.

## 3. Exact copy and I18n

Use these English/Chinese pairs, with no punctuation, interpolation, all-caps treatment or bilingual duplication in one image. Reuse the verified identical English keys below. Add only the three new pairs to `config/locales/website_home_site.en.yml` and `website_home_site.zh-CN.yml` under `website.home_site.illustration`.

| Token used below | English | zh-CN | I18n key |
|---|---|---|---|
| records | Records | 记录 | `settings_people.icons.rectangle_stack` |
| website | Website | 网站 | `chrome.sidebar.pages.website` |
| draft | Draft | 草稿 | `website.home_site.preview.draft` |
| theme | Theme | 主题 | `website.platform.catalog.theme.swatches` |
| preview | Preview | 预览 | `common.labels.preview` |
| forms | Forms | 表单 | `chrome.menu_bar.items.forms` |
| members | Members | 会员 | `settings_navigation.groups.members` |
| payments | Payments | 支付 | `chrome.menu_bar.items.payments` |
| email | Email | 邮件 | `chrome.menu_bar.items.email` |
| sms | SMS | 短信 | `chrome.menu_bar.items.sms` |
| local_data | Local data | 本地数据 | **New:** `website.home_site.illustration.local_data` |
| plan | Plan | 套餐 | `settings_navigation.items.plan_subscription` |
| idea | Idea | 想法 | **New:** `website.home_site.illustration.idea` |
| goals | Goals | 目标 | **New:** `website.home_site.illustration.goals` |

Metadata stores keys, not translated Ruby constants. Resolve `t(key)`/`I18n.t(key)` for each render using the current request locale, with normal ERB text escaping. New English values must be byte-identical to this table; new en/zh-CN key sets must match.

`Plan` identifies one illustrative tier without naming a price or available offer. `Idea` and `Goals` identify conversation subjects without suggesting a functioning contact channel. `Local data` identifies the local-hosting concept; the existing Coming soon wording remains the availability explanation. There are no invented prices, balances, delivery receipts, published/live statuses or privacy guarantees inside the art.

## 4. Coordinate and typography contract

**Use SVG `viewBox` units, not the file's width/height attributes.** Home has `viewBox="0 0 2400 1030"`. Every other illustration, including the four 2400×1500 hero files, has `viewBox="0 0 1600 1000"`.

- A plate is an opaque rounded rect that covers the old abstract header bars or forms an attached nameplate. Plate tuple: `(x, y, width, height)`. Text tuple: `(x, baseline-y, font-size)`.
- Coordinates below are local to the listed transform. Apply transforms in nested outer → inner groups exactly as written. Do not transform the base image again: it already contains those transforms.
- Text uses Tailwind `font-sans font-semibold`, weight 600, normal tracking, explicit SVG `font-size` in source units, and start anchoring unless `middle` is specified. Baselines use ordinary SVG alphabetic positioning. Same coordinates/font size in both locales.
- Ordinary header plate radius: 10 source units. Home rear header radius: 6. Drawer radius: 17. Front-glass nameplate radius: 12. No outline, letter shadow, embossed type or new filter.
- Colors are artwork presentation attributes, not custom CSS. Style tokens: **L** = fill `#FAF9FF`, text `#3C286B`; **D** = fill `#493481`, text `#FFFFFF`; **P** = fill `#FFE8D9`, text `#64324E`; **M** = fill `#D9F8ED`, text `#24594F`; **R** = fill `#E0AFAD`, text `#64324E`. **V** uses the asset-specific lavender fill listed below, with text `#3C286B`.
- Plates must cover the existing bars completely. They may enlarge a header into its surrounding blank space. Preserve nearby icons, avatars, image selections, shields, device outlines and connector endpoints.
- Maximum text widths below are fit bounds, **not** instructions to stretch/compress text with `textLength`. Keep normal glyph proportions and full wording. Verify real English and Chinese system-font metrics before acceptance.

### Complete asset placement specification

All filenames are relative to `public/site-images/anysys/`. Each asset gets its listed labels in every rendered reuse.

| Filename | In-scene location / token | Exact overlay transform | Plate / style | Text / anchor / max width |
|---|---|---|---|---|
| `anysys-home-workspace-hero.svg` | Central white record table title: **records** | `translate(-172 -30.9) scale(1.06)` | `(991,373,348,60)` / L | `(1000,423,64)` / start / 328 |
| ↳ same | Rear website browser title, above the page content: **website** | outer `translate(-172 -30.9) scale(1.06)`; inner `rotate(7 1650 440)` | `(1467,166,332,58)` / L | `(1480,216,56)` / start / 306 |
| `anysys-ai-draft.svg` | Foreground form header, after the violet icon: **draft** | outer `translate(144 90) scale(.82)`; inner `rotate(3 861 667)` | `(741,482,280,64)` / V `#E9DDF9` | `(750,541,80)` / start / 262 |
| `anysys-website-draft.svg` | Foreground dark landing-page heading: **draft** | `rotate(-2 806 500)` | `(480,317,305,90)` / D | `(492,389,72)` / start / 281 |
| `anysys-brand-studio.svg` | Preview navigation title, between its violet logo and right-side links: **theme** | none | `(655,294,295,76)` / L | `(670,354,64)` / start / 265 |
| `anysys-review-publish.svg` | Foreground page's dark hero heading: **preview** | `rotate(4 984 535)` | `(707,369,325,80)` / D | `(718,434,72)` / start / 303 |
| `anysys-records-forms.svg` | Rear table header after its square icon: **records** | `rotate(-3 704 478)` | `(353,302,470,59)` / D | `(365,351,64)` / start / 446 |
| ↳ same | Foreground form header after its field icon: **forms** | `rotate(4 1113 555)` | `(1008,307,270,70)` / V `#E9DEF9` | `(1017,365,64)` / start / 252 |
| `anysys-members-payments.svg` | Foreground profile title below the portrait: **members** | `rotate(-3 716 566)` | `(508,539,407,78)` / L | `(716,602,64)` / middle / 383 |
| ↳ same | Payment-method sheet title, above the chip/card details: **payments** | `rotate(7 1120 661)` | `(940,500,346,62)` / L | `(953,548,64)` / start / 320 |
| `anysys-email-sms.svg` | Letter's lavender header after its square icon: **email** | `rotate(-7 653 500)` | `(511,342,338,73)` / V `#EBE1F8` | `(521,397,64)` / start / 318 |
| ↳ same | Phone's first lavender message bubble: **sms** | `rotate(7 1118 471)` | `(1006,340,190,68)` / V `#E7D9F7` | `(1010,392,64)` / start / 182 |
| `anysys-local-desktop.svg` | Monitor content's top heading, above the table: **local_data** | `matrix(.99 .06 -.08 .99 68 -46)` | `(515,214,508,65)` / L | `(526,264,64)` / start / 486 |
| `anysys-record-control.svg` | Drawer-front physical nameplate: **records** | none | `(640,714,320,77)` / R | `(800,768,64)` / middle / 296 |
| `anysys-local-privacy.svg` | Attached nameplate at lower left of front glass; shield remains clear at right: **local_data** | `translate(-120 -75) scale(1.15)` | `(442,674,389,77)` / L | `(458,730,64)` / start / 357 |
| `anysys-platform-workspace-hero.svg` | Central indigo table header after its square icon: **records** | `rotate(2 826 587)` | `(611,398,342,76)` / D | `(620,461,72)` / start / 324 |
| `anysys-pricing-growth-hero.svg` | Second tier's table header; neutral sample heading: **plan** | `rotate(-3 621 526)` | `(542,402,182,68)` / D | `(633,459,72)` / middle / 166 |
| `anysys-about-idea-hero.svg` | Peach idea bubble at lower left: **idea** | `rotate(-6 448 584)` | `(332,493,223,95)` / P | `(344,559,72)` / start / 199 |
| `anysys-contact-conversation-hero.svg` | Left conversation panel's peach header after its icon: **idea** | `rotate(-7 533 499)` | `(394,339,310,73)` / P | `(403,394,72)` / start / 292 |
| ↳ same | Right conversation panel's mint header after its icon: **goals** | `rotate(6 1091 616)` | `(960,454,293,79)` / M | `(966,519,72)` / start / 277 |

Paint plates and text above the base image. These locations are exposed foreground surfaces, or an exposed rear header; they avoid the need to reconstruct the illustration's occlusion tree. The privacy label deliberately attaches to the glass, rather than pretending text behind glass is on top of it. Repeated labels use the same definition, not per-page copies.

## 5. Responsive rendering and accessibility

The component's outer frame receives the caller's positioning, sizing, stacking, transition and hover classes. Inside it:

- Native image: absolute full-size, centered `object-cover`, existing `src`, unchanged supplied `alt`, `loading="eager"` for heroes / `lazy` otherwise, `decoding="async"`.
- Inline SVG: `absolute inset-0 size-full pointer-events-none`, matching source `viewBox`, **`preserveAspectRatio="xMidYMid slice"`**, `aria-hidden="true"`, `focusable="false"`.
- Clip the composed frame; caller's rounded frame remains the outer silhouette. Scale the composed frame on hover so art and words stay locked together. `object-cover` alone cannot set the inline SVG's crop; `slice` is required.
- Use one native image accessibility node. The overlay has no role, accessible name, duplicate alt or focusable child. Essential meaning remains in the existing alt and adjacent HTML. When the caller supplies empty alt for decorative imagery, retain that behavior.
- No fixed-width page layout, new stylesheet, webfont, JS or Stimulus controller. SVG geometry/paint/font-size attributes and existing Tailwind utilities supply the presentation.

Protect the established crops: Home 4:3 → 16:9 → 21:9; AI 4:5 → 5:4; centered heroes 16:10; desktop cards 4:3; alternating features 4:3 → 16:10; bento variable width with the existing fixed-height frames and 1.03× hover enlargement.

Require an effective rendered font-size floor of **at least 12 CSS px** for these bundled labels in the existing frames at CSS viewport widths ≥320px, including the release's 200%-zoom-equivalent layouts. Measure source font size × the scale of `getScreenCTM()`'s text x-axis, including nested scene transforms. A 64-unit ordinary label renders at about 12.3px in a 192px-high bento; AI's 80-unit label compensates for its .82 scene scale. Pricing/About/Contact and the refined Platform title use 72-unit type to stay about 12.6px at a 280px-wide mobile hero. Home's refined 56-unit rear title measures about 12.10px at 320px. The two former sub-12px values are corrected rather than waived.

All label ink and plate corners must survive the strictest reuse, including About's AI/platform bento and Home's portrait AI image. Maintain the existing image frame sizes. If browser metrics reveal overflow, first adjust the local plate within its blank header space or shorten only through a reviewed paired translation; do not truncate wording, shrink it below the readability target or move it into a detached caption.

### 5.1 Release refinement — four approved label corrections

Evidence reviewed: `/tmp/opencode/illustration-wording-release-report.md`, `wording-clipping-proof-sheet.png`, both `wording-contact-sheet-{en,zh-CN}-{320,1440}.png` pairs, and `wording-clipping-source-metrics.json`. Release found Theme/主题 clipping in Home/About's wide fixed-height bento, including complete disappearance at 767px. It also measured Home's rear Website at 11.24px and Platform's Records at 11.20px at 320px. The complete table above incorporates the following approved revisions.

The final 767px edge check additionally found the rear Records plate in `anysys-records-forms.svg` clipped by approximately 3px normally and 6px on hover. The parent approved a fourth narrow correction: translate that plate and text down 22 source units within the existing dark header.

| Label | Approved plate / text | Deviation rationale and panel fit |
|---|---|---|
| Theme / 主题 | Plate **`(655,294,295,76)`**; text **`(670,354,64)`**; max width **265**; no transform; L; radius 10 | Approve the release candidate. Relocate from the editor toolbar into the preview's blank navigation strip, retaining 64-unit type. Plate begins at x=655, 13 units after the logo's right edge x=642, and ends at x=950, about 12.5 units before the first link stroke at x=962.5. Its bottom y=370 meets, without covering, the hero content's top y=370; selected-image handles begin lower at y=382. It reads as the preview's title, integrated into the illustrated page. |
| Website / 网站 | Plate **`(1467,166,332,58)`**; text **`(1480,216,56)`**; max width **306**; retain both transforms, L and radius 6 | Increase source type 52→56 to meet the mobile floor. Taller plate and baseline 207→216 accommodate the Chinese glyphs. Plate fits the rear white panel from its top y=166 to y=224, leaving 6 units before actual page content starts at y=230. It covers the title area's central separator segment at y=214 as an attached nameplate; nearby browser dots remain clear. |
| Records / 记录 — Platform asset | Plate **`(611,398,342,76)`**; text **`(620,461,72)`**; max width **324**; retain rotation, D and radius 10 | Increase source type 64→72. Preserve the baseline and move the plate's top up 9 units, into the table shell's blank upper margin, to support Chinese ascenders. The plate stays inside the shell beginning at y=384; its bottom y=474 leaves 20 units before the white table body. Its left edge clears the icon ending at x=604 by 7 units; its right edge x=953 clears the badge starting at x=981 by 28 units. Apply this asset definition to the About reuse too. |
| Records / 记录 — Records/Forms asset | Plate **`(353,302,470,59)`**; text **`(365,351,64)`**; max width **446**; retain `rotate(-3 704 478)`, D and radius 10 | Move the plate and baseline down 22 units to address the final 767px normal/hover crop clipping. The plate spans y=302–361 inside the dark panel at y=256–764, covers the original header bars at y=304/320 and leaves 6 units before the white data body begins at y=367. Its left edge x=353 clears the header icon at x=295–328. |

Fresh Chrome measurements used temporary DOM text attributes only; no production source or saved content was changed. At 320px, the candidate Home rear type measured **12.1025 CSS px** and Platform type **12.60 CSS px**. English text widths were approximately 217.5 and 285.7 source units respectively, within their existing width bounds. Canvas ink metrics for Chinese gave Website ascent/descent 47/7 units and Records 60/8 units: the approved baselines place their ink at y=169–223 and y=401–469, inside the revised plates.

For Theme, the fresh 64-unit text `getBBox()` at baseline 354 began at approximately y=291.5, with English width 213.5 units and Chinese width 125 units. This clears the release's worst 767px hover crop top y≈287.87 by about 3.6 units; the plate starts at y=294. Ascent/descent whitespace can extend beyond a nameplate even when glyph ink fits. Use BBox polygons to check frame clipping, actual ink/visual inspection to check lettering against its plate, and account for the rounded corners. These measurements support design approval, not a completed release pass.

Frontend/release recheck: Home/About Theme at 640, 720, 767 and 768 CSS px, normal and 1.03× hover, in both locales; the existing 512/720 CSS-px DPR-2 zoom equivalents; Home Website and Platform Records at 320px; the Records/Forms rear Records plate at 767px, normal and 1.03× hover, in both locales; and all four labels in their larger existing reuses. Confirm the ≥12px floor, complete plate/text visibility and the specified logo/icon/nav clearances. These are corrections to the four label definitions only.

## 6. Interaction, states and owner preservation

1. Visitor opens any listed public URL → existing image URLs render with the corresponding request-locale wording → existing section actions lead to Platform, Pricing or signup as before.
2. Visitor uses the existing language dropdown → native GET to the same page with `locale=en` or `locale=zh-CN` → image wording and source-backed presentation follow that locale. Existing internal links continue carrying locale. No record write occurs.
3. Owner changes a media URL through the existing builder → that stored URL determines the presentation. An upload, HTTPS photo or any other custom media follows its existing image/fitted-photo path. An exact bundled path gets its defined scene labels. Reordered cards remain correct because selection is by URL, not array position.
4. Owner edits heading/body/alt-driving copy → existing read-only HomeSite localization rules preserve owner-authored text. The illustration does not translate, replace or save that copy.

State contract:

- **Normal:** static scene with a short noun/state label. No generated output or editable field is implied by the overlay itself.
- **Loading:** retain native image loading and the reserved frame. SVG wording is server-rendered with the page and may precede the image decode; its restrained plates require no loader or animation.
- **Empty/invalid/unknown media:** existing placeholder or valid custom-image behavior from `render_media`; no speculative illustration label.
- **Broken valid image URL:** existing native image/alt behavior; no fabricated support or retry panel. Bundled files are verified during release.
- **Navigation, authorization, validation or vendor failure:** existing handlers and screens; this read-only imagery adds no action endpoint or vendor dependency.

Keep stored URLs, section/list order, ids, publication flags, custom media and custom copy intact. Integrate through the render path rather than `HomeSite.apply!`, migrations, seeds, asset generators or automatic content updates. Recognition is an explicit map of the 15 complete local paths, not a basename match against arbitrary owner URLs. Render fixed SVG overlay markup and escaped translations; reading/inlining user SVGs is unnecessary.

## 7. Component reuse and implementation handoff

| Piece | Component / contract |
|---|---|
| New illustration composition | `Websites::IllustrationComponent.new(src:, alt:, css_class:, eager: false)`; immutable path → viewBox/label-key/geometry metadata; locale read at render time |
| Selection | Existing `Websites::SectionComponent#render_media`; validated known bundled media dispatches to the new component |
| Custom media / missing media | Existing `FittedPhotoComponent`, native image branch, `PlaceholderImageComponent` |
| Frames and layout | Existing `Sections::{HeroCinematic,HeroCentered,SplitImageText,BentoGrid,AlternatingFeatures,CardGrid}Component` and `PageComponent` |
| Language and actions | Existing `LanguageSwitcherComponent`, public href helpers, `SectionHeaderComponent`, `SectionButtonsComponent`, navigation and footer |

Frontend acceptance:

1. Cover all 15 mapped assets / 24 existing slots with the 20 labels above, in both locales. Verify complete en/zh-CN font fit, contrasting type and natural attachment to each drawn subject.
2. Inspect all five pages at 320, 375, 768 and 1440px, plus Home's 640px hero breakpoint, bento hover and 200% zoom. Words and plates must remain inside the crop, align with the image and introduce no page overflow. Preserve the approved Home/AI/privacy artwork transforms.
3. Verify locale switching after rendering English then Chinese in the same process; no cached English labels or translated constants. Owner custom images and copy must survive both requests without writes.
4. During implementation, add targeted component/section integration coverage for known-path selection, English/Chinese text, native alt/loading behavior, crop metadata and custom-media fallthrough. Run affected Website component/request specs plus `spec/services/websites/home_site_spec.rb` and `home_site_localization_spec.rb`. Static-base vector/security assertions can remain; wording belongs to component output.
5. Update **both** `doc/reference/en/website-builder.md` and `doc/reference/zh-CN/website-builder.md` with the code change: replace the HTML-only label prohibition with render-time localized SVG wording, describe exact known-path selection, shared base files, read-only presentation and custom-media preservation. Earlier imagery UX documents are historical; this handoff is the wording decision.

**Status: READY_FOR_FRONTEND.** Release refinement approves the four revised label geometries above. Frontend application and fresh browser acceptance of those corrections follow this design-only update.

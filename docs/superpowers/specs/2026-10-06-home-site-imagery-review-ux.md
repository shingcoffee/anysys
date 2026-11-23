# Home-site imagery review — UX handoff

Date: 2026-10-06 · Role: anysys-ux-designer · Research/review only

## Decision

**Retain the cohesive collection. Refine two crop failures and give one illustration a restrained contrast lift; retain the other 12 assets.** The lavender/porcelain surfaces, dimensional shadows, indigo structure and peach/mint accents already form an attractive SaaS marketing system. Different silhouettes make the collection feel designed rather than repetitive. No new UI surface or component is needed.

The official [shadcn new-york-v4 Card registry](https://ui.shadcn.com/r/styles/new-york-v4/card.json) was consulted again for this review: rounded frames, fine borders, restrained shadows and clear content hierarchy support the existing direction. Continue through the project's ViewComponent + Tailwind conventions.

## Evidence and surface inventory

Chrome/Playwright reviewed **all 15 assets** in a fresh browser-rendered native contact sheet and **all 24 rendered placements at 375, 768 and 1440px**. All five public pages returned HTTP 200. A separate 375px Chinese pass confirmed localized, nonempty image alt text on every placement and no horizontal page overflow. The three Home step image assignments remain latent; they are not rendered media regions.

| Public surface | Media regions reviewed |
|---|---|
| `/81721200/site` | Home hero, AI split, website bento ×3, local-desktop cards ×3 |
| `/81721200/site/platform` | Platform hero, capabilities bento ×3, alternating website features ×3, local-desktop cards ×3 |
| `/81721200/site/pricing` | Pricing hero |
| `/81721200/site/about` | About hero, principles bento ×3 |
| `/81721200/site/contact` | Contact hero |

**Measured crop constraints:** all illustrations use centered `object-cover`. Home hero: 335×251 at 375px, 704×302 at 768px, 1184×507 at 1440px; its responsive ratios are 4:3 / 16:9 / 21:9. AI split: 335×419 portrait (4:5), 328×262 and 552×442 landscape (5:4). Other heroes are 16:10. Desktop cards are 4:3. Current bento cells are **192px high**, with widths approximately 335 / 221 / 381px at the three viewports; their effective ratios differ substantially. Platform alternating features are 4:3 on mobile and 16:10 at larger widths.

Before evidence:

- All assets, native: `/tmp/opencode/anysys-ux-native-sheet.png`.
- All live placements: `/tmp/opencode/anysys-ux-live-crops-375.png`, `/tmp/opencode/anysys-ux-live-crops-768.png`, `/tmp/opencode/anysys-ux-live-crops-1440.png`.
- Home mobile defect: `/tmp/opencode/ux-before-home-375-0-anysys-home-workspace-hero.png`.
- AI portrait defect: `/tmp/opencode/ux-before-home-375-1-anysys-ai-draft.png`.
- Privacy detail: `/tmp/opencode/ux-before-home-375-7-anysys-local-privacy.png`.
- Page context: `/tmp/opencode/ux-before-{home,platform,pricing,about,contact}-en-{375,768,1440}-full.png` (expand braces).
- Prior corroborating proofs: `/tmp/opencode/anysys-art-native-sheet.png`, `/tmp/opencode/anysys-art-responsive-proof.png`.
- Measured dimensions, source URLs and English/Chinese alt text: `/tmp/opencode/anysys-ux-imagery-report.json`.

## Complete asset review

Every filename below is relative to **`public/site-images/anysys/`**. Retain decisions are based on both the native sheet and the asset's actual placements in all three live crop sheets.

| Exact filename | Decision | Visual finding |
|---|---|---|
| `anysys-home-workspace-hero.svg` | **Refine, priority 1** | Desktop has a strong workspace/site/form hierarchy. Mobile cuts through the right website shell and artwork, weakening the two-product story. Shift the existing scene left; peripheral request cropping is acceptable. |
| `anysys-ai-draft.svg` | **Refine, priority 1** | Layered records/form/page drafts read well in landscape and About's bento. The Home portrait clips the request bubble/table on the left and page on the right. Layer overlap itself is intentional and useful; reduce the scene uniformly. |
| `anysys-website-draft.svg` | Retain | Distinct page stack, clear landing-page silhouette and mint/peach content blocks survive the wide bento, narrower tablet cell and alternating-feature crops. |
| `anysys-brand-studio.svg` | Retain | Strong frontal editor, theme rail and swatch strip remain recognizable in all placements. Its selected image handles appropriately suggest refinement. |
| `anysys-review-publish.svg` | Retain | Draft/public-page contrast, review lens and connecting arc remain legible. The page's darker hero supplies a convincing foreground anchor. |
| `anysys-records-forms.svg` | Retain | Rear table and forward form are differentiated by silhouette and contrast; mint form action survives capability-card cropping. |
| `anysys-members-payments.svg` | Retain | Profile disc anchors the member story; peach payment panel stays visible. Supporting profiles add depth without obscuring the subjects. |
| `anysys-email-sms.svg` | Retain | Envelope and phone are immediately distinguishable, including at tablet card width; colored message bubbles and fine connector support the dual-channel story. |
| `anysys-local-desktop.svg` | Retain | Monitor is the strongest hardware silhouette; keyboard/base survive the 4:3 frames. Good dark-to-light balance next to record control. |
| `anysys-record-control.svg` | Retain | Peach tray, record sheets and selected field are clear at card size. Provides useful warm contrast against the adjacent monitor and glass enclosure. |
| `anysys-local-privacy.svg` | **Refine, priority 2** | Crop is sound. In actual 335×251 and 373×280 cards, translucent glass, pale field bars and mint lock have weaker separation than neighboring illustrations. Lift only those details, preserving the airy enclosure. |
| `anysys-platform-workspace-hero.svg` | Retain | Connected records/form/site hub works in both its spacious 16:10 hero and About's shallow bento. No missing semantic core at reviewed sizes. |
| `anysys-pricing-growth-hero.svg` | Retain | Four ascending tiers remain distinct on mobile. Calm margins suit the pricing hierarchy; no need for extra labels, growth claims or decorative badges. |
| `anysys-about-idea-hero.svg` | Retain | Warm plinth, request and crafted page layers give About its own character; foreground image region remains recognizable in 16:10. |
| `anysys-contact-conversation-hero.svg` | Retain | Two peach/mint conversation panels and quiet central form create an open composition. Pale rear panel is deliberate depth, not a contrast defect requiring another edit. |

## Exact vector handoff

These candidates were rendered in temporary browser previews, including replacement images in the live page DOM at **320, 375, 640, 768 and 1440px**. Previewing changed no server data or production file. Comparison proof: `/tmp/opencode/anysys-ux-candidate-proof.png`; individual candidates: `/tmp/opencode/ux-candidate-{home,about}-<width>-<asset-basename-without-anysys>.png` for applicable placements.

### 1. Home: translate the subject 100 source units left

File: `public/site-images/anysys/anysys-home-workspace-hero.svg`.

Change the existing outer scene transform from `translate(-72 -30.9) scale(1.06)` to **`translate(-172 -30.9) scale(1.06)`**. Keep the background, glow, orbit paths and ambient ellipse in their existing positions; keep nested rotations, panel sizes and paint order. This shifts the complete subject 100 units left on the 2400×1030 canvas, approximately 24px in the 375px mobile frame. The website's right outline and plant become complete while records and form remain prominent. The slightly left-weighted desktop arrangement remains balanced by the rear website.

### 2. AI: fit the complete draft story into the portrait safe area

File: `public/site-images/anysys/anysys-ai-draft.svg`.

Wrap the ground-shadow ellipse (`cx="825" cy="873"`) and everything following it through the final connector node in one **`<g transform="translate(144 90) scale(.82)">`**. Leave `<defs>`, the painted background rect and radial glow ellipse outside the wrapper. This is an 82% uniform scale around canvas center (800,500). Preserve individual panel rotations, layering, stroke shapes and unfinished field/image placeholders.

The 4:5 center crop exposes source `x=400–1200`; the candidate brings the request, records, form and page silhouettes inside that interval. It also retains readable outlines at 5:4 and About's 221×192 / 381×192 bento sizes. The modest increase in landscape breathing room is an accepted tradeoff for a complete portrait story. Do not replace normal overlap with a disconnected row of tiny icons.

### 3. Privacy: restrained contrast correction, no geometry change

File: `public/site-images/anysys/anysys-local-privacy.svg`. Retain its existing `translate(-120 -75) scale(1.15)`, gradients other than the specified front glass stops, and all dimensions.

| Exact target | Current → candidate |
|---|---|
| `#glass` white first-stop opacity | `.55` → **`.32`** |
| `#glass` final `#AC8BD9` stop opacity | `.35` → **`.20`**; middle `.08` stays |
| Front record header bars | stroke `#AF91CA` → **`#8B6AAF`** |
| Front record field labels | stroke `#B497CC` → **`#9373B4`** |
| Front record value bars | stroke `#CCB6DF` → **`#AA8DC6`** |
| Outer front-glass rect (`x=398,y=307,w=706,h=471`) | stroke `#F7F0FF` → **`#C4ACE4`**, keep 3-unit stroke |
| Mint shield fill opacity | `.72` → **`.9`** |
| Inset shield outline | stroke `#78B9A7` → **`#5B9F8F`** |
| Lock body and shackle | stroke `#70AA9A` → **`#347F73`** |

Keep white edge glints and broad soft shadows. The target is visible records behind glass and a crisp small lock, not a darker or more saturated scene overall.

## Composition and I18n rules

- Keep the porcelain/lavender backgrounds and existing indigo, peach and mint family. Maintain the current soft upper-left lighting, opaque foreground cards and quieter rear layers.
- Protect the **semantic core**, not every peripheral connector. For Home's mobile crop the source interval is approximately `x=513–1887`; for AI portrait it is `x=400–1200`. Preserve recognizable subject silhouettes inside those intervals. Allow only nonessential request edges/orbits to crop in Home.
- Check bento artwork at actual fixed heights and narrow tablet widths, including its 1.03× hover enlargement. Preserve a recognizable foreground subject; decorative glows may bleed. Do not impose a new shared aspect ratio to conceal crop failures.
- **Keep every SVG word-free.** Current abstract bars, shapes and field handles are intentional, not untranslated labels. `spec/services/websites/home_site_spec.rb` forbids embedded text, scripts and external resources. Add no `<text>`, outlined word glyphs, plan names, currency figures, captions or language-specific raster content.
- Existing HTML already supplies meaningful localized headings, titles, explanatory copy and alt text. `Websites::HomeSite::Definition#copy` reads `website.home_site.*` at call time from **both** `config/locales/website_home_site.en.yml` and `config/locales/website_home_site.zh-CN.yml`; media alt text uses those heading/title props. Reuse this delivery. No new visible labels are warranted.
- If later wording is genuinely required, put it in server-rendered HTML outside static art, backed by paired `en` / `zh-CN` keys with matching interpolation variables. Keep English byte-identical when only changing delivery. Static art stays shared across languages. Retain localized Draft, Coming soon and contact-availability wording.

## Component reuse, flow and acceptance

Reuse `Websites::SectionComponent#render_media`, `Websites::Sections::{HeroCinematic,HeroCentered,SplitImageText,BentoGrid,AlternatingFeatures,CardGrid}Component` inside `Websites::PageComponent`. **New components: none.** Existing Tailwind responsive frame classes, centered `object-cover`, rounded containers and hover behavior are the validation frames. No new Stimulus controller is needed.

Art remains noninteractive. Existing navigation/CTAs supply the flow: Home → Platform → Pricing; signup → `/auth/sign_up`. Existing server rendering, eager heroes, lazy secondary images, placeholders and failure handling remain the relevant states; no new action, loading indicator, permission or vendor flow is introduced.

Implementation sequence: apply the two priority-1 transforms; apply the priority-2 privacy paint changes; then compare against the before crops and temporary candidates. Verify all five pages at 375, 768 and 1440px in both locales, plus 320px portrait and 640px Home 16:9. Home must retain records + form + a complete visible website edge/plant; AI must retain the complete request bubble and rear-page outline; privacy must retain airy glass with stronger field/lock separation. Recheck About's AI reuse and bento hover. The other 12 images should match their current approved appearance.

Run the existing targeted asset/mapping/localization checks during implementation, including `spec/services/websites/home_site_spec.rb` and `spec/services/websites/home_site_localization_spec.rb`. Reflect the refined crop-safe/word-free artwork guidance in `doc/reference/en/website-builder.md` and `doc/reference/zh-CN/website-builder.md` in that change. This review delivers the design document and temporary visual evidence only; it makes no production-test claim.

**Handoff: READY_FOR_FRONTEND.** Three bounded SVG refinements; existing surfaces, components and localized HTML provide the complete delivery contract.

# Embedded illustration wording — implementation plan

Date: 2026-10-06

## Goal and design

Add concise, meaningful wording inside all 15 existing marketing illustrations, covering the 24 rendered placements across Home, Platform, Pricing, About and Contact. Follow `docs/superpowers/specs/2026-10-06-illustration-wording-ux.md`: panel headings, draft labels and attached nameplates are localized at request time and aligned with each illustration's source geometry.

Use a ViewComponent combining the existing native image with an inline SVG label layer. Keep native image accessibility, eager/lazy loading and caching. Match `object-cover` with `preserveAspectRatio="xMidYMid slice"`; the wrapper receives the caller's sizing, positioning and hover transforms. Metadata stores stable translation keys, never translated constants. This supersedes the earlier HTML-only wording restriction while leaving the shared static base artwork reusable.

## Implementation lanes

1. **Frontend:** implement `Websites::IllustrationComponent` (Ruby + ERB), its exact 15-path metadata, render-media selection and focused component coverage. Follow the UX placement table, preserving the current image frame and owner-supplied alt text.
2. **Backend/content:** add the three new paired illustration translation keys, reuse existing exact-text keys, and update both `doc/reference/{en,zh-CN}/website-builder.md` pages to describe render-time SVG wording and its owner/custom-media behavior.
3. **Security:** review exact-path recognition and translation escaping. Rendering must not read/inject arbitrary SVG content or add mutable/public endpoints.
4. **QA:** verify all known paths and both locales, locale switching within one process, custom-media fallback, existing alt/loading contracts and unaffected saved-page localization. Run the targeted Website component/service/request specs.
5. **Release:** rebuild Tailwind, remove stale asset manifest before a development restart if needed, and inspect responsive browser proofs in both languages. Verify labels align, fit and survive crops at mobile/tablet/desktop widths and hover.
6. **Review:** parallel convention and correctness review; resolve findings and repeat only affected checks.

## Acceptance

- All 15 bundled scenes show the 20 specified short labels in English or Simplified Chinese according to the request locale.
- Scene labels are integrated into the illustrated panels/nameplates, with adequate contrast and intact glyphs at the smallest current placements.
- Effective label font size is at least 12 CSS px at viewport widths ≥320px, including 200%-zoom-equivalent layouts; measure source font size × the text x-axis scale of `getScreenCTM()`, including nested transforms.
- Only exact known bundled paths receive labels; custom images retain their existing rendering.
- Saved URLs, copy, section IDs/order, links and publication controls remain intact. Locale presentation performs no writes.
- Existing image alt text and eager/lazy behavior are preserved. Static bases remain self-contained and the SVG label layer is decorative to assistive technology.
- Both language reference pages and paired locale keys ship with the component change.

## Approved release refinement

Apply the four corrected label definitions in UX §5.1: move Theme into the preview navigation strip, enlarge Home's rear Website heading and its plate, enlarge Platform Records into the table's upper margin while retaining its baseline, and lower the Records/Forms rear Records plate and text by 22 source units. The revised definitions apply to every reuse, including About.

The fourth correction follows the final 767px edge check's approximately 3px normal / 6px hover plate clipping. Records/Forms now uses plate `(353,302,470,59)` and text `(365,351,64)`, retaining its rotation and styling. The plate stays at y=302–361 within the dark header, covers the original y=304/320 bars, clears the header icon and leaves 6 units before the white data body at y=367.

Fresh browser acceptance must check Home/About Theme at 640, 720, 767 and 768 CSS px, in both locales, normal and 1.03× hover; include the 512/720 CSS-px DPR-2 zoom equivalents. Recheck Home Website and Platform Records at 320px, the Records/Forms rear Records plate at 767px in both locales and hover states, and all four labels in their larger reuses. Confirm the ≥12px floor, complete plate/text visibility and logo/icon/navigation clearances. Use text BBox polygons for frame clipping and glyph ink/visual inspection for plate fit, accounting for rounded corners.

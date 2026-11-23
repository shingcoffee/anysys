# Home-site original imagery — implementation plan

Date: 2026-10-06

## Delivery decision

Use the UX specification's exact placement mapping and SVG master filenames, served directly from `public/site-images/anysys/` as `/site-images/anysys/<exact-master-filename>.svg`. This decision supersedes the UX handoff's WebP export/upload steps. Direct SVG serving keeps small vector artwork crisp at responsive sizes and ships a reproducible collection with the application, without media uploads or runtime generation. Normal Website upload/import restrictions remain JPEG, PNG, WebP and GIF, at most 8 MB; SVG uploads are not enabled.

Preserve current section types, order, ids, responsive frames, wording, links and publication behavior. Five pages contain 27 mapped image props using 15 unique assets; only 24 image slots render because Home's three step image fields remain latent.

## Implementation lanes

### 1. Frontend — original assets

- Create the 12 scene compositions and three tailored hero derivatives specified in `docs/superpowers/specs/2026-10-06-home-site-imagery-ux.md`.
- Deliver all 15 exact SVG master filenames under `public/site-images/anysys/`, with the prescribed viewBoxes, crop-safe subjects and shared visual system.
- Use self-contained vector shapes, gradients and filters. Keep artwork free of embedded wording, raster images, scripts and external dependencies; meaning and localized alt text remain in existing HTML props.
- Retain existing components, cropping, loading and interactions; Home steps stay numbers/text only.

### 2. Backend — deterministic source wiring and reference docs

Owned files:

- `app/services/websites/home_site.rb`
- `config/locales/website_home_site.en.yml`
- `config/locales/website_home_site.zh-CN.yml`
- `doc/reference/en/website-builder.md`
- `doc/reference/zh-CN/website-builder.md`
- This plan

Replace the 22 existing locale `image_url: placeholder` leaves using the UX mapping with `.svg` public paths. Add the five page-specific hero paths to each locale's hero hashes and remove the hardcoded hero placeholder so translated props supply the path. Both locales use identical paths; all existing text remains byte-identical.

Keep `definition` fresh, deterministic and free of IO/database access. Document Home's nine sections, custom hero artwork, all image roles, static serving, localized text, owner editing and the three non-rendering Home step fields in both reference locales. Preserve existing restore behavior; introduce no model, migration, controller or automatic content mutation.

### 3. Security — narrow media-path acceptance

Add a fully anchored media validation regex for the bundled `/site-images/anysys/` SVG filename family in `Websites::Href.media?`. Keep arbitrary root-relative media paths rejected and existing HTTPS/tenant-media behavior intact. Verify traversal, extra path segments, query/fragment suffixes, protocol-relative paths, backslashes and control characters cannot enter through the new rule. Upload/import format restrictions remain unchanged.

### 4. QA and release — integration verification

- QA updates the targeted HomeSite, media-validation, localization and relevant component/public request specs after the implementation lanes merge.
- Assert all 27 source paths match the UX placement map with `.svg` delivery, all 15 assets exist, hero paths come from locale props, locale keys/interpolation variables remain in parity and all non-image source values stay unchanged.
- Verify definition calls perform no IO/database access and return independent hashes. Confirm owner-edited copy/images, ids, ordering, links and publication flags remain intact during public localization.
- Run targeted specs for HomeSite and affected media/public rendering behavior; no full-suite run is needed for this imagery slice.
- Check all five pages in both locales at 375, 768, 1024 and 1440 px, plus 320 px and 200% zoom. Confirm crop-safe artwork, distinct card silhouettes, unchanged Coming soon copy, no overflow and 24 rendered image slots.

## Existing-site deployment

1. Ship the SVG assets, source catalogs and narrow media acceptance together; confirm every static URL resolves before editing saved content.
2. Review customer 81721200's saved pages in the owner builder. Match sections by stable id/type and nested items by role rather than assuming owner order is unchanged.
3. Replace only original `placeholder` image fields with their mapped paths. Retain custom images, all copy, ids, structure and publication flags; preview and save through the existing page workflow. Home step fields are mapped source data but remain non-rendering.
4. Source deployment alone does not update persisted sections. This plan adds no migration, automatic runner, seed change or public-request write. `HomeSite.apply!` is a deliberate full source restore that replaces source-page owner edits and site metadata; it is not the image-only deployment mechanism. Use it only when full restoration is intended.

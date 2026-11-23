# Home-site imagery review — implementation and verification plan

Date: 2026-10-06

## Approved direction

Follow [the approved UX handoff](../specs/2026-10-06-home-site-imagery-review-ux.md): retain the collection and refine the Home hero crop, AI draft portrait fit and local-privacy detail contrast. The artwork lane has implemented these three refinements; verification below is the release acceptance checklist, not a claim of completed test runs.

## Focused implementation

1. **Artwork lane:** shift the Home scene left to retain the website edge/plant alongside records and form; uniformly scale the AI scene down for the portrait frame and About reuse; improve privacy glass, records and shield/lock separation. Use the handoff for exact vector edits. Preserve existing static filenames and validate in the current centered `object-cover` frames.
2. **I18n review:** keep all SVGs word-free, including outlined word glyphs. Existing alt text, header labels, titles and copy use the current catalogs at call time. Any future artwork labels/captions must be server-rendered I18n HTML with paired `en` / `zh-CN` keys and matching interpolation variables.
3. **Documentation lane:** update `doc/reference/en/website-builder.md` and `doc/reference/zh-CN/website-builder.md` under Bundled illustration roles with matching I18n rules, crop-safe composition guidance, the three refinements and static-path deployment behavior. Preserve existing documentation edits.
4. **Deployment:** ship the refined assets at their existing URLs. Saved image fields already referencing those URLs receive the new artwork; content reseeding or `Websites::HomeSite.apply!` is unnecessary.

## Verification

- Run the existing targeted checks:

  ```sh
  bundle exec rspec spec/services/websites/home_site_spec.rb spec/services/websites/home_site_localization_spec.rb spec/components/websites/page_component_spec.rb spec/requests/websites/home_site_localization_spec.rb
  ```

  Confirm asset/mapping integrity, the word-free SVG contract, localized source copy/alt text and preservation of owner edits during public rendering.
- Inspect all five public pages in English and Simplified Chinese at 375, 768 and 1440px; add 320px portrait and 640px Home checks. Compare with the UX before/candidate evidence. Verify complete Home website edge/plant, complete AI request/page silhouettes, clearer privacy details, About AI reuse, narrow fixed-height bento crops and hover enlargement, and no horizontal overflow.
- Confirm the existing static URLs resolve, the 24 rendered image slots remain mapped, and localized Draft, Coming soon and contact-availability wording remain correct.
- Review the paired reference additions for identical guidance, examples and asset roles; run `git diff --check` on the three documentation files.

This refinement introduces no JavaScript changes. Use targeted RSpec and visual checks; no full test-suite run is needed.

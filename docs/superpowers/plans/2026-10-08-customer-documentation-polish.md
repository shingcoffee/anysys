# Customer documentation polish — implementation plan

- Date: 2026-10-08
- Status: Ready for coordinated implementation
- UX contract: `docs/superpowers/specs/2026-10-08-customer-documentation-polish-ux.md`

## Goal and baseline

Polish the existing customer documentation homepage/reader, author all 13 guides bilingually, and embed six real screenshot subjects in each locale. Preserve the responsive shell, contents/search behavior, locale-aware customer links, and protected admin routes. Use ViewComponent + Tailwind and native image links.

The earlier customer-documentation spec/plan are separate existing artifacts. Implementation must inspect current working changes before editing: customer docs and several shared renderer/reader/locales files already contain ongoing work. Use the live `translation_scope` and `locale` contracts, not older spec names.

## 1. Lock contracts and capture handoff

Owners: coordinator, backend, frontend, content, capture.

- Agree the UX's exact `guide_groups` shape, `article_variant: :reference` / `:customer`, `home_groups: nil`, `screenshot_root: nil` / `"/help/docs/screenshots"`, and standalone Markdown image-title-as-caption syntax before parallel work.
- Keep the existing `DeveloperDocs::Repository::Page` and sidebar Entry shapes. Home cards use a separate customer guide/group value object and existing route resolution.
- Capture lane starts independently: authenticated admin-role session, localized real screens, demo data, no owner-only chrome. Produce `workspace-help.png`, `records-list.png`, `forms-publishing.png`, `website-publishing.png`, `email-audience.png`, `payment-settings.png` in both `public/help/docs/screenshots/en/` and `zh-CN/`.
- Record actual subject/state and honest fallbacks per UX §6. Content links/captions are finalized against those captures. Avoid operational writes just to obtain a screenshot; disposable demo setup is separate from live customer content.

## 2. Add customer homepage metadata

Owner: backend. Files:

- `app/services/customer_docs/repository.rb`
- `app/controllers/admin/help/docs_controller.rb`
- `spec/services/customer_docs/repository_spec.rb`
- `spec/requests/admin/help/docs_spec.rb`

Steps:

1. Add `CustomerDocs::Repository#guide_groups`: localized front-matter title/summary plus allow-listed slug and route-generated path; full catalog order, exclude overview, omit absent sources/empty groups.
2. Reuse the same repository instance for article lookup and metadata. Supply groups only for `HOME_SLUG`, including both index and explicit overview route. No query filtering of cards; existing contents filtering remains.
3. Verify links use URL customer/effective locale and exclude `q`; metadata reads reflect summary edits on the next request. Do not load/render each whole article merely to get card metadata.
4. Add focused checks for 12 non-home entries, Chinese metadata, missing sources, empty directory, body-only search match not changing cards, and URL customer differing from the owner's account customer. Keep existing auth, 404 and locale navigation request checks passing.

## 3. Implement safe captioned screenshots

Owner: backend; frontend owns generated-figure visual review. Files:

- `app/services/developer_docs/renderer.rb`
- `app/services/developer_docs/repository.rb`
- `app/services/customer_docs/repository.rb`
- `spec/services/developer_docs/renderer_spec.rb`
- `spec/services/developer_docs/repository_spec.rb`
- `spec/services/customer_docs/repository_spec.rb`

Steps:

1. Add explicit screenshot-root configuration, off by default and enabled only by customer repository configuration. Thread it into rendering/cache identity; revise fragment cache version so prior image-stripped output is not reused.
2. Recognize standalone Markdown images with valid source, nonblank alt and caption title. Generate semantic figure, escaped caption/alt, native same-path image/full-size links, translated accessible text, lazy loading and async decoding.
3. Validate exact whole-string locale/PNG URL as specified in UX §3 before link rewriting and at sanitization. Extend tag-specific allowed attributes for generated markup, retaining existing slug/heading/callout behavior. Invalid images become escaped alt text with no image/link. Default developer rendering continues stripping images.
4. Add meaningful sanitizer tests: both locale paths; escaped malicious caption/alt; external/data/SVG/protocol-relative/traversal/encoded traversal/backslash/query/fragment/whitespace rejection; event/style/srcset stripping; arbitrary full-size destinations rejected; valid figure and identical native hrefs survive final scrub. Verify policy/cache isolation and invalidation across repository instances.
5. Keep native screenshot links a deliberate exception to catalog-slug rewriting, not a generic allowance for arbitrary root-relative Markdown links or image sources.

## 4. Build homepage and reading polish

Owner: frontend. Files:

- New `app/components/customer_docs/home_guides_component.rb` and `.html.erb`
- `app/components/developer_docs/reader_component.rb` and `.html.erb`
- `app/views/admin/help/docs/show.html.erb`
- `config/locales/customer_docs.en.yml` and `.zh-CN.yml`
- New `spec/components/customer_docs/home_guides_component_spec.rb`
- `spec/components/developer_docs/reader_component_spec.rb`

Steps:

1. Implement HomeGuides `groups:` using `CardComponent`, one accessible same-tab anchor per guide, metadata descriptions, natural wrapping, decorative arrow and focus ring. Apply the exact responsive grid/reset and states in UX §2–3.
2. Add optional reader props with reference defaults; render the homepage block in the center column only when groups are supplied. Keep it outside article descendant typography. Pass customer variant/groups from the customer view.
3. Implement scoped 16px body, heading/list rhythm, 72ch reading measure and captioned figure styles. Keep tables locally scrollable, image proportions natural, and existing anchors/details/navigation intact. New utility names emitted by Ruby must be visible to the Tailwind build; use complete literal classes or narrowly safelist generated classes.
4. Add four paired UI keys from the UX table. No strings hard-coded in ERB/Ruby, no translation evaluation in constants.
5. Check normal/empty cards, localized metadata and labels, single link per card, no cards on non-home/developer readers, image link/caption markup, unchanged search/drawer contract, and customer/reference typography selection. No new JavaScript is needed.

## 5. Rewrite all bilingual guides and integrate captures

Owner: content, informed by backend/capture. Files: every `.md` under `doc/customer/en/` and `doc/customer/zh-CN/` for:

`overview`, `getting-started`, `users`, `records`, `forms`, `websites`, `payments`, `email`, `sms`, `assistant`, `settings`, `billing`, `support`.

Steps:

1. Use the UX §5 per-guide matrix. Keep the five required H2 sections in order and add task H3s/concrete substeps. Update front matter to task/outcome wording; no article H1. Remove the homepage's duplicate 12-guide list.
2. Verify action labels against current locale files/components. Check behavioral claims against controllers/services before translating. Key sources: payment MerchantAccountsController/GatewayConfig/Gateway tests, email TemplatesController/VariableContext/template editor, page audience/launch controls, website composer/site settings, authentication MFA/settings and captcha status/pages controllers.
3. Explain Save versus activation/publication/submission at the relevant step. Include customer provider setup; saved-connection test limits; current-user test personalization; tenant MFA scope and stored-but-unenforced timeout/lockout settings; password-reset disable consequences; public-form protection readiness.
4. Embed captures at the relevant steps using UX syntax and exact filenames. Use locale-specific URLs, descriptive alt, and captions matching real state. Six representative subjects are sufficient; reuse only where informative, without forcing a screenshot into each guide.
5. Update `spec/services/customer_docs/published_guides_spec.rb`: retain all-guide required-section/catalog checks; distinguish guide anchors from checked screenshot links; verify local PNG existence, locale path, nonblank captions/alt and locale parity of image basenames/subjects. Keep related-guide target parity independent of images.
6. Update `doc/reference/en/customer-documentation.md` and `doc/reference/zh-CN/customer-documentation.md` with homepage metadata/props, image syntax/policy/static-public assets, cache configuration/version, and verification paths. Update any other reference description contradicted by the implementation; keep both locales aligned.

## 6. Integrate and verify

Owners: QA, release, reviewers. Run targeted checks after the build/content/capture lanes converge:

```bash
bundle exec rspec spec/services/customer_docs spec/services/developer_docs/renderer_spec.rb spec/services/developer_docs/repository_spec.rb spec/components/customer_docs/home_guides_component_spec.rb spec/components/developer_docs/reader_component_spec.rb spec/requests/admin/help/docs_spec.rb
bin/rails tailwindcss:build
git diff --check
```

- Extend the existing service/component/request suites for the new contracts; do not run the full suite for this bounded feature. Add other targeted specs only for additional files actually changed.
- Smoke-test both locales at 320/390/768/1024/1440px and 200% zoom: homepage grid, long Chinese/English titles, article spacing, native image navigation/Back, empty search, mobile Contents and section details, previous/next, locale switch. Check desktop `lg` card reset prevents squeezed text and that tables/images never cause page-wide overflow.
- Verify all 26 sources and 12 PNGs exist, image subjects/locale/captions match, no credentials/private or owner-only chrome is pictured, and essential guidance is understandable without images.
- Verify metadata cards are current after edits, screenshot policy changes cannot reuse incompatible cached HTML, and developer-reader defaults/catalog remain correct.
- Source-only UI changes require assets rebuilt. If restarting the dev server, follow AGENTS.md asset-shadowing/manifest rules. `SKIP_AUTH=1` is for ordinary local smoke work, not customer-role screenshot capture or authorization proof.
- Coordinator obtains frontend/backend/content integration review, targeted QA, and convention/security review. Resolve concrete failures, report real test results and remaining capture limitations; leave the change ready for human review.

## Completion criteria

The existing authorized customer home shows 12 goal-based metadata cards; guides remain fully bilingual with accurate actionable procedures; six real captioned subjects render safely per locale and open natively at full size; responsive navigation/search still behaves as before; relevant developer reference matches the source changes; targeted checks and browser evidence support the result.

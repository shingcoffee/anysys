# Home-site marketing polish — focused implementation plan

Date: 2026-10-06 · Design: [UX handoff](../specs/2026-10-06-home-site-marketing-polish-ux.md)

## Outcome and source contract

Polish all five public pages with slate/violet atmosphere and more intentional panels. Prioritize dark recommended pricing, an illustrated About hero and three purposeful Contact routes. Deliver through existing props and ViewComponents, preserving saved section order.

`Websites::HomeSite.definition(locale: :en)` / `definition(locale: :"zh-CN")` is the source interface; explicit `Websites::HomeSite.apply!(locale: :en)` persists to customer 81721200. Final source counts: **Home 8 / Platform 7 / Pricing 5 / About 5 / Contact 3**. Stored image assignments: **9**; rendered images: **2/2/0/1/0**. No new JS or routes.

## 1. Parallel write lanes

### Frontend — components, presentation resolver and component specs

Own `app/components/websites/home_site/**`, `app/services/websites/home_site/presentation.rb`, `spec/components/websites/home_site/**` and `spec/services/websites/home_site/**`.

1. Update shared gradient, panel, button and footer styling; decorative elements use Tailwind and existing icons, hidden from accessibility output.
2. Center compact Pricing hero; implement four checkmark-feature cards with Starter dark violet and white CTA. Render new foundation with existing Index props.
3. Implement About hero's desktop text/media split and mobile stack; compact mission, three principles cards and rich-text craft statement. Add internal role/type variants, preserving generic editorial fallback.
4. Implement Contact welcome motif and bordered availability note; replace action group with description-bearing route cards, reading runtime `contact.routes.*` keys and saved nav/signup labels/hrefs.
5. Refine Home/Platform draft titlebar/icons/connectors, capability panels and ordered process rail. Preserve configured-service/Windows qualifications and all current media behavior.
6. Verify actual props/order remain authoritative; mapped presentation is limited to the five platform-home-site records and works in public/admin preview. Update focused specs for media modes, featured contrast classes, route omission, saved labels/actions and opaque-role fallbacks.

If a semantic-role accessor in `home_site.rb` is needed for craft styling, agree its exact small edit with backend; backend applies it as sole writer of that file. Never identify craft by English wording or array position.

### Backend — source, paired locales, reference docs and service specs

Own `app/services/websites/home_site.rb`, `config/locales/website_home_site.{en,zh-CN}.yml`, `doc/reference/{en,zh-CN}/website-builder.md`, `spec/services/websites/home_site_spec.rb` and `spec/services/websites/home_site_localization_spec.rb`. Coordinate request-level source/localization checks in `spec/requests/websites/home_site_localization_spec.rb` if affected.

1. Add exact paired UX copy. Build foundation from `pricing.foundation` using existing `heading/items` fields and blank kicker/subhead. Resolve translations at call time; reuse identical existing title keys.
2. Insert `home_site_pricing_foundation` (`feature_grid`) between plans and FAQ. Set About hero `media_mode: image` with existing idea asset; change `home_site_about_craft` to `rich_text`, retain heading/body/id and remove moved media props.
3. Preserve source matcher, catalog-generated tiers, quota/trial/reference disclaimers and Windows source assignments. Document new source composition and runtime Contact description keys in both reference locales.
4. Update meaningful source/localization checks: paired structure/copy, counts, assignment count, craft identity/type, hero media and foundation placement. Confirm changed strings localize after explicit source persistence.

### QA — browser evidence and integration checks

Own browser checks under `spec/e2e/**`, primarily `website_responsive.app.spec.js`; coordinate any `spec/requests/websites/home_site_preview_spec.rb` changes with frontend/backend. No app writes.

1. Confirm published Contact links omit unpublished destinations and honor saved labels; all signup links retain locale and destination. Check FAQ keyboard expansion and existing mobile/language navigation.
2. Capture all five pages in EN/zh-CN at desktop/mobile; inspect Pricing first-view hierarchy, About art placement, Contact full composition and Home/Platform draft readability.
3. Check 320/390/768/1024/1440 px and 200% desktop zoom, no document overflow, natural card height, focus and contrast. Assert default image placement count and source order.

## 2. Integration and completion

1. Review the existing dirty tree before work; preserve prior work and confine edits to agreed lanes. Integrate source and component changes together.
2. Run affected component/presentation, home-site source/localization and relevant public/preview request specs with `bundle exec rspec <affected files>`. Run the targeted browser checks using the repository's existing Playwright configuration. No full-suite or JS-coverage run is needed for a change that adds no JS.
3. Build Tailwind with `bin/rails tailwindcss:build`; follow AGENTS.md asset-shadowing/server instructions if a restart is needed. QA screenshots must use rebuilt assets.
4. Reconfirm current DB/source parity before explicit application; inspect/export existing site/page definitions to preserve intervening owner edits. Apply the completed paired source explicitly, then confirm section ids/order/counts and nine image assignments against persisted pages. Never call `apply!` during rendering.
5. Review bilingual reference docs, factual claims and responsive evidence. Report targeted test results and screenshots. Human review owns the commit.

**Acceptance:** all five pages visibly refined; Pricing adds exactly one foundation section; About moves rather than duplicates its image; Contact uses saved destinations and three localized runtime descriptions; catalog/disclaimers and existing navigation behavior remain intact.

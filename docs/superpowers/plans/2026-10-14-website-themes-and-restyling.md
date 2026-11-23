# Website themes and per-element restyling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Named curated themes paired with every skeleton/layout, plus section/block/element restyling in the website page builder.

**Architecture:** Theme tokens expand (12 accents, 11 font pairings, corners, neutral) and apply through CSS variables on `<html>`; `ThemePresets` + `ThemePairing` name and pair them. Section props gain a reserved `styles` object; `StyleResolver` turns validated tokens into inline CSS; templates mark nodes with `el_attrs` / `item_attrs`; the composer gets a Design block and click-to-select.

**Tech Stack:** Rails 8.1, ViewComponent, Tailwind v4.1, Stimulus, Reform, json_schemer, RSpec, Vitest.

Spec: `docs/superpowers/specs/2026-10-14-website-themes-and-restyling-design.md`

## Global Constraints

- I18n: no hard-coded user-facing strings; every key in `en` and `zh-CN` (`config/locales/website*.yml`). JS text via Stimulus values with English defaults.
- Tailwind only (inline CSS only for validated user tokens / CSS variables); Stimulus only.
- `app/javascript/**` stays at 100% Vitest lines + branches.
- Docs `doc/reference/{en,zh-CN}/{websites,website-builder}.md` updated in lockstep.
- No backward-compat shims; no auto-commit.

---

### Task A1: Theme engine v2 + font registry
**Files:** Create `app/services/websites/fonts.rb`; Modify `app/services/websites/theme.rb`, `app/assets/tailwind/application.css` (`--font-site-heading`, `--font-site-body`), `app/helpers/websites_helper.rb` (`websites_font_stylesheet(theme, sections)`), `app/helpers/member_chrome_helper.rb`, `app/views/layouts/{website,member}.html.erb` (`root_style`), `app/components/websites/public_component.rb` (button shape), `app/services/websites/contracts/site.rb`, `app/components/websites/theme_preview_swatch_component.*`, `app/components/websites/admin/theme_option_component.*`.
**Produces:** `Websites::Fonts.families`, `.stack(key)`, `.stylesheet_url(keys)`; `Theme::TOKENS`, `ACCENTS`, `TYPES`, `CORNERS`, `NEUTRALS`, `PAIRINGS`; `Theme#root_style`, `#font_keys`, `#heading_stack`, `#body_stack`, `#button_shape_class`, `#preset_key`, `#with_appearance(a)`, `#color_var(role)`.
**Tests:** `spec/services/websites/fonts_spec.rb`, `spec/services/websites/theme_spec.rb`.

### Task A2: Presets + pairing + catalog columns
**Files:** Create `app/services/websites/theme_presets.rb`, `app/services/websites/theme_pairing.rb`, migration `add_theme_key_to_website_catalog_and_pages`; Modify `app/models/{website_skeleton,website_layout,website_page}.rb` (`theme_preset_key`), `app/services/websites/catalog.rb` (seed theme_key), `app/services/websites/activities/{provision,replace_skeleton}.rb`, catalog gallery components + `concerns/websites/catalog_preview.rb` (use pairing).
**Produces:** `ThemePresets.keys`, `.tokens(key)`, `.theme(key)`, `.name(key)`, `.description(key)`; `ThemePairing.for_skeleton(key)`, `.for_layout(key)`, `.for_catalog(key)`; `Theme.for_catalog(key)`, `Theme.for_record(record)`, `Theme.for_page(website:, page:)`.
**Tests:** presets/pairing specs (every skeleton + layout key resolves to a known preset), catalog spec, provision/replace specs.

### Task A3: Settings gallery, page override, platform editor select
**Files:** Create `app/components/websites/admin/theme_gallery_component.*`, `app/components/websites/admin/theme_select_component.*`; Modify settings form component + `website_theme_picker_controller.js` (applyPreset), `save_site.rb`, page identity + new page components, `save_page.rb` + page contract (theme_key), controllers' permitted params, `websites/pages_controller.rb` + admin pages controller (`Theme.for_page`), platform skeleton/layout editor header + save activities.
**Tests:** component specs, request specs, Vitest for theme picker.

### Task B1: Styles schema, resolver, validation, section-level render
**Files:** Create `app/services/websites/section_styles.rb`, `app/services/websites/style_resolver.rb`; Modify `prop_schema.rb`, `contracts/section.rb`, `section_component.rb` (`styles`, `el_attrs`, `item_attrs`, `buttons_style`), `page_component.rb` (section wrapper style + appearance flip), `section_header_component.*`, `section_buttons_component.*`, assistant schema validator (preserve styles).
**Produces:** `SectionStyles.targets_for(type)` -> `[{ key:, kind: :section|:element|:buttons|:items, label_key: }]`, `.attributes_for(kind)`, `.valid_value?(attribute, value)`, `.sanitize(type, raw)`; `StyleResolver.new(styles, theme:)` with `#section_css`, `#section_appearance`, `#element_css(target)`, `#item_css(array)`, `#buttons_css`, `#button_shape_class`, `#font_keys`.
**Tests:** section_styles_spec, style_resolver_spec, contracts/section_spec additions, page_component_spec.

### Task B2: Mark all 47 section templates
**Files:** `app/components/websites/sections/*_component.{rb,html.erb}`.
Every text prop in the type's schema renders through `el_attrs("<prop>", class: ...)`; every list item container through `item_attrs("<array>", class: ...)`; every list-item text field through `el_attrs("<array>.<field>", class: ...)`.
**Tests:** `spec/components/websites/sections/styles_marking_spec.rb` renders each type with styles for every target and asserts the inline CSS lands on a `data-site-el` node.

### Task B3: Builder Design block + JS + click-to-select
**Files:** Create `app/components/websites/admin/section_style_component.*`, `app/components/websites/admin/style_color_field_component.*`; Modify `section_editor_component.*`, `composer_component.*`, `website_builder_controller.js`, `spec/javascript/controllers/website_builder_controller.test.js`.
**Tests:** component specs; Vitest 100%.

### Task C: I18n, docs, QA, release
All new keys en + zh-CN; docs both locales; targeted RSpec + Vitest coverage; dev server smoke of `/81721200/admin/modules/website/pages/22/edit`; tech-lead + code-reviewer review.

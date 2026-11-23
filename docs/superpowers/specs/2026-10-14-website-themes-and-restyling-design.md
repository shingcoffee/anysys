# Website themes and per-element restyling — design

Date: 2026-10-14 · Status: approved

## Goal

1. A library of named, curated website themes. Every skeleton and every layout ships paired with its best-matched theme; beauty is the top priority.
2. In the website page builder (`/:cid/admin/modules/website/pages/:id/edit`) every section, block, and text element can be restyled (color, font, size, weight, italic, alignment, background, button shape) in addition to editing its content.

## Decisions (from the user)

- Rich themes: expand tokens (more fonts, accents, corner style, neutral tone); pick a theme then fine-tune.
- Site-wide theme with an optional per-page override; adding a page from a layout offers the layout's paired theme.
- Colors: theme-aware swatches first, plus a curated palette and a custom hex picker.
- Granularity: section + block (buttons, list items) + element (each text field, including list-item fields).

## A. Theme library

### Tokens (`Websites::Theme`)

| Token | Values | Default |
|---|---|---|
| appearance | light, dark | light |
| accent | azure, ink, gold, forest, rose, violet, copper, indigo, teal, crimson, plum, olive | azure |
| type (font pairing) | sans, serif, display, grotesk, classic, modern, geometric, elegant, gallery, technical, expressive | sans |
| density | spacious, compact | spacious |
| corners | sharp, soft, round | soft |
| neutral | neutral, warm, cool | neutral |

A website's stored `theme` JSON holds the tokens plus `preset` (the named theme it started from).

Application:
- Fonts, corner radii, and the neutral grey ramp are CSS custom properties emitted by `Theme#root_style` on `<html>` (website + member layouts): `--font-site-heading`, `--font-site-body`, `--font-sans`, `--font-serif`, `--radius-*`, `--color-neutral-*`. Tailwind v4 compiles `rounded-*`, `text-site-*`, and `*-neutral-*` utilities to these variables, so all 47 sections inherit without template changes.
- New Tailwind theme utilities `font-site-heading` / `font-site-body`. `type_headline_class` -> `font-site-heading` + pairing weight/tracking; `type_body_class` -> `font-site-body`.
- Buttons take `Theme#button_shape_class` instead of a hard-coded `rounded-full`.
- Accents keep literal Tailwind class maps (5 new rows).
- `Websites::Fonts` is the font registry (family key -> display name, CSS stack, bunny.net slug). The stylesheet only requests families used by the page's theme and its section style overrides.

### Named themes (`Websites::ThemePresets`)

27 code-defined presets with en + zh-CN name/description: linen, porcelain, meridian, midnight, aurora, monochrome, obsidian, noir, broadsheet, almanac, gilded, terracotta, ember, riviera, coral, blossom, sage, sandstone, academy, pulse, stage, prism, canopy, orchard, glacier, exhibit, nightshift.

### Pairing (`Websites::ThemePairing`)

- Every skeleton key maps to one preset; skeleton-derived layouts inherit their family's preset; each standalone layout maps to its own. Replaces `Theme::CATALOG_TOKENS`.
- `website_skeletons.theme_key` / `website_layouts.theme_key` (nullable). Catalog sync fills blanks from code. The platform owner edits them in the platform skeleton/layout editors. `#theme_preset_key` resolves column -> code pairing.
- Provision / replace-skeleton set the site theme to the skeleton's preset. Galleries and catalog previews render each entry with its paired preset.

### Site settings

Theme section starts with a gallery of preset cards. Picking one sets every token radio; token fieldsets below fine-tune. A "Customized" badge shows when tokens differ from the chosen preset.

### Page override

`website_pages.theme_key` (nullable; blank = site theme). Editable in the builder's page panel; the new-page form offers "Site theme" or the layout's paired theme. Effective theme: `Websites::Theme.for_page(website:, page:)` (public page, admin preview, nav, footer).

## B. Restyling in the builder

### Storage

Section props gain an optional reserved `styles` object: `{ target => { attribute => value } }`. Blank values are dropped; an empty object is omitted. Existing flat `surface` / `spacing` / `align` are unchanged.

Targets (`Websites::SectionStyles.targets_for(type)`):
- `section` — background (custom color), heading_font, body_font, scale.
- each text prop of the type (e.g. `kicker`, `headline`, `subhead`, `body`, `quote`) — color, font, size, weight, italic, align.
- `buttons` when the type has a button pair — shape, fill, text.
- `<array>` (e.g. `cards`) when the type has a list — background, text.
- `<array>.<field>` for list-item text fields (e.g. `cards.title`) — element attributes.

Values: color/fill/text in {accent, ink, body, muted, inverse} or `#rrggbb`; item background in {band, accent_soft, accent, ink, canvas} or `#rrggbb`; section background `#rrggbb`; font in `Websites::Fonts` keys; size/scale in {xs, sm, lg, xl, 2xl}; weight in {regular, medium, semibold, bold}; italic in {italic, normal}; align in {start, center, end}; shape in {pill, rounded, square}.

### Rendering (`Websites::StyleResolver`)

- Validated tokens -> inline CSS only (never raw CSS). Theme-aware tokens resolve against the section's final theme so they recolor with the theme.
- Size/scale override `--text-site-*` on the node, preserving responsive ratios.
- Custom section background flips the section theme light/dark by luminance; custom item background sets a contrasting text color unless one is chosen.
- Templates mark nodes via `el_attrs(target, **html)` / `item_attrs(array, **html)` on `Websites::SectionComponent`; `SectionHeaderComponent` / `SectionButtonsComponent` once for shared markup. Marked nodes carry `data-site-el` for click-to-select.

### Editor

- Design block in the section inspector (`Websites::Admin::SectionStyleComponent`): Section row, then a collapsible row per target with swatches (default, theme tokens, palette, custom color), font select, size/italic/align segmented, weight select, per-row reset.
- `website_builder_controller.js` serializes `[data-style-target] [data-style-prop]` into `props.styles`, restores on section reset, and live-previews through the existing draft POST.
- Click-to-select in the admin preview iframe: hover outlines a `data-site-el` node; click opens its section inspector with the target row expanded.

### Validation

`Websites::PropSchema` accepts `styles` with only the type's targets/attributes; `Websites::Contracts::Section` checks values with `SectionStyles.valid_value?`. Styles are excluded from the AI assistant schema.

## Out of scope

Nav/footer restyling; single-item overrides; gradients/background images; theme CRUD UI.

## Testing

RSpec for theme tokens/root style, presets, pairing, fonts URL, style resolver, contracts, components, request specs, catalog seeding. Vitest 100% lines/branches for touched JS. Docs `websites.md` + `website-builder.md` in en and zh-CN.

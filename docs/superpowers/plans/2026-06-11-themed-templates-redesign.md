# Themed Templates Redesign Implementation Plan

> **For agentic workers:** Execute via anysys-* SDLC agents. Tasks A/B/C are independent (no shared files) and run in parallel. QA, release, and review follow sequentially.

**Goal:** Make the member/public rendering of page-builder pages distinctly more beautiful: six visually distinct theme presets, theme-aware public chrome, and theme-coherent inputs and layout elements.

**Architecture:** Pure visual redesign driven by `docs/superpowers/specs/2026-06-11-themed-templates-redesign-design.md` (the spec contains the exact Tailwind class strings — it is the contract; palette key names in §3.1 are FINAL). One amendment overrides spec §3.6–3.9: nothing writes a `"preset"` theme key (verified — the builder stores expanded values only), so preset chrome is resolved by **value-matching** the stored theme against `THEME_PRESETS`, with a per-hue tinted fallback for customized themes.

**Tech Stack:** Rails 8.1 ViewComponents, Tailwind v4 (literal class strings only — JIT scans .rb/.erb), Stimulus, RSpec.

**Do NOT commit** — leave all changes uncommitted on master for user review.

---

## Amendment to spec §3.6–3.9 (preset detection — REPLACES the `"preset"` key approach)

Do NOT add a `"preset"` key to `THEME_PRESETS` (it would break value-matching). Instead add to `ThemeResolver`:

```ruby
PAGE_CHROME_BG_MAP = {
  "modern"     => "bg-gradient-to-br from-slate-50 to-indigo-50",
  "minimalist" => "bg-white",
  "bold"       => "bg-rose-50",
  "elegant"    => "bg-amber-50",
  "playful"    => "bg-emerald-50",
  "showcase"   => "bg-gradient-to-br from-violet-950 via-violet-900 to-indigo-900"
}.freeze

# Fallback wash for customized themes (no exact preset match), keyed by primary_color
PAGE_CHROME_BG_BY_HUE = {
  "indigo"  => "bg-gradient-to-br from-slate-50 to-indigo-50",
  "blue"    => "bg-gradient-to-br from-slate-50 to-blue-50",
  "emerald" => "bg-emerald-50/60",
  "rose"    => "bg-rose-50/60",
  "amber"   => "bg-amber-50/60",
  "violet"  => "bg-gradient-to-br from-slate-50 to-violet-50",
  "teal"    => "bg-teal-50/60",
  "slate"   => "bg-slate-50"
}.freeze

PAGE_CHROME_HEADER_MAP = {
  "modern" => "text-gray-900", "minimalist" => "text-gray-900",
  "bold" => "text-rose-700", "elegant" => "text-violet-900",
  "playful" => "text-emerald-800", "showcase" => "text-white"
}.freeze

PAGE_CHROME_DESC_MAP = {
  "modern" => "text-gray-500", "minimalist" => "text-gray-400",
  "bold" => "text-rose-400", "elegant" => "text-violet-400",
  "playful" => "text-emerald-600", "showcase" => "text-violet-200"
}.freeze

PAGE_CHROME_CARD_MAP = {
  "modern" => "rounded-xl overflow-hidden", "minimalist" => "",
  "bold" => "rounded-2xl overflow-hidden border-t-4 border-rose-500",
  "elegant" => "rounded-lg overflow-hidden", "playful" => "rounded-3xl overflow-hidden",
  "showcase" => "rounded-2xl overflow-hidden shadow-2xl"
}.freeze
```

```ruby
# in the private section
def detect_preset(theme)
  resolved = resolve_theme(theme)
  THEME_PRESETS.each do |name, preset|
    return name if preset.all? { |key, value| resolved[key] == value }
  end
  nil
end

def resolve_page_chrome_bg(theme)
  preset = detect_preset(theme)
  return PAGE_CHROME_BG_MAP[preset] if preset

  PAGE_CHROME_BG_BY_HUE[resolve_theme(theme)["primary_color"]] || "bg-gray-50"
end

def resolve_page_chrome_header_color(theme)
  PAGE_CHROME_HEADER_MAP[detect_preset(theme)] || "text-gray-900"
end

def resolve_page_chrome_desc_color(theme)
  PAGE_CHROME_DESC_MAP[detect_preset(theme)] || "text-gray-500"
end

def resolve_page_chrome_card(theme)
  card = PAGE_CHROME_CARD_MAP[detect_preset(theme)]
  card.nil? ? "rounded-xl overflow-hidden" : card
end
```

Note `resolve_page_chrome_card` must distinguish `nil` (no preset → default) from `""` (minimalist → intentionally bare).

Layout access: layouts can't include concerns, so add `app/helpers/page_chrome_helper.rb`:

```ruby
# frozen_string_literal: true

module PageChromeHelper
  include ThemeResolver

  def page_chrome_theme(page)
    page.configuration_json&.dig("theme") || {}
  end

  def page_chrome_bg(page)           = resolve_page_chrome_bg(page_chrome_theme(page))
  def page_chrome_header_color(page) = resolve_page_chrome_header_color(page_chrome_theme(page))
  def page_chrome_desc_color(page)   = resolve_page_chrome_desc_color(page_chrome_theme(page))
  def page_chrome_card(page)         = resolve_page_chrome_card(page_chrome_theme(page))
end
```

---

### Task A: ThemeResolver + public chrome + containers (anysys-frontend-developer)

**Files:**
- Modify: `app/components/concerns/theme_resolver.rb` — apply spec §3.1 (COLOR_PALETTES with new literal keys `gradient_from`, `gradient_to`, `soft_bg`, `soft_hover`, `outline_hover`, `ring_color`, `border_accent`, `border_accent_strong`, `checked_track` from §4.12; skip `ring_offset_color`, it is a constant — hardcode `focus:ring-offset-2` where needed), §3.2 INPUT_STYLES, §3.3 LABEL_STYLE_MAP, §3.4 BUTTON_STYLE_MAP (no string surgery), §3.5 FORM_BG_MAP, §4.8 `resolve_input_classes`, plus the Amendment above. THEME_PRESETS values stay EXACTLY as they are today (value-matching depends on it).
- Create: `app/helpers/page_chrome_helper.rb` (Amendment above).
- Modify: `app/assets/tailwind/application.css` — remove the four `@source inline(...)` lines, keep an explanatory comment (spec §6).
- Modify: `app/views/layouts/public_page.html.erb` — spec §4.1 but use the helper methods (`page_chrome_bg(@page)` etc.) instead of inline resolver calls; remove the hardcoded `max-w-2xl` double-constraint per §5 ONLY for the card area — keep a `max-w-2xl` on the flash + header block so text doesn't sprawl on `form_width: full` pages; title/description move into the layout header per §4.1, so also stop rendering a duplicate title inside the card if the existing show view/page component does (check `show_title` usage in the generator and keep behavior consistent: the public chrome header now owns title/description).
- Modify: `app/views/public_pages/show.html.erb` — spec §4.2 (empty-state tweak only).
- Modify: `app/components/form_fields/page_component.html.erb` — spec §4.5 title/description typography.
- Modify: `app/components/form_fields/form_component.rb` + `.html.erb` — spec §4.6.
- Modify: `app/components/form_fields/wizard_component.rb` + `.html.erb` — spec §4.7 (connector `h-0.5 rounded-full transition-colors duration-300`, nav footer `border-gray-100`, `secondary_button_classes` upgrade).

**Steps:**
- [ ] Read spec §3, §4.1–4.8, §5, §6 and the Amendment; read each target file fully before editing.
- [ ] Apply ThemeResolver changes; run `bundle exec rspec spec/services/page_content_generator_spec.rb` to catch breakage early (do not fix generator specs — QA owns spec updates; just report failures).
- [ ] Apply chrome + container changes.
- [ ] Verify with `bin/rails runner` smoke: render `ThemeResolver` maps load, `detect_preset(ThemeResolver::THEME_PRESETS["modern"].dup)` returns `"modern"`, `detect_preset({})` returns nil... (use a tiny class including the concern).
- [ ] Grep your own diff for `.sub(` inside theme_resolver.rb — must be zero occurrences.

### Task B: Special input components (anysys-frontend-developer)

**Files:**
- Modify: `app/components/form_fields/radio_field_component.rb` + `.html.erb` — spec §4.10.
- Modify: `app/components/form_fields/checkbox_field_component.rb` (+ `.html.erb` if needed) — spec §4.11 (`input_classes` override).
- Modify: `app/components/form_fields/toggle_field_component.rb` + `.html.erb` — spec §4.12 (`toggle_track_classes` using `palette[:checked_track]` — key added by Task A; reference it by name, do not redefine).
- Modify: `app/components/form_fields/rating_field_component.rb` + `.html.erb` — spec §4.13 (amber stars, themed focus ring via `color_palette(theme)[:ring_color]`).
- Modify: `app/components/form_fields/file_upload_field_component.rb` + `.html.erb` — spec §4.14 (already extends BaseFieldComponent — `theme`/`color_palette` available).
- Modify: `app/javascript/controllers/rating_controller.js` — replace `text-yellow-400` with `text-amber-400` (spec §11).

**Steps:**
- [ ] Read spec §4.10–4.14 + §3.1 (palette key contract) and each target file fully.
- [ ] All five components extend `BaseFieldComponent` (verify; all do today) so `theme` and `ThemeResolver` are available.
- [ ] Apply changes. All Tailwind classes literal. No new Stimulus controllers.
- [ ] Run existing component specs if any exist for these files (`ls spec/components/form_fields/ 2>/dev/null`); report failures, do not rewrite specs (QA owns that).

### Task C: Layout element components + generator theme passing (anysys-frontend-developer)

**Files:**
- Modify: `app/components/form_fields/divider_element_component.rb` + `.html.erb` — spec §4.15: add `theme: {}` param, `include ThemeResolver`, `label_bg_class` masks with the resolved form background.
- Modify: `app/components/form_fields/section_element_component.rb` + `.html.erb` — spec §4.16: add `theme: {}` param + `include ThemeResolver`; linked variant uses `color_palette(theme)[:border_accent_strong]` and `[:text]`.
- Modify: `app/components/form_fields/callout_element_component.rb` + `.html.erb` — spec §4.17: add `theme: {}` + `include ThemeResolver`, accent-derived classes via `resolve_accent_palette(theme)`.
- Modify: `app/components/form_fields/quote_element_component.html.erb` — spec §4.18.
- Modify: `app/components/form_fields/heading_element_component.rb` — spec §4.19 LEVELS map.
- Modify: `app/components/form_fields/card_element_component.html.erb` — spec §4.20.
- Modify: `app/components/form_fields/alert_element_component.html.erb` — spec §4.21 (`rounded-xl shadow-sm`; semantic colors unchanged).
- Modify: `app/components/form_fields/progress_bar_element_component.html.erb` — spec §4.22.
- Modify: `app/components/form_fields/button_element_component.html.erb` — spec §4.24 (`active:scale-95`).
- Modify: `app/services/page_content_generator/layout_elements.rb` — append `#{theme_param_string}` to the constructor args in `generate_section_element`, `generate_divider_element`, `generate_callout_element` (same pattern as the existing `generate_button_element:160` / `generate_columns_element:176`).

**Steps:**
- [ ] Read spec §4.15–4.24 + §3.1 and each target file fully.
- [ ] Components gaining `theme:` MUST default it (`theme: {}`) so direct renders without theme keep working.
- [ ] In `layout_elements.rb`, mind the heredoc comma placement (mirror `generate_button_element`).
- [ ] Run `bundle exec rspec spec/services/page_content_generator_spec.rb spec/services/page_content_generator_safety_spec.rb`; report failures (expected if assertions pin old ERB output — QA owns spec updates), but fix any genuine Ruby/ERB syntax errors you introduced.

### Task D: QA (anysys-qa-engineer) — after A+B+C

- [ ] Run: `bundle exec rspec spec/services/page_content_generator_spec.rb spec/services/page_content_generator_safety_spec.rb spec/services/page_content_generator_composite_spec.rb spec/services/page_content_generator_calculated_spec.rb spec/requests/public_pages_submission_spec.rb spec/requests/public_pages_visibility_spec.rb spec/requests/member/pages_spec.rb spec/requests/maintenance/page_renders_spec.rb` plus any `spec/components/form_fields/` specs.
- [ ] Stale-test policy: where specs fail because output intentionally changed (new `theme:` args in generated ERB, new class strings), REWRITE the assertions; do not revert production code.
- [ ] Add new specs: (1) ThemeResolver preset detection — exact preset theme → preset chrome; customized theme → hue fallback; empty theme → `bg-gray-50` chrome + defaults; unknown color value → indigo fallback; (2) divider label mask resolves warm form background; (3) generated ERB passes `theme:` to section/divider/callout; (4) request spec asserting public page body contains the chrome bg class for a preset-themed page.
- [ ] All listed specs green.

### Task E: Release verification (anysys-release-engineer) — after D

- [ ] Re-run the Task D spec list; PASS required.
- [ ] `rm -f public/assets/.manifest.json`, rebuild assets, restart dev server with `SKIP_AUTH=1` on port 3000.
- [ ] Smoke-hit an admin page-render URL and a public form URL (find a published page via `bin/rails runner`); confirm HTTP 200 and themed chrome classes present in the response body.

### Task F: Parallel review — after E

- [ ] anysys-tech-lead: diff-only convention review.
- [ ] anysys-code-reviewer: diff-only correctness/security review (watch: `render inline:` injection surface unchanged, no auth changes, Tailwind literality).
- [ ] Coordinator: Playwright screenshots (~/pw-tools) of all six presets at mobile + desktop widths for visual confirmation.

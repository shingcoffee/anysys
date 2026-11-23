# Flexible Rendering Refactor Implementation Plan

> Tasks A and B run in parallel (no shared files); QA, release, review follow.

**Goal:** Make the shared member/public rendering templates and theme styling uniformly flexible: every field/layout-element type renders properly with the page theme, unknown/malformed configurations degrade gracefully and visibly, and adding a new element type or styling hook touches one place.

**Architecture:** Pure refactor — rendered output for valid existing pages must stay visually identical. Three moves: (1) a `FormFields::BaseElementComponent` giving all 16 layout elements one API (`theme:` + ThemeResolver + shared helpers); (2) a single component-emission helper in `PageContentGenerator` so every render call serializes kwargs the same way and ALWAYS threads `theme:`; (3) semantic neutral-style maps in `ThemeResolver` (`ELEMENT_NEUTRALS`) so element templates stop hardcoding gray classes, plus graceful fallbacks for unknown types.

**Do NOT commit. No visual changes for valid pages. Tailwind literal-class discipline throughout.**

---

## Contract (fixed — both tasks depend on it)

1. Every `FormFields::*ElementComponent` accepts `theme: {}` (keyword, defaulted) and inherits `FormFields::BaseElementComponent < ApplicationComponent`, which `include`s `ThemeResolver`, stores `@theme`, and exposes protected helpers:
   - `accent` → `resolve_accent_palette(theme)`
   - `palette` → `color_palette(theme)`
   - `neutral(key)` → `ThemeResolver::ELEMENT_NEUTRALS.fetch(key)`
   - `alignment_class(alignment)` (the existing left/center/right map, deduplicated from individual components)
2. `ThemeResolver::ELEMENT_NEUTRALS` (frozen hash, literal classes — single place to retune element neutrals):
   ```ruby
   ELEMENT_NEUTRALS = {
     muted_text:    "text-gray-500",
     faint_text:    "text-gray-400",
     body_text:     "text-gray-600",
     strong_text:   "text-gray-900",
     subtle_border: "border-gray-100",
     soft_border:   "border-gray-200",
     surface:       "bg-white",
     surface_muted: "bg-gray-50",
     track:         "bg-gray-100"
   }.freeze
   ```
3. Generator emission: one private helper in `PageContentGenerator` used by ALL form-field and layout-element generators:
   ```ruby
   # Emits `<%= render FormFields::X.new(...) %>` ERB with safely-serialized
   # kwargs; ALWAYS appends the theme kwarg so every component is themed.
   def render_component_erb(component_class, kwargs = {}, block: nil)
   ```
   String values serialized via existing `rb_str` (user data) or literal whitelisted strings; theme appended as `theme: (@page.configuration_json["theme"] || {})` unconditionally (components default it, so blank themes are fine — this also fixes the content-only path's conditional pass).

---

### Task A: Component layer (anysys-frontend-developer)

**Files:** create `app/components/form_fields/base_element_component.rb`; modify `app/components/concerns/theme_resolver.rb` (add ELEMENT_NEUTRALS only); modify all 16 element components + templates (`section, divider, heading, paragraph, spacer, alert, image, callout, quote, button, video, list, code_block, card, progress_bar, columns` `_element_component.rb/.html.erb`); modify `app/components/form_fields/calculated_field_component.rb` (theme-derived display classes).

- [ ] Create `BaseElementComponent` per Contract. Convert every element component to inherit it; keep each component's existing keyword params and defaults EXACTLY (only add `theme: {}` where missing); unify on private `attr_reader`.
- [ ] Replace hardcoded neutral classes in element templates with `neutral(...)` helpers where they match the ELEMENT_NEUTRALS values (gray-50/100/200/400/500/600/900, bg-white) — the emitted classes must remain IDENTICAL so no visual change. Alert semantic variant colors stay hardcoded. Rating amber stars stay. Code block dark grays stay (they're intentional terminal styling — leave).
- [ ] `ProgressBarElementComponent`: `progress_color` values map via a literal hash as today, but when `progress_color` is absent/unknown fall back to `palette[:bg]` (theme primary) instead of hardcoded indigo.
- [ ] `HeadingElementComponent` & `SpacerElementComponent` & others with Pattern C/E signatures: keep signature kwargs, add `theme: {}`, inherit base.
- [ ] `CalculatedFieldComponent`: replace hardcoded `bg-gray-50 border-gray-200 rounded-lg` display box with `resolve_radius_class(theme)` + neutrals (same emitted classes under default theme).
- [ ] Verify: `bundle exec rspec spec/components/form_fields/` green (update stale class assertions only if the emitted HTML actually changed — it mostly should not); `ruby -c` all changed files.

### Task B: Generator layer (anysys-frontend-developer)

**Files:** modify `app/services/page_content_generator.rb`, `app/services/page_content_generator/form_fields.rb`, `app/services/page_content_generator/layout_elements.rb`.

- [ ] Implement `render_component_erb` per Contract in `page_content_generator.rb`; refactor every generator method in `form_fields.rb` and `layout_elements.rb` to build a kwargs hash and emit through it (kill per-method heredoc duplication). Preserve EXACT existing param names/values per component (read each generator first); user-sourced values still go through `rb_str`.
- [ ] Theme is now passed unconditionally everywhere (single-page, wizard, content-only, columns children) — remove `theme_param_string`/`theme_hash` conditionals.
- [ ] Unknown `html_type` fallback: instead of the silent comment, render `FormFields::TextFieldComponent` with the field's name/label/required (a text input renders any scalar sensibly) AND prepend an ERB comment `<%# fallback: unknown html_type "<sanitized>" %>`. Keep the sanitization of the slug as today.
- [ ] Unknown layout `field_type`: return `<%# skipped layout element: unknown field_type "<sanitized>" %>` instead of `""`.
- [ ] Delete the redundant `FIELD_COMPONENTS` map if grep proves it unreferenced after the refactor; otherwise leave and note.
- [ ] Verify: `bundle exec rspec spec/services/` for the four page_content_generator specs — failures from intentionally reorganized ERB whitespace/arg-order are expected (report; QA rewrites), genuine errors are yours. Sanity: `bin/rails runner` generate content for an existing page (Page.find(43)) and assert the ERB still compiles via `ERB.new(...)` or a request to the public form.

### Task C: QA (anysys-qa-engineer) — after A+B

- [ ] Run + repair (stale-test policy): the 4 page_content_generator specs, `spec/components/form_fields/`, `spec/components/concerns/theme_resolver_spec.rb`, `spec/requests/public_pages_*`, `spec/requests/member/pages_spec.rb`.
- [ ] New coverage: (1) theme propagation matrix — generated ERB for a page containing EVERY layout element type + several input types passes `theme:` to each render call; (2) unknown html_type renders a text-input fallback (not a silent skip); (3) unknown layout field_type emits a comment; (4) element components render without theme (default {}) and with a non-default palette (e.g. rose accent on callout/section); (5) progress bar falls back to theme primary; (6) content-only path passes theme to ContentComponent even when page theme is {}.
- [ ] Full targeted suite green.

### Task D: Release + visual parity — after C

- [ ] Targeted suite + tailwind rebuild + restart (SKIP_AUTH for screenshots), screenshot presets modern/bold/showcase on page 43 and diff against /tmp/preset2-*/preset3-* expectations (manual eyeball: must look identical).
- [ ] Restore real-auth server (rm manifest, precompile, no SKIP_AUTH).

### Task E: Review — parallel tech-lead + code-reviewer on the diff.

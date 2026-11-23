# Public Default Page-Layout Template — Design

**Status:** Approved by PO + UX
**Date:** 2026-05-27
**Branch:** `worktree-member-default-template` (work continues in the same worktree)

## Goal

Add a `PageLayoutTemplates` DEFINITION named `public_default` — a third default template that sits alongside `default` (admin) and `member_default` (members). It renders entity-attribute-driven pages for the **public** audience (anonymous + authenticated, no login required, paths outside `/admin/` and `/member/`), with three differentiating qualities:

1. **Beautiful visual identity.** A new `"showcase"` theme preset (violet accent, generous spacing, large inputs, uppercase micro-labels, gradient CTA, pronounced card shadow) chosen specifically for first-impression public traffic.
2. **Responsive end-to-end.** Width rules favor full-width fields; the few "half" pairs auto-collapse to full on mobile via an opt-in applier feature.
3. **Audience-aware visibility.** Drops attributes flagged `visibility.public == false`. (Existing `apply_visibility_filter!` already handles any audience string — no engine change for visibility itself.)

The template flows through the same shared engine as the other two defaults: `PageTemplateApplier` for layout, `PageContentGenerator` + `FormFields::*Component` for rendering.

## Non-Goals

- No new routes, controllers, or URL category. Public pages already exist as a AGENTS.md URL category.
- No new view components. The `FormFields::*` library handles all html_types.
- No new `SurfaceTemplateApplier` analog — public pages don't have a member-surface equivalent.
- No new `visibility.public` column or migration.
- No new `PageLayoutTemplates::CATEGORIES` entry — the template lives under `general/`.
- No changes to the admin default or member default.
- No new Stimulus controllers.

## Design

### 1. The DEFINITION

**File:** `app/services/page_layout_templates/templates/general/public_default.rb`

```ruby
# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module PublicDefault
        DEFINITION = {
          key: "public_default",
          name: "Default (Public)",
          description: "Public-facing layout — showcase theme, generous spacing, full-width fields that auto-collapse on mobile. Designed to look polished and trustworthy on first impression for anonymous internet users.",
          category: "general",
          theme_preset: "showcase",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "full" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Details" }],
            [{ type: :select, width: "full" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            audience: "public",
            default_width: "full",
            mobile_stack: true,                  # NEW — auto-inject responsive_widths.mobile = "full"
            field_width_rules: {
              "text" => "full", "search" => "full", "password" => "full", "hidden" => "full",
              "select" => "full", "multi-select" => "full",
              "radio" => "full", "checkbox" => "full", "switch" => "full",
              "number" => "half", "currency" => "half", "range" => "full", "rating" => "full",
              "date" => "half", "time" => "half", "datetime-local" => "full",
              "month" => "full", "week" => "full",
              "email" => "full", "tel" => "full", "url" => "full",
              "rich-text" => "full", "signature" => "full",
              "file" => "full", "image" => "full",
              "color" => "half", "textarea" => "full"
            },
            group_by: :attribute_groups,
            sections: [],
            inject_elements: [
              { after_section: 0, type: "spacer" },
              { after_section: 1, type: "divider" },
              { after_section: 2, type: "divider" },
              { after_section: 3, type: "spacer" }
            ]
          }.freeze
        }.freeze
      end
    end
  end
end
```

**Width philosophy (UX-authored):** Aggressively full-width. Only inputs that naturally pair on desktop (`number`, `currency`, `date`, `time`, `color`) take `"half"`. Even those collapse to full on mobile via `mobile_stack`. Compare to:

| | Admin Default | Member Default | Public Default |
| --- | --- | --- | --- |
| `default_width` | `"half"` (dense) | `"full"` | `"full"` |
| `text` width | `"half"` | `"half"` | `"full"` |
| `email` / `url` / `tel` | `"half"` | `"full"` / `"full"` / `"half"` | `"full"` (all three) |
| `mobile_stack` | (no) | (no) | `true` |

### 2. The `"showcase"` theme preset

**File modified:** `app/components/concerns/theme_resolver.rb`

Add a new entry to `THEME_PRESETS` (immediately after `"playful"`):

```ruby
"showcase" => {
  "primary_color"   => "violet",     # warm + modern; reads premium without being loud
  "accent_color"    => "violet",
  "font_family"     => "sans",
  "border_radius"   => "lg",         # friendly but not pill-shaped
  "input_style"     => "outline",    # clearest affordance for untrained users
  "form_background" => "white",
  "form_width"      => "full",       # outer shell controls max-width; preset lets form expand
  "form_shadow"     => "xl",         # the single biggest "quality" signal available pre-built
  "form_padding"    => "generous",   # p-10 — breathing room as a trust signal
  "form_border"     => "subtle",
  "field_spacing"   => "relaxed",    # space-y-8 — each field claims its own territory
  "input_size"      => "lg",         # px-4 py-3 text-base — 44px+ tap targets; iOS no-zoom threshold
  "label_style"     => "uppercase",  # premium-form signature (Stripe/Linear/Notion aesthetic)
  "button_style"    => "gradient",
  "button_width"    => "full",
  "button_size"     => "lg"          # py-3.5 text-base — ~52px CTA height
}
```

**Why a new preset and not reuse one:** `modern` is close but `form_width: "xl"` caps too narrow and `label_style: "default"` is understated. `elegant` reads niche/serif. `playful` reads childish. `bold` (rose, pill radii) is too aggressive. None of the existing five hits "polished public form" cleanly — `showcase` is purpose-built for it.

**All token values are valid against the existing maps** (`FORM_WIDTH_MAP`, `FORM_SHADOW_MAP`, `BUTTON_SIZE_MAP`, etc.) — no new resolver code needed; just a new entry in the preset hash.

### 3. `mobile_stack` — new applier feature

**File modified:** `app/services/page_template_applier.rb`

Add a new opt-in layout key. When `layout[:mobile_stack] == true`, any field whose resolved width is **not** `"full"` gets `responsive_widths["mobile"] = "full"` set on it — so the existing `PageContentGenerator#responsive_col_span` collapses it to a single column on mobile.

Implementation lives next to `apply_width_rules` (and is called immediately after it in `apply_single_page` and `build_multi_page`):

```ruby
def apply_mobile_stack!(fields, layout)
  return unless layout[:mobile_stack]

  fields.each do |field|
    next if field["property_type"] == "layout"
    next if field["width"] == "full"

    existing = field["responsive_widths"]
    field["responsive_widths"] = (existing.is_a?(Hash) ? existing : {}).merge("mobile" => "full")
  end
end
```

**Why a new key rather than hardcoding in `public_default`:** future templates (or even an updated member_default) may want the same behavior. Making it data-driven keeps the engine consistent with how `audience` and `group_by` already work.

**Interaction with existing `responsive_widths`:** if a field already has `responsive_widths["mobile"]` set by upstream code, we merge — the `mobile_stack` injection only fills in the gap when nothing else is set, because `.merge("mobile" => "full")` overwrites. Decision: **overwrite** is the right behavior because `mobile_stack: true` is the template's stated intent. Any field that already had a specific mobile width set was either set by the editor explicitly (so the admin meant it) or by another applier pass — in either case, the new merge wins because the template's intent is unambiguous.

Wait — that's a contradiction. Let me reconsider.

**Revised decision:** preserve existing `responsive_widths["mobile"]` when present:

```ruby
def apply_mobile_stack!(fields, layout)
  return unless layout[:mobile_stack]

  fields.each do |field|
    next if field["property_type"] == "layout"
    next if field["width"] == "full"

    existing = field["responsive_widths"]
    existing_hash = existing.is_a?(Hash) ? existing : {}
    next if existing_hash.key?("mobile")  # respect upstream choice

    field["responsive_widths"] = existing_hash.merge("mobile" => "full")
  end
end
```

This treats `mobile_stack` as a *fallback* — only fills in mobile when the field doesn't already declare one. Safer default and matches the principle "don't overwrite admin intent".

### 4. Wiring

- **Registry discovery:** `PageLayoutTemplates::Registry.load_templates` walks the directory; the new file is picked up automatically. No manual registration.
- **Template picker:** appears in the General tab of the editor's template picker via `PageBuilder::TemplateCardComponent` (already category-aware). No code change.
- **Applier:** the existing `apply_visibility_filter!` already supports any audience string (it reads `layout[:audience]` generically). The member path was the first to use it; `public_default` is the second. **No change to `apply_visibility_filter!`.**
- **Renderer:** `PageContentGenerator#responsive_col_span` already reads `responsive_widths.mobile` and emits the right `col-span-12 md:col-span-N` classes. No renderer change.

### 5. Testing strategy

#### Targeted specs (run before claiming completion)

- **`spec/services/page_layout_templates/templates/general/public_default_spec.rb`** (new file):
  - DEFINITION is frozen, has `key: "public_default"`, `category: "general"`, `theme_preset: "showcase"`, `audience: "public"`, `default_width: "full"`, `mobile_stack: true`.
  - `field_width_rules` covers every `html_type` in `PageContentGenerator::HTML_TYPE_COMPONENTS`.
  - `text`, `email`, `url`, `tel`, `month`, `week`, `password`, `hidden` are all `"full"` (more aggressive than member_default).
  - `number`, `currency`, `date`, `time`, `color` are `"half"`.
  - `inject_elements` array matches UX spec.
  - `PageLayoutTemplates.find("public_default")` returns the DEFINITION.

- **`spec/components/concerns/theme_resolver_spec.rb`** (extend if exists; otherwise new file):
  - `THEME_PRESETS["showcase"]` exists with all 16 expected tokens.
  - Every token value resolves correctly via the existing `_MAP` constants (`FORM_WIDTH_MAP`, `FORM_SHADOW_MAP`, etc.).

- **`spec/services/page_template_applier_spec.rb`** (new context):
  - `mobile_stack: true` injects `responsive_widths["mobile"] = "full"` on every field whose resolved width is not `"full"`.
  - `mobile_stack: true` does NOT touch fields whose width is `"full"`.
  - `mobile_stack: true` does NOT touch layout/section fields.
  - `mobile_stack: true` preserves a pre-existing `responsive_widths["mobile"]` value (fallback semantics).
  - `mobile_stack: false` or missing key is a no-op.
  - A spec applying `public_default` end-to-end confirms `audience: "public"` filtering + `group_by: :attribute_groups` + `mobile_stack` injection all compose correctly.

- **`spec/services/page_layout_templates_spec.rb`** (stale-test fix):
  - Bump expected count `210` → `211`.
  - Add `"public_default"` to the expected keys list.

#### Scope of test run

Per AGENTS.md, moderate-change scope: run `spec/services/page_layout_templates_spec.rb`, `spec/services/page_layout_templates/`, `spec/services/page_template_applier_spec.rb`, `spec/services/page_template_applier_default_spec.rb`, `spec/services/member/`, and `spec/components/concerns/theme_resolver_spec.rb` if it exists. Do not run the full suite.

#### Smoke

If the dev DB can be bootstrapped on the worktree, smoke-hit the template picker to confirm "Default (Public)" appears under General. If not (the worktree dev DB had migration issues before), the spec suite is the source of truth.

### 6. Risks & open questions

- **Risk:** `mobile_stack`'s "preserve existing mobile width" semantics could mask bugs where a buggy upstream sets `responsive_widths.mobile = "half"` accidentally. Mitigation: spec covers preservation explicitly so the contract is locked.
- **Risk:** the `"showcase"` preset uses `form_width: "full"` (no max-width). Depends on the surrounding page shell to bound the form on wide desktops. If a public page is rendered in a shell that doesn't constrain width, the form spans the full viewport — readable but unflattering at 2560px+. Acceptable for v1; flag for a follow-up if reports come in.
- **Open question (deferred):** should the existing member_default also adopt `mobile_stack: true`? Probably yes (it has many half-width pairs), but out of scope here. Follow-up PR.

## Rollout

Single merge. No migration. No feature flag. New template appears in the picker on next deploy; previously-applied templates are unaffected.

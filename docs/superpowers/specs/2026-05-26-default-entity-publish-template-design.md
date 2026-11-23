# Default Layout Template for Entity Publish — Design Spec

**Date:** 2026-05-26
**Branch:** `worktree-implement-preset-layout-style-4-entity-publish`
**Author:** Copilot (Opus 4.7) under direct user direction (no per-section confirmation)

## Goal

Ship a *default* layout template under `app/services/page_layout_templates/templates/general/default.rb` that is selected automatically when an entity is published as a page. The template must render any entity's attribute set well — including:

1. Every supported HTML field type (text, textarea, select, radio, checkbox, switch, number, currency, range, rating, date/time, email, tel, url, file/image, color, signature, rich-text, hidden).
2. **Attribute groups** — entity own fields and base-model fields, grouped by their `source_section`.
3. **Entity associations** — each associated entity's bridge fields rendered as their own labelled section, in association order.

The look must match the existing admin aesthetic (Tailwind tokens, `card`, `section-header`, `border-border-subtle`, `bg-canvas-elevated`) so the published page feels native to the platform.

## Aesthetic Direction

**Refined-editorial.** Calm, generous whitespace, a clear typographic spine, and disciplined column rhythm. Section headings act as chapter markers. Bridge entities are visually demoted (smaller heading, accent rule on the left) so they read as *context for* the primary entity rather than competing siblings. The default theme preset is `modern` (indigo primary, lg radius, gradient submit button) — premium without being loud.

## Architecture

### 1. New layout template definition

`app/services/page_layout_templates/templates/general/default.rb`

```ruby
class PageLayoutTemplates
  module Templates
    module General
      module Default
        DEFINITION = {
          key: "default",
          name: "Default",
          description: "Auto-arranged layout — groups attributes by entity, gives each association its own section, and picks sensible widths for every field type.",
          category: "general",
          theme_preset: "modern",
          preview_rows: [...],            # mini-form thumbnail
          layout: {
            default_width: "half",
            field_width_rules: { ...full HTML_TYPE coverage... },
            group_by: :source,            # NEW — drives source-aware grouping
            section_label_for_entity: ->(name) { name },
            section_label_for_bridge: ->(name) { "Linked: #{name}" },
            sections: [],                 # unused under group_by:source
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
```

`field_width_rules` covers every key in `PageContentGenerator::HTML_TYPE_COMPONENTS`, so no field falls back to "full" by accident:

| html_type | width |
|---|---|
| text, email, tel, url, password, search | half |
| select, multi-select, date, datetime-local, time, currency, number | half |
| month, week, third | third |
| rating, color, range | third |
| radio, checkbox, switch, file, image, textarea, rich-text, signature | full |
| hidden | half (visually no-op) |

### 2. Source-aware grouping in `PageTemplateApplier`

`PageTemplateApplier` currently groups by `match_types` (html_type-based). Add a parallel branch that triggers when `layout[:group_by] == :source`:

```ruby
def apply_single_page(layout)
  working_fields = separate_entity_fields
  apply_width_rules(working_fields[:entity_fields], layout)

  if layout[:group_by] == :source
    result = reorganize_by_source(working_fields, layout)
  elsif layout[:sections].present?
    result = reorganize_into_sections(working_fields, layout)
    result = inject_layout_elements(result, layout)
  else
    apply_ordering(@fields)
    return @fields
  end

  apply_ordering(result)
  result
end
```

`reorganize_by_source` walks the entity fields **preserving their original order** and emits a section header every time `source` or `source_section` changes:

- `source: "base_model"` → header = humanised model name
- `source: "entity"` → header = entity name (the primary)
- `source: "bridge"` → header = `"Linked: <bridge_or_target_entity_name>"`
- legacy/unknown → header = "Other Fields" (defensive)

Empty groups are skipped. A `divider` is injected after each non-final section to give visual breathing room.

### 3. `PageFieldPopulator` already supplies the metadata

`PageFieldPopulator` already stamps `source` + `source_section` onto every field (see `app/services/page_field_populator.rb` lines 55–80). No change needed there — the default template just consumes what's already produced.

### 4. Default selection on publish

When an admin publishes an entity-bound page without picking a template, the system should fall back to `key: "default"`. Two integration points:

- **`PageTemplateApplier.call(fields, nil)`** currently no-ops. Change the call sites that have `referenced_template` blank to pass `"default"` instead. Specifically:
  - `app/controllers/admin/maintenance/page_template_applications_controller.rb` (when no template is selected)
  - `app/controllers/admin/maintenance/entity_template_previews_controller.rb` (already requires referenced_template, leave alone)
  - `app/services/page_field_populator.rb` consumers — no change; this lives one layer up.
- Leave `PageTemplateApplier` itself permissive: a nil/unknown key still no-ops as before. The defaulting is an explicit caller decision.

### 5. Section header styling

Section headers are emitted as existing `field_type: "section"` layout fields, which `LayoutElements` already renders. No new component needed. Bridge headers carry an extra `"variant" => "linked"` field so the existing section renderer can apply a left accent rule + smaller type. If the renderer ignores `variant`, the header still renders correctly — graceful degradation.

The corresponding small change in `app/services/page_content_generator/layout_elements.rb` (or wherever section is rendered) reads:

```ruby
classes = field["variant"] == "linked" ? "section-header section-header--linked" : "section-header"
```

…and we add a single Tailwind utility composition:

```css
.section-header--linked {
  @apply pl-3 border-l-2 border-accent text-text-secondary text-sm uppercase tracking-wide;
}
```

### 6. Preview rows

Mini-form preview shown on the template selection card should communicate the *layout idea*: a tall stack with a clear section/divider/section/divider pattern, showing both half-width pairs and a full-width textarea so the rhythm reads at a glance.

## Data flow

```
Entity (property_schema + associations)
        │
        ▼
PageFieldPopulator.call(entity)            (already adds source + source_section)
        │
        ▼
PageTemplateApplier.call(fields, "default")
        │  ├── apply_width_rules        (covers every html_type)
        │  ├── reorganize_by_source     (NEW — source-aware grouping)
        │  └── inject dividers between groups
        ▼
Page configuration (pages → fields)
        │
        ▼
PageContentGenerator.new(page).generate    (existing — renders ERB)
        │
        ▼
Published public form, served by PublicPagesController
```

## Edge cases

- **Entity with no associations** — only the primary section renders, no dividers.
- **Entity with associations but no bridge fields** — that association is skipped (matches `EntityFieldOrganizer` behaviour).
- **Bridge entity itself being edited** — `PageFieldPopulator` already excludes the source-side NestedEntity ref; no change.
- **Calculated fields** — already marked `readonly` + `storage: "computed"` upstream; rendered fine inside whatever group they sit in.
- **Custom html_type not in the width map** — falls back to `default_width: "half"`.
- **Wizard mode** — `multi_page: false` on default; wizard remains its own template. Out of scope.

## Files added / changed

**Added**
- `app/services/page_layout_templates/templates/general/default.rb` — the template definition
- `spec/services/page_layout_templates/templates/general/default_spec.rb` — definition coverage spec
- `spec/services/page_template_applier_default_spec.rb` — source-grouping behaviour spec

**Changed**
- `app/services/page_template_applier.rb` — add `reorganize_by_source` branch
- `app/controllers/admin/maintenance/page_template_applications_controller.rb` — fall back to `"default"` when no template chosen
- `app/services/page_content_generator/layout_elements.rb` — render `variant: "linked"` section headers (or whichever file owns section rendering — verified at impl time)
- `app/components/page_builder/template_card_component.rb` (only if the card needs to handle "default" badge — verified at impl time)

## Test plan

- **Unit** — `PageLayoutTemplates::Templates::General::Default` exposes the expected DEFINITION shape (key, name, layout structure, all html_types covered).
- **Service** — `PageTemplateApplier.call(fields, "default")` emits one section per source/source_section, preserves original field order within each section, applies the per-html-type width map, injects dividers between sections, and skips empty groups.
- **Integration** — given an entity with own fields + 2 associations, publishing produces a page configuration whose first section is the entity name, followed by a divider and one "Linked: <bridge>" section per association.
- **System** — boot the dev server (`SKIP_AUTH=1`), open an entity with associations, publish, hit the public form URL, and visually confirm sectioning + width rhythm + theme.

## Out of scope

- Wizard / multi-page splits for the default
- Per-field reordering UI inside the default template
- Persisting the default key on the Page record (it's applied at publish time, not stored as a referenced_template — that's the explicit-choice slot)
- Theme customization beyond `modern` preset

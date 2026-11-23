# Member Default Page-Layout Template — Design

**Status:** Approved (pending user review)
**Date:** 2026-05-27
**Branch:** `master` (worktree TBD before implementation)

## Goal

Add a `PageLayoutTemplates` DEFINITION analogous to the existing admin `Default` template (`app/services/page_layout_templates/templates/general/default.rb`) but tuned for the **member** audience. The new template:

1. Picks **mobile-first** widths for every HTML field type defined on an entity's attributes (`html_type` ∈ text, textarea, select, radio, checkbox, switch, number, currency, range, rating, date, time, email, tel, url, rich-text, signature, file, image, color, …).
2. Groups attributes by the entity's **user-curated `attribute_groups_json`** (the same groups shown in the admin attributes panel), rather than by `source` like the admin default.
3. **Filters out** attributes whose `visibility.member` flag is `false`, so members never see fields they aren't supposed to.
4. Drives **both** consumer paths from one DEFINITION:
   - The admin-built **Page** rendered to a member user (via `PageTemplateApplier` → `PageContentGenerator`).
   - The auto-generated read-only **`Member::Surface::Detail`** (via a new `Member::SurfaceTemplateApplier`).

## Non-Goals

- No change to `DetailGridComponent` or any view component.
- No new category in `PageLayoutTemplates::CATEGORIES` — the template lives under `general/`.
- No change to `Member::Surface::Index` (index columns) — only the `Detail` side.
- No new admin UI for picking the template — the existing template picker already lists everything under `general/`.
- No migration. `attribute_groups_json` already exists on `Entity`.

## Background

- `PageLayoutTemplates::Registry` auto-discovers any `app/services/page_layout_templates/templates/<category>/<file>.rb` whose module defines a `DEFINITION` constant.
- The admin `Default` (`templates/general/default.rb`) currently encodes width rules per `html_type` plus `group_by: :source`, which makes the applier emit one section per entity source (`base_model`, `entity:<name>`, `bridge:<name>`).
- `PageTemplateApplier.call(fields, template_key, entity:)` is the sole consumer today. It walks the fields array, assigns widths from `field_width_rules`, and inserts section headers/dividers.
- `PageContentGenerator` (`app/services/page_content_generator.rb`) then renders the laid-out fields via `FormFields::*Component` ViewComponents.
- The member side has two relevant rendering paths:
  - **Member Page render** (admin-built Pages, audience=member): already goes through `PageContentGenerator`. Honors a `PageLayoutTemplates` template when one is applied via the editor.
  - **Member Surface render** (`Member::EntitySurfaceBuilder` → `Member::Surface::Detail` → `Member::DetailGridComponent`): does **not** consume `PageLayoutTemplates` today. Builds one undifferentiated `:primary` section containing every data attribute.

Attributes already carry a per-audience visibility hash (`visibility.{admin, member, public}`), but the current applier ignores it; visibility filtering happens (if at all) at render time elsewhere.

## Design

### 1. The DEFINITION

**File:** `app/services/page_layout_templates/templates/general/member_default.rb`

```ruby
# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module MemberDefault
        DEFINITION = {
          key: "member_default",
          name: "Default (Member)",
          description: "Member-facing layout — mobile-first widths, groups attributes by the entity's curated attribute groups, hides anything not flagged visible to members.",
          category: "general",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Account" }],
            [{ type: :input, width: "full" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Profile" }],
            [{ type: :select, width: "full" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            audience: "member",              # NEW — drives visibility filter
            default_width: "full",
            field_width_rules: {
              "text" => "half", "search" => "full", "password" => "full", "hidden" => "half",
              "select" => "full", "multi-select" => "full",
              "radio" => "full", "checkbox" => "full", "switch" => "full",
              "number" => "half", "currency" => "half", "range" => "full", "rating" => "full",
              "date" => "half", "time" => "half", "datetime-local" => "full",
              "month" => "half", "week" => "half",
              "email" => "full", "tel" => "half", "url" => "full",
              "rich-text" => "full", "signature" => "full",
              "file" => "full", "image" => "full",
              "color" => "half", "textarea" => "full"
            },
            group_by: :attribute_groups,         # NEW — reads entity.attribute_groups_json
            sections: [],
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
```

**Width philosophy:** mobile-first. `"full"` is the default; `"half"` reserved for tightly-paired short inputs (text, number, date/time pairs, tel, currency, color, month/week). Where the admin default's instinct is density, the member default's instinct is breathing room and touch-friendliness.

`PageContentGenerator#responsive_col_span` already collapses widths on tablet/mobile via `field["responsive_widths"]`, so values here describe **desktop** behavior; mobile reflow continues to happen for free.

### 2. `PageTemplateApplier` — two surgical additions

Both additions are **opt-in**. Existing templates without `audience:` and with `group_by: :source` (or no `group_by`) are unaffected.

#### 2a. Visibility filter

In `apply_single_page`, immediately after `separate_entity_fields`, when `layout[:audience]` is present:

```ruby
audience = layout[:audience].to_s
working_fields[:entity_fields].reject! do |f|
  v = f["visibility"]
  next false unless v.is_a?(Hash)
  v[audience] == false || v[audience.to_sym] == false
end
```

Matches the normalization in `EntityAttributeDisplayHelper#normalize_attribute_visibility` (only `false` hides; `nil`/missing is visible). Section/layout fields (`property_type == "layout"`) are **not** filtered.

#### 2b. `group_by: :attribute_groups` branch

When `layout[:group_by] == :attribute_groups` (and `@entity` is provided), `apply_single_page` calls a new private `reorganize_by_attribute_groups(working_fields, layout)`:

```ruby
def reorganize_by_attribute_groups(working_fields, _layout)
  entity_fields = working_fields[:entity_fields]
  groups = Array(@entity&.attribute_groups_json)

  result = []
  placed_ids = Set.new

  groups.each do |g|
    members = entity_fields.select { |f| f["group_id"] == g["id"] && !placed_ids.include?(f["id"]) }
    next if members.empty?

    result << build_layout_element("divider") if result.any?
    result << build_section_header(g["name"])
    members.each { |f| placed_ids << f["id"]; result << f }
  end

  ungrouped = entity_fields.reject { |f| placed_ids.include?(f["id"]) }
  if ungrouped.any?
    result << build_layout_element("divider") if result.any?
    result << build_section_header("Additional")
    result.concat(ungrouped)
  end

  result
end
```

Empty groups (all members filtered out by visibility, or no attributes assigned to them) are skipped entirely — never emit a barren section header. `apply_ordering` runs at the end as today.

When `@entity` is nil and `group_by: :attribute_groups`, fall through to flat ordering (no sections) so the applier never crashes in editor-preview contexts.

### 3. `Member::SurfaceTemplateApplier` — new adapter

**File:** `app/services/member/surface_template_applier.rb`

Single-purpose service that bridges a `PageLayoutTemplates` DEFINITION into a `Member::Surface::Detail` struct (the read-only entity browser).

```ruby
# frozen_string_literal: true

module Member
  class SurfaceTemplateApplier
    def self.call(entity:, template_key: "member_default")
      new(entity, template_key).call
    end

    def initialize(entity, template_key)
      @entity   = entity
      @template = PageLayoutTemplates.find(template_key)
    end

    def call
      return nil unless @template

      fields = synthesize_fields
      result = PageTemplateApplier.call(fields, @template[:key], entity: @entity)
      Member::Surface::Detail.new(
        title:    ->(entry) { "##{entry.id}" },
        subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
        sections: build_sections(result[:fields])
      )
    end

    private

    def synthesize_fields
      @entity.data_fields.map do |attr|
        slug = attr["name_slug"].to_s
        {
          "id"            => slug,
          "name_slug"     => slug,
          "html_type"     => attr["html_type"].presence || "text",
          "group_id"      => attr["group_id"],
          "visibility"    => attr["visibility"],
          "display_label" => attr["display_label"].presence || attr["name"],
          "property_type" => "input"
        }
      end
    end

    def build_sections(laid_out)
      sections = []
      current  = nil

      laid_out.each do |f|
        if section_header?(f)
          sections << current if current
          current = { key: f["property_slug"].to_sym, title: f["label"], rows: [] }
        elsif layout_element?(f)
          next # dividers/spacers don't render in read-only detail
        else
          current ||= { key: :primary, title: nil, rows: [] }
          current[:rows] << build_row(f)
        end
      end

      sections << current if current
      sections
    end

    def section_header?(f)
      f["property_type"] == "layout" && f["field_type"] == "section"
    end

    def layout_element?(f)
      f["property_type"] == "layout"
    end

    def build_row(f)
      slug = f["name_slug"]
      {
        key:   slug.to_sym,
        label: f["display_label"],
        span:  f["width"] == "full" ? 2 : 1,
        value: ->(entry) { entry.respond_to?(:data_json) ? entry.data_json[slug] : nil }
      }
    end
  end
end
```

**Width → span mapping.** `DetailGridComponent` already supports `row[:span] ∈ {1, 2}` on a `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3` grid:
- `"full"` → `span: 2` (full row on tablet, 2-of-3 columns on desktop).
- `"half"`, `"third"`, anything else → `span: 1`.

No `DetailGridComponent` change needed.

### 4. Wiring

#### 4a. Member surface path

`Member::EntitySurfaceBuilder.call` becomes a thin shim. It still builds the index columns as today, but defers `Detail` construction to the new applier:

```ruby
detail = Member::SurfaceTemplateApplier.call(entity: entity) || legacy_detail(columns)
```

`legacy_detail` is the current single-`:primary`-section behavior, retained as the fallback for the unlikely case the registry returns `nil`.

#### 4b. Admin Page-builder path

No new wiring. The template appears in the "General" tab of the picker automatically because `Registry.load_templates` walks the directory. When an admin applies it via the existing template picker, `PageTemplateApplicationsController#create` already routes through `PageTemplateApplier`, which now honors `layout[:audience]` and `layout[:group_by]`.

### 5. Testing strategy

#### Targeted specs (run before claiming completion)

- **`spec/services/page_layout_templates/registry_spec.rb`** — `Registry.find("member_default")` returns a frozen DEFINITION with the expected `audience`, `default_width`, and `group_by` keys, and is grouped under `general`.
- **`spec/services/page_template_applier_spec.rb`** — new contexts:
  - `audience: "member"` drops fields whose `visibility.member == false`; leaves `nil`/missing visibility intact.
  - `group_by: :attribute_groups` emits one section per non-empty entity group, in stored order; appends "Additional" for ungrouped fields.
  - Empty groups (all members hidden) are skipped, not rendered as empty headers.
  - Admin templates with no `audience:` or `group_by: :source` are unaffected (regression).
  - `group_by: :attribute_groups` with `@entity = nil` falls through to flat ordering without raising.
- **`spec/services/member/surface_template_applier_spec.rb`** — new file:
  - Builds an entity with two attribute groups + one ungrouped attribute + one member-hidden attribute; asserts returned `Detail.sections` titles/order and that the hidden attribute is absent.
  - Row widths translate: `"full"` → `span: 2`, `"half"` → `span: 1`.
  - Returns `nil` when the registry returns `nil`; `EntitySurfaceBuilder` falls back to legacy.
- **`spec/services/member/entity_surface_builder_spec.rb`** — updated: builder delegates `Detail` to the applier, preserves existing `Index` behavior.

#### Multi-tenant isolation

The template engine itself is pure (no AR). The surface applier reads from an `Entity` instance handed in by `EntitySurfaceBuilder`, which is already scoped by `customer_id` at the source (`Member::Sources::Entities#surfaces`). No new scoping required, but the surface applier spec asserts that passing a foreign-customer entity simply produces sections for that entity — ownership is the caller's responsibility, same as today.

#### Scope of test run

Per `AGENTS.md`, this change touches one new template file, one applier (with isolated new branches), one new surface applier, and `EntitySurfaceBuilder`. That's a moderate-change scope: run the specs above plus any request specs covering `PageTemplateApplicationsController` and the member surface controllers. Do **not** run the full suite.

## Risks & Open Questions

- **Risk:** The new visibility-filter branch in `PageTemplateApplier` runs `reject!` on the mutable `working_fields[:entity_fields]` array. The existing `deep_dup` in `PageTemplateApplier#initialize` already isolates inputs, so this is safe. Spec covers it.
- **Risk:** `attribute_groups_json` is an open-ended hash (entries may carry `id`, `name`, `description`, `color`, `icon`). The new branch reads only `id` and `name`. Anything else is ignored — explicit by design (read-only `Detail` does not surface group colors/icons).
- **Risk:** `Entity#data_fields` already excludes `Calculated` fields, which matches today's `EntitySurfaceBuilder` behavior. If a future requirement is to display read-only computed values in the member detail, the surface applier will need a `Calculated`-aware row builder. Flagged, not solved here.
- **Open question (deferred):** Should the member surface index columns also honor visibility? Today `EntitySurfaceBuilder` builds columns from all non-`Calculated` attributes, ignoring visibility. Out of scope here, but flagged for a follow-up.

## Rollout

Single deploy. No migration, no feature flag. The new template appears in the picker immediately; the member surface auto-picks it up the first time `EntitySurfaceBuilder.call` runs after deploy.

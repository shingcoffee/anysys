# Member Default Page-Layout Template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `PageLayoutTemplates` DEFINITION for member-audience pages — mobile-first widths per `html_type`, grouping by the entity's own `attribute_groups_json`, automatic visibility filtering — and project the same DEFINITION into the read-only `Member::Surface::Detail` via a new applier.

**Architecture:** One DEFINITION drives two consumers. `PageTemplateApplier` learns two opt-in branches (visibility filter when `layout[:audience]` is set; `group_by: :attribute_groups` when requested). A new `Member::SurfaceTemplateApplier` reuses `PageTemplateApplier` to lay out fields and then projects the result into a `Member::Surface::Detail` struct consumed by `DetailGridComponent`. `Member::EntitySurfaceBuilder` becomes a thin shim that delegates `Detail` construction.

**Tech Stack:** Ruby 3.2.8, Rails 8.1, RSpec, ViewComponent. Pure-Ruby additions, no migrations, no front-end work.

**Spec reference:** `docs/superpowers/specs/2026-05-27-member-default-layout-template-design.md`

**Execution context:** Run this plan inside a git worktree (`worktree-member-default-template` is a fine branch name). Commits land on the worktree branch and get merged back to `master` at the end — auto-commits on the worktree branch are fine. Do **not** commit directly on `master`.

---

## File Structure

**Create (4 files):**
- `app/services/page_layout_templates/templates/general/member_default.rb` — the new DEFINITION (frozen hash).
- `spec/services/page_layout_templates/templates/general/member_default_spec.rb` — DEFINITION shape + registry discovery.
- `app/services/member/surface_template_applier.rb` — projects a template into a `Member::Surface::Detail`.
- `spec/services/member/surface_template_applier_spec.rb` — applier behavior (sections, visibility, span mapping).

**Modify (3 files):**
- `app/services/page_template_applier.rb` — add visibility filter + `group_by: :attribute_groups` branch.
- `app/services/member/entity_surface_builder.rb` — delegate `Detail` to the new applier; keep legacy fallback.
- `spec/services/page_template_applier_spec.rb` — new contexts covering the two new branches + regression.
- `spec/services/member/entity_surface_builder_spec.rb` — assert delegation; remove tests duplicated by the new applier spec.

**Dependency map (parallelizable batches):**
- **Batch 1 (parallel):** Task 1 (DEFINITION), Task 2 (visibility filter), Task 3 (group_by branch). All three touch independent files/branches.
- **Batch 2:** Task 4 (SurfaceTemplateApplier) — depends on Batch 1.
- **Batch 3:** Task 5 (EntitySurfaceBuilder shim) — depends on Task 4.
- **Batch 4 (parallel):** Task 6 (release-engineer spec run) and Task 7 (tech-lead + code-reviewer).
- **Batch 5:** Task 8 (merge worktree back to master).

---

## Task 1: Member Default DEFINITION

**Files:**
- Create: `app/services/page_layout_templates/templates/general/member_default.rb`
- Create test: `spec/services/page_layout_templates/templates/general/member_default_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/page_layout_templates/templates/general/member_default_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageLayoutTemplates::Templates::General::MemberDefault do
  describe "DEFINITION" do
    subject(:definition) { described_class::DEFINITION }

    it "is frozen" do
      expect(definition).to be_frozen
    end

    it "has key member_default" do
      expect(definition[:key]).to eq("member_default")
    end

    it "has name Default (Member)" do
      expect(definition[:name]).to eq("Default (Member)")
    end

    it "is registered under the general category" do
      expect(definition[:category]).to eq("general")
    end

    it "uses the modern theme preset" do
      expect(definition[:theme_preset]).to eq("modern")
    end

    it "has non-empty preview_rows" do
      expect(definition[:preview_rows]).to be_an(Array)
      expect(definition[:preview_rows]).not_to be_empty
    end

    describe "layout" do
      subject(:layout) { definition[:layout] }

      it "tags the audience as member" do
        expect(layout[:audience]).to eq("member")
      end

      it "defaults to full width (mobile-first)" do
        expect(layout[:default_width]).to eq("full")
      end

      it "groups by attribute_groups" do
        expect(layout[:group_by]).to eq(:attribute_groups)
      end

      it "has empty sections and inject_elements" do
        expect(layout[:sections]).to eq([])
        expect(layout[:inject_elements]).to eq([])
      end

      describe "field_width_rules" do
        subject(:rules) { layout[:field_width_rules] }

        it "covers every html_type from PageContentGenerator::HTML_TYPE_COMPONENTS" do
          expect(rules.keys).to match_array(PageContentGenerator::HTML_TYPE_COMPONENTS.keys)
        end

        it "uses only valid width values" do
          rules.each_value { |w| expect(%w[full half third two_thirds]).to include(w) }
        end

        it "prefers half for tightly-paired short inputs" do
          %w[text number currency date time tel month week color hidden].each do |t|
            expect(rules[t]).to eq("half"), "expected #{t} => half, got #{rules[t]}"
          end
        end

        it "uses full for selection/toggle/textarea/rich/file/email/url types" do
          %w[textarea select multi-select radio checkbox switch rich-text signature
             file image email url password search range rating datetime-local].each do |t|
            expect(rules[t]).to eq("full"), "expected #{t} => full, got #{rules[t]}"
          end
        end
      end
    end
  end

  describe "PageLayoutTemplates.find" do
    it "returns the definition by key" do
      template = PageLayoutTemplates.find("member_default")
      expect(template).to eq(described_class::DEFINITION)
    end
  end

  describe "PageLayoutTemplates::Registry" do
    it "discovers the template under the general category" do
      keys = PageLayoutTemplates.for_category("general").map { |t| t[:key] }
      expect(keys).to include("member_default")
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/page_layout_templates/templates/general/member_default_spec.rb`
Expected: All examples error (`uninitialized constant PageLayoutTemplates::Templates::General::MemberDefault`).

- [ ] **Step 3: Create the DEFINITION**

Write `app/services/page_layout_templates/templates/general/member_default.rb`:

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
            audience: "member",
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
            group_by: :attribute_groups,
            sections: [],
            inject_elements: []
          }.freeze
        }.freeze
      end
    end
  end
end
```

Note: the nested `layout:` hash is `.freeze`d as well so each `field_width_rules` lookup can't mutate the registry.

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/page_layout_templates/templates/general/member_default_spec.rb`
Expected: all examples PASS. If the `for_category("general")` example fails because the cached registry doesn't see the new file, the `PageLayoutTemplates::Registry.reload!` mechanism exists — but a fresh test process won't hit the cache. Skip the workaround unless the test actually fails.

- [ ] **Step 5: Commit**

```bash
git add app/services/page_layout_templates/templates/general/member_default.rb \
        spec/services/page_layout_templates/templates/general/member_default_spec.rb
git commit -m "feat(page-templates): add member default layout template"
```

---

## Task 2: PageTemplateApplier visibility filter

**Files:**
- Modify: `app/services/page_template_applier.rb` (insert filter step in `apply_single_page` and `build_multi_page`)
- Modify test: `spec/services/page_template_applier_spec.rb`

- [ ] **Step 1: Write the failing tests**

Append the following context to `spec/services/page_template_applier_spec.rb` inside `RSpec.describe PageTemplateApplier do ... end`, before the closing `end`:

```ruby
context "with layout[:audience] set" do
  let(:audience_template_definition) do
    {
      key: "audience_test_tmpl",
      name: "Audience Test",
      category: "general",
      theme_preset: "modern",
      preview_rows: [],
      layout: {
        audience: "member",
        default_width: "full",
        field_width_rules: { "text" => "half" },
        group_by: nil,
        sections: [],
        inject_elements: []
      }
    }.freeze
  end

  before do
    allow(PageLayoutTemplates).to receive(:find).with("audience_test_tmpl").and_return(audience_template_definition)
  end

  let(:fields_with_visibility) do
    [
      { "id" => "f1", "property_slug" => "a", "property_type" => "string", "html_type" => "text",
        "label" => "A", "width" => "full", "order" => 0,
        "visibility" => { "admin" => true, "member" => true, "public" => true } },
      { "id" => "f2", "property_slug" => "b", "property_type" => "string", "html_type" => "text",
        "label" => "B", "width" => "full", "order" => 1,
        "visibility" => { "admin" => true, "member" => false, "public" => true } },
      { "id" => "f3", "property_slug" => "c", "property_type" => "string", "html_type" => "text",
        "label" => "C", "width" => "full", "order" => 2 } # no visibility key — visible by default
    ]
  end

  it "drops fields whose visibility[audience] is explicitly false" do
    result = described_class.call(fields_with_visibility, "audience_test_tmpl")
    slugs = result[:fields].reject { |f| f["property_type"] == "layout" }.map { |f| f["property_slug"] }
    expect(slugs).to contain_exactly("a", "c")
  end

  it "keeps fields with nil/missing visibility hash" do
    result = described_class.call(fields_with_visibility, "audience_test_tmpl")
    slugs = result[:fields].reject { |f| f["property_type"] == "layout" }.map { |f| f["property_slug"] }
    expect(slugs).to include("c")
  end

  it "tolerates symbol-keyed visibility hashes" do
    field = fields_with_visibility[1].merge("visibility" => { admin: true, member: false, public: true })
    result = described_class.call([field, fields_with_visibility[0]], "audience_test_tmpl")
    slugs = result[:fields].reject { |f| f["property_type"] == "layout" }.map { |f| f["property_slug"] }
    expect(slugs).not_to include("b")
  end
end

context "with admin templates (no audience)" do
  it "does not filter any fields by visibility" do
    fields_all = [
      { "id" => "f1", "property_slug" => "a", "property_type" => "string", "html_type" => "text",
        "label" => "A", "width" => "full", "order" => 0,
        "visibility" => { "admin" => true, "member" => false, "public" => true } }
    ]

    result = described_class.call(fields_all, "default")
    slugs = result[:fields].reject { |f| f["property_type"] == "layout" }.map { |f| f["property_slug"] }
    expect(slugs).to include("a")
  end
end
```

- [ ] **Step 2: Run the new contexts and confirm they fail**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb -e "with layout[:audience]" -e "with admin templates"`
Expected: the three new examples in the first context FAIL (audience field B is still present); the admin regression example PASSES (no filtering exists yet).

- [ ] **Step 3: Implement the visibility filter**

Edit `app/services/page_template_applier.rb`. Inside `apply_single_page`, after `working_fields = separate_entity_fields`, insert:

```ruby
apply_visibility_filter!(working_fields[:entity_fields], layout)
```

Then add the new private method near the other layout-helper methods (right after `apply_width_rules`):

```ruby
def apply_visibility_filter!(fields, layout)
  audience = layout[:audience]
  return if audience.nil?

  audience_str = audience.to_s
  audience_sym = audience.to_sym

  fields.reject! do |f|
    v = f["visibility"]
    next false unless v.is_a?(Hash)
    v[audience_str] == false || v[audience_sym] == false
  end
end
```

Also apply the same filter in `build_multi_page` (the wizard path), right after `entity_fields = working_fields[:entity_fields]`:

```ruby
apply_visibility_filter!(entity_fields, layout)
```

- [ ] **Step 4: Run the new contexts and confirm they pass**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb -e "with layout[:audience]" -e "with admin templates"`
Expected: all four examples PASS.

- [ ] **Step 5: Run the full applier spec to confirm no regression**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb`
Expected: all existing examples still PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/page_template_applier.rb spec/services/page_template_applier_spec.rb
git commit -m "feat(page-templates): filter fields by visibility[audience] when applier template opts in"
```

---

## Task 3: PageTemplateApplier `group_by: :attribute_groups` branch

**Files:**
- Modify: `app/services/page_template_applier.rb`
- Modify test: `spec/services/page_template_applier_spec.rb`

- [ ] **Step 1: Write the failing tests**

Append to the same describe block in `spec/services/page_template_applier_spec.rb`:

```ruby
context "with group_by: :attribute_groups" do
  let(:attribute_groups_template) do
    {
      key: "attr_groups_test_tmpl",
      name: "Attr Groups Test",
      category: "general",
      theme_preset: "modern",
      preview_rows: [],
      layout: {
        default_width: "full",
        field_width_rules: { "text" => "half" },
        group_by: :attribute_groups,
        sections: [],
        inject_elements: []
      }
    }.freeze
  end

  before do
    allow(PageLayoutTemplates).to receive(:find).with("attr_groups_test_tmpl").and_return(attribute_groups_template)
  end

  let(:customer) { create(:customer) }
  let(:entity) do
    e = create(:entity, customer: customer)
    e.update_columns(
      attribute_groups: [
        { "id" => "g_one", "name" => "Account" },
        { "id" => "g_two", "name" => "Profile" }
      ].to_json,
      property_schema: [].to_json
    )
    Entity.find(e.id)
  end

  let(:grouped_fields) do
    [
      { "id" => "f1", "property_slug" => "email",     "property_type" => "string", "html_type" => "email", "group_id" => "g_one", "width" => "full", "order" => 0 },
      { "id" => "f2", "property_slug" => "password",  "property_type" => "string", "html_type" => "password", "group_id" => "g_one", "width" => "full", "order" => 1 },
      { "id" => "f3", "property_slug" => "bio",       "property_type" => "string", "html_type" => "textarea", "group_id" => "g_two", "width" => "full", "order" => 2 },
      { "id" => "f4", "property_slug" => "freeform",  "property_type" => "string", "html_type" => "text",     "group_id" => nil,     "width" => "full", "order" => 3 }
    ]
  end

  it "emits one section header per non-empty entity group in stored order" do
    result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: entity)
    headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
    expect(headers.map { |h| h["label"] }).to eq(["Account", "Profile", "Additional"])
  end

  it "places ungrouped fields under an 'Additional' tail section" do
    result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: entity)
    fields = result[:fields]
    additional_idx = fields.index { |f| f["field_type"] == "section" && f["label"] == "Additional" }
    expect(additional_idx).not_to be_nil
    expect(fields[additional_idx + 1]["property_slug"]).to eq("freeform")
  end

  it "skips empty groups entirely" do
    # An entity that defines three groups but only provides fields for one
    e = create(:entity, customer: customer)
    e.update_columns(
      attribute_groups: [
        { "id" => "ga", "name" => "Used" },
        { "id" => "gb", "name" => "Empty" }
      ].to_json,
      property_schema: [].to_json
    )
    e = Entity.find(e.id)

    fields = [
      { "id" => "x1", "property_slug" => "only", "property_type" => "string", "html_type" => "text", "group_id" => "ga", "width" => "full", "order" => 0 }
    ]

    result = described_class.call(fields, "attr_groups_test_tmpl", entity: e)
    headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
    expect(headers.map { |h| h["label"] }).to eq(["Used"])
  end

  it "falls through to flat ordering when entity is nil" do
    result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: nil)
    headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
    expect(headers).to be_empty
    expect(result[:fields].map { |f| f["property_slug"] }).to eq(%w[email password bio freeform])
  end

  it "injects a divider between sections (not before the first)" do
    result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: entity)
    types_in_order = result[:fields].map { |f| f["field_type"] }
    first_section_idx = types_in_order.index("section")
    expect(types_in_order[0...first_section_idx]).not_to include("divider")
    expect(types_in_order.count("divider")).to be >= 2
  end
end
```

- [ ] **Step 2: Run the new context and confirm it fails**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb -e "with group_by: :attribute_groups"`
Expected: all five examples FAIL (current code only knows `group_by: :source`).

- [ ] **Step 3: Implement the new branch**

Edit `app/services/page_template_applier.rb`. In `apply_single_page`, just below the existing `if layout[:group_by] == :source` block, add:

```ruby
if layout[:group_by] == :attribute_groups
  if @entity
    result = reorganize_by_attribute_groups(working_fields, layout)
    apply_ordering(result)
    return result
  else
    # No entity context (editor preview). Fall through to flat ordering of
    # entity_fields, dropping section_headers since we have nothing to anchor them to.
    apply_ordering(working_fields[:entity_fields])
    return working_fields[:entity_fields]
  end
end
```

Then add the private method below `reorganize_by_source`:

```ruby
def reorganize_by_attribute_groups(working_fields, _layout)
  entity_fields = working_fields[:entity_fields]
  groups        = Array(@entity&.attribute_groups_json)
  result        = []
  placed_ids    = Set.new

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

Make sure `require "set"` (or `Set.new`) works in this file — Ruby 3.2 includes `Set` core. No new require needed.

- [ ] **Step 4: Run the new context and confirm it passes**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb -e "with group_by: :attribute_groups"`
Expected: all five examples PASS.

- [ ] **Step 5: Run the full applier spec to confirm no regression**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb`
Expected: every example PASSES.

- [ ] **Step 6: Commit**

```bash
git add app/services/page_template_applier.rb spec/services/page_template_applier_spec.rb
git commit -m "feat(page-templates): add group_by :attribute_groups branch to applier"
```

---

## Task 4: Member::SurfaceTemplateApplier

**Files:**
- Create: `app/services/member/surface_template_applier.rb`
- Create test: `spec/services/member/surface_template_applier_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/services/member/surface_template_applier_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceTemplateApplier do
  let(:customer) { create(:customer) }
  let(:entity) do
    e = create(:entity, customer: customer)
    e.update_columns(
      attribute_groups: [
        { "id" => "g_account", "name" => "Account" },
        { "id" => "g_profile", "name" => "Profile" }
      ].to_json,
      property_schema: [
        { "name" => "Email", "name_slug" => "email", "type" => "string", "html_type" => "email",
          "group_id" => "g_account",
          "visibility" => { "admin" => true, "member" => true, "public" => false } },
        { "name" => "Password", "name_slug" => "password", "type" => "string", "html_type" => "password",
          "group_id" => "g_account",
          "visibility" => { "admin" => true, "member" => false, "public" => false } },
        { "name" => "Bio", "name_slug" => "bio", "type" => "string", "html_type" => "textarea",
          "group_id" => "g_profile" },
        { "name" => "Score", "name_slug" => "score", "type" => "number", "html_type" => "number",
          "group_id" => nil },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "group_id" => nil }
      ].to_json
    )
    Entity.find(e.id)
  end

  subject(:detail) { described_class.call(entity: entity) }

  it "returns a Member::Surface::Detail" do
    expect(detail).to be_a(Member::Surface::Detail)
  end

  it "emits one section per non-empty attribute group" do
    titles = detail.sections.map { |s| s[:title] }
    expect(titles).to eq(["Account", "Profile", "Additional"])
  end

  it "filters out attributes with visibility.member == false" do
    slugs = detail.sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
    expect(slugs).to include(:email)
    expect(slugs).not_to include(:password)
  end

  it "excludes Calculated attributes (matches EntitySurfaceBuilder behavior)" do
    slugs = detail.sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
    expect(slugs).not_to include(:total)
  end

  it "maps width=full to span=2 and other widths to span=1" do
    bio_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :bio }
    score_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :score }
    expect(bio_row[:span]).to eq(2)    # textarea -> full -> 2
    expect(score_row[:span]).to eq(1)  # number -> half -> 1
  end

  it "exposes a value lambda that reads data_json by name_slug" do
    entry = double("EntityEntry", id: 7, created_at: Time.current,
                                   data_json: { "email" => "x@example.com" })
    email_row = detail.sections.flat_map { |s| s[:rows] }.find { |r| r[:key] == :email }
    expect(email_row[:value].call(entry)).to eq("x@example.com")
  end

  it "returns nil when no template is registered for the given key" do
    expect(described_class.call(entity: entity, template_key: "nonexistent_key")).to be_nil
  end

  context "when an entity group is empty after visibility filtering" do
    let(:entity) do
      e = create(:entity, customer: customer)
      e.update_columns(
        attribute_groups: [
          { "id" => "g_secrets", "name" => "Secrets" },
          { "id" => "g_visible", "name" => "Visible" }
        ].to_json,
        property_schema: [
          { "name" => "SSN", "name_slug" => "ssn", "type" => "string", "html_type" => "text",
            "group_id" => "g_secrets",
            "visibility" => { "member" => false } },
          { "name" => "Nick", "name_slug" => "nick", "type" => "string", "html_type" => "text",
            "group_id" => "g_visible" }
        ].to_json
      )
      Entity.find(e.id)
    end

    it "skips the empty group" do
      titles = detail.sections.map { |s| s[:title] }
      expect(titles).not_to include("Secrets")
      expect(titles).to include("Visible")
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/services/member/surface_template_applier_spec.rb`
Expected: every example errors (`uninitialized constant Member::SurfaceTemplateApplier`).

- [ ] **Step 3: Implement the applier**

Create `app/services/member/surface_template_applier.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Projects a PageLayoutTemplates DEFINITION into a Member::Surface::Detail.
  # Reuses PageTemplateApplier for the heavy lifting (visibility filter, width
  # assignment, attribute-group sectioning) and translates the resulting field
  # array into the row-and-section shape DetailGridComponent consumes.
  class SurfaceTemplateApplier
    DEFAULT_TEMPLATE_KEY = "member_default"

    def self.call(entity:, template_key: DEFAULT_TEMPLATE_KEY)
      new(entity, template_key).call
    end

    def initialize(entity, template_key)
      @entity        = entity
      @template      = PageLayoutTemplates.find(template_key)
      @template_key  = template_key
    end

    def call
      return nil unless @template

      laid_out = PageTemplateApplier.call(synthesize_fields, @template_key, entity: @entity)[:fields]

      Member::Surface::Detail.new(
        title:    ->(entry) { "##{entry.id}" },
        subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
        sections: build_sections(laid_out)
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
          next
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

- [ ] **Step 4: Run the spec and confirm it passes**

Run: `bundle exec rspec spec/services/member/surface_template_applier_spec.rb`
Expected: all examples PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/member/surface_template_applier.rb \
        spec/services/member/surface_template_applier_spec.rb
git commit -m "feat(member): project layout template into Surface::Detail"
```

---

## Task 5: Wire EntitySurfaceBuilder through the applier

**Files:**
- Modify: `app/services/member/entity_surface_builder.rb`
- Modify test: `spec/services/member/entity_surface_builder_spec.rb`

- [ ] **Step 1: Update the builder spec to assert delegation**

Open `spec/services/member/entity_surface_builder_spec.rb`. Add a new context at the bottom (before the final `end`):

```ruby
describe "Detail delegation" do
  let(:customer) { create(:customer) }
  let(:entity) do
    e = create(:entity, customer: customer)
    e.update_columns(
      attribute_groups: [{ "id" => "g_one", "name" => "Account" }].to_json,
      property_schema: [
        { "name" => "Email", "name_slug" => "email", "type" => "string",
          "html_type" => "email", "group_id" => "g_one" }
      ].to_json
    )
    Entity.find(e.id)
  end

  it "delegates Detail construction to SurfaceTemplateApplier" do
    detail = double("Detail", title: nil, subtitle: nil, meta: nil, sections: [])
    expect(Member::SurfaceTemplateApplier)
      .to receive(:call).with(entity: entity).and_return(Member::Surface::Detail.new(
        title: ->(e) { "##{e.id}" }, subtitle: ->(_) { "" },
        sections: [{ key: :primary, title: "Account",
                     rows: [{ key: :email, label: "Email", span: 2,
                              value: ->(e) { e.data_json["email"] } }] }]
      ))

    surface = described_class.call(entity: entity)
    titles = surface.detail.sections.map { |s| s[:title] }
    expect(titles).to eq(["Account"])
  end

  it "falls back to a single :primary section when the applier returns nil" do
    allow(Member::SurfaceTemplateApplier).to receive(:call).and_return(nil)
    surface = described_class.call(entity: entity)
    expect(surface.detail.sections.map { |s| s[:key] }).to eq([:primary])
  end
end
```

- [ ] **Step 2: Run the new context and confirm it fails**

Run: `bundle exec rspec spec/services/member/entity_surface_builder_spec.rb -e "Detail delegation"`
Expected: both new examples FAIL — the builder doesn't currently call the applier.

- [ ] **Step 3: Update the builder**

Edit `app/services/member/entity_surface_builder.rb`. Replace the `detail:` argument in the `Member::Surface.new(...)` call with a delegated build. Final shape:

```ruby
# frozen_string_literal: true

module Member
  module EntitySurfaceBuilder
    DEFAULT_POSITION_BASE = 200

    def self.call(entity:)
      grouped     = entity.grouped_property_schema
      data_fields = grouped.flat_map { |s| s[:attributes] }.reject { |f| f["type"] == "Calculated" }

      columns = data_fields.map { |f|
        slug = f["name_slug"] || f["key"] || ""
        next nil if slug.empty?

        {
          key:      slug.to_sym,
          label:    f["name"].presence || slug.to_s.titleize,
          value:    ->(entry) { entry.respond_to?(:data_json) ? entry.data_json[slug] : nil },
          format:   format_for(f["type"]),
          align:    align_for(f["type"]),
          hideable: true
        }
      }.compact

      columns = [{ key: :id, label: "ID", value: ->(e) { e.id }, hideable: false }] if columns.empty?

      Member::Surface.new(
        key:   :"entity_#{entity.name_slug}",
        label: entity.name,
        icon:  :rectangle_stack,
        default_position: DEFAULT_POSITION_BASE + entity.id.to_i,
        enabled_for: ->(user) { user.customer_id == entity.customer_id },
        groups: grouped.map { |s| { group: s[:group], attributes: s[:attributes].reject { |f| f["type"] == "Calculated" } } },
        index: Member::Surface::Index.new(
          title:    entity.name,
          subtitle: entity.description.presence || "Records linked to your account.",
          scope:    ->(_user) { EntityEntry.none },
          columns:  columns,
          empty_state: {
            headline: "No #{entity.name.downcase} yet",
            body:     "Records will appear here once they're linked to your account.",
            icon:     :rectangle_stack
          },
          per_page: 20
        ),
        detail: build_detail(entity, columns)
      ).tap(&:validate!)
    end

    def self.build_detail(entity, columns)
      Member::SurfaceTemplateApplier.call(entity: entity) || legacy_detail(columns)
    end

    def self.legacy_detail(columns)
      Member::Surface::Detail.new(
        title:    ->(entry) { "##{entry.id}" },
        subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
        sections: [{
          key:   :primary,
          rows:  columns.map { |c|
            { key: c[:key], label: c[:label], value: c[:value], format: c[:format], hideable: c[:hideable] }
          }
        }]
      )
    end

    def self.format_for(type)
      case type.to_s.downcase
      when "money", "currency"           then :money
      when "number", "integer", "decimal" then :number
      when "datetime", "timestamp"       then :datetime
      when "date"                        then :date
      else                                    :string
      end
    end

    def self.align_for(type)
      %w[money currency number integer decimal].include?(type.to_s.downcase) ? :right : :left
    end
  end
end
```

- [ ] **Step 4: Run the builder spec and confirm everything passes**

Run: `bundle exec rspec spec/services/member/entity_surface_builder_spec.rb`
Expected: all examples PASS (existing ones + the two new delegation examples).

- [ ] **Step 5: Run the full member + page-template spec slice**

Run: `bundle exec rspec spec/services/member/ spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb spec/services/page_layout_templates_spec.rb spec/services/page_layout_templates/`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/member/entity_surface_builder.rb \
        spec/services/member/entity_surface_builder_spec.rb
git commit -m "feat(member): delegate Surface::Detail to SurfaceTemplateApplier"
```

---

## Task 6: Release-engineer verification

**Files:**
- Read only (no edits)

- [ ] **Step 1: Rebuild assets cache and restart dev server**

Per AGENTS.md:

```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

- [ ] **Step 2: Smoke the template picker**

Open the admin page editor for any Page (any entity will do). Confirm the "Default (Member)" card appears in the General tab of the template picker alongside the existing "Default" card. Confirm clicking Apply on a Page with at least one attribute populates the configuration with a member-style layout (mostly full-width rows, sections drawn from the entity's `attribute_groups`).

- [ ] **Step 3: Smoke the member surface**

Sign in as a member of any customer whose entity has member-visible attributes. Navigate to that entity's surface detail page. Confirm:
- Sections appear with the entity's attribute-group names.
- Member-hidden attributes do **not** appear.
- Wide fields (textarea, select, file) span 2 detail columns; paired short fields (text, number, date) span 1.

- [ ] **Step 4: Run the moderate-change spec slice**

Run: `bundle exec rspec spec/services/page_layout_templates_spec.rb spec/services/page_layout_templates/ spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb spec/services/member/`
Expected: 0 failures.

- [ ] **Step 5: Record result**

No commit. Report PASS/FAIL with trimmed output. If FAIL, halt and triage before moving to Task 7.

---

## Task 7: Tech-lead + code-reviewer review (parallel)

**Files:**
- Read only

- [ ] **Step 1: Dispatch anysys-tech-lead and anysys-code-reviewer in parallel**

In a single message, dispatch two Agent calls:
- `anysys-tech-lead` — diff vs. AGENTS.md conventions. Particularly: ViewComponent purity (not touched, fine), single-file payment/captcha rule (not touched, fine), URL areas (not touched, fine), tenant scoping (no AR writes — the new applier reads from a caller-provided Entity, so isolation is the caller's job; assert this is documented). Reviewer should flag if any review finding warrants an inline edit.
- `anysys-code-reviewer` — correctness + security on the diff. Focus areas: visibility filter does not accidentally drop layout/section fields; the `group_by: :attribute_groups` branch handles symbol vs. string keys in `attribute_groups_json` correctly; `SurfaceTemplateApplier` never raises when `entity.attribute_groups_json` is nil or `entity.data_fields` is empty; no N+1 risk (`@entity.attribute_groups_json` is in-memory JSON).

- [ ] **Step 2: Collate findings**

If either reviewer surfaces blocking findings, add a remediation task for each, fix, run targeted specs, and commit before re-review.

If both come back clean, proceed to Task 8.

---

## Task 8: Merge worktree back to master

**Files:**
- Git-only

- [ ] **Step 1: Confirm clean state**

```bash
git status
```

Expected: working tree clean, on the worktree branch.

- [ ] **Step 2: Switch to master and merge**

```bash
git switch master
git merge --no-ff <worktree-branch-name> -m "Merge <worktree-branch-name>: member default page-layout template"
```

- [ ] **Step 3: Remove the worktree**

```bash
git worktree remove <worktree-path>
git branch -d <worktree-branch-name>
```

(Or via `EnterWorktree`/`ExitWorktree` if executed through those tools — the cleanup happens automatically when the worktree exits.)

- [ ] **Step 4: Final verification on master**

```bash
git log --oneline -10
bundle exec rspec spec/services/page_layout_templates_spec.rb spec/services/page_layout_templates/ spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb spec/services/member/
```

Expected: merge commit visible, spec slice PASSES.

Do **not** push to remote — per user preference, work stays local on master.

---

## Self-Review Notes (post-write)

- **Spec coverage:**
  - Spec §1 (DEFINITION) → Task 1.
  - Spec §2a (visibility filter) → Task 2.
  - Spec §2b (`group_by: :attribute_groups`) → Task 3.
  - Spec §3 (`Member::SurfaceTemplateApplier`) → Task 4.
  - Spec §4a (EntitySurfaceBuilder shim) → Task 5.
  - Spec §4b (admin path) → no code change needed; Task 6 smoke confirms the template appears in the picker.
  - Spec §5 (testing strategy) → woven into Tasks 1–5 plus Task 6's targeted spec slice.
- **Type consistency:** `Member::SurfaceTemplateApplier.call(entity:, template_key:)` keyword args are consistent in Task 4 spec, Task 4 implementation, and Task 5's mocked expectation.
- **Naming consistency:** `apply_visibility_filter!` (Task 2) and `reorganize_by_attribute_groups` (Task 3) match across spec, implementation, and follow-up tasks.
- **Multi-tenant note (Task 7):** The new applier reads only from a caller-provided Entity. Tenant isolation remains the caller's responsibility — `Member::Sources::Entities#surfaces` already scopes by `customer_id`. Documented; nothing to enforce inside the applier.

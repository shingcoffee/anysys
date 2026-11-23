# Public Default Page-Layout Template — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `public_default` PageLayoutTemplates DEFINITION, a new `"showcase"` theme preset, and a `mobile_stack` opt-in applier feature so public pages render beautifully and responsively for anonymous internet users.

**Architecture:** Three additive, non-overlapping changes: one new template file, one new entry in `ThemeResolver::THEME_PRESETS`, one new helper method in `PageTemplateApplier`. All other existing default templates (admin, member) remain unchanged.

**Tech Stack:** Ruby 3.2.8, Rails 8.1, RSpec, ViewComponent. No migrations, no new routes, no new view components.

**Spec reference:** `docs/superpowers/specs/2026-05-27-public-default-layout-template-design.md`

**Execution context:** Continue in the existing `worktree-member-default-template` worktree (the branch name is a slight mismatch with the work — addressed in the final merge commit message). Auto-commits OK on the worktree branch.

---

## File Structure

**Create (3 files):**
- `app/services/page_layout_templates/templates/general/public_default.rb` — the DEFINITION
- `spec/services/page_layout_templates/templates/general/public_default_spec.rb` — DEFINITION + registry
- `spec/components/concerns/theme_resolver_spec.rb` — only if not already present (otherwise extend)

**Modify (3 files):**
- `app/components/concerns/theme_resolver.rb` — add `"showcase"` preset
- `app/services/page_template_applier.rb` — add `apply_mobile_stack!` helper, call sites in `apply_single_page` and `build_multi_page`
- `spec/services/page_template_applier_spec.rb` — new `mobile_stack` context
- `spec/services/page_layout_templates_spec.rb` — stale-test fix (count 210 → 211, add `"public_default"` to key list)

**Dependency map (parallelizable batches):**

- **Batch 1 (parallel):**
  - Task 1: DEFINITION + spec + stale-test fix (one slice — same backend dev)
  - Task 2: `"showcase"` preset + preset spec
  - Task 3: `mobile_stack` in applier + applier spec
- **Batch 2:** Task 4 — release-engineer verification (depends on all of Batch 1)
- **Batch 3 (parallel):** Task 5 — tech-lead + code-reviewer
- **Batch 4:** Task 6 — merge

---

## Task 1: Public Default DEFINITION + stale-test fix

**Files:**
- Create: `app/services/page_layout_templates/templates/general/public_default.rb`
- Create: `spec/services/page_layout_templates/templates/general/public_default_spec.rb`
- Modify: `spec/services/page_layout_templates_spec.rb` (count bump + key add)

- [ ] **Step 1: Write the failing DEFINITION spec**

Create `spec/services/page_layout_templates/templates/general/public_default_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageLayoutTemplates::Templates::General::PublicDefault do
  describe "DEFINITION" do
    subject(:definition) { described_class::DEFINITION }

    it "is frozen" do
      expect(definition).to be_frozen
    end

    it "has key public_default" do
      expect(definition[:key]).to eq("public_default")
    end

    it "has name Default (Public)" do
      expect(definition[:name]).to eq("Default (Public)")
    end

    it "is registered under the general category" do
      expect(definition[:category]).to eq("general")
    end

    it "uses the showcase theme preset" do
      expect(definition[:theme_preset]).to eq("showcase")
    end

    it "has non-empty preview_rows" do
      expect(definition[:preview_rows]).to be_an(Array)
      expect(definition[:preview_rows]).not_to be_empty
    end

    describe "layout" do
      subject(:layout) { definition[:layout] }

      it "tags the audience as public" do
        expect(layout[:audience]).to eq("public")
      end

      it "defaults to full width" do
        expect(layout[:default_width]).to eq("full")
      end

      it "opts into mobile_stack" do
        expect(layout[:mobile_stack]).to be true
      end

      it "groups by attribute_groups" do
        expect(layout[:group_by]).to eq(:attribute_groups)
      end

      it "injects spacers and dividers between sections" do
        expect(layout[:inject_elements]).to eq([
          { after_section: 0, type: "spacer" },
          { after_section: 1, type: "divider" },
          { after_section: 2, type: "divider" },
          { after_section: 3, type: "spacer" }
        ])
      end

      describe "field_width_rules" do
        subject(:rules) { layout[:field_width_rules] }

        it "covers every html_type from PageContentGenerator::HTML_TYPE_COMPONENTS" do
          expect(rules.keys).to match_array(PageContentGenerator::HTML_TYPE_COMPONENTS.keys)
        end

        it "uses only valid width values" do
          rules.each_value { |w| expect(%w[full half third two_thirds]).to include(w) }
        end

        it "uses half only for tightly-paired short inputs" do
          %w[number currency date time color].each do |t|
            expect(rules[t]).to eq("half"), "expected #{t} => half, got #{rules[t]}"
          end
        end

        it "uses full for text, email, url, tel, month, week, password, hidden (more aggressive than member default)" do
          %w[text email url tel month week password hidden].each do |t|
            expect(rules[t]).to eq("full"), "expected #{t} => full, got #{rules[t]}"
          end
        end

        it "uses full for all selection/toggle/textarea/rich/file types" do
          %w[textarea select multi-select radio checkbox switch rich-text signature
             file image search range rating datetime-local].each do |t|
            expect(rules[t]).to eq("full"), "expected #{t} => full, got #{rules[t]}"
          end
        end
      end
    end
  end

  describe "PageLayoutTemplates.find" do
    it "returns the definition by key" do
      expect(PageLayoutTemplates.find("public_default")).to eq(described_class::DEFINITION)
    end
  end

  describe "PageLayoutTemplates::Registry" do
    it "discovers the template under the general category" do
      keys = PageLayoutTemplates.for_category("general").map { |t| t[:key] }
      expect(keys).to include("public_default")
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

Run: `bundle exec rspec spec/services/page_layout_templates/templates/general/public_default_spec.rb`
Expected: every example errors (`uninitialized constant PageLayoutTemplates::Templates::General::PublicDefault`).

- [ ] **Step 3: Create the DEFINITION**

Write `app/services/page_layout_templates/templates/general/public_default.rb`:

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
            mobile_stack: true,
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

- [ ] **Step 4: Run the spec; confirm it passes**

Run: `bundle exec rspec spec/services/page_layout_templates/templates/general/public_default_spec.rb`
Expected: all examples PASS.

- [ ] **Step 5: Fix the stale registry-count test**

In `spec/services/page_layout_templates_spec.rb`:
- Change `it "returns 210 templates"` to `it "returns 211 templates"`, with `eq(210)` → `eq(211)`
- Change `expect(described_class.for_category("all").length).to eq(210)` → `eq(211)`
- Change `expect(described_class.category_counts["all"]).to eq(210)` → `eq(211)`
- Change `expect(described_class.all.length).to eq(210)` (inside the reload! test) → `eq(211)`
- In the expected-keys list, insert `public_default` immediately after `member_default`:
  - Replace `blank default member_default compact_two_column ...` with `blank default member_default public_default compact_two_column ...`

Run: `bundle exec rspec spec/services/page_layout_templates_spec.rb`
Expected: all examples PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/page_layout_templates/templates/general/public_default.rb \
        spec/services/page_layout_templates/templates/general/public_default_spec.rb \
        spec/services/page_layout_templates_spec.rb
git commit -m "feat(page-templates): add public default layout template

Adds the public_default DEFINITION targeting the public audience
(anonymous + authenticated, no login required). Mobile-first widths
(mostly full; only number/currency/date/time/color are half),
mobile_stack opt-in for responsive collapse, audience: public for
visibility filtering, and group_by: attribute_groups with source
fallback. Uses the new 'showcase' theme preset (introduced separately)."
```

---

## Task 2: Add the `"showcase"` theme preset

**Files:**
- Modify: `app/components/concerns/theme_resolver.rb`
- Modify test: `spec/components/concerns/theme_resolver_spec.rb` (if exists; otherwise create)

- [ ] **Step 1: Inspect the existing spec file (if any)**

```bash
ls spec/components/concerns/theme_resolver_spec.rb 2>/dev/null && echo "exists" || echo "missing"
```

If missing, create a minimal new file in Step 2; if present, append new contexts.

- [ ] **Step 2: Write the failing preset spec**

If the spec file exists, append to it. Otherwise create `spec/components/concerns/theme_resolver_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ThemeResolver do
  describe "THEME_PRESETS['showcase']" do
    subject(:preset) { ThemeResolver::THEME_PRESETS["showcase"] }

    it "exists" do
      expect(preset).to be_a(Hash)
    end

    it "uses the violet primary and accent color" do
      expect(preset["primary_color"]).to eq("violet")
      expect(preset["accent_color"]).to eq("violet")
    end

    it "uses outline input style with sans font and large radius" do
      expect(preset["input_style"]).to eq("outline")
      expect(preset["font_family"]).to eq("sans")
      expect(preset["border_radius"]).to eq("lg")
    end

    it "uses full form width with subtle border and pronounced shadow" do
      expect(preset["form_width"]).to eq("full")
      expect(preset["form_shadow"]).to eq("xl")
      expect(preset["form_border"]).to eq("subtle")
      expect(preset["form_background"]).to eq("white")
    end

    it "uses generous padding and relaxed spacing for readability" do
      expect(preset["form_padding"]).to eq("generous")
      expect(preset["field_spacing"]).to eq("relaxed")
    end

    it "uses large inputs with uppercase labels for accessibility and polish" do
      expect(preset["input_size"]).to eq("lg")
      expect(preset["label_style"]).to eq("uppercase")
    end

    it "uses a gradient full-width large CTA button" do
      expect(preset["button_style"]).to eq("gradient")
      expect(preset["button_width"]).to eq("full")
      expect(preset["button_size"]).to eq("lg")
    end

    it "uses only token values that are valid against the existing _MAP constants" do
      expect(ThemeResolver::FORM_WIDTH_MAP).to have_key(preset["form_width"])
      expect(ThemeResolver::FORM_SHADOW_MAP).to have_key(preset["form_shadow"])
      expect(ThemeResolver::BUTTON_SIZE_MAP).to have_key(preset["button_size"])
    end
  end
end
```

- [ ] **Step 3: Run the spec; confirm it fails**

Run: `bundle exec rspec spec/components/concerns/theme_resolver_spec.rb`
Expected: all examples in the new context FAIL (preset doesn't exist yet).

- [ ] **Step 4: Add the preset**

In `app/components/concerns/theme_resolver.rb`, find the `THEME_PRESETS = {` hash (around line 121–157). After the `"playful"` entry (closing brace `}`), insert:

```ruby
    "showcase" => {
      "primary_color" => "violet", "accent_color" => "violet", "font_family" => "sans",
      "border_radius" => "lg", "input_style" => "outline", "form_background" => "white",
      "form_width" => "full", "form_shadow" => "xl", "form_padding" => "generous",
      "form_border" => "subtle", "field_spacing" => "relaxed", "input_size" => "lg",
      "label_style" => "uppercase", "button_style" => "gradient", "button_width" => "full", "button_size" => "lg"
    }
```

Make sure the line above (the playful entry's closing `}`) ends with a `,` if you're not at the end. The new entry itself should NOT have a trailing comma if it's the last in the hash (or should, if a future entry follows — keep matching the surrounding style).

- [ ] **Step 5: Run the spec; confirm it passes**

Run: `bundle exec rspec spec/components/concerns/theme_resolver_spec.rb`
Expected: all examples PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/concerns/theme_resolver.rb spec/components/concerns/theme_resolver_spec.rb
git commit -m "feat(themes): add showcase preset for public-audience pages

Violet primary, large inputs, uppercase labels, generous padding,
shadow-xl card, gradient CTA. Designed for first-impression public
forms where polish and trust matter more than density."
```

---

## Task 3: `mobile_stack` opt-in in PageTemplateApplier

**Files:**
- Modify: `app/services/page_template_applier.rb`
- Modify: `spec/services/page_template_applier_spec.rb`

- [ ] **Step 1: Write the failing applier spec**

Append the following context to `spec/services/page_template_applier_spec.rb` (after the `with group_by: :attribute_groups` context, before the closing `end`):

```ruby
context "with mobile_stack: true" do
  let(:mobile_stack_template) do
    {
      key: "mobile_stack_test_tmpl",
      name: "Mobile Stack Test",
      category: "general",
      theme_preset: "modern",
      preview_rows: [],
      layout: {
        default_width: "full",
        mobile_stack: true,
        field_width_rules: { "text" => "half", "number" => "half", "textarea" => "full" },
        group_by: nil,
        sections: [],
        inject_elements: []
      }
    }.freeze
  end

  before do
    allow(PageLayoutTemplates).to receive(:find).with("mobile_stack_test_tmpl").and_return(mobile_stack_template)
  end

  let(:stack_fields) do
    [
      { "id" => "f1", "property_slug" => "name",  "property_type" => "string", "html_type" => "text",     "width" => "full", "order" => 0 },
      { "id" => "f2", "property_slug" => "age",   "property_type" => "integer", "html_type" => "number", "width" => "full", "order" => 1 },
      { "id" => "f3", "property_slug" => "bio",   "property_type" => "string", "html_type" => "textarea", "width" => "full", "order" => 2 },
      { "id" => "section1", "field_type" => "section", "property_type" => "layout", "label" => "X", "width" => "full", "order" => 3 }
    ]
  end

  it "injects responsive_widths['mobile'] = 'full' for half-width fields" do
    result = described_class.call(stack_fields, "mobile_stack_test_tmpl")
    data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }
    name_field = data_fields.find { |f| f["property_slug"] == "name" }
    age_field  = data_fields.find { |f| f["property_slug"] == "age" }

    expect(name_field["width"]).to eq("half")
    expect(name_field["responsive_widths"]).to eq({ "mobile" => "full" })
    expect(age_field["width"]).to eq("half")
    expect(age_field["responsive_widths"]).to eq({ "mobile" => "full" })
  end

  it "does NOT inject responsive_widths for full-width fields" do
    result = described_class.call(stack_fields, "mobile_stack_test_tmpl")
    bio_field = result[:fields].reject { |f| f["property_type"] == "layout" }
                                .find { |f| f["property_slug"] == "bio" }

    expect(bio_field["width"]).to eq("full")
    expect(bio_field["responsive_widths"]).to be_nil
  end

  it "does NOT touch layout/section fields" do
    result = described_class.call(stack_fields, "mobile_stack_test_tmpl")
    section = result[:fields].find { |f| f["field_type"] == "section" }
    expect(section["responsive_widths"]).to be_nil
  end

  it "preserves a pre-existing responsive_widths['mobile'] value" do
    fields = stack_fields.first(1).map(&:dup)
    fields.first["responsive_widths"] = { "mobile" => "half", "tablet" => "half" }

    result = described_class.call(fields, "mobile_stack_test_tmpl")
    name_field = result[:fields].reject { |f| f["property_type"] == "layout" }
                                 .find { |f| f["property_slug"] == "name" }
    expect(name_field["responsive_widths"]).to eq({ "mobile" => "half", "tablet" => "half" })
  end
end

context "when mobile_stack is absent or false" do
  it "is a no-op (no responsive_widths injected)" do
    # Use the existing 'default' template, which has no mobile_stack key.
    fields = [
      { "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text",
        "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 0 }
    ]
    result = described_class.call(fields, "default")
    data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }
    data_fields.each { |f| expect(f["responsive_widths"]).to be_nil }
  end
end
```

- [ ] **Step 2: Run the spec; confirm it fails**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb -e "mobile_stack"`
Expected: the four `mobile_stack: true` examples FAIL; the absent/false example PASSES.

- [ ] **Step 3: Implement `apply_mobile_stack!`**

Edit `app/services/page_template_applier.rb`. Add the new method near `apply_width_rules` (between `apply_width_rules` and `apply_visibility_filter!`):

```ruby
# When layout[:mobile_stack] is true, force any non-full field to collapse to
# full width on mobile by setting responsive_widths["mobile"] = "full". Preserves
# any pre-existing mobile width so callers can override per-field.
def apply_mobile_stack!(fields, layout)
  return unless layout[:mobile_stack]

  fields.each do |field|
    next if field["property_type"] == "layout"
    next if field["width"] == "full"

    existing = field["responsive_widths"]
    existing_hash = existing.is_a?(Hash) ? existing : {}
    next if existing_hash.key?("mobile")

    field["responsive_widths"] = existing_hash.merge("mobile" => "full")
  end
end
```

Then add a call site in `apply_single_page` immediately after `apply_width_rules`:

```ruby
apply_width_rules(working_fields[:entity_fields], layout)
apply_mobile_stack!(working_fields[:entity_fields], layout)
```

And in `build_multi_page` immediately after the existing `apply_width_rules`:

```ruby
apply_width_rules(entity_fields, layout)
apply_mobile_stack!(entity_fields, layout)
```

- [ ] **Step 4: Run the spec; confirm it passes**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb -e "mobile_stack"`
Expected: all five examples PASS.

- [ ] **Step 5: Run the full applier slice to confirm no regression**

Run: `bundle exec rspec spec/services/page_template_applier_spec.rb spec/services/page_template_applier_default_spec.rb`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/page_template_applier.rb spec/services/page_template_applier_spec.rb
git commit -m "feat(page-templates): add mobile_stack opt-in to applier

When layout[:mobile_stack] is true, the applier injects
responsive_widths['mobile'] = 'full' on every field whose resolved
width is not 'full'. PageContentGenerator#responsive_col_span then
collapses those fields to col-span-12 on mobile while keeping the
half-width pair on desktop. Preserves any pre-existing mobile width
to respect upstream callers' explicit intent."
```

---

## Task 4: Release-engineer verification

**Files:** read-only

- [ ] **Step 1: Run the moderate-change spec slice**

```
bundle exec rspec \
  spec/services/page_layout_templates_spec.rb \
  spec/services/page_layout_templates/ \
  spec/services/page_template_applier_spec.rb \
  spec/services/page_template_applier_default_spec.rb \
  spec/services/member/ \
  spec/components/concerns/theme_resolver_spec.rb
```

Expected: 0 failures.

- [ ] **Step 2: Asset rebuild + smoke (best-effort)**

```
rm -f public/assets/.manifest.json
```

If the dev DB is bootstrapped, start the dev server with `SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` and curl the template-picker endpoint to confirm "Default (Public)" appears under General. If the worktree dev DB has pending migrations (as it did during the member_default rollout), skip the live smoke and rely on the spec suite. Note explicitly in the report which one happened.

- [ ] **Step 3: Report PASS/FAIL** with counts. No commit.

---

## Task 5: Parallel review

**Files:** read-only

- [ ] **Step 1: Dispatch anysys-tech-lead and anysys-code-reviewer in one message**

Tech-lead checks AGENTS.md compliance (no new URLs, no view component changes, tenant safety, the ignore-templates note carved out for `templates/general/public_default.rb`, the `theme_resolver.rb` change is a pure data addition).

Code-reviewer focuses on:
- `apply_mobile_stack!` correctness — preserves existing `responsive_widths["mobile"]`, ignores layout fields, ignores full-width fields.
- `"showcase"` preset tokens all resolve cleanly via the existing `_MAP` constants.
- Stale-test fix is complete (count + key list both updated).
- No N+1 / nothing that touches AR.

- [ ] **Step 2: Fix any blocking findings** before Task 6.

---

## Task 6: Merge back to master

**Files:** git-only

- [ ] **Step 1: Verify clean state**

```
git status
```

Expected: working tree clean.

- [ ] **Step 2: Merge to master with `--no-ff`**

From `/home/ec2-user/anysys` (the main checkout, not the worktree):

```
cd /home/ec2-user/anysys
git merge --no-ff worktree-member-default-template -m "Merge follow-up: public_default page-layout template + showcase theme preset

Adds a third default template (public_default) targeted at anonymous
internet visitors. Brings a new 'showcase' theme preset (violet,
generous spacing, large inputs, uppercase labels, gradient CTA) and an
opt-in 'mobile_stack' applier feature for responsive collapse of
half-width pairs on small screens."
```

- [ ] **Step 3: Final spec slice on master**

Run the same spec slice as Task 4 from master. Expected: 0 failures.

Do NOT push to remote.

---

## Self-review notes

- **Spec coverage:**
  - Spec §1 (DEFINITION) → Task 1.
  - Spec §2 (`"showcase"` preset) → Task 2.
  - Spec §3 (`mobile_stack` applier) → Task 3.
  - Spec §4 (wiring) → no code; verified by integration tests in Tasks 1 + 3.
  - Spec §5 (testing strategy) → covered across Tasks 1-4.
- **Naming consistency:** `apply_mobile_stack!`, `mobile_stack:` key, `"showcase"` preset all match across spec, plan, and implementation.
- **Multi-tenant safety:** `apply_mobile_stack!` and the new preset entry are pure functions / pure data — no AR access. Tech-lead review will confirm.
- **Independence:** Tasks 1, 2, 3 are file-disjoint and parallelizable. Task 4 depends on all three.

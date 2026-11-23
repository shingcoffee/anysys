# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageTemplateApplier do
  # Registers a stubbed custom template so PageLayoutTemplates.find(key) returns it.
  # Only the :layout differs between cases; the surrounding metadata is boilerplate.
  def stub_template(key, **layout)
    definition = {
      key: key, name: key.titleize, category: "general",
      theme_preset: "modern", preview_rows: [],
      layout: {
        default_width: "full", field_width_rules: {},
        group_by: nil, sections: [], inject_elements: []
      }.merge(layout)
    }.freeze
    allow(PageLayoutTemplates).to receive(:find).with(key).and_return(definition)
    definition
  end

  let(:sample_fields) do
    [
      { "id" => "section_001", "field_type" => "section", "property_type" => "layout", "label" => "User Fields", "width" => "full", "order" => 0 },
      { "id" => "field_001", "field_type" => "text", "property_slug" => "name", "property_type" => "string", "label" => "Name", "html_type" => "text", "width" => "full", "order" => 1 },
      { "id" => "field_002", "field_type" => "email", "property_slug" => "email", "property_type" => "string", "label" => "Email", "html_type" => "email", "width" => "full", "order" => 2 },
      { "id" => "field_003", "field_type" => "tel", "property_slug" => "phone", "property_type" => "string", "label" => "Phone", "html_type" => "tel", "width" => "full", "order" => 3 },
      { "id" => "field_004", "field_type" => "textarea", "property_slug" => "bio", "property_type" => "string", "label" => "Bio", "html_type" => "textarea", "width" => "full", "order" => 4 },
      { "id" => "field_005", "field_type" => "number", "property_slug" => "age", "property_type" => "integer", "label" => "Age", "html_type" => "number", "width" => "full", "order" => 5 }
    ]
  end

  describe ".call" do
    context "with blank template" do
      it "returns unmodified fields" do
        result = described_class.call(sample_fields, "blank")

        expect(result[:fields].length).to eq(sample_fields.length)
        expect(result[:theme]).to eq("modern")
      end
    end

    context "with nil template key" do
      it "returns unmodified fields" do
        result = described_class.call(sample_fields, nil)

        expect(result[:fields]).to eq(sample_fields)
        expect(result[:theme]).to be_nil
      end
    end

    context "with invalid template key" do
      it "returns unmodified fields" do
        result = described_class.call(sample_fields, "nonexistent")

        expect(result[:fields]).to eq(sample_fields)
        expect(result[:theme]).to be_nil
      end
    end

    context "with contact_detailed template" do
      it "applies width rules based on html_type" do
        result = described_class.call(sample_fields, "contact_detailed")
        fields = result[:fields].reject { |f| f["property_type"] == "layout" }

        text_field = fields.find { |f| f["html_type"] == "text" }
        email_field = fields.find { |f| f["html_type"] == "email" }
        tel_field = fields.find { |f| f["html_type"] == "tel" }
        textarea_field = fields.find { |f| f["html_type"] == "textarea" }

        expect(text_field["width"]).to eq("half")
        expect(email_field["width"]).to eq("half")
        expect(tel_field["width"]).to eq("half")
        expect(textarea_field["width"]).to eq("full")
      end

      it "creates section headers with field_type 'section'" do
        result = described_class.call(sample_fields, "contact_detailed")
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["id"]&.start_with?("section_") }

        header_labels = headers.map { |h| h["label"] }
        expect(header_labels).to include("Your Information")
        expect(header_labels).to include("Your Message")

        headers.each do |header|
          expect(header["field_type"]).to eq("section")
        end
      end

      it "returns the correct theme preset" do
        result = described_class.call(sample_fields, "contact_detailed")
        expect(result[:theme]).to eq("modern")
      end

      it "applies sequential ordering" do
        result = described_class.call(sample_fields, "contact_detailed")
        orders = result[:fields].map { |f| f["order"] }

        expect(orders).to eq((0...result[:fields].length).to_a)
      end
    end

    context "with compact_simple template" do
      it "uses half-width as default for unmatched types" do
        fields_with_search = [
          { "id" => "field_010", "property_slug" => "q", "property_type" => "string", "label" => "Search", "html_type" => "search", "width" => "full", "order" => 0 }
        ]

        result = described_class.call(fields_with_search, "compact_two_column")
        field = result[:fields].find { |f| f["html_type"] == "search" }

        expect(field["width"]).to eq("half")
      end

      it "applies full width for textarea" do
        result = described_class.call(sample_fields, "compact_two_column")
        textarea = result[:fields].find { |f| f["html_type"] == "textarea" }

        expect(textarea["width"]).to eq("full")
      end
    end

    context "with wizard_multi_step template" do
      it "creates multi-page structure" do
        result = described_class.call(sample_fields, "wizard_multi_step")

        expect(result[:fields]).to be_an(Array)
        expect(result[:fields].first).to have_key("id")
        expect(result[:fields].first).to have_key("name")
        expect(result[:fields].first).to have_key("fields")
      end

      it "distributes fields across pages" do
        result = described_class.call(sample_fields, "wizard_multi_step")
        pages = result[:fields]

        total_fields = pages.sum { |p| p["fields"].length }
        entity_field_count = sample_fields.count { |f| f["property_type"] != "layout" }
        expect(total_fields).to eq(entity_field_count)
      end

      it "creates pages with sequential ordering" do
        result = described_class.call(sample_fields, "wizard_multi_step")
        pages = result[:fields]

        page_orders = pages.map { |p| p["order"] }
        expect(page_orders).to eq(page_orders.sort)
      end

      it "names pages as steps" do
        result = described_class.call(sample_fields, "wizard_multi_step")
        names = result[:fields].map { |p| p["name"] }

        expect(names.first).to eq("Step 1")
      end
    end

    context "with professional_detailed template" do
      it "organizes fields into category sections" do
        result = described_class.call(sample_fields, "sectioned_professional")
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["id"]&.start_with?("section_") }

        header_labels = headers.map { |h| h["label"] }
        expect(header_labels).to include("Text Fields")
        expect(header_labels).to include("Numbers & Dates")
      end

      it "injects dividers between sections with correct field_type" do
        result = described_class.call(sample_fields, "sectioned_professional")
        dividers = result[:fields].select { |f| f["field_type"] == "divider" }

        expect(dividers).not_to be_empty
        dividers.each do |divider|
          expect(divider["property_type"]).to eq("layout")
          expect(divider["field_type"]).to eq("divider")
        end
      end
    end

    context "with survey_feedback template" do
      it "injects dividers between sections" do
        fields_with_rating = sample_fields + [
          { "id" => "field_006", "property_slug" => "rating", "property_type" => "number", "label" => "Rating", "html_type" => "rating", "width" => "full", "order" => 6 }
        ]

        result = described_class.call(fields_with_rating, "customer_feedback")
        dividers = result[:fields].select { |f| f["field_type"] == "divider" }

        expect(dividers).not_to be_empty
      end
    end

    context "with group_by: :source template (lines 55-58)" do
      let(:source_fields) do
        [
          { "id" => "f1", "property_slug" => "name", "property_type" => "string",
            "html_type" => "text", "source" => "entity", "source_section" => "Personal",
            "width" => "full", "order" => 0 },
          { "id" => "f2", "property_slug" => "org", "property_type" => "string",
            "html_type" => "text", "source" => "base_model", "source_section" => "user",
            "width" => "full", "order" => 1 },
          { "id" => "f3", "property_slug" => "linked_thing", "property_type" => "string",
            "html_type" => "text", "source" => "bridge", "source_section" => "Course",
            "width" => "full", "order" => 2 }
        ]
      end

      before { stub_template("source_group_tmpl", group_by: :source) }

      it "groups fields by source, generating section headers per group" do
        result = described_class.call(source_fields, "source_group_tmpl")
        headers = result[:fields].select { |f| f["field_type"] == "section" }
        header_labels = headers.map { |h| h["label"] }
        # entity source -> "Personal", base_model source -> "User", bridge source -> "Linked: Course"
        expect(header_labels).to include("Personal")
        expect(header_labels).to include("User")
        expect(header_labels).to include("Linked: Course")
      end

      it "sets variant to 'linked' for bridge section headers (line 337 build_source_section_label)" do
        result = described_class.call(source_fields, "source_group_tmpl")
        bridge_header = result[:fields].find { |f| f["field_type"] == "section" && f["label"].start_with?("Linked:") }
        expect(bridge_header["variant"]).to eq("linked")
      end

      it "humanizes base_model source_section as label (line 332-333)" do
        result = described_class.call(source_fields, "source_group_tmpl")
        base_header = result[:fields].find { |f| f["field_type"] == "section" && f["label"] == "User" }
        expect(base_header).not_to be_nil
      end

      it "uses source_section directly for entity source (line 335)" do
        result = described_class.call(source_fields, "source_group_tmpl")
        entity_header = result[:fields].find { |f| f["field_type"] == "section" && f["label"] == "Personal" }
        expect(entity_header).not_to be_nil
      end
    end

    context "build_source_section_label 'else' branch — unknown source type (line 339)" do
      before { stub_template("other_source_tmpl", group_by: :source) }

      it "labels the section 'Other Fields' for unknown source types" do
        fields = [
          { "id" => "f1", "property_slug" => "x", "property_type" => "string",
            "html_type" => "text", "source" => "computed", "source_section" => "Derived",
            "width" => "full", "order" => 0 }
        ]
        result = described_class.call(fields, "other_source_tmpl")
        headers = result[:fields].select { |f| f["field_type"] == "section" }
        expect(headers.map { |h| h["label"] }).to include("Other Fields")
      end

      it "translates Other Fields" do
        fields = [{ "id" => "f1", "property_slug" => "x", "property_type" => "string", "html_type" => "text",
                    "source" => "computed", "source_section" => "Derived", "width" => "full", "order" => 0 }]
        result = I18n.with_locale(:"zh-CN") { described_class.call(fields, "other_source_tmpl") }

        expect(result[:fields].select { |f| f["field_type"] == "section" }.map { |h| h["label"] }).to eq(["其他字段"])
      end
    end

    context "layout_element_defaults — spacer and heading branches (lines 365, 367)" do
      let(:inject_fields) do
        [
          { "id" => "f1", "property_slug" => "name", "property_type" => "string",
            "html_type" => "text", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_slug" => "email", "property_type" => "string",
            "html_type" => "email", "width" => "full", "order" => 1 }
        ]
      end

      before do
        stub_template("inject_tmpl",
          sections: [
            { label: "A", match_types: %w[text] },
            { label: "B", match_types: %w[email] }
          ],
          inject_elements: [
            { type: "spacer", after_section: 0 },
            { type: "heading", after_section: 1 }
          ])
      end

      it "injects a spacer element between sections (line 365)" do
        result = described_class.call(inject_fields, "inject_tmpl")
        spacers = result[:fields].select { |f| f["field_type"] == "spacer" }
        expect(spacers).not_to be_empty
        expect(spacers.first["spacer_height"]).to eq("md")
      end

      it "injects a heading element between sections (line 367)" do
        result = described_class.call(inject_fields, "inject_tmpl")
        headings = result[:fields].select { |f| f["field_type"] == "heading" }
        expect(headings).not_to be_empty
        expect(headings.first["heading_level"]).to eq("h3")
      end
    end

    context "layout_element_defaults — else branch for unknown type (line 369)" do
      before do
        stub_template("custom_inject_tmpl",
          sections: [{ label: "Only", match_types: %w[text] }],
          inject_elements: [{ type: "custom_element", after_section: 0 }])
      end

      it "raises for unknown element types" do
        fields = [
          { "id" => "f1", "property_slug" => "name", "property_type" => "string",
            "html_type" => "text", "width" => "full", "order" => 0 }
        ]
        expect { described_class.call(fields, "custom_inject_tmpl") }.to raise_error(ArgumentError, /custom_element/)
      end
    end

    it "does not mutate original fields" do
      original_fields = sample_fields.map { |f| f.dup }
      described_class.call(sample_fields, "contact_detailed")

      sample_fields.each_with_index do |field, i|
        expect(field["width"]).to eq(original_fields[i]["width"])
      end
    end

    it "places unmatched fields in an 'Other Fields' section" do
      fields_with_hidden = [
        { "id" => "field_100", "property_slug" => "secret", "property_type" => "string", "label" => "Secret", "html_type" => "hidden", "width" => "full", "order" => 0 }
      ]

      result = described_class.call(fields_with_hidden, "customer_feedback")
      headers = result[:fields].select { |f| f["property_type"] == "layout" && f["id"]&.start_with?("section_") }

      expect(headers.map { |h| h["label"] }).to include("Other Fields")
    end

    context "with layout[:audience] set" do
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

      before { stub_template("audience_test_tmpl", audience: "member", field_width_rules: { "text" => "half" }) }

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

    context "with mobile_stack: true" do
      let(:stack_fields) do
        [
          { "id" => "f1", "property_slug" => "name",  "property_type" => "string", "html_type" => "text",     "width" => "full", "order" => 0 },
          { "id" => "f2", "property_slug" => "age",   "property_type" => "integer", "html_type" => "number", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_slug" => "bio",   "property_type" => "string", "html_type" => "textarea", "width" => "full", "order" => 2 },
          { "id" => "section1", "field_type" => "section", "property_type" => "layout", "label" => "X", "width" => "full", "order" => 3 }
        ]
      end

      before do
        stub_template("mobile_stack_test_tmpl", mobile_stack: true,
          field_width_rules: { "text" => "half", "number" => "half", "textarea" => "full" })
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

    context "with group_by: :attribute_groups" do
      let_it_be(:customer) { create(:customer) }
      let(:entity) do
        e = create(:entity, customer: customer)
        e.attribute_groups_json = [
            { "id" => "g_one", "name" => "Account" },
            { "id" => "g_two", "name" => "Profile" }
          ]
        e.property_schema_json = []
        e.save(validate: false)
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

      before do
        stub_template("attr_groups_test_tmpl", field_width_rules: { "text" => "half" }, group_by: :attribute_groups)
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

      it "skips groups whose name is nil or blank" do
        e = create(:entity, customer: customer)
        e.attribute_groups_json = [
            { "id" => "g_named", "name" => "Named" },
            { "id" => "g_nameless", "name" => nil },
            { "id" => "g_blank",    "name" => "" }
          ]
        e.property_schema_json = []
        e.save(validate: false)
        e = Entity.find(e.id)

        fields = [
          { "id" => "f_n", "property_slug" => "n", "property_type" => "string", "html_type" => "text", "group_id" => "g_named",    "width" => "full", "order" => 0 },
          { "id" => "f_x", "property_slug" => "x", "property_type" => "string", "html_type" => "text", "group_id" => "g_nameless", "width" => "full", "order" => 1 },
          { "id" => "f_y", "property_slug" => "y", "property_type" => "string", "html_type" => "text", "group_id" => "g_blank",    "width" => "full", "order" => 2 }
        ]

        result = described_class.call(fields, "attr_groups_test_tmpl", entity: e)
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
        # Only the named group keeps its own section header; the rest fall into "Additional".
        expect(headers.map { |h| h["label"] }).to eq(["Named", "Additional"])
      end

      it "skips empty groups entirely" do
        # An entity that defines three groups but only provides fields for one
        e = create(:entity, customer: customer)
        e.attribute_groups_json = [
            { "id" => "ga", "name" => "Used" },
            { "id" => "gb", "name" => "Empty" }
          ]
        e.property_schema_json = []
        e.save(validate: false)
        e = Entity.find(e.id)

        fields = [
          { "id" => "x1", "property_slug" => "only", "property_type" => "string", "html_type" => "text", "group_id" => "ga", "width" => "full", "order" => 0 }
        ]

        result = described_class.call(fields, "attr_groups_test_tmpl", entity: e)
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
        expect(headers.map { |h| h["label"] }).to eq(["Used"])
      end

      it "falls back to source-based grouping when entity is nil or has no named groups" do
        # No entity → source grouping kicks in. With fields lacking source/source_section,
        # reorganize_by_source places them all under one "Other Fields" section header.
        result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: nil)
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
        expect(headers.map { |h| h["label"] }).to eq(["Other Fields"])
        expect(result[:fields].reject { |f| f["property_type"] == "layout" }.map { |f| f["property_slug"] })
          .to eq(%w[email password bio freeform])
      end

      it "falls back to source-based grouping when entity has only nameless/blank groups" do
        e = create(:entity, customer: customer)
        e.attribute_groups_json = [{ "id" => "g_blank", "name" => "" }, { "id" => "g_nil", "name" => nil }]
        e.property_schema_json = []
        e.save(validate: false)
        e = Entity.find(e.id)

        result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: e)
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }
        # All fields lack source/source_section, so reorganize_by_source produces a single "Other Fields" section.
        expect(headers.map { |h| h["label"] }).to eq(["Other Fields"])
      end

      it "injects a divider between sections (not before the first)" do
        result = described_class.call(grouped_fields, "attr_groups_test_tmpl", entity: entity)
        types_in_order = result[:fields].map { |f| f["field_type"] }
        first_section_idx = types_in_order.index("section")
        expect(types_in_order[0...first_section_idx]).not_to include("divider")
        expect(types_in_order.count("divider")).to be >= 2
      end

      it "gives each link section its own heading instead of Additional" do
        fields = grouped_fields + [
          { "id" => "l1", "property_slug" => "student", "property_type" => "string", "html_type" => "select",
            "source" => "bridge", "source_section" => "assoc_course_student", "source_section_label" => "Student",
            "group_id" => "g_one", "width" => "full", "order" => 4 }
        ]
        result = described_class.call(fields, "attr_groups_test_tmpl", entity: entity)
        headers = result[:fields].select { |f| f["property_type"] == "layout" && f["field_type"] == "section" }

        expect(headers.map { |h| h["label"] }).to eq(["Account", "Profile", "Additional", "Linked: Student"])
        expect(headers.last["variant"]).to eq("linked")
        expect(result[:fields].last["property_slug"]).to eq("student")
      end

      it "writes zh-CN headings and slugs when generating in zh-CN" do
        fields = grouped_fields + [
          { "id" => "l1", "property_slug" => "student", "property_type" => "string", "html_type" => "select",
            "source" => "bridge", "source_section" => "assoc_course_student", "source_section_label" => "学生",
            "width" => "full", "order" => 4 }
        ]
        result = I18n.with_locale(:"zh-CN") { described_class.call(fields, "attr_groups_test_tmpl", entity: entity) }
        layout = result[:fields].select { |f| f["property_type"] == "layout" }

        expect(layout.select { |f| f["field_type"] == "section" }.map { |h| h["label"] }).to eq(["Account", "Profile", "其他信息", "关联：学生"])
        expect(layout.select { |f| f["field_type"] == "divider" }.map { |d| d["label"] }.uniq).to eq(["分隔线"])
        expect(layout.map { |f| f["property_slug"] }).to all(be_present)
      end
    end
  end

  # -----------------------------------------------------------------------
  # Branch-coverage additions — remaining arms not hit above
  # -----------------------------------------------------------------------

  describe "apply_mobile_stack! — pre-existing mobile key is preserved (line 121 :then next-branch)" do
    before { stub_template("pre_mobile_tmpl", default_width: "half", mobile_stack: true) }

    it "preserves an already-set responsive_widths['mobile'] value" do
      fields = [
        { "id" => "f1", "property_slug" => "name", "property_type" => "string",
          "html_type" => "text", "width" => "full", "order" => 0,
          "responsive_widths" => { "mobile" => "quarter" } }
      ]
      result = described_class.call(fields, "pre_mobile_tmpl")
      data = result[:fields].reject { |f| f["property_type"] == "layout" }.first
      # The pre-existing "mobile" => "quarter" must NOT be overwritten to "full"
      expect(data["responsive_widths"]["mobile"]).to eq("quarter")
    end
  end

  describe "reorganize_by_attribute_groups — no ungrouped fields (line 203 :else — ungrouped.any? false)" do
    let(:customer) { create(:customer) }

    before { stub_template("all_grouped_tmpl", group_by: :attribute_groups) }

    it "omits the Additional section when all fields belong to named groups" do
      e = create(:entity, customer: customer)
      e.attribute_groups_json = [{ "id" => "g1", "name" => "Core" }]
        e.property_schema_json = []
        e.save(validate: false)
      e = Entity.find(e.id)

      fields = [
        { "id" => "f1", "property_slug" => "name", "property_type" => "string",
          "html_type" => "text", "group_id" => "g1", "width" => "full", "order" => 0 }
      ]
      result = described_class.call(fields, "all_grouped_tmpl", entity: e)
      headers = result[:fields].select { |f| f["field_type"] == "section" }
      expect(headers.map { |h| h["label"] }).not_to include("Additional")
    end

    it "no divider before the first group section when result starts empty (line 185 :else)" do
      e = create(:entity, customer: customer)
      e.attribute_groups_json = [{ "id" => "g1", "name" => "Core" }]
        e.property_schema_json = []
        e.save(validate: false)
      e = Entity.find(e.id)

      fields = [
        { "id" => "f1", "property_slug" => "x", "property_type" => "string",
          "html_type" => "text", "group_id" => "g1", "width" => "full", "order" => 0 }
      ]
      result = described_class.call(fields, "all_grouped_tmpl", entity: e)
      types = result[:fields].map { |f| f["field_type"] }
      # First field in result should be the section header, not a divider
      expect(types.first).to eq("section")
    end
  end

  describe "inject_layout_elements — insert-at-end when last section (lines 245-249)" do
    before do
      stub_template("inject_end_tmpl",
        sections: [{ label: "Only", match_types: %w[text] }],
        inject_elements: [{ type: "divider", after_section: 0 }])
    end

    it "inserts a divider after the last section (next_header_pos is nil → insert at end)" do
      fields = [
        { "id" => "f1", "property_slug" => "name", "property_type" => "string",
          "html_type" => "text", "width" => "full", "order" => 0 }
      ]
      result = described_class.call(fields, "inject_end_tmpl")
      types = result[:fields].map { |f| f["field_type"] }
      expect(types).to include("divider")
      # Divider must come after the data field, not before the section header
      div_idx    = types.rindex("divider")
      field_idx  = types.index { |t| !%w[section divider spacer heading].include?(t) }
      expect(div_idx).to be > field_idx
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageTemplateApplier do
  describe "default template (source-based grouping)" do
    describe "single primary entity with multiple html_types" do
      it "produces one section header followed by all fields in original order" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "label" => "Name", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "string", "html_type" => "email", "label" => "Email", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_type" => "integer", "html_type" => "number", "label" => "Age", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 2 },
          { "id" => "f4", "property_type" => "string", "html_type" => "textarea", "label" => "Bio", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 3 }
        ]

        result = described_class.call(fields, "default")

        sections = result[:fields].select { |f| f["field_type"] == "section" }
        expect(sections.length).to eq(1)
        expect(sections.first["label"]).to eq("Student")
        expect(sections.first["variant"]).to be_nil

        # Check fields follow in original order
        data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }
        expect(data_fields.map { |f| f["id"] }).to eq(%w[f1 f2 f3 f4])

        # No dividers (only one section)
        dividers = result[:fields].select { |f| f["field_type"] == "divider" }
        expect(dividers).to be_empty
      end

      it "applies width rules from the template" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "label" => "Name", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "string", "html_type" => "textarea", "label" => "Bio", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_type" => "string", "html_type" => "file", "label" => "Resume", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 2 }
        ]

        result = described_class.call(fields, "default")
        data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }

        expect(data_fields.find { |f| f["html_type"] == "text" }["width"]).to eq("half")
        expect(data_fields.find { |f| f["html_type"] == "textarea" }["width"]).to eq("full")
        expect(data_fields.find { |f| f["html_type"] == "file" }["width"]).to eq("full")
      end
    end

    describe "primary entity plus two associations" do
      it "produces three sections with correct labels and variants" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "label" => "Name", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "string", "html_type" => "email", "label" => "Email", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_type" => "string", "html_type" => "text", "label" => "Street", "source" => "bridge", "source_section" => "Address", "width" => "full", "order" => 2 },
          { "id" => "f4", "property_type" => "string", "html_type" => "text", "label" => "City", "source" => "bridge", "source_section" => "Address", "width" => "full", "order" => 3 },
          { "id" => "f5", "property_type" => "string", "html_type" => "text", "label" => "Zip", "source" => "bridge", "source_section" => "Address", "width" => "full", "order" => 4 },
          { "id" => "f6", "property_type" => "string", "html_type" => "text", "label" => "Course Name", "source" => "bridge", "source_section" => "Course", "width" => "full", "order" => 5 },
          { "id" => "f7", "property_type" => "integer", "html_type" => "number", "label" => "Credits", "source" => "bridge", "source_section" => "Course", "width" => "full", "order" => 6 }
        ]

        result = described_class.call(fields, "default")

        sections = result[:fields].select { |f| f["field_type"] == "section" }
        expect(sections.length).to eq(3)

        # First section: Student (no variant)
        expect(sections[0]["label"]).to eq("Student")
        expect(sections[0]["variant"]).to be_nil

        # Second section: Linked: Address (variant: linked)
        expect(sections[1]["label"]).to eq("Linked: Address")
        expect(sections[1]["variant"]).to eq("linked")

        # Third section: Linked: Course (variant: linked)
        expect(sections[2]["label"]).to eq("Linked: Course")
        expect(sections[2]["variant"]).to eq("linked")

        # Check dividers between sections (2 dividers for 3 sections)
        dividers = result[:fields].select { |f| f["field_type"] == "divider" }
        expect(dividers.length).to eq(2)

        # No trailing divider
        expect(result[:fields].last["field_type"]).not_to eq("divider")
      end

      it "preserves original field order within each group" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "label" => "Name", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "string", "html_type" => "email", "label" => "Email", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_type" => "string", "html_type" => "text", "label" => "Street", "source" => "bridge", "source_section" => "Address", "width" => "full", "order" => 2 },
          { "id" => "f4", "property_type" => "string", "html_type" => "text", "label" => "City", "source" => "bridge", "source_section" => "Address", "width" => "full", "order" => 3 },
          { "id" => "f5", "property_type" => "string", "html_type" => "text", "label" => "Zip", "source" => "bridge", "source_section" => "Address", "width" => "full", "order" => 4 }
        ]

        result = described_class.call(fields, "default")
        data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }

        # Student fields
        student_fields = data_fields[0..1]
        expect(student_fields.map { |f| f["id"] }).to eq(%w[f1 f2])

        # Address fields
        address_fields = data_fields[2..4]
        expect(address_fields.map { |f| f["id"] }).to eq(%w[f3 f4 f5])
      end
    end

    describe "width rules per html_type" do
      it "applies correct widths for various html_types" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "source" => "entity", "source_section" => "Test", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "string", "html_type" => "textarea", "source" => "entity", "source_section" => "Test", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_type" => "string", "html_type" => "file", "source" => "entity", "source_section" => "Test", "width" => "full", "order" => 2 },
          { "id" => "f4", "property_type" => "integer", "html_type" => "rating", "source" => "entity", "source_section" => "Test", "width" => "full", "order" => 3 },
          { "id" => "f5", "property_type" => "boolean", "html_type" => "checkbox", "source" => "entity", "source_section" => "Test", "width" => "full", "order" => 4 }
        ]

        result = described_class.call(fields, "default")
        data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }

        expect(data_fields.find { |f| f["html_type"] == "text" }["width"]).to eq("half")
        expect(data_fields.find { |f| f["html_type"] == "textarea" }["width"]).to eq("full")
        expect(data_fields.find { |f| f["html_type"] == "file" }["width"]).to eq("full")
        expect(data_fields.find { |f| f["html_type"] == "rating" }["width"]).to eq("third")
        expect(data_fields.find { |f| f["html_type"] == "checkbox" }["width"]).to eq("full")
      end
    end

    describe "empty input" do
      it "returns empty fields array" do
        result = described_class.call([], "default")
        expect(result[:fields]).to eq([])
      end
    end

    describe "order preservation within group" do
      it "maintains input order when entity fields enter as name, age, email" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "label" => "Name", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "integer", "html_type" => "number", "label" => "Age", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 1 },
          { "id" => "f3", "property_type" => "string", "html_type" => "email", "label" => "Email", "source" => "entity", "source_section" => "Student", "width" => "full", "order" => 2 }
        ]

        result = described_class.call(fields, "default")
        data_fields = result[:fields].reject { |f| f["property_type"] == "layout" }

        expect(data_fields.map { |f| f["id"] }).to eq(%w[f1 f2 f3])
        expect(data_fields.map { |f| f["label"] }).to eq(["Name", "Age", "Email"])
      end
    end

    describe "theme" do
      it "returns modern as the theme preset" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "source" => "entity", "source_section" => "Test", "width" => "full", "order" => 0 }
        ]

        result = described_class.call(fields, "default")
        expect(result[:theme]).to eq("modern")
      end
    end

    describe "base_model source" do
      it "renders base_model fields with humanized section label" do
        fields = [
          { "id" => "f1", "property_type" => "string", "html_type" => "text", "label" => "ID", "source" => "base_model", "source_section" => "base_model", "width" => "full", "order" => 0 },
          { "id" => "f2", "property_type" => "datetime", "html_type" => "datetime-local", "label" => "Created At", "source" => "base_model", "source_section" => "base_model", "width" => "full", "order" => 1 }
        ]

        result = described_class.call(fields, "default")
        sections = result[:fields].select { |f| f["field_type"] == "section" }

        expect(sections.length).to eq(1)
        expect(sections.first["label"]).to eq("Base model")
        expect(sections.first["variant"]).to be_nil
      end
    end
  end
end

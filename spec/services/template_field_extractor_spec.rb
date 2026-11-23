# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateFieldExtractor do
  describe ".call" do
    def fields_for(template)
      described_class.call(template)[:fields]
    end

    def groups_for(template)
      described_class.call(template)[:groups]
    end

    it "returns empty fields and groups for nil template" do
      expect(described_class.call(nil)).to eq(fields: [], groups: [])
    end

    it "returns empty fields and groups for template without preview_rows" do
      expect(described_class.call({ key: "test" })).to eq(fields: [], groups: [])
    end

    it "extracts input fields with correct html_type" do
      template = {
        preview_rows: [
          [{ type: :input, width: "full", label: "Name" }]
        ]
      }
      fields = fields_for(template)
      expect(fields.length).to eq(1)
      expect(fields.first).to include(
        name: "Name",
        name_slug: "name",
        html_type: "text"
      )
    end

    it "extracts textarea fields" do
      template = { preview_rows: [[{ type: :textarea, width: "full", label: "Message" }]] }
      expect(fields_for(template).first).to include(html_type: "textarea")
    end

    it "extracts select fields" do
      template = { preview_rows: [[{ type: :select, width: "half", label: "Category" }]] }
      expect(fields_for(template).first).to include(html_type: "select")
    end

    it "extracts checkbox fields" do
      template = { preview_rows: [[{ type: :checkbox, width: "full", label: "Newsletter" }]] }
      expect(fields_for(template).first).to include(html_type: "checkbox")
    end

    it "extracts date fields" do
      template = { preview_rows: [[{ type: :date, width: "half", label: "Start Date" }]] }
      expect(fields_for(template).first).to include(html_type: "date")
    end

    it "extracts number fields" do
      template = { preview_rows: [[{ type: :number, width: "half", label: "Amount" }]] }
      expect(fields_for(template).first).to include(html_type: "number")
    end

    it "extracts file fields" do
      template = { preview_rows: [[{ type: :file, width: "full", label: "Attachment" }]] }
      expect(fields_for(template).first).to include(html_type: "file")
    end

    it "extracts radio fields" do
      template = { preview_rows: [[{ type: :radio, width: "full", label: "Gender" }]] }
      expect(fields_for(template).first).to include(html_type: "radio")
    end

    it "skips non-field layout elements (divider, spacer, button, steps)" do
      template = {
        preview_rows: [
          [{ type: :divider }],
          [{ type: :spacer }],
          [{ type: :button, label: "Submit" }],
          [{ type: :steps, labels: ["Step 1", "Step 2"] }]
        ]
      }
      expect(described_class.call(template)).to eq(fields: [], groups: [])
    end

    it "skips elements without labels" do
      template = { preview_rows: [[{ type: :input, width: "full" }]] }
      expect(fields_for(template)).to be_empty
    end

    it "infers email html_type from label" do
      template = { preview_rows: [[{ type: :input, width: "full", label: "Email" }]] }
      expect(fields_for(template).first[:html_type]).to eq("email")
    end

    it "infers tel html_type from phone label" do
      template = { preview_rows: [[{ type: :input, width: "half", label: "Phone" }]] }
      expect(fields_for(template).first[:html_type]).to eq("tel")
    end

    it "infers url html_type from website label" do
      template = { preview_rows: [[{ type: :input, width: "full", label: "Website" }]] }
      expect(fields_for(template).first[:html_type]).to eq("url")
    end

    it "infers password html_type from password label" do
      template = { preview_rows: [[{ type: :input, width: "full", label: "Password" }]] }
      expect(fields_for(template).first[:html_type]).to eq("password")
    end

    it "deduplicates fields with the same label" do
      template = {
        preview_rows: [
          [{ type: :input, width: "half", label: "Item" }, { type: :number, width: "half", label: "Amount" }],
          [{ type: :input, width: "half", label: "Item" }, { type: :number, width: "half", label: "Amount" }]
        ]
      }
      slugs = fields_for(template).map { |f| f[:name_slug] }
      expect(slugs).to eq(%w[item amount item_2 amount_2])
    end

    it "generates correct slugs from multi-word labels" do
      template = {
        preview_rows: [
          [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }]
        ]
      }
      expect(fields_for(template).map { |f| f[:name_slug] }).to eq(%w[first_name last_name])
    end

    it "does not include type key in field output" do
      template = { preview_rows: [[{ type: :input, width: "full", label: "Name" }]] }
      expect(fields_for(template).first).not_to have_key(:type)
    end

    it "extracts fields from a real template" do
      template = PageLayoutTemplates.find("contact_simple")
      skip "contact_simple template not found" unless template

      fields = fields_for(template)
      expect(fields).to be_an(Array)
      expect(fields.length).to be > 0
      fields.each do |field|
        expect(field).to have_key(:name)
        expect(field).to have_key(:name_slug)
        expect(field).to have_key(:html_type)
      end
    end

    context "section -> group extraction" do
      let(:template) do
        {
          preview_rows: [
            [{ type: :section, label: "Personal Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "full", label: "Email" }],
            [{ type: :divider }],
            [{ type: :section, label: "Address" }],
            [{ type: :input, width: "full", label: "Street" }],
            [{ type: :input, width: "half", label: "City" }, { type: :select, width: "half", label: "State" }],
            [{ type: :checkbox, width: "full", label: "Newsletter" }]
          ]
        }
      end

      it "extracts every field across sections in order" do
        expect(fields_for(template).map { |f| f[:name] }).to eq(
          ["First Name", "Last Name", "Email", "Street", "City", "State", "Newsletter"]
        )
      end

      it "emits one group per section label, in order" do
        expect(groups_for(template).map { |g| g[:label] }).to eq(["Personal Info", "Address"])
      end

      it "tags each field with the key of the section it falls under" do
        groups = groups_for(template)
        personal_key = groups.find { |g| g[:label] == "Personal Info" }[:key]
        address_key  = groups.find { |g| g[:label] == "Address" }[:key]

        by_name = fields_for(template).index_by { |f| f[:name] }
        expect(by_name["First Name"][:group_key]).to eq(personal_key)
        expect(by_name["Email"][:group_key]).to eq(personal_key)
        expect(by_name["Street"][:group_key]).to eq(address_key)
        expect(by_name["Newsletter"][:group_key]).to eq(address_key)
      end

      it "assigns nil group_key to fields preceding the first section" do
        template = {
          preview_rows: [
            [{ type: :input, width: "full", label: "Headline" }],
            [{ type: :section, label: "Details" }],
            [{ type: :input, width: "full", label: "Body" }]
          ]
        }
        by_name = fields_for(template).index_by { |f| f[:name] }
        expect(by_name["Headline"][:group_key]).to be_nil
        expect(by_name["Body"][:group_key]).not_to be_nil
      end

      it "drops sections that capture no fields" do
        template = {
          preview_rows: [
            [{ type: :section, label: "Empty Section" }],
            [{ type: :divider }],
            [{ type: :section, label: "Real Section" }],
            [{ type: :input, width: "full", label: "Name" }]
          ]
        }
        expect(groups_for(template).map { |g| g[:label] }).to eq(["Real Section"])
      end

      it "ignores section elements without a label" do
        template = {
          preview_rows: [
            [{ type: :section }],
            [{ type: :input, width: "full", label: "Name" }]
          ]
        }
        expect(groups_for(template)).to be_empty
        expect(fields_for(template).first[:group_key]).to be_nil
      end
    end
  end
end

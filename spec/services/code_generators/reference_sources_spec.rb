# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ReferenceSources do
  let(:customer_a) { create(:customer) }
  let(:customer_b) { create(:customer) }

  it "registers every A6 source and returns nil for an unknown key" do
    expect(described_class.keys).to match_array(
      %w[
        email_templates sms_templates constants entities entity_associations
        pages flowcharts job_classes service_classes
      ]
    )
    expect(described_class.fetch("email_templates")).to be_present
    expect(described_class.fetch("missing")).to be_nil
  end

  describe "email_templates" do
    let!(:owned) { create(:email_template, customer: customer_a, name: "Welcome A") }
    let!(:other) { create(:email_template, customer: customer_b, name: "Welcome B") }

    it "lists and validates only the given customer's templates" do
      source = described_class.fetch("email_templates")
      values = source.options(customer: customer_a).map { |row| row[:value] }
      expect(values).to include(owned.id)
      expect(values).not_to include(other.id)
      expect(source.valid?(owned.id, customer: customer_a)).to be(true)
      expect(source.valid?(other.id, customer: customer_a)).to be(false)
    end
  end

  describe "sms_templates" do
    let!(:template) { create(:sms_template, key: "verify_code_t4", description: "Verify") }

    it "lists platform templates by key" do
      source = described_class.fetch("sms_templates")
      row = source.options(customer: customer_a).find { |item| item[:value] == "verify_code_t4" }
      expect(row[:label]).to be_present
      expect(source.valid?("verify_code_t4", customer: customer_a)).to be(true)
      expect(source.valid?("missing_key", customer: customer_a)).to be(false)
    end
  end

  describe "constants" do
    let!(:shared) { create(:constant, :shared, name: "Shared Status") }
    let!(:owned) { create(:constant, :customer_specific, customer: customer_a, name: "Owned A") }
    let!(:other) { create(:constant, :customer_specific, customer: customer_b, name: "Owned B") }

    it "includes customer-owned and shared rows, never the other tenant" do
      source = described_class.fetch("constants")
      labels = source.options(customer: customer_a).map { |row| row[:label] }
      expect(labels).to include("Shared Status", "Owned A")
      expect(labels).not_to include("Owned B")
      expect(source.valid?(owned.id, customer: customer_a)).to be(true)
      expect(source.valid?(other.id, customer: customer_a)).to be(false)
      expect(source.valid?(shared.id, customer: customer_a)).to be(true)
    end
  end

  describe "entities" do
    let!(:shared) { create(:entity, :shared, name: "Shared Entity") }
    let!(:owned) { create(:entity, customer: customer_a, name: "Owned Entity") }
    let!(:other) { create(:entity, customer: customer_b, name: "Other Entity") }

    it "includes customer-owned and shared entities" do
      source = described_class.fetch("entities")
      values = source.options(customer: customer_a).map { |row| row[:value] }
      expect(values).to include(owned.id, shared.id)
      expect(values).not_to include(other.id)
      expect(source.valid?(other.id, customer: customer_a)).to be(false)
    end
  end

  describe "entity_associations" do
    let!(:course) do
      create(:entity, customer: customer_a, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let!(:student) do
      create(:entity, customer: customer_a, name: "Student").tap do |entity|
        entity.update!(
          associations: [{
            "target_entity_id" => course.id,
            "target_entity_name" => "Course",
            "display_field" => "name",
            "display_field_label" => "Name"
          }].to_json
        )
      end
    end
    let!(:foreign) { create(:entity, customer: customer_b, name: "Foreign") }

    it "lists associations of the bound entity only" do
      source = described_class.fetch("entity_associations")
      rows = source.options(customer: customer_a, entity_id: student.id)
      expect(rows).to include(hash_including(value: course.id.to_s, label: "Course"))
      expect(source.options(customer: customer_a, entity_id: foreign.id)).to eq([])
      expect(source.valid?(course.id, customer: customer_a, entity_id: student.id)).to be(true)
      expect(source.valid?(course.id, customer: customer_b, entity_id: student.id)).to be(false)
    end
  end

  describe "pages" do
    let!(:owned) { create(:page, customer: customer_a, name: "Owned Page", launched: true) }
    let!(:draft) { create(:page, customer: customer_a, name: "Draft Page", launched: false) }
    let!(:shared) { create(:page, :shared, name: "Shared Page", launched: true) }
    let!(:other) { create(:page, customer: customer_b, name: "Other Page", launched: true) }

    it "lists launched visible pages the customer can access" do
      source = described_class.fetch("pages")
      values = source.options(customer: customer_a).map { |row| row[:value] }
      expect(values).to include(owned.id, shared.id)
      expect(values).not_to include(draft.id, other.id)
    end
  end

  describe "flowcharts" do
    let!(:owned) { create(:flowchart, :launched_status, customer: customer_a, name: "Owned Flow") }
    let!(:draft) { create(:flowchart, :draft, customer: customer_a, name: "Draft Flow") }
    let!(:shared) { create(:flowchart, :shared_type, :launched_status, name: "Shared Flow") }
    let!(:other) { create(:flowchart, :launched_status, customer: customer_b, name: "Other Flow") }

    it "lists launched flowcharts the customer can use and excludes another id" do
      source = described_class.fetch("flowcharts")
      values = source.options(customer: customer_a).map { |row| row[:value] }
      expect(values).to include(owned.id, shared.id)
      expect(values).not_to include(draft.id, other.id)
      excluded = source.options(customer: customer_a, exclude_id: owned.id).map { |row| row[:value] }
      expect(excluded).not_to include(owned.id)
      expect(source.valid?(owned.id, customer: customer_a)).to be(true)
      expect(source.valid?(other.id, customer: customer_a)).to be(false)
      expect(source.valid?(owned.id, customer: customer_a, exclude_id: owned.id)).to be(false)
    end
  end

  describe "job_classes" do
    it "lists ApplicationJob subclasses accepted by Invocable" do
      source = described_class.fetch("job_classes")
      values = source.options(customer: customer_a).map { |row| row[:value] }
      expect(values).to include("Emails::DeliverMessageJob")
      expect(source.valid?("Emails::DeliverMessageJob", customer: customer_a)).to be(true)
      expect(source.valid?("Kernel", customer: customer_a)).to be(false)
    end
  end

  describe "service_classes" do
    it "lists the Invocable service allow-list" do
      source = described_class.fetch("service_classes")
      values = source.options(customer: customer_a).map { |row| row[:value] }
      expect(values).to include(*FlowchartRuntime::Invocable::SERVICE_ALLOWLIST)
      expect(source.valid?("ApplicationService", customer: customer_a)).to be(true)
      expect(source.valid?("Object", customer: customer_a)).to be(false)
    end
  end

  it "honours query and limit on options" do
    create(:email_template, customer: customer_a, name: "Alpha Welcome")
    create(:email_template, customer: customer_a, name: "Beta Notice")
    source = described_class.fetch("email_templates")
    rows = source.options(customer: customer_a, query: "alpha", limit: 1)
    expect(rows.size).to eq(1)
    expect(rows.first[:label]).to match(/alpha/i)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplatePreviewBuilder do
  let_it_be(:customer) { create(:customer) }

  # Use a real registered template so we exercise the full call path
  # without stubbing the internal collaborators.
  let(:template_key) { "job_application" }
  let(:ref_data)     { PageLayoutTemplates.find(template_key) }

  describe ".call (no entity — template-only path)" do
    subject(:result) { described_class.call(customer: customer, ref_data: ref_data) }

    it "returns a hash with :page and :content keys" do
      expect(result).to include(:page, :content)
    end

    it "returns an unsaved Page instance" do
      expect(result[:page]).to be_a(Page)
      expect(result[:page]).not_to be_persisted
    end

    it "sets the page name from the template name" do
      expect(result[:page].name).to eq(ref_data[:name].to_s)
    end

    it "sets the page customer" do
      expect(result[:page].customer).to eq(customer)
    end

    it "produces a non-blank content string" do
      expect(result[:content]).to be_present
    end

    it "stores the template description on the page" do
      expect(result[:page].description).to eq(ref_data[:description])
    end
  end

  describe ".call (with entity — entity-scoped path)" do
    subject(:result) do
      described_class.call(customer: customer, ref_data: ref_data, entity: entity)
    end

    let(:entity) { create(:entity, name: "Applicant", customer: customer) }


    it "returns a hash with :page and :content keys" do
      expect(result).to include(:page, :content)
    end

    it "prefixes the page name with the entity name" do
      expect(result[:page].name).to start_with("Applicant — ")
    end
  end

  describe "ref_data as HashWithIndifferentAccess" do
    it "handles HashWithIndifferentAccess input without error" do
      indifferent = ref_data.with_indifferent_access
      expect {
        described_class.call(customer: customer, ref_data: indifferent)
      }.not_to raise_error
    end
  end

  describe "theme injection" do
    it "does not raise when the template has no theme key" do
      ref = { key: "custom_no_theme", name: "No Theme", description: "",
              preview_rows: [] }
      # Should call TemplateFieldExtractor cleanly with an empty template
      expect {
        described_class.call(customer: customer, ref_data: ref)
      }.not_to raise_error
    end
  end
end

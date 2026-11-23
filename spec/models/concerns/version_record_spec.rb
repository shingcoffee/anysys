# frozen_string_literal: true

require "rails_helper"

# Shared behavior spec for VersionRecord (content-addressed, head-pointer
# versioning) across the three version classes that include it.
RSpec.describe VersionRecord do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  describe "FlowchartVersion" do
    let(:flowchart) { create(:flowchart, customer: customer) }

    it "validates version_number uniqueness per parent" do
      v1 = flowchart.current_version
      content = FlowchartConfigurationContent.store!(
        customer_id: customer.id, payload: JSON.parse(flowchart.configuration))
      dup = flowchart.flowchart_versions.build(
        customer_id: customer.id, version_number: v1.version_number, content: content)
      expect(dup).not_to be_valid
    end

    it "exposes payload uniformly through content" do
      v = flowchart.current_version
      expect(JSON.parse(v.payload)).to eq(JSON.parse(flowchart.configuration))
    end

    it "exposes based_on_version_number" do
      v1 = flowchart.current_version
      flowchart.configuration = {
        "elements" => [], "connections" => [],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }.to_json
      v2 = flowchart.commit_version!
      expect(v2.based_on_version_number).to eq(v1.version_number)
    end

    it "ordered scope returns newest first" do
      flowchart.configuration = {
        "elements" => [], "connections" => [],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }.to_json
      flowchart.commit_version!
      expect(flowchart.flowchart_versions.ordered.first.version_number).to eq(2)
    end
  end

  describe "EntityVersion" do
    let(:entity) { create(:entity, customer: customer) }

    it "validates version_number uniqueness per parent" do
      v1 = entity.current_version
      content = EntityDefinitionContent.store!(customer_id: customer.id, payload: { "property_schema" => [] })
      dup = entity.entity_versions.build(
        customer_id: customer.id, version_number: v1.version_number, content: content)
      expect(dup).not_to be_valid
    end

    it "requires a content row" do
      v = entity.entity_versions.build(customer_id: customer.id, version_number: 99, content: nil)
      expect(v).not_to be_valid
      expect(v.errors[:content]).to include("must exist")
    end

    it "exposes payload uniformly through content" do
      content = EntityDefinitionContent.store!(customer_id: customer.id, payload: { "x" => 1 })
      v = EntityVersion.create!(entity: entity, customer_id: customer.id, version_number: 999, content: content)
      expect(v.payload).to eq(content.payload)
    end

    it "exposes based_on_version_number" do
      v1 = entity.current_version
      content2 = EntityDefinitionContent.store!(customer_id: customer.id, payload: { "property_schema" => [{ "key" => "z" }] })
      v2 = EntityVersion.create!(
        entity: entity, customer_id: customer.id, version_number: v1.version_number + 1,
        content: content2, based_on_version: v1)
      expect(v2.based_on_version_number).to eq(v1.version_number)
    end
  end

  describe "PageVersion" do
    let(:page) { create(:page, customer: customer) }

    it "validates version_number uniqueness per parent" do
      v1 = page.current_version
      content = PageConfigurationContent.store!(customer_id: customer.id, payload: JSON.parse(page.configuration))
      dup = page.page_versions.build(customer_id: customer.id, version_number: v1.version_number, content: content)
      expect(dup).not_to be_valid
    end

    it "exposes payload uniformly through content" do
      v = page.current_version
      expect(JSON.parse(v.payload)).to eq(JSON.parse(page.configuration))
    end

    it "exposes based_on_version_number" do
      v1 = page.current_version
      config = JSON.parse(page.configuration)
      config["pages"] = [{ "id" => "page_2", "name" => "Page 2", "order" => 1, "fields" => [] }]
      page.configuration = config.to_json
      page.save!
      v2 = page.current_version
      expect(v2.based_on_version_number).to eq(v1.version_number)
    end

    it "ordered scope returns newest first" do
      config = JSON.parse(page.configuration)
      config["pages"] = [{ "id" => "page_2", "name" => "Page 2", "order" => 1, "fields" => [] }]
      page.configuration = config.to_json
      page.save!
      expect(page.page_versions.ordered.first.version_number).to eq(2)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Versionable, "parent content garbage collection", type: :model do
  let(:customer) { create(:customer) }

  it "collects content only after the last referencing parent/version is destroyed" do
    first = create(:entity, customer: customer, name: "First", description: "identical")
    second = create(:entity, customer: customer, name: "Second", description: "identical")
    content_id = first.current_version.content_id
    expect(second.current_version.content_id).to eq(content_id)

    first.destroy!
    expect(EntityDefinitionContent.exists?(content_id)).to be(true)
    second.destroy!
    expect(EntityDefinitionContent.exists?(content_id)).to be(false)
  end

  it "preserves global content reused by a different tenant version line" do
    shared = create(:entity, :shared, description: "global")
    content = shared.current_version.content
    owned = create(:entity, customer: customer)
    reused = owned.entity_versions.create!(customer_id: customer.id, version_number: 2, content: content)
    shared.destroy!
    expect(EntityDefinitionContent.exists?(content.id)).to be(true)
    expect(reused.reload.payload).to include("global")
    owned.destroy!
    expect(EntityDefinitionContent.exists?(content.id)).to be(false)
  end

  it "collects unreferenced content from both global and override lines" do
    shared = create(:entity, :shared, description: "global")
    Current.with_customer(customer) do
      Entity.find(shared.id).update!(description: "override")
    end
    ids = shared.entity_versions.pluck(:content_id)
    shared.destroy!
    expect(EntityDefinitionContent.where(id: ids)).to be_empty
  end

  it "does not sweep global content still reused by an override when the default line is pruned" do
    shared = create(:entity, :shared, description: "global")
    content = shared.current_version.content
    shared.entity_versions.create!(customer_id: customer.id, version_number: 1, content: content)
    stub_const("Versionable::MAX_VERSIONS", 1)
    Current.with_customer(nil) { shared.update!(description: "new default") }
    expect(EntityDefinitionContent.exists?(content.id)).to be(true)
  end

  it "collects page content after the last referencing page is destroyed" do
    entity = create(:entity, customer: customer)
    first = create(:page, customer: customer, entity: entity)
    second = create(:page, customer: customer, entity: entity, configuration: first.configuration)
    content_id = first.current_version.content_id
    expect(second.current_version.content_id).to eq(content_id)
    first.destroy!
    expect(PageConfigurationContent.exists?(content_id)).to be(true)
    second.destroy!
    expect(PageConfigurationContent.exists?(content_id)).to be(false)
  end

  it "collects flowchart content after the last referencing flowchart is destroyed" do
    first = create(:flowchart, :empty, customer: customer)
    second = create(:flowchart, :empty, customer: customer, configuration: first.configuration)
    content_id = first.current_version.content_id
    expect(second.current_version.content_id).to eq(content_id)
    first.destroy!
    expect(FlowchartConfigurationContent.exists?(content_id)).to be(true)
    second.destroy!
    expect(FlowchartConfigurationContent.exists?(content_id)).to be(false)
  end
end

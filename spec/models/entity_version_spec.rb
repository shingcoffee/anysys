# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityVersion, type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before { Current.customer = customer }

  def content_for(payload)
    EntityDefinitionContent.store!(customer_id: customer.id, payload: payload)
  end

  it "is valid with a content row and version_number" do
    v = entity.entity_versions.build(customer_id: customer.id, version_number: 99, content: content_for({ "x" => 1 }))
    expect(v).to be_valid
  end

  it "requires a content row" do
    v = entity.entity_versions.build(customer_id: customer.id, version_number: 99, content: nil)
    expect(v).not_to be_valid
    expect(v.errors[:content]).to be_present
  end

  it "enforces version_number uniqueness per entity" do
    entity.entity_versions.create!(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 1 }))
    dup = entity.entity_versions.build(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 2 }))
    expect(dup).not_to be_valid
  end

  it "allows the same version_number for a different entity" do
    other_entity = create(:entity, customer: customer)
    entity.entity_versions.create!(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 1 }))
    version = other_entity.entity_versions.build(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 2 }))
    expect(version).to be_valid
  end

  it "orders newest first and exposes payload through content" do
    # Entity auto-creates v1 via Versionable's after_save; use higher numbers to avoid collision
    entity.entity_versions.create!(customer_id: customer.id, version_number: 10, content: content_for({ "name" => "A" }))
    entity.entity_versions.create!(customer_id: customer.id, version_number: 20, content: content_for({ "name" => "B" }))
    latest = entity.entity_versions.ordered.first
    expect(latest.version_number).to eq(20)
    expect(JSON.parse(latest.payload)).to eq("name" => "B")
  end

  describe "content dedup" do
    it "shares one content row when the same payload is stored twice" do
      c1 = content_for({ "same" => true })
      c2 = content_for({ "same" => true })
      expect(c1).to eq(c2)
    end
  end

  describe "committed via Entity#commit_version!" do
    it "creates v1 pointing at content derived from the entity's definition" do
      v1 = entity.current_version
      expect(v1).to be_present
      expect(v1.version_number).to eq(1)
      expect(JSON.parse(v1.payload)["property_schema"]).to eq([])
    end

    it "advances the head and preserves lineage when the definition changes" do
      v1 = entity.current_version
      entity.property_schema_json = [{ "name_slug" => "a" }]
      entity.save!
      v2 = entity.current_version
      expect(v2.version_number).to eq(2)
      expect(v2.based_on_version_id).to eq(v1.id)
    end
  end
end

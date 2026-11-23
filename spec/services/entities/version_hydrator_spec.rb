# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::VersionHydrator do
  let_it_be(:customer) { create(:customer) }

  def version_for(entity, payload)
    content = entity.content_class.store!(customer_id: entity.customer_id, payload: payload)
    entity.commit_version!(content: content)
  end

  describe ".snapshot_hash" do
    it "returns {} for a nil version" do
      expect(described_class.snapshot_hash(nil)).to eq({})
    end

    it "parses a JSON string payload" do
      entity = create(:entity, customer: customer)
      version = version_for(entity, { "property_schema" => [{ "name" => "Title" }] })
      expect(described_class.snapshot_hash(version)["property_schema"]).to eq([{ "name" => "Title" }])
    end

    it "returns {} for invalid JSON" do
      entity = create(:entity, customer: customer)
      version = entity.current_version
      allow(version).to receive(:payload).and_return("{not-json")
      expect(described_class.snapshot_hash(version)).to eq({})
    end

    it "returns {} when the payload is not a hash" do
      entity = create(:entity, customer: customer)
      version = entity.current_version
      allow(version).to receive(:payload).and_return("[1]")
      expect(described_class.snapshot_hash(version)).to eq({})
    end

    it "accepts an already-parsed hash payload" do
      entity = create(:entity, customer: customer)
      version = entity.current_version
      allow(version).to receive(:payload).and_return({ "property_schema" => [] })
      expect(described_class.snapshot_hash(version)).to eq({ "property_schema" => [] })
    end
  end

  describe ".hydrate" do
    it "loads the version snapshot onto a separate in-memory copy" do
      entity = create(:entity, customer: customer, property_schema: [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
      ].to_json)
      v1 = entity.current_version
      entity.property_schema_json = [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
        { "name" => "Email", "name_slug" => "email", "html_type" => "email" }
      ]
      entity.save!

      hydrated = described_class.hydrate(entity, v1)
      slugs = hydrated.property_schema_json.map { |f| f["name_slug"] }
      expect(slugs).to eq(["name"])
      expect(entity.reload.property_schema_json.map { |f| f["name_slug"] }).to include("email")
    end

    it "applies icon, color, and description from the snapshot" do
      entity = create(:entity, customer: customer, icon: "custom", color: "#111111", description: "now")
      version = entity.current_version
      payload = described_class.snapshot_hash(version).merge(
        "icon" => "star", "color" => "#ffffff", "description" => "then"
      )
      content = entity.content_class.store!(customer_id: entity.customer_id, payload: payload)
      v = entity.commit_version!(content: content)
      hydrated = described_class.hydrate(entity, v)
      expect(hydrated.icon).to eq("star")
      expect(hydrated.color).to eq("#ffffff")
      expect(hydrated.description).to eq("then")
    end
  end
end

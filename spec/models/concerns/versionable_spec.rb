# frozen_string_literal: true

require "rails_helper"

# Authoritative behavior spec for content-addressed, head-pointer versioning.
RSpec.describe Versionable do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  def build_entity(schema)
    e = Entity.new(name: "E#{rand(1_000_000)}", customer: customer)
    e.property_schema_json = schema
    e.save!
    e
  end

  describe "#commit_version! (auto-committed on save)" do
    it "creates v1 on create and advances the head" do
      e = build_entity([{ "name_slug" => "a" }])
      expect(e.current_version).to be_present
      expect(e.current_version.version_number).to eq(1)
      expect(e.property_schema_json).to eq([{ "name_slug" => "a" }])
    end

    it "no-ops when the definition is unchanged (rename creates no version)" do
      e = build_entity([{ "name_slug" => "a" }])
      expect { e.update!(name: "renamed") }.not_to change { e.entity_versions.count }
    end

    it "creates a new version and dedups content when the definition changes" do
      e = build_entity([{ "name_slug" => "a" }])
      v1 = e.current_version
      e.property_schema_json = [{ "name_slug" => "b" }]
      e.save!
      expect(e.current_version.version_number).to eq(2)
      expect(e.current_version_id).not_to eq(v1.id)
      expect(EntityDefinitionContent.where(customer_id: customer.id).count).to eq(2)
    end

    it "reuses one content row for an identical definition committed twice" do
      e = build_entity([{ "name_slug" => "a" }])
      e.property_schema_json = [{ "name_slug" => "b" }]; e.save!
      e.property_schema_json = [{ "name_slug" => "a" }]; e.save!
      expect(EntityDefinitionContent.where(customer_id: customer.id).count).to eq(2)
    end
  end

  describe "#restore_as_new!" do
    it "creates a new head referencing the chosen version's existing content (no new content row)" do
      e = build_entity([{ "name_slug" => "a" }])
      v1 = e.current_version
      e.property_schema_json = [{ "name_slug" => "b" }]; e.save!
      content_count = EntityDefinitionContent.where(customer_id: customer.id).count

      e.restore_as_new!(v1)

      expect(EntityDefinitionContent.where(customer_id: customer.id).count).to eq(content_count)
      expect(e.property_schema_json).to eq([{ "name_slug" => "a" }])
      expect(e.current_version.based_on_version_id).to eq(v1.id)
      expect(e.current_version.version_number).to eq(3)
    end
  end

  describe "#set_current_version!" do
    it "moves the head pointer without creating a version and reloads the definition" do
      e = build_entity([{ "name_slug" => "a" }])
      v1 = e.current_version
      e.property_schema_json = [{ "name_slug" => "b" }]; e.save!

      expect { e.set_current_version!(v1) }.not_to change { e.entity_versions.count }
      expect(e.current_version_id).to eq(v1.id)
      expect(e.property_schema_json).to eq([{ "name_slug" => "a" }])
    end
  end

  describe "pruning + content GC" do
    it "prunes past MAX_VERSIONS and GCs content orphaned by the prune" do
      stub_const("Versionable::MAX_VERSIONS", 2)
      e = build_entity([{ "name_slug" => "value", "k" => 1 }])
      e.property_schema_json = [{ "name_slug" => "value", "k" => 2 }]; e.save!
      e.property_schema_json = [{ "name_slug" => "value", "k" => 3 }]; e.save!

      payloads = EntityDefinitionContent.where(customer_id: customer.id).pluck(:payload)
      expect(payloads.any? { |p| p.include?('"k":1') }).to be(false)
      expect(e.entity_versions.count).to eq(2)
    end
  end

  describe "multi-tenant content scoping" do
    it "does not share content rows across customers" do
      e1 = build_entity([{ "name_slug" => "same" }])
      other = create(:customer)
      Current.customer = other
      e2 = Entity.new(name: "E2", customer: other)
      e2.property_schema_json = [{ "name_slug" => "same" }]
      e2.save!
      expect(e1.current_version.content_id).not_to eq(e2.current_version.content_id)
    end
  end
end

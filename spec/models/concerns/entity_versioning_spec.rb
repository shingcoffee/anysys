# frozen_string_literal: true

#
# This spec was previously testing the EntityVersioning concern, which has been
# folded into the shared, content-addressed Versionable concern (see
# spec/models/concerns/versionable_spec.rb for the authoritative behavior spec).
# The tests here exercise Entity-specific versioning behavior on top of that
# concern: auto-commit on save, restore-as-new, lineage, pruning, and bridge
# entities (which now DO receive versions, unlike the pre-refactor behavior).
#
require "rails_helper"

RSpec.describe "Entity versioning via Versionable", type: :model do
  let_it_be(:customer) { create(:customer) }

  def build_entity(**attrs)
    create(:entity, { customer: customer, name: "Donor",
                      property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json }.merge(attrs))
  end

  describe "#commit_version! (auto-committed on save)" do
    it "creates version 1 as the current head on create" do
      e = build_entity
      v1 = e.current_version
      expect(v1).to be_present
      expect(v1.version_number).to eq(1)
      snap = JSON.parse(v1.payload)
      expect(snap["property_schema"].first["name_slug"]).to eq("email")
    end

    it "creates a new current version when the definition changes" do
      e = build_entity
      v1 = e.current_version
      e.update!(description: "A donor record")
      v2 = e.current_version
      expect(v2.version_number).to eq(2)
      expect(e.current_version_id).to eq(v2.id)
      expect(v2.id).not_to eq(v1.id)
    end

    it "no-ops when the definition is unchanged (identity-only change creates no version)" do
      e = build_entity
      expect { e.update!(name: "Renamed Donor") }.not_to change { e.entity_versions.count }
    end
  end

  describe "bridge entities" do
    it "now receive versions (they are no longer excluded from versioning)" do
      e = build_entity(category: :bridge)
      expect(e.bridge_entity?).to be true
      expect(e.current_version).to be_present
      expect(e.entity_versions.count).to be >= 1
    end
  end

  describe "pruning to MAX_VERSIONS" do
    it "keeps only the latest MAX_VERSIONS versions" do
      stub_const("Versionable::MAX_VERSIONS", 2)
      e = build_entity
      5.times do |n|
        e.property_schema_json = [{ "name" => "Field#{n}", "name_slug" => "field_#{n}" }]
        e.save!
      end
      expect(e.entity_versions.count).to eq(2)
    end
  end

  describe "#restore_as_new!" do
    it "creates a single new head version referencing the chosen version's existing content" do
      e = build_entity
      v1 = e.current_version
      e.property_schema_json = [{ "name" => "Changed", "name_slug" => "changed" }]
      e.save!
      content_count = EntityDefinitionContent.where(customer_id: customer.id).count

      e.restore_as_new!(v1)

      expect(EntityDefinitionContent.where(customer_id: customer.id).count).to eq(content_count)
      expect(e.property_schema_json.first["name_slug"]).to eq("email")
      expect(e.current_version.based_on_version_id).to eq(v1.id)
      expect(e.current_version.version_number).to eq(3)
    end
  end

  describe "based-on lineage" do
    it "leaves the initial version with no based_on reference" do
      e = build_entity
      v1 = e.current_version
      expect(v1.based_on_version_id).to be_nil
      expect(v1.based_on_version_number).to be_nil
    end

    it "references the previous current version as lineage on successive commits" do
      e = build_entity
      v1 = e.current_version
      e.update!(description: "v2")
      v2 = e.current_version
      expect(v2.based_on_version_id).to eq(v1.id)
      expect(v2.based_on_version_number).to eq(1)
    end

    it "references an explicit based_on_version_id when provided" do
      e = build_entity
      v1 = e.current_version
      e.update!(description: "v2")
      e.property_schema_json = [{ "name" => "Z", "name_slug" => "z" }]
      v3 = e.commit_version!(description: "v3", based_on_version_id: v1.id)
      expect(v3.based_on_version_id).to eq(v1.id)
    end
  end

  describe "bridge entity versioning via sync_bridge_entities!" do
    let!(:source) { build_entity(name: "Student") }
    let!(:target) do
      create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end

    it "creates a v1 head for bridge entities created by sync_bridge_entities!" do
      source.associations_json = [{
        "target_entity_id" => target.id,
        "target_entity_name" => target.name,
        "display_field" => "name",
        "display_field_label" => "Name",
        "additional_attributes" => []
      }]
      source.save!
      source.sync_bridge_entities!

      bridge = Entity.unscope(where: :category).find_by(name: "assoc_student_course")
      expect(bridge).to be_present
      expect(bridge.bridge_entity?).to be true
      # Bridge entities now go through the same autocommit path as any other entity.
      expect(bridge.current_version).to be_present
      expect(bridge.entity_versions.count).to be >= 1
    end
  end
end

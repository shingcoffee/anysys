# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entity, "backend audit", type: :model do
  let(:customer) { create(:customer) }

  %i[property_schema associations attribute_groups default_properties].each do |attribute|
    ["{", "null", "true", "42", '"text"'].each do |raw|
      it "rejects #{attribute}=#{raw.inspect} with model errors" do
        entity = build(:entity, customer: customer)
        entity.public_send("#{attribute}=", raw)
        expect(entity).not_to be_valid
        expect(entity.errors[attribute]).to be_present
        expect(entity.public_send(attribute)).to eq(raw)
      end
    end
  end

  %i[property_schema associations attribute_groups].each do |attribute|
    [{}, [nil], ["text"], [1], [true]].each do |value|
      it "rejects malformed #{attribute} container/items: #{value.inspect}" do
        entity = build(:entity, customer: customer)
        entity.public_send("#{attribute}_json=", value)
        expect(entity).not_to be_valid
        expect(entity.errors[attribute]).to be_present
      end
    end
  end

  it "does not read invalid JSON as an empty definition" do
    entity = build(:entity, customer: customer, property_schema: "{")
    expect(entity.property_schema_json).to be_nil
    expect(entity.save).to be(false)
  end

  it "requires a slug for every property and association additional attribute" do
    target = create(:entity, customer: customer,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    entity = build(:entity, customer: customer)
    entity.property_schema_json = [{ "name" => "Missing slug" }]
    entity.associations_json = [{ "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name", "additional_attributes" => [{ "name" => "Missing slug" }] }]
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to be_present
    expect(entity.errors[:associations]).to be_present
  end

  it "rejects malformed association ids and nested attributes without throwing" do
    entity = build(:entity, customer: customer)
    entity.associations_json = [{ "target_entity_id" => {}, "bridge_entity_id" => [], "additional_attributes" => false }]
    expect(entity).not_to be_valid
    expect(entity.errors[:associations]).to be_present
  end

  it "rejects an association without a target" do
    entity = build(:entity, customer: customer)
    entity.associations_json = [{}]
    expect(entity).not_to be_valid
    expect(entity.errors[:associations]).to be_present
  end

  [nil, false, [], "bad"].each do |config|
    it "rejects malformed computed config #{config.inspect}" do
      entity = build(:entity, customer: customer)
      entity.property_schema_json = [{ "name" => "Count", "name_slug" => "count", "type" => "Computed", "config" => config }]
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to be_present
    end
  end

  it "rejects structured computed bridge ids through validation" do
    entity = build(:entity, customer: customer)
    entity.property_schema_json = [{ "name" => "Count", "name_slug" => "count", "type" => "Computed", "config" => { "function" => "count", "bridge_role" => "source", "bridge_entity_id" => {} } }]
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to be_present
  end

  describe "approved model extensions" do
    let(:feature_module) { create(:feature_module, extendable_models: ["Payments::Order", "String", "NoSuchModel", "ApplicationRecord"].to_json) }

    before { create(:customer_feature_module, customer: customer, feature_module: feature_module) }

    it "accepts an approved concrete ActiveRecord model from an enabled module" do
      expect(build(:entity, customer: customer, extended_model: "Payments::Order")).to be_valid
    end

    %w[String NoSuchModel ApplicationRecord Customer].each do |model|
      it "rejects #{model} even when the constant exists or appears in the registry" do
        entity = build(:entity, customer: customer, extended_model: model)
        expect(entity).not_to be_valid
        expect(entity.errors[:extended_model]).to be_present
      end
    end

    it "rejects approved models when the module is disabled for this tenant" do
      customer.customer_feature_modules.find_by!(feature_module: feature_module).update!(status: :suspended)
      expect(build(:entity, customer: customer, extended_model: "Payments::Order")).not_to be_valid
    end

    it "does not use another tenant's module grants" do
      expect(build(:entity, customer: create(:customer), extended_model: "Payments::Order")).not_to be_valid
    end
  end

  it "blocks shared deletion when an entity in another tenant references it" do
    shared = create(:entity, :shared,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    source = create(:entity, customer: customer)
    source.update!(associations: [{ "target_entity_id" => shared.id.to_s, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    Current.with_customer(create(:customer)) do
      expect(shared.soft_delete).to be(false)
    end
    expect(shared.reload).to be_active
  end

  it "blocks physical shared deletion while even a trashed tenant definition references it" do
    shared = create(:entity, :shared,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    source = create(:entity, customer: customer)
    source.update!(associations: [{ "target_entity_id" => shared.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    source.update_columns(status: :inactive)
    expect(shared.destroy).to be(false)
    expect(Entity.exists?(shared.id)).to be(true)
  end

  it "returns false and rolls back every bridge restoration when one bridge is invalid" do
    source = create(:entity, customer: customer, name: "RestoreSource")
    name_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    targets = [create(:entity, customer: customer, name: "RestoreA", property_schema: name_schema),
               create(:entity, customer: customer, name: "RestoreB", property_schema: name_schema)]
    source.update!(associations: targets.map { |target| { "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" } }.to_json)
    expect(source.sync_bridge_entities!).to be(true)
    bridges = source.reload.associations_list.map { |association| Entity.find(association["bridge_entity_id"]) }
    bridges.each { |bridge| bridge.update_columns(status: :inactive) }
    bridges.last.property_schema_json = [{ "name" => "Invalid" }]
    bridges.last.save!(validate: false)
    source.update_columns(status: :inactive)
    head = source.current_version_id

    expect(source.restore).to be(false)
    expect(source).to be_inactive
    expect(source.errors[:associations]).to be_present
    expect(source.reload.current_version_id).to eq(head)
    expect(Entity.with_deleted.where(id: bridges.map(&:id)).pluck(:status)).to eq(["inactive", "inactive"])
  end

  it "reports a missing bridge as a failed restoration" do
    target = create(:entity, customer: customer,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    source = create(:entity, customer: customer)
    source.update!(associations: [{ "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    source.sync_bridge_entities!
    bridge_id = source.reload.associations_list.first["bridge_entity_id"]
    Entity.find(bridge_id).destroy!
    source.update_columns(status: :inactive)
    expect(source.restore).to be(false)
    expect(source).to be_inactive
    expect(source.errors[:associations]).to be_present
  end
end

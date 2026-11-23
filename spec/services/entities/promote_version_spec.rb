# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::PromoteVersion do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer, name: "PromotionSource") }

  def version_with(snapshot)
    content = EntityDefinitionContent.store!(customer_id: entity.customer_id, payload: snapshot)
    entity.entity_versions.create!(customer_id: entity.customer_id, version_number: entity.entity_versions.maximum(:version_number) + 1, content: content)
  end

  def association_to(target, **extra)
    { "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" }.merge(extra.stringify_keys)
  end

  def named_target(name, **extra)
    create(:entity, { customer: customer, name: name,
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json }.merge(extra))
  end

  [false, true].each do |restore|
    it "validates a malformed historical candidate before #{restore ? 'restoring' : 'setting'} the head" do
      head = entity.current_version_id
      version = version_with(entity.definition_snapshot.merge("property_schema" => [nil]))
      count = entity.entity_versions.count
      result = described_class.call(entity: entity, version: version, restore: restore)

      expect(result.success?).to be(false)
      expect(result.errors).to be_present
      expect(entity.reload.current_version_id).to eq(head)
      expect(entity.entity_versions.count).to eq(count)
    end

    it "rejects a non-object historical snapshot for restore=#{restore}" do
      head = entity.current_version_id
      result = described_class.call(entity: entity, version: version_with([]), restore: restore)
      expect(result.success?).to be(false)
      expect(entity.reload.current_version_id).to eq(head)
    end
  end

  it "reconciles bridges before moving the source head and retires removed bridges" do
    old_target = named_target("OldTarget")
    new_target = named_target("NewTarget")
    entity.update!(associations: [association_to(old_target)].to_json)
    entity.sync_bridge_entities!
    old_bridge_id = entity.reload.associations_list.first["bridge_entity_id"]
    head = entity.current_version_id
    candidate = version_with(entity.definition_snapshot.merge("associations" => [association_to(new_target)]))

    allow(entity).to receive(:sync_bridge_entities!).and_wrap_original do |original, **options|
      expect(Entity.find(entity.id).current_version_id).to eq(head)
      original.call(**options)
    end
    result = described_class.call(entity: entity, version: candidate)

    expect(result).to be_success
    association = entity.reload.associations_list.first
    bridge = Entity.find(association["bridge_entity_id"])
    expect(bridge.property_schema_json.last["entity_id"]).to eq(new_target.id.to_s)
    expect(Entity.with_deleted.find(old_bridge_id)).to be_inactive
    expect(result.version.id).to eq(entity.current_version_id)
    expect(JSON.parse(result.version.payload)["associations"].first["bridge_entity_id"]).to eq(bridge.id)
  end

  it "rolls back created bridges and removed-bridge status if later reconciliation fails" do
    old_target = named_target("Previous")
    target = named_target("Next")
    unavailable = named_target("Unavailable")
    unavailable.update_columns(status: :inactive)
    entity.update!(associations: [association_to(old_target)].to_json)
    entity.sync_bridge_entities!
    bridge_id = entity.reload.associations_list.first["bridge_entity_id"]
    head = entity.current_version_id
    candidate = version_with(entity.definition_snapshot.merge("associations" => [association_to(target), association_to(unavailable)]))
    count = Entity.with_deleted.count
    result = described_class.call(entity: entity, version: candidate, restore: true)

    expect(result.success?).to be(false)
    expect(entity.reload.current_version_id).to eq(head)
    expect(Entity.find(bridge_id)).to be_active
    expect(Entity.with_deleted.count).to eq(count)
    expect(Entity.find_by(name: "assoc_promotion_source_next")).to be_nil
  end

  it "restores computed fields after reconciling the historical retired bridge" do
    target = named_target("ComputedTarget")
    entity.update!(associations: [association_to(target)].to_json)
    entity.sync_bridge_entities!
    bridge_id = entity.reload.associations_list.first["bridge_entity_id"]
    entity.property_schema_json = [{ "name" => "Count", "name_slug" => "count", "type" => "Computed", "config" => { "function" => "count", "bridge_entity_id" => bridge_id, "bridge_role" => "source" } }]
    entity.save!
    candidate = entity.current_version
    entity.update!(associations: "[]", property_schema: "[]")
    entity.sync_bridge_entities!
    expect(Entity.with_deleted.find(bridge_id)).to be_inactive

    result = described_class.call(entity: entity, version: candidate, restore: true)
    expect(result).to be_success
    expect(Entity.find(bridge_id)).to be_active
    expect(entity.computed_fields.first["config"]["bridge_entity_id"]).to eq(bridge_id)
  end

  it "rejects a version belonging to another entity" do
    foreign = create(:entity, customer: customer)
    head = entity.current_version_id
    expect(described_class.call(entity: entity, version: foreign.current_version).success?).to be(false)
    expect(entity.reload.current_version_id).to eq(head)
  end

  it "does not repurpose an unrelated same-tenant bridge named by a historical id" do
    target = named_target("Target")
    unrelated = create(:entity, customer: customer, category: :bridge, name: "UnrelatedBridge")
    original_head = unrelated.current_version_id
    candidate = version_with(entity.definition_snapshot.merge("associations" => [association_to(target, bridge_entity_id: unrelated.id)]))
    result = described_class.call(entity: entity, version: candidate)
    expect(result.success?).to be(false)
    expect(unrelated.reload.current_version_id).to eq(original_head)
    expect(unrelated.name).to eq("UnrelatedBridge")
  end

  it "keeps shared override heads and versions isolated by customer" do
    shared = create(:entity, :shared)
    other = create(:customer)
    versions = {}
    [customer, other].each do |tenant|
      Current.with_customer(tenant) do
        record = Entity.find(shared.id)
        record.update!(description: tenant.id.to_s)
        versions[tenant.id] = record.resolved_current_version
      end
    end
    Current.with_customer(customer) do
      record = Entity.find(shared.id)
      head = record.current_line_head_version_id
      result = described_class.call(entity: record, version: versions[other.id], restore: true)
      expect(result.success?).to be(false)
      expect(record.current_line_head_version_id).to eq(head)
      expect(record.description).to eq(customer.id.to_s)
    end
    expect(EntityCustomerHead.find_by!(entity_id: shared.id, customer_id: other.id).current_version_id).to eq(versions[other.id].id)
  end

  it "validates shared overrides before promoting and preserves the global default" do
    shared = create(:entity, :shared)
    global_head = shared.current_version_id
    Current.with_customer(customer) do
      record = Entity.find(shared.id)
      record.update!(description: "override")
      head = record.resolved_current_version.id
      content = EntityDefinitionContent.store!(customer_id: customer.id, payload: record.definition_snapshot.merge("property_schema" => [{ "name" => "Missing slug" }]))
      version = record.entity_versions.create!(customer_id: customer.id, version_number: 2, content: content)
      expect(described_class.call(entity: record, version: version).success?).to be(false)
      expect(record.current_line_head_version_id).to eq(head)
    end
    expect(shared.reload.current_version_id).to eq(global_head)
  end

  it "routes direct entity head changes through validation" do
    version = version_with(entity.definition_snapshot.merge("attribute_groups" => [nil]))
    head = entity.current_version_id
    expect { entity.set_current_version!(version) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { entity.restore_as_new!(version) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(entity.reload.current_version_id).to eq(head)
  end
end

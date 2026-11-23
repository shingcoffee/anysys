# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::DeleteEntry do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:shared) { create(:entity, :shared, name: "SharedParticipant") }
  let(:entry) { create(:entity_entry, customer: customer, entity: shared) }

  def bridge_for(tenant)
    create(:entity, customer: tenant, category: :bridge, property_schema: [
      { "name" => "Participant", "name_slug" => "participant", "type" => "EntityReference", "entity_id" => shared.id.to_s }
    ].to_json)
  end

  it "nullifies optional logs and deletes JSON junction references only in the entry tenant" do
    log = create(:feature_module_log, customer: customer, entity_entry: entry)
    bridge = bridge_for(customer)
    deleted_bridge = bridge_for(customer)
    deleted_bridge.update_columns(status: :inactive)
    junction = create(:entity_entry, customer: customer, entity: bridge, data: { "participant" => entry.id.to_s }.to_json)
    hidden = create(:entity_entry, customer: customer, entity: deleted_bridge, data: { "participant" => entry.id }.to_json)
    junction_log = create(:feature_module_log, customer: customer, entity_entry: junction)
    survivor = create(:entity_entry, customer: customer, entity: bridge, data: { "participant" => "99999999" }.to_json)
    other_bridge = bridge_for(other)
    foreign = create(:entity_entry, customer: other, entity: other_bridge, data: { "participant" => entry.id.to_s }.to_json)

    result = described_class.call(entry: entry)
    expect(result).to be_success
    expect(EntityEntry.where(id: [entry.id, junction.id, hidden.id])).to be_empty
    expect(log.reload.entity_entry_id).to be_nil
    expect(junction_log.reload.entity_entry_id).to be_nil
    expect(EntityEntry.where(id: [survivor.id, foreign.id]).count).to eq(2)
  end

  it "rolls back junction deletion and log nullification when the entry cannot be deleted" do
    log = create(:feature_module_log, customer: customer, entity_entry: entry)
    junction = create(:entity_entry, customer: customer, entity: bridge_for(customer), data: { "participant" => entry.id }.to_json)
    allow(entry).to receive(:destroy!).and_wrap_original do |original|
      original.call
      raise ActiveRecord::InvalidForeignKey
    end

    result = described_class.call(entry: entry)
    expect(result.success?).to be(false)
    expect(EntityEntry.exists?(entry.id)).to be(true)
    expect(EntityEntry.exists?(junction.id)).to be(true)
    expect(log.reload.entity_entry_id).to eq(entry.id)
  end

  it "also applies cleanup to direct model deletion" do
    log = create(:feature_module_log, customer: customer, entity_entry: entry)
    entry.destroy!
    expect(log.reload.entity_entry_id).to be_nil
  end

  it "cleans tenant rows on a shared bridge using that tenant's resolved definition" do
    bridge = create(:entity, :shared, category: :bridge)
    Current.with_customer(customer) do
      loaded = Entity.find(bridge.id)
      loaded.property_schema_json = [{ "name" => "Participant", "name_slug" => "participant", "type" => "EntityReference", "entity_id" => shared.id.to_s }]
      loaded.save!
    end
    junction = nil
    Current.with_customer(customer) do
      junction = create(:entity_entry, customer: customer, entity: Entity.find(bridge.id), data: { "participant" => "00#{entry.id}" }.to_json)
    end
    foreign = create(:entity_entry, customer: other, entity: bridge)
    Current.with_customer(other) do
      expect(described_class.call(entry: entry)).to be_success
    end
    expect(EntityEntry.exists?(junction.id)).to be(false)
    expect(EntityEntry.exists?(foreign.id)).to be(true)
  end
end

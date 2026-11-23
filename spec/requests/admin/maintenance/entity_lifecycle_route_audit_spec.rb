# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entity version promotion request lifecycle", type: :request do
  include_context "as admin"
  let!(:source) { create(:entity, :with_name_status_schema, customer: customer, name: "Audit source") }
  let!(:target) { create(:entity, :with_name_status_schema, customer: customer, name: "Audit target") }

  def versions_path(entity = source)
    "/#{customer.id}/admin/maintenance/entities/#{entity.id}/versions"
  end

  def association_version
    source.update!(associations: [{
      "target_entity_id" => target.id, "target_entity_name" => target.name,
      "display_field" => "name", "display_field_label" => "Name", "additional_attributes" => []
    }].to_json)
    source.sync_bridge_entities!
    source.reload.current_version
  end

  it "reconciles a historical bridge before making its entity version the default" do
    version = association_version
    bridge_id = source.associations_list.first.fetch("bridge_entity_id")
    source.update!(associations: [].to_json)
    source.sync_bridge_entities!
    expect(Entity.with_deleted.find(bridge_id)).to be_inactive

    put "#{versions_path}/#{version.id}/default", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("success")).to be(true)
    expect(Entity.find(bridge_id)).to be_active
    expect(source.reload.associations_list.first.fetch("bridge_entity_id")).to eq(bridge_id)
  end

  it "restores as a new validated version with historical lineage" do
    version = association_version
    source.update!(description: "A later definition")
    before = source.entity_versions.count

    post versions_path, params: { version_id: version.id }, as: :json

    expect(response).to have_http_status(:ok)
    expect(source.reload.entity_versions.count).to eq(before + 1)
    expect(source.current_version.based_on_version_id).to eq(version.id)
    expect(response.parsed_body.fetch("version_number")).to eq(source.current_version.version_number)
  end

  it "returns a controlled invalid result and preserves the head for a malformed stored snapshot" do
    head_id = source.current_version_id
    content = source.content_class.store!(customer_id: customer.id, payload: source.definition_snapshot.merge("property_schema" => [nil]))
    invalid = source.entity_versions.create!(customer_id: customer.id, version_number: source.entity_versions.maximum(:version_number) + 1, content: content)

    put "#{versions_path}/#{invalid.id}/default", as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("success")).to be(false)
    expect(response.parsed_body.fetch("errors")).to be_present
    expect(source.reload.current_version_id).to eq(head_id)
  end

  it "does not delegate a shared global version mutation from a tenant path" do
    shared = create(:entity, :shared)
    version = shared.current_version
    expect(Entities::PromoteVersion).not_to receive(:call)
    get versions_path(shared), as: :json
    expect(response).to have_http_status(:ok)

    put "#{versions_path(shared)}/#{version.id}/default", as: :json
    expect(response).to have_http_status(:not_found)

    post versions_path(shared), params: { version_id: version.id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(shared.reload.current_version_id).to eq(version.id)
  end

  it "rejects malformed version ID containers before delegation" do
    expect(Entities::PromoteVersion).not_to receive(:call)
    post versions_path, params: { version_id: [source.current_version_id] }, as: :json
    expect(response).to have_http_status(:not_found)
  end
end

RSpec.describe "Entity entry deletion request lifecycle", type: :request do
  include_context "as admin"
  let!(:shared) { create(:entity, :shared, :with_name_status_schema) }
  let!(:entry) { create(:entity_entry, entity: shared, customer: customer, data: { name: "Owned" }.to_json) }
  let!(:second) { create(:entity_entry, entity: shared, customer: customer, data: { name: "Second" }.to_json) }
  let!(:log) { create(:feature_module_log, customer: customer, entity_entry: entry) }

  def batch_path
    "/#{customer.id}/admin/entities/#{shared.id}/entries/batch"
  end

  def bridge_for(tenant)
    target = create(:entity, customer: tenant)
    create(:entity, customer: tenant, category: :bridge, property_schema: [
      { "name" => "Shared participant", "name_slug" => "shared_ref", "type" => "EntityReference", "entity_id" => shared.id.to_s },
      { "name" => "Target participant", "name_slug" => "target_ref", "type" => "EntityReference", "entity_id" => target.id.to_s }
    ].to_json)
  end

  it "nullifies log references and removes only the tenant's referencing bridge entries" do
    bridge = bridge_for(customer)
    linked = create(:entity_entry, entity: bridge, customer: customer, data: { shared_ref: entry.id.to_s }.to_json)
    foreign_customer = create(:customer)
    foreign_entry = create(:entity_entry, entity: shared, customer: foreign_customer)
    foreign_bridge = bridge_for(foreign_customer)
    foreign_linked = create(:entity_entry, entity: foreign_bridge, customer: foreign_customer, data: { shared_ref: foreign_entry.id.to_s }.to_json)

    delete "/#{customer.id}/admin/entities/#{shared.id}/entries/#{entry.id}", as: :json

    expect(response).to have_http_status(:no_content)
    expect(EntityEntry.exists?(entry.id)).to be(false)
    expect(EntityEntry.exists?(linked.id)).to be(false)
    expect(log.reload.entity_entry_id).to be_nil
    expect(EntityEntry.exists?(foreign_entry.id)).to be(true)
    expect(EntityEntry.exists?(foreign_linked.id)).to be(true)
  end

  it "rolls back earlier entry and log changes when a later helper result fails" do
    allow(Entities::DeleteEntry).to receive(:call).and_wrap_original do |method, entry:|
      if entry.id == second.id
        entry.errors.add(:base, :invalid)
        Entities::DeleteEntry::Result.new(ok: false, entry: entry, errors: entry.errors.full_messages)
      else
        method.call(entry: entry)
      end
    end

    delete batch_path, params: { ids: [entry.id, second.id] }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("success")).to be(false)
    expect(EntityEntry.exists?(entry.id)).to be(true)
    expect(EntityEntry.exists?(second.id)).to be(true)
    expect(log.reload.entity_entry_id).to eq(entry.id)
  end

  it "counts unique selected entries and excludes another tenant's entry on the same shared entity" do
    foreign = create(:entity_entry, entity: shared, customer: create(:customer))

    delete batch_path, params: { ids: [entry.id, entry.id, foreign.id] }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("success" => true, "count" => 1)
    expect(EntityEntry.exists?(foreign.id)).to be(true)
  end
end

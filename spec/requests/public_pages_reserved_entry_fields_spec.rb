# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reserved entity fields in public page submissions", type: :request do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "validators" => [{ "type" => "presence" }] },
      { "name" => "Admin secret", "name_slug" => "admin_secret", "visibility" => { "public" => false } },
      { "name" => "Data", "name_slug" => "data", "visibility" => { "public" => true } }
    ].to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, entity: entity, launched: true, configuration: {
        metadata: { entity_id: entity.id, entity_name: entity.name }, fields: []
      }.to_json)
    end
  end

  it "creates through the record writer without a bulk-data visibility bypass" do
    url = "/#{customer.id}/page/#{page.public_uuid}"
    expect do
      post url, params: { entity: { name: "Anonymous", data: '{"admin_secret":"anonymous overwrite"}',
                                   admin_secret: "direct overwrite" } }
    end.to change(EntityEntry, :count).by(1)

    expect(response).to redirect_to(url)
    entry = EntityEntry.where(entity: entity, customer: customer).sole
    expect(entry.data_json["admin_secret"]).to be_nil
    expect(entry.data_json).to include("name" => "Anonymous")
    expect(entry.data_json).not_to have_key("data")
    expect(entry.entity_version_number).to eq(entity.resolved_current_version.version_number)
  end
end

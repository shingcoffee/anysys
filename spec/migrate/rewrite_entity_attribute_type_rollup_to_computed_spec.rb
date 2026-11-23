# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260904160000_rewrite_entity_attribute_type_rollup_to_computed")

RSpec.describe RewriteEntityAttributeTypeRollupToComputed, type: :model do
  it "rewrites stored Rollup attribute types to Computed and sweeps the old content" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, name: "Host")
    payload = JSON.parse(entity.current_version.content.payload)
    payload["property_schema"] = [
      { "name" => "Average Score", "name_slug" => "average_score", "type" => "Rollup",
        "html_type" => "number", "config" => { "function" => "avg" } }
    ]
    old_content = EntityDefinitionContent.store!(customer_id: entity.customer_id, payload: payload)
    entity.current_version.update_columns(content_id: old_content.id)

    described_class.new.up

    entity.current_version.reload
    entity.reload_definition_from_head!
    expect(entity.property_schema_json.first["type"]).to eq("Computed")
    expect(EntityDefinitionContent.find_by(id: old_content.id)).to be_nil
  end
end

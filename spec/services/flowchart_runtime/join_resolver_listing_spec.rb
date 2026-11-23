# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::JoinResolver, ".related list and count" do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  def link_entities(source:, target:, customer:)
    attrs = {
      name: "assoc_#{source.name.parameterize(separator: '_')}_#{target.name.parameterize(separator: '_')}",
      category: :bridge,
      property_schema: [
        { "name" => source.name, "name_slug" => source.name.parameterize(separator: "_"),
          "type" => Entity::ENTITY_REFERENCE_TYPE, "html_type" => "number", "entity_id" => source.id.to_s },
        { "name" => target.name, "name_slug" => target.name.parameterize(separator: "_"),
          "type" => Entity::ENTITY_REFERENCE_TYPE, "html_type" => "number", "entity_id" => target.id.to_s }
      ].to_json
    }
    bridge = create(:entity, attrs.merge(customer: customer))
    source.associations_json = [{ "target_entity_id" => target.id, "bridge_entity_id" => bridge.id }]
    source.save(validate: false)
    [Entity.find(source.id), Entity.find(target.id), Entity.find(bridge.id)]
  end

  it "lists and counts only this customer's related rows" do
    source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
    target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
    source, target, bridge = link_entities(source: source, target: target, customer: customer)
    own_source = create(:entity_entry, :with_data, entity: source, customer: customer, entry_data: { "name" => "Ada" })
    math = create(:entity_entry, :with_data, entity: target, customer: customer, entry_data: { "title" => "Math" })
    physics = create(:entity_entry, :with_data, entity: target, customer: customer, entry_data: { "title" => "Physics" })
    foreign_source = create(:entity_entry, :with_data, entity: source, customer: other, entry_data: { "name" => "Ada" })
    foreign_target = create(:entity_entry, :with_data, entity: target, customer: other, entry_data: { "title" => "Math" })
    slug_source = source.name.parameterize(separator: "_")
    slug_target = target.name.parameterize(separator: "_")
    create(:entity_entry, :with_data, entity: bridge, customer: customer, entry_data: { slug_source => own_source.id.to_s, slug_target => math.id.to_s })
    create(:entity_entry, :with_data, entity: bridge, customer: customer, entry_data: { slug_source => own_source.id.to_s, slug_target => physics.id.to_s })
    create(:entity_entry, :with_data, entity: bridge, customer: other, entry_data: { slug_source => foreign_source.id.to_s, slug_target => foreign_target.id.to_s })

    ctx = { bound_entity: source, customer_id: customer.id }
    listed = described_class.related(ctx, association: target.id, operation: "list", source: own_source, limit: 1, order_by: "title")
    expect(listed.map(&:id)).to eq([math.id])
    expect(described_class.related(ctx, association: target.id, operation: "count", source: own_source)).to eq(2)
  end
end

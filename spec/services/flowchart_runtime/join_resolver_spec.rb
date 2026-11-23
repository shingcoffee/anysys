# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::JoinResolver do
  let_it_be(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, name: "Product", customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:order_entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end
  let(:bridge_entity) do
    create(:entity, name: "assoc_product_order", customer: customer, category: :bridge, property_schema: [
      { "name" => "Product", "name_slug" => "product", "type" => "EntityReference", "html_type" => "number", "entity_id" => product_entity.id.to_s },
      { "name" => "Order", "name_slug" => "order", "type" => "EntityReference", "html_type" => "number", "entity_id" => order_entity.id.to_s }
    ].to_json)
  end

  let!(:product1) { create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Widget" }.to_json) }
  let!(:product2) { create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Gadget" }.to_json) }
  let!(:order1) { create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "50" }.to_json) }
  let!(:bridge1) do
    create(:entity_entry, entity: bridge_entity, customer: customer,
      data: { "product" => product1.id.to_s, "order" => order1.id.to_s }.to_json)
  end

  let(:resolver) do
    described_class.new(
      source_entity: product_entity,
      target_entity: order_entity,
      bridge_entity: bridge_entity,
      customer_id: customer.id
    )
  end

  describe "#apply_sql_join" do
    it "returns scope with SQL JOIN through bridge entity" do
      base_scope = EntityEntry.where(entity_id: product_entity.id, customer_id: customer.id)
      joined_scope = resolver.apply_sql_join(base_scope)
      expect(joined_scope.distinct.count).to eq(1)
      expect(joined_scope.distinct.pluck(:id)).to contain_exactly(product1.id)
    end
  end

  describe "#resolve_related_ids" do
    it "returns target entry IDs related to source entry via bridge" do
      ids = resolver.resolve_related_ids(product1.id)
      expect(ids).to contain_exactly(order1.id.to_s)
    end

    it "returns empty array for unlinked source" do
      ids = resolver.resolve_related_ids(product2.id)
      expect(ids).to be_empty
    end

    it "resolves join keys by entity_id from bridge property_schema_json even when attribute slug differs from entity.name_slug" do
      custom_bridge = create(:entity, name: "assoc_product_order_custom", customer: customer, category: :bridge, property_schema: [
        { "name" => "Item", "name_slug" => "item_ref", "type" => "EntityReference", "html_type" => "number", "entity_id" => product_entity.id.to_s },
        { "name" => "Purchase", "name_slug" => "purchase_ref", "type" => "EntityReference", "html_type" => "number", "entity_id" => order_entity.id.to_s }
      ].to_json)
      create(:entity_entry, entity: custom_bridge, customer: customer,
        data: { "item_ref" => product1.id.to_s, "purchase_ref" => order1.id.to_s }.to_json)

      custom_resolver = described_class.new(
        source_entity: product_entity,
        target_entity: order_entity,
        bridge_entity: custom_bridge,
        customer_id: customer.id
      )
      expect(custom_resolver.resolve_related_ids(product1.id)).to contain_exactly(order1.id.to_s)
    end
  end

  describe ".detect_bridge" do
    it "finds bridge entity from source entity associations" do
      product_entity.associations_json = [
        { "target_entity_id" => order_entity.id, "bridge_entity_id" => bridge_entity.id }
      ]
      product_entity.save(validate: false)

      # Re-fetch to clear JsonSerializable memoization
      reloaded_product = Entity.find(product_entity.id)

      bridge = described_class.detect_bridge(reloaded_product, order_entity)
      expect(bridge).to eq(bridge_entity)
    end

    it "returns nil when no association exists" do
      bridge = described_class.detect_bridge(product_entity, order_entity)
      expect(bridge).to be_nil
    end
  end

  describe ".related" do
    before do
      product_entity.associations_json = [
        { "target_entity_id" => order_entity.id, "bridge_entity_id" => bridge_entity.id }
      ]
      product_entity.save(validate: false)
    end

    let(:ctx) { { bound_entity: Entity.find(product_entity.id), customer_id: customer.id } }

    it "finds the related target for the tenant and creates a new pair in the same customer" do
      found = described_class.related(ctx, association: order_entity.id, operation: "find", source: product1)
      expect(found.id).to eq(order1.id)

      created = described_class.related(
        ctx, association: order_entity.id, operation: "create", source: product2,
        assignments: { "total" => "99" }
      )
      expect(created.customer_id).to eq(customer.id)
      expect(created.total).to eq("99")
      expect(EntityEntry.where(entity_id: bridge_entity.id, customer_id: customer.id).count).to eq(2)
    end

    it "takes the association by entity name" do
      found = described_class.related(ctx, association: "Order", operation: "find", source: product1)

      expect(found.id).to eq(order1.id)
    end

    it "finds the first related row after order_by" do
      later = create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "10" }.to_json)
      create(:entity_entry, entity: bridge_entity, customer: customer,
             data: { "product" => product1.id.to_s, "order" => later.id.to_s }.to_json)

      found = described_class.related(
        ctx, association: "Order", operation: "find", source: product1,
        order_by: "total", order_direction: "asc"
      )
      expect(found.id).to eq(later.id)
    end

    it "starts from the record passed in, even when the page saves another entity" do
      page_ctx = ctx.merge(bound_entity: order_entity)

      found = described_class.related(page_ctx, association: "Order", operation: "find", source: product1.reload)

      expect(found.id).to eq(order1.id)
    end
  end
end


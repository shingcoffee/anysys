# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Composite page integration", type: :model do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Customer Name", "name_slug" => "customer_name", "type" => "String", "html_type" => "text" },
      { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "customer_name" => "Alice", "amount" => "100", "status" => "pending" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "customer_name" => "Bob", "amount" => "250", "status" => "shipped" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "customer_name" => "Carol", "amount" => "75", "status" => "pending" }.to_json)
  end

  describe "CompositePageRenderer" do
    it "renders list module with all records" do
      modules_config = [
        { "id" => "orders_list", "module_type" => "list", "title" => "Orders",
          "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => ["customer_name", "amount", "status"], "pageSize" => 25 } }
      ]
      result = CompositePageRenderer.new(modules_config, customer_id: customer.id).render_modules.first

      expect(result[:records].size).to eq(3)
      expect(result[:columns].map { |c| c[:slug] }).to eq(%w[customer_name amount status])
    end

    it "filters list with conditions" do
      modules_config = [
        { "id" => "pending", "module_type" => "list", "entity_id" => entity.id, "width" => "half",
          "config" => { "columns" => ["customer_name"],
            "conditions" => { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "pending" }] } } }
      ]
      result = CompositePageRenderer.new(modules_config, customer_id: customer.id).render_modules.first

      expect(result[:records].size).to eq(2)
      names = result[:records].map { |r| r.data_json["customer_name"] }
      expect(names).to contain_exactly("Alice", "Carol")
    end

    it "renders multiple modules" do
      modules_config = [
        { "id" => "list_mod", "module_type" => "list", "entity_id" => entity.id, "width" => "half",
          "config" => { "columns" => ["customer_name"] } },
        { "id" => "form_mod", "module_type" => "form", "entity_id" => entity.id, "width" => "half",
          "config" => { "fields" => [] } }
      ]
      result = CompositePageRenderer.new(modules_config, customer_id: customer.id).render_modules

      expect(result.size).to eq(2)
      expect(result[0][:width_class]).to eq("col-span-12 md:col-span-6")
      expect(result[1][:width_class]).to eq("col-span-12 md:col-span-6")
    end
  end

  describe "PageContentGenerator with composite layout" do
    it "generates HTML with list data" do
      page = create(:page, customer: customer, entity: entity, configuration: {
        "layout" => "composite",
        "modules" => [
          { "id" => "mod_1", "module_type" => "list", "title" => "Orders",
            "entity_id" => entity.id, "width" => "full",
            "config" => { "columns" => ["customer_name", "status"], "pageSize" => 10 } }
        ],
        "metadata" => { "entity_id" => entity.id },
        "rules" => [], "calculations" => []
      }.to_json)

      content = PageContentGenerator.new(page).generate

      expect(content).to include("composite-page")
      expect(content).to include("Orders")
      expect(content).to include("Alice")
      expect(content).to include("Bob")
      expect(content).to include("Carol")
      expect(content).to include("list-module")
    end
  end

  describe "visibility configuration" do
    it "preserves visibility settings" do
      modules_config = [
        { "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "half",
          "config" => { "columns" => ["customer_name"] }, "visibility" => nil,
          "events" => { "emit" => ["row:selected"] } },
        { "id" => "mod_2", "module_type" => "form", "entity_id" => entity.id, "width" => "half",
          "config" => {}, "visibility" => { "on_event" => "row:selected" },
          "events" => { "listen" => ["row:selected"] } }
      ]
      result = CompositePageRenderer.new(modules_config, customer_id: customer.id).render_modules

      expect(result[0][:visibility]).to be_nil
      expect(result[1][:visibility]).to eq({ "on_event" => "row:selected" })
    end
  end
end

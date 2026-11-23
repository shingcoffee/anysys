# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::ChildRecordsGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  let(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, customer: customer, name: "Product", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
    ].to_json)
  end
  let(:order_entity) do
    create(:entity, customer: customer, name: "Order", property_schema: [
      { "name" => "Number", "name_slug" => "number", "html_type" => "text" }
    ].to_json)
  end
  let(:line_entity) do
    create(:entity, customer: customer, name: "Order line", property_schema: [
      { "name" => "Order", "name_slug" => "order", "html_type" => "select", "type" => "EntityReference",
        "entity_id" => order_entity.id.to_s },
      { "name" => "Product", "name_slug" => "product", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => product_entity.id.to_s, "label_field" => "name" } },
      { "name" => "Quantity", "name_slug" => "quantity", "html_type" => "number" }
    ].to_json)
  end
  let(:order) { EntityEntry.build_for(order_entity).create!(customer: customer, entity: order_entity, data: { number: "1" }.to_json) }
  let(:chair) { EntityEntry.build_for(product_entity).create!(customer: customer, entity: product_entity, data: { name: "Chair" }.to_json) }

  def line(order_id, quantity, product: chair)
    EntityEntry.build_for(line_entity).create!(customer: customer, entity: line_entity,
                                               data: { order: order_id, product: product.id.to_s, quantity: quantity }.to_json)
  end

  def config(overrides = {})
    { "entity" => "Order line", "field" => "order", "modelVariable" => "model", "operation" => "list", "resultVar" => "lines" }.merge(overrides)
  end

  def errors(cfg, bound_entity: order_entity)
    Current.set(customer: customer) do
      described_class.new({ "config" => cfg }, { bound_entity: bound_entity }).validate_config(cfg).map(&:code)
    end
  end

  def execute(cfg, model: order)
    ctx = { customer_id: customer.id, bound_entity: order_entity, model: model, errors: [] }
    [CodeGenerators::TestRunner.execute(described_class, config: cfg, ctx: ctx)[:outcome], ctx]
  end

  before { line_entity }

  it "accepts sample_input and compiles" do
    expect(described_class.new({ "config" => described_class.sample_input }, {}).validate_config(described_class.sample_input)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generated_step}\nend") }.not_to raise_error
  end

  describe "configuration checks" do
    it "accepts the child entity by name, with or without the reference named" do
      expect(errors(config)).to eq([])
      expect(errors(config("field" => ""))).to eq([])
      expect(errors(config("entity" => line_entity.id.to_s))).to eq([])
    end

    it "names an entity the tenant does not have" do
      expect(errors(config("entity" => "Invoice line"))).to include(:unknown_entity)
    end

    it "requires the field to be a reference that points at the page's record" do
      expect(errors(config("field" => "quantity"))).to include(:not_a_reference)
      expect(errors(config("field" => "product"))).to include(:not_pointing_at)
      expect(errors(config("field" => "bad slug"))).to include(:invalid_identifier)
    end

    it "leaves the target of a record other than the page's to the run" do
      expect(errors(config("field" => "product", "modelVariable" => "item"))).to eq([])
    end

    it "checks assignment keys and the sort column against the child entity" do
      create = config("operation" => "create")
      expect(errors(create.merge("assignments" => [{ "key" => "quantity", "value" => "2" }]))).to eq([])
      expect(errors(create.merge("assignments" => [{ "key" => "number", "value" => "2" }]))).to include(:unknown_attribute)
      expect(errors(config("orderBy" => "quantity; DROP"))).to include(:unsafe_column)
    end
  end

  it "lists the records pointing at the record, whether the id is stored as text or a number" do
    first = line(order.id.to_s, 2)
    second = line(order.id, 3)
    line((order.id + 1000).to_s, 9)

    outcome, ctx = execute(config("orderBy" => "quantity", "orderDirection" => "desc"))

    expect(outcome).to be(true)
    expect(ctx[:lines].map(&:id)).to eq([second.id, first.id])
    expect(ctx[:lines].first.quantity.to_i).to eq(3)
  end

  it "keeps the order they were added in, newest first when told, without a sort column" do
    first = line(order.id.to_s, 2)
    latest = line(order.id.to_s, 1)

    _, ctx = execute(config)
    expect(ctx[:lines].map(&:id)).to eq([first.id, latest.id])

    _, ctx = execute(config("operation" => "find", "orderDirection" => "desc", "resultVar" => "line"))
    expect(ctx[:line].id).to eq(latest.id)
  end

  it "finds one by its conditions, counts them, and fails a find when told to" do
    line(order.id.to_s, 2)
    big = line(order.id.to_s, 5)
    conditions = { "type" => "group", "joins" => [], "conditions" => [{ "kind" => "field", "leftOperand" => "quantity", "operator" => ">", "rightOperand" => 4 }] }

    _, ctx = execute(config("operation" => "find", "conditions" => conditions, "resultVar" => "line"))
    expect(ctx[:line].id).to eq(big.id)

    _, ctx = execute(config("operation" => "count", "resultVar" => "count", "field" => ""))
    expect(ctx[:count]).to eq(2)

    outcome, ctx = execute(config, model: nil)
    expect([outcome, ctx[:errors]]).to eq([false, [I18n.t("flowchart_runtime.errors.child_records.failed", reason: "Error")]])
    expect(ctx[:error_details].last["diagnostic"]).to eq("record is required")

    empty = EntityEntry.build_for(order_entity).create!(customer: customer, entity: order_entity, data: { number: "2" }.to_json)
    outcome, ctx = execute(config("operation" => "find", "onNotFound" => "fail"), model: empty)
    expect([outcome, ctx[:errors]]).to eq([false, [I18n.t("flowchart_runtime.errors.child_records.not_found")]])
  end

  it "takes the id a reference field holds as the record, when the field names its entity" do
    mine = line(order.id.to_s, 2)
    line((order.id + 1000).to_s, 9)
    item = { customer_id: customer.id, bound_entity: order_entity, item: order.id.to_s, errors: [] }

    outcome = CodeGenerators::TestRunner.execute(described_class, config: config("modelVariable" => "item"), ctx: item)[:outcome]
    expect([outcome, item[:lines].map(&:id)]).to eq([true, [mine.id]])

    blank_field = { customer_id: customer.id, bound_entity: order_entity, item: order.id, errors: [] }
    outcome = CodeGenerators::TestRunner.execute(described_class, config: config("modelVariable" => "item", "field" => ""),
                                                                  ctx: blank_field)[:outcome]
    expect([outcome, blank_field[:error_details].last["diagnostic"]]).to eq([false, "record is required"])

    foreign = create(:customer)
    foreign_order = EntityEntry.build_for(order_entity).create!(customer: foreign, entity: order_entity, data: { number: "9" }.to_json)
    elsewhere = { customer_id: customer.id, bound_entity: order_entity, item: foreign_order.id.to_s, errors: [] }
    outcome = CodeGenerators::TestRunner.execute(described_class, config: config("modelVariable" => "item"), ctx: elsewhere)[:outcome]
    expect(outcome).to be(false)
  end

  it "creates a record pointing at the record, which the assignments cannot redirect, and has the record's totals read again" do
    other = EntityEntry.build_for(order_entity).create!(customer: customer, entity: order_entity, data: { number: "2" }.to_json)
    assignments = [{ "key" => "product", "value" => "ctx[:product].id" }, { "key" => "quantity", "value" => "4" },
                   { "key" => "order", "value" => other.id.to_s }]
    ctx = { customer_id: customer.id, bound_entity: order_entity, model: order, product: chair, errors: [] }
    allow(order).to receive(:reset_derived_values!).and_call_original

    outcome = CodeGenerators::TestRunner.execute(described_class, config: config("operation" => "create", "assignments" => assignments,
                                                                                  "resultVar" => "line"), ctx: ctx)[:outcome]

    expect(outcome).to be(true)
    expect(ctx[:line].reload.data_json.slice("order", "product")).to eq("order" => order.id.to_s, "product" => chair.id.to_s)
    expect(ctx[:line].quantity.to_i).to eq(4)
    expect(order).to have_received(:reset_derived_values!)
  end

  it "never reads another tenant's records or entities" do
    foreign = create(:customer)
    foreign_lines = create(:entity, customer: foreign, name: "Order line",
                                    property_schema: [{ "name" => "Order", "name_slug" => "order", "html_type" => "text" }].to_json)
    EntityEntry.build_for(foreign_lines).create!(customer: foreign, entity: foreign_lines, data: { order: order.id.to_s }.to_json)
    mine = line(order.id.to_s, 1)

    _, ctx = execute(config)

    expect(ctx[:lines].map(&:id)).to eq([mine.id])
  end
end

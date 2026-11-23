# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::ReferencedRecordGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  let(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, customer: customer, name: "Product", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "html_type" => "text" }
    ].to_json)
  end
  let(:line_entity) do
    create(:entity, customer: customer, name: "Line", property_schema: [
      { "name" => "Product", "name_slug" => "product", "html_type" => "select", "type" => "EntityReference",
        "entity_id" => product_entity.id.to_s },
      { "name" => "Note", "name_slug" => "note", "html_type" => "text" }
    ].to_json)
  end
  let(:chair) { create(:entity_entry, customer: customer, entity: product_entity, data: { name: "Chair", status: "listed" }.to_json) }

  def line_with(product_id)
    EntityEntry.build_for(line_entity).create!(customer: customer, entity: line_entity, data: { product: product_id.to_s }.to_json)
  end

  def errors(config, bound_entity: line_entity)
    described_class.new({ "config" => config }, { bound_entity: bound_entity }).validate_config(config).map(&:code)
  end

  def execute(config, line)
    ctx = { customer_id: customer.id, bound_entity: line_entity, model: line, errors: [] }
    [CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)[:outcome], ctx]
  end

  it "accepts sample_input and compiles" do
    expect(errors(described_class.sample_input, bound_entity: nil)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generated_step}\nend") }.not_to raise_error
  end

  it "checks the field is a reference of the page's entity and the update keys belong to the referenced one" do
    expect(errors(described_class.sample_input.merge("field" => "note"))).to include(:not_a_reference)
    expect(errors(described_class.sample_input.merge("field" => "bad slug"))).to include(:invalid_identifier)
    update = described_class.sample_input.merge("operation" => "update")
    expect(errors(update.merge("assignments" => [{ "key" => "status", "value" => '"sold"' }]))).to eq([])
    expect(errors(update.merge("assignments" => [{ "key" => "note", "value" => '"x"' }]))).to include(:unknown_attribute)
  end

  it "leaves a reference on a record other than the page's to be checked when the step runs" do
    expect(errors(described_class.sample_input.merge("field" => "note", "modelVariable" => "line"))).to eq([])
  end

  it "follows a reference stored as a choice list of another entity's records" do
    order = create(:entity, customer: customer, name: "Order", property_schema: [
      { "name" => "Product", "name_slug" => "product", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => product_entity.id.to_s, "label_field" => "name" } }
    ].to_json)
    row = EntityEntry.build_for(order).create!(customer: customer, entity: order, data: { product: chair.id.to_s }.to_json)
    ctx = { customer_id: customer.id, bound_entity: order, model: row, errors: [] }

    expect(errors(described_class.sample_input, bound_entity: order)).to eq([])
    expect(CodeGenerators::TestRunner.execute(described_class, config: described_class.sample_input, ctx: ctx)[:outcome]).to be(true)
    expect(ctx[:referenced_record].id).to eq(chair.id)
  end

  it "loads the record the field points at" do
    outcome, ctx = execute(described_class.sample_input.merge("resultVar" => "product"), line_with(chair.id))

    expect(outcome).to be(true)
    expect([ctx[:product].id, ctx[:product].name]).to eq([chair.id, "Chair"])
  end

  it "updates and saves the referenced record" do
    config = described_class.sample_input.merge("operation" => "update", "assignments" => [{ "key" => "status", "value" => '"sold"' }])

    outcome, = execute(config, line_with(chair.id))

    expect(outcome).to be(true)
    expect(chair.reload.data_json["status"]).to eq("sold")
  end

  it "fails when nothing is referenced, or returns nil when told to" do
    outcome, ctx = execute(described_class.sample_input, line_with(""))
    expect([outcome, ctx[:errors]]).to eq([false, [I18n.t("flowchart_runtime.errors.referenced_record.not_found")]])

    outcome, ctx = execute(described_class.sample_input.merge("onNotFound" => "nil", "operation" => "update"), line_with(""))
    expect([outcome, ctx[:referenced_record], ctx[:errors]]).to eq([true, nil, []])
  end

  it "never loads another tenant's record" do
    foreign = create(:entity_entry, customer: create(:customer), entity: product_entity, data: { name: "Desk" }.to_json)

    outcome, ctx = execute(described_class.sample_input, line_with(foreign.id))

    expect([outcome, ctx[:referenced_record]]).to eq([false, nil])
  end
end

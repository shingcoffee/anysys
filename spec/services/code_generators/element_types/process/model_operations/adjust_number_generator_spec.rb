# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::AdjustNumberGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  let(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, customer: customer, name: "Product", property_schema: [
      { "name" => "Stock", "name_slug" => "stock", "html_type" => "number" },
      { "name" => "Weight", "name_slug" => "weight", "html_type" => "number" }
    ].to_json)
  end
  let(:product) { EntityEntry.build_for(product_entity).create!(customer: customer, entity: product_entity, data: { stock: 5 }.to_json) }
  let(:config) { described_class.sample_input.except("message").merge("amount" => "ctx[:quantity]") }

  def stock = product.class.find(product.id).data_json["stock"]

  def execute(config, quantity:, record: product)
    ctx = { customer_id: customer.id, product: record, quantity: quantity, errors: [] }
    [CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)[:outcome], ctx]
  end

  it "accepts sample_input and compiles" do
    expect(described_class.new({ "config" => described_class.sample_input }, {}).validate_config(described_class.sample_input)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generated_step}\nend") }.not_to raise_error
  end

  it "rejects a field that is not an identifier" do
    codes = described_class.new({ "config" => {} }, {}).validate_config(config.merge("field" => "stock level", "errorField" => "1x")).map(&:code)

    expect(codes.count(:invalid_identifier)).to eq(2)
  end

  it "takes the amount from the stored number, saves it and keeps the new value" do
    outcome, ctx = execute(config, quantity: 2)

    expect([outcome, ctx[:adjusted_value], stock]).to eq([true, 3, 3])
  end

  it "refuses a change past the minimum on the form field, saying how much is left" do
    outcome, ctx = execute(config, quantity: 6)

    expect([outcome, stock]).to eq([false, 5])
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.adjust_number.below_minimum", available: 5)])
    expect(ctx[:error_details].last).to include("code" => "adjust_number.below_minimum", "field" => "quantity")
  end

  it "uses the step's own message and refuses past the maximum" do
    outcome, ctx = execute(described_class.sample_input.merge("direction" => "add", "amount" => "ctx[:quantity]", "maximum" => "8", "minimum" => ""), quantity: 4)

    expect(outcome).to be(false)
    expect(ctx[:errors]).to eq(["Only 3 left in stock."])
  end

  it "reads the stored value afresh, so a stale copy cannot oversell" do
    stale = product.class.find(product.id)
    execute(config, quantity: 4)

    outcome, = execute(config, quantity: 4, record: stale)

    expect([outcome, stock]).to eq([false, 1])
  end

  it "fails busy when the row lock cannot be acquired" do
    allow(FlowchartRuntime::Lock).to receive(:acquire).and_return(false)
    stub_const("FlowchartRuntime::Entries::ADJUST_LOCK_WAIT", 0)

    outcome, ctx = execute(config, quantity: 1)

    expect([outcome, stock]).to eq([false, 5])
    expect(ctx[:error_details].last["code"]).to eq("adjust_number.busy")
  end

  it "fails the step for a field it cannot write or an amount that is not a number" do
    outcome, ctx = execute(config.merge("field" => "price"), quantity: 1)
    expect([outcome, ctx[:error_details].last["code"]]).to eq([false, "adjust_number.failed"])

    outcome, ctx = execute(config.merge("amount" => '"lots"'), quantity: 1)
    expect([outcome, ctx[:error_details].last["code"]]).to eq([false, "adjust_number.failed"])
  end

  it "adds decimals without float noise" do
    weighed = EntityEntry.build_for(product_entity).create!(customer: customer, entity: product_entity, data: { weight: "0.1" }.to_json)

    outcome, ctx = execute(config.merge("field" => "weight", "direction" => "add", "amount" => "0.2", "minimum" => ""), quantity: 0, record: weighed)

    expect([outcome, ctx[:adjusted_value]]).to eq([true, 0.3])
  end
end

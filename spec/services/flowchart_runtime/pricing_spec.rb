# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Pricing do
  let(:ctx) { { errors: [] } }

  def calculate(**overrides)
    described_class.calculate(
      ctx,
      lines: [{ "quantity" => 1, "unit_price" => "100" }],
      quantity_field: "quantity",
      unit_price_field: "unit_price",
      **overrides
    )
  end

  it "adds exclusive tax and taxable shipping" do
    result = calculate(tax_mode: "exclusive", tax_rate: 10, shipping_amount: 10, shipping_taxable: true)
    expect(result["subtotal"]).to eq("100.00")
    expect(result["tax"]).to eq("11.00")
    expect(result["shipping"]).to eq("10.00")
    expect(result["total"]).to eq("121.00")
    expect { JSON.generate(result) }.not_to raise_error
  end

  it "prices order lines loaded as records" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Quantity", "name_slug" => "quantity", "data_type" => "integer" },
      { "name" => "Unit price", "name_slug" => "unit_price", "data_type" => "string" }
    ].to_json)
    [[2, "15.50"], [1, "9"]].each do |quantity, price|
      create(:entity_entry, :with_data, entity: entity, customer: customer,
                                        entry_data: { "quantity" => quantity, "unit_price" => price })
    end

    result = calculate(lines: EntityEntry.build_for(entity).where(customer_id: customer.id).order(:id))
    expect(result["subtotal"]).to eq("40.00")
  end

  it "overrides a fixed shipping amount from a runtime value" do
    result = calculate(shipping_amount: 99, shipping_override: "8.50")
    expect(result["shipping"]).to eq("8.50")
    expect(result["total"]).to eq("108.50")
  end

  it "extracts inclusive tax from the entered price" do
    result = calculate(lines: [{ "quantity" => 1, "unit_price" => "110" }], tax_mode: "inclusive", tax_rate: 10)
    expect(result["lines"].first["net"]).to eq("100.00")
    expect(result["lines"].first["tax"]).to eq("10.00")
    expect(result["lines"].first["total"]).to eq("110.00")
    expect(result["total"]).to eq("110.00")
  end

  it "allocates an order-level amount discount pro rata without going below zero" do
    result = calculate(
      lines: [
        { "quantity" => 1, "unit_price" => "60" },
        { "quantity" => 1, "unit_price" => "40" }
      ],
      discount_type: "amount",
      discount_value: 10
    )
    expect(result["lines"].map { |row| row["discount"] }).to eq(%w[6.00 4.00])
    expect(result["discount"]).to eq("10.00")
    expect(result["subtotal"]).to eq("90.00")
  end

  it "caps an oversized order discount at the merchandise net" do
    result = calculate(
      lines: [
        { "quantity" => 1, "unit_price" => "30" },
        { "quantity" => 1, "unit_price" => "20" }
      ],
      discount_type: "amount",
      discount_value: 80
    )
    expect(result["lines"].map { |row| row["total"] }).to eq(%w[0.00 0.00])
    expect(result["discount"]).to eq("50.00")
    expect(result["total"]).to eq("0.00")
  end

  it "fails on a negative quantity" do
    expect(calculate(lines: [{ "quantity" => -1, "unit_price" => "10" }])).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("calculate_pricing.invalid_line")
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.calculate_pricing.invalid_line", line: 1))
  end
end

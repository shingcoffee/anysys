# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Allocation do
  let(:ctx) { { errors: [] } }

  it "splits 100 into 3 with largest remainder as 33.34/33.33/33.33" do
    result = described_class.split(ctx, amount: 100, method: "even", parts: 3, precision: 2,
                                   remainder_strategy: "largest_remainder")
    expect(result).to eq(%w[33.34 33.33 33.33])
    expect(result.map { |row| BigDecimal(row) }.sum).to eq(BigDecimal("100.00"))
    expect { JSON.generate(result) }.not_to raise_error
  end

  it "applies each remainder strategy to an uneven ratio" do
    weights = [2, 3, 1]
    strategies = described_class::REMAINDER_STRATEGIES.index_with do |strategy|
      described_class.split(ctx, amount: 10, method: "ratio", weights: weights, precision: 0,
                           remainder_strategy: strategy)
    end
    expect(strategies["first"]).to eq(%w[4 5 1])
    expect(strategies["last"]).to eq(%w[3 5 2])
    expect(strategies["largest_share"]).to eq(%w[3 6 1])
    expect(strategies["largest_remainder"]).to eq(%w[3 5 2])
    expect(strategies.values.uniq.size).to eq(3)
  end

  it "accepts hash weights and percent weights that sum to 100" do
    ratio = described_class.split(ctx, amount: 100, method: "ratio",
                                  weights: [{ "weight" => 1 }, { "weight" => 3 }], precision: 2)
    expect(ratio).to eq(%w[25.00 75.00])

    percent = described_class.split(ctx, amount: 50, method: "percent", weights: [40, 60], precision: 2)
    expect(percent).to eq(%w[20.00 30.00])
  end

  it "fails when percent weights do not sum to 100" do
    expect(described_class.split(ctx, amount: 100, method: "percent", weights: [40, 50], precision: 2)).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("allocate_amount.percent_total")
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.allocate_amount.percent_total", total: "90.00"))
  end

  it "reads ratio weights from a field on hashes or records" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Share", "name_slug" => "share", "data_type" => "integer" }
    ].to_json)
    records = [1, 3].map do |share|
      entry = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "share" => share })
      EntityEntry.build_for(entity).find(entry.id)
    end

    expect(described_class.split(ctx, amount: 100, method: "ratio", weights: records, weight_field: "share"))
      .to eq(%w[25.00 75.00])
    expect(described_class.split(ctx, amount: 10, method: "ratio", weights: [{ "ratio" => 1 }, { "ratio" => 1 }]))
      .to eq(%w[5.00 5.00])
  end

  it "fails on empty or negative weights" do
    expect(described_class.split(ctx, amount: 100, method: "ratio", weights: [], precision: 2)).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("allocate_amount.invalid_weights")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityTracer, "subflow input variables" do
  let_it_be(:customer) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:child) do
    create(:flowchart, :launched_status, name: "Echo Order", customer: customer, configuration: {
      "elements" => [
        { "id" => "start", "type" => "start", "properties" => {} },
        { "id" => "end", "type" => "end",
          "properties" => { "responseType" => "value", "returnValue" => "ctx.order" } }
      ], "connections" => [{ "from" => "start", "to" => "end" }], "metadata" => {}
    }.to_json)
  end

  def parent_with(subflow_properties)
    create(:flowchart, :draft, customer: customer, configuration: {
      "elements" => [
        { "id" => "start", "type" => "start", "properties" => {} },
        { "id" => "child", "type" => "subflow", "label" => "Echo order",
          "properties" => { "flowchartId" => child.id, **subflow_properties } },
        { "id" => "end", "type" => "end", "properties" => {} }
      ], "connections" => [{ "from" => "start", "to" => "child" }, { "from" => "child", "to" => "end" }],
      "metadata" => {}
    }.to_json)
  end

  def run(record, trace:)
    Current.set(customer: customer, user: owner) do
      described_class.new(record).call(customer_id: customer.id, model: "order-42", trace: trace)
    end
  end

  let(:mapped) { parent_with("inputVariables" => [{ "key" => "order", "value" => "ctx[:model]" }]) }

  it "declares each input variable as a Trailblazer Inject on the Subprocess" do
    expect(mapped.activity).to include(
      "step Subprocess(EchoOrderActivity), id: :echo_order,\n" \
      "    Inject(:order, override: true) => ->(ctx, **) { ctx[:model] }"
    )
  end

  [false, true].each do |trace|
    it "hands the child its named inputs and keeps them out of the parent (trace: #{trace})" do
      result = run(mapped, trace: trace)

      expect(result).to be_success
      expect(result.ctx[:response]).to eq("order-42")
      expect(result.ctx.to_h).not_to have_key(:order)
    end
  end

  it "shares the run's variables unchanged when no inputs are named" do
    result = run(parent_with({}), trace: false)

    expect(result).to be_success
    expect(result.ctx[:response]).to be_nil
  end

  it "rejects an input that would shadow a seeded run variable" do
    expect { parent_with("inputVariables" => [{ "key" => "params", "value" => "ctx[:model]" }]) }
      .to raise_error(ActivityGenerator::Error, /inputVariables cannot be params/)
  end
end

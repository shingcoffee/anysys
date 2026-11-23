# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ServiceInvocation::InvokeServiceGenerator do
  let(:field_type) { Struct.new(:name, :type, keyword_init: true) }

  def execute(config, ctx = {})
    result = CodeGenerators::TestRunner.execute(
      described_class,
      config: { "serviceClass" => "FeatureModules::InputCaster", "resultVar" => "service_result" }.merge(config),
      ctx: ctx
    )
    expect(result[:validation_errors]).to be_empty
    result
  end

  [false, nil, 0, ""].each do |value|
    it "preserves a keyword #{value.inspect} literal rather than omitting or looking it up in ctx" do
      received = nil
      allow(FlowchartRuntime::Invocable).to receive(:call!) do |_klass, **kwargs|
        received = kwargs
        {}
      end
      execute("kwargs" => [{ "key" => "input", "value" => value }, { "key" => "fields", "value" => [] }])
      expect(received[:input]).to eq(value)
    end
  end

  it "evaluates a dot-context argument using the same convention as communication generators" do
    result = execute(
      { "kwargs" => [{ "key" => "input", "value" => "ctx.payload" }, { "key" => "fields", "value" => "fields" }] },
      { payload: { "qty" => "3" }, fields: [field_type.new(name: "qty", type: "integer")] }
    )
    expect(result[:ctx][:service_result]).to eq("qty" => 3)
  end

  it "keeps false service return values as data while completing the invocation" do
    allow(FlowchartRuntime::Invocable).to receive(:call!).and_return(false)
    result = execute("kwargs" => [{ "key" => "input", "value" => {} }, { "key" => "fields", "value" => [] }])
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:service_result]).to be(false)
  end

  it "keeps nil service return values as data while completing the invocation" do
    allow(FlowchartRuntime::Invocable).to receive(:call!).and_return(nil)
    result = execute("kwargs" => [{ "key" => "input", "value" => {} }, { "key" => "fields", "value" => [] }])
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:service_result]).to be_nil
  end

  it "propagates a missing-keyword service error as invoke_service.failed" do
    ctx = { errors: [] }
    result = execute({ "kwargs" => [] }, ctx)
    expect(result[:outcome]).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.invoke_service.failed", reason: "Error"))
  end

  it "passes constructor/call keyword arguments through the real service" do
    ctx = { session: {}, customer: Customer.new, payment: Payments::Payment.new(status: "pending") }
    result = CodeGenerators::TestRunner.execute(
      described_class,
      config: {
        "serviceClass" => "Payments::HandoffCompletion",
        "resultVar" => "service_result",
        "kwargs" => [
          { "key" => "session", "value" => "session" },
          { "key" => "customer", "value" => "customer" },
          { "key" => "payment", "value" => "payment" }
        ]
      },
      ctx: ctx
    )
    expect(result[:validation_errors]).to be_empty
    expect(result).to include(outcome: true)
    expect(ctx[:service_result]).to be_nil
  end
end

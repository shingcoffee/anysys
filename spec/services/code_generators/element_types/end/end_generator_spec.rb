# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::End::EndGenerator do
  let(:element) { { "label" => "End", "properties" => { "responseType" => "none" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"
  it_behaves_like "covers all configured branches", action_name: "end",
                  base_element: { "label" => "End", "properties" => { "returnValue" => "ctx.result" } }

  def generator(properties)
    described_class.new({ "label" => "End", "properties" => properties }, context)
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        true
      end
    RUBY
  end

  it "generates a value response step" do
    expect(generated_step({ "responseType" => "value", "returnValue" => "ctx.result" })).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:response] = ctx[:result]
        true
      end
    RUBY
  end

  it "declares responseType and returnValue" do
    names = described_class._config_schema.fields.map(&:name)
    expect(names).to eq(%w[responseType returnValue])
  end

  it "writes a converted ctx path onto ctx[:response] and succeeds" do
    result = CodeGenerators::TestRunner.execute(
      described_class,
      config: { "responseType" => "value", "returnValue" => "ctx.result" },
      ctx: { result: "done" }
    )
    expect(result[:outcome]).to eq(true)
    expect(result[:ctx][:response]).to eq("done")
  end

  it "emits none and value variants as compilable methods" do
    [
      { "responseType" => "none" },
      { "responseType" => "value", "returnValue" => "ctx.result" }
    ].each do |properties|
      code = generator(properties).generate_step_method
      expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
    end
  end

  it "writes a converted ctx path onto ctx[:response] for value responses" do
    body = generator("responseType" => "value", "returnValue" => "ctx.result").generate_body
    expect(body).to include("ctx[:response] = ctx[:result]")
    expect(body).not_to include("http_status")
  end

  it "emits a non-path return value as the Ruby expression it is" do
    {
      "ctx[:total] * 2" => "ctx[:response] = (ctx[:total] * 2)",
      '"approved"' => 'ctx[:response] = "approved"',
      "ctx.order.total" => "ctx[:response] = FlowchartRuntime::Step.dig(ctx[:order], :total)"
    }.each do |source, expected|
      body = generator("responseType" => "value", "returnValue" => source).generate_body
      expect(body).to include(expected), source
    end
  end

  it "requires a return expression for value responses, field-addressed" do
    errors = generator({}).validate_config("responseType" => "value")
    expect(errors).to include(have_attributes(field: "returnValue", code: :required))
    expect(errors.map(&:message)).to include(I18n.t("flowchart_elements.shared.errors.required", field: "returnValue"))
  end

  it "rejects http_response as not in the enum" do
    errors = generator({}).validate_config("responseType" => "http_response")
    expect(errors).to include(have_attributes(field: "responseType", code: :not_in_list))
  end

  it "reports leftover HTTP keys as unknown fields" do
    errors = generator({}).validate_config("responseType" => "none", "httpStatus" => 200, "responseBody" => "x")
    expect(errors.map(&:field)).to include("httpStatus", "responseBody")
    expect(errors).to all(have_attributes(code: :unknown_field))
  end
end

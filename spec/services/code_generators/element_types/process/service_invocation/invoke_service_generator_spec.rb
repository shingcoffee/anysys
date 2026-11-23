# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ServiceInvocation::InvokeServiceGenerator do
  let(:element) { { "config" => described_class.sample_input } }
  let(:context) { {} }
  let(:base) do
    {
      "serviceClass" => "FeatureModules::InputCaster",
      "resultVar" => "service_result",
      "kwargs" => [
        { "key" => "input", "value" => "payload" },
        { "key" => "fields", "value" => "fields" }
      ]
    }
  end

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def errors(config)
    generate(config).validate_config(config)
  end

  def error_messages(config)
    errors(config).map(&:message)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "has only required errors on schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(generate(sample).generate_step_method) }.not_to raise_error
    lint!(sample)
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"invoke_service.failed",
          FlowchartRuntime::Invocable::Error
        ) do
          service = FlowchartRuntime::Invocable.service!("FeatureModules::InputCaster")
          result = FlowchartRuntime::Invocable.call!(service)
          next FlowchartRuntime::Invocable.fail_result(ctx, result) if FlowchartRuntime::Invocable.failed?(result)
          ctx[:service_result] = result
          true
        end
      end
    RUBY
  end

  it "emits keyword arguments on call!" do
    expect(body(base)).to include("call!(service, input: ctx[:payload], fields: ctx[:fields])")
    expect(body(base)).to include("FlowchartRuntime::Invocable.fail_result")
    lint!(base)
  end

  it "appends ctx: ctx when passContext is set" do
    expect(body(base.merge("passContext" => true))).to include("ctx: ctx")
    expect(body(base.merge("passContext" => true))).not_to eq(body(base.merge("passContext" => false)))
  end

  describe "validation" do
    it "requires serviceClass" do
      expect(error_messages({})).to include(a_string_matching(/serviceClass is required/))
    end

    it "validates class name format" do
      expect(error_messages("serviceClass" => "lowercase_service"))
        .to include("serviceClass must be a valid Ruby class name")
    end

    it "rejects non-allowlisted services" do
      expect(error_messages("serviceClass" => "Kernel")).to include(a_string_matching(/not allowlisted/))
    end

    it "rejects an allowlisted ActiveRecord class" do
      expect(error_messages("serviceClass" => "Emails::Credential")).to include(a_string_matching(/ActiveRecord/))
    end

    it "rejects a class that does not define self.call" do
      expect(error_messages("serviceClass" => "Emails::Gateway")).to include(a_string_matching(/self\.call/))
    end

    it "allows FeatureModules::InputCaster.call" do
      expect(errors(base)).to be_empty
    end

    it "rejects keyword-argument names that are not valid Ruby identifiers" do
      expect(error_messages(base.merge("kwargs" => [{ "key" => "bad key", "value" => "x" }])))
        .to include(a_string_matching(/keyword argument name/))
    end
  end

  describe "argument expressions" do
    it "honors keyword args" do
      expect(body(base.merge("kwargs" => [{ "key" => "input", "value" => "fmt" }])))
        .not_to eq(body(base.merge("kwargs" => [])))
    end

    it "emits a ctx lookup for an explicit ctx[:ref] value" do
      expect(body(base.merge("kwargs" => [{ "key" => "input", "value" => "ctx[:order]" }])))
        .to include("input: ctx[:order]")
    end

    it "emits a quoted literal for a value that is not a ctx reference" do
      expect(body(base.merge("kwargs" => [{ "key" => "input", "value" => "hello world" }])))
        .to include('input: "hello world"')
    end

    it "keeps an injection payload inside a string literal" do
      payload = 'x"); system("id"); ("'
      expect(body(base.merge("kwargs" => [{ "key" => "input", "value" => payload }])))
        .to include(payload.inspect)
    end
  end

  describe "behaviour" do
    let(:field_type) { Struct.new(:name, :type, keyword_init: true) }

    it "invokes Service.call and writes the result" do
      ctx = { payload: { "qty" => "2" }, fields: [field_type.new(name: "qty", type: "integer")] }
      result = CodeGenerators::TestRunner.execute(described_class, config: base, ctx: ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:service_result]).to eq("qty" => 2)
    end

    it "surfaces a Result failure to the submitter" do
      failed = Struct.new(:ok, :errors, keyword_init: true).new(ok: false, errors: ["too expensive"])
      allow(FlowchartRuntime::Invocable).to receive(:call!).and_return(failed)
      ctx = { payload: {}, fields: [], errors: [] }
      result = CodeGenerators::TestRunner.execute(described_class, config: base, ctx: ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include("too expensive")
    end
  end
end

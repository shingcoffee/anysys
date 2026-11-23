# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Outcome::SetSubmissionOutcomeGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "is version 1.2.0" do
    expect(described_class._metadata[:version]).to eq("1.2.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        outcome = (ctx[:submission_outcome] || {}).stringify_keys
        payload = { "preset" => "submitted", "message" => nil, "flash" => "notice" }
        payload["handoff"] = outcome["handoff"] if outcome["handoff"]
        payload["journey"] = outcome["journey"] if outcome["journey"]
        ctx[:submission_outcome] = payload
      end
    RUBY
  end

  it "lints the body for each enum variant" do
    %w[submitted saved thank_you custom].each do |preset|
      config = described_class.sample_input.merge("preset" => preset, "message" => { "en" => "Thanks" })
      src = generate(config)
      expect(CodeGenerators::BodyLint.check(src, outputs: []).ok?).to be(true), "#{preset}: #{src}"
    end
  end

  it "writes no post-submit destination" do
    expect(described_class.sample_input.keys).not_to include("target", "page")
    expect(generate).not_to include("target")
  end

  it "emits interpolate_each when message variables are configured" do
    expect(generated_step(
      described_class.sample_input.merge(
        "preset" => "custom",
        "message" => { "en" => "Thanks %{name}", "zh-CN" => "谢谢%{name}。" },
        "messageVariables" => [{ "key" => "name", "value" => "ctx[:name]" }]
      )
    )).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        outcome = (ctx[:submission_outcome] || {}).stringify_keys
        payload = {
          "preset" => "custom",
          "message" => FlowchartRuntime::LocalizedText.interpolate_each(
            {"en" => "Thanks %{name}", "zh-CN" => "谢谢%{name}。"},
            {"name" => ctx[:name]}
          ),
          "flash" => "notice"
        }
        payload["handoff"] = outcome["handoff"] if outcome["handoff"]
        payload["journey"] = outcome["journey"] if outcome["journey"]
        ctx[:submission_outcome] = payload
      end
    RUBY
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    it "writes the outcome for one tenant without leaking into another ctx" do
      ctx_a = { customer_id: customer.id, errors: [] }
      ctx_b = { customer_id: other.id, errors: [] }

      result = execute(
        described_class.sample_input.merge(
          "preset" => "custom",
          "message" => { "en" => "Thanks", "zh-CN" => "谢谢。" }
        ),
        ctx_a
      )
      expect(result[:outcome]).to eq(ctx_a[:submission_outcome])
      expect(ctx_a[:submission_outcome]).to eq(
        "preset" => "custom",
        "message" => { "en" => "Thanks", "zh-CN" => "谢谢。" },
        "flash" => "notice"
      )

      execute(described_class.sample_input.merge("preset" => "saved"), ctx_b)
      expect(ctx_b[:submission_outcome]["preset"]).to eq("saved")
      expect(ctx_a[:submission_outcome]["preset"]).to eq("custom")
    end

    it "preserves a payment handoff already on the outcome" do
      ctx = { customer_id: customer.id, submission_outcome: { "handoff" => { "module_key" => "payment" } } }
      execute(described_class.sample_input.merge("preset" => "thank_you"), ctx)
      expect(ctx[:submission_outcome]["preset"]).to eq("thank_you")
      expect(ctx[:submission_outcome]["handoff"]).to eq("module_key" => "payment")
    end

    it "preserves journey steps an earlier step left out" do
      ctx = { customer_id: customer.id, submission_outcome: { "journey" => { "skip" => ["catering"] } } }
      execute(described_class.sample_input.merge("preset" => "saved"), ctx)
      expect(ctx[:submission_outcome]).to include("preset" => "saved", "journey" => { "skip" => ["catering"] })
    end

    it "interpolates message variables into every locale of the stored message" do
      ctx = { customer_id: customer.id, name: "Ada", errors: [] }
      execute(
        described_class.sample_input.merge(
          "preset" => "custom",
          "message" => { "en" => "Thanks %{name}", "zh-CN" => "谢谢%{name}。" },
          "messageVariables" => [{ "key" => "name", "value" => "ctx[:name]" }]
        ),
        ctx
      )
      expect(ctx[:submission_outcome]["message"]).to eq("en" => "Thanks Ada", "zh-CN" => "谢谢Ada。")
    end
  end
end

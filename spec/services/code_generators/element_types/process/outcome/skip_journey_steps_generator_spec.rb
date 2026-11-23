# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Outcome::SkipJourneyStepsGenerator do
  let(:element) { { "config" => described_class.sample_input } }
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
    expect(errors(described_class._config_schema.defaults).map(&:code)).to eq([:required])
  end

  it "accepts sample_input and compiles" do
    expect(errors(described_class.sample_input)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate}\nend") }.not_to raise_error
  end

  it "asks the journey to leave the listed steps out" do
    expect(generate("steps" => ["catering", " invoice "])).to eq(
      %(FlowchartRuntime::JourneySkips.request(ctx, steps: ["catering", "invoice"]))
    )
  end

  it "rejects anything that is not a journey step key" do
    expect(errors("steps" => ["Catering"]).map(&:code)).to eq([:invalid_step_key])
    expect(errors("steps" => ["x\"; system('id')"]).map(&:code)).to eq([:invalid_step_key])
    expect(errors("steps" => []).map(&:code)).to eq([:required])
  end

  it "never emits a value that is not a step key" do
    expect(generate("steps" => ["catering", "a\"); exit; ("])).to include(%(steps: ["catering"]))
  end

  describe "behaviour" do
    let(:journey) { { "key" => "booking", "step" => "details", "finishing" => false } }

    it "parks the steps on the outcome, keeping what is already there" do
      ctx = { journey: journey, submission_outcome: { "handoff" => { "module_key" => "payment" },
                                                      "journey" => { "skip" => ["notes"] } } }
      execute({ "steps" => %w[catering notes] }, ctx)

      expect(ctx[:submission_outcome]).to eq(
        "handoff" => { "module_key" => "payment" },
        "journey" => { "skip" => %w[notes catering] }
      )
    end

    it "does nothing outside a journey" do
      ctx = { submission_outcome: { "preset" => "saved" } }
      execute({ "steps" => ["catering"] }, ctx)

      expect(ctx[:submission_outcome]).to eq("preset" => "saved")
    end
  end
end

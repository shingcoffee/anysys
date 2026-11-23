# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::LogGenerator do
  let(:context) { {} }
  let(:base) { { "messageTemplate" => "Processing step" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"log.failed", FlowchartRuntime::Log::Error) do
          FlowchartRuntime::Log.write(ctx, level: "info", logger: "rails", message: "Processing step")
        end
      end
    RUBY
  end

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
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
    expect { RubyVM::InstructionSequence.compile(body(sample)) }.not_to raise_error
  end

  it "lints a BodyLint-clean body for every logger and logLevel" do
    described_class::LOGGERS.product(described_class::LOG_LEVELS).each do |logger, level|
      config = described_class.sample_input.merge("logger" => logger, "logLevel" => level)
      next if errors(config).any?

      result = CodeGenerators::BodyLint.check(body(config), outputs: [])
      expect(result.ok?).to be(true), "#{logger}/#{level}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  it "emits distinct bodies for rails and file" do
    sample = described_class.sample_input
    expect(body(sample.merge("logger" => "file", "filePath" => "custom.log")))
      .not_to eq(body(sample.merge("logger" => "rails")))
  end

  it "rejects stdout as a logger" do
    expect(errors("messageTemplate" => "x", "logger" => "stdout").map(&:code)).to include(:not_in_list)
  end

  describe "behaviour" do
    it "writes through Rails.logger" do
      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      expect(logger).to receive(:info).with("Processing step")
      result = execute(base, {})
      expect(result[:outcome]).to be_truthy
    end

    it "writes a structured JSON payload" do
      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      expect(logger).to receive(:info) do |payload|
        parsed = JSON.parse(payload)
        expect(parsed).to include("level" => "info", "message" => "Processing step")
      end
      execute(base.merge("structured" => true), {})
    end

    it "records a translated failure when the file logger has no tenant" do
      result = execute(described_class.sample_input.merge("logger" => "file", "filePath" => "log/custom.log"), {})
      expect(result[:outcome]).to eq(false)
      expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.log.failed", reason: "Error"))
    end
  end

  describe "#validate_config" do
    it "requires messageTemplate" do
      expect(errors({}).map(&:field)).to include("messageTemplate")
    end

    it "requires filePath when logger is file" do
      expect(errors("messageTemplate" => "x", "logger" => "file").map(&:field)).to include("filePath")
    end

    it "rejects a traversal filePath" do
      codes = errors("messageTemplate" => "x", "logger" => "file", "filePath" => "../../config/master.key")
                .map(&:code)
      expect(codes).to include(:unsafe_path)
    end

    it "rejects an invalid logger" do
      expect(errors("messageTemplate" => "x", "logger" => "audit").map(&:code)).to include(:not_in_list)
    end
  end

  it "redacts sensitive tag values in structured output" do
    logger = instance_double(ActiveSupport::Logger)
    allow(Rails).to receive(:logger).and_return(logger)
    expect(logger).to receive(:info) do |payload|
      parsed = JSON.parse(payload)
      expect(parsed["tags"]["password"]).to eq("[FILTERED]")
    end
    execute(
      base.merge("structured" => true, "tags" => [{ "key" => "password", "value" => "secret_value" }]),
      { secret_value: "hunter2" }
    )
  end
end

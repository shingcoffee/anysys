# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::GenerateFileGenerator do
  let(:context) { {} }
  let(:base) { described_class.sample_input }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    expect(generate(base).validate_config(base)).to eq([])
    expect { RubyVM::InstructionSequence.compile(generate(base).generate_step_method) }.not_to raise_error
    lint!(base)
  end

  it "is version 5.0.0" do
    expect(described_class._metadata[:version]).to eq("5.0.0")
  end

  it "does not expose pdf, xml, encodings, or outputDestination" do
    keys = described_class._config_schema.fields.map(&:name)
    expect(keys).not_to include("outputDestination", "encoding", "pageSize", "rootElement")
    expect(described_class::FILE_TYPES).to eq(%w[csv xlsx json txt])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"generate_file.failed",
          FlowchartRuntime::FileGenerate::Error,
          FlowchartRuntime::Template::Error
        ) do
          ctx[:generated_file] = FlowchartRuntime::FileGenerate.apply(
            ctx[:rows],
            file_type: "csv",
            locale: ctx[:locale]
          )
        end
      end
    RUBY
  end

  described_class::FILE_TYPES.each do |file_type|
    it "emits FileGenerate.apply for fileType #{file_type}" do
      config = base.merge("fileType" => file_type)
      expect(generate(config).validate_config(config)).to eq([])
      expect(body(config)).to include("FlowchartRuntime::FileGenerate.apply")
      expect(body(config)).to include(%(file_type: "#{file_type}"))
      lint!(config)
    end
  end

  it "writes a CSV file payload into the result variable" do
    config = base.merge(
      "fileType" => "csv",
      "sourceVariable" => "rows",
      "columns" => [{ "key" => "Name", "value" => "name" }],
      "headerRow" => true
    )
    result = execute(config, { rows: [{ "name" => "Ada" }] })
    expect(result[:outcome]).to be_truthy
    payload = result[:ctx][:generated_file]
    expect(payload["filename"]).to eq("export.csv")
    expect(payload["content_type"]).to eq("text/csv")
    expect(payload["content"].byteslice(0, 3)).to eq("\xEF\xBB\xBF".b)
    expect(CSV.parse(payload["content"].b.delete_prefix("\xEF\xBB\xBF".b).force_encoding("UTF-8"))).to eq([%w[Name], %w[Ada]])
  end

  it "omits the BOM when includeBom is false" do
    config = base.merge("fileType" => "csv", "includeBom" => false, "sourceVariable" => "rows")
    result = execute(config, { rows: [{ "id" => 1 }] })
    expect(result[:ctx][:generated_file]["content"].byteslice(0, 3)).not_to eq("\xEF\xBB\xBF".b)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::CompressFilesGenerator do
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

  it "is version 4.0.0" do
    expect(described_class._metadata[:version]).to eq("4.0.0")
  end

  it "does not expose tar or gzip format options" do
    keys = described_class._config_schema.fields.map(&:name)
    expect(keys).not_to include("format")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"compress_files.failed",
          FlowchartRuntime::Archive::Error,
          FlowchartRuntime::Template::Error
        ) do
          ctx[:archive] = FlowchartRuntime::Archive.pack(ctx, sources: {"data.txt" => "file_data"})
        end
      end
    RUBY
  end

  it "emits Archive.pack as zip without a format kwarg" do
    expect(body).to include("FlowchartRuntime::Archive.pack")
    expect(body).not_to include("format:")
    lint!(base)
  end

  it "emits filename when filenameTemplate is set" do
    config = base.merge("filenameTemplate" => "orders.zip")
    expect(body(config)).to include('filename: "orders.zip"')
  end

  it "compresses ctx entries into a zip file payload" do
    result = execute(base, { file_data: "hello" })
    expect(result[:outcome]).to be_truthy
    payload = result[:ctx][:archive]
    expect(payload).to include("filename" => "archive.zip", "content_type" => "application/zip")
    files = FlowchartRuntime::Archive.decompress(payload["content"], format: :zip)
    expect(files).to include(hash_including(name: "data.txt", content: "hello"))
  end

  it "zips a generate_file payload under the mapped entry name" do
    source = { "filename" => "export.csv", "content" => "a,b\n", "content_type" => "text/csv" }
    result = execute(base, { file_data: source })
    expect(result[:outcome]).to be_truthy
    files = FlowchartRuntime::Archive.decompress(result[:ctx][:archive]["content"], format: :zip)
    expect(files).to include(hash_including(name: "data.txt", content: "a,b\n"))
  end
end

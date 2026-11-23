# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::DecompressFilesGenerator do
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

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"decompress_files.failed",
          FlowchartRuntime::Archive::Error,
          FlowchartRuntime::SandboxPath::Error
        ) do
          ctx[:extracted] = FlowchartRuntime::Archive.unpack(ctx[:archive])
        end
      end
    RUBY
  end

  described_class::FORMATS.each do |format|
    it "emits Archive.unpack for format #{format}" do
      config = base.merge("format" => format)
      expect(generate(config).validate_config(config)).to eq([])
      expect(body(config)).to include("FlowchartRuntime::Archive.unpack")
      if format == "auto"
        expect(body(config)).not_to include("format:")
      else
        expect(body(config)).to include(%(format: "#{format}"))
      end
      lint!(config)
    end
  end

  it "extracts zip entries as file payloads through a zip-slip-safe unpack" do
    payload = FlowchartRuntime::Archive.compress([{ name: "ok.txt", content: "safe" }], format: :zip)
    result = execute(base.merge("format" => "zip"), { archive: payload })
    expect(result[:outcome]).to be_truthy
    expect(result[:ctx][:extracted]).to contain_exactly(
      hash_including("filename" => "ok.txt", "content" => "safe")
    )
  end

  it "unpacks a file payload from download_file or compress_files" do
    packed = FlowchartRuntime::Archive.pack({ file_data: "hello" }, sources: { "ok.txt" => "file_data" })
    result = execute(base.merge("format" => "zip"), { archive: packed })
    expect(result[:outcome]).to be_truthy
    expect(result[:ctx][:extracted]).to contain_exactly(
      hash_including("filename" => "ok.txt", "content" => "hello")
    )
  end

  it "emits maxEntries and maxTotalBytes only when set" do
    code = body(base.merge("maxEntries" => 2, "maxTotalBytes" => 64))
    expect(code).to include("max_entries: 2")
    expect(code).to include("max_total_bytes: 64")
    expect(body(base)).not_to include("max_entries:")
    expect(body(base)).not_to include("max_total_bytes:")
  end

  it "fails when extracted entries exceed maxEntries" do
    payload = FlowchartRuntime::Archive.compress(
      [{ name: "a.txt", content: "a" }, { name: "b.txt", content: "b" }],
      format: :zip
    )
    result = execute(base.merge("format" => "zip", "maxEntries" => 1), { archive: payload })
    expect(result[:outcome]).to be(false)
    expect(Array(result[:ctx][:error_details]).last.to_h["diagnostic"].to_s).to match(/too many entries/)
  end

  it "fails closed on a zip-slip entry name" do
    allow(FlowchartRuntime::Archive).to receive(:decompress)
      .and_return([{ name: "../secret.txt", content: "secret" }])

    result = execute(base.merge("format" => "zip"), { archive: "PK\x03\x04" })
    expect(result[:outcome]).to be(false)
    expect(result[:ctx]).not_to have_key(:extracted)
    expect(result[:ctx][:errors].join).to match(/decompress/i)
    expect(Array(result[:ctx][:error_details]).last.to_h["diagnostic"].to_s).to match(/path traversal/)
  end
end

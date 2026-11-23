# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::DownloadFileGenerator do
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

  def execute(config, ctx = { customer_id: 81721200, errors: [] })
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

  it "does not expose a destination field" do
    expect(described_class._config_schema.fields.map(&:name)).not_to include("destination")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"download_file.failed",
          FlowchartRuntime::FileDownload::Error
        ) do
          download = FlowchartRuntime::FileDownload.fetch(ctx, "https://example.com/file.csv")
          next false if download == false
          ctx[:file_content] = download
        end
      end
    RUBY
  end

  it "emits timeouts, retries and a breaker only when they differ from runtime defaults" do
    expect(body).not_to include("open_timeout:")
    expect(body).not_to include("retries:")
    config = base.merge("connectTimeout" => 2, "retryOnTransportError" => true, "circuitBreaker" => true)
    src = body(config)
    expect(src).to include("open_timeout: 2")
    expect(src).to include("retries:")
    expect(src).to include("breaker:")
  end

  it "downloads a GET body into a file payload" do
    stub_request(:get, "https://example.com/file.csv").to_return(status: 200, body: "a,b\n1,2")

    result = execute(base.merge("url" => "https://example.com/file.csv"))
    expect(result[:outcome]).to be_truthy
    payload = result[:ctx][:file_content]
    expect(payload["content"]).to eq("a,b\n1,2")
    expect(payload["filename"]).to eq("file.csv")
  end

  it "emits allowedContentTypes" do
    code = body(base.merge("allowedContentTypes" => ["text/csv"]))
    expect(code).to include("allowed_content_types:")
    expect(code).to include("text/csv")
    expect(body(base)).not_to include("text/csv")
  end

  it "accepts a matching Content-Type and rejects a mismatch" do
    stub_request(:get, "https://example.com/file.csv")
      .to_return(status: 200, body: "a,b\n1,2", headers: { "Content-Type" => "text/csv" })
    ok = execute(base.merge("url" => "https://example.com/file.csv", "allowedContentTypes" => ["text/csv"]))
    expect(ok[:outcome]).to be_truthy
    expect(ok[:ctx][:file_content]["content"]).to eq("a,b\n1,2")

    stub_request(:get, "https://example.com/file.bin")
      .to_return(status: 200, body: "nope", headers: { "Content-Type" => "application/octet-stream" })
    denied = execute(base.merge("url" => "https://example.com/file.bin", "allowedContentTypes" => ["text/csv"]))
    expect(denied[:outcome]).to be(false)
    expect(denied[:ctx][:errors].join).to match(/download/i)
  end

  it "fails with a translated HTTP status message" do
    stub_request(:get, "https://example.com/file.csv").to_return(status: 503, body: "busy")

    result = execute(base.merge("url" => "https://example.com/file.csv"))
    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors].join).to match(/HTTP 503|503/)
    expect(result[:ctx]).not_to have_key(:_last_error)
  end
end

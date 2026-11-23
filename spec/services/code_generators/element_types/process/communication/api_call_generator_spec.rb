# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def run_body(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "registers only api_call" do
    expect(described_class.registered_names).to eq(["api_call"])
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "is version 3.2.0" do
    expect(described_class._metadata[:version]).to eq("3.2.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        response = FlowchartRuntime::Http.request(
          ctx,
          :get,
          "https://api.example.com/users",
          follow_redirects: true,
          max_redirects: 5
        )
        return false unless response
        FlowchartRuntime::Step.attempt(ctx, :invalid_json, JSON::ParserError) do
          body = response.body.to_s
          ctx[:api_response] = FlowchartRuntime::Http.parse_json(body)
        end
      end
    RUBY
  end

  it "emits a BodyLint-clean body for each httpMethod" do
    %w[GET HEAD POST PUT PATCH DELETE OPTIONS].each do |method|
      config = described_class.sample_input.merge("httpMethod" => method)
      next if errors(config).any?

      result = CodeGenerators::BodyLint.check(generate(config), outputs: %w[api_response])
      expect(result.ok?).to be(true), "#{method}: #{result.violations.inspect}\n#{generate(config)}"
    end
  end

  it "emits POST JSON and form bodies" do
    json = generated_step(described_class.sample_input.merge("httpMethod" => "POST", "bodyTemplate" => "ctx[:payload] || {}"))
    expect(json).to include("body: (ctx[:payload] || {}).to_json")
    expect(json).to include('headers: {"Content-Type" => "application/json"}')

    form = generated_step(described_class.sample_input.merge("httpMethod" => "POST", "bodyFormat" => "form", "bodyTemplate" => "{ a: 1 }"))
    expect(form).to include("form: { a: 1 }")
    expect(form).not_to include("Content-Type")
  end

  it "emits text bodies without JSON parsing" do
    expect(generated_step(described_class.sample_input.merge("responseFormat" => "text"))).to include(
      "ctx[:api_response] = response.body.to_s"
    )
  end

  it "digs a parse key out of the JSON body" do
    expect(generated_step(described_class.sample_input.merge("responseParseKey" => "data.user"))).to include(
      "ctx[:api_response] = FlowchartRuntime::Step.dig(parsed, :data, :user)"
    )
  end

  it "emits ctx/ENV query and header values as expressions" do
    src = generated_step(described_class.sample_input.merge(
      "queryParams" => [{ "key" => "order_id", "value" => "ctx[:order_id]" }],
      "headers" => [{ "key" => "X-Request-Id", "value" => "ctx[:request_id]" }]
    ))
    expect(src).to include('"order_id" => ctx[:order_id]')
    expect(src).to include('"X-Request-Id" => ctx[:request_id]')
  end

  it "emits bearer auth and optional status/headers variables" do
    bearer = generated_step(described_class.sample_input.merge("authType" => "bearer", "authToken" => "ctx[:api_token]"))
    expect(bearer).to include(%(headers: {"Authorization" => "Bearer " + ctx[:api_token].to_s}))

    status = generated_step(described_class.sample_input.merge(
      "failOnHttpError" => false,
      "statusVar" => "http_status",
      "headersVar" => "http_headers"
    ))
    expect(status).to include("fail_on_http_error: false")
    expect(status).to include("ctx[:http_status] = response.status")
    expect(status).to include("ctx[:http_headers] = response.headers")
  end

  it "rejects retry on a non-idempotent POST without an idempotency key" do
    msgs = errors(described_class.sample_input.merge("httpMethod" => "POST", "retryOnTransportError" => true))
    expect(msgs.map(&:code)).to include(:retry_not_idempotent)
  end

  describe "behaviour" do
    let(:url) { "https://api.example.test/users" }
    let(:get_config) { described_class.sample_input.merge("url" => url.inspect, "httpMethod" => "GET") }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }
    after { FlowchartRuntime::RunContext.reset }

    it "retries a GET once after a connect timeout then succeeds" do
      attempts = 0
      allow(OutboundHttp).to receive(:request) do |**|
        attempts += 1
        raise OutboundHttp::TransportError, "execution expired" if attempts == 1

        OutboundHttp::Response.new(status: 200, headers: {}, body: '{"ok":true}')
      end
      ctx = { customer_id: 41, errors: [] }
      config = get_config.merge("retryOnTransportError" => true, "retryAttempts" => 1)

      result = run_body(config, ctx)
      expect(result[:validation_errors]).to eq([])
      expect(result[:outcome]).to eq(ok: true)
      expect(ctx[:api_response]).to eq(ok: true)
      expect(attempts).to eq(2)
    end

    it "never retries a POST without an idempotency key" do
      allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError, "refused")
      ctx = { customer_id: 41, errors: [] }
      config = described_class.sample_input.merge("url" => url.inspect, "httpMethod" => "POST")

      result = run_body(config, ctx)
      expect(result[:outcome]).to be(false)
      expect(OutboundHttp).to have_received(:request).once
      expect(ctx[:error_details].last["code"]).to eq("transport_error")
    end

    it "never retries a 503" do
      stub_request(:get, url).to_return(status: 503, body: "busy")
      ctx = { customer_id: 41, errors: [] }
      config = get_config.merge("retryOnTransportError" => true, "retryAttempts" => 2)

      result = run_body(config, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("http_status")
      expect(a_request(:get, url)).to have_been_made.once
    end

    it "stores status and body on 4xx when failOnHttpError is false" do
      stub_request(:get, url).to_return(status: 404, headers: { "X-Request-Id" => "abc" }, body: '{"error":true}')
      ctx = { customer_id: 41, errors: [] }
      config = get_config.merge(
        "failOnHttpError" => false,
        "statusVar" => "http_status",
        "headersVar" => "http_headers"
      )

      result = run_body(config, ctx)
      expect(result[:validation_errors]).to eq([])
      expect(result[:outcome]).to eq(error: true)
      expect(ctx[:http_status]).to eq(404)
      headers = ctx[:http_headers].to_h.transform_keys { |key| key.to_s.downcase }
      expect(headers).to include("x-request-id" => "abc")
      expect(ctx[:errors]).to eq([])
    end

    it "sends nothing when the breaker is open" do
      5.times { FlowchartRuntime::CircuitBreaker.evaluate(41, "api_call", outcome: "failure", failure_threshold: 5) }
      expect(OutboundHttp).not_to receive(:request)
      ctx = { customer_id: 41, errors: [] }
      config = get_config.merge("circuitBreaker" => true, "breakerName" => "api_call", "failureThreshold" => 5)

      result = run_body(config, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.circuit_open", name: "api_call"))
    end
  end
end

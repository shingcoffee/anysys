# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::SendWebhookGenerator do
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
        payload = ctx[:webhook_payload].to_json
        headers = {"Content-Type" => "application/json"}
        response = FlowchartRuntime::Http.request(
          ctx,
          :post,
          "https://hooks.example.com/webhook",
          headers: headers,
          body: payload
        )
        return false unless response
        ctx[:webhook_response] = FlowchartRuntime::Http.parse_json(response.body, strict: false)
      end
    RUBY
  end

  it "emits HMAC signing when a secret is present" do
    src = generated_step(described_class.sample_input.merge("secretExpression" => "ctx[:secret]"))
    expect(src).to include("FlowchartRuntime::Crypto.hmac")
    expect(src).to include(':"send_webhook.sign_failed"')
    expect(src).to include('headers["X-Signature"] = "sha256=" + digest')
  end

  it "emits form-encoded payloads and optional status" do
    form = generated_step(described_class.sample_input.merge("contentType" => "application/x-www-form-urlencoded"))
    expect(form).to include("URI.encode_www_form(ctx[:webhook_payload])")
    expect(form).to include("application/x-www-form-urlencoded")

    status = generated_step(described_class.sample_input.merge("failOnHttpError" => false, "statusVar" => "hook_status"))
    expect(status).to include("fail_on_http_error: false")
    expect(status).to include("ctx[:hook_status] = response.status")
  end

  it "rejects transport retry on POST without an idempotency key" do
    msgs = errors(described_class.sample_input.merge("retryOnTransportError" => true))
    expect(msgs.map(&:code)).to include(:retry_not_idempotent)
  end

  describe "behaviour" do
    let(:url) { "https://hooks.example.test/webhook" }
    let(:base) do
      described_class.sample_input.merge("url" => url.inspect, "payloadExpression" => "ctx[:webhook_payload]")
    end
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }
    after { FlowchartRuntime::RunContext.reset }

    it "never retries a POST without an idempotency key" do
      allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError, "refused")
      ctx = { customer_id: 41, errors: [], webhook_payload: { event: "update" } }

      result = run_body(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(OutboundHttp).to have_received(:request).once
      expect(ctx[:error_details].last["code"]).to eq("transport_error")
    end

    it "never retries a 503" do
      stub_request(:post, url).to_return(status: 503, body: "busy")
      ctx = { customer_id: 41, errors: [], webhook_payload: { event: "update" } }

      result = run_body(base.merge("idempotencyKey" => '"hook-1"', "retryOnTransportError" => true, "retryAttempts" => 2), ctx)
      expect(result[:outcome]).to be(false)
      expect(a_request(:post, url)).to have_been_made.once
      expect(ctx[:error_details].last["code"]).to eq("http_status")
    end

    it "sends nothing when the breaker is open" do
      5.times { FlowchartRuntime::CircuitBreaker.evaluate(41, "send_webhook", outcome: "failure", failure_threshold: 5) }
      expect(OutboundHttp).not_to receive(:request)
      ctx = { customer_id: 41, errors: [], webhook_payload: { event: "update" } }
      config = base.merge("circuitBreaker" => true, "breakerName" => "send_webhook")

      result = run_body(config, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("circuit_open")
    end

    it "stores a non-JSON 200 body without failing the step" do
      stub_request(:post, url).to_return(status: 200, body: "ok")
      ctx = { customer_id: 41, errors: [], webhook_payload: { event: "update" } }

      result = run_body(base, ctx)
      expect(result[:outcome]).to eq(body: "ok")
      expect(ctx[:webhook_response]).to eq(body: "ok")
      expect(ctx[:errors]).to eq([])
    end

    it "stores the status on 4xx when failOnHttpError is false" do
      stub_request(:post, url).to_return(status: 400, body: '{"ok":false}')
      ctx = { customer_id: 41, errors: [], webhook_payload: { event: "update" } }

      result = run_body(base.merge("failOnHttpError" => false, "statusVar" => "hook_status"), ctx)
      expect(result[:outcome]).to eq(ok: false)
      expect(ctx[:hook_status]).to eq(400)
      expect(ctx[:errors]).to eq([])
    end

    it "signs and delivers a JSON body" do
      payload = '{"event":"update"}'
      signature = OpenSSL::HMAC.hexdigest("sha256", "secret", payload)
      stub_request(:post, url).with(body: payload, headers: { "X-Signature" => "sha256=#{signature}" })
        .to_return(status: 200, body: '{"accepted":true}')
      ctx = { customer_id: 41, errors: [], secret: "secret", webhook_payload: { event: "update" } }

      result = run_body(base.merge("secretExpression" => "ctx[:secret]"), ctx)
      expect(result[:outcome]).to eq(accepted: true)
      expect(a_request(:post, url)).to have_been_made.once
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::SendChatMessageGenerator do
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

  it "is version 1.1.0" do
    expect(described_class._metadata[:version]).to eq("1.1.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"send_chat_message.render_failed",
          FlowchartRuntime::Template::Error
        ) do
          ctx[:chat_response] = FlowchartRuntime::ChatMessage.deliver(
            ctx,
            provider: "slack",
            url: "https://hooks.example.com/services/xxx",
            text: FlowchartRuntime::Template.render("New order {{order_number}}", ctx)
          )
        end
      end
    RUBY
  end

  it "emits a BodyLint-clean sample body for every provider" do
    described_class::PROVIDERS.each do |provider|
      src = generate(described_class.sample_input.merge("provider" => provider))
      result = CodeGenerators::BodyLint.check(src, outputs: %w[chat_response])
      expect(result.ok?).to be(true), "#{provider}: #{result.violations.inspect}\n#{src}"
    end
  end

  it "includes a signing secret only when the field is present" do
    expect(generated_step).not_to include("signing_secret:")
    signed = generated_step(described_class.sample_input.merge("provider" => "dingtalk", "signingSecret" => "ctx[:chat_secret]"))
    expect(signed).to include("signing_secret: ctx[:chat_secret]")
    expect(signed).to include('provider: "dingtalk"')
  end

  it "emits markdown title and mention_all" do
    src = generated_step(described_class.sample_input.merge("messageType" => "markdown", "title" => "Orders", "mentionAll" => true))
    expect(src).to include('message_type: "markdown"')
    expect(src).to include('title: "Orders"')
    expect(src).to include("mention_all: true")
  end

  describe "behaviour" do
    let(:url) { "https://hooks.slack.test/services/xxx" }
    let(:base) { described_class.sample_input.merge("webhookUrl" => url.inspect) }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }
    after { FlowchartRuntime::RunContext.reset }

    it "renders the Liquid text and posts the Slack payload" do
      stub_request(:post, url).with(body: { "text" => "New order 99" }.to_json)
        .to_return(status: 200, body: "ok")
      ctx = { customer_id: 41, order_number: 99, errors: [] }

      result = run_body(base, ctx)
      expect(result[:outcome]).to eq("body" => "ok")
      expect(ctx[:chat_response]).to eq("body" => "ok")
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "signs a DingTalk post with timestamp and sign query params" do
      hook = "https://oapi.dingtalk.test/robot/send"
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
        timestamp, sign = FlowchartRuntime::ChatMessage.dingtalk_sign("bot-secret")
        stub_request(:post, hook)
          .with(query: { "timestamp" => timestamp, "sign" => sign })
          .to_return(status: 200, body: '{"errcode":0}')
        ctx = { customer_id: 41, order_number: 99, chat_secret: "bot-secret", errors: [] }
        config = base.merge(
          "webhookUrl" => hook.inspect,
          "provider" => "dingtalk",
          "signingSecret" => "ctx[:chat_secret]"
        )

        result = run_body(config, ctx)
        expect(result[:outcome]).to include("errcode" => 0)
      end
    end

    it "treats a non-2xx response as send_chat_message.delivery_failed" do
      stub_request(:post, url).to_return(status: 503, body: "busy")
      ctx = { customer_id: 41, order_number: 99, errors: [] }

      result = run_body(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("send_chat_message.delivery_failed")
    end

    it "sends nothing when the breaker is open" do
      5.times { FlowchartRuntime::CircuitBreaker.evaluate(41, "send_chat_message", outcome: "failure", failure_threshold: 5) }
      expect(OutboundHttp).not_to receive(:request)
      ctx = { customer_id: 41, order_number: 99, errors: [] }
      config = base.merge("circuitBreaker" => true, "breakerName" => "send_chat_message")

      result = run_body(config, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("circuit_open")
    end
  end
end

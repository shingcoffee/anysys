# frozen_string_literal: true

require "rails_helper"

RSpec.describe "communication generated execution wiring" do
  def execute(klass, config, ctx = {})
    result = CodeGenerators::TestRunner.execute(klass, config: config, ctx: ctx)
    expect(result[:validation_errors]).to be_empty
    result
  end

  describe CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator do
    let(:url) { "https://api.example.test/events" }
    let(:config) do
      described_class.sample_input.merge("url" => url.inspect, "httpMethod" => "POST", "bodyTemplate" => "ctx[:payload] || {}")
    end

    it "serializes the body expression at the HTTP boundary" do
      stub_request(:post, url).with(body: '{"enabled":false}').to_return(status: 200, body: '{"ok":true}')
      ctx = { customer_id: 41, payload: { enabled: false }, errors: [] }
      result = execute(described_class, config, ctx)
      expect(result[:outcome]).to eq(ok: true)
      expect(a_request(:post, url)).to have_been_made.once
    end
  end

  describe CodeGenerators::ElementTypes::Process::Communication::SendWebhookGenerator do
    let(:url) { "https://hooks.example.test/events" }

    it "posts JSON through FlowchartRuntime::Http" do
      stub_request(:post, url).with(body: '{"event":"update"}').to_return(status: 200, body: "{}")
      ctx = { customer_id: 41, errors: [] }
      config = described_class.sample_input.merge("url" => url.inspect, "payloadExpression" => '{ event: "update" }')
      result = execute(described_class, config, ctx)
      expect(result[:outcome]).to eq({})
    end
  end
end

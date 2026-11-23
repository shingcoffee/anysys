# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ChatMessage do
  let(:ctx) { { customer_id: 41, errors: [], error_details: [] } }
  let(:text) { "New order 42" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }
  after { FlowchartRuntime::RunContext.reset }

  def deliver(url:, provider: "slack", **overrides)
    described_class.deliver(
      ctx,
      provider: provider,
      url: url,
      message_type: "text",
      title: "",
      text: text,
      mention_all: false,
      mention_mobiles: [],
      signing_secret: nil,
      open_timeout: 3,
      read_timeout: 7,
      breaker: nil,
      **overrides
    )
  end

  describe ".payload" do
    it "builds a Slack text body and a markdown block kit payload" do
      expect(described_class.payload(
        provider: "slack", message_type: "text", title: "", text: text,
        mention_all: true, mention_mobiles: []
      )).to eq("text" => "<!channel> #{text}")

      markdown = described_class.payload(
        provider: "slack", message_type: "markdown", title: "Orders", text: text,
        mention_all: false, mention_mobiles: []
      )
      expect(markdown["blocks"].first).to include("type" => "header")
      expect(markdown["blocks"].last.dig("text", "type")).to eq("mrkdwn")
    end

    it "builds a Teams Adaptive Card message for Workflows webhooks" do
      message = described_class.payload(
        provider: "teams", message_type: "markdown", title: "Orders", text: text,
        mention_all: true, mention_mobiles: []
      )
      attachment = message.fetch("attachments").sole
      expect(message["type"]).to eq("message")
      expect(attachment["contentType"]).to eq("application/vnd.microsoft.card.adaptive")
      expect(attachment.dig("content", "type")).to eq("AdaptiveCard")
      expect(attachment.dig("content", "body").map { |block| block["text"] }).to eq(["Orders", "@all #{text}"])
    end

    it "builds DingTalk text and markdown payloads with at-targets" do
      text_payload = described_class.payload(
        provider: "dingtalk", message_type: "text", title: "", text: text,
        mention_all: true, mention_mobiles: %w[13800138000]
      )
      expect(text_payload).to include("msgtype" => "text")
      expect(text_payload["at"]).to eq("isAtAll" => true, "atMobiles" => %w[13800138000])

      md = described_class.payload(
        provider: "dingtalk", message_type: "markdown", title: "Orders", text: text,
        mention_all: false, mention_mobiles: []
      )
      expect(md["markdown"]).to eq("title" => "Orders", "text" => text)

      untitled = described_class.payload(
        provider: "dingtalk", message_type: "markdown", title: "", text: "Order 42 shipped\nDetails",
        mention_all: false, mention_mobiles: []
      )
      expect(untitled.dig("markdown", "title")).to eq("Order 42 shipped")
    end

    it "builds WeCom mentioned_mobile_list and markdown content" do
      text_payload = described_class.payload(
        provider: "wecom", message_type: "text", title: "", text: text,
        mention_all: true, mention_mobiles: %w[13800138000]
      )
      expect(text_payload["text"]).to include(
        "content" => text,
        "mentioned_list" => ["@all"],
        "mentioned_mobile_list" => %w[13800138000]
      )
    end

    it "builds a Feishu text payload and an interactive markdown card" do
      expect(described_class.payload(
        provider: "feishu", message_type: "text", title: "", text: text,
        mention_all: false, mention_mobiles: []
      )).to eq("msg_type" => "text", "content" => { "text" => text })

      card = described_class.payload(
        provider: "feishu", message_type: "markdown", title: "Orders", text: text,
        mention_all: true, mention_mobiles: []
      )
      expect(card["msg_type"]).to eq("interactive")
      expect(card.dig("card", "header", "title", "content")).to eq("Orders")
      expect(card.dig("card", "elements", 0, "text", "content")).to eq("<at id=all></at> #{text}")

      I18n.with_locale(:"zh-CN") do
        mention = described_class.payload(
          provider: "feishu", message_type: "text", title: "", text: text,
          mention_all: true, mention_mobiles: []
        )
        expect(mention.dig("content", "text")).to eq("<at user_id=\"all\">所有人</at> #{text}")
      end
    end
  end

  describe ".deliver" do
    it "posts a Slack JSON body and returns the parsed response" do
      url = "https://hooks.slack.test/services/xxx"
      stub_request(:post, url).with(body: { "text" => text }.to_json)
        .to_return(status: 200, body: "ok")

      result = deliver(url: url)
      expect(result).to eq("body" => "ok")
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "applies runtime defaults when optional keyword arguments are omitted" do
      url = "https://hooks.slack.test/services/xxx"
      stub_request(:post, url).with(body: { "text" => text }.to_json)
        .to_return(status: 200, body: "ok")

      result = described_class.deliver(ctx, provider: "slack", url: url, text: text)
      expect(result).to eq("body" => "ok")
    end

    it "appends DingTalk timestamp and sign query params" do
      url = "https://oapi.dingtalk.test/robot/send"
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
        timestamp, sign = described_class.dingtalk_sign("bot-secret")
        stub_request(:post, url)
          .with(query: { "timestamp" => timestamp, "sign" => sign })
          .to_return(status: 200, body: '{"errcode":0}')

        result = deliver(url: url, provider: "dingtalk", signing_secret: "bot-secret")
        expect(result).to include("errcode" => 0)
      end
    end

    it "places a Feishu timestamp and sign in the JSON body" do
      url = "https://open.feishu.test/open-apis/bot/v2/hook/xxx"
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
        timestamp, sign = described_class.feishu_sign("bot-secret")
        stub_request(:post, url)
          .with { |request|
            body = JSON.parse(request.body)
            body["timestamp"] == timestamp.to_s && body["sign"] == sign && body["msg_type"] == "text"
          }
          .to_return(status: 200, body: '{"code":0}')

        expect(deliver(url: url, provider: "feishu", signing_secret: "bot-secret")).to include("code" => 0)
      end
    end

    it "fails with send_chat_message.delivery_failed on a non-2xx response" do
      url = "https://hooks.slack.test/services/xxx"
      stub_request(:post, url).to_return(status: 503, body: "busy")

      expect(deliver(url: url)).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("send_chat_message.delivery_failed")
      expect(ctx[:errors].first).to include("503")
    end

    it "fails with a translated transport_failed reason when the request cannot be made" do
      expect(deliver(url: "")).to be(false)
      detail = ctx[:error_details].last
      expect(detail["code"]).to eq("send_chat_message.transport_failed")
      expect(detail.dig("details", :reason)).to eq("Error")
      expect(detail["diagnostic"]).to eq("url is required")
    end

    it "keeps blocked_destination when the webhook URL points at a private address" do
      allow(OutboundHttp).to receive(:request)
        .and_raise(OutboundHttp::BlockedDestinationError, "destination is not allowed")

      expect(deliver(url: "http://169.254.169.254/latest/meta-data")).to be(false)
      expect(ctx[:error_details].map { |detail| detail["code"] }).to eq(["blocked_destination"])
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.blocked_destination")])
    end

    it "fails with send_chat_message.provider_error when DingTalk errcode is non-zero" do
      url = "https://oapi.dingtalk.test/robot/send"
      stub_request(:post, url).to_return(status: 200, body: '{"errcode":310000,"errmsg":"sign error"}')

      expect(deliver(url: url, provider: "dingtalk")).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("send_chat_message.provider_error")
      expect(ctx[:errors].first).to include("310000")
    end

    it "fails with send_chat_message.provider_error when Feishu code is non-zero" do
      url = "https://open.feishu.test/open-apis/bot/v2/hook/xxx"
      stub_request(:post, url).to_return(status: 200, body: '{"code":19021,"msg":"sign match fail"}')

      expect(deliver(url: url, provider: "feishu")).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("send_chat_message.provider_error")
    end

    it "sends nothing when the breaker is open" do
      5.times { FlowchartRuntime::CircuitBreaker.evaluate(41, "send_chat_message", outcome: "failure", failure_threshold: 5) }
      expect(OutboundHttp).not_to receive(:request)

      result = deliver(
        url: "https://hooks.slack.test/services/xxx",
        breaker: { name: "send_chat_message", threshold: 5, reset_seconds: 60 }
      )
      expect(result).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("circuit_open")
    end
  end
end

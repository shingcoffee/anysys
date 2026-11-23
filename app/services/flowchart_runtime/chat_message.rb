# frozen_string_literal: true

require "json"
require "openssl"
require "base64"

module FlowchartRuntime
  # Builds and posts incoming-webhook payloads for Slack, Teams, DingTalk,
  # WeCom, and Feishu. Signing and provider error bodies stay here so generated
  # step code stays under BodyLint's line budget.
  module ChatMessage
    class Error < StandardError; end

    PROVIDERS = %w[slack teams dingtalk wecom feishu].freeze
    MESSAGE_TYPES = %w[text markdown].freeze

    module_function

    def deliver(ctx, **message)
      Step.attempt(ctx, :"send_chat_message.transport_failed", Http::Error, Error) { post(ctx, **message) }
    end

    def post(ctx, provider:, url:, text:, message_type: "text", title: "", mention_all: false,
             mention_mobiles: [], signing_secret: nil, open_timeout: Http::DEFAULT_OPEN_TIMEOUT,
             read_timeout: Http::DEFAULT_READ_TIMEOUT, breaker: nil)
      body = payload(
        provider: provider,
        message_type: message_type,
        title: title,
        text: text,
        mention_all: mention_all,
        mention_mobiles: mention_mobiles
      )
      query = {}
      secret = signing_secret.to_s
      if secret.present? && provider.to_s == "dingtalk"
        timestamp, sign = dingtalk_sign(secret)
        query = { "timestamp" => timestamp, "sign" => sign }
      elsif secret.present? && provider.to_s == "feishu"
        timestamp, sign = feishu_sign(secret)
        body = body.merge("timestamp" => timestamp.to_s, "sign" => sign)
      end

      response = Http.request(
        ctx, :post, url,
        headers: { "Content-Type" => "application/json" },
        query: query,
        body: body.to_json,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        retries: 0,
        breaker: breaker
      )
      return remap_http_status!(ctx) unless response

      parsed = parse_body(response.body)
      if provider_error?(provider, parsed)
        return Step.fail(ctx, :"send_chat_message.provider_error", code: provider_error_code(parsed))
      end

      parsed
    end

    def payload(provider:, message_type:, title:, text:, mention_all:, mention_mobiles:)
      mobiles = Array(mention_mobiles).map(&:to_s).reject(&:empty?)
      case provider.to_s
      when "teams" then teams_payload(message_type, title, text, mention_all)
      when "dingtalk" then dingtalk_payload(message_type, title, text, mention_all, mobiles)
      when "wecom" then wecom_payload(message_type, title, text, mention_all, mobiles)
      when "feishu" then feishu_payload(message_type, title, text, mention_all)
      else slack_payload(message_type, title, text, mention_all)
      end
    end

    def dingtalk_sign(secret, at: Time.now)
      timestamp = (at.to_f * 1000).to_i
      string_to_sign = "#{timestamp}\n#{secret}"
      [timestamp, Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret.to_s, string_to_sign))]
    end

    def feishu_sign(secret, at: Time.now)
      timestamp = at.to_i
      string_to_sign = "#{timestamp}\n#{secret}"
      [timestamp, Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", string_to_sign, ""))]
    end

    def slack_payload(message_type, title, text, mention_all)
      body = mention_all ? "<!channel> #{text}" : text.to_s
      return { "text" => body } unless message_type.to_s == "markdown"

      blocks = []
      blocks << { "type" => "header", "text" => { "type" => "plain_text", "text" => title.to_s } } if title.to_s.present?
      blocks << { "type" => "section", "text" => { "type" => "mrkdwn", "text" => body } }
      { "text" => body, "blocks" => blocks }
    end

    # Teams Workflows webhooks accept only Adaptive Card attachments.
    def teams_payload(message_type, title, text, mention_all)
      body = mention_all ? "@all #{text}" : text.to_s
      blocks = []
      if title.to_s.present? && message_type.to_s == "markdown"
        blocks << { "type" => "TextBlock", "text" => title.to_s, "weight" => "Bolder", "size" => "Medium", "wrap" => true }
      end
      blocks << { "type" => "TextBlock", "text" => body, "wrap" => true }
      card = {
        "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
        "type" => "AdaptiveCard", "version" => "1.4", "body" => blocks
      }
      { "type" => "message",
        "attachments" => [{ "contentType" => "application/vnd.microsoft.card.adaptive", "content" => card }] }
    end

    def dingtalk_payload(message_type, title, text, mention_all, mobiles)
      at = {}
      at["isAtAll"] = true if mention_all
      at["atMobiles"] = mobiles if mobiles.any?
      payload = if message_type.to_s == "markdown"
        heading = title.to_s.presence || text.to_s.lines.first.to_s.strip[0, 64]
        { "msgtype" => "markdown", "markdown" => { "title" => heading, "text" => text.to_s } }
      else
        { "msgtype" => "text", "text" => { "content" => text.to_s } }
      end
      payload["at"] = at if at.any?
      payload
    end

    def wecom_payload(message_type, title, text, mention_all, mobiles)
      if message_type.to_s == "markdown"
        content = title.to_s.present? ? "**#{title}**\n#{text}" : text.to_s
        { "msgtype" => "markdown", "markdown" => { "content" => content } }
      else
        text_body = { "content" => text.to_s }
        text_body["mentioned_list"] = ["@all"] if mention_all
        text_body["mentioned_mobile_list"] = mobiles if mobiles.any?
        { "msgtype" => "text", "text" => text_body }
      end
    end

    def feishu_payload(message_type, title, text, mention_all)
      if message_type.to_s == "markdown"
        body = mention_all ? "<at id=all></at> #{text}" : text.to_s
        card = { "elements" => [{ "tag" => "div", "text" => { "tag" => "lark_md", "content" => body } }] }
        card["header"] = { "title" => { "tag" => "plain_text", "content" => title.to_s } } if title.to_s.present?
        { "msg_type" => "interactive", "card" => card }
      else
        everyone = I18n.t("flowchart_runtime.chat_message.mention_all")
        body = mention_all ? "<at user_id=\"all\">#{everyone}</at> #{text}" : text.to_s
        { "msg_type" => "text", "content" => { "text" => body } }
      end
    end

    def parse_body(raw)
      text = raw.to_s
      return {} if text.strip.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      { "body" => text }
    end

    def provider_error?(provider, parsed)
      return false unless parsed.is_a?(Hash)

      case provider.to_s
      when "dingtalk", "wecom"
        code = parsed["errcode"] || parsed[:errcode]
        !code.nil? && code.to_i != 0
      when "feishu"
        code = parsed["code"] || parsed[:code]
        !code.nil? && code.to_i != 0
      when "slack"
        parsed["ok"] == false || parsed[:ok] == false
      else
        false
      end
    end

    def provider_error_code(parsed)
      parsed["errcode"] || parsed["code"] || parsed["error"] ||
        parsed[:errcode] || parsed[:code] || parsed[:error] || "error"
    end

    def remap_http_status!(ctx)
      last = Array(ctx[:error_details]).last
      return false unless last && last["code"] == "http_status"

      status = last.dig("details", "status") || last.dig("details", :status)
      ctx[:error_details].pop
      ctx[:errors].pop if ctx[:errors].is_a?(Array) && ctx[:errors].any?
      Step.fail(ctx, :"send_chat_message.delivery_failed", status: status)
    end
    private_class_method :post, :slack_payload, :teams_payload, :dingtalk_payload, :wecom_payload,
                         :feishu_payload, :parse_body, :provider_error?, :provider_error_code,
                         :remap_http_status!
  end
end

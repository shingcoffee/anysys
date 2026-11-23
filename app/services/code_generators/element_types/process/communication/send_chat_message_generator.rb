# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class SendChatMessageGenerator < BaseGenerator
          PROVIDERS = FlowchartRuntime::ChatMessage::PROVIDERS
          MESSAGE_TYPES = FlowchartRuntime::ChatMessage::MESSAGE_TYPES

          generator_metadata do
            description "Posts text or Markdown to a Slack, Teams, DingTalk, WeCom, or Feishu " \
                        "incoming webhook. Use send_webhook for a generic signed POST, or " \
                        "send_email for email. Reads provider, webhookUrl, messageType, text " \
                        "(Liquid), optional title (Markdown), mentionAll, mentionMobiles " \
                        "(DingTalk/WeCom), and signingSecret (DingTalk/Feishu). Writes resultVar " \
                        "(default chat_response) with the parsed provider body. Fails with " \
                        "send_chat_message.delivery_failed, provider_error, transport_failed, or " \
                        "render_failed."
            category :communication
            version "1.1.0"
            presentation icon: "M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z",
                          color: "sky", single_use: false, privileged: false
          end

          config_schema do
            enum :provider, PROVIDERS, default: "slack",
                 description: "Chat platform that owns the incoming webhook: slack (default), teams, dingtalk, wecom, or feishu."
            expression :webhookUrl, required: true, example: '"https://hooks.example.com/services/xxx"',
                       placeholder: true,
                       description: "Incoming webhook URL as Ruby, e.g. \"https://hooks.slack.com/services/T../B../...\". Must be a public https URL."
            enum :messageType, MESSAGE_TYPES, default: "text",
                 description: "text (default) sends a plain body. markdown sends a formatted payload and shows the title field."
            template :title, default: "", visible: { messageType: "markdown" },
                     description: "Optional heading above a Markdown message, e.g. New order {{ order_number }}. Hidden when messageType is text."
            template :text, required: true, example: "New order {{order_number}}", placeholder: true,
                     description: "Message body. Liquid placeholders resolve from ctx, e.g. New order {{ order_number }}."
            flag :mentionAll, default: false,
                 description: "When true, pings every member (@channel / @all). Default false."
            list :mentionMobiles, item: :literal, default: [],
                 visible: { provider: %w[dingtalk wecom] }, group: :advanced,
                 description: "Mobile numbers @-mentioned on DingTalk or WeCom, e.g. 13800138000. Hidden for other providers."
            expression :signingSecret, example: "ctx[:chat_secret]",
                       visible: { provider: %w[dingtalk feishu] }, group: :advanced,
                       description: "DingTalk or Feishu bot signing secret as a ctx/ENV expression, e.g. ENV.fetch(\"CHAT_SECRET\", nil). Never a quoted secret. Hidden for other providers."
            output :resultVar, default: "chat_response",
                   description: "ctx key for the parsed provider response (default chat_response). JSON object, or {body:} when the remote returns non-JSON text."
            timeouts open: 3, read: 7
            circuit_breaker_option
          end

          def generate_body
            body(
              attempt('"send_chat_message.render_failed"', FlowchartRuntime::Template::Error) do
                [assign(:resultVar, "FlowchartRuntime::ChatMessage.deliver(#{deliver_args})")]
              end
            )
          end

          private

          def deliver_args
            [
              "ctx",
              "provider: #{read(:provider)}",
              "url: #{read(:webhookUrl)}",
              optional_kw("message_type", read(:messageType), '"text"'),
              optional_kw("title", read(:title), '""'),
              "text: #{read(:text)}",
              optional_kw("mention_all", read(:mentionAll), "false"),
              optional_kw("mention_mobiles", read(:mentionMobiles), "[]"),
              optional_kw("signing_secret", signing_secret_source, "nil"),
              optional_kw("open_timeout", read(:connectTimeout), "3"),
              optional_kw("read_timeout", read(:readTimeout), "7"),
              optional_kw("breaker", breaker_source, "nil")
            ].compact.join(", ")
          end

          def signing_secret_source
            value(:signingSecret).to_s.strip.empty? ? "nil" : read(:signingSecret)
          end

          def breaker_source
            return "nil" unless value(:circuitBreaker)

            "{ name: #{read(:breakerName)}, threshold: #{read(:failureThreshold)}, reset_seconds: #{read(:resetTimeoutSeconds)} }"
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "base64"

# AiAssistant::Providers (registry) is referenced by `register!` at
# class-body load time. Force-load it so this file is safe to require in
# isolation (eager load may hit this file before providers.rb).
require_relative "../providers"

module AiAssistant
  module Providers
    # Cursor Cloud Agents via OutboundHttp. Generation only — #transcribe
    # fail-closes. #chat runs from jobs and must never run on a Puma request
    # thread; #health_check is a single bounded GET that the platform-owner
    # "Test connection" button runs live.
    class Cursor < Base
      AGENTS_URL = "https://api.cursor.com/v1/agents"
      MODELS_URL = "https://api.cursor.com/v1/models"
      OPEN_TIMEOUT = 5
      CHAT_READ_TIMEOUT = 60
      HEALTH_READ_TIMEOUT = 30
      POLL_INTERVAL = 0.5
      # A run on the full assistant prompt that writes a large tool document takes several minutes.
      # Limits::MAX_VENDOR_CALLS runs at this deadline must still finish inside
      # AiAssistant::Generation::MAX_RUNNING_AGE.
      AGENT_TIMEOUT = 600
      RETRYABLE_CLIENT_STATUS = 429
      RUN_TERMINAL_STATUSES = %w[FINISHED ERROR CANCELLED EXPIRED].freeze
      MAX_PROMPT_IMAGES = 5

      class << self
        def key                  = "cursor"
        def default_display_name = "Cursor"

        def config_fields
          [
            { name: :chat_model, label: "Chat model", type: :string }
          ]
        end

        def configured?(settings)
          settings.api_key.present?
        end

        def supports_transcribe? = false
        def supports_generation? = true
      end

      register!

      def transcribe(io:, filename:, content_type:, language: nil) # rubocop:disable Lint/UnusedMethodArgument
        { outcome: :configuration_error, text: nil, raw: nil }
      end

      # Cloud Agents are a create-then-poll API with no token stream, so
      # `on_chunk` is accepted and ignored (supports_streaming? stays false).
      def chat(messages:, tools: nil, on_chunk: nil) # rubocop:disable Lint/UnusedMethodArgument
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)
        return AiAssistant::ScriptedCompletion.call(messages: messages) if AiAssistant::ScriptedCompletion.enabled?

        created = create_agent(messages)
        return created unless created[:outcome] == :success

        poll_run(created[:text], created[:run_id])
      rescue OutboundHttp::TransportError, Faraday::Error => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      end

      def health_check
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        res = cursor_request(:get, MODELS_URL, read_timeout: HEALTH_READ_TIMEOUT)
        mapped = map_status(res.status, parse_json(res.body))
        return mapped.merge(http_status: res.status) unless mapped[:outcome] == :success

        items = Array(mapped[:raw].is_a?(Hash) ? mapped[:raw]["items"] : nil)
        models = items.filter_map { |item| model_entry(item) }
        { outcome: :success, text: nil, raw: mapped[:raw], models: models }
      rescue OutboundHttp::TransportError, Faraday::Error => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      end

      private

      def create_agent(messages)
        prompt = { text: flatten_messages(messages) }
        images = prompt_images(messages)
        prompt[:images] = images if images.any?
        body = { prompt: prompt }
        chat_model = settings.config_value(:chat_model).to_s.strip
        body[:model] = { id: chat_model } if chat_model.present?

        res = cursor_request(:post, AGENTS_URL, body: body, read_timeout: CHAT_READ_TIMEOUT)
        mapped = map_status(res.status, parse_json(res.body))
        return mapped unless mapped[:outcome] == :success

        # v1 returns the durable agent AND the initial run, not a top-level id.
        # Pin the run from this envelope; latestRunId can change on follow-up.
        payload = mapped[:raw].is_a?(Hash) ? mapped[:raw] : {}
        agent_id = payload.dig("agent", "id").to_s
        run_id = payload.dig("run", "id").to_s
        return { outcome: :unreachable, text: nil, raw: payload } if agent_id.blank? || run_id.blank?

        { outcome: :success, text: agent_id, run_id: run_id, raw: payload }
      end

      def poll_run(agent_id, run_id)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + AGENT_TIMEOUT
        url = "#{AGENTS_URL}/#{agent_id}/runs/#{run_id}"
        loop do
          res = cursor_request(:get, url, read_timeout: CHAT_READ_TIMEOUT)
          mapped = map_status(res.status, parse_json(res.body))
          return mapped unless mapped[:outcome] == :success

          payload = mapped[:raw]
          status = payload.is_a?(Hash) ? (payload["status"] || payload[:status]).to_s : ""
          if RUN_TERMINAL_STATUSES.include?(status)
            return { outcome: :unreachable, text: nil, raw: payload } unless status == "FINISHED"

            text = payload["result"].to_s.strip
            return { outcome: text.present? ? :success : :empty, text: text.presence, raw: payload }
          end
          return { outcome: :unreachable, text: nil, raw: payload } if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          poll_wait
        end
      end

      def flatten_messages(messages)
        lines = Array(messages).map do |msg|
          role = (msg[:role] || msg["role"]).to_s.upcase
          content = (msg[:content] || msg["content"]).to_s
          "#{role}: #{content}"
        end
        lines << "Reply with a JSON object only."
        lines.join("\n")
      end

      def prompt_images(messages)
        Array(messages)
          .flat_map { |msg| Array(msg[:images] || msg["images"]) }
          .last(MAX_PROMPT_IMAGES)
          .filter_map { |blob| image_payload(blob) }
      end

      def image_payload(blob)
        return nil unless blob.respond_to?(:content_type) && blob.respond_to?(:download)

        mime = blob.content_type.to_s
        return nil unless AiAssistant::Assistant::Attachments::IMAGE_TYPES.include?(mime)

        bytes = blob.download
        return nil if bytes.nil? || bytes.empty?

        { data: Base64.strict_encode64(bytes), mimeType: mime }
      end

      def model_entry(item)
        return nil unless item.is_a?(Hash)

        id = (item["id"] || item[:id]).to_s
        return nil if id.blank?

        display = (item["displayName"] || item[:displayName] || item["display_name"] || id).to_s
        { "id" => id, "display_name" => display }
      end

      def cursor_request(method, url, body: nil, read_timeout:)
        OutboundHttp.request(
          method,
          url,
          headers: auth_headers,
          body: body,
          open_timeout: OPEN_TIMEOUT,
          read_timeout: read_timeout
        )
      end

      def auth_headers
        {
          "Authorization" => "Bearer #{settings.api_key}",
          "Content-Type" => "application/json"
        }
      end

      def map_status(status, raw)
        code = status.to_i
        if (200..299).cover?(code)
          { outcome: :success, text: nil, raw: raw }
        elsif code != RETRYABLE_CLIENT_STATUS && (400..499).cover?(code)
          { outcome: :configuration_error, text: nil, raw: raw }
        else
          { outcome: :unreachable, text: nil, raw: raw }
        end
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end

      def poll_wait
        sleep(POLL_INTERVAL)
      end
    end
  end
end

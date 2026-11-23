# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # What the processing a build writes may contain: no secret values, no
    # web or email address the admin did not type themselves, no overwrite of
    # a field the page fills before processing runs, and no method call on
    # the signed-in user snapshot (a Hash, see FlowchartRuntime::CurrentUser).
    # Assistant replies don't count, so the model can't vouch for an address
    # it made up.
    class Screen
      URL = %r{https?://[^\s"'<>`{}]+}i
      EMAIL = /\b[A-Z0-9._%+-]+@[A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,}\b/i
      TRAILING = /[.,;:!?)\]]+\z/
      SECRET_FIELDS = {
        "api_call" => %w[authToken authPassword],
        "send_chat_message" => %w[signingSecret],
        "send_webhook" => %w[secretExpression]
      }.freeze
      SECRET_HEADER = /authorization|api[-_]?key|token|secret|password|cookie/i
      RECORD_WRITERS = %w[update_model set_record_fields].freeze

      # `filled` names the page record's fields set before processing runs.
      def self.for(conversation, filled: [])
        new(allowed_text: conversation.messages.where(role: "user").order(:id).pluck(:body).join("\n"), filled: filled)
      end

      def initialize(allowed_text:, filled: [])
        @allowed_text = allowed_text.to_s
        @filled = Array(filled).map(&:to_s)
      end

      def errors(normalized)
        secret_errors(normalized) +
          unknown_values(normalized).map { |value| I18n.t("ai_assistant.subsystems.screen.unknown_value", value: value) } +
          filled_errors(normalized) + user_errors(normalized)
      end

      def unknown_values(normalized)
        steps(normalized).flat_map { |step| literal_values(step) }.uniq.reject { |value| @allowed_text.include?(value) }
      end

      # The web and email addresses in +text+ the admin did not type.
      def unknown_text(text)
        addresses(text).uniq.reject { |value| @allowed_text.include?(value) }
      end

      # [[action, field]] for every secret value or credential header a step fills.
      def secrets(normalized)
        steps(normalized).flat_map do |step|
          action = step["action"].to_s
          config = step["config"].is_a?(Hash) ? step["config"] : {}
          fields = SECRET_FIELDS.fetch(action, []).select { |field| config[field].to_s.strip.present? }
          (fields + secret_headers(config["headers"])).map { |field| [action, field] }
        end
      end

      private

      def secret_errors(normalized)
        secrets(normalized).map do |action, field|
          I18n.t("ai_assistant.subsystems.screen.secret_value", step: action, field: field)
        end
      end

      def filled_errors(normalized)
        steps(normalized).flat_map do |step|
          config = step["config"].is_a?(Hash) ? step["config"] : {}
          next [] unless RECORD_WRITERS.include?(step["action"].to_s) && config["modelVariable"].to_s.in?(["", "model"])

          Array(config["assignments"]).grep(Hash).map { |row| row["key"].to_s } & @filled
        end.uniq.map { |field| I18n.t("ai_assistant.subsystems.screen.filled_field", field: field) }
      end

      def user_errors(normalized)
        variables = steps(normalized).select { |step| step["action"] == "load_current_user" }.map do |step|
          (step["config"].is_a?(Hash) && step["config"]["resultVar"].presence) || "current_user"
        end
        texts = elements(normalized).flat_map { |element| strings(element["properties"]) }
        variables.uniq.flat_map do |variable|
          calls = texts.flat_map { |text| text.scan(/ctx\[:#{Regexp.escape(variable)}\]&?\.(?!dig\b|fetch\b)([a-z_]\w*)/i).flatten }
          calls.uniq.map { |key| I18n.t("ai_assistant.subsystems.screen.user_hash", variable: variable, key: key) }
        end
      end

      def elements(normalized)
        Array(normalized.configuration&.dig("elements")).grep(Hash)
      end

      def steps(normalized)
        elements(normalized).flat_map { |element| Array(element.dig("properties", "steps")) }.grep(Hash)
      end

      def literal_values(step)
        defaults = palette_defaults(step["action"])
        strings(step["config"]).reject { |text| defaults.include?(text) }.flat_map { |text| addresses(text) }
      end

      def addresses(text) = text.scan(URL).map { |url| url.sub(TRAILING, "") } + text.scan(EMAIL)


      def secret_headers(headers)
        Array(headers).grep(Hash).filter_map do |row|
          name = row["key"].to_s
          name if name.match?(SECRET_HEADER) && row["value"].to_s.strip.present?
        end
      end

      def strings(value)
        case value
        when String then [value]
        when Hash then value.values.flat_map { |item| strings(item) }
        when Array then value.flat_map { |item| strings(item) }
        else []
        end
      end

      def palette_defaults(action)
        Array(FlowchartDefinitions::Palette.action(action)&.fetch("config_fields", nil)).filter_map do |field|
          field["default"] if field["default"].is_a?(String) && field["default"].present?
        end
      end
    end
  end
end

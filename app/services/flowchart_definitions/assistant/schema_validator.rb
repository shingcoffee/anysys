# frozen_string_literal: true

require "json_schemer"

module FlowchartDefinitions
  module Assistant
    # Validates LLM structured output against StructureSchema via json_schemer.
    class SchemaValidator
      Result = Struct.new(:errors, keyword_init: true) do
        def ok? = errors.empty?
      end

      def self.call(payload)
        new(payload).call
      end

      def initialize(payload)
        @payload = document_for(payload)
      end

      def call
        details = schemer.validate(@payload).map { |err| format_error(err) }
        Result.new(errors: details.empty? ? [] : [
          I18n.t("ai_assistant.assistant.apply_errors.flowchart_schema_invalid", details: details.join("; "))
        ])
      end

      private

      def document_for(payload)
        case payload
        when Extraction then payload.as_json
        when Hash then payload.deep_stringify_keys
        else payload
        end
      end

      def schemer
        self.class.schemer
      end

      def self.schemer
        @schemer ||= JSONSchemer.schema(StructureSchema.json)
      end

      def self.reset!
        @schemer = nil
      end

      def format_error(err)
        message = JSONSchemer::Errors.pretty(err)
        data = err["data"]
        return message unless data.is_a?(String) || data.is_a?(Numeric)

        "#{message} (#{data})"
      end
    end
  end
end

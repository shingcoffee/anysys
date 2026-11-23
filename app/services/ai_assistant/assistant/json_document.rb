# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Decodes the JSON document in a model completion. Prefers a fenced
    # ```json block (the closing fence is the delimiter, so nested objects stay
    # intact), then the whole string, then the first `{ ... }` span when the
    # model wrapped the JSON in prose.
    module JsonDocument
      def self.parse(text)
        JSON.parse(body(text.to_s.strip))
      rescue JSON::ParserError, TypeError
        nil
      end

      def self.body(stripped)
        fenced = stripped[/\A```(?:json)?\s*(.*?)\s*```/mi, 1]
        return fenced if fenced.present?
        return stripped if stripped.start_with?("{")

        stripped[/(\{.*\})/m, 1]
      end
      private_class_method :body
    end
  end
end

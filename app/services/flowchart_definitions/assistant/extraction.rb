# frozen_string_literal: true

module FlowchartDefinitions
  module Assistant
    # Parsed LLM structured output for one flowchart completion.
    class Extraction
      module Intent
        CHAT = "chat"
        CLARIFY = "clarify"
        PERSIST = "apply_flowchart"
        ALL = [CHAT, CLARIFY, PERSIST].freeze
      end

      BOOLEAN = ActiveModel::Type::Boolean.new
      private_constant :BOOLEAN

      MAX_NEEDS_SETUP = 5
      MAX_NEEDS_SETUP_LENGTH = 120

      attr_reader :intent, :reply, :flowchart, :updates_confirmed, :questions, :needs_setup, :error

      def self.parse(text)
        new(text).tap(&:decode!)
      end

      def self.boolean(value)
        BOOLEAN.cast(value) == true
      end

      def initialize(text)
        @text = text.to_s
        @flowchart = nil
        @updates_confirmed = false
        @questions = []
        @needs_setup = []
      end

      def valid?
        error.nil?
      end

      def persistable?
        valid? && intent == Intent::PERSIST && flowchart.is_a?(Hash)
      end

      def as_json(*)
        {
          "intent" => intent,
          "reply" => reply,
          "flowchart" => flowchart,
          "updates_confirmed" => updates_confirmed
        }
      end

      def decode!
        document = AiAssistant::Assistant::JsonDocument.parse(@text)
        return reject! unless document.is_a?(Hash)

        document = document.deep_stringify_keys
        @intent = document["intent"].to_s
        @reply = document["reply"]
        @flowchart = document["flowchart"]
        @flowchart = nil if @flowchart == {}
        @updates_confirmed = self.class.boolean(document["updates_confirmed"])
        @questions = AiAssistant::Assistant::Questions.sanitize(document["questions"])
        @needs_setup = sanitize_needs_setup(document["needs_setup"])

        return reject! unless Intent::ALL.include?(@intent)
        return reject! unless @reply.is_a?(String)
        @reply = @reply.strip
        return reject! if @reply.blank? && @intent != Intent::CHAT
        return reject! unless @flowchart.nil? || @flowchart.is_a?(Hash)

        self
      end

      private

      def sanitize_needs_setup(raw)
        Array(raw).grep(String).map { |item| item.squish.truncate(MAX_NEEDS_SETUP_LENGTH) }
                  .reject(&:blank?).uniq.first(MAX_NEEDS_SETUP)
      end

      def reject!
        @error = :invalid
        self
      end
    end
  end
end

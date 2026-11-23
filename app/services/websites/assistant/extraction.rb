# frozen_string_literal: true

module Websites
  module Assistant
    # Parsed `apply_website` document from one assistant completion. The JSON
    # keys are the wire contract; this object is the in-process shape that
    # SchemaValidator and Processor consume.
    class Extraction
      INTENT = "apply_website"
      MAX_PAGES = 5
      MAX_SECTIONS = 12

      attr_reader :intent, :reply, :pages, :error

      def self.parse(text)
        new(text).tap(&:decode!)
      end

      # Routing check for TurnProcessor: runs on every completion, so the
      # substring test keeps entity and chat replies away from JSON.parse.
      def self.website_document?(text)
        return false unless text.is_a?(String) && text.include?(INTENT)

        parse(text).intent == INTENT
      end

      def initialize(text)
        @text = text.to_s
        @pages = []
      end

      def valid?
        error.nil?
      end

      def persistable?
        valid? && pages.any?
      end

      def as_json(*)
        { "intent" => intent, "reply" => reply, "pages" => pages }
      end

      def decode!
        document = AiAssistant::Assistant::JsonDocument.parse(@text)
        return reject! unless document.is_a?(Hash)

        document = document.deep_stringify_keys
        @intent = document["intent"].to_s
        @reply = document["reply"]
        @pages = document.key?("pages") ? document["pages"] : []

        return reject! unless @intent == INTENT
        return reject! unless @reply.is_a?(String) && @reply.strip.present?
        return reject! unless @pages.is_a?(Array) && @pages.all? { |page| page.is_a?(Hash) }

        @reply = @reply.strip
        self
      end

      private

      def reject!
        @error = :invalid
        self
      end
    end
  end
end

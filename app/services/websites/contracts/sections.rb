# frozen_string_literal: true

require "reform/form"

module Websites
  module Contracts
    class Sections < Reform::Form
      Input = Struct.new(:sections)
      SECTION_KEYS = %w[id type props].freeze

      property :sections
      validate :section_list_is_valid

      def initialize(model, allow_empty: false)
        @allow_empty = allow_empty
        super(model)
      end

      private

      def section_list_is_valid
        unless sections.is_a?(Array) && (@allow_empty || sections.any?)
          return invalid_sections
        end

        ids = []
        sections.each do |raw|
          unless raw.is_a?(Hash)
            invalid_sections
            next
          end

          item = raw.deep_stringify_keys
          invalid_sections if (item.keys - SECTION_KEYS).any?
          if item.key?("id")
            invalid_sections unless item["id"].is_a?(String) && item["id"].present? && !ids.include?(item["id"])
            ids << item["id"]
          end
          unless item["type"].is_a?(String) && item["props"].is_a?(Hash)
            invalid_sections
            next
          end

          form = Section.new(Section::Input.new(item["id"], item["type"], item["props"]))
          unless form.validate(item.slice("id", "type", "props"))
            form.errors.full_messages.each { |message| errors.add(:sections, message) }
          end
          validate_media(item["props"])
        end
      end

      def validate_media(props)
        props.each do |key, value|
          if SectionKit::IMAGE_KEYS.include?(key) && value.present?
            invalid_sections unless value.is_a?(String) && Href.media?(value)
          elsif value.is_a?(Hash)
            validate_media(value)
          elsif value.is_a?(Array)
            value.grep(Hash).each { |item| validate_media(item) }
          end
        end
      end

      def invalid_sections
        errors.add(:sections, I18n.t("website.errors.invalid_sections"))
      end
    end
  end
end

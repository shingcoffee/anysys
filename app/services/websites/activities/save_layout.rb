# frozen_string_literal: true

module Websites
  module Activities
    class SaveLayout
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(layout:, params:)
        attrs = sanitize(params)
        if attrs[:sections] == :invalid
          layout.errors.add(:sections, I18n.t("website.errors.invalid_sections"))
          return Result.new(success?: false, model: layout, errors: layout.errors.full_messages)
        end

        layout.key = attrs[:key] if attrs.key?(:key) && layout.new_record?
        layout.assign_attributes(attrs.except(:key))
        contract = Contracts::Layout.new(layout)
        unless contract.validate({})
          contract.errors.each { |error| layout.errors.add(error.attribute, error.message) }
          return Result.new(success?: false, model: layout, errors: layout.errors.full_messages)
        end
        layout.sections = Websites::Skeletons.decorate_sections(layout.sections)
        if layout.save
          Websites::Catalog.reset_sync_flag!
          Result.new(success?: true, model: layout, errors: [])
        else
          Result.new(success?: false, model: layout, errors: layout.errors.full_messages)
        end
      end

      def self.sanitize(params)
        h = params.to_h.deep_symbolize_keys
        attrs = h.slice(:key, :name, :description, :position, :archived, :sections, :sections_json, :theme_key)
        attrs[:theme_key] = attrs[:theme_key].to_s.presence if attrs.key?(:theme_key)
        json = attrs.delete(:sections_json)
        attrs[:sections] = json if json.present? && attrs[:sections].blank?
        if attrs.key?(:sections)
          parsed = parse_sections(attrs[:sections])
          attrs[:sections] = parsed
        end
        attrs[:archived] = ActiveModel::Type::Boolean.new.cast(attrs[:archived]) if attrs.key?(:archived)
        attrs
      end

      def self.parse_sections(raw)
        return raw if raw.is_a?(Array)
        return [] if raw.blank?
        return :invalid unless raw.is_a?(String)

        parsed = JSON.parse(raw)
        parsed.is_a?(Array) ? parsed : :invalid
      rescue JSON::ParserError
        :invalid
      end
      private_class_method :parse_sections
    end
  end
end

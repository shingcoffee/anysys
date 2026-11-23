# frozen_string_literal: true

module Admin
  module Entities
    class FiltersBuilder
      FILTER_TYPES = %w[select radio checkbox].freeze

      def self.call(entity:)
        new(entity: entity).call
      end

      def initialize(entity:)
        @entity = entity
      end

      def call
        @entity.input_fields.filter_map { |field| build_filter(field) }
      end

      private

      # Filters are built only for enum-typed (selection) fields that actually
      # enumerate options — a select/radio/checkbox with no configured options
      # yields an empty, useless dropdown, so it is skipped.
      def build_filter(field)
        html_type = field["html_type"].to_s
        return nil unless FILTER_TYPES.include?(html_type)

        slug = field["name_slug"].to_s
        return nil if slug.blank?

        options = options_for(field, html_type)
        return nil if options.empty?

        {
          key: slug.to_sym,
          label: field["display_label"].presence || field["name"].presence || slug,
          options: options,
          scope: scope_for(html_type, slug)
        }
      end

      def scope_for(html_type, slug)
        if html_type == "checkbox"
          ->(rel, value) {
            if value.to_s == "true"
              rel.where(
                "CAST(json_extract(entity_entries.data, '$.#{slug}') AS TEXT) IN ('1', 'true')"
              )
            else
              rel.where(
                "CAST(json_extract(entity_entries.data, '$.#{slug}') AS TEXT) IN ('0', 'false')"
              )
            end
          }
        else
          ->(rel, value) {
            rel.where("json_extract(entity_entries.data, '$.#{slug}') = ?", value)
          }
        end
      end

      def options_for(field, html_type)
        if html_type == "checkbox"
          [[I18n.t("common.labels.yes"), "true"], [I18n.t("common.labels.no"), "false"]]
        else
          Array(field.dig("config", "options")).filter_map do |opt|
            next if opt["value"].to_s.blank?

            [(opt["label"].presence || opt["value"]).to_s, opt["value"].to_s]
          end
        end
      end
    end
  end
end

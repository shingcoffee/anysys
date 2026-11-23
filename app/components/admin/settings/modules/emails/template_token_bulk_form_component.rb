# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Emails
        class TemplateTokenBulkFormComponent < ApplicationComponent
          def initialize(token:, entities:, entity_attributes:, existing_slugs:, submitted_fields:, url:, cancel_path:)
            @token, @entities, @entity_attributes = token, entities, entity_attributes
            @existing_slugs, @submitted_fields = existing_slugs, submitted_fields
            @url, @cancel_path = url, cancel_path
          end

          attr_reader :token, :entities, :url, :cancel_path

          def entity_options
            entities.each_with_index.map do |entity, index|
              [entity.display_label.presence || t("settings_modules.email.unnamed_record", number: index + 1), entity.id]
            end
          end

          def fields_for(entity)
            fields = @submitted_fields.respond_to?(:values) ? @submitted_fields.values : Array(@submitted_fields)
            fields = fields.map { |field| field.to_h.with_indifferent_access }
            Array(@entity_attributes[entity.id.to_s]).each_with_index.filter_map do |(label, slug), index|
              next if @existing_slugs.fetch(entity.id, []).include?(slug)

              name = if label.present? && label != slug
                label
              else
                t("common.labels.#{slug}", default: t("settings_modules.email.unnamed_field", number: index + 1))
              end
              submitted = fields.find { |field| field[:attribute_slug] == slug } if token.entity_id.to_s == entity.id.to_s
              [slug, name, submitted]
            end
          end
        end
      end
    end
  end
end

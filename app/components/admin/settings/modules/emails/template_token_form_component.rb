# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Emails
        class TemplateTokenFormComponent < ViewComponent::Base
          def initialize(token:, entities:, entity_attributes:, existing_slugs:, url:, method: :patch, cancel_path:, submitted_values: nil)
            @token = token
            @entities = entities
            @entity_attributes = entity_attributes
            @existing_slugs = existing_slugs
            @url = url
            @method = method
            @cancel_path = cancel_path
            @submitted_values = (submitted_values || {}).stringify_keys
          end

          private

          attr_reader :token, :entities, :url, :method, :cancel_path

          def form_value(name)
            @submitted_values.key?(name.to_s) ? @submitted_values[name.to_s] : token.public_send(name)
          end

          def entity_options
            options = entities.each_with_index.map do |entity, index|
              [entity.display_label.presence || I18n.t("settings_modules.email.unnamed_record", number: index + 1), entity.id]
            end
            selected = form_value(:entity_id)
            options << [selected.to_s, selected] if selected.present? && options.none? { |_, id| id.to_s == selected.to_s }
            options
          end

          def entity_attributes
            @readable_attributes ||= @entity_attributes.each_with_object({}) do |(entity_id, options), available|
              available[entity_id] = Array(options).each_with_index.filter_map do |(label, slug), index|
                next if @existing_slugs.fetch(entity_id.to_i, []).include?(slug) &&
                        !(entity_id == token.entity_id.to_s && slug == token.attribute_slug) &&
                        !(entity_id == form_value(:entity_id).to_s && slug == form_value(:attribute_slug))

                name = if label.present? && label != slug
                  label
                else
                  I18n.t("common.labels.#{slug}", default: I18n.t("settings_modules.email.unnamed_field", number: index + 1))
                end
                [name, slug]
              end
            end.tap do |available|
              selected = form_value(:attribute_slug)
              if selected.present?
                options = available[form_value(:entity_id).to_s] ||= []
                options << [selected, selected] if options.none? { |_, slug| slug == selected }
              end
            end
          end

          def selected_attribute_options
            (entity_attributes[form_value(:entity_id).to_s] || []).dup
          end
        end
      end
    end
  end
end

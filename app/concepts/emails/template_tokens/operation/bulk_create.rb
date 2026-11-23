# frozen_string_literal: true

module Emails
  module TemplateTokens
    module Operation
      class BulkCreate
        Result = Struct.new(:success?, :model, keyword_init: true) do
          def [](key) = send(key)
        end

        def self.call(customer:, params:)
          new(customer, params).call
        end

        def initialize(customer, params)
          @customer, @params = customer, params.to_h.with_indifferent_access
        end

        def call
          model = Emails::TemplateToken.new(customer_id: @customer.id, source_type: Emails::TemplateToken::SOURCE_ENTITY, entity_id: @params[:entity_id])
          entity = Entity.where(customer_id: @customer.id).or(Entity.shared).active.find_by(id: @params[:entity_id])
          return failure(model, "choose_valid_record") unless entity

          fields = normalized_fields
          return failure(model, "invalid_selection") unless fields

          selected = fields.select { |field| field[:selected] == "1" }
          return failure(model, "select_at_least_one") if selected.empty?

          slugs = selected.map { |field| field[:attribute_slug] }
          available = Array(entity.property_schema_json).filter_map { |attribute| attribute["name_slug"].presence || attribute[:name_slug].presence }
          return failure(model, "invalid_selection") if slugs.uniq.size != slugs.size || (slugs - available).any?
          return failure(model, "already_added") if Emails::TemplateToken.custom_for(@customer.id).where(entity_id: entity.id, attribute_slug: slugs).exists?

          tokens = selected.map do |field|
            Emails::TemplateToken.new(customer_id: @customer.id, source_type: Emails::TemplateToken::SOURCE_ENTITY,
                                      entity: entity, attribute_slug: field[:attribute_slug], label: field[:label])
          end
          tokens.each { |token| model.errors.merge!(token.errors) unless token.valid? }
          return Result.new(success?: false, model: model) if model.errors.any?

          Emails::TemplateToken.transaction { tokens.each(&:save!) }
          Result.new(success?: true, model: tokens.first)
        rescue ActiveRecord::RecordNotUnique
          failure(model, "already_added")
        rescue ActiveRecord::RecordInvalid => e
          model.errors.merge!(e.record.errors)
          Result.new(success?: false, model: model)
        end

        private

        def normalized_fields
          input = @params[:fields]
          return [] if input.nil?

          fields = case input
                   when Array then input
                   when Hash then input.values
                   else return nil
                   end
          return nil unless fields.all? { |field| field.is_a?(Hash) }

          fields.map do |field|
            field = field.with_indifferent_access
            return nil unless %i[selected attribute_slug label].all? { |key| field[key].nil? || field[key].is_a?(String) }

            field
          end
        end

        def failure(model, key)
          model.errors.add(:base, I18n.t("settings_modules.email.bulk_errors.#{key}"))
          Result.new(success?: false, model: model)
        end
      end
    end
  end
end

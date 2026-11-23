# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class EntityAssociations
      class << self
        def options(customer:, query: nil, limit: 50, entity_id: nil, **_filters)
          entity = bound_entity(customer, entity_id)
          return [] unless entity

          rows = entity.associations_list.filter_map do |association|
            value = (association["target_entity_id"] || association[:target_entity_id]).to_s
            next if value.blank?

            label = association["target_entity_name"] || association["associated_entity_name"] || value
            { value: value, label: label }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, entity_id: nil, **_filters)
          return false if value.blank?

          options(customer: customer, entity_id: entity_id, limit: 10_000).any? do |row|
            row[:value].to_s == value.to_s
          end
        end

        def bound_entity(customer, entity_id)
          return if customer.nil? || entity_id.blank?

          Entities.scope(customer).find_by(id: entity_id)
        end
      end
    end
  end
end

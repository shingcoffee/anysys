# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class Entities
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          rows = scope(customer).order(:name).map do |entity|
            { value: entity.id, label: entity.display_label.presence || entity.name }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          return false unless customer && value.present?

          scope(customer).exists?(id: value)
        end

        def scope(customer)
          ReferenceSources.accessible(Entity.visible, customer)
        end
      end
    end
  end
end

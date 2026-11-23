# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class Flowcharts
      class << self
        def options(customer:, query: nil, limit: 50, exclude_id: nil, **_filters)
          rows = scope(customer, exclude_id: exclude_id).by_name.map do |flowchart|
            { value: flowchart.id, label: flowchart.name }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, exclude_id: nil, **_filters)
          return false unless customer && value.present?

          scope(customer, exclude_id: exclude_id).exists?(id: value)
        end

        def scope(customer, exclude_id: nil)
          relation = ReferenceSources.accessible(::Flowchart.launched, customer)
          exclude_id.present? ? relation.except_id(exclude_id) : relation
        end
      end
    end
  end
end

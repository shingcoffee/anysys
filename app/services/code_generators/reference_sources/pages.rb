# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class Pages
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          rows = scope(customer).by_name.map do |page|
            { value: page.id, label: page.name }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          return false unless customer && value.present?

          scope(customer).exists?(id: value)
        end

        def scope(customer)
          ReferenceSources.accessible(Page.launched, customer)
        end
      end
    end
  end
end

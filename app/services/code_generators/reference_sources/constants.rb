# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class Constants
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          rows = ReferenceSources.accessible(::Constant.ordered, customer).map do |constant|
            { value: constant.id, label: constant.name }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          return false unless customer && value.present?

          ReferenceSources.accessible(::Constant.all, customer).exists?(id: value)
        end
      end
    end
  end
end

# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class EmailTemplates
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          return [] unless customer

          rows = Emails::Template.for_customer(customer.id).active.order(:name).map do |template|
            { value: template.id, label: template.name }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          return false unless customer && value.present?

          Emails::Template.for_customer(customer.id).exists?(id: value)
        end
      end
    end
  end
end

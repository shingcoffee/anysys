# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class SmsTemplates
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          rows = Sms::Template.active.order(:key).map do |template|
            { value: template.key, label: template.description.presence || template.key }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          return false if value.blank?

          Sms::Template.exists?(key: value.to_s)
        end
      end
    end
  end
end

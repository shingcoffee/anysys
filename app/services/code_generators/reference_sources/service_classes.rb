# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class ServiceClasses
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          rows = FlowchartRuntime::Invocable::SERVICE_ALLOWLIST.map do |name|
            { value: name, label: name }
          end
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          FlowchartRuntime::Invocable.allowlisted_service?(value.to_s)
        end
      end
    end
  end
end

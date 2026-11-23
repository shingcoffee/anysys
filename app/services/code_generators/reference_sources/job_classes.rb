# frozen_string_literal: true

module CodeGenerators
  module ReferenceSources
    class JobClasses
      class << self
        def options(customer:, query: nil, limit: 50, **_filters)
          rows = names.map { |name| { value: name, label: name } }
          ReferenceSources.filter(rows, query: query, limit: limit)
        end

        def valid?(value, customer:, **_filters)
          name = value.to_s
          return false unless FlowchartRuntime::Invocable.valid_const_name?(name)

          klass = name.safe_constantize
          klass.is_a?(Class) && klass < ApplicationJob
        end

        def names
          Pathname.glob(Rails.root.join("app/jobs/**/*.rb")).filter_map do |path|
            name = path.relative_path_from(Rails.root.join("app/jobs")).to_s.delete_suffix(".rb").camelize
            next unless FlowchartRuntime::Invocable.valid_const_name?(name)

            klass = name.safe_constantize
            name if klass.is_a?(Class) && klass < ApplicationJob
          end.sort
        end
      end
    end
  end
end

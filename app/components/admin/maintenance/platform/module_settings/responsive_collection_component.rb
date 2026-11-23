# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class ResponsiveCollectionComponent < ApplicationComponent
          def initialize(label:, columns:, desktop_grid_class: nil)
            @label = label
            @columns = Array(columns).map { |column| normalize_column(column) }
            @desktop_grid_class = desktop_grid_class.presence || "lg:grid-cols-#{@columns.size}"
          end

          attr_reader :label, :columns, :desktop_grid_class

          private

          def normalize_column(column)
            value = column.is_a?(Hash) ? column.symbolize_keys : { label: column }
            value.merge(sort_direction: value[:sort_direction]&.to_sym)
          end
        end
      end
    end
  end
end

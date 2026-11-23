# frozen_string_literal: true

# Columns of whatever model an entity extends, and the entry association that
# points at a row of that model. A model may hide columns with SENSITIVE_COLUMNS
# or .sensitive_columns. Structural columns stay on the entry itself.
module ExtendedModels
  module Attributes
    STRUCTURAL = %w[id customer_id created_at updated_at].freeze

    module_function

    # Non-sensitive columns. With a customer, only attributes the platform owner
    # has checked are returned.
    def allowed(class_name, customer_id: nil)
      klass = resolve(class_name)
      return [] unless klass

      names = klass.column_names - sensitive(klass)
      return names - STRUCTURAL if customer_id.blank?

      names & ExtendableModelRegistry.selected_attributes(customer_id, class_name)
    end

    # belongs_to on EntityEntry whose target is the extended model, if one exists.
    def link(class_name)
      klass = resolve(class_name)
      return unless klass

      EntityEntry.reflect_on_all_associations(:belongs_to).find do |reflection|
        reflection.class_name == klass.name
      end
    end

    def resolve(class_name)
      klass = class_name.to_s.safe_constantize
      klass if klass.is_a?(Class) && klass < ApplicationRecord
    end

    def sensitive(klass)
      names = if klass.respond_to?(:sensitive_columns)
        klass.sensitive_columns
      elsif klass.const_defined?(:SENSITIVE_COLUMNS)
        klass::SENSITIVE_COLUMNS
      else
        []
      end
      Array(names).map(&:to_s)
    end
  end
end

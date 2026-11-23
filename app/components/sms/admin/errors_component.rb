# frozen_string_literal: true

module Sms
  module Admin
    class ErrorsComponent < BaseComponent
      attr_reader :errors, :root

      def initialize(errors:, root: nil)
        @errors, @root = errors || {}, root
      end

      def render? = errors.any?

      def target(key)
        field = { custom_attributes: :custom_attributes_json, segment_rules: :segment_rules_json,
                  variable_map: :variable_map_json, attribute_map: :attribute_map_json,
                  scheduled_at: :scheduled_local }.fetch(key.to_sym, key)
        "##{root}_#{field}" if root && key.to_sym != :base
      end
    end
  end
end

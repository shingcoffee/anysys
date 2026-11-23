# frozen_string_literal: true

module Billing
  module Admin
    class FormErrorsComponent < ApplicationComponent
      def initialize(errors:, scope:, label_prefix:)
        @errors, @scope, @label_prefix = errors, scope, label_prefix
      end

      attr_reader :errors, :scope, :label_prefix

      def render? = errors.present? && errors.any?
    end
  end
end

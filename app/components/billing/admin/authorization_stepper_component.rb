# frozen_string_literal: true

module Billing
  module Admin
    # Three-step authorization progress for the payment-method mandate flow.
    class AuthorizationStepperComponent < ApplicationComponent
      STEPS = %i[select_provider authorize_provider ready].freeze

      attr_reader :payment_method, :authorization_kind

      def initialize(payment_method:, authorization_kind: nil)
        @payment_method = payment_method
        @authorization_kind = authorization_kind
      end

      def steps
        STEPS.map.with_index(1) do |key, index|
          { key: key, index: index, label: t("settings_billing.payment_methods.steps.#{key}"), state: state_for(key) }
        end
      end

      def marker_class(state)
        case state
        when :complete then "bg-success-subtle text-success"
        when :current then "bg-accent-subtle text-accent-text ring-2 ring-accent"
        else "bg-surface-active text-text-muted"
        end
      end

      def highlighted?(step)
        step[:state] == :current || (step[:key] == :ready && step[:state] == :complete)
      end

      private

      def state_for(key)
        case key
        when :select_provider
          payment_method.present? ? :complete : :current
        when :authorize_provider
          return :complete if payment_method&.status == "active"
          return :current if payment_method.present?

          :upcoming
        when :ready
          payment_method&.status == "active" ? :complete : :upcoming
        end
      end
    end
  end
end

# frozen_string_literal: true

module Payments
  module Admin
    # Pure presentational badge for a gateway's status.
    # state ∈ :active | :needs_setup | :disabled
    # Wraps BadgeComponent with the correct variant and label.
    class StatusBadgeComponent < ApplicationComponent
      # Badge variant per state. Labels are resolved at render time via I18n
      # (see #label) so they bind to the request locale, not class-load time.
      VARIANTS = {
        active:      :success,
        needs_setup: :warning,
        disabled:    :default
      }.freeze

      attr_reader :state

      def initialize(state:)
        @state = state.to_sym
      end

      def badge_variant
        VARIANTS.fetch(resolved_state)
      end

      def label
        I18n.t("comp_payments.status_badge.states.#{resolved_state}")
      end

      private

      # Unknown states fall back to :disabled, matching the prior STATES.fetch default.
      def resolved_state
        VARIANTS.key?(state) ? state : :disabled
      end
    end
  end
end

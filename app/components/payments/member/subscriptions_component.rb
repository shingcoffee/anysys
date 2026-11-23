# frozen_string_literal: true

module Payments
  module Member
    # Member self-service: lists the member's own recurring subscription plans.
    #
    # All URLs are passed as constructor props — no route helpers are called
    # inside this component, so specs can pass plain strings.
    #
    # Props:
    #   subscriptions:  Array<Payments::Subscription>
    #   cancel_url_for: Proc/Method — called with (subscription) → String cancel URL
    class SubscriptionsComponent < ApplicationComponent
      include ::Member::UsesSiteChrome
      STATUS_BADGE = {
        "pending_sign" => "badge-warning",
        "active"       => "badge-success",
        "paused"       => "badge-warning",
        "cancelled"    => "badge-default",
        "expired"      => "badge-default"
      }.freeze

      attr_reader :subscriptions, :cancel_url_for, :publishable_key

      # recovery_for: Proc/Method — called with (subscription) → nil, or
      #   { client_secret: } when the sub is paused awaiting on-session SCA.
      # publishable_key: Stripe publishable key for the SCA-recovery widget.
      def initialize(subscriptions:, cancel_url_for:, recovery_for: ->(_s) { nil }, publishable_key: nil)
        @subscriptions   = subscriptions
        @cancel_url_for  = cancel_url_for
        @recovery_for    = recovery_for
        @publishable_key = publishable_key
      end

      def any_subscriptions?
        subscriptions.any?
      end

      def cycle_label(sub)
        cycle = sub.cycle.to_s
        if Payments::Subscription::CYCLES.include?(cycle)
          I18n.t("comp_payments.member.subscriptions.cycles.#{cycle}")
        else
          cycle
        end
      end

      def status_badge_class(sub)
        STATUS_BADGE.fetch(sub.status.to_s, "badge-default")
      end

      def status_label(sub)
        key = sub.status.to_s
        if Payments::Subscription::STATUSES.include?(key)
          I18n.t("comp_payments.member.subscriptions.statuses.#{key}")
        else
          key
        end
      end

      def cancel_url(sub)
        cancel_url_for.call(sub)
      end

      def cancellable?(sub)
        !%w[cancelled expired].include?(sub.status.to_s)
      end

      # Returns the on-session SCA recovery context for a paused subscription
      # ({ client_secret: }), or nil when there is nothing to recover.
      def recovery(sub)
        @recovery_for.call(sub)
      end

      # Format amount as decimal with currency code, e.g. "29.99 USD"
      def amount_label(sub)
        amount = Payments::Money.new(sub.amount, sub.currency).decimal_string
        "#{amount} #{sub.currency.to_s.upcase}"
      end

      def next_charge_label(sub)
        return I18n.t("common.labels.em_dash") if sub.next_charge_at.blank?

        I18n.l(sub.next_charge_at.to_date, format: :long)
      end
    end
  end
end

# frozen_string_literal: true

module Billing
  module Activities
    class CancelSubscription
      def self.call(subscription:, immediately: false)
        Result.transaction(subscription) do
          next Result.new(status: :unchanged, subscription: subscription, reason: :subscription_ended) unless Subscription::LIVE_STATUSES.include?(subscription.status)
          change = subscription.pending_plan_change
          if change
            cancelled = CancelPlanChange.call(subscription: subscription, plan_change: change)
            next cancelled if cancelled.status == :conflict && !immediately
            change.update!(status: "cancelled", cancelled_at: Time.current) if cancelled.status == :conflict && immediately
          end
          if immediately
            subscription.update!(status: "cancelled", ended_at: Time.current, cancelled_at: Time.current, cancel_at_period_end: false)
          elsif subscription.cancel_at_period_end?
            next Result.new(status: :unchanged, subscription: subscription)
          else
            subscription.update!(cancel_at_period_end: true)
          end
          # Genuine debt is retained. B owns durable, deduplicated notice intent.
          Notifier.subscription_cancelled(subscription)
          Result.new(status: immediately ? :cancelled : :scheduled, subscription: subscription)
        end
      end
    end
  end
end

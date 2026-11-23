# frozen_string_literal: true

module Billing
  module Activities
    class ResumeSubscription
      def self.call(subscription:)
        Result.transaction(subscription) do
          boundary = PlanChangePolicy.period_boundary(subscription)
          unless %w[active trialing past_due].include?(subscription.status) && boundary && Time.current < boundary
            next Result.invalid(:resume_blocked, subscription: subscription)
          end
          next Result.new(status: :unchanged, subscription: subscription) unless subscription.cancel_at_period_end?

          subscription.update!(cancel_at_period_end: false)
          Result.new(status: :resumed, subscription: subscription)
        end
      end
    end
  end
end

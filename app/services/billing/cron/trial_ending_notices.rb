# frozen_string_literal: true

module Billing
  module Cron
    class TrialEndingNotices
      def self.perform(at: Time.current)
        days = (Settings.find_by(singleton_guard: 0)&.trial_ending_notice_days || 3).days
        Billing::Subscription.unscoped_by_tenant.where(status: "trialing", trial_end: at..(at + days)).find_each do |subscription|
          Current.set(customer: subscription.customer) { Notifier.trial_ending(subscription) }
        rescue StandardError => error
          Rails.logger.error("[billing.trial_notice] subscription=#{subscription.id} #{error.class}: #{error.message}")
        end
      end
    end
  end
end

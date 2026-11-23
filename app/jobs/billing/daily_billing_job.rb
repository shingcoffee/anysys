# frozen_string_literal: true

module Billing
  # Orchestrates the four billing crons in sequence once per day.
  # Registered in config/recurring.yml as `billing_daily`.
  #
  # Each cron is wrapped in its own rescue block so that one failing cron
  # does not prevent the remaining ones from running.
  class DailyBillingJob < ApplicationJob
    queue_as :default

    CRONS = [
      Billing::Cron::ReconcileCollections,
      Billing::Cron::RenewSubscriptions,
      Billing::Cron::CollectDueInvoices,
      Billing::Cron::Dunning,
      Billing::Cron::TrialEndingNotices,
      Billing::Cron::RevokePaymentMethods,
      Billing::Cron::DispatchNotices
    ].freeze

    def perform
      CRONS.each do |cron|
        Current.set(customer: nil) { cron.perform }
      rescue StandardError => e
        Rails.logger.error("[billing.daily_billing_job] #{cron.name} failed: #{e.class}: #{e.message}")
      end
    end
  end
end

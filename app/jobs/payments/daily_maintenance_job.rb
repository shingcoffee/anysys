# frozen_string_literal: true

module Payments
  # Orchestrates the daily payment crons in sequence (config/recurring.yml:
  # payments_daily_maintenance). Each cron is isolated in its own rescue so
  # one failure does not starve the rest — mirrors Billing::DailyBillingJob.
  class DailyMaintenanceJob < ApplicationJob
    queue_as :default

    CRONS = [
      Payments::Cron::DownloadBills,
      Payments::Cron::ReapStalePaymentMethods,
      Payments::Cron::PruneWebhookEvents
    ].freeze

    def perform
      CRONS.each do |cron|
        cron.perform
      rescue StandardError => e
        Rails.logger.error("[payments.daily_maintenance_job] #{cron.name} failed: #{e.class}: #{e.message}")
      end
    end
  end
end

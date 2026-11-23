# frozen_string_literal: true

module Billing
  class CollectionMaintenanceJob < ApplicationJob
    queue_as :default
    CRONS = [Cron::ReconcileCollections, Cron::Dunning, Cron::RevokePaymentMethods, Cron::DispatchNotices].freeze

    def perform
      CRONS.each do |cron|
        Current.set(customer: nil) { cron.perform }
      rescue StandardError => error
        Rails.logger.error("[billing.maintenance] #{cron.name} #{error.class}: #{error.message}")
      end
    end
  end
end

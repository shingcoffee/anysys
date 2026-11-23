# frozen_string_literal: true

module Payments
  # Hourly recurring entry point (config/recurring.yml: payments_charge_due_subscriptions).
  class ChargeDueSubscriptionsJob < ApplicationJob
    queue_as :default

    def perform
      Payments::Cron::ChargeDueSubscriptions.perform
    end
  end
end

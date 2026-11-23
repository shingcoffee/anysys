# frozen_string_literal: true

module Payments
  # Hourly recurring entry point (config/recurring.yml: payments_redrive_webhook_events).
  # Runs far more often than the daily maintenance job because recovering a
  # stranded webhook event is time-sensitive (a captured payment sits
  # unmarked-paid until this reaper re-drives it).
  class RedriveWebhookEventsJob < ApplicationJob
    queue_as :default

    def perform
      Payments::Cron::RedriveWebhookEvents.perform
    end
  end
end

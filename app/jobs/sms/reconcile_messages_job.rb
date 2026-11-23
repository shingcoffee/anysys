# frozen_string_literal: true

module Sms
  # Thin wrapper over Sms::Cron::ReconcileMessages, scheduled from
  # config/recurring.yml. Kept minimal so the logic stays testable in the Cron
  # service.
  class ReconcileMessagesJob < ApplicationJob
    queue_as :default

    def perform
      Sms::Cron::ReconcileMessages.call
    end
  end
end

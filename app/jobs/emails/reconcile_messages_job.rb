# frozen_string_literal: true

module Emails
  # Durable queued-ledger recovery, scheduled from
  # config/recurring.yml.
  class ReconcileMessagesJob < ApplicationJob
    queue_as :default

    def perform
      Emails::Cron::RecoverMessages.call
    end
  end
end

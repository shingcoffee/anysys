# frozen_string_literal: true

module Payments
  module Cron
    # Retention sweep for the webhook idempotency ledger. PSP redelivery
    # windows are measured in days, so rows older than RETENTION serve no
    # dedup purpose and only accumulate (payloads embed full PSP bodies).
    class PruneWebhookEvents
      RETENTION = 90.days

      def self.perform(now: Time.current)
        Payments::WebhookEvent.where(created_at: ...(now - RETENTION))
                              .in_batches.delete_all
      end
    end
  end
end

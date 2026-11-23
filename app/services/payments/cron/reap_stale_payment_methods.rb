# frozen_string_literal: true

module Payments
  module Cron
    # Sweeps abandoned card-vault placeholder rows. VaultCard inserts a row with a
    # "pending:" token that the setup_intent.succeeded webhook later backfills with
    # the real PSP token. If the buyer abandons the flow (or the webhook never
    # lands), the row would otherwise linger as an unusable, unconfirmed card
    # forever. Rows still pending after STALE_AFTER are soft-removed.
    class ReapStalePaymentMethods
      STALE_AFTER = 24.hours

      def self.perform(now: Time.current)
        Payments::PaymentMethod.unscoped_by_tenant
                               .active
                               .pending
                               .where(created_at: ..(now - STALE_AFTER))
                               .find_each { |pm| pm.update!(status: "removed") }
      end
    end
  end
end

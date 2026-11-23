# frozen_string_literal: true

module Sms
  module Cron
    class RecoverMessages
      def self.call(now: Time.current)
        ReceiptInbox.reconcile
        Message.where(status: "queued")
               .delivery_due(now)
               .where("delivery_claim_token IS NULL OR delivery_claimed_at <= ?", now - DeliveryDispatch::CLAIM_TTL)
               .find_each(batch_size: 100) do |message|
          token = message.delivery_claim_token || :unclaimed
          if message.dispatch_started_at
            # Even expiry/disablement cannot prove that an attempted SMS wasn't
            # accepted. Quarantine it as unknown; never enqueue another send.
            # Retain the sole attempt's token so a genuinely late response can
            # still record its vendor ID. Unknown rows are never claimable.
            message.mark_unknown!(raw: {}, claim_token: token, retain_claim: true)
          elsif DeliveryDispatch.apply_block(message, token, now: now)
            next
          else
            DeliveryHandoff.call(message, now: now)
          end
        rescue StandardError => error
          Rails.logger.warn("[sms.recovery] message=#{message.id} #{error.class}: #{error.message}")
        end
      end
    end
  end
end

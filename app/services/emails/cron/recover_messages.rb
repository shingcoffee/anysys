# frozen_string_literal: true

module Emails
  module Cron
    class RecoverMessages
      def self.call(now: Time.current)
        ReceiptInbox.reconcile
        Message.where(status: "queued")
               .where("delivery_due_at IS NULL OR delivery_due_at <= ?", now)
               .where("delivery_claim_token IS NULL OR delivery_claimed_at <= ?", now - DeliveryDispatch::CLAIM_TTL)
               .find_each do |message|
          next unless FeatureModules::Module.enabled?(key: "email", customer_id: message.customer_id)

          if DeliveryDispatch.blocked?(message)
            message.mark_suppressed!(claim_token: message.delivery_claim_token || :unclaimed)
          elsif message.delivery_attempts >= DeliveryDispatch::MAX_ATTEMPTS
            message.mark_failed!(code: "UNDELIVERED", message: I18n.t("admin_modules.emails.send_activities.dead_letter.stuck_reason"),
                                 claim_token: message.delivery_claim_token || :unclaimed)
          else
            DeliveryHandoff.call(message, now: now)
          end
        rescue StandardError => error
          Rails.logger.warn("[emails.recovery] message=#{message.id} #{error.class}: #{error.message}")
        end
      end
    end
  end
end
